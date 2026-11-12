## The keyboard follows the pointer between the dockers and the main window.
##
## A docker takes the focus when the pointer enters it, and the main window
## takes it back when the pointer leaves the docker for the canvas, so a
## shortcut always reaches whatever the pointer is over, as in Krita.
##
## Two engine rules make this more than a preference. An embedded window is
## handed the motion under the pointer only while it holds the subwindow focus,
## and a tooltip's timer is started from that motion, so without this a docker
## nobody had clicked shows no tooltip at all. And the only thing that moves the
## subwindow focus is a left press, so a painter who painted a stroke and then
## hovers the Colour Picker to remember what a swatch is gets nothing until they
## click into the docker.
##
## The root window's `window_input` is where this listens, because it fires
## before the viewport routes the event, so the focus has already moved when the
## engine decides whose motion it is, and the same motion that crosses the edge
## starts the tooltip's timer.
##
## A docker that comes to hold the pointer without the pointer crossing its edge,
## shown by Tab, opened from a menu or a chord, moved or resized under it, stands
## off until the pointer has stayed in it for [constant DWELL_MSEC], has left it
## and come back, or presses in it. Without that the first twitch of a
## resting hand gave it the keyboard, and the next shortcut went to the docker.
class_name DockerFocus
extends Node

## How long a pointer stays inside a docker that appeared under it before the
## docker takes the keyboard.
const DWELL_MSEC := 600

## The window the dockers are embedded in, once [method watch] has been handed it.
var _host: Window = null

## Answers whether a docker is one the focus should not follow the pointer into,
## `(window: Window) -> bool`. A docker summoned under the pointer is under the
## pointer by construction and takes no focus, so `MainDockers` hands the
## summon's own question in here.
## Empty answers false for every docker.
var _stands_off: Callable = Callable()

## Which docker appeared under the pointer and since when, read off the motions.
var _arrival: Arrival = null


func _init(stands_off: Callable = Callable(), dwell_msec: int = DWELL_MSEC) -> void:
    name = "DockerFocus"
    _stands_off = stands_off
    _arrival = Arrival.new(dwell_msec)


## Listens to *host*. Safe to call again, which `MainDockers` does on every
## rebuild of its menu.
func watch(host: Window) -> void:
    if host == null or host == _host:
        return
    if _host != null and _host.window_input.is_connected(_on_host_input):
        _host.window_input.disconnect(_on_host_input)
    _host = host
    host.window_input.connect(_on_host_input)


## A motion with no button held moves the focus to whatever is under it.
##
## A held button leaves the focus where it is. A drag belongs to the window it
## started in, whether that is a slider pulled past the docker's edge, a docker
## moved by its bar or a stroke that wanders over a docker, and moving the focus
## under it would hand the rest of the drag to somebody else. A pen in contact
## reports the left button, so a stroke is one of those drags.
func _on_host_input(raw: InputEvent) -> void:
    if _host == null or not _host.is_inside_tree():
        return
    var press := raw as InputEventMouseButton
    if press != null and press.pressed:
        _arrival.pressed()
        return
    var motion := raw as InputEventMouseMotion
    if motion == null or motion.button_mask != 0:
        return
    # The event as the window received it, before the viewport un-scales it, the
    # same arithmetic `MainDockers._focus_docker_under_press` does.
    var at: Vector2 = _host.get_final_transform().affine_inverse() * motion.position
    var stack: Array[Window] = []
    stack.assign(_host.get_embedded_subwindows())
    _arrival.note(window_under(stack, at), at, Time.get_ticks_msec())
    _settle(stack, at)


## Looks once a frame at what the resting pointer is over.
##
## Tab showing the dockers again, a docker opened from a menu or a chord, or a
## layout switched sends no motion, so a docker that appears under a pointer at
## rest is only seen by looking. The same look lifts the stand-off once the dwell
## is over, which a pointer at rest would otherwise never do.
func _process(_delta: float) -> void:
    if _host == null or not _host.is_inside_tree() or not _arrival._seen:
        return
    var stack: Array[Window] = []
    stack.assign(_host.get_embedded_subwindows())
    var before := _arrival._appeared
    var held := Input.get_mouse_button_mask() != 0
    _arrival.look(window_under(stack, _arrival._last_at), not held, Time.get_ticks_msec())
    if before != 0 and _arrival._appeared == 0 and not held:
        _settle(stack, _arrival._last_at)


## Moves the focus to where the pointer at *at* says it belongs.
func _settle(stack: Array[Window], at: Vector2) -> void:
    var focused := focused_of(stack)
    var target := follow(stack, focused, at, _stands_off, _arrival.stands_off)
    if target == focused:
        return
    if target == null:
        release(focused)
    else:
        target.grab_focus()


## The embedded window of *stack* holding the subwindow focus, or null when no
## embedded window does and the main window has it.
static func focused_of(stack: Array[Window]) -> Window:
    for window in stack:
        if window.has_focus():
            return window
    return null


## Which window should hold the focus with the pointer at *at*: a docker, null for
## the main window, or *focused* itself when nothing should move. Free of node
## state so a test can ask it, because a `Window` outside the tree cannot be
## given the focus.
##
## Only a docker gives the focus up or takes it. A popup, a menu or a dialog that
## holds it keeps it wherever the pointer goes, because a popup closes when it
## loses the focus and a painter reading a dropdown's list over a docker would
## lose the list. A window that is not a docker, under the pointer while a docker
## holds the focus, leaves the focus with that docker, because nothing here says
## where the keyboard should go instead.
##
## A docker *stands_off* answers true for is passed over the same way: the focus
## stays where it was while the pointer is inside it, so a summoned docker is
## read with the keyboard still on the canvas, and a click inside it takes the
## focus the ordinary way. Once it has the focus it keeps it wherever the pointer
## goes, because the leave timer waits while a field holds focus, which needs
## a field that stays focused after the pointer has left, and the rule
## above would have taken it the moment the pointer crossed the canvas.
##
## A docker *appeared* answers true for, `(window: Window) -> bool`, came under
## the pointer without the pointer crossing its edge, and while the pointer is
## inside it the main window holds the keyboard, taken from any other docker
## that had it, because the next shortcut belongs to the canvas until the
## pointer has stayed. Tab showing the dockers again hands one of them the
## subwindow focus on its own, and that docker is seldom the one under the
## pointer. Once the docker that appeared holds the focus it gives it up as any
## docker does.
static func follow(
    stack: Array[Window], focused: Window, at: Vector2, stands_off: Callable = Callable(), appeared: Callable = Callable()
) -> Window:
    if focused != null and not (focused is DockerWindow):
        return focused
    if focused != null and stands_off.is_valid() and bool(stands_off.call(focused)):
        return focused
    var under := window_under(stack, at)
    if under == null:
        return null
    if under == focused:
        return focused
    if not (under is DockerWindow):
        return focused
    if stands_off.is_valid() and bool(stands_off.call(under)):
        return focused
    if appeared.is_valid() and bool(appeared.call(under)):
        return null
    return under


## The topmost window of *stack* whose rectangle holds *at*, in the host
## viewport's logical units, or null.
##
## Topmost is the last of *stack* that holds the point, because
## `Viewport.get_embedded_subwindows` returns the embedder's own array, which is
## the stacking order a left press is tested in. A window the pointer passes
## through is skipped, and a tooltip's panel is one: the engine builds it
## unfocusable and passthrough, and a docker's tooltip hanging over the canvas
## would otherwise keep the focus in the docker for as long as it showed.
static func window_under(stack: Array[Window], at: Vector2) -> Window:
    for i in range(stack.size() - 1, -1, -1):
        var window := stack[i]
        if not window.visible or window.mouse_passthrough:
            continue
        if Rect2(Vector2(window.position), Vector2(window.size)).has_point(at):
            return window
    return null


## Hands the focus from *docker* back to the main window.
##
## The engine does this on a left press outside every subwindow and offers no
## call for it: `Window.grab_focus` on the root only raises the OS window.
## What it does offer is its rule for an
## unfocusable window, which releases whatever focus is held and grants none, so
## the docker is unfocusable for the length of one `grab_focus`. That grab also
## raises the docker, which is already on top unless another docker was opened
## while it held the focus, and then it goes back above that one.
##
## One difference from the press, and nothing in Sara reads it: the engine's own
## release sends the root a focus-in, and this sends none. `Main` listens for the
## root's focus-out alone.
static func release(docker: Window) -> void:
    if docker == null:
        return
    docker.unfocusable = true
    docker.grab_focus()
    docker.unfocusable = false


## Which docker came under the pointer without the pointer crossing its edge,
## and how long the pointer has stayed in it.
##
## Two ways tell it. A look at the resting pointer finds a docker under it that
## was not under it at the look before, with no motion between, so the docker
## was shown, opened, moved or resized there. And a motion that first finds a
## docker under the pointer, while the motion before it lay inside that docker's
## rectangle as it stands now, met a docker that arrived since. A motion that
## came from outside the rectangle crossed its edge. Free of node state but for
## the windows it is handed, so a suite reads it over detached windows with a
## clock of its own.
class Arrival:
    extends RefCounted

    ## How long the pointer stays inside before the stand-off lifts.
    var _dwell_msec: int = DWELL_MSEC

    ## Where the last motion with no button held was, in the host's logical units.
    var _last_at := Vector2.ZERO

    ## Whether there has been a motion at all, because before the first there is
    ## no pointer to be at rest under anything.
    var _seen := false

    ## The instance id of the window under the pointer at the last motion or
    ## look, 0 for none.
    var _last_under := 0

    ## The instance id of the docker standing off, 0 for none.
    var _appeared := 0

    ## When it arrived under the pointer, in ticks.
    var _since := 0

    func _init(dwell: int = DWELL_MSEC) -> void:
        _dwell_msec = dwell

    ## A motion to *at*, with *under* the window it is over, at *now* ticks.
    func note(under: Window, at: Vector2, now: int) -> void:
        var id := _id_of(under)
        if id != _appeared:
            # The pointer left it, so coming back is a crossing like any other.
            _appeared = 0
        if under is DockerWindow and id != _last_under and _seen and _rect_of(under).has_point(_last_at):
            _arrive(id, now)
        _lapse(now)
        _last_at = at
        _last_under = id
        _seen = true

    ## A look with the pointer resting at the last motion, *under* the window
    ## over it now. *may_arrive* is false while a button is held, because a
    ## drag moves a docker with the pointer and that is no arrival.
    func look(under: Window, may_arrive: bool, now: int) -> void:
        var id := _id_of(under)
        if id != _appeared:
            _appeared = 0
        if may_arrive and under is DockerWindow and id != _last_under and _seen:
            _arrive(id, now)
        _lapse(now)
        _last_under = id

    ## A press anywhere, which takes the focus the engine's own way.
    func pressed() -> void:
        _appeared = 0

    ## The answer `follow` takes as *appeared*.
    func stands_off(window: Window) -> bool:
        return window != null and _appeared != 0 and window.get_instance_id() == _appeared

    func _arrive(id: int, now: int) -> void:
        _appeared = id
        _since = now

    ## Lifts the stand-off once the pointer has stayed its dwell.
    func _lapse(now: int) -> void:
        if _appeared != 0 and now - _since >= _dwell_msec:
            _appeared = 0

    static func _id_of(window: Window) -> int:
        return window.get_instance_id() if window != null else 0

    static func _rect_of(window: Window) -> Rect2:
        return Rect2(Vector2(window.position), Vector2(window.size))
