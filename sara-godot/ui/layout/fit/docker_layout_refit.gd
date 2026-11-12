## Where each docker of the live layout goes on the host it is on now, at a
## boot, a resize of the window or a change of the UI scale.
##
## **Two rules, one for each kind of layout.** The four layouts Sara ships are
## placed again from their shipped files through `SaDockerLayoutFit`, the
## rectangles and which dockers have room to be open, so a host that shrinks
## and grows back gives the same dockers in the same places. Any other layout
## keeps the positions the painter chose while the host keeps every title strip
## in reach, and is fitted over its own rectangles once it does not, [method
## painter_entries], with every title strip below the bar.
##
## A scale change saves none of the positions it pushes the dockers to as the
## painter's, or a trip to scale 2 and back would leave them heaped over the
## menus, and a resize places a title below the bar. Its own class because where
## a docker goes on a host is one decision with two callers, the restore and
## every reflow, and the store's subject is what is stored.
class_name SaDockerLayoutRefit
extends RefCounted

## The key of the shipped file's meta section that lists the dockers the fit
## closes for room, first to last.
const CLOSE_ORDER: String = "close_order"

## The key of a docker's section that raises its floor for the fit above the
## docker's own, in the file's units. The Layers docker's is the width its
## blend row reads whole at and the height that shows four rows.
const FLOOR_SIZE: String = "floor_size"

## Set on a docker the fit closed, so a later fit with room for it opens it
## again and opens nothing a painter, Tab or the boot closed.
const CLOSED_META: StringName = &"sa_closed_by_the_fit"

## `func() -> int`, the first logical row below the bar, the store's own
## `top_inset`. Unset reads as the host's top edge.
var _top_inset: Callable

## `func(win: Window, size: Vector2i) -> Vector2i`, a size never below the
## docker's own floor, the store's rule for every size it writes.
var _floor: Callable


func _init(top_inset: Callable, floor_of: Callable) -> void:
    _top_inset = top_inset
    _floor = floor_of


## Each docker of the shipped layout *live* names on this host, as the store's
## own entry, when that is one of the four Sara ships, and nothing for any
## other. `{"position", "size", "visible": true}` is a docker the fit places,
## and `{"visible": false}` one it closed for room. `{"position", "size"}` with
## no `visible` is a docker the file keeps closed and the place it opens at,
## [method SaDockerLayoutFit.opening], given while it is closed, so a chord or
## the Window menu opens it there. One a step has shown is left out and kept on
## the host as before.
##
## **The live file is the painter's the moment they touch it.** An edit under a
## shipped name forks it (`SaDockerLayoutPresets.fork_for_edit`), so a live file
## still naming `default` or `full` is the shipped one, copied on a first run or
## loaded from the Window menu, and never a layout anybody arranged. The name
## has to be written in the file: one with none is a profile from before
## presets, and that is the painter's own.
##
## **All four, and not the default alone.** A shipped layout sets no UI scale,
## so a load keeps the painter's, and at 1.25 on a 1920 by 1080 window the host
## is 1536 by 864. Kept on it the way a resize keeps a painter's layout,
## Minimalistic's Layers stood at y 344 with its title under the Colour Picker,
## whose foot was at 474. A module's layout is kept as a painter's is, because
## its file is found through the module loader, which this class does not
## reach.
##
## The rectangles and the open dockers are the shipped file's rather than the
## live one's. The live file is written back after every settle, and fitting
## what the last fit wrote would shrink a docker a little further on every
## smaller screen and never grow it back on a larger one. And since opening or
## closing a docker forks, a live shipped layout opens what its file opens: a
## docker Tab hid is still placed, so it comes back where it belongs.
func shipped_entries(live: ConfigFile, dockers: Array) -> Dictionary:
    var meta := DockerLayoutStore.META_SECTION
    var named := String(live.get_value(meta, DockerLayoutStore.META_PRESET, ""))
    if not SaDockerLayoutPresets.SHIPPED.has(named):
        return {}
    var shipped := ConfigFile.new()
    if shipped.load(SaDockerLayoutPresets.SHIPPED_DIR.path_join(named + ".cfg")) != OK:
        return {}
    var written_for: Vector2i = shipped.get_value(meta, DockerLayoutStore.META_WRITTEN_FOR, Vector2i())
    var placed: Dictionary = {}
    var closed: Dictionary = {}
    var host := Vector2i()
    var factor := 1.0
    for config: Dictionary in dockers:
        var win: Window = config["node"] as Window
        var section := DockerLayoutStore.section_for(config)
        if win == null or not shipped.has_section(section) or SaDockerMaximise.is_maximised(win):
            continue
        if not bool(shipped.get_value(section, "visible", false)):
            if not win.visible:
                closed[section] = win
            continue
        factor = SaUI.window_scale(win)
        host = DockerDragHandle.host_size_of(win) - Vector2i(0, status_rows_in(factor))
        var pos: Vector2i = shipped.get_value(section, "position", Vector2i())
        var sz: Vector2i = shipped.get_value(section, "size", Vector2i())
        var floor_size: Vector2i = shipped.get_value(section, FLOOR_SIZE, Vector2i())
        var own: Vector2i = _floor.call(win, Vector2i.ONE)
        var least := own.max(Vector2i((Vector2(floor_size) * factor).ceil()))
        placed[section] = {
            "rect": Rect2i(Vector2i(Vector2(pos) * factor), Vector2i(Vector2(sz) * factor)),
            "min": least,
            "content": opening_height(win, Vector2i(Vector2(sz) * factor)),
        }
    if placed.is_empty() or host.x <= 0 or host.y <= 0 or written_for == Vector2i():
        return {}
    var order: Array = shipped.get_value(meta, CLOSE_ORDER, [])
    var fit := SaDockerLayoutFit.new(host, _top(factor), Vector2i(Vector2(written_for) * factor), order)
    var rects := fit.place(placed)
    var out: Dictionary = {}
    for section: String in placed:
        out[section] = {"visible": false}
        if rects.has(section):
            var rect: Rect2i = rects[section]
            out[section] = {"position": rect.position, "size": rect.size, "visible": true}
    for section: String in closed:
        var opened := _opening(closed[section], shipped, section, fit, placed, rects)
        out[section] = {"position": opened.position, "size": opened.size}
    return out


## Where *win*, which *shipped* keeps closed under *section*, opens on this
## host. Its own place first, sized and kept on the whole host as the store
## restores a closed docker, which is where it always opened. *placed* and
## *rects* are what *fit* was handed and answered.
func _opening(
    win: Window, shipped: ConfigFile, section: String, fit: SaDockerLayoutFit, placed: Dictionary, rects: Dictionary
) -> Rect2i:
    var factor := SaUI.window_scale(win)
    var pos: Vector2i = shipped.get_value(section, "position", Vector2i())
    var sz: Vector2i = shipped.get_value(section, "size", Vector2i())
    var stored := Rect2i(Vector2i(Vector2(pos) * factor), Vector2i(Vector2(sz) * factor))
    var size: Vector2i = _floor.call(win, stored.size)
    var whole := DockerDragHandle.host_size_of(win)
    if whole.x > 0 and whole.y > 0:
        size = size.min(whole)
    return fit.opening(Rect2i(kept(win, stored.position, size), size), stored, placed, rects)


## The restore's fit taken again by *store* each time a docker's floor moves and
## the fit then answers otherwise, for as long as the boot settles, which is
## *store*'s `save_allowed` saying no. *dockers* are the ones the restore placed
## and *refit* the one it asked.
##
## **The boot's floors are read before the dockers have laid out.** A docker's
## floor at the boot's fit is a line wrapped at a column not yet sorted, or a
## grid with nothing in it yet, and a couple of frames later it is what a live
## change of scale reads. Where the floors bind the two give different layouts,
## a docker grown over its neighbour's title at boot where a live change closes
## the neighbour for room, so the fit follows the floors until they settle.
##
## Its own coroutine and not the store's settle loop, which re-asserts one
## docker's rectangle at a time and has no lines to spare.
static func follow_the_floors(refit: SaDockerLayoutRefit, store: DockerLayoutStore, dockers: Array) -> void:
    if not store.is_inside_tree() or not store.save_allowed.is_valid() or store.save_allowed.call():
        return
    var answered := refit.shipped_entries(_live(store), dockers)
    var read := refit.floors(dockers)
    while not answered.is_empty():
        await store.get_tree().process_frame
        if not is_instance_valid(store) or not store.is_inside_tree() or store.save_allowed.call():
            return
        var now := refit.floors(dockers)
        if now != read:
            read = now
            answered = refit.fitted_again(store, dockers, answered)


## The floor the fit reads for each docker of *dockers*, in their order, for
## [method follow_the_floors] to tell a moved one by.
func floors(dockers: Array) -> Array[Vector2i]:
    var out: Array[Vector2i] = []
    for config: Dictionary in dockers:
        var win: Window = config["node"] as Window
        out.append(_floor.call(win, Vector2i.ONE) if win != null else Vector2i())
    return out


## What the fit answers for *store*'s *dockers* now, which places them again
## when it is not *answered*, the answer they were placed by. Nothing is placed
## once the live layout is not one Sara ships.
func fitted_again(store: DockerLayoutStore, dockers: Array, answered: Dictionary) -> Dictionary:
    var again := shipped_entries(_live(store), dockers)
    if again != answered and not again.is_empty():
        store.reflow_to_host()
    return again


static func _live(store: DockerLayoutStore) -> ConfigFile:
    var live := ConfigFile.new()
    live.load(store.path)
    return live


## Where each open docker of a painter's layout goes on this host, by section,
## as `{"position", "size"}`, or nothing when every one of *rects* stands inside
## the host as it is. *rects* is the painter's rectangle of each open embedded
## docker, by section, and *wins* its window. *arranged_on* is the host the
## painter last saw every rectangle on, or zero when none is known. *live* is
## the live file, whose [constant FLOOR_SIZE] a fork of a shipped layout keeps,
## so its Layers docker still shows four rows, and whose `written_for` stands in
## for *arranged_on* when the store never saw the painter's rectangles fit,
## which is a fork reopened on a smaller window. Either only when it holds every
## rectangle, and the rectangles' own extent otherwise, since the fit keeps a
## docker of the right half at its distance from that host's right edge.
##
## **The fit a shipped layout gets, run over the painter's own rectangles.**
## Opening a docker forks the default to Default (Custom), and from then on a
## change of scale only kept each docker on the host at the size the old scale
## left it. Opened at 1.0 and changed live to 1.25, Layers stood from 314 to 838
## over the Colour Picker and the Reference over Tool Options. A fork that
## remembered the shipped file it came from was the other way, and it would
## fit the shipped rectangles and not the painter's, so a docker they dragged
## or opened would jump back to where Sara ships it. With no close order,
## because a docker of the painter's is never closed for them.
##
## **A docker the fit lays over another goes beside its column**, through
## [method SaDockerLayoutFit.opening], where a shipped layout's close order
## would close it.
##
## **Nothing moves while every title strip is in reach.** A host that keeps
## a part of each strip on it, [method reached], answers nothing, and the store
## puts each docker where the painter left it, cut by the window's edge or not,
## rather than answering as soon as one docker's frame leaves the host, which
## would push every docker of the right column in for a window 40 narrower.
## The status line counts only once something has to move, since a
## docker a painter dragged over the line stays there.
##
## **A docker the painter put past an edge or over the bar is theirs to keep
## there.** One whose rectangle stands partly outside *arranged_on*, or outside
## this host while that is unknown, or whose top is above the bar's foot, is
## left out of the fit, and the store moves it only as far
## as its strip needs. The fit places the rest, which stood whole where the
## painter arranged them, when one of their strips leaves the host, a change to
## scale 1.25 putting the right column past the edge.
func painter_entries(live: ConfigFile, rects: Dictionary, wins: Dictionary, arranged_on: Vector2i) -> Dictionary:
    var host := Vector2i()
    var placed: Dictionary = {}
    var moves := false
    var extent := Vector2i()
    for section: String in rects:
        var win: Window = wins[section]
        var rect: Rect2i = rects[section]
        host = DockerDragHandle.host_size_of(win)
        if not Rect2i(Vector2i(), arranged_on if arranged_on != Vector2i() else host).encloses(rect):
            continue
        if rect.position.y < _top(1.0):
            continue
        moves = moves or reached(win, rect.position, rect.size) != rect.position
        extent = extent.max(rect.end + Vector2i(0, SaDockerLayoutFit.BOTTOM_MARGIN))
        var floor_size: Vector2i = live.get_value(section, FLOOR_SIZE, Vector2i())
        placed[section] = {"rect": rect, "min": floor_size.max(_floor.call(win, Vector2i.ONE))}
    if not moves or host.x <= 0 or host.y <= 0:
        return {}
    var written_for := extent.max(host)
    var in_file: Vector2i = live.get_value(DockerLayoutStore.META_SECTION, DockerLayoutStore.META_WRITTEN_FOR, Vector2i())
    for known: Vector2i in [in_file, arranged_on]:
        if known.x >= extent.x and known.y >= extent.y:
            written_for = known
    var room := host - Vector2i(0, status_rows_in(1.0))
    var fit := SaDockerLayoutFit.new(room, _top(1.0), written_for)
    var rects_now := fit.place(placed)
    # A column whose floors are more than its height is laid over itself, and
    # the lowest docker of it goes beside the column, as a closed one opens.
    var lowest_first: Array = rects_now.keys()
    lowest_first.sort_custom(func(a: String, b: String) -> bool: return rects[a].position.y > rects[b].position.y)
    for section: String in lowest_first:
        var others: Dictionary = rects_now.duplicate()
        others.erase(section)
        rects_now[section] = fit.opening(rects_now[section], rects[section], placed, others)
    var out: Dictionary = {}
    for section: String in rects_now:
        var rect: Rect2i = rects_now[section]
        out[section] = {"position": rect.position, "size": rect.size}
    return out


## The painter's own rectangle of each docker a fit of their layout has moved,
## which the window does not show. The store saves this rather than the
## window, and a host with room for it again puts the docker back at it.
##
## **The size has to be remembered and not only the place.** The store's intent
## keeps the painter's position through a push, but a save writes the window's
## size, and a save comes with every focus the window loses. The fit shrinks a
## column's lowest docker first, so without this a docker cut at 1.25 would be
## saved cut and stay cut at 1.0 again. A window that is not at the rectangle
## the fit gave it has been moved by something else, a drag above all, and what
## it shows is the painter's again.
class PainterRects:
    extends RefCounted

    ## Section -> `{"at": Rect2i, "painter": Rect2i}`, where the fit put the
    ## docker and what the painter had.
    var _moved: Dictionary = {}

    ## The host every painter's rectangle last stood inside, or zero before one.
    var arranged_on: Vector2i = Vector2i()

    ## The painter's rectangle of *win*, standing at *intended* by the store's
    ## memory: the one the fit moved it from while it is still where the fit put
    ## it, and its own size at *intended* otherwise.
    func painter(section: String, win: Window, intended: Vector2i) -> Rect2i:
        if moved(section, win):
            return _moved[section]["painter"]
        return Rect2i(intended, win.size)

    ## Whether *win* stands where a fit of the painter's layout put it.
    func moved(section: String, win: Window) -> bool:
        return _moved.has(section) and _moved[section]["at"] == Rect2i(win.position, win.size)

    ## *win* placed at *entry* of [method SaDockerLayoutRefit.painter_entries],
    ## away from *theirs*, the painter's rectangle.
    func put(section: String, win: Window, entry: Dictionary, theirs: Rect2i) -> void:
        win.position = entry["position"]
        win.size = entry["size"]
        # The window's own minimum can refuse the size, so the rectangle it
        # took is the one remembered.
        _moved[section] = {"at": Rect2i(win.position, win.size), "painter": theirs}

    ## *win* back at its own size, when a fit had moved it, and forgotten.
    func put_back(section: String, win: Window) -> void:
        if moved(section, win):
            win.size = (_moved[section]["painter"] as Rect2i).size
        _moved.erase(section)

    func forget() -> void:
        _moved.clear()
        arranged_on = Vector2i()


## *entry* of [method shipped_entries] for the restore to merge into *win*'s,
## with *win* marked as closed by the fit or not, so the reflow after it knows.
## An entry with no `visible` is a docker its file keeps closed, which the fit
## never did.
static func taken(win: Window, entry: Dictionary) -> Dictionary:
    win.set_meta(CLOSED_META, not bool(entry.get("visible", true)))
    return entry


## *win* placed as *entry* of [method shipped_entries] says, on a resize or a
## change of the scale. A docker the fit closes is hidden, and one it closed
## earlier is shown once there is room for it again. Nothing is shown or hidden
## while Tab has the dockers hidden, whose memory of what was open
## `SaFocusMode` keeps, and `MainDockers.toggle_all_dockers` reflows on the way
## back, so a docker Tab shows on a host that has no room for it closes again.
## A docker its file keeps closed is only moved to where it opens.
static func put(win: Window, entry: Dictionary) -> void:
    if entry.has("position"):
        win.position = entry["position"]
        win.size = entry["size"]
    if not entry.has("visible"):
        return
    var open := bool(entry["visible"])
    if SaFocusMode.active or open == win.visible:
        return
    if open and not bool(win.get_meta(CLOSED_META, false)):
        return
    win.set_meta(CLOSED_META, not open)
    win.visible = open


## The height *win* shows all it holds at, in the units its geometry is
## measured in, or 0 for a docker that keeps the height a layout gives it.
##
## **A docker opts in, and the layout never guesses**, because a view that
## fills its docker has no height of its own to report, and the Tool Options'
## changes with the tool in the hand. A docker with
## `opening_height()` is one whose rows are a fixed set and which says how tall
## they are, the toolbox first, and a module's docker answers the same way
## through the same method.
static func opening_height(win: Window, given: Vector2i) -> int:
    return int(win.call("opening_height", given)) if win.has_method("opening_height") else 0


## The height the shipped file at *shipped_path* gives each docker that says
## how tall its content is, in this run's pixels, for a shipped layout other
## than the four [method shipped_entries] fits, a module's. The store measures
## the content at the width the docker will open at, which only it knows.
##
## From the shipped file and not the live one, for the reason [method
## shipped_entries] gives. The live file holds the last cut, so a toolbox cut to
## five buttons in one session never grew back to show a sixth a module added
## by the next.
func shipped_heights(shipped_path: String, dockers: Array) -> Dictionary:
    var shipped := ConfigFile.new()
    if shipped.load(shipped_path) != OK:
        return {}
    var out: Dictionary = {}
    for config: Dictionary in dockers:
        var win: Window = config["node"] as Window
        var section := DockerLayoutStore.section_for(config)
        if win == null or not win.has_method("opening_height") or not shipped.has_section(section):
            continue
        var stored := Vector2(shipped.get_value(section, "size", Vector2i()))
        out[section] = int(stored.y * SaUI.window_scale(win))
    return out


## *pos*, moved as little as possible to keep *win*'s whole frame on its host
## and its title strip below the bar. A host too short for both keeps the title,
## because a docker whose foot is off the window can still be dragged up by it.
## *size* is the one *win* is about to take, when a restore has not set it yet.
func kept(win: Window, pos: Vector2i, size: Vector2i = Vector2i()) -> Vector2i:
    var host := DockerDragHandle.host_size_of(win)
    if host == Vector2i():
        return pos
    var fit := SaDockerLayoutFit.new(host, _top(SaUI.window_scale(win)), Vector2i())
    return fit.kept(pos, size if size != Vector2i() else win.size)


## *pos*, moved as little as possible to keep a part of *win*'s title strip on
## its host, [method SaDockerLayoutFit.reached], where a painter's docker
## stands after a resize, a change of scale and a reopen. The whole host and
## not the part below the bar, because a drag may put a docker over the bar and
## it stays there. A window of its own keeps [method
## kept]'s screen rule. *size* is as [method kept] takes it.
func reached(win: Window, pos: Vector2i, size: Vector2i = Vector2i()) -> Vector2i:
    if win == null or not win.is_inside_tree() or not win.is_embedded():
        return kept(win, pos, size)
    var host := DockerDragHandle.host_size_of(win)
    return SaDockerLayoutFit.reached(pos, size if size != Vector2i() else win.size, Rect2i(Vector2i(), host))


## Whether *rect* of *win* stands whole on its host, the bar's rows counted as
## host, which is the host a painter's layout was arranged on. An empty host
## holds anything.
func whole_on_host(win: Window, rect: Rect2i) -> bool:
    var host := DockerDragHandle.host_size_of(win)
    return host == Vector2i() or SaDockerLayoutFit.new(host, 0, Vector2i()).kept(rect.position, rect.size) == rect.position


## Where the Window menu's show opens *win*, asked for at *at*: an embedded
## docker whole on its host and below the bar, [method kept], so a docker the
## painter left over the bar or past an edge comes back where all of it is
## seen, and a window of its own on the screen under its centre, `DockerDragHandle.fit_inside`.
func shown(win: Window, at: Vector2i) -> Vector2i:
    if win.is_inside_tree() and win.is_embedded():
        return kept(win, at)
    return DockerDragHandle.fit_inside(win, at, Vector2(at) + Vector2(win.size) * 0.5)


## Whether *win* can stand at *pos* as a reflow leaves it: anywhere its title
## strip is in reach when embedded, [method reached], and wholly on its screen
## when it is a window of its own. An empty host holds anything.
func fits(win: Window, pos: Vector2i) -> bool:
    if win.is_inside_tree() and win.is_embedded():
        return reached(win, pos) == pos
    var host := DockerDragHandle.host_size_of(win)
    return host == Vector2i() or Rect2i(Vector2i(), host).encloses(Rect2i(pos, win.size))


## *win* put at *pos* with its title strip in reach, [method reached], where a
## reflow puts a painter's docker back.
##
## **The engine moves an embedded window wholly inside after the reflow.** A
## viewport that changes size emits `size_changed`, which is what runs
## `DockerLayoutStore.reflow_to_host`, and only then clamps every embedded
## window to lie whole on it, on a change of either side. Layers left 165 past
## the right edge of a 1280 wide window stood at 890 after a shrink to 1200
## rather than at the 1072 the reflow gave it, and at 970 after growing back
## rather than at 1115. So a place partly outside is written again deferred,
## which lands after the clamp in the same frame.
func put_back(win: Window, pos: Vector2i) -> void:
    win.position = reached(win, pos)
    if win.is_inside_tree() and win.is_embedded() and kept(win, win.position) != win.position:
        win.set_deferred("position", win.position)


## *pos* as the store's settle loop and a reapply hold *win* at it, with an
## embedded docker's title strip kept in reach of the host it has now. A window
## of its own and a zero *pos*, which is no place, are left as they are. The
## store's cache holds the painter's place, which a shrink since may have taken
## the strip of, and a settle still running from a drag put Layers back at 1115
## on a window shrunk to 1200, 85 of its strip left on it.
func held(win: Window, pos: Vector2i) -> Vector2i:
    if pos == Vector2i() or not win.is_inside_tree() or not win.is_embedded():
        return pos
    return reached(win, pos)


## The row below the bar in the units a window of *factor* measures in.
func _top(factor: float) -> int:
    return int(ceil(int(_top_inset.call()) * factor)) if _top_inset.is_valid() else 0


## The rows `SaStatusLine.rows_taken` says the line takes from the window's
## foot, in the units a window of *factor* measures in. The floor no docker of
## a shipped layout's fit passes, kept the way [member _top_inset] keeps the
## head, and `SaDockerFontGrowth` keeps a growing docker above it as well. A
## painter's own layout is only [method reached] on the whole host while its
## strips are in reach, so a docker they dragged over the line stays where they
## put it, and
## [method painter_entries] counts the line once something has to move.
##
## **The window's last rows and not the host's.** At 1280 by 1024 the fit gave
## Full's Undo History and Default's Layers at a font size of 1.3 a foot at
## 1009, 15 above the window's foot and nine rows into the line, over the size
## and the colour space it reads. Read off the line's class rather than handed
## in as the bar's height is, because the store that would hand it stands at
## its thousand lines.
static func status_rows_in(factor: float) -> int:
    return int(ceil(SaStatusLine.rows_taken() * factor))
