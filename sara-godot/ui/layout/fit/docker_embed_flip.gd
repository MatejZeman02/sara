## Where each docker goes when the dockers are let out of the main window or
## taken back into it, the Workspace page's "Dockers inside the main window".
##
## **The two sides measure a position in two units.** An embedded docker's
## position is in the main window's logical space, below a bar it shares with
## the menus, and a docker let out is a window of the system whose position is
## in the screen's pixels. A switch that carries the numbers across unchanged
## puts a docker at x 1600 inside a window at scale 2 at screen pixel 1600.
## Under Wayland it is worse: a window of the system is given no position at
## all, every docker reads (0, 0) while it is out, and taking them back in on
## those numbers piles all six in the top left corner over the menus.
##
## So this remembers every docker's place in the main window's terms before the
## switch, and after it puts each docker back at that place converted into
## whatever it measures in now, kept inside the main window and below the bar.
## The place remembered is the one the store meant, which is what was put there
## rather than what Wayland reports. `SaSettingsApply` announces the two
## moments, the store hands itself over at each, and the store's memory is
## written through the store's own public methods, a note, a settle and a save.
##
## Beside the store rather than in it, because the store stands a few lines
## under the thousand a run fails, and because the conversion is one decision
## with no file behind it. It holds no store of its own: a piece that keeps the
## class it was cut from is what the second rule of structure refuses.
class_name SaDockerEmbedFlip
extends RefCounted

## Section -> the docker's place in the main window's logical space, read before
## the switch.
var _held: Dictionary = {}


## *store*'s dockers, its provider's entries.
static func _dockers(store: DockerLayoutStore) -> Array:
    return store.dockers_provider.call() if store.dockers_provider.is_valid() else []


## A docker out on a summon is given back first, because its return address is
## in the units about to change. Then every docker of *store* is remembered at
## the place the store holds as the painter's for it. A store that has left the
## tree has no dockers on any screen.
func before_the_switch(store: DockerLayoutStore) -> void:
    if not store.is_inside_tree():
        return
    for section: String in store.borrowed.sections():
        store.give_back(section)
    remember_all(_dockers(store), store._intended_positions)


## Every docker of *store* placed, noted there and held by its settle loop, and
## the file written in the new side's units, which the store refuses at the
## next start when it names the other side.
func after_the_switch(store: DockerLayoutStore) -> void:
    if not store.is_inside_tree():
        return
    var top := int(store.top_inset.call()) if store.top_inset.is_valid() else 0
    var moved := place_all(_dockers(store), top)
    for section: String in moved:
        store.note_placement(moved[section])
        store.reapply_deferred(moved[section], section)
    store.save()


## Before the switch: every docker of *dockers*, the store's provider entries,
## at the place *intended* holds for its section, which is the store's own
## memory of where the painter put it, or where it stands when that has none.
func remember_all(dockers: Array, intended: Dictionary) -> void:
    _held.clear()
    for config: Dictionary in dockers:
        var win: Window = config["node"] as Window
        if win != null and win.is_inside_tree():
            var section := DockerLayoutStore.section_for(config)
            remember(section, win, intended.get(section, win.position))


## After it: every docker of *dockers* moved to [method placed], by section.
## *top* is the first logical row below the bar.
##
## The switch shows again only what was shown and re-derives only its size, so
## a hidden docker's is re-derived here, or it would open later measured at the
## other side's scale. A maximised docker fills its host and is left to the
## maximise, as the store leaves it everywhere else.
func place_all(dockers: Array, top: int) -> Dictionary:
    var moved: Dictionary = {}
    for config: Dictionary in dockers:
        var win: Window = config["node"] as Window
        if win == null or not win.is_inside_tree() or SaDockerMaximise.is_maximised(win):
            continue
        if not win.visible and win.has_method("apply_window_scale"):
            win.call("apply_window_scale")
        var section := DockerLayoutStore.section_for(config)
        win.position = placed(section, win, top)
        moved[section] = win
    return moved


## Remembers *pos*, measured the way *win* measures it now, under *section*.
func remember(section: String, win: Window, pos: Vector2i) -> void:
    _held[section] = to_host(win, pos)


## Where *win* goes after the switch, in the units it measures in now: its
## remembered place moved as little as keeps the whole docker inside the main
## window with its title no higher than *top*, the first logical row below the
## bar. A docker nothing was remembered for stays where it is.
func placed(section: String, win: Window, top: int) -> Vector2i:
    if not _held.has(section) or not win.is_inside_tree():
        return win.position
    var host := Vector2i(win.get_tree().root.get_visible_rect().size)
    var at: Vector2i = _held[section]
    if host.x > 0 and host.y > 0:
        at = SaDockerLayoutFit.new(host, top, Vector2i()).kept(at, logical_size(win))
    return from_host(win, at)


## *pos*, measured the way *win* measures it now, in the main window's logical
## space. An embedded docker already is, and one let out is in screen pixels
## from the main window's own corner, at the main window's scale.
static func to_host(win: Window, pos: Vector2i) -> Vector2i:
    if win.is_embedded():
        return pos
    var root := win.get_tree().root
    return Vector2i((Vector2(pos - root.position) / SaUI.window_scale(root)).round())


## The inverse of [method to_host], for whichever side *win* is on now.
static func from_host(win: Window, pos: Vector2i) -> Vector2i:
    if win.is_embedded():
        return pos
    var root := win.get_tree().root
    return root.position + Vector2i((Vector2(pos) * SaUI.window_scale(root)).round())


## *win*'s size in logical units, divided by the scale its geometry was last
## derived at rather than the one it would get now. A window with no
## `apply_window_scale` of its own, which a suite's probe is, still measures in
## the old side's units after the switch, and dividing by the new side's scale
## would halve or double it.
static func logical_size(win: Window) -> Vector2i:
    var applied: float = win.get_meta(SaUI.APPLIED_SCALE_META, 0.0)
    var factor := applied if applied > 0.0 else SaUI.window_scale(win)
    return Vector2i((Vector2(win.size) / factor).ceil())
