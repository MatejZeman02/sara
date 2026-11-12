## Where the pointer is, what is drawn in its place, and when the OS cursor is
## hidden. The facade of the cursor package, and the one name the rest of the
## tree calls.
##
## Apart from `render/sa_canvas.gd`, because none of this is about displaying
## a texture, and everything in it is a process-wide policy rather than a
## property of one view.
##
## The package answers three questions that share nothing but a name, one
## class each. [SaPointerDevice] says which device moves the pointer and where
## it last was, and is the one file that asks the display server. [SaCursorRing]
## says how the ring is sized and pinned and what owns the pixel under the
## pointer. This file says what is drawn in the pointer's place on each display
## driver, the OS cursor's visibility and the tool's own picture among it, and
## forwards the other two, so a caller names this file alone. [SaPointerLock]
## says whether the system's mouse and pen are listened to at all, which an
## client turns off from the door, and is forwarded the same way.
##
## `SaCanvas` keeps no forwarder for any name below: the canvas is the file the
## painter's own input goes through, and a forwarder there gives a reader a
## longer file and one more name to hold.
##
## The one rule the whole package exists to keep: **the OS cursor is hidden
## only while a replacement is certainly drawn, decided in the same tick as the
## drawing.** Hiding it process-wide behind one overlay that reparents itself
## into whatever window is under the pointer is the obvious design, and closing
## a transient window takes that overlay with it and leaves no pointer at all
## for the rest of the session.
##
## "Certainly drawn" has a second half, and it is the same rule read outwards: a
## window of its own stands over this one, so a cursor drawn in this one is not
## certainly drawn there. With `embed_subwindows` off every docker is such a
## window, and a ring claimed for the canvas a docker covers would hide the OS
## cursor for a replacement nobody can see.
class_name SaCursorPolicy
extends RefCounted

## Whether a tablet tool is what is moving the pointer, read off
## [member SaPointerDevice.pointer_is_tablet], which alone writes it.
static var pointer_is_tablet: bool:
    get:
        return SaPointerDevice.pointer_is_tablet

## Whether a client holds the lock on the system's mouse and pen, read off
## [member SaPointerLock.held], which alone writes it.
static var system_pointer_locked: bool:
    get:
        return SaPointerLock.held

## How many plain motions in a row it takes to call the pointer a mouse again.
const MOUSE_MOTION_STREAK: int = SaPointerDevice.MOUSE_MOTION_STREAK

## The pressure a driver gives a mouse motion while the left button is down.
const MADE_UP_PRESSURE: float = SaPointerDevice.MADE_UP_PRESSURE

## What `DisplayServer.get_name()` answers under the driver whose tablet cursor
## is missing. Capitalised the way the server spells it, which is not the way the
## `--display-driver` flag does.
const WAYLAND_DRIVER: String = "Wayland"
## The name Godot's Android display server answers to.
const ANDROID_DRIVER: String = "Android"

## What `SaSettings.software_cursor` may hold, and what the Tablet page's row
## calls each one. The list lives here rather than on the page or in the
## settings, because what the four mean is this file's subject and a second copy
## is how a row and a policy come to disagree.
##
## The wording is what the painter sees rather than which driver they are on:
## somebody who has never heard of Wayland still knows whether their pen has a
## pointer over the panels.
##
## The last two are debugging switches and the first two are the painter's.
## *Never* switches Sara's own drawing off, which is how a Sara bug is told from
## a driver one, and *Both* draws the ring beside the pointer the system draws,
## which is how the lag between them is read. Neither is a mode a painter is
## meant to leave on, so the two come after the two that are. Only *Both* says
## debugging in its label: *Never* keeps its one word, because a painter who
## picks it gets exactly what the word promises.
const CURSOR_MODES: Array[Dictionary] = [
    {"id": "auto", "label": "Only where the system does not draw one"},
    {"id": "always", "label": "Always"},
    {"id": "never", "label": "Never"},
    {"id": "both", "label": "Both, to see the lag (debugging)"},
]

## Every live `CursorOverlay`, one per Window. Registered by the overlay itself,
## so `render/` still does not depend on `ui/`: this holds Objects and asks them
## only for their window.
static var _live_overlays: Array = []


## Adds *overlay* to the registry, so the OS cursor policy knows which windows
## have something drawn in them.
static func register_overlay(overlay: Object) -> void:
    if not _live_overlays.has(overlay):
        _live_overlays.append(overlay)


static func unregister_overlay(overlay: Object) -> void:
    _live_overlays.erase(overlay)


## Whether an overlay registered here stands in *window* itself. Asked of the
## register rather than of a node name, so the dependency is the one
## [method register_overlay] states and a rename in `ui/` cannot break it.
static func has_overlay(window: Window) -> bool:
    for entry: Variant in _live_overlays:
        if not is_instance_valid(entry) or not entry is Node:
            continue
        var overlay: Node = entry
        if overlay.get_parent() == window:
            return true
    return false


## Whether the pen's place moves the system pointer as well, where a driver
## leaves it behind, [method SaPointerDevice.carry_system_pointer]. Sara's boot
## turns it on. A suite never does, because a suite's made-up pen would move the
## real pointer of whoever runs it.
static var pen_carries_system_pointer: bool = false


## Records what kind of device sent *event*, [method SaPointerDevice.note_pointer_device],
## and takes the system pointer to the pen while [member pen_carries_system_pointer].
static func note_pointer_device(event: InputEvent, window: Window = null) -> void:
    SaPointerDevice.note_pointer_device(event, window)
    if pen_carries_system_pointer:
        SaPointerDevice.carry_system_pointer(event, window)


## Records that *window* said the pointer left it, [method SaPointerDevice.note_pointer_left].
## The trip is heard as well, [method SaCursorTrip.note_pointer_left].
static func note_pointer_left(window: Window) -> void:
    SaPointerDevice.note_pointer_left(window)
    SaCursorTrip.note_pointer_left(window, mouse_mode_seat.read())


## Whether a pen that has gone quiet has left, which is how Godot 4.7's Android
## port has to be read. Android tells a view that a pen has left hover
## range with `ACTION_HOVER_EXIT`, and Godot hands that over as one more
## `InputEventMouseMotion` at the pen's last place, with no pressure, no
## buttons and the last tilt, the same event a hover move makes, and no
## `NOTIFICATION_WM_MOUSE_EXIT` follows. So a pen that has sent nothing for
## [constant SaPointerDevice.PEN_SILENCE_USEC] counts as out of range. On by
## itself on Android alone, where nothing else says so, and a suite or a
## scenario turns it on to play what that port sends.
static var pen_silence_means_gone: bool = OS.get_name() == "Android"

## Where a pen that has left its window is, [constant SaPointerDevice.NOWHERE].
const NOWHERE: Vector2 = SaPointerDevice.NOWHERE


## Records that a quiet pen has left *window* while [member pen_silence_means_gone],
## and answers whether it did so just now, [method SaPointerDevice.note_pen_silence].
static func note_pen_silence(window: Window, now_usec: int) -> bool:
    return SaPointerDevice.note_pen_silence(window, now_usec, pen_silence_means_gone)


## Records that *window* said the pointer came over it, and hands it the focus
## when the pen needs it there, [method SaPointerDevice.note_pointer_entered].
## Only while [member pen_carries_system_pointer], for the reason that member
## gives: a suite's made-up pen must not move the focus of whoever runs it.
##
## Writes the whole answer as well, as a focus in does, because an enter is
## where a grab or a focus change ends, [SaCursorTrip] says why.
static func note_pointer_entered(window: Window) -> void:
    if pen_carries_system_pointer:
        SaPointerDevice.note_pointer_entered(window)
    SaCursorTrip.note_pointer_entered(window, mouse_mode_seat.read())
    sync_os_cursor_visibility()


## Forgets what device was last seen, [method SaPointerDevice.forget_pointer_device].
static func forget_pointer_device() -> void:
    SaPointerDevice.forget_pointer_device()


## Where the pointer is in *space*, for everything but the ring,
## [method SaPointerDevice.pointer_in].
static func pointer_in(space: Object = null) -> Vector2:
    return SaPointerDevice.pointer_in(space)


## The system pointer on the desktop, [method SaPointerDevice.system_pointer].
static func system_pointer() -> Vector2:
    return SaPointerDevice.system_pointer()


## The pointer in *window*'s viewport space, or the pinned point,
## [method SaCursorRing.pointer_in_window].
static func pointer_in_window(window: Window) -> Vector2:
    return SaCursorRing.pointer_in_window(window)


## Freezes where the pointer is thought to be, [method SaCursorRing.pin_pointer].
static func pin_pointer(holder: Object, window: Window, at: Vector2) -> void:
    SaCursorRing.pin_pointer(holder, window, at)


## Drops *holder*'s pin, [method SaCursorRing.unpin_pointer].
static func unpin_pointer(holder: Object) -> void:
    SaCursorRing.unpin_pointer(holder)


## Whether a pin holds, [method SaCursorRing.pointer_is_pinned].
static func pointer_is_pinned() -> bool:
    return SaCursorRing.pointer_is_pinned()


## The ring radius under *pointer*, or -1.0, [method SaCursorRing.cursor_ring_radius_at].
static func cursor_ring_radius_at(window: Window, pointer: Vector2) -> float:
    return SaCursorRing.cursor_ring_radius_at(window, pointer)


## The ring asked with rectangles alone, [method SaCursorRing.canvas_ring_radius_at].
static func canvas_ring_radius_at(window: Window, pointer: Vector2) -> float:
    return SaCursorRing.canvas_ring_radius_at(window, pointer)


## The outline the ring is drawn as, [method SaCursorRing.cursor_outline_at].
static func cursor_outline_at(window: Window, pointer: Vector2) -> PackedVector2Array:
    return SaCursorRing.cursor_outline_at(window, pointer)


## Every window embedded in *root*, [method SaCursorRing.embedded_subwindows].
static func embedded_subwindows(root: Node, include_internal: bool = false) -> Array[Window]:
    return SaCursorRing.embedded_subwindows(root, include_internal)


## Every window of its own under *root*, [method SaCursorRing.windows_of_their_own].
static func windows_of_their_own(root: Node, asked: Window = null) -> Array[Window]:
    return SaCursorRing.windows_of_their_own(root, asked)


## Stops listening to the system's mouse and pen for *by*,
## [method SaPointerLock.lock].
static func lock_system_pointer(by: String) -> void:
    SaPointerLock.lock(by)


## Listens to the system's mouse and pen again, [method SaPointerLock.unlock],
## and answers how many of their events the lock dropped while it held.
static func unlock_system_pointer() -> int:
    var dropped := SaPointerLock.dropped
    SaPointerLock.unlock()
    return dropped


## Whether *event* is the system's and the lock drops it,
## [method SaPointerLock.drops].
static func drops_system_pointer(event: InputEvent) -> bool:
    return SaPointerLock.drops(event)


## Where *other* sits in *asked*'s space, [method SaCursorRing.rect_in].
static func rect_in(asked: Window, other: Window) -> Rect2:
    return SaCursorRing.rect_in(asked, other)


## Whether a window of its own covers *pointer*,
## [method SaCursorRing.pointer_is_over_a_window_of_its_own].
static func pointer_is_over_a_window_of_its_own(window: Window, pointer: Vector2) -> bool:
    return SaCursorRing.pointer_is_over_a_window_of_its_own(window, pointer)


## Whether an embedded window owns *pointer*,
## [method SaCursorRing.pointer_is_over_embedded_window].
static func pointer_is_over_embedded_window(window: Window, pointer: Vector2) -> bool:
    return SaCursorRing.pointer_is_over_embedded_window(window, pointer)


## Whether something other than the canvas owns *pointer*,
## [method SaCursorRing.pointer_is_over_ui].
static func pointer_is_over_ui(window: Window, pointer: Vector2) -> bool:
    return SaCursorRing.pointer_is_over_ui(window, pointer)


## Whether *pointer* is on a canvas, [method SaCursorRing.pointer_is_over_a_canvas].
static func pointer_is_over_a_canvas(window: Window, pointer: Vector2) -> bool:
    return SaCursorRing.pointer_is_over_a_canvas(window, pointer)


## What the painter is shown at *pointer* in *window*, asked with rectangles
## alone: `ring`, `pointer` or `system`, the three outcomes
## [method CursorOverlay.resolve_cursor] names.
##
## **The one answer a capture can read.** The overlay decides the same three
## from `cursor_ring_radius_at`, which folds in `gui_get_hovered_control`, and
## that answers for wherever the hand physically left the mouse rather than for
## the point being asked about. Wayland will not let a capture put the pointer
## anywhere, so offscreen every probed point comes back `over_ui=true` there,
## whatever the mode. This asks nothing but rectangles, so it
## says the same thing wherever the pointer is, which is what makes a scenario
## able to say what each mode draws over a canvas, over a docker and over the
## Preferences window.
##
## The refinement it leaves out is the hovered Control: the top bar and the menu
## bar are Controls rather than embedded windows, so a point over one of them
## reads `ring` here and `system` in the frame. Every point a scenario asks
## about is a canvas, a docker or a window, and none of those is that case.
static func drawn_at(window: Window, pointer: Vector2) -> StringName:
    if window == null:
        return &"system"
    if SaSettings.software_cursor == "never":
        return &"system"
    if not Rect2(Vector2.ZERO, window.get_visible_rect().size).has_point(pointer):
        return &"system"
    # A window of its own covers this pixel and would cover anything drawn at it,
    # so the system's pointer is what the painter sees there, exactly as it is
    # over a docker embedded in this window.
    if pointer_is_over_a_window_of_its_own(window, pointer):
        return &"system"
    if not pointer_is_over_embedded_window(window, pointer) and canvas_ring_radius_at(window, pointer) >= 0.0:
        return &"ring"
    return &"pointer" if pointer_is_tablet and wants_software_pointer(window, pointer) else &"system"


## Whether the painter should be shown a drawn pointer at *pointer* in *window*
## rather than the OS cursor.
##
## True only while a tablet tool is what is moving the pointer. Godot's Wayland
## driver sets the mouse pointer's cursor and not the tablet tool's, so a pen has
## no cursor anywhere over the UI under it, and only the brush ring over the
## canvas. A mouse is left alone, because the driver already gets that right and
## a drawn cursor lags a hardware one.
##
## The invariant is kept by the last check: a window with no overlay has
## nothing drawn over it, so the OS cursor stays in charge there. An open
## `SaChoicePopup` has one of its own, attached as it opens, so over a list the
## answer is yes and the arrow is drawn in the list's own window, which is what
## gave a pen under Wayland a pointer over every menu. A popup of the engine's
## that no Sara list wraps still has none, and keeps the OS cursor.
static func wants_software_pointer(window: Window, pointer: Vector2) -> bool:
    if not pointer_is_tablet or not software_pointer_mode_active():
        return false
    if window == null or not window.visible:
        return false
    if not Rect2(Vector2.ZERO, window.get_visible_rect().size).has_point(pointer):
        return false
    # Drawn in *window*, so a window of its own standing over this pixel would
    # cover it. Nothing is drawn in the other window on this one's behalf.
    if pointer_is_over_a_window_of_its_own(window, pointer):
        return false
    var under: Array[Window] = []
    var a_list_is_on_top := false
    for sub in embedded_subwindows(window, true):
        if SaCursorRing.place_of(window, sub).has_point(pointer):
            under.append(sub)
            a_list_is_on_top = a_list_is_on_top or sub is Popup
    for sub in under:
        # An open popup stands over every window that is not one, so under it
        # only the popups decide.
        if a_list_is_on_top and not (sub is Popup):
            continue
        if not has_overlay(sub):
            return false
    return not _covered_by_an_undrawn_window(window, pointer)


## Whether the overlay of *window* is the one that draws the pen's arrow at
## *pointer*: [method wants_software_pointer] says yes and no window embedded in
## *window* stands there.
##
## Over an embedded window with an overlay of its own the answer above is yes,
## because it is also what hides the OS cursor and what a capture reads as what
## the painter sees there. The arrow belongs to the embedded window's overlay, so
## the host's leaves it out, rather than drawing a second arrow beneath the
## docker where nobody sees it and a `state` dump reads two windows drawing the
## pen at once.
static func arrow_drawn_in(window: Window, pointer: Vector2) -> bool:
    if not wants_software_pointer(window, pointer):
        return false
    return not pointer_is_over_embedded_window(window, pointer)


## Whether a window with nothing drawn in it stands over *pointer*, asked in the
## root's own space rather than in *window*'s.
##
## A popup belongs to the root, or to whoever owns the menu, and never to the
## docker it happens to cover, so the loop above finds nothing when it is a
## docker's overlay asking. Driving a pen over an open View menu where it
## crosses the Tool Options docker showed what that costs: the docker's overlay
## answered yes, the OS cursor went out with it, and the menu drew over the
## pointer the docker thought it was drawing. That is the one failure this whole
## file exists to prevent, one window further in.
static func _covered_by_an_undrawn_window(window: Window, pointer: Vector2) -> bool:
    if not window.is_inside_tree():
        return false
    var root := window.get_tree().root
    if root == null or root == window:
        return false
    var in_root := root_point_of(window, pointer)
    for sub in embedded_subwindows(root, true):
        if not Rect2(Vector2(sub.position), Vector2(sub.size)).has_point(in_root):
            continue
        # A popup stands over every window that is not one, the rule the ring
        # keeps for windows of their own, so an open list is not covered by a
        # window it is drawn above.
        if window is Popup and not (sub is Popup):
            continue
        if not has_overlay(sub):
            return true
    return false


## *pointer*, in *window*'s own space, as the same point in the root's space,
## the one the root's own overlay would be asked about.
##
## Derived rather than read from the display server, because a hypothetical
## point a probe asks about has to get a hypothetical answer. Carried through
## both windows' transforms, because a window's own units are not the root's
## once it has a content scale of its own: adding the window's position alone
## lands the point a fifth short on a window at 1.25, a note box the pointer is
## in is missed, and the system cursor is hidden over a window that draws
## nothing. The size ratio is the answer for a window the desktop transform
## cannot place.
static func root_point_of(window: Window, pointer: Vector2) -> Vector2:
    var root := window.get_tree().root if window.is_inside_tree() else null
    var to_desktop: Variant = SaPointerDevice.desktop_transform(window)
    var root_to_desktop: Variant = SaPointerDevice.desktop_transform(root)
    if to_desktop is Transform2D and root_to_desktop is Transform2D:
        var from: Transform2D = to_desktop
        var into: Transform2D = root_to_desktop
        return into.affine_inverse() * (from * pointer)
    var units := window.get_visible_rect().size
    var scale := Vector2(window.size) / units if units.x > 0.0 and units.y > 0.0 else Vector2.ONE
    return Vector2(window.position) + pointer * scale


## Whether the setting resolves to drawing Sara's own pointer at all, before any
## question of where the pointer is.
##
## "auto" is the default and reads the display driver, because the defect is the
## Wayland driver's and only its: one build under `--display-driver x11` has a
## pen cursor over the UI and under `--display-driver wayland` has none. Drawing
## one under X11 by default would
## replace a working hardware cursor with a laggier drawn one for no reason.
##
## "always" and "never" override that in either direction, which is what makes
## the driver check a default rather than a gate. A painter whose pen has no
## pointer under some other driver can switch it on, and one who would rather
## have the hardware cursor with its lag under Wayland can switch it off.
##
## "both" resolves exactly as "always" does, because it differs from it in one
## thing only and that thing is not here: what Sara draws is the same, and what
## the OS cursor does about it is [method sync_os_cursor_visibility]'s answer.
static func software_pointer_mode_active() -> bool:
    match SaSettings.software_cursor:
        "never":
            return false
        "always", "both":
            return true
        _:
            return DisplayServer.get_name() == WAYLAND_DRIVER


## Whether the pen's place on screen is drawn by Sara alone, the second fact the
## cursor lead's Auto rule asks of this machine.
##
## Where Sara draws the pointer, and on Android under any mode but Never, where
## the system draws nothing for a pen over Godot's window and the ring over the
## canvas is all a painter sees of where the pen is. Asked apart from
## [method software_pointer_mode_active], because on Android that answer also
## puts Sara's own arrow over every docker, which nobody on a tablet asked for.
## *display_server* is the driver's name, there so a suite asks the Android case
## on any machine.
static func sara_draws_the_pen(display_server: String = DisplayServer.get_name()) -> bool:
    if SaSettings.software_cursor == "never":
        return false
    return software_pointer_mode_active() or display_server == ANDROID_DRIVER


## Hide the OS cursor exactly while a software ring is being drawn somewhere, and
## show it otherwise. *Never* and *Both* are the two modes that never hide it,
## and the body says why each does not.
##
## Mouse mode is process-global, so this is the single writer: every caller
## computes the same answer from the same registry, which makes repeated calls
## from different overlays harmless. Nothing else in the codebase may set it,
## or the pointer can end up hidden with nothing drawn in its place.
static func sync_os_cursor_visibility() -> void:
    # The two modes that never hide it, for opposite reasons. Under *Never* there
    # is nothing drawn to hide it for, and under *Both* the whole point is that the
    # painter sees the ring and the OS pointer at once and reads the distance
    # between them as the lag. Everything below this is the hiding and only the
    # hiding, so both leave through the same door, and the tool's own picture is
    # still asked for on the way out.
    if SaSettings.software_cursor in ["never", "both"]:
        SaCursorTrip.take_write_whole()
        if SaCursorTrip.needs_write(mouse_mode_seat, Input.MOUSE_MODE_VISIBLE):
            SaCursorTrip.write(mouse_mode_seat, Input.MOUSE_MODE_VISIBLE)
        sync_tool_cursor()
        return

    # Asked through cursor_ring_radius_at, so "hidden" means exactly "a ring is
    # being drawn here" rather than a second, subtly different rect test. A
    # pointer read from the viewport while the overlay reads it from the display
    # server can disagree with it. Every live canvas and not the front
    # surface's: this asks which windows have a ring in them at all, which is
    # a question about the hand rather than about the document.

    var hide_os_cursor := false
    var checked: Array[Window] = []
    for sa_canvas: SaCanvas in SaCanvas.live_canvases():
        if sa_canvas.cursor_ring_radius < 0.0 or not sa_canvas.is_visible_in_tree():
            continue
        var window := sa_canvas.get_window()
        if window == null or checked.has(window):
            continue
        checked.append(window)
        if cursor_ring_radius_at(window, pointer_in_window(window)) >= 0.0:
            hide_os_cursor = true
            break

    # The pen's pointer, which is drawn over the UI and not only over a canvas,
    # so the windows to ask are the ones with an overlay rather than the ones
    # with a canvas. Same tick as the overlay's own decision, and both read
    # `wants_software_pointer`, so the two cannot disagree.
    if not hide_os_cursor:
        for entry: Variant in _live_overlays:
            if not is_instance_valid(entry) or not entry is Node:
                continue
            var overlay: Node = entry
            if not overlay.is_inside_tree():
                continue
            var overlay_window := overlay.get_window()
            if wants_software_pointer(overlay_window, pointer_in_window(overlay_window)):
                hide_os_cursor = true
                break

    var wanted := Input.MOUSE_MODE_HIDDEN if hide_os_cursor else Input.MOUSE_MODE_VISIBLE
    # After a trip out or an enter the reading is not to be trusted, so a
    # hidden pointer is written visible first: a driver that skips a write of
    # the mode it holds would otherwise skip this one too.
    if SaCursorTrip.take_write_whole():
        if wanted == Input.MOUSE_MODE_HIDDEN:
            SaCursorTrip.write(mouse_mode_seat, Input.MOUSE_MODE_VISIBLE)
        SaCursorTrip.write(mouse_mode_seat, wanted)
    elif SaCursorTrip.needs_write(mouse_mode_seat, wanted):
        SaCursorTrip.write(mouse_mode_seat, wanted)

    # The tool's own picture, in the same tick and from the same reading of
    # where the pointer is. It is here rather than on its own frame hook
    # because this function is the one thing the overlay already calls every
    # frame, and because a picture and a hidden OS cursor are two halves of one
    # answer: what the painter is looking at.
    sync_tool_cursor()


## Where the policy reads and writes the process's mouse mode, which is
## [Input] itself in Sara. A suite stands a seat of its own here to record each
## write, and to play the system showing its pointer while Godot's mode still
## reads hidden.
class MouseModeSeat:
    extends RefCounted

    func read() -> int:
        return Input.get_mouse_mode()

    func write(mode: int) -> void:
        Input.set_mouse_mode(mode as Input.MouseMode)


## The seat [method sync_os_cursor_visibility] reads and writes the mouse mode
## through.
static var mouse_mode_seat: MouseModeSeat = MouseModeSeat.new()


## Hears that another program took the focus, [method SaCursorTrip.note_focus_out].
##
## The system shows its own pointer over Sara then, while Godot's mode still
## reads hidden, so a guard that writes only a change would never hide it again
## on the way back.
static func note_focus_out() -> void:
    SaCursorTrip.note_focus_out(mouse_mode_seat.read())


## Hears that the focus came back, and after a trip out writes the whole answer
## again, so a ring under the pen hides the pointer at once whatever the system
## did meanwhile.
static func note_focus_in() -> void:
    if SaCursorTrip.note_focus_in(mouse_mode_seat.read()):
        sync_os_cursor_visibility()


## The process frame the overlays last asked for the sync in, or -1 before the
## first.
static var _synced_frame: int = -1


## [method sync_os_cursor_visibility] once per process frame, however many
## overlays ask for it in that frame. Every overlay steps every frame, and the
## answer is process-wide and read from the same registry, so after the first
## call the other overlays have nothing left to do.
##
## Asking every time runs the whole sync once per overlay, and with a window of
## dockers open that is most of an idle Sara's processor time. An overlay that
## asks after the first gets the answer it would have computed, because it was
## computed in the same tick from the same pointer.
## A caller that has just changed what the answer depends on, a tool or a
## setting, calls the sync itself and is never skipped.
static func sync_os_cursor_visibility_this_frame() -> void:
    var frame := Engine.get_process_frames()
    if frame == _synced_frame:
        return
    _synced_frame = frame
    sync_os_cursor_visibility()


## The shape slot a tool's own picture is currently standing in, and the tool it
## belongs to, so a clear cannot give back a slot somebody else is holding.
##
## Process wide because `Input.set_custom_mouse_cursor` is, which is the reason
## this lives here rather than on the tool machine: the machine is one per
## surface and there is one pointer.
static var _tool_cursor_shape: int = -1
static var _tool_cursor_owner: StringName = &""
## The name of the tool's own picture by position standing in that slot, empty
## while the slot holds the descriptor's picture or nothing.
static var _tool_cursor_picture_name: StringName = &""

## The cursor picture's edge, in logical pixels. 24 rather than the icon's own
## 16 or the 64 the SVG import rasterises to at `svg/scale=4.0`: a cursor is
## read at a glance from a hand's distance and 16 is smaller than every stock
## arrow it stands beside.
const TOOL_CURSOR_EDGE: int = 24

## The same edge in the pixels the picture is resized to. The cursor overlay
## writes it when it joins a window, because how a logical size becomes pixels
## is the interface's to say and `render` names nothing under `ui`. Until an
## overlay has spoken it is the logical edge itself.
static var tool_cursor_edge: int = TOOL_CURSOR_EDGE

## Cached by tool id, because building an `ImageTexture` per activation would
## rasterise the same picture on every press of the tool's chord.
static var _tool_cursor_cache: Dictionary = {}

## The picture the active tool asks for, and the canvas it belongs to, held so
## the pointer's own position can put it up and take it down without the tool
## machine being asked again.
##
## `Input.set_custom_mouse_cursor` replaces a *shape* for the whole process, so
## a tool that has claimed one keeps its picture wherever the pointer goes: an
## eyedropper icon left over the Minimap after an ALT drag of it, a drag that
## takes the pointer over a docker without crossing the canvas on the way.
static var _tool_cursor_descriptor: Object = null
static var _tool_cursor_canvas: Control = null
static var _tool_cursor_wanted_shape: int = Control.CURSOR_ARROW
## The picture the active tool asks for where the pointer is now, which wins
## over the descriptor's while it is not null, held beside the descriptor for
## the same reason.
static var _tool_cursor_wanted_picture: SaCursorPicture = null


## Puts *descriptor*'s own picture under the pointer over *canvas*, or its stock
## *shape* when it has none, and gives back whatever the last tool was holding.
## *picture* is the one the tool asks for where the pointer is now, standing in
## the same slot in place of the descriptor's, the Transform's rotate arrow
## beside a corner.
##
## Records what the tool wants and hands the question of whether it is showing
## to [method sync_tool_cursor], which the frame asks again as the pointer
## moves.
static func apply_tool_cursor(canvas: Control, descriptor: Object, shape: int, picture: SaCursorPicture = null) -> void:
    _tool_cursor_canvas = canvas
    _tool_cursor_descriptor = descriptor
    _tool_cursor_wanted_shape = shape
    _tool_cursor_wanted_picture = picture
    sync_tool_cursor()


## Puts the active tool's picture up while the pointer is over a canvas and
## gives the slot back the moment it is not.
##
## Called every frame from [method sync_os_cursor_visibility], because a picture
## that is only revisited when the tool changes is a picture that outlives the
## reason it was shown. That is the same rule the ring half of this package keeps,
## one tick further out: what the painter sees is decided from where the pointer
## is now rather than from where it was when something last happened.
static func sync_tool_cursor() -> void:
    # A tool registry a test built and freed, or a canvas whose window has gone,
    # leaves this holding an Object that is no longer one. Reading either back
    # is a script error rather than a null, so both are dropped before anything
    # else looks at them.
    # `is_instance_valid` without a null test in front of it, because a freed
    # Object does not compare unequal to null: `held != null and not
    # is_instance_valid(held)` is false for exactly the case this is for, and
    # the dangling reference went on to the call below. `is_instance_valid(null)`
    # is false, so the null case takes the same branch and nothing is lost.
    if not is_instance_valid(_tool_cursor_descriptor):
        _tool_cursor_descriptor = null
    if not is_instance_valid(_tool_cursor_canvas):
        _tool_cursor_canvas = null
    var canvas := _tool_cursor_canvas

    # True until something can say otherwise: with no canvas in a tree there is
    # no window to ask where the pointer is, and a picture withheld on a guess
    # is a tool whose cursor never appears. The app always has one, because the
    # tool machine only asks for a picture when its surface draws through a
    # canvas view.
    var window: Window = canvas.get_window() if canvas != null and canvas.is_inside_tree() else null
    var showing := true
    var over_a_menu := false
    if window != null:
        var at := pointer_in_window(window)
        # The hovered Control as well as the rectangles, because this runs where
        # the pointer really is: the canvas Control reaches under the top bar
        # and the menu bar, so the rectangle test alone calls a point on the
        # menu "over the canvas". `tool_cursor_shows_at` is the half without it,
        # for a probe that asks about a point the pointer is not at.
        var held := _tool_cursor_wanted_picture != null and _tool_cursor_wanted_picture.held
        over_a_menu = not held and pointer_is_over_ui(window, at)
        showing = tool_cursor_shows_at(window, at) and not over_a_menu
    var shown := _tool_cursor_descriptor if showing else null
    # A menu or popup over the canvas leaves the canvas the Control the engine
    # reads the pointer's shape from, so the tool's shape would stay under the
    # menu. The menu's is the arrow.
    var canvas_shape := Control.CURSOR_ARROW if over_a_menu else _tool_cursor_wanted_shape
    _show_tool_cursor(canvas, shown, _tool_cursor_wanted_shape, _tool_cursor_wanted_picture if showing else null, canvas_shape)


## Whether the active tool's own picture belongs under the pointer at *pointer*
## in *window*, asked with rectangles alone.
##
## False when no tool has asked for a picture, which is every tool but the
## eyedropper and the Transform by a corner today, and false under *Never*
## whatever the tool asked for. True off the canvas too for a picture a held
## gesture asked for. *Never* means Sara draws no pointer, and a pointer the
## system draws on Sara's asking is fine. The eyedropper's picture
## is one Sara rasterised and the display server only places, so under *Never*
## it goes and the tool's stock shape stays, exactly as the brush keeps its
## crosshair and the pan its hand.
static func tool_cursor_shows_at(window: Window, pointer: Vector2) -> bool:
    if SaSettings.software_cursor == "never":
        return false
    if not is_instance_valid(_tool_cursor_descriptor):
        return false
    var by_position := _tool_cursor_wanted_picture != null and _tool_cursor_wanted_picture.texture != null
    if not by_position and _tool_cursor_descriptor.get("cursor_texture") == null:
        return false
    # A picture a held gesture asked for stands over a docker as well, since the
    # gesture goes on there, and goes with the gesture's release.
    if by_position and _tool_cursor_wanted_picture.held:
        return true
    return pointer_is_over_a_canvas(window, pointer)


## The tool's own picture the pen's drawn pointer wears at *pointer* in
## *window*, sized to `tool_cursor_edge` and named for a dump, or null for the
## plain drawn arrow.
##
## A pen under Wayland moves a pointer the driver gives no cursor, so the
## overlay draws an arrow of its own and hides the OS cursor, over the canvas as
## over the UI. A tool's picture put only into the OS cursor's slot is hidden
## exactly there, so the drawn pointer asks the same question the slot is filled
## from, with the same answer, and wears the picture in the arrow's place. The
## descriptor's picture, the Eyedropper's, is worn the same way, named for its
## tool.
static func pen_picture_at(window: Window, pointer: Vector2) -> SaCursorPicture:
    if window == null or not tool_cursor_shows_at(window, pointer):
        return null
    var wanted := _tool_cursor_wanted_picture
    var held := wanted != null and wanted.held
    if not held and pointer_is_over_ui(window, pointer):
        return null
    var tool_id: StringName = _tool_cursor_descriptor.get("id")
    if wanted != null and wanted.texture != null:
        var cached_as := StringName("%s/%s" % [tool_id, wanted.name])
        return SaCursorPicture.new(wanted.name, _tool_cursor_texture(cached_as, wanted.texture), wanted.hotspot, held)
    var texture: Texture2D = _tool_cursor_descriptor.get("cursor_texture")
    var hotspot: Vector2 = _tool_cursor_descriptor.get("cursor_hotspot")
    return SaCursorPicture.new(tool_id, _tool_cursor_texture(tool_id, texture), hotspot, false)


## The half that talks to the display server: *descriptor*'s picture in *shape*,
## or *picture* in its place when the tool asked for one where the pointer is,
## or nothing when *descriptor* is null, and the last slot given back.
##
## One call rather than a set and a clear, because the two must happen in the
## same tick: a tool change that cleared first would show the stock arrow for a
## frame, a visible flicker. The pointer leaving the Transform's corner is the
## same change within one tool, the arrow's slot given straight back to the
## stock move.
static func _show_tool_cursor(
    canvas: Control, descriptor: Object, shape: int, picture: SaCursorPicture = null, canvas_shape: int = -1
) -> void:
    if canvas != null and is_instance_valid(canvas):
        _write_cursor_shape(canvas, shape if canvas_shape < 0 else canvas_shape)

    var wanted_id: StringName = descriptor.get("id") if descriptor != null else &""
    var texture: Texture2D = descriptor.get("cursor_texture") if descriptor != null else null
    var hotspot: Vector2 = descriptor.get("cursor_hotspot") if descriptor != null else Vector2.ZERO
    var picture_name: StringName = &""
    if descriptor != null and picture != null and picture.texture != null:
        texture = picture.texture
        hotspot = picture.hotspot
        picture_name = picture.name
    if texture == null:
        wanted_id = &""
        picture_name = &""

    if _tool_cursor_owner == wanted_id and _tool_cursor_shape == shape and _tool_cursor_picture_name == picture_name:
        return

    # The old slot goes back first, except when the new tool is taking that very
    # slot: clearing one the next line refills is a frame of stock arrow.
    if _tool_cursor_shape >= 0 and (_tool_cursor_shape != shape or wanted_id == &""):
        Input.set_custom_mouse_cursor(null, _tool_cursor_shape as Input.CursorShape)
    _tool_cursor_shape = -1
    _tool_cursor_owner = &""
    _tool_cursor_picture_name = &""
    if wanted_id == &"":
        return

    # Cached under the tool and the picture's name together, so a tool with a
    # picture of its own as well as its descriptor's keeps both copies.
    var cached_as := StringName("%s/%s" % [wanted_id, picture_name]) if picture_name != &"" else wanted_id
    var drawn := _tool_cursor_texture(cached_as, texture)
    if drawn == null:
        return
    Input.set_custom_mouse_cursor(drawn, shape as Input.CursorShape, hotspot * Vector2(drawn.get_size()))
    _tool_cursor_shape = shape
    _tool_cursor_owner = wanted_id
    _tool_cursor_picture_name = picture_name


## Writes *shape* onto *canvas*, the shape the OS pointer takes over it.
##
## The engine's setter asks whether the pointer is over the control with
## `get_global_rect().has_point()`, and a Control mirrors by a negative scale,
## which one mirrored axis turns into a rect with a negative height
## (`test_mirrored_canvas_rect.gd`). So every change of shape over a mirrored
## view logged `Rect2 size is negative`. A note's question mark is such a
## change, which is why the line came as a note began and again as Escape
## cancelled it. The mirror is lifted for the one write and put back in the
## same call, which no frame draws. The setter's own test then ran against the
## lifted rect rather than the drawn one, so the pointer's shape is brought up
## to date here in its place.
static func _write_cursor_shape(canvas: Control, shape: int) -> void:
    if canvas.mouse_default_cursor_shape == shape:
        return
    if not canvas.is_inside_tree() or canvas.get_global_transform().determinant() >= 0.0:
        canvas.mouse_default_cursor_shape = shape as Control.CursorShape
        return
    var mirrored := canvas.scale
    canvas.scale = Vector2(mirrored.x, -mirrored.y)
    canvas.mouse_default_cursor_shape = shape as Control.CursorShape
    canvas.scale = mirrored
    canvas.get_viewport().update_mouse_cursor_state()


## Gives back every slot a tool picture is holding, and forgets what tool asked
## for one. For a test, and for a shutdown that must not leave the desktop's
## pointer replaced.
static func clear_tool_cursor() -> void:
    if _tool_cursor_shape >= 0:
        Input.set_custom_mouse_cursor(null, _tool_cursor_shape as Input.CursorShape)
    _tool_cursor_shape = -1
    _tool_cursor_owner = &""
    _tool_cursor_picture_name = &""
    _tool_cursor_descriptor = null
    _tool_cursor_canvas = null
    _tool_cursor_wanted_shape = Control.CURSOR_ARROW
    _tool_cursor_wanted_picture = null


## Gives the slot back when *canvas*, the one the picture was put up over,
## leaves the tree. Called from `SaCanvas._exit_tree`, so the app's shutdown
## reaches [method clear_tool_cursor], which otherwise only the tests would.
##
## The display server keeps the picture it was handed, and it is torn down
## after the rendering server has already counted what is left: a picture
## still standing in a slot at exit is `1 RID allocations of type
## 'TextureStorage::Texture' were leaked` and `2 RIDs of type "Texture"` in
## the log of a run that hovers the eyedropper over the canvas and quits from
## there. A run that leaves the canvas first is clean, because the frame sync
## gives the slot back on the way out. Only the canvas that holds the picture
## gives it back, so a
## secondary surface closing cannot take the main canvas's cursor with it.
static func release_tool_cursor_of(canvas: Control) -> void:
    if canvas == null or _tool_cursor_canvas != canvas:
        return
    clear_tool_cursor()


## Which tool's picture is under the pointer, and in which slot, for a dump. A
## screenshot cannot show the OS cursor at all, so this is the only place the
## claim can be read. `picture` names the tool's picture by position, the
## Transform's `rotate`, and is empty for the descriptor's own or none.
static func tool_cursor_state() -> Dictionary:
    return {
        "tool": String(_tool_cursor_owner),
        "shape": _tool_cursor_shape,
        "custom": _tool_cursor_owner != &"",
        "picture": String(_tool_cursor_picture_name),
    }


## *source* resized to `tool_cursor_edge`, cached under *tool_id*, which is
## the tool's id for its descriptor's picture and `tool/picture` for one it asks
## for by position.
##
## Resized rather than handed over as it is: the icons are rasterised at
## `svg/scale=4.0`, so `colorpick.svg`'s 16 pixels arrive as 64 and a 64 pixel
## cursor is three times the size of the arrow beside it. Lanczos because the
## picture is being made smaller and a nearest read of a 64 to 24 reduction
## drops the one pixel wide stem the eyedropper is mostly made of.
static func _tool_cursor_texture(tool_id: StringName, source: Texture2D) -> Texture2D:
    var cached: Texture2D = _tool_cursor_cache.get(tool_id)
    if cached != null and is_instance_valid(cached):
        return cached
    var image := source.get_image()
    if image == null:
        return null
    var edge := tool_cursor_edge
    var copy := Image.new()
    copy.copy_from(image)
    if copy.is_compressed():
        copy.decompress()
    copy.resize(edge, edge, Image.INTERPOLATE_LANCZOS)
    var made := ImageTexture.create_from_image(copy)
    _tool_cursor_cache[tool_id] = made
    return made
