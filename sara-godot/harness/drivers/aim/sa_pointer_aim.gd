## Where a scenario's pointer is: which window of Sara's own an event goes to,
## the point in that window, and the controls the pointer hovers there.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **With embedded subwindows off every docker is a window of the operating
## system**, and an injected event that names no window is the main window's.
## So a click aimed at a docker's button went to the canvas under it. This
## class is the display server's half of the hand the input driver plays: it
## puts each event where the operating system would have, and keeps the hover
## the operating system's pointer would have kept, because a capture under
## Wayland cannot move that pointer and a button takes a press only while it
## is hovered.
##
## One instance per input driver, because the hover and the window the last
## event went to are the pointer's own state from one step to the next. The
## geometry is static, so a suite asks it without an instance and the driver
## asks it for a point it is about to report.
class_name SaPointerAim
extends RefCounted

## The run, by path like every other harness file this one names.
const CaptureRun := preload("res://harness/sa_capture_run.gd")

## The run whose windows the pointer is aimed at.
var _run: CaptureRun = null

## The controls a window of Sara's own has been told the pointer is over, the
## innermost first, which is the hover [method hover] keeps in place of the
## display server's.
var _hovered: Array[Control] = []

## The window the last pointer event went to, or null for the main window,
## which is where [method aim_again] sends a press that names no point.
var _pointer_window: Window = null

## The node that takes the warp's answers while the door holds a press, made
## by [method _quiet_answers] when the first button goes in.
var _answers: WarpAnswers = null


## Takes the motions the display server makes of [method place]'s warp while
## the door holds a press, before the canvas hears them.
##
## **Windows answers a warp with a motion of its own**, to the warped point at
## no pressure and with no button held, since no real button is down. Inside a
## door stroke at pressure 1, which the cursor reads as a mouse and so keeps
## the warp for, the stamp brush has already read a pen from the 1, and laid
## each answer as the pen at no pressure. The stroke came out as a sawtooth
## that fell to nothing every 50 pixels and died before its end. A motion
## with no button held cannot be the door's while its press is down, because
## the door's motions carry the mask `Input` keeps, so this takes exactly the
## answers and leaves a painter's own hand alone, whose motions carry the
## buttons the hand holds.
class WarpAnswers:
    extends Node

    ## The motions the last press of the door's heard, kept for the state
    ## dump's `door_pointer` block, at most this many.
    const KEPT: int = 64

    ## Every motion the root heard during the door's last press, the frame, the
    ## point, the pressure, the buttons and whose it was, `door` or `answer`,
    ## the first [constant KEPT] of them. Static so the state report reads it
    ## without the driver, and written here only.
    static var heard: Array[Dictionary] = []
    ## The answers taken during the door's last press.
    static var taken: int = 0

    ## Whether a press of the door's is down, from the press to its release.
    var _held: bool = false

    ## Notes a press or a release of the door's, and starts the account of a
    ## press afresh.
    func follow(button: InputEventMouseButton) -> void:
        _held = button.pressed
        if button.pressed:
            heard = []
            taken = 0

    func _input(event: InputEvent) -> void:
        var motion := event as InputEventMouseMotion
        if not _held or motion == null:
            return
        var answer := motion.button_mask == 0 and motion.pressure == 0.0
        if heard.size() < KEPT:
            var at := [snappedf(motion.position.x, 0.01), snappedf(motion.position.y, 0.01)]
            var source := "answer" if answer else "door"
            var line := {"frame": Engine.get_process_frames(), "at": at, "pressure": motion.pressure}
            line["buttons"] = motion.button_mask
            line["source"] = source
            heard.append(line)
        if not answer:
            return
        taken += 1
        get_viewport().set_input_as_handled()

    ## The dump's `door_pointer` block.
    static func report() -> Dictionary:
        return {"answers_taken": taken, "motions": heard}


func _init(run: CaptureRun) -> void:
    _run = run


## Moves the system pointer to *at*, in the main window's space, unless a pen
## holds a press.
##
## **On Windows a warp is answered**. The display server sees
## the pointer move and reports it as a mouse motion of its own to the same
## point, at zero pressure since no real button is down. Inside a stroke that
## is a pen lift after every injected motion, and the brush ramps each segment
## up from nothing, so a stroke that is solid under Wayland, which refuses the
## warp, comes out in dashes on Windows. While
## [member SaCursorPolicy.pointer_is_tablet] holds, the tool, the ring and a
## docker drag read the pen's own events and not the system pointer,
## so the warp buys nothing there. A press that reads as a mouse, at exactly
## pressure 1.0 and no tilt, keeps it, because the tool then asks that pointer.
static func place(at: Vector2) -> void:
    if Input.get_mouse_button_mask() != 0 and SaCursorPolicy.pointer_is_tablet:
        return
    Input.warp_mouse(at)


## The environment variable that plays Windows' answer to the warp on a
## desktop that refuses it, `SARA_ANSWER_WARP=1`.
const ANSWER_WARP_ENV := "SARA_ANSWER_WARP"

## Whether [method answer] plays Windows' answer, read once from
## [constant ANSWER_WARP_ENV]. Public so a suite turns it on and off.
static var answer_warp: bool = OS.get_environment(ANSWER_WARP_ENV) == "1"


## Sends what Windows sends after [method place] warped the pointer under a
## held button, when [member answer_warp] is on: a motion of the display
## server's own to *sent*'s point, at no pressure and with no button held,
## since no real button is down. Called right after *sent* went in, which is
## the order Windows delivers the two in, the answer read in the next poll.
## Under Wayland the warp is refused and nothing answers, so a stroke solid on
## Linux came out in dashes on Windows, and this is how a Linux run reads the
## Windows fault.
static func answer(sent: InputEventMouseMotion) -> void:
    if not answer_warp or Input.get_mouse_button_mask() == 0 or SaCursorPolicy.pointer_is_tablet:
        return
    var echo := sent.duplicate() as InputEventMouseMotion
    echo.pressure = 0.0
    echo.tilt = Vector2.ZERO
    echo.pen_inverted = false
    echo.button_mask = 0
    echo.relative = Vector2.ZERO
    echo.velocity = Vector2.ZERO
    Input.parse_input_event(echo)
    Input.flush_buffered_events()


## Places *event*, a pointer event aimed at *at* in root units, the way the
## display server would have placed it for a hand at that point: its window and
## its position in that window. Returns the window of Sara's own it went to, or
## null for the main window. *named* is the window a named control stands in,
## which wins over the one [method window_under] finds while it is still shown
## and still a window of its own.
##
## **A docker that is a window of its own is not reached through the main
## window**. With embedded subwindows off every docker is a window of the
## operating system, and an event that names no window is the main window's, so
## a click aimed at a docker's button painted a dab on the canvas under it.
## The event carries the docker's window id instead, and `Input` hands it to
## that window's own callback, which is the path a real click takes. `Input`
## rather than `Window.push_input`, so the button mask `Input` keeps is the
## hand's and the next motion's `button_mask` reads it: a drag that starts in a
## docker stays a drag in it.
func aim(event: InputEventMouse, at: Vector2, named: Window = null) -> Window:
    var root := _run.tree().root
    var own := is_instance_valid(named) and named.visible and not named.is_embedded()
    var target := named if own else window_under(root, at)
    var physical := physical_in(root, target, at)
    event.position = physical
    event.global_position = physical
    if target != null:
        event.window_id = target.get_window_id()
        # A press is what hands a window the keyboard, on every desktop Sara
        # runs on. A compositor may refuse, and the headless weston always
        # does, which is the limit [method address_key] states.
        if event is InputEventMouseButton and event.pressed and not target.has_focus():
            target.grab_focus()
    hover(target, at)
    _pointer_window = target
    var button := event as InputEventMouseButton
    if button != null:
        var answers := _quiet_answers(root)
        if answers != null:
            answers.follow(button)
    return target


## The node that keeps the display server's answers to the warp off the canvas
## while a press of the door's is held, put in the root window the first time
## a button goes in, [class WarpAnswers], or null before the first frame.
##
## Before that frame the root is still readying its children and refuses one,
## which is where a suite of `run_all.gd` runs (pitfalls/capture.md). No warp
## has been answered by then, so the node is made at the first press after it.
func _quiet_answers(root: Window) -> WarpAnswers:
    if not is_instance_valid(_answers):
        if Engine.get_process_frames() == 0:
            return null
        _answers = WarpAnswers.new()
        _answers.name = "SaDoorWarpAnswers"
        root.add_child(_answers)
    # Last among the root's children, so its `_input` is heard before the
    # canvas's, which runs a stroke from that call.
    root.move_child(_answers, -1)
    return _answers


## Places *event* at *at* in the window the last event went to, for a press or
## release that names no point of its own and so means the pointer where the
## step before it left it.
func aim_again(event: InputEventMouse, at: Vector2) -> Window:
    return aim(event, at, _pointer_window)


## Addresses *event*, a key step's, to the window of Sara's own that has the
## keyboard, and leaves it with the main window when none has.
##
## The display server sends a key to the window that has the keyboard, and a
## window of its own has it only when the compositor gave it. So this asks the
## window rather than remembering which one was last clicked: a desktop that
## hands a clicked docker the keyboard sends it the step's keys, and one that
## does not, the headless weston among them, leaves them with the main
## window.
static func address_key(root: Window, event: InputEventKey) -> void:
    for window in SaCursorPolicy.windows_of_their_own(root):
        if window.has_focus():
            event.window_id = window.get_window_id()
            return


## Tells the controls under *at* in *target* the pointer is over them, and the
## ones it has left that it has, as the display server's pointer would.
##
## **A button in a window of its own ignored a press the pointer never
## hovered.** A `BaseButton` takes a mouse press only while it is hovered, and
## with subwindows off the engine reads the hover of every window from the
## display server's own pointer, which a capture cannot move under Wayland and
## which no injected event carries. So the click reached the lock button's
## window and the button in it, and the button did nothing. The main window is
## left to the engine, which hovers it from the events themselves while it
## embeds, and a point on it only ends the hover this kept.
func hover(target: Window, at: Vector2) -> void:
    var now: Array[Control] = []
    if target != null:
        var under := control_under(target, local_in(_run.tree().root, target, at))
        while under != null:
            if under.mouse_filter != Control.MOUSE_FILTER_IGNORE:
                now.append(under)
            under = under.get_parent() as Control
    for control in _hovered:
        if is_instance_valid(control) and not control in now:
            control.notification(Control.NOTIFICATION_MOUSE_EXIT)
    for control in now:
        if not control in _hovered:
            control.notification(Control.NOTIFICATION_MOUSE_ENTER)
    _hovered = now


## The innermost visible control of *window* whose rect holds *local*, a point
## in the window's own units, the one the engine's own hit test would find, or
## null when the point is on none. A control that ignores the mouse is passed
## over for what is under it, and a later sibling is drawn over an earlier one.
static func control_under(window: Window, local: Vector2) -> Control:
    for index in range(window.get_child_count() - 1, -1, -1):
        var found := _control_under(window.get_child(index), local)
        if found != null:
            return found
    return null


static func _control_under(node: Node, local: Vector2) -> Control:
    var control := node as Control
    if control == null or not control.is_visible_in_tree():
        return null
    if not control.get_global_rect().has_point(local):
        return null
    for index in range(control.get_child_count() - 1, -1, -1):
        var inner := _control_under(control.get_child(index), local)
        if inner != null:
            return inner
    return null if control.mouse_filter == Control.MOUSE_FILTER_IGNORE else control


## The topmost visible window of Sara's own whose rect in *root* holds *at*, a
## point in root units, or null when none does and the point is the main
## window's.
##
## The windows are the ones the cursor package walks: windows of the operating
## system, not embedded ones, which the main window reaches itself. A later
## window in the walk was shown over an earlier one, and a popup stands over
## every window that is not one, the order the cursor package keeps. The rect
## is the one `rect_in` measures from the window's place as the engine knows
## it, so under a nested compositor that put the window somewhere else the
## point still resolves to the window [method root_point_of] measured it in.
##
## **With *embedded* the windows the main window embeds count as well**, under
## every window of the operating system, because that is where they are drawn.
## [method aim] leaves it off, since an embedded window is reached through the
## main window and an event addressed to it would go nowhere. A click's report
## turns it on, or a point on a dialog reads "in main" and a click on the
## dialog cannot be told from one on the canvas.
static func window_under(root: Window, at: Vector2, embedded: bool = false) -> Window:
    var found: Window = null
    for window in SaCursorPolicy.windows_of_their_own(root):
        if not SaCursorPolicy.rect_in(root, window).has_point(at):
            continue
        if found is Popup and not (window is Popup):
            continue
        found = window
    if found != null or not embedded:
        return found
    # Bottom to top, the order the main window stacks them in and hit tests a
    # press against, so the last that holds the point is the one drawn there.
    for window in root.get_embedded_subwindows():
        if Rect2(Vector2(window.position), Vector2(window.size)).has_point(at):
            found = window
    return found


## *at*, a point in root units, in *window*'s own units, whether *window* is
## embedded or a window of its own, the point the control under it is found
## at. The inverse of the arithmetic `SaInputDriver.control_point` aims a
## named control in an embedded window with.
static func point_in(root: Window, window: Window, at: Vector2) -> Vector2:
    if window != null and window.is_embedded():
        return window.get_final_transform().affine_inverse() * (at - Vector2(window.position))
    return local_in(root, window, at)


## *at*, a point in root units, in *window*'s own units, or *at* itself when
## *window* is null or the main window.
static func local_in(root: Window, window: Window, at: Vector2) -> Vector2:
    if window == null or window == root:
        return at
    var rect := SaCursorPolicy.rect_in(root, window)
    var local := at - rect.position
    var size := window.get_visible_rect().size
    if rect.size.x > 0.0 and rect.size.y > 0.0:
        local *= size / rect.size
    return local


## *at*, a point in root units, as the physical point *window* reads it, or as
## the main window reads it when *window* is null.
##
## An event pushed in from outside is un-scaled on the way in, so it has to be
## handed over pre-multiplied or a 2x display halves it, and a move that is not
## lands at half the coordinates it asks for, which on a 2x display is the whole
## difference between a scenario's pointer and where it meant to put it. A window of its own is un-scaled by
## its own transform and not the main window's.
static func physical_in(root: Window, window: Window, at: Vector2) -> Vector2:
    var into := root if window == null else window
    return into.get_final_transform() * local_in(root, window, at)


## *local*, a point in *window*'s own units, as a point in *root*'s, the
## inverse of [method local_in]. What lets a step name a control inside a
## docker that is a window of its own and aim at a point that lands back on
## that control.
static func root_point_of(root: Window, window: Window, local: Vector2) -> Vector2:
    var rect := SaCursorPolicy.rect_in(root, window)
    var size := window.get_visible_rect().size
    if size.x <= 0.0 or size.y <= 0.0:
        return rect.position + local
    return rect.position + local * (rect.size / size)


## The name a click's report gives the window a point lands on: the title a
## painter reads and the node's name a step's `in` takes, or `main`.
static func window_label(target: Window) -> String:
    if target == null:
        return "main"
    if target.title.is_empty():
        return String(target.name)
    return '"%s" (%s)' % [target.title, target.name]
