## How a docker's stored rectangle is read back into this run: scaled from the
## file's units, floored at what the docker's content needs, kept inside its host
## and on a screen that is there, and refused when no working session could have
## written it.
##
## Coordinates are stored normalised to 1x so a layout survives moving between
## displays, and are multiplied back by the window's scale on load.
##
## Its own class rather than a part of `DockerLayoutStore`, because the store
## decides when an entry is read and what it is applied to, and this decides
## what an entry read out of a file may be. It holds no state, since every rule
## here is a question asked of a window and a file, and the variant sizes ask
## the floor below as the store does.
class_name SaDockerStoredEntry
extends RefCounted


## Scaled geometry for one section, clamped to the minimum size and checked
## against the screens actually present, since a layout saved on a second
## monitor must not place a docker where it cannot be reached.
static func scaled(section: String, win: Window, cfg: ConfigFile, usable_rect: Rect2i) -> Dictionary:
    var scale_factor := SaUI.window_scale(win)

    var pos: Vector2i = cfg.get_value(section, "position", win.position)
    var sz: Vector2i = cfg.get_value(section, "size", win.size)
    if pos != Vector2i():
        pos = Vector2i(Vector2(pos) * scale_factor)
    if sz != Vector2i():
        sz = Vector2i(Vector2(sz) * scale_factor)

    # A stored size below the docker's own minimum is not a small preference, it
    # is a corrupt entry: the minimum is the floor for manual resizing, so
    # nothing legitimate can be written below it. Clamping such a value would
    # produce a minimum-sized docker (a 15x100 toolbox), which looks like a
    # layout bug rather than the bad file it is. Reject the whole section
    # instead, so the defaults main.gd already applied survive and the next save
    # heals the file.
    if _is_implausible(win, sz):
        return {"position": win.position, "size": win.size, "visible": cfg.get_value(section, "visible", win.visible)}

    sz = floored(win, sz)
    sz = _clamp_to_host(win, sz)

    var vis: bool = cfg.get_value(section, "visible", win.visible)

    # An empty usable_rect means headless, where there is nothing to validate against.
    var no_screens := usable_rect.size.x <= 0 or usable_rect.size.y <= 0
    if pos != Vector2i() and (no_screens or usable_rect.intersects(Rect2i(pos, sz))):
        win.position = pos
    else:
        pos = win.position

    return {"position": pos, "size": sz, "visible": vis}


## A stored size, never below the window's own floor.
##
## **Every path that writes a stored size goes through this**. Four of the five
## did not: `_apply`, both halves of `reapply_deferred` and the settle loop each
## wrote `win.size` straight from the file, and all four run *after*
## `DockerWindow.enforce_column_minimum` has raised `min_size` to what the column
## inside actually wants. So the floor was applied and then written over, and the
## Minimap opened 300 wide against a column wanting 335 with 31 units of its own
## hide button past the right edge. The Colour Picker escaped it only because its
## stored size already cleared its floor.
static func floored(win: Window, sz: Vector2i) -> Vector2i:
    var min_sz := win.min_size
    if min_sz == Vector2i():
        min_sz = DockerUtils.get_min_docker_size(win)
    # The column's own want, and not only what `min_size` was last set to.
    #
    # `DockerWindow.apply_window_scale` writes `min_size` from the logical
    # minimum and then raises it, and the raise reads a column that has not
    # necessarily laid out yet. The Minimap's has not: a run reads its
    # `min_size` at 177 while its column already wants 335, so flooring against
    # `min_size` alone let the stored 300 through and left the hide button 31
    # units past the right edge. Read rather than enforced, because this is
    # called from the save path too and a clamp that resizes a window while
    # measuring it is not one.
    var column := DockerWindow.column_min_width(win)
    if column > 0:
        min_sz.x = maxi(min_sz.x, column)
    var rows := DockerWindow.column_min_height(win)
    if rows > 0:
        min_sz.y = maxi(min_sz.y, rows)
    return Vector2i(maxi(sz.x, min_sz.x), maxi(sz.y, min_sz.y))


## Every screen's usable rectangle merged into one, which a stored position has
## to touch to be kept.
static func all_screens_rect() -> Rect2i:
    var merged := Rect2i()
    for screen in DisplayServer.get_screen_count():
        var r := DisplayServer.screen_get_usable_rect(screen)
        merged = r if merged == Rect2i() else merged.merge(r)
    return merged


## Never restore a docker larger than the area hosting it.
##
## Layouts are stored normalised, so a scale bug multiplies them back out wrong:
## one wrote docker sizes of 3070 into a 1920-logical viewport, leaving them
## unreachable. Clamping on load means a bad file heals itself instead of
## needing to be deleted by hand.
static func _clamp_to_host(win: Window, sz: Vector2i) -> Vector2i:
    var host := Vector2i()
    if win.is_embedded():
        # An embedded subwindow is drawn inside the viewport of whatever node
        # hosts it, so that viewport's visible rect is the space available.
        var parent_node := win.get_parent()
        if parent_node != null and parent_node.is_inside_tree():
            var host_vp := parent_node.get_viewport()
            if host_vp != null:
                host = Vector2i(host_vp.get_visible_rect().size)
    else:
        var usable := DisplayServer.screen_get_usable_rect(win.current_screen if win.is_inside_tree() else -1)
        host = usable.size
    if host.x <= 0 or host.y <= 0:
        return sz
    return Vector2i(mini(sz.x, host.x), mini(sz.y, host.y))


## Whether a stored size is too small to have been written by a working session,
## which is what tells corrupt geometry from a file merely older than the
## store's check of its units.
static func _is_implausible(win: Window, sz: Vector2i) -> bool:
    if sz == Vector2i():
        return false
    var min_sz := win.min_size
    if min_sz == Vector2i():
        min_sz = DockerUtils.get_min_docker_size(win)
    return sz.x < min_sz.x or sz.y < min_sz.y
