## What a scenario's hand does to the running app: the pointer, the mouse
## buttons and the keyboard.
##
## One instance per run, holding the runner it drives, because nearly everything
## here reads or writes the runner's live state: [member SaCapture.last_pointer]
## is what a `press` without an `at` aims at, and the physical transform an
## event has to be pre-multiplied by comes off the runner's own window.
##
## **Aiming is here because pressing is.** [method point_of] turns a step's `at`
## or `control` into a point, and the only reason anything wants that point is
## to put an event on it, so the two live together rather than in a class that
## answers questions nobody acts on.
##
## Reached by path from the runner rather than by class name, so no editor
## rescan stands between a fresh checkout and a step.
class_name SaInputDriver
extends RefCounted

## The run, by path like every other harness file this one names.
const CaptureRun := preload("res://harness/sa_capture_run.gd")

## The pointer's aim, by path for the reason the run is.
const PointerAim := preload("res://harness/drivers/aim/sa_pointer_aim.gd")

## The run this drives for: its tree, the pointer it last aimed at, which this
## writes on every move it injects (f13), and the tool a click changes.
var _run: CaptureRun = null

## Which window each pointer event goes to, and the hover kept there.
var _aim: SaPointerAim = null

## The window of Sara's own the control the last step named stands in, or null,
## written by [method point_of]. A name says which window it means where a point
## cannot, because a nested compositor stands every let-out docker at its origin.
var _named: Window = null


func _init(run: CaptureRun) -> void:
    _run = run
    _aim = PointerAim.new(run)


## The call the warp probe moves the pointer with, `Input.warp_mouse` in
## everything but a suite, which counts the calls to prove a door moves no
## painter's pointer before anyone asked it to.
## Test seam. A suite that replaces it puts `Input.warp_mouse` back.
static var warp: Callable = Input.warp_mouse


## Whether this platform lets the app place the pointer.
##
## Wayland generally refuses. Recorded once rather than guessed at, because a
## screenshot taken after a failed warp shows the cursor wherever the user's hand
## left it and silently means nothing. Returned rather than written through the
## capture, the way `wheel` returns the point it aimed at.
static func probe_pointer_warp(window: Window) -> bool:
    var before := DisplayServer.mouse_get_position()
    var target := before + Vector2i(7, 5)
    warp.call(window.get_screen_transform().affine_inverse() * Vector2(target))
    return DisplayServer.mouse_get_position() != before


## Runs the probe for *run* once, the first time anything asks, and leaves its
## answer in the run's `pointer_warp_works`.
##
## **Asked for, never run by itself.** A door is a capture with no scenario,
## and a probe on its first frame past the settle would move a painter's
## pointer as soon as Modules › Local Server opened. So the probe runs at a scenario's
## settle, where the scenario is about to place the pointer anyway, and in a
## door at its first injected motion, the moment the pointer was going to move
## for a reason the client gave.
static func know_the_warp(run: CaptureRun, window: Window) -> void:
    if run.pointer_warp_probed or window == null:
        return
    run.pointer_warp_works = probe_pointer_warp(window)
    run.pointer_warp_probed = true


## Moves the pointer: it moves first, then injects a matching motion event.
##
## Both halves are needed: the warp is what the CursorOverlay reads (it samples
## DisplayServer.mouse_get_position()), and the event is what makes it redraw.
##
## Accepts `[x, y]` or `{"at": [x, y], "pressure": p, "tilt": [x, y]}`. The pen
## telemetry is not decoration: the brush decides mouse-versus-tablet from it, and
## a tablet stroke reported at zero pressure paints at zero alpha. See the `stroke`
## step for why that mattered.
##
## **And `{"control": "Name"}`, the way `click` takes one**. The two steps read
## their point through the same [method point_of], because a `move` that looked
## for `at` alone would leave the pointer where the step before it put it and
## hover whatever was last under it, and a step that does nothing silently is
## worse than one that refuses: the run goes on to shoot, dump and pass.
func move_pointer(raw: Variant) -> void:
    var spec: Dictionary = raw if typeof(raw) == TYPE_DICTIONARY else {"at": raw}
    var found: Variant = point_of(spec)
    if found == null:
        return
    var pos: Vector2 = found
    var pressure := float(spec.get("pressure", 0.0))
    var tilt_raw := spec.get("tilt", [0, 0]) as Array
    var tilt := Vector2(float(tilt_raw[0]), float(tilt_raw[1])) if tilt_raw.size() >= 2 else Vector2.ZERO
    _inject_motion(pos, pressure, tilt, bool(spec.get("inverted", false)), _named)


## Injects motions in one frame: every point as its own `InputEventMouseMotion`,
## all inside the one process step this runs in, `{"motion_burst": [[x1, y1],
## [x2, y2], ...]}`. `move` and a `stroke`'s own points are each spaced a frame
## apart by the runner's own step loop, one call to `_run_step` per `_process`,
## which is exactly what this has to not do to answer whether several hardware
## samples inside one real frame all reach the tool.
##
## An entry may also be a dictionary in the `move` shape, `{"at": [x, y],
## "pressure": p, "tilt": [x, y], "inverted": b}`, mixed freely with bare
## pairs in the same burst. A bare pair carries no telemetry and still
## injects pressure 0, which is what stopped a burst from ever proving a
## tablet's pressure reaches the brush. A dictionary's `made_usec` is when the
## pen made the report, and the motion goes in with the pen's clock
## [method SaPenClock.held] at it, which is how a stroke's `rate` gives each
## report of a burst its own time.
func motion_burst(raw: Variant) -> void:
    var points := raw as Array
    if points == null:
        return
    for entry: Variant in points:
        if entry is Dictionary:
            var parsed: Variant = burst_entry_motion(entry)
            if parsed != null:
                var found: Dictionary = parsed
                var send := _inject_motion.bind(found["pos"], found["pressure"], found["tilt"], found["inverted"], null)
                if (entry as Dictionary).has("made_usec"):
                    SaPenClock.held(int(entry["made_usec"]), send)
                else:
                    send.call()
            continue
        var coords := entry as Array
        if coords == null or coords.size() < 2:
            continue
        _inject_motion(Vector2(float(coords[0]), float(coords[1])))


## Sends a pen motion to a window: a named one, at a point in its own space, with
## the system pointer left where it was, `{"pen_in": {"window": "LayersDocker",
## "at": [x, y], "tilt": [x, y]}}`. `"android": true` reads the pen from here on
## as Android's port has to be read, gone once quiet.
##
## The way Windows Ink delivers a pen. The window under the pen gets the event
## and the display server goes on reporting the mouse, which is what a `move`
## cannot show, because it warps the pointer and injects into the main window.
## A window of its own is reached the same way as an embedded one, and the point
## is local, so the window's scale is not applied to it a second time.
func pen_in(raw: Variant) -> void:
    var spec := raw as Dictionary
    var window := CaptureRun.DockerLookup.named(_run.tree().root, String(spec.get("window", ""))) as Window
    var coords := spec.get("at", []) as Array
    if window == null or coords.size() < 2:
        print("SaCapture: pen_in found no window %s or no point" % spec.get("window", ""))
        return
    var tilt := spec.get("tilt", [0.2, -0.1]) as Array
    SaCursorPolicy.pen_silence_means_gone = SaCursorPolicy.pen_silence_means_gone or bool(spec.get("android", false))
    var motion := InputEventMouseMotion.new()
    motion.position = Vector2(float(coords[0]), float(coords[1]))
    motion.global_position = motion.position
    motion.tilt = Vector2(float(tilt[0]), float(tilt[1]))
    motion.pressure = float(spec.get("pressure", 0.0))
    window.push_input(motion, true)
    print("SaCapture: pen_in %s at %s, embedded=%s" % [window.name, motion.position, window.is_embedded()])


## Tells a window the pointer left: the word the display server sends a window
## of its own, and it sends no motion anywhere after it, `{"pointer_left":
## "main"}` or `{"pointer_left": "LayersDocker"}`. `main` is the main window.
##
## The way Windows Ink leaves a pen that crosses onto a docker without the
## focus. Godot 4.7 tells the window the pen left, and parses the pen's hover
## over the docker only while the docker has the focus, so no `pen_in` follows.
## Handed to every node of the window and to none inside a window of its own
## within it, which is how the engine hands `NOTIFICATION_WM_MOUSE_EXIT` on.
func pointer_left(name: String) -> void:
    var root := _run.tree().root
    var window := root if name == "main" else CaptureRun.DockerLookup.named(root, name) as Window
    if window == null:
        print("SaCapture: pointer_left found no window %s" % name)
        return
    _tell_the_window(window, Node.NOTIFICATION_WM_MOUSE_EXIT)
    print("SaCapture: pointer_left %s, embedded=%s" % [window.name, window.is_embedded()])


## Stops listening to the system's mouse: `{"lock_cursor": "lesson 3"}`, the
## words the status line's tooltip names the holder by, or
## `{"lock_cursor": true}` for a client with no name. Only the door's hand moves
## the pointer then, and the system's pen is not listened to either.
##
## For a lesson where the painter and a script both work, and a press of the
## painter's in the middle of the script's drag would end it. Every mouse, pen
## and touchpad event the operating system sends is dropped before a tool or a
## widget hears it, and the door's own `move`, `click`, `stroke` and the rest
## go on as before. Touch and the keyboard are left alone. The status line says
## the mouse is locked. It holds until `unlock_cursor`, until the door closes,
## and until no request has come for the door's idle timeout, which is how a
## notebook that went away looks to the door, since a notebook hangs up between
## its calls. [class SaPointerLock] says how the system's events are told from
## the door's.
func lock_cursor(raw: Variant) -> void:
    var by := String(raw) if raw is String and not String(raw).is_empty() else "an agent"
    SaCursorPolicy.lock_system_pointer(by)
    print("SaCapture: lock_cursor held for %s, the system's mouse and pen are not listened to" % by)


## Listens to the system's mouse again: `{"unlock_cursor": true}` after
## `lock_cursor`, and the pen with it, and says how many of their events the
## lock dropped. Nothing happens when no lock is held, and the line says so.
func unlock_cursor(_raw: Variant) -> void:
    if not SaCursorPolicy.system_pointer_locked:
        print("SaCapture: unlock_cursor found no lock held")
        return
    var dropped := SaCursorPolicy.unlock_system_pointer()
    print("SaCapture: unlock_cursor let go, %d events of the system's dropped while it held" % dropped)


## *what* to *node* and every node below it short of another window, the walk
## the engine's `Window._propagate_window_notification` makes.
static func _tell_the_window(node: Node, what: int) -> void:
    node.notification(what)
    for child in node.get_children(true):
        if not child is Window:
            _tell_the_window(child, what)


## The point, pressure, tilt and inverted flag one `motion_burst` entry names
## in the `move` dictionary shape, or `null` when it names no usable point.
##
## Split out of the loop above so the shape can be asserted without
## dispatching an event or needing a window, the way `button_event` is:
## an injected motion is delivered on the next input flush rather than inside
## the call that queues it, so a suite that never processes a frame never
## sees one arrive.
static func burst_entry_motion(spec: Dictionary) -> Variant:
    var coords := spec.get("at", []) as Array
    if coords == null or coords.size() < 2:
        return null
    var pressure := float(spec.get("pressure", 0.0))
    var tilt_raw := spec.get("tilt", [0, 0]) as Array
    var tilt := Vector2(float(tilt_raw[0]), float(tilt_raw[1])) if tilt_raw.size() >= 2 else Vector2.ZERO
    return {
        "pos": Vector2(float(coords[0]), float(coords[1])),
        "pressure": pressure,
        "tilt": tilt,
        "inverted": bool(spec.get("inverted", false)),
    }


## One motion event at *pos*, carrying the pen telemetry a real tablet would send.
## *named* is the window of Sara's own a named control stands in, the window
## the motion goes to whatever else is at the point.
func _inject_motion(
    pos: Vector2, pressure: float = 0.0, tilt: Vector2 = Vector2.ZERO, inverted: bool = false, named: Window = null
) -> void:
    know_the_warp(_run, _run.tree().root if _run.tree() != null else null)
    PointerAim.place(pos)

    var motion := InputEventMouseMotion.new()
    var target := _aim.aim(motion, pos, named)
    motion.relative = motion.position - PointerAim.physical_in(_run.tree().root, target, _run.last_pointer)
    motion.pressure = pressure
    motion.tilt = tilt
    # The eraser end of the pen, which is what flips the brush to erasing.
    motion.pen_inverted = inverted
    # The buttons the hand holds, as a real pointer reports them. A drag with none
    # reads as a hover, `DockerFocus` hands a hover's docker the subwindow focus,
    # and the engine would then give that docker the drag's release.
    motion.button_mask = Input.get_mouse_button_mask()
    motion.shift_pressed = Input.is_key_pressed(KEY_SHIFT)
    _run.last_pointer = pos
    Input.parse_input_event(motion)
    Input.flush_buffered_events()
    PointerAim.answer(motion)


## Where a pointer step is aiming: the `at` point, or the centre of the control
## `control` names. Null when the step named neither, or named a control nothing
## answers to, and both are said out loud.
##
## **A point is only right until a row is added above the control.** Two slider
## rows put into the colour picker's column move its hex box 25 units, and a
## scenario clicking by point then clicks below it and dumps what that click
## produced as if it were the box's. A name resolves at run time and cannot go
## stale that way.
##
## **A name that two surfaces answer to resolves to the docker's copy**,
## and `in` narrows it to one node's subtree when the step means the other copy:
## `{"click": {"control": "RadiusSlider", "in": "CustomTitleBar"}}`.
##
## Returned as a `Variant` rather than as a `Vector2`, because "nowhere" has to be
## tellable from the origin: a click at (0, 0) is a real point on the canvas.
func point_of(spec: Dictionary) -> Variant:
    _named = null
    if spec.has("control"):
        return control_point(String(spec["control"]), String(spec.get("in", "")), spec.get("within", [0.5, 0.5]) as Array)
    var coords := spec.get("at", []) as Array
    if coords == null or coords.size() < 2:
        push_warning("SaCapture: a pointer step needs an 'at' point or a 'control'")
        return null
    return Vector2(float(coords[0]), float(coords[1]))


## The centre of the drawn rect of the control called *name*, in root units.
##
## A control inside an embedded docker measures from its own window's corner, so
## the window's position is added, which is the same arithmetic `drag_window`
## does, so no scenario aiming at a docker does it by hand. The point goes through the window's own scale first, or a docker
## maximised at a quarter again is aimed at a fifth short of every control.
## Reported either way, so a run says what it aimed at rather than leaving a
## reader to work out whether a click landed.
##
## The first candidate that is a Control a painter can see is the one aimed at,
## which is `_run.nodes_named`'s order: a docker's copy before the top bar's.
## A name nothing answers to and a name whose control is not drawn are
## different sentences, because they send a reader to different places.
func control_point(name: String, in_node: String = "", within: Array = [0.5, 0.5]) -> Variant:
    var root := _run.tree().root
    var node: Control = null
    var any_control := false
    for candidate in _run.nodes_named(root, name, in_node):
        var control := candidate as Control
        if control == null:
            continue
        any_control = true
        if control.is_visible_in_tree():
            node = control
            break
    if node == null:
        var why := "nothing draws" if any_control else "nothing is called"
        print("SaCapture: click failed, %s '%s'" % [why, name])
        push_error("SaCapture: click failed, %s '%s'" % [why, name])
        return null
    var rect := node.get_global_rect()
    # `"within": [0.25, 0.5]` aims at that fraction of the rect, the middle
    # unless a step says, so a scenario presses one region of an icon.
    var at := rect.position + rect.size * Vector2(float(within[0]), float(within[1]))
    var window := node.get_window()
    if window != null and window != root and window.is_embedded():
        at = Vector2(window.position) + window.get_final_transform() * at
    elif window != null and window != root:
        at = PointerAim.root_point_of(root, window, at)
        _named = window
    print("SaCapture: '%s' is at (%d, %d), %d by %d" % [name, at.x, at.y, rect.size.x, rect.size.y])
    return at


## Clicks at a point: a full press-release, optionally with ALT, Shift or Ctrl
## held as [method button_event] reads them for a press, and a report of what it
## did to the active tool. Shift was dropped, so a Shift click painted a dot.
##
## ALT + click on a docker is supposed to move the docker and nothing else. The
## thing that made it wrong is invisible from a screenshot: the click reached the
## button underneath as well, so the tool changed. `{"click": {"at": [x, y],
## "alt": true}}` answers that directly.
##
## It cannot check that the docker moved, because the drag reads the real pointer
## and Wayland will not let a client put it anywhere.
##
## `{"click": {"control": "HexInput"}}` aims at a control by name instead of by a
## point, which is what stops a click going stale.
##
## **The line names the window the point lands on and what the press did
## there**, embedded or a window of its own, and a click on a dialog that
## pressed nothing is an error, which a door's answer carries in `errors`.
## The line also names each dialog the press opened, because a boot with two
## recovery copies asks its question twice in the same place, and a click that
## answered the first reads as one that did nothing unless the client sees that
## the question in front of it is a second one.
func click(spec: Dictionary) -> void:
    var found: Variant = point_of(spec)
    if found == null:
        return
    var at: Vector2 = found
    var named := _named
    var held := " ALT" if bool(spec.get("alt", false)) else ""
    held += " SHIFT" if bool(spec.get("shift", false)) else ""
    var before: String = _run.active_tool_name()
    var root := _run.tree().root

    _run.last_pointer = at

    var landing: Landing = null
    for pressed: bool in [true, false]:
        var event := button_event(spec, "left", pressed)
        var target := _aim.aim(event, at, named)
        if pressed:
            # Read before the press, because a button that answers a question
            # takes its window off the screen.
            landing = Landing.new(root, at, target)
        Input.parse_input_event(event)
        Input.flush_buffered_events()
    # Nothing waits in the app, which turns accumulated input off and so has
    # every injected event delivered inside the call that parses it. A suite
    # runs before that, and this is what delivers the press there too.
    Input.flush_buffered_events()
    landing.settle(root)

    print(
        (
            "SaCapture: click%s at (%d, %d) in %s%s  tool %s -> %s"
            % [
                held if not held.is_empty() else "    ",
                at.x,
                at.y,
                PointerAim.window_label(landing.window),
                landing.said(),
                before,
                _run.active_tool_name()
            ]
        )
    )
    if landing.pressed_nothing():
        push_error(landing.error())


## What a click landed on and what its press did there, read before the press
## and again once it is done. A class rather than the click's own locals,
## because the line and the error both read all of it.
class Landing:
    extends RefCounted

    ## The window of Sara's own the point is on, embedded or a window of its
    ## own, or null for the main window.
    var window: Window = null

    ## The control under the point in that window, or null.
    var control: Control = null

    ## Whether the button under the point emitted `pressed`.
    var pressed_it: bool = false

    ## The dialogs of Sara's own the press opened, which is how a second
    ## recovery question in the first one's place is told from the first.
    var opened: Array[Window] = []

    var _dialogs_before: Array[Window] = []

    func _init(root: Window, at: Vector2, target: Window) -> void:
        window = target if target != null else PointerAim.window_under(root, at, true)
        if window != null:
            control = PointerAim.control_under(window, PointerAim.point_in(root, window, at))
        _dialogs_before = Landing.dialogs_up(root)
        # A method rather than a lambda, which would hold this object and be
        # held by it, and the pair would outlive the click.
        if control is BaseButton:
            (control as BaseButton).pressed.connect(_heard)

    ## Stops listening, and takes the dialogs that are up now and were not.
    func settle(root: Window) -> void:
        var button := control as BaseButton
        if is_instance_valid(button) and button.pressed.is_connected(_heard):
            button.pressed.disconnect(_heard)
        for dialog in Landing.dialogs_up(root):
            if not dialog in _dialogs_before:
                opened.append(dialog)

    func _heard() -> void:
        pressed_it = true

    ## The part of the click's line between the window and the tool: the
    ## button it pressed or did not, the control it landed on, and each
    ## dialog the press opened.
    func said() -> String:
        var line := ""
        if control is BaseButton:
            var label := Landing.label_of(control)
            line = ", pressed '%s'" % label if pressed_it else ", pressed nothing on '%s'" % label
        elif control != null:
            line = ", on %s" % control.name
        for dialog in opened:
            line += ", then %s opened" % PointerAim.window_label(dialog)
        return line

    ## Whether the click landed on a dialog and pressed nothing there.
    func pressed_nothing() -> bool:
        return window is SaDialogWindow and not pressed_it and not Landing.takes_a_click(control)

    ## The error a click on a dialog that pressed nothing raises: the dialog by
    ## its title, what the point was on, and for a message window the step that
    ## answers it and the button that route presses.
    func error() -> String:
        var on := "on no button"
        if control is BaseButton:
            var disabled := " and it is disabled" if (control as BaseButton).disabled else ""
            on = "on '%s'%s" % [Landing.label_of(control), disabled]
        var line := 'SaCapture: click in "%s" (%s) pressed nothing, %s' % [window.title, window.name, on]
        var message := window as SaMessage
        if message == null:
            return line
        line += ', and {"message": {"close": "escape"}} answers it'
        if message.cancel_index >= 0 and message.cancel_index < message.buttons.size():
            line += " with '%s'" % message.buttons[message.cancel_index].text
        return line

    ## Every dialog of Sara's own on screen, embedded or a window of its own.
    static func dialogs_up(root: Window) -> Array[Window]:
        var up: Array[Window] = []
        for embedded in root.get_embedded_subwindows():
            if embedded is SaDialogWindow:
                up.append(embedded)
        for own in SaCursorPolicy.windows_of_their_own(root):
            if own is SaDialogWindow:
                up.append(own)
        return up

    ## Whether *under* takes a click that presses no button: a field, a slider
    ## or a text a painter selects, any control a click hands the keyboard to,
    ## and a control that reads the press itself, a list's row or a dialog's
    ## title bar. A container, a label and a dialog's bare chrome take none,
    ## and a click there is one that missed a button.
    static func takes_a_click(under: Control) -> bool:
        if not is_instance_valid(under) or under is BaseButton:
            return false
        if under is SpinBox or under.focus_mode != Control.FOCUS_NONE or not under.gui_input.get_connections().is_empty():
            return true
        var script := under.get_script() as Script
        if script == null:
            return false
        for method: Dictionary in script.get_script_method_list():
            if method["name"] == "_gui_input":
                return true
        return false

    ## What a painter reads on *shown*, its text where it has one, else its
    ## name.
    static func label_of(shown: Control) -> String:
        var button := shown as Button
        if button != null and not button.text.is_empty():
            return button.text
        return String(shown.name)


## Presses or releases a button at a point the scenario chose.
##
## *raw* is `"left"` or `{"button": "left", "at": [x, y], "shift": true}`. Without
## an `at` this uses wherever the last `move` aimed, which is the sequence a stroke
## writes. A modifier is on the press because that is where it decides what a
## drag means: shift plus a horizontal drag resizes the brush instead of painting,
## and no other step can reach that gesture.
##
## **`alt` and `ctrl` are read the same way `shift` is**, so the whole chord
## the selection mode option documents is drivable: `StateMarquee`, `StateLasso`
## and `StateWand` each read `button.shift_pressed` for add and
## `button.alt_pressed` for subtract, and the `click` step takes `alt` as well.
##
## The modifier goes on the mouse event and no key event is sent, which is
## deliberate: Alt is also `tool_eyedropper_quick`, and a scenario asking for an
## alt-drag of the marquee is asking about the marquee. `ToolMachine._held_keys`
## only follows key events, so the quick tool stays where it was.
func mouse_button(raw: Variant, pressed: bool) -> void:
    var spec: Dictionary = raw if typeof(raw) == TYPE_DICTIONARY else {}
    var which := String(spec.get("button", "left")) if not spec.is_empty() else String(raw)
    var event := button_event(spec, which, pressed)
    if spec.has("at") or spec.has("control"):
        var wanted: Variant = point_of(spec)
        if wanted == null:
            return
        _run.last_pointer = wanted
        _aim.aim(event, wanted, _named)
    else:
        _aim.aim_again(event, _run.last_pointer)
    Input.parse_input_event(event)
    Input.flush_buffered_events()


## The event a `press` or `release` step describes, before it is placed.
##
## Out of [method mouse_button] so the step's three modifier keys can be
## asserted without a window, because a key documented and not read is caught
## by an assertion on this mapping and by nothing else.
static func button_event(spec: Dictionary, which: String, pressed: bool) -> InputEventMouseButton:
    var button := MOUSE_BUTTON_LEFT
    if which == "right":
        button = MOUSE_BUTTON_RIGHT
    elif which == "middle":
        button = MOUSE_BUTTON_MIDDLE

    var event := InputEventMouseButton.new()
    event.button_index = button
    event.pressed = pressed
    event.shift_pressed = bool(spec.get("shift", false))
    event.alt_pressed = bool(spec.get("alt", false))
    event.ctrl_pressed = bool(spec.get("ctrl", false))
    event.double_click = pressed and bool(spec.get("double", false))
    return event


## Drags a docker by its title, and reports whether it actually moved.
##
## Events are pushed straight into the docker Window rather than through
## Input.parse_input_event, which separates two questions that otherwise look
## identical from the outside: does the drag logic work, and does input routing
## reach it. `route: true` uses the global path instead, to test the other half.
func drag_window(spec: Dictionary) -> void:
    var title := String(spec.get("window", ""))
    var by := spec.get("by", [40, 40]) as Array
    var delta := Vector2(float(by[0]), float(by[1]))
    var routed := String(spec.get("via", "window")) != "window"

    var target: Window = null
    for window: Window in _run.all_windows(_run.tree().root):
        if window.title == title:
            target = window
            break
    if target == null:
        print("SaCapture: drag target %s not found" % title)
        return

    var handle := target.find_child("DragHandle", true, false) as Control
    if handle == null:
        print("SaCapture: %s has no DragHandle" % title)
        return

    var before := target.position
    # The handle's rect is in its own window's space. Routing through the global
    # input path means the event is hit-tested in the host's space instead, so an
    # embedded docker's offset has to be added or the click lands somewhere else
    # entirely and the drag looks broken when only the test was.
    var start := handle.get_global_rect().get_center()
    if routed and target.is_embedded():
        start += Vector2(target.position)

    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    press.position = start
    press.global_position = start

    var motion := InputEventMouseMotion.new()
    motion.position = start + delta
    motion.global_position = start + delta
    motion.relative = delta

    var release := InputEventMouseButton.new()
    release.button_index = MOUSE_BUTTON_LEFT
    release.pressed = false
    release.position = start + delta
    release.global_position = start + delta

    for event: InputEvent in [press, motion, release]:
        match String(spec.get("via", "window")):
            "input":
                Input.parse_input_event(event)
                Input.flush_buffered_events()
            "root":
                _run.tree().root.push_input(event, true)
            _:
                target.push_input(event, true)

    var moved := target.position - before
    print(
        (
            "SaCapture: drag %s routed=%s handle_at=%s before=%s after=%s moved=%s (wanted %s)"
            % [title, routed, start, before, target.position, moved, delta]
        )
    )


## Presses and releases a key: through the same path a keyboard uses, so a
## scenario can ask what Escape or Ctrl+Q does to the running app.
##
## `{"key": "escape"}`, or `{"key": {"key": "q", "ctrl": true}}` with `shift`
## and `alt` the same way. By default both the keycode and the physical keycode
## are set, because the input map binds by the physical one.
##
## **`shape` picks which of the three fields the event carries**, because a
## keyboard does not always send all of them and an event that sets every field
## proves the chord for a US layout only. `"both"` is the default. `"physical"` leaves the keycode at zero
## and is the shape a layout-independent binding is meant to answer. `"keycode"`
## is the mirror, the character with no position behind it. `"label"` carries
## `key_label` and `unicode` alone, which is what a layout that needs a modifier
## to type the character sends, and it is the shape a Czech keyboard produces
## for a bracket.
## `echo` is the count of OS-repeat events a real held key would send
## between its press and its release, for a scenario that proves a shortcut
## answers a held key rather than a tapped one. `pressed` sends that one
## edge alone rather than the tap, for a key a scenario holds down across
## other steps and lets go of later, such as Space held through a pan drag.
## `char` is the character the key types, `{"key": {"key": "t", "char": "t"}}`,
## for a step whose key must reach a text box as a letter does.
func key(raw: Variant) -> void:
    var spec: Dictionary = raw if raw is Dictionary else {"key": String(raw)}
    # Not capitalized. `OS.find_keycode_from_string` already matches without
    # regard to case, and `capitalize()` puts a space between a letter and a
    # digit, so every spelling of F1 would become `F 1` and resolve to nothing.
    var keycode := OS.find_keycode_from_string(String(spec.get("key", "")))
    if keycode == KEY_NONE:
        push_warning("SaCapture: no key called '%s'" % spec.get("key", ""))
        return
    var shape := String(spec.get("shape", "both"))
    if not shape in ["both", "physical", "keycode", "label"]:
        push_warning("SaCapture: no key shape called '%s'" % shape)
        return
    var echoes := int(spec.get("echo", 0))
    # A held quick tool (Space for pan) needs its key down before a drag and
    # up after it, not the tap every other caller wants, so a step naming
    # `pressed` sends that one edge alone, with no echo and no modifier release,
    # both of which belong to the full press-release tap every other caller asks
    # for.
    var edges: Array = [bool(spec["pressed"])] if spec.has("pressed") else [true, false]
    for pressed: bool in edges:
        var event := InputEventKey.new()
        if shape in ["both", "keycode"]:
            event.keycode = keycode
        if shape in ["both", "physical"]:
            event.physical_keycode = keycode
        if shape == "label":
            event.key_label = keycode
            event.unicode = keycode
        event.unicode = String(spec["char"]).unicode_at(0) if spec.has("char") else event.unicode
        event.pressed = pressed
        event.ctrl_pressed = bool(spec.get("ctrl", false))
        event.shift_pressed = bool(spec.get("shift", false))
        event.alt_pressed = bool(spec.get("alt", false))
        PointerAim.address_key(_run.tree().root, event)
        Input.parse_input_event(event)
        Input.flush_buffered_events()
        if pressed and echoes > 0 and not spec.has("pressed"):
            for _i in echoes:
                var echo_event: InputEventKey = event.duplicate()
                echo_event.echo = true
                Input.parse_input_event(echo_event)
                Input.flush_buffered_events()
    if not spec.has("pressed"):
        _release_modifiers(spec)
    print("SaCapture: key %s  tool in hand %s" % [JSON.stringify(spec), _run.active_tool_name()])


## Hands Sara a controller's message: through the input source registered
## under *source_id*, as its device would. The `midi` step asks the one whose
## id is `midi`, so a scenario turns a knob on a machine with no controller, as
## `key` presses a key on one with no keyboard. The line the step prints is the
## source's answer, and what the spec says and what the line reads are the
## source's own, see [method SaInputSource.simulate]. *sources* is the registry
## asked, the main scene's when none is given, and a suite hands its own.
static func simulate_input(source_id: StringName, spec: Dictionary, sources: SaInputSourceRegistry = null) -> String:
    if sources == null:
        sources = SaInputSourceRegistry.in_app()
    if sources == null:
        return "SaCapture: %s has no app to feed %s" % [source_id, JSON.stringify(spec)]
    return sources.simulate(source_id, spec)


## Lets go of whatever modifiers the step held, as a keyboard does.
##
## A real keyboard sends the modifier's own keyup after the character's, and
## nothing here did. `ToolMachine._update_held_keys` reads the modifier flags off
## every event including the release, so one `{"key": {"alt": true}}` left ALT
## held for the rest of the run, and ALT is `tool_eyedropper_quick`: every step
## after it ran with the eyedropper active whatever the scenario asked for. The
## symptom was a `{"tool": "transform"}` that reported success and changed
## nothing, which is not a symptom anybody would read back to a missing keyup.
func _release_modifiers(spec: Dictionary) -> void:
    for modifier: String in ["ctrl", "shift", "alt"]:
        if not bool(spec.get(modifier, false)):
            continue
        var event := InputEventKey.new()
        event.keycode = {"ctrl": KEY_CTRL, "shift": KEY_SHIFT, "alt": KEY_ALT}[modifier]
        event.physical_keycode = event.keycode
        event.pressed = false
        PointerAim.address_key(_run.tree().root, event)
        Input.parse_input_event(event)
        Input.flush_buffered_events()


## Resizes the main window: to that many logical pixels, so a layout claim can
## be photographed at a width other than 1920, `{"window": [2560, 1440]}`.
##
## Without it every capture is at 1920 by 1080, and a question about another
## width is answered only by arithmetic over a number the app dumped. A step
## rather than a flag, so a scenario carries the width it
## needs and any harness that runs the file reaches the same picture.
##
## **The size a nested compositor gives is the size it has.** A headless weston
## pins a window to its output, so `scripts/sara_shot.py` reads the scenario
## before it starts one and sizes the output to the largest window step in the
## file. The line printed here says what was asked for and what arrived, because
## a resize that did not take must not read as one that did: on a compositor
## that pins it, the two numbers differ and the scenario's own log says so.
##
## Here rather than on the runner, which sits in the window it would resize. The
## root window is that window, and sizing it is what this driver does to it in
## every other step.
func resize_window(size: Array) -> String:
    if size.size() < 2:
        return "SaCapture: window takes [width, height]"
    var wanted := Vector2i(int(size[0]), int(size[1]))
    if wanted.x <= 0 or wanted.y <= 0:
        return "SaCapture: window %s is not a size" % str(wanted)
    var scene_tree := _run.tree()
    var window: Window = scene_tree.root if scene_tree != null else null
    if window == null:
        return "SaCapture: no window to resize"
    var before := window.size
    window.size = wanted
    var got := window.size
    return (
        "SaCapture: window %d x %d -> asked %d x %d, got %d x %d%s"
        % [before.x, before.y, wanted.x, wanted.y, got.x, got.y, "" if got == wanted else "  PINNED"]
    )
