## Which device moves the pointer and where it last was: the tablet flag, the
## pen's last place in the window it was seen in and on the desktop, and the
## one reading of the pointer the display server is asked for.
##
## One of the three parts of the cursor package, private to it. The rest of the
## tree asks [SaCursorPolicy], which forwards here. Names neither of the other
## two parts, since everything else about the pointer is built on this.
##
## The one file under `render`, `ui/main` and `ui/dockers` that asks
## `DisplayServer` where the mouse is, and the one that moves it. Under Windows
## Ink the pen moves the window's events and not that pointer, so a reader that
## asks the display server itself paints and opens dockers where the mouse was
## left. A suite answers for the display server through
## [member suite_pointer].
class_name SaPointerDevice
extends RefCounted

## Whether the last thing to move the pointer was a tablet tool rather than a
## mouse, and how many plain motions have arrived since one said otherwise.
##
## Godot's Wayland driver reports every pointer as device 0, so there is no
## device to ask. The heuristic is the one `state_brush.gd` uses: a pen almost
## always reports a pressure, a tilt or the inverted flag, and ten motions in a
## row with none of the three is a mouse. It lives here as well because the
## cursor has to answer for the whole window and not only for a stroke in
## progress, and because a module tool cannot be the authority for the
## skeleton's own chrome. Whether a tablet tool is what is moving the pointer.
##
## False until something proves otherwise, so a build that never sees a pen
## behaves exactly as one with no pen support would.
static var pointer_is_tablet: bool = false
static var _plain_motion_streak: int = 0

## Whether the press the pointer is in the middle of began at the pressure a
## driver makes up for a mouse, and whether the last motion was pressed at all,
## which is how the first pressed motion of a press is told from the rest.
static var _press_is_made_up: bool = false
static var _last_motion_pressed: bool = false

## Whether the pen's tip is down: a motion carried the pen's own pressure and no
## left release has come since, nor a run of plain motions long enough to hand
## the pointer to the mouse.
##
## **While it is down, a motion with no pressure and no tilt is not the pen.**
## Under Windows Ink Godot 4.7 answers the pen's own messages as handled, so the
## system pointer stays where it was, and a let-out docker the pen drags moves
## under it. Windows tells a window that moved under the pointer that the
## pointer moved, and the driver builds that `WM_MOUSEMOVE` with a pressure only
## for a left button the system knows is down, which a pen press it never saw is
## not. Kept as the pen's, it would put many steps of the drag back on the
## system pointer's place, near where the drag began.
static var _pen_pressed: bool = false

## Where the pen was last seen and in which window, which is where the pointer
## is while `pointer_is_tablet` holds. Under XWayland a pen moves the window's
## events and not the X pointer that `DisplayServer.mouse_get_position` reads,
## so a ring read from the query stands still while the pen paints and shows
## only while the shift drag pins it. Under Wayland the query is the last event
## anyway, so reading the event is the same answer there and the right one
## under X11.
static var _pen_window: Window = null
static var _pen_position: Vector2 = Vector2.ZERO

## The same place in desktop pixels, taken when the motion arrived. Kept rather
## than worked out again when asked, because a docker dragged by the pen moves
## the window the position was measured in, and the old position read through
## the new window is a pointer that runs away with the drag. Null while no pen
## has been seen in a window in the tree.
static var _pen_desktop: Variant = null

## Whether the place above was kept from a left press that came while no pen
## was known, and no motion has arrived since. Until one does, that press is
## where the pointer is, whatever device made it.
static var _place_from_press: bool = false

## Whether the window the pen's place was kept in has said the pointer left it,
## and no motion or press of the pen has come since.
##
## Windows Ink tells a window of its own about a pen's hover only while that
## window has the focus. Godot 4.7's `WM_POINTERUPDATE` parses the motion for
## the focused window or an open popup and drops it for every other, and answers
## the message as handled either way, so the system makes no mouse motion of it
## either. What it does send first, focused or not, is the window event that
## says the pointer went from one window to the other. So a pen that crosses
## from the canvas onto a let-out docker leaves no motion anywhere, and the
## place kept above is its last one on the canvas beside the docker's edge,
## where the ring would stay. WinTab moves the system pointer, whose motion over
## the docker Godot hands to the focused window, so there the place moves on.
static var _pen_left: bool = false

## How long a pen with its tip up may send nothing before it counts as gone,
## two seconds. A pen held still in range may send nothing either, and the
## engine opens a tooltip only once the pointer has rested half a second, so the
## quiet is long enough to read a tooltip by and short enough that a ring left
## behind is gone before the painter looks for it.
const PEN_SILENCE_USEC: int = 2000000

## When the pen's place was last kept, in `Time.get_ticks_usec`.
static var _pen_heard_usec: int = 0

## Whether the focus follows the pen from one window of Sara's to the next: the
## pen last pressed in a window that is not the main one. A press in the main
## window, or one by the mouse, puts it down. [method hands_the_focus] says why.
static var _focus_follows_pen: bool = false

## Where the ring's reader says the pen is while it has left its window: outside
## every window's visible rectangle, which is how [method SaCursorRing.pointer_in_window]
## already answers for no window at all.
const NOWHERE: Vector2 = Vector2(-1.0, -1.0)

## Where a suite says the mouse is, in desktop pixels, or null when the display
## server's pointer is the answer, which is every run that is not a suite's.
##
## The shape of the docker drag handle's `capture_pointer`, for every reader in
## this file. A suite cannot put the live pointer where its events say on every
## desktop: a parsed event moves it under Wayland alone, a warp only where the
## driver lets it, and on a Windows desktop neither does, so a suite reads the
## pointer wherever the desktop has it. Set, it stands in for
## `DisplayServer.mouse_get_position` and for Godot's own reading through a
## window or a Control, carried into the space asked the way the pen's desktop
## place is. A pen still comes first, as it does over the display server. A
## SubViewport has no desktop place to carry it into and keeps Godot's answer,
## which is the last event it was handed and never the system pointer. The suite
## that sets it clears it in `after_each`.
static var suite_pointer: Variant = null

## How many plain motions in a row it takes to call the pointer a mouse again.
const MOUSE_MOTION_STREAK: int = 10

## How far from the place asked for `DisplayServer.warp_mouse` puts the pointer,
## in desktop pixels, measured by the last warp that landed wrong. It is the
## client corner of the window Godot warps from, which a script cannot name.
static var _warp_offset: Vector2i = Vector2i.ZERO

## The pen's buttons held back from a window that had no control under the pen,
## in the window's own pixels and in the order they came, and the window.
## [method carry_system_pointer] says why.
static var _held: Array[InputEventMouseButton] = []
static var _held_window: Window = null
## Which hold the timer that ends it belongs to, so an old timer ends no new one.
static var _hold_serial: int = 0
## How many held buttons are on their way back, each let through when it comes.
static var _resending: int = 0
## The longest a button is held when no motion comes to say the window found
## the control under the pen.
const HOLD_SECONDS: float = 0.2
## Where a held button goes when it is sent again. A suite catches it here,
## because a button it parsed would reach whatever suite runs after it.
static var send_again: Callable = Input.parse_input_event
## How many warps it may take to put the pointer on the pen.
const WARP_TRIES: int = 3

## The pressure a driver gives a mouse motion while the left button is down.
## Godot's Windows driver writes it for every `WM_MOUSEMOVE` under Windows Ink,
## and its X11 driver for a device that reports no pressure, and neither writes
## a tilt or the inverted flag with it. A pen's reading is a fraction of its
## driver's range, so a press that starts at exactly this is a mouse's.
const MADE_UP_PRESSURE: float = 1.0


## Records what kind of device sent *event*, for `pointer_is_tablet`.
##
## Fed from `CursorOverlay._input`, which is the one place that sees every motion
## in a window whether or not it is over a canvas. Reads the event and never
## consumes it.
##
## A pressure is a pen's only when the press it belongs to did not begin at
## `MADE_UP_PRESSURE`. Under Windows Ink a mouse drag carries that pressure on
## every motion, so reading any pressure as a pen would keep the flag up for a
## mouse that has clicked once, and the streak would never count. Tilt and the
## inverted flag stay evidence on their own, because no driver makes either up.
##
## A motion with neither pressure nor tilt while the pen's tip is down counts
## towards the streak and does nothing else, which `_pen_pressed` says the
## reason for.
static func note_pointer_device(event: InputEvent, window: Window = null) -> void:
    var motion := event as InputEventMouseMotion
    if motion == null:
        # A pen's tip coming down is a button event on Windows Ink and X11
        # alike, at a place no motion has reported yet. It says nothing of the
        # device, but a stroke that begins on it must begin where it landed.
        #
        # **A press with no pen known is kept as well, until the next motion.**
        # When a pen's hovers stop arriving, or a mouse moved last, its press
        # comes with the flag down, and a tool reading the display server's
        # pointer would start where the mouse was left under Windows Ink and run
        # the stroke from there to the pen. For a mouse the press is where the
        # display server says anyway.
        var button := event as InputEventMouseButton
        if button == null:
            return
        if button.button_index == MOUSE_BUTTON_LEFT and not button.pressed:
            _pen_pressed = false
        if button.pressed:
            _focus_follows_pen = pointer_is_tablet and window != null and not _is_main_window(window)
        if not (pointer_is_tablet or button.pressed):
            return
        _keep_pen_place(button.position, window)
        _place_from_press = not pointer_is_tablet
        return
    _place_from_press = false
    var pressed := motion.pressure > 0.0
    var tilted := motion.tilt != Vector2.ZERO or motion.pen_inverted
    if _pen_pressed and not pressed and not tilted:
        # Counted as any plain motion is, so a release that never came cannot
        # hold a mouse's place on the pen's for longer than the streak. The
        # press it would break into is the pen's and is left as it stands.
        _count_plain_motion()
        return
    if pressed and not _last_motion_pressed:
        _press_is_made_up = motion.pressure == MADE_UP_PRESSURE
    _last_motion_pressed = pressed
    var pen_pressure := pressed and not _press_is_made_up
    if pen_pressure:
        _pen_pressed = true
    if pen_pressure or tilted:
        pointer_is_tablet = true
        _plain_motion_streak = 0
    else:
        _count_plain_motion()
    # A hover with no pressure is still the pen until the streak says otherwise,
    # so its position is kept the same as a pressed motion's.
    if pointer_is_tablet:
        _keep_pen_place(motion.position, window)


## Takes the system pointer to the pen when *event* was the pen's own, in
## *window*, under Windows Ink.
##
## **Godot 4.7 answers Windows Ink's pen messages as handled**, so Windows makes
## no mouse move of them and the system pointer stays where the mouse left it.
## Windows then tells the window under that pointer that the mouse moved or left
## there: a docker the pen hovers gets a plain motion at the mouse's place after
## every one of the pen's, and loses the control under the pen. A tap with the
## pen in a docker presses nothing, and the system pointer stands apart from
## Sara's ring. WinTab moves the system pointer itself, and
## no other display server lets a program move it, so this is for Windows Ink
## alone.
##
## `DisplayServer.warp_mouse` places the pointer from the client corner of the
## focused window or the open popup, so a warp that lands away from the pen
## measures that corner from where it landed and warps again. The corner is kept
## for the warps after it. The place is the one [method note_pointer_device] kept
## from *event*, so a plain motion that did not move the pen moves nothing.
##
## **A tap on a docker that was not focused is held until the docker finds the
## control under the pen.** Godot reads Ink's hovers in the focused window only,
## so the docker has seen no motion and Godot's buttons press only for a pointer
## that has hovered them. The press gives the docker focus, so the next update
## of the pen resting on the glass comes to it and finds the control. The press
## and any release behind it are sent again then, or after
## [constant HOLD_SECONDS] without such a motion.
static func carry_system_pointer(event: InputEvent, window: Window) -> void:
    var mouse := event as InputEventMouse
    if mouse == null or window == null:
        return
    if OS.get_name() != "Windows" or DisplayServer.tablet_get_current_driver() != "winink":
        return
    if _held_back(mouse, window):
        return
    if not pointer_is_tablet or _pen_left or window != _pen_window:
        return
    if _pen_desktop == null or mouse.position != _pen_position:
        return
    var desktop: Vector2 = _pen_desktop
    var wanted := Vector2i(desktop.round())
    # A few tries, because the corner moves between two warps into a docker
    # that has just taken focus.
    for _try in WARP_TRIES:
        var landed := DisplayServer.mouse_get_position()
        if landed == wanted:
            break
        if _try > 0:
            _warp_offset += landed - wanted
        DisplayServer.warp_mouse(wanted - _warp_offset)
    _hold_unhovered_press(mouse, window)


## Holds *mouse* when it is a press in *window* that has no control under it.
static func _hold_unhovered_press(mouse: InputEventMouse, window: Window) -> void:
    var button := mouse as InputEventMouseButton
    if button == null or not button.pressed or window.gui_get_hovered_control() != null:
        return
    _held = [_unlocal(button, window)]
    _held_window = window
    _hold_serial += 1
    var serial := _hold_serial
    window.set_input_as_handled()
    var tree := Engine.get_main_loop() as SceneTree
    tree.create_timer(HOLD_SECONDS).timeout.connect(func() -> void: _send_held(serial))


## Whether *mouse* in *window* is a held button coming back, which passes, or one
## more for the hold, which is kept. A motion in the held window that found a
## control sends the hold.
static func _held_back(mouse: InputEventMouse, window: Window) -> bool:
    var button := mouse as InputEventMouseButton
    if button != null and _resending > 0:
        _resending -= 1
        return true
    if _held_window == null or window != _held_window:
        return false
    if button != null:
        _held.append(_unlocal(button, window))
        window.set_input_as_handled()
        return true
    if window.gui_get_hovered_control() != null:
        # Deferred, because Godot's Windows driver drops an event parsed while it
        # is handing one out. The window stays held until then, so a release in
        # the same frame waits behind its press.
        var serial := _hold_serial
        (func() -> void: _send_held(serial)).call_deferred()
    return false


## Sends the held buttons again, unless hold *serial* has already been sent.
static func _send_held(serial: int) -> void:
    if serial != _hold_serial or _held.is_empty():
        return
    var held := _held
    _held = []
    _held_window = null
    _resending += held.size()
    for button in held:
        send_again.call(button)


## *button* as *window* had it from the display server, before the window made
## it its own, so the window takes it the same way when it comes again.
static func _unlocal(button: InputEventMouseButton, window: Window) -> InputEventMouseButton:
    var raw := button.xformed_by(window.get_final_transform()) as InputEventMouseButton
    raw.global_position = raw.position
    return raw


## One more plain motion in a row, which past the streak hands the pointer to
## the mouse and lets go of a pen press nobody released.
static func _count_plain_motion() -> void:
    _plain_motion_streak += 1
    if _plain_motion_streak > MOUSE_MOTION_STREAK:
        pointer_is_tablet = false
        _pen_pressed = false


## Records that *window* has said the pointer left it, which is the engine's
## `NOTIFICATION_WM_MOUSE_EXIT` and comes only to a window of its own.
##
## Fed from `CursorOverlay._notification`. It counts while the pen is the
## pointer and its place was kept in *window*, and not while the pen is pressed:
## a stroke's motions keep coming to the window it began in, under Ink's capture
## of a pen in contact and under the mouse capture Godot takes for WinTab and a
## mouse, so the place a stroke reads is never the stale one this is about.
static func note_pointer_left(window: Window) -> void:
    if window == null or window != _pen_window or not pointer_is_tablet or _last_motion_pressed:
        return
    _pen_left = true


## Records that the pen has gone out of range when it has sent nothing to
## *window* for [constant PEN_SILENCE_USEC] up to *now_usec* while
## *quiet_means_gone*, and answers whether it did so just now,
## which is when the window's hover and tooltip have to be let go as well.
##
## Fed once a frame from `CursorOverlay._process`. Never while the tip or a left
## button is down, because a pen pressed and held still sends nothing either
## and is still on the canvas. The next motion or press of the pen brings it
## back, as it does after [method note_pointer_left].
static func note_pen_silence(window: Window, now_usec: int, quiet_means_gone: bool) -> bool:
    if not quiet_means_gone or _pen_left or not pointer_is_tablet:
        return false
    if window == null or window != _pen_window:
        return false
    if _pen_pressed or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
        return false
    if now_usec - _pen_heard_usec < PEN_SILENCE_USEC:
        return false
    _pen_left = true
    return true


## Gives *window* the focus when the pen has come over it and
## [method hands_the_focus] says the focus follows the pen there, under Windows
## Ink alone. *window* said so with the engine's `NOTIFICATION_WM_MOUSE_ENTER`,
## which comes only to a window of its own and, under Ink, from the pen's first
## update over it whether or not it has the focus.
static func note_pointer_entered(window: Window) -> void:
    if OS.get_name() != "Windows" or DisplayServer.tablet_get_current_driver() != "winink":
        return
    var holder: Window = _pen_window if is_instance_valid(_pen_window) else null
    if hands_the_focus(window, holder, holder != null and holder.has_focus()):
        window.grab_focus()


## Whether the pen coming over *window* takes the focus to it from *holder*, the
## window the pen was last seen in, which has the focus when *holder_focused*.
##
## **After a pick in a let-out docker the pen is heard nowhere else.** Godot
## reads Ink's updates in the focused window alone, [member _pen_left] says how,
## and the press of the pick gives the docker the focus. Over Tool Options, and
## over the canvas on the way there, the pen sends nothing, so no pointer is
## drawn there and the system pointer [method carry_system_pointer] moves stays
## where the pen left the docker. So from a press in a window that is not the
## main one the focus follows the pen from window to window, and the pen's next
## update is heard where it is.
##
## **Until the pen presses in the main window**, which keeps the focus it took
## then, rather than a docker taking the focus whenever the pen comes over it,
## which would take the keyboard from the canvas at every pass. Here the
## keyboard has already left the canvas with the press in the docker, and the
## pen coming back over the canvas brings it back.
##
## Never into a list, which Godot hears open or not, nor out of one or out of a
## window that holds the others off. Never while the focus is in a text field,
## so a painter typing a value with the pen resting elsewhere keeps the keys.
static func hands_the_focus(window: Window, holder: Window, holder_focused: bool) -> bool:
    if not (pointer_is_tablet and _focus_follows_pen and holder_focused):
        return false
    if window == null or holder == null or window == holder or window.has_focus():
        return false
    if window is Popup or holder is Popup or holder.exclusive:
        return false
    var typing := holder.gui_get_focus_owner()
    return not (typing is LineEdit or typing is TextEdit)


## Whether *window* is the main one, which a pen press keeps the focus in.
static func _is_main_window(window: Window) -> bool:
    return window != null and window.is_inside_tree() and window == window.get_tree().root


static func _keep_pen_place(position: Vector2, window: Window) -> void:
    if window == null:
        return
    _pen_left = false
    _pen_window = window
    _pen_position = position
    _pen_heard_usec = Time.get_ticks_usec()
    var to_desktop: Variant = desktop_transform(window)
    _pen_desktop = null
    if to_desktop != null:
        var desktop: Transform2D = to_desktop
        _pen_desktop = desktop * position


## Forgets what device was last seen, for a test that needs a known start.
static func forget_pointer_device() -> void:
    pointer_is_tablet = false
    _plain_motion_streak = 0
    _press_is_made_up = false
    _last_motion_pressed = false
    _pen_pressed = false
    _pen_window = null
    _pen_desktop = null
    _place_from_press = false
    _pen_left = false
    _pen_heard_usec = 0
    _focus_follows_pen = false
    _held = []
    _held_window = null
    _resending = 0


## Where the pointer is in *space*'s own coordinates: a Control's local space, a
## Viewport's, or desktop pixels when *space* is null, which is the space a
## window of its own is placed in.
##
## The reader for everything that is not the ring. Under Windows Ink the pen
## moves the events and not the pointer the display server reports, so a tool,
## a summoned docker and a docker drag that asked the display server got where
## the mouse was left. While a pen moves the pointer this answers from the pen's
## last event, carried from its window to the one asked about. A mouse, and a
## space the pen cannot be carried into, keep Godot's answer. The pin is the
## ring's and not asked, because a tool reads the hand's travel.
static func pointer_in(space: Object = null) -> Vector2:
    var pen: Variant = _pen_in(space)
    if pen is Vector2:
        return pen
    var placed: Variant = _placed_in(space)
    if placed is Vector2:
        return placed
    var control := space as Control
    if control != null:
        return control.get_local_mouse_position() if control.is_inside_tree() else Vector2.ZERO
    var viewport := space as Viewport
    if viewport != null:
        return viewport.get_mouse_position()
    return Vector2(DisplayServer.mouse_get_position())


## The system pointer on the desktop whatever the pen did, or [member
## suite_pointer] when a suite set one. WinTab's driver carries it with the pen.
static func system_pointer() -> Vector2:
    return suite_pointer if suite_pointer is Vector2 else Vector2(DisplayServer.mouse_get_position())


## The pointer in *window*'s viewport space, with no pin asked: the pen's last
## place carried into *window* while a pen moves the pointer, and the display
## server's pointer otherwise.
##
## The ring's reader, which [method SaCursorRing.pointer_in_window] puts the pin
## in front of. It asks the display server rather than the viewport as
## [method pointer_in] does, because the ring has to be answered for a window
## the pointer is outside of, and a viewport only knows the pointer while it is
## inside.
##
## **A pen that has left its window is in none**, [constant NOWHERE], until its
## next motion or press says where it went. Its last place is where it crossed
## out, beside a docker's edge on the canvas, and the display server's pointer
## is where the mouse was left, so either answer draws a ring the pen is not
## at. The tool readers keep the last place, since a summon or a drag wants a
## point and the next press gives the true one before a stroke reads it.
static func in_window(window: Window) -> Vector2:
    if pointer_is_tablet and _pen_left:
        return NOWHERE
    var pen: Variant = _pen_in(window)
    if pen is Vector2:
        return pen
    var placed: Variant = _placed_in(window)
    if placed is Vector2:
        return placed
    var to_desktop: Variant = desktop_transform(window)
    if to_desktop == null:
        return window.get_screen_transform().affine_inverse() * Vector2(DisplayServer.mouse_get_position())
    var desktop: Transform2D = to_desktop
    return desktop.affine_inverse() * Vector2(DisplayServer.mouse_get_position())


## The pen's last place in *space*, or null when the pen is not what moves the
## pointer or there is no way to carry its place into *space*.
static func _pen_in(space: Object) -> Variant:
    if not (pointer_is_tablet or _place_from_press) or not is_instance_valid(_pen_window):
        return null
    var control := space as Control
    if control != null:
        if not control.is_inside_tree():
            return null
        var in_viewport: Variant = _pen_in(control.get_viewport())
        if in_viewport == null:
            return null
        var place: Vector2 = in_viewport
        return control.get_global_transform_with_canvas().affine_inverse() * place
    if space != null and space == _pen_window:
        return _pen_position
    if _pen_desktop == null:
        return null
    var desktop: Vector2 = _pen_desktop
    return _from_desktop(desktop, space)


## The suite's place for the mouse in *space*, or null while no suite set one or
## there is no way to carry it into *space*.
static func _placed_in(space: Object) -> Variant:
    if not suite_pointer is Vector2:
        return null
    var placed: Vector2 = suite_pointer
    var control := space as Control
    if control == null:
        return _from_desktop(placed, space)
    if not control.is_inside_tree():
        return null
    var in_viewport: Variant = _from_desktop(placed, control.get_viewport())
    if in_viewport == null:
        return null
    var place: Vector2 = in_viewport
    return control.get_global_transform_with_canvas().affine_inverse() * place


## *desktop*, a place in desktop pixels, in *space*'s own coordinates: itself
## for no space and through its desktop transform for a window. Null for a
## SubViewport, which has no desktop place of its own to measure against and
## keeps Godot's answer.
static func _from_desktop(desktop: Vector2, space: Object) -> Variant:
    if space == null:
        return desktop
    var to_desktop: Variant = desktop_transform(space as Window)
    if to_desktop == null:
        return null
    var transform: Transform2D = to_desktop
    return transform.affine_inverse() * desktop


## From *window*'s viewport space to desktop pixels, or null for a window that
## is not in the tree or is embedded somewhere other than a window.
##
## `Viewport.get_screen_transform` stops at the window of its own, whose place
## on the desktop it leaves out, so that window's position is put back here.
## Every embedded window between is already in it.
static func desktop_transform(window: Window) -> Variant:
    if window == null or not window.is_inside_tree():
        return null
    var outer := window
    while outer.is_embedded():
        var parent := outer.get_parent()
        var host := parent.get_viewport() as Window if parent != null else null
        if host == null:
            return null
        outer = host
    return Transform2D(0.0, Vector2(outer.position)) * window.get_screen_transform()
