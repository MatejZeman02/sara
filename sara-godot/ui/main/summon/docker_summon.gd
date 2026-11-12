## A docker summoned under the pointer by its chord, and sent back when the
## pointer has left it.
##
## The rules of it: the docker appears only when its chord is pressed and it appears
## under the pointer, it goes when the pointer has been out for a second and
## three percent of the screen's width away, the chord twice within a second
## closes it, a docker that was already visible jumps and comes back, it takes
## no focus, the leave timer waits while a field inside it holds focus and while
## a window the docker opened is up, and a docker a painter has locked open
## ignores the leave timer altogether.
##
## The borrow itself is `DockerLayoutStore`'s, which keeps the return address
## and writes nothing to the layout while a docker is out. This node owns the
## rest: when each summon was pressed, how long each borrowed docker has had the
## pointer away, whether its bar is offering the lock, and the frame loop that
## sends it back. A child of `MainDockers`, which hands it the store and asks it
## the one question `DockerFocus` needs.
##
## The leave waits while a field inside the docker is being typed into, and
## "being typed into" is not the same question as "the field has the keyboard":
## the engine keeps the keyboard on a `LineEdit` after Enter, so a field whose
## edit was finished at the keyboard would go on holding its docker for good.
class_name DockerSummon
extends Node

## A second press of the same chord within this many milliseconds closes the
## docker rather than moving it.
const TWICE_MS: int = 1000

## The store whose borrow this drives.
var _store: DockerLayoutStore = null

## The dwell and the distance, read from the profile each time they are asked.
var _preferences := SaDockerBorrow.new()

## Section -> the `Time.get_ticks_msec()` of the last summon, for the chord
## twice.
var _pressed_at: Dictionary = {}

## Section -> when the pointer was first seen past the distance, cleared the
## moment it comes back. A section with no entry has the pointer near it.
var _away_since: Dictionary = {}

## The fields being typed into inside the borrowed dockers, which is what holds
## one out after the keyboard has outlived the edit.
var _edits := EditWatch.new()


func _init(store: DockerLayoutStore) -> void:
    name = "DockerSummon"
    _store = store


## Shows *win*, stored under *section*, centred on *point*, or sends it back
## when the same chord ran less than [constant TWICE_MS] ago. *point* is in the
## space `win.position` is measured in. *now_ms* is the clock, handed in so a
## suite can press twice without waiting. *locked* holds the docker out from the
## first frame, which is the summon chord pressed with its modifier.
##
## The keyboard is `MainDockers`' to put back, because the window that held it
## is a question for `DockerFocus`, which that node already asks.
func summon(win: Window, section: String, point: Vector2i, now_ms: int = Time.get_ticks_msec(), locked: bool = false) -> bool:
    if win == null or _store == null:
        return false
    if _store.is_borrowed(section) and now_ms - int(_pressed_at.get(section, -TWICE_MS)) < TWICE_MS:
        send_back(section)
        return true
    if not _store.borrow(win, section, point):
        return false
    _watch(win, section)
    _pressed_at[section] = now_ms
    _away_since.erase(section)
    SaDockerLock.offer(win, true)
    _show_lent(win, true)
    if locked:
        SaDockerLock.set_locked(win, true)
    return true


## Returns the docker borrowed under *section* and forgets its timers.
##
## The lock goes with the borrow: what a painter holds open is the docker being
## out, and a docker that has gone back is not out.
func send_back(section: String) -> void:
    _pressed_at.erase(section)
    _away_since.erase(section)
    if _store != null:
        # Read while the store still has the address, which `give_back` is what
        # forgets.
        var win := _borrowed_node(section)
        SaDockerLock.forget(win)
        SaDockerLock.offer(win, false)
        _show_lent(win, false)
        _store.give_back(section)


## Draws *win*'s head for a docker out on a lend or home again, see
## [method DockerWindow.show_lent]. A window that is not a docker has no head.
static func _show_lent(win: Window, out: bool) -> void:
    var docker := win as DockerWindow
    if docker != null:
        docker.show_lent(out)


## What is wrong with *win*, stored under *section*, when Sara counts it as shown
## and it is not, or the empty string when nothing is.
##
## **A fault Windows can show.** A docker dragged, summoned and given back can
## end as a picture on screen that takes no input, which Windows lists as a
## window not visible, with nothing in the log and nothing Linux reproduces. So
## a sighting leaves a line, and these are the two ways Sara can hold a docker as shown that it is not:
##
## - **Out on a summon and hidden.** A borrowed docker is shown by the borrow,
##   and every path of Sara's own that hides one gives it back first:
##   [method send_back] and the docker's own close, which `MainDockers` sends
##   back before it hides. A hidden docker the store still holds was hidden by
##   something else.
## - **Shown with no window of its own.** Every show of a docker with the
##   subwindows off builds a new OS window, so a visible one whose id the
##   display server does not list is a window Sara draws into and nobody sees.
##
## A third way is neither: a flag written to a docker that owns its window and
## holds the keyboard makes Windows take `WS_VISIBLE` off a window the display
## server still lists, which no call of Godot's can see, so
## `MainDockers.summon_docker_by_id` writes none.
func hidden_while_counted(win: Window, section: String) -> String:
    if win == null or _store == null:
        return ""
    if not win.visible and _store.is_borrowed(section) and _borrowed_node(section) == win:
        return "%s was hidden while it is out on a summon" % section
    if win.visible and DockerLayoutStore.owns_os_window(win) and not DisplayServer.get_window_list().has(win.get_window_id()):
        return "%s is shown and its window %d is not one the display server lists" % [section, win.get_window_id()]
    return ""


## Watches *win*, stored under *section*, for the moment it is shown or hidden,
## from its first summon on. Connected once in the window's life.
func _watch(win: Window, section: String) -> void:
    var check := _check_after_a_frame.bind(win, section)
    if not win.visibility_changed.is_connected(check):
        win.visibility_changed.connect(check)


## Asks [method hidden_while_counted] a frame after *win* was shown or hidden,
## so the path that did it has finished, and a borrow given back has left the
## store before its window is asked about.
func _check_after_a_frame(win: Window, section: String) -> void:
    _warn_if_counted.call_deferred(win, section)


## The warning itself, with where the window is and what the display server
## says about it, which is what a reader of the log after a sighting needs.
func _warn_if_counted(win: Window, section: String) -> void:
    if not is_instance_valid(win):
        return
    var fault := hidden_while_counted(win, section)
    if fault.is_empty():
        return
    push_warning("DockerSummon: %s, at %s size %s, embedded %s" % [fault, win.position, win.size, win.is_embedded()])


## Whether *win* is out on a summon, which is what `DockerFocus` asks before it
## hands the keyboard to the docker under the pointer.
func is_summoned(win: Window) -> bool:
    if win == null or _store == null:
        return false
    for section: String in _store.borrowed.sections():
        if _borrowed_node(section) == win:
            return true
    return false


## One look at the docker borrowed under *section* with the pointer at *at* at
## *now_ms*, and whether it was sent back. *within* is the reach in the units
## of *at*, measured to the docker's rectangle rather than to its
## centre, so a large docker is not easier to leave than a small one.
##
## The dwell runs only while the pointer is past the reach, and not at all while a
## field inside the docker is being typed into, because a painter typing a
## layer's name has the pointer anywhere. It also does not run while a window
## the docker opened is up: a file dialog is a window the pointer has every
## reason to be in, and a docker sent back under its own dialog leaves the files
## picked nowhere to land. The guard clears the clock
## rather than pausing it, so the dwell runs its full length again once the window
## has closed and the pointer is still away.
##
## A locked docker is the third of those, and it is the painter's own answer
## rather than the app's: "We need to spawn and lock it functionality as well."
## The clock is cleared here too, so unlocking starts the dwell afresh instead of
## counting the time the docker was held.
func step(section: String, at: Vector2, within: float, now_ms: int) -> bool:
    var win := _borrowed_node(section)
    if win == null:
        return false
    if not win.visible:
        # A docker something closed, which the lock does not survive: what a
        # painter holds open is the docker being out, and a closed one is not.
        # The docker's own close sends it back before it hides it, so what
        # reaches here is a hide from outside the summon, which the warning of
        # `_warn_if_counted` has already put in the log. The step carries on
        # below, so the leave such a docker has always had is untouched.
        SaDockerLock.forget(win)
    if (
        SaDockerLock.is_locked(win)
        or _holds_a_field(win)
        or _has_a_window_up(win)
        or distance_to(Rect2(Vector2(win.position), Vector2(win.size)), at) <= within
    ):
        _away_since.erase(section)
        return false
    if not _away_since.has(section):
        _away_since[section] = now_ms
        return false
    if now_ms - int(_away_since[section]) < _preferences.dwell_ms:
        return false
    send_back(section)
    return true


## How far *point* is from *rect*, zero inside it.
static func distance_to(rect: Rect2, point: Vector2) -> float:
    var nearest := Vector2(clampf(point.x, rect.position.x, rect.end.x), clampf(point.y, rect.position.y, rect.end.y))
    return point.distance_to(nearest)


## Where the pointer is, in the space a docker's `position` is measured in: the
## host viewport's logical units for an embedded docker, the desktop's for a
## native one. A capture scenario's pointer wins, because Wayland will not let
## one place the real pointer, which is the seam `DockerDragHandle` keeps.
func pointer() -> Vector2:
    if DockerDragHandle.capture_pointer is Vector2:
        return DockerDragHandle.capture_pointer
    if SaSettings.embed_subwindows and is_inside_tree():
        return SaCursorPolicy.pointer_in(get_viewport())
    return SaCursorPolicy.pointer_in(null)


## The preference's fraction of the screen's width, in the same units as
## [method pointer]. The screen the main window is on, divided by the interface
## scale when the dockers are embedded, since their positions are logical.
func reach() -> float:
    var screen_id := DisplayServer.window_get_current_screen()
    var width := float(DisplayServer.screen_get_size(screen_id).x)
    if SaSettings.embed_subwindows and is_inside_tree():
        width /= maxf(get_window().content_scale_factor, 0.01)
    return width * _preferences.distance


func _process(_delta: float) -> void:
    if _store == null:
        return
    var sections: Array = _store.borrowed.sections()
    if sections.is_empty():
        return
    var at := pointer()
    var distance := reach()
    var now := Time.get_ticks_msec()
    for section: String in sections:
        step(section, at, distance, now)


## The docker out on a borrow under *section*, or null.
func _borrowed_node(section: String) -> Window:
    if _store == null:
        return null
    return _store.borrowed.node_of(section)


## Whether a docker is out on this summon. False for a summon with no store.
func docker_out() -> bool:
    return _store != null and _store.borrowed.any()


## Whether *win* has a window of its own up: a file picker it asked for, a
## rename dialog, a popup. Every one of them but the picker is a `Window` a
## docker opened as its own child, so the walk is *win*'s own subtree and reaches
## into the child windows too.
##
## **A picker the platform draws is no window of the tree**. `SaFilePicker` puts
## it up through the display server and no node stands for it, so it is asked
## whether one that a node under *win* asked for is still waiting for its answer.
## Without this the Reference docker's own Open button puts up a picker nothing in
## the app can see, which is what a note once reported. The engine's dialog, on a
## platform with no picker of its own, is a child `Window` and counts on the walk.
##
## A `Window` that is hidden is not up, and a dockers' window that is parked
## rather than closed is hidden, so the parked ones a session keeps around do
## not hold their owner forever.
func _has_a_window_up(node: Node) -> bool:
    return SaFilePicker.is_up_under(node) or _has_a_shown_window(node)


## Whether a `Window` anywhere under *node* is shown.
func _has_a_shown_window(node: Node) -> bool:
    for child: Node in node.get_children():
        var win := child as Window
        if win != null and win.visible:
            return true
        if _has_a_shown_window(child):
            return true
    return false


## Whether *win* is being typed into, which holds it out on a summon. Only a
## focused docker's focus owner counts, since a window that lost the focus keeps
## naming its last owner, and `_edits` knows a field the painter has finished
## with from one still under the keyboard. The other ways the keyboard leaves a
## field need nothing here: Escape drops it, a click on a button hands it to the
## button, and a click on the canvas takes the whole window's.
func _holds_a_field(win: Window) -> bool:
    if not win.has_focus():
        return false
    return _edits.holds(win.gui_get_focus_owner())


## The fields being typed into inside the borrowed dockers, and which of them
## have given the edit up.
##
## **"The keyboard is on a field" and "the field is being typed into" are two
## questions, and it is the second a summoned docker waits for.** A `LineEdit`
## keeps the keyboard after Enter, so a field whose edit is over would go on
## holding the docker for good. A field that
## announces its own submission stops holding until a keystroke changes it again.
##
## An inner class rather than members on the summon, because its whole subject
## is the fields: a field outlives a summon, a summon holds several, and what is
## kept is about the field rather than about the borrow. A suite can build one
## over a `LineEdit` and ask it without a `Window` anywhere, which the summon's
## own frame loop cannot be, since a `Window` outside the tree cannot be given
## the focus.
class EditWatch:
    extends RefCounted
    ## The instance id of every field whose text has been submitted since the
    ## last keystroke that changed it. One entry per field ever typed into
    ## during a summon, which the dockers' own controls bound at a handful.
    var _submitted: Dictionary = {}

    ## Whether *holder*, a summoned docker's focus owner, is being typed into.
    ##
    ## Only a field counts: a button a painter clicked keeps the focus too and is
    ## not being typed into. A `TextEdit` holds for as long as it has the
    ## keyboard, since Enter is a newline in it and it has no submission to
    ## announce.
    ##
    ## Watching starts here rather than in the summon, so a field is connected
    ## from the first frame it is asked about and the summon never names a signal
    ## of a control it does not own.
    func holds(holder: Node) -> bool:
        if holder is LineEdit:
            watch(holder)
            return not _submitted.has(holder.get_instance_id())
        return holder is TextEdit

    ## Watches *field* for the end and the resumption of its edit. Connected once
    ## in the field's life: the callbacks carry the field itself, so a later
    ## frame finds the first connection and returns, and the connections end with
    ## the node.
    func watch(field: LineEdit) -> void:
        if field.text_submitted.is_connected(_on_submitted):
            return
        field.text_submitted.connect(_on_submitted.bind(field))
        field.text_changed.connect(_on_typed.bind(field))

    ## Enter in the field: the edit is over, whatever the keyboard still says.
    func _on_submitted(_text: String, field: LineEdit) -> void:
        _submitted[field.get_instance_id()] = true

    ## The painter typed in it again, so the edit is under way once more.
    func _on_typed(_text: String, field: LineEdit) -> void:
        _submitted.erase(field.get_instance_id())
