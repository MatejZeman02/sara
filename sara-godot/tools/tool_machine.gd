## Input router and tool state controller.
##
## Two kinds of activation:
##   - Permanent: set_active_tool(), stays until another permanent switch.
##   - Quick/hold: a held modifier temporarily overrides it. Releasing restores
##     the permanent tool. The highest quick_priority among held actions wins.
##
## Which tools are painting tools, which get a brush ring, which quick key maps
## to which and what cursor each shows come from SaToolDescriptor rather than
## from a tool's name, so a module tool behaves exactly like a built-in.
extends Node

class_name ToolMachine

## Bounds on the brush radius, which is a fraction of the canvas's smaller
## dimension. Shared with ShortcutRouter, so the [ and ] keys and the shift drag
## cannot end up clamping to different sizes. The brush radius as a fraction of
## the canvas's smaller dimension, which is how a preset stores it and what the
## Size row shows as pixels of the document. The soft ceiling is where the row's
## drag and its fill stop, half the smaller dimension, 540 pixels on the default
## document. The hard one is the whole of it, reached by typing, and it is also
## where the shift-drag over the canvas and the bracket keys stop. There are two
## because one ceiling, 0.2, would make 216 pixels the largest brush a painter
## could have. **The floor is a tenth of a pixel's radius on the default
## document**, because a size under one pixel is one a painter asks for, and a
## floor of 0.001, 1.08 pixels on a 1080-tall one, would keep the Size row from
## expressing a brush under a pixel at all, its shown number stopping at
## "1 px". The plane the floor belongs to is the dab's own, not the canvas's: `StateBrush` drops a dab
## under `MIN_DAB_DIAMETER`, a fifth of a pixel across, so 0.0001 of 1080 is a
## radius of 0.108 and a diameter of 0.216, which is the smallest size that
## still paints. Lower would be a floor below the paint, and the row would offer
## sizes that leave no mark.
const BRUSH_RADIUS_MIN: float = 0.0001
const BRUSH_RADIUS_SOFT_MAX: float = 0.5
const BRUSH_RADIUS_MAX: float = 1.0

## The surface this machine drives. Replaces `canvas = get_parent()` plus an
## assert that it is a SaCanvas, which is what made the machine untestable
## without a Control tree.
var surface: SaSurface = null

var registry: SaToolRegistry = null
## Handed to every tool instance beside the surface, so a tool asks for its
## engines by role. Null when the host binds without one.
var roles: SaRoleRegistry = null

var registered_tools: Dictionary = {}  # StringName -> ToolState
var active_tool_name: StringName = &""
var default_tool_name: StringName = &""
var active_tool: ToolState = null

## Blocks painting if the tool changed while the mouse was still held down.
var block_brush_until_release: bool = false

## Whether the last left button this machine heard was a press, the drag a tool
## change blocks for. `Input`'s own button reads a press on a docker too.
var _left_heard: bool = false

## Who holds the pointer in place of the active tool, empty when the tool does,
## and the OS shape every canvas asks for while they do. The note mode is the
## first holder and `MainCanvas`'s symmetry handles the second: each writes both and clears the name,
## because the machine cannot name a class under `ui` to ask. Static because
## there is one pointer and a machine per surface. While a name stands no
## canvas asks for a brush ring, so the OS pointer stays visible over a box the
## holder draws above the canvas. One for every document as well, because the
## pointer is the window's and never two documents' at once.
static var pointer_holder: StringName = &""
static var pointer_holder_shape: int = Control.CURSOR_ARROW

## A right press on the canvas, in the window's logical coordinates, asking
## for the context menu. The machine has no UI, so it announces and the
## host pops the menu.
signal context_menu_requested(global_position: Vector2)

## physical_keycode -> true. Used instead of Input.is_action_pressed so quick
## tools work in headless tests as well as at runtime.
var _held_keys: Dictionary = {}

## The pen buttons down and bound to a tool while held, and the stroke one of
## them makes when the pen touches with it down.
var _held: SaHeldButtons = null

## Whether the middle press now down, or the last one, was the pen's and so
## followed the pen's Middle row. Decided at the press, so its release follows
## the row its press did whatever the pointer has done since.
var _middle_is_the_pens: bool = false

## Whether the tip's touch now down belongs to a held button bound to Pan or
## Context menu, so its motions and its release go to no tool either.
var _tip_taken: bool = false

## Rebuilt from the registry on change, so the hot path never sorts.
var _quick_tools: Array = []

## A Shift press of the left button, which a drag turns into a resize and a
## click into a straight line.
var _shift := SaShiftPress.new()

## The left drag of the pan or the zoom, its press and its log line.
var _drag := SaNavigationDrag.new()

## The shape [method _wanted_cursor_shape] answered when the cursor was last
## published, so a frame that finds the tool wanting another publishes again.
var _cursor_shape_shown: int = Control.CURSOR_ARROW

## The picture [method _wanted_cursor_picture] answered at the same moment, for
## the same reason, told apart by the object since a tool hands back one.
var _cursor_picture_shown: SaCursorPicture = null

## How many `InputEventMouseMotion` events `handle_input` has forwarded to the
## active tool since the last `reset_motion_samples`, so a scenario can prove
## several hardware samples inside one frame all reach the tool rather than
## one merged per frame. Counted here rather than on the tool, because the
## tool changes mid-scenario and the count answers the machine's own delivery,
## not any one tool's reading of it.
var motion_samples_seen: int = 0

## The fingers on the canvas, of which two move the view and one taps, picks or pans.
var _fingers := SaTwoFingers.new()
## The trail of what a pen and a finger reach the canvas as, which the canvas hands every window event.
const InputTrail := preload("res://tools/sa_input_trail.gd")

## The pan, turn or zoom a button bound to Pan drags, the middle one unless
## Preferences > Tablet says otherwise, and the turn a Shift left press makes.
var _view_drag := SaViewDrag.new()


## *wayland* says whether the pen's upper button is the tip's left press here,
## which [SaHeldButtons] tells from the tip and which a suite answers for itself.
func _init(wayland: bool = DisplayServer.get_name() == "Wayland") -> void:
    _held = SaHeldButtons.new(wayland)


func _ready() -> void:
    # Deliver every hardware mouse movement rather than one merged event per
    # frame, or fast curved strokes come out as straight segments.
    Input.set_use_accumulated_input(false)


## Binds this machine to a surface and a tool registry, instantiating one tool
## instance per descriptor. Called by the host once both exist.
func bind(
    target_surface: SaSurface, tool_registry: SaToolRegistry, role_registry: SaRoleRegistry = null, pens: SaPenRegistry = null
) -> void:
    surface = target_surface
    registry = tool_registry
    roles = role_registry
    _held.upper.pens = pens
    # The back-reference a module reaches through SaContext.list_surfaces(),
    # since a module has no door to main.gd's own get_tool_machine().
    if surface != null:
        surface.tool_machine = self
    # The brush ring is in screen pixels, so it must be recomputed when the view
    # scales. The view announces the change and the machine subscribes, rather
    # than the zoom state finding this node through the canvas.
    if surface != null and surface.view != null:
        if not surface.view.transform_changed.is_connected(_on_view_transform_changed):
            surface.view.transform_changed.connect(_on_view_transform_changed)
    if registry != null and not registry.changed.is_connected(_rebuild_tools):
        registry.changed.connect(_rebuild_tools)
    _rebuild_tools()


## Instantiates the tools this surface should offer, an embedded surface taking
## only descriptors marked available_in_embedded.
func _rebuild_tools() -> void:
    if registry == null:
        return
    var wanted: Array = registry.list_for_embedded() if (surface != null and surface.is_embedded) else registry.list_descriptors()

    for descriptor: SaToolDescriptor in wanted:
        if registered_tools.has(descriptor.id):
            continue
        var instance: Variant = descriptor.tool_script.new()
        if not (instance is ToolState):
            push_error("ToolMachine: tool '%s' does not extend ToolState." % descriptor.id)
            continue
        var tool := instance as ToolState
        tool.surface = surface
        tool.roles = roles
        tool.hand_back = return_to_previous_tool
        tool.takes_holds = descriptor.is_painting and descriptor.wants_brush_cursor
        # Shared settings let brush size follow the user between surfaces.
        if descriptor.shared_settings != null and "settings" in tool:
            tool.settings = descriptor.shared_settings
        registered_tools[descriptor.id] = tool

    # Drop instances whose descriptor is gone (module unloaded).
    for tool_id: StringName in registered_tools.keys().duplicate():
        if not registry.has(tool_id):
            registered_tools.erase(tool_id)

    _quick_tools = registry.list_quick_tools()

    if active_tool == null and not registered_tools.is_empty():
        var first: SaToolDescriptor = wanted[0] if not wanted.is_empty() else null
        if first != null:
            set_active_tool(first.id)
    _update_cursor()


## Registers a pre-built tool instance directly. Kept for tests and for hosts
## that build a machine without a registry.
func register_tool(tool_name: StringName, tool: ToolState) -> void:
    assert(tool != null, "ToolState cannot be null")
    tool.surface = surface
    tool.roles = roles
    tool.hand_back = return_to_previous_tool
    registered_tools[tool_name] = tool
    if active_tool == null or tool_name == active_tool_name:
        set_active_tool(tool_name)


## The permanent tool before the last permanent switch, which is where a
## tool's [method ToolState.request_hand_back] goes. Quick tools held on
## a key do not move it: they are a detour, not a switch.
var previous_tool_name: StringName = &""


func set_active_tool(tool_name: StringName) -> void:
    if tool_name != default_tool_name and not String(default_tool_name).is_empty():
        previous_tool_name = default_tool_name
    default_tool_name = tool_name
    SaToolRegistry.note_in(registry, tool_name)
    _evaluate_tool()
    EventBus.tool_picked.emit(String(tool_name))


## Back to the tool before this one, or to [method fallback_tool_name] when
## there was none. The transform's Enter is the caller: the painter pressed
## Ctrl+T from some tool to move a thing, and a commit means the thing is moved.
func return_to_previous_tool() -> void:
    var target := previous_tool_name
    if String(target).is_empty() or not registered_tools.has(target):
        target = fallback_tool_name()
    if registered_tools.has(target):
        set_active_tool(target)


## The tool to land on when there is no other to go back to: the first tool
## this machine holds whose descriptor sets [member SaToolDescriptor.is_fallback],
## and failing that the first tool it was handed, which is the one it came up
## with. Empty with no tools at all.
##
## Asked of the descriptor rather than of an id, because the skeleton names no
## module's tool. The stamp brush sets the flag on its brush,
## and a build without that module falls back to its own first tool rather
## than to one nobody registered.
func fallback_tool_name() -> StringName:
    for tool_id: StringName in registered_tools:
        var descriptor := get_descriptor(tool_id)
        if descriptor != null and descriptor.is_fallback:
            return tool_id
    return registered_tools.keys()[0] if not registered_tools.is_empty() else &""


## The first tool this machine holds whose descriptor sets
## [member SaToolDescriptor.picks_colour], or empty when none does. Asked of the
## descriptor, as [method fallback_tool_name] is.
func picker_tool_name() -> StringName:
    for tool_id: StringName in registered_tools:
        var descriptor := get_descriptor(tool_id)
        if descriptor != null and descriptor.picks_colour:
            return tool_id
    return &""


## The first tool this machine holds whose descriptor sets
## [member SaToolDescriptor.erases], or empty when none does, as
## [method picker_tool_name] finds the picker.
func eraser_tool_name() -> StringName:
    for tool_id: StringName in registered_tools:
        var descriptor := get_descriptor(tool_id)
        if descriptor != null and descriptor.erases:
            return tool_id
    return &""


## Asks the active tool to write an open session as its history step, which
## the chord, the Edit menu and the Undo History docker all do before they move
## the history. True when a step was written.
func close_session() -> bool:
    return active_tool != null and active_tool.close_session()


## Whether [method close_session] would write a step now, the active tool's
## answer to [method ToolState.holds_session].
func holds_session() -> bool:
    return active_tool != null and active_tool.holds_session()


func get_tool(tool_name: StringName) -> ToolState:
    return registered_tools.get(tool_name, null)


func get_descriptor(tool_name: StringName) -> SaToolDescriptor:
    return registry.get_descriptor(tool_name) if registry != null else null


## *moves_the_view* says the target is a held pan or zoom, which moves the view
## under the tool in hand and so leaves an open session in that tool where it is.
func _switch_tool(tool_name: StringName, moves_the_view: bool) -> void:
    if not registered_tools.has(tool_name):
        push_error("ToolMachine: tool '%s' is not registered." % tool_name)
        return
    if active_tool != null and not (moves_the_view and active_tool.holds_session()):
        active_tool.reset()
    _shift.drop()
    _view_drag.drop()
    active_tool_name = tool_name
    active_tool = registered_tools[tool_name]
    _update_cursor()
    SaTrail.note("the %s tool" % active_tool_name)
    EventBus.tool_changed.emit(String(active_tool_name))


## A held tool wins, and otherwise the permanent tool.
##
## The usage tally hears which tool a hold puts in the hand before any swap, so
## the swap in and the one back count as no switch. A held tool that is the
## permanent one already is no hold at all.
func _evaluate_tool() -> void:
    var held := _held_target()
    SaUsageTally.hold(held if held != default_tool_name else &"", default_tool_name)
    var target := held if not String(held).is_empty() else _permanent_target()
    if target == active_tool_name or not registered_tools.has(target):
        return
    var descriptor := get_descriptor(target)
    # A left button this machine heard pressed, and so a drag on the canvas. One
    # held on a docker is a pick there, and blocking for it swallowed the first
    # press after a preset that changes the tool. The left button the
    # upper barrel holds under Wayland is no stroke under way either.
    var stroking := _left_heard and not _held.upper.down
    if descriptor != null and descriptor.is_painting and stroking:
        block_brush_until_release = true
    # A held pan or zoom moves the view under the tool in hand, not the hand away from it.
    var moves_the_view := not String(held).is_empty() and descriptor != null and descriptor.category == &"navigate"
    _switch_tool(target, moves_the_view)
    _drag.came_into_hand(self)


## A tool a held pen button asks for, then the highest-priority held quick
## action's, and empty while neither holds one.
func _held_target() -> StringName:
    var held := _held.wanted(registered_tools)
    if not String(held).is_empty():
        return held
    for descriptor: SaToolDescriptor in _quick_tools:
        if registered_tools.has(descriptor.id) and _is_action_held(descriptor.quick_action):
            return descriptor.id
    return &""


## The permanent tool, or the first tool this machine holds before one is set.
func _permanent_target() -> StringName:
    if not String(default_tool_name).is_empty():
        return default_tool_name
    return registered_tools.keys()[0] if not registered_tools.is_empty() else &""


## Whether a key of *action* and its modifiers are down. A chord the shortcut store writes
## names its key by keycode, so that key is asked about, or a quick tool put on Ctrl was held
## whatever the hand did. A key the tool in hand reads holds nothing, a selection's Alt.
func _is_action_held(action: StringName) -> bool:
    if not InputMap.has_action(action):
        return false
    for ev in InputMap.action_get_events(action):
        if ev is InputEventKey:
            var key: int = ev.physical_keycode if ev.physical_keycode != KEY_NONE else ev.keycode
            var kept := SaToolDescriptor.reads_key(get_descriptor(active_tool_name), key)
            var match_key: bool = key == KEY_NONE or (_held_keys.get(key, false) and not kept)
            var match_mods: bool = (
                (not ev.ctrl_pressed or _held_keys.get(KEY_CTRL, false))
                and (not ev.shift_pressed or _held_keys.get(KEY_SHIFT, false))
                and (not ev.alt_pressed or _held_keys.get(KEY_ALT, false))
            )
            if match_key and match_mods:
                return true
    return false


func _update_held_keys(event: InputEventKey) -> void:
    var kc := event.physical_keycode
    if kc == 0:
        kc = event.keycode
    if kc != 0:
        if event.pressed:
            _held_keys[kc] = true
        else:
            _held_keys.erase(kc)

    if event.ctrl_pressed:
        _held_keys[KEY_CTRL] = true
    elif not event.pressed and (kc == KEY_CTRL or kc == KEY_META):
        _held_keys.erase(KEY_CTRL)

    if event.shift_pressed:
        _held_keys[KEY_SHIFT] = true
    elif not event.pressed and kc == KEY_SHIFT:
        _held_keys.erase(KEY_SHIFT)

    if event.alt_pressed:
        _held_keys[KEY_ALT] = true
    elif not event.pressed and kc == KEY_ALT:
        _held_keys.erase(KEY_ALT)


## Clears held keys and pen buttons when the window loses focus, so Alt+Tab
## does not leave a quick tool stuck on.
func clear_held_keys() -> void:
    if _held_keys.is_empty() and _held.is_empty():
        return
    _held_keys.clear()
    _feed_tool(_held.clear())
    _evaluate_tool()


## A motion the canvas's window took before any window had it, which tells the
## upper barrel whether the pen is in the air and reaches no tool. It lets go
## of a key held past its release too, since a dialog holding the focus is
## handed every motion before the canvas.
func pen_moved(motion: InputEventMouseMotion) -> void:
    _held.upper.heard(motion)
    _resync_stuck_modifiers(true)


func handle_input(event: InputEvent) -> void:
    if surface == null or not surface.is_ready():
        if surface != null and SaUnpaintedPress.watched(event, self):
            SaUnpaintedPress.print_why("the canvas was not ready for a tool")
        return
    # A finger also arrives as the mouse Godot emulates from it, a left press
    # and a drag, and on the canvas that would paint. Its touch events are the
    # finger's own route, so the copy is dropped here.
    if event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION:
        return
    # Under Wayland the upper barrel button arrives as the tip's left press,
    # and goes on as the middle button wherever it can be told from the tip.
    for told: InputEvent in _held.upper.told(event):
        _handle_told(told)


func _handle_told(event: InputEvent) -> void:
    var watched := SaUnpaintedPress.watched(event, self)
    _drag.heard(event, self)
    if event is InputEventKey:
        _update_held_keys(event)
        _evaluate_tool()
    else:
        _resync_stuck_modifiers()

    # A press lifts the block as a release does: it begins a drag of its own, and
    # the one the block was for let go where this machine never heard it.
    var button := event as InputEventMouseButton
    if button != null and button.button_index == MOUSE_BUTTON_LEFT:
        block_brush_until_release = false
        _left_heard = button.pressed

    if _handle_pen_button(event):
        SaUnpaintedPress.print_why_if(watched, "a pen button's binding took it")
        return
    if _handle_view_navigation(event):
        SaUnpaintedPress.print_why_if(watched, "the view's pan or zoom took it")
        return
    if _tip_is_the_buttons(event):
        SaUnpaintedPress.print_why_if(watched, "a held pen button bound to Pan or the context menu took it")
        return
    if _shift.take(event, self):
        SaUnpaintedPress.print_why_if(
            watched, "the Shift key was held, which draws a line at the release or sizes the brush with a drag"
        )
        return

    if block_brush_until_release:
        var descriptor := get_descriptor(active_tool_name)
        if descriptor != null and descriptor.is_painting:
            return

    if active_tool == null:
        SaUnpaintedPress.print_why_if(watched, "no tool was in hand")
        return
    if event is InputEventMouseMotion:
        motion_samples_seen += 1
    if _held.is_empty():
        _feed_tool(event)
        return
    for each: InputEvent in _held.route(event, active_tool_name):
        _feed_tool(each)


## Hands *event* to the active tool, and to the tally as that tool's, unless an
## active scene layer's scene takes it. Null is nothing to hand.
func _feed_tool(event: InputEvent) -> void:
    if event == null or active_tool == null:
        return
    var watched := SaUnpaintedPress.watched(event, self)
    if SaScenePress.take(event, self):
        SaUnpaintedPress.print_why_if(watched, "the active scene layer's scene took it")
        return
    if SaOpeningPress.take(event, self):
        SaUnpaintedPress.print_why_if(watched, "the document was still opening")
        return
    SaUsageTally.tool_input(event, active_tool_name)
    var refusal := SaUnpaintedPress.new(active_tool_name) if watched else null
    if refusal != null:
        refusal.hear()
    active_tool.take_input(event)
    if refusal != null:
        refusal.done()
    _drag.fed(event)
    _shift.fed(event, self)


## Zeroes the count above, for a scenario about to push a known number of
## samples and read how many actually arrived.
func reset_motion_samples() -> void:
    motion_samples_seen = 0


## For the state dump: the count and what tool it was counted against, so a
## scenario reading a stale count after a tool switch is a misread of its own
## rather than an ambiguity in the number.
static func motion_report(canvas: Node) -> Dictionary:
    var machine := canvas.get_node_or_null("ToolMachine") as ToolMachine
    if machine == null:
        return {}
    return {"motion_samples_seen": machine.motion_samples_seen, "tool": String(machine.active_tool_name)}


## A missed focus-out can leave a modifier latched. Correct it on the next
## non-key event rather than trusting the latched state forever. *every_key*
## asks of every held key, which a release a dialog kept needs: Space pressed
## over the canvas and let go after a click put a dialog's window in front kept
## the pan in the hand with no key down. Only the window's own motion asks it,
## since a suite that holds a key through the machine alone tells the engine
## nothing.
func _resync_stuck_modifiers(every_key: bool = false) -> void:
    var changed := false
    for key: int in _held_keys.keys() if every_key else [KEY_ALT, KEY_CTRL, KEY_SHIFT]:
        if _held_keys.has(key) and not Input.is_key_pressed(key as Key) and not Input.is_physical_key_pressed(key as Key):
            _held_keys.erase(key)
            changed = true
    if changed:
        _evaluate_tool()


## The gestures that move the view whatever tool is active: the wheel and a
## pinch zoom about the pointer, a two-finger pan, two fingers on a touch
## screen, and the drag of a button bound to pan, which `_pan_with` starts. A touch is always the view's, so one
## finger alone is taken here and taps, picks or pans, and a palm never paints. A
## Shift left drag under the pan tool turns the view too, which
## `_turn_with_left` starts.
##
## Here rather than in a tool state because they have to work while the brush is
## active, and beside `SaShiftPress` because that is the pattern for a
## gesture that outranks the active tool. Returns true when the event belongs to
## the view, and the caller then keeps it away from the tool: a wheel notch must
## not reach a tool that would read it as a button.
##
## The anchor is the event's `position`, which is local to the full-rect control
## that receives input, the same space the canvas's own position is in, so the
## view needs no conversion (SaView.zoom_at).
func _handle_view_navigation(event: InputEvent) -> bool:
    if surface == null or surface.view == null:
        return false
    var view := surface.view

    var button := event as InputEventMouseButton
    if button != null:
        if button.button_index == MOUSE_BUTTON_LEFT:
            return _turn_with_left(button)
        var is_wheel := button.button_index == MOUSE_BUTTON_WHEEL_UP or button.button_index == MOUSE_BUTTON_WHEEL_DOWN
        if not is_wheel:
            return false
        # A wheel notch arrives as a press and a release. Act once, swallow both.
        if not button.pressed:
            return true
        # A smooth wheel reports a fraction of a notch in `factor`, a clicky one
        # reports nothing, which is one notch.
        var notches := button.factor if button.factor > 0.0 else 1.0
        SaView.Steps.notch(view, notches, button.button_index == MOUSE_BUTTON_WHEEL_UP, button.position)
        _reveal_after_zoom()
        return true

    var finger := event as InputEventScreenTouch
    if finger != null:
        _fingers.touch(finger, view, self)
        return true
    var moved := event as InputEventScreenDrag
    if moved != null:
        if _fingers.drag(moved, view):
            _reveal_after_zoom()
        return true

    var magnify := event as InputEventMagnifyGesture
    if magnify != null:
        view.zoom_by(magnify.factor, magnify.position)
        _reveal_after_zoom()
        return true

    var pan := event as InputEventPanGesture
    if pan != null:
        # The picture follows the fingers, as a page does under a two-finger
        # scroll. Godot hands the delta as a scroll distance, pointing against
        # the fingers, so it is subtracted. The suite test_touch_gestures sends
        # fingers moving right and down and reads the picture moving right and
        # down. The speed, one pixel of pan per unit of delta, is untried on a
        # real trackpad.
        view.set_pan(view.get_pan() - pan.delta)
        return true

    var motion := event as InputEventMouseMotion
    if motion == null or not _view_drag.follow(motion, view):
        return false
    if _view_drag.kind == SaViewDrag.Kind.ZOOM:
        _reveal_after_zoom()
    return true


## Zooming out reveals chunks that were outside the composited region.
func _reveal_after_zoom() -> void:
    var doc := SaSurface.document_of(surface)
    if doc != null:
        doc.reveal_all_allocated_chunks()


## Tells the surfaces a Shift drag moved the size, [method SaShiftPress.tell_moved_size],
## which the frame's end calls and a suite, which cannot wait, calls here.
func tell_moved_size() -> void:
    _shift.tell_moved_size()


## Where the last Shift press on *canvas* asked the pointer back to.
##
## For the state dump, because nothing else can answer it: Wayland refuses to
## move a client's pointer, so a capture cannot photograph where the cursor
## ended up, and the request is what goes wrong when its two spaces mix. `at` is the
## viewport point, `to` the physical one handed to the warp, and a fixed release
## has `to` equal to the press point times the window's content scale.
static func warp_report(canvas: Node) -> Dictionary:
    var machine := canvas.get_node_or_null("ToolMachine") as ToolMachine
    return machine._shift.last_warp.duplicate(true) if machine != null else {}


## A press or release of one of the pen's buttons, acted on as Preferences >
## Tablet binds it and kept from the tool whatever it is bound to, nothing
## included, so a button does its one action and no other. The
## left button and the wheel are no pen button and fall through. The binding is
## read at every press rather than cached, so a changed row holds at once. A
## middle press follows [method _middle_action].
func _handle_pen_button(event: InputEvent) -> bool:
    var button := event as InputEventMouseButton
    if button == null:
        return false
    var action: Variant = SaSettingsPenButtons.action_for(SaSettings.pen_buttons, button.button_index)
    if action == null:
        return false
    if button.button_index == MOUSE_BUTTON_MIDDLE:
        action = _middle_action(button, String(action))
    match String(action):
        SaSettingsPenButtons.PAN:
            _pan_with(button)
        SaSettingsPenButtons.CONTEXT_MENU:
            _handle_context_menu(button)
        SaSettingsPenButtons.EYEDROPPER, SaSettingsPenButtons.ERASER:
            _hold_tool(button, SaSettingsPenButtons.tool_for(String(action), self))
    return true


## What a middle press does: the pen's Middle row, *pen_row*, when a pen made
## it, and the mouse's own row otherwise, so a wheel press pans while the pen's
## upper button holds the eraser.
##
## A pen made it when the upper barrel told it from the tip, which is Wayland's
## left press after a pen in the air, or when the pointer is a pen's, which
## [member SaCursorPolicy.pointer_is_tablet] answers from the motions before the
## press for a driver that sends the upper button as a middle press itself.
## Decided at the press and kept for the release. A pen that reports no tilt is
## taken for a mouse once its hovers are ten plain motions in a row, so its
## upper button follows the mouse's row there.
func _middle_action(button: InputEventMouseButton, pen_row: String) -> String:
    if button.pressed:
        _middle_is_the_pens = SaHeldButtons.UpperBarrel.made(button) or SaCursorPolicy.pointer_is_tablet
    return pen_row if _middle_is_the_pens else SaSettings.mouse_middle


## Whether *event* is the tip's touch, or a motion or the release of it, made
## while a button bound to Pan or Context menu is held. That touch belongs to
## the button and paints nothing. Wacom's driver sends the upper button as the
## middle one and the tip as a left press under it, so a pan with the button
## held laid a dot where the tip came down, and so did a touch with the button
## on Context menu. The held buttons are read from the press's own mask, which
## a menu that took the button's release cannot leave stale.
func _tip_is_the_buttons(event: InputEvent) -> bool:
    var button := event as InputEventMouseButton
    if button == null:
        return _tip_taken and event is InputEventMouseMotion
    if button.button_index != MOUSE_BUTTON_LEFT:
        return false
    if not button.pressed:
        var was := _tip_taken
        _tip_taken = false
        return was
    _tip_taken = _view_drag.kind in [SaViewDrag.Kind.PAN, SaViewDrag.Kind.ZOOM] or _holds_pan_or_menu(button.button_mask)
    return _tip_taken


## Whether *mask* holds a button bound to Pan or Context menu, the middle one
## by the row its press followed.
func _holds_pan_or_menu(mask: int) -> bool:
    for index: int in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_XBUTTON1, MOUSE_BUTTON_XBUTTON2]:
        if mask & (1 << (index - 1)) == 0:
            continue
        var action: Variant = SaSettingsPenButtons.action_for(SaSettings.pen_buttons, index)
        if action != null and index == MOUSE_BUTTON_MIDDLE and not _middle_is_the_pens:
            action = SaSettings.mouse_middle
        if action in [SaSettingsPenButtons.PAN, SaSettingsPenButtons.CONTEXT_MENU]:
            return true
    return false


## A press of a button bound to pan starts the drag the motion branch of
## `_handle_view_navigation` follows, a pan, a turn with Shift down and a zoom
## with Ctrl, [SaViewDrag]. The release ends it.
func _pan_with(button: InputEventMouseButton) -> void:
    if surface != null and surface.view != null:
        _view_drag.button(button, surface.view)


## A left press with Shift down, under a tool whose descriptor sets
## [member SaToolDescriptor.turns_view_on_shift_drag], starts the turn a Shift
## press of the pan button starts, and the left release ends it. True when the
## event is the turn's, and the tool then sees none of it.
##
## The pan tool sets it, and Space holds the pan tool, so Shift, Space and a
## pen drag turn the view as they do in Krita, where they had panned and turned
## it 0 degrees. A pen's tip is the left button, so this is the turn a pen
## makes with no barrel button given to pan. Shift released during the drag
## goes on turning, as the pan button's turn does.
func _turn_with_left(button: InputEventMouseButton) -> bool:
    if not button.pressed:
        return _view_drag.left_released()
    var descriptor := get_descriptor(active_tool_name)
    if not button.shift_pressed or descriptor == null or not descriptor.turns_view_on_shift_drag:
        return false
    _view_drag.turn_with_left(button.position, surface.view)
    return true


## A button bound to a tool while held swaps it in on the press and hands the
## permanent one back on the release, through the resolution a quick key uses,
## so a stroke under way is blocked as it is for a key. A registry holding no
## tool of that id leaves the button doing nothing. The stroke the button made,
## when the pen touched with it down, is closed before the tool is handed back.
func _hold_tool(button: InputEventMouseButton, tool_id: StringName) -> void:
    if button.pressed:
        _held.press(button.button_index, tool_id)
    else:
        _feed_tool(_held.release(button))
    _evaluate_tool()


## A press of a button bound to the context menu asks for it. Not while the left
## button is down: a pen's barrel button is often the right one, and a menu over
## a stroke in progress is worse than no menu. The release is swallowed with it.
##
## **The brush asks for the Brush Presets docker instead**, so a right click
## with the brush in hand opens the presets. The brush tool therefore has no
## context menu, and that is a choice rather than an oversight: every other
## tool keeps it, and taking the line below out is what gives the brush its
## menu back.
##
## A modified press belongs to whatever reads the modifier. The ALT right drag
## that resizes a docker is the drag handle's, and the shift drag that resizes
## the brush is a left one, which `SaShiftPress` takes.
func _handle_context_menu(button: InputEventMouseButton) -> void:
    if not button.pressed or (button.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
        return
    if button.alt_pressed or button.ctrl_pressed or button.shift_pressed:
        return
    if _right_click_opens_a_docker(button.global_position):
        return
    context_menu_requested.emit(button.global_position)


## Whether the active tool answers a right click with a docker under the
## pointer rather than with the context menu, and it did if this says so. The
## docker is Brush Presets or the pop-up palette, as the painter chose on
## Preferences > Brushes, which `SaRightClickDocker` reads.
##
## **A second press sends it back**, because a right click that opens it should
## close it too. Each docker's own `toggle_at` lends it under the pointer and
## sends it home, so the place the painter gave it and the layout's name are
## never written.
##
## Asked of [member SaToolDescriptor.opens_docker_on_right_click] rather than
## of `is_painting`, because a painting tool that takes no presets has nothing
## to lend, while the Brush and the Eraser, which share theirs, both opt in
##. A member rather than the brush's id, so a
## module's own brush takes the gesture on the same terms. The docker is asked
## through `SaRightClickDocker`, because a tool machine names no docker class.
##
## *at* is the press's own point in the window's logical units, which the
## canvas menu opens at too. The pointer read back from the system came
## in the screen's pixels at a UI scale above 1 and put the docker that many
## times as far from the window's corner.
func _right_click_opens_a_docker(at: Vector2) -> bool:
    if not is_inside_tree():
        return false
    var descriptor := get_descriptor(active_tool_name)
    if descriptor == null or not descriptor.opens_docker_on_right_click:
        return false
    var window := get_window()
    if window == null:
        return false
    return SaRightClickDocker.toggle_at(at)


## Key events forwarded from a focused docker window, so quick tools work when a
## docker has focus.
##
## Enter and Escape go on to the active tool, because they are a tool's own
## keys: the polygon lasso closes on one and abandons on the other, and the
## crop tool applies and cancels. A Control sees a key through `gui_input` only
## while it has focus and the canvas takes none, so this is the only door
## either of them has. Everything else a tool needs arrives as a mouse event.
## A bare key the tool keeps, [method ToolState.keeps_key], goes to it too and
## answers true, so the router lets no shortcut have it.
func handle_key_event(event: InputEventKey) -> bool:
    _update_held_keys(event)
    _evaluate_tool()
    if active_tool == null:
        return false
    var kept := event.get_modifiers_mask() == 0 and active_tool.keeps_key(event.keycode)
    if kept or event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE]:
        active_tool.handle_input(event)
    return kept


## Tools hold the surface, the surface holds the easel, and the easel owns
## GPU resources - so a machine that keeps its instances past teardown keeps the
## whole chain alive.
func _exit_tree() -> void:
    if registry != null and registry.changed.is_connected(_rebuild_tools):
        registry.changed.disconnect(_rebuild_tools)
    if surface != null and surface.view != null:
        if surface.view.transform_changed.is_connected(_on_view_transform_changed):
            surface.view.transform_changed.disconnect(_on_view_transform_changed)
    for tool_id: StringName in registered_tools:
        registered_tools[tool_id].surface = null
        registered_tools[tool_id].hand_back = Callable()
    registered_tools.clear()
    active_tool = null
    surface = null
    registry = null


func refresh_cursor() -> void:
    _update_cursor()


## The brush radius lives on the tool's settings object, which a slider writes
## directly and which has no way to announce the change. Nothing republished the
## ring, so it kept the size it had at the last tool switch and only caught up
## when something else happened to call refresh_cursor().
##
## Polling here is the same trade the CursorOverlay makes: the check is two
## property reads and a multiply, and the work only happens when the answer moved.
func _process(delta: float) -> void:
    if surface == null:
        return
    # A pin outliving the gesture is a cursor that never moves again, and a
    # release can go missing: the window loses focus mid-drag, or the tool is
    # swapped from under the gesture. Dropping it here costs one comparison a
    # frame and makes the worst case last one frame. Only a pin this machine
    # owns is dropped, or the scratchpad's machine would unpin the main canvas's
    # gesture. One line for the airbrush: a tool that deposits paint on a
    # pointer that is not moving has no input event to hang the work on, and
    # `ToolState` is a `RefCounted` with no tree to put a Timer in. Every tool
    # but the brush inherits the base class's no-op.
    if active_tool != null:
        active_tool.tick(delta)
    _show_tooltip()
    if not _shift.held:
        SaCursorPolicy.unpin_pointer(self)
    if not is_equal_approx(_wanted_ring_radius(), surface.cursor_ring_radius):
        _update_cursor()
        return
    # The shape as well as the radius. A painter loading an image tip changes
    # neither the tool nor the size, so nothing else would ask again and the
    # ring would keep the last tip's outline until the brush was resized.
    # `SaTipImage` memoises the transformed points, so this is a dictionary hit
    # a frame rather than a silhouette a frame.
    if _wanted_cursor_outline() != surface.cursor_outline:
        _update_cursor()
    elif _wanted_cursor_shape() != _cursor_shape_shown or _wanted_cursor_picture() != _cursor_picture_shown:
        _update_cursor()


## Ring radius the active tool wants right now, or -1.0 when it wants none.
func _wanted_ring_radius() -> float:
    if pointer_holder != &"":  # The holder owns the pointer, not the tool.
        return -1.0
    var descriptor := get_descriptor(active_tool_name)
    if descriptor == null or not descriptor.wants_brush_cursor or active_tool == null:
        return -1.0
    var radius := active_tool.get_cursor_radius()
    var zoom := surface.view.get_zoom() if surface != null and surface.view != null else 1.0
    return (radius if radius >= 0.0 else 10.0) * zoom


## The outline the active tool wants the ring drawn as, or empty for the
## circle. Answered by the descriptor rather than stored on it, because the
## shape changes whenever a painter loads a tip and a descriptor is registered
## once.
func _wanted_cursor_outline() -> PackedVector2Array:
    if pointer_holder != &"":  # The holder owns the pointer, not the tool.
        return PackedVector2Array()
    var descriptor := get_descriptor(active_tool_name)
    if descriptor == null or not descriptor.wants_brush_cursor or not descriptor.cursor_outline.is_valid():
        return PackedVector2Array()
    var answered: Variant = descriptor.cursor_outline.call()
    return answered if answered is PackedVector2Array else PackedVector2Array()


## The OS shape the active tool wants, its own answer where it gives one and
## its descriptor's otherwise.
func _wanted_cursor_shape() -> int:
    var asked := active_tool.cursor_shape() if active_tool != null else -1
    if asked >= 0:
        return asked
    var descriptor := get_descriptor(active_tool_name)
    return descriptor.cursor_shape if descriptor != null else Control.CURSOR_ARROW


## The picture the active tool wants in that shape's slot where the pointer is
## now, or null. None while a holder owns the pointer, as with the ring.
func _wanted_cursor_picture() -> SaCursorPicture:
    if pointer_holder != &"" or active_tool == null:
        return null
    return active_tool.cursor_picture()


## Writes the active tool's tooltip onto the canvas the engine shows it from,
## and only when it moved, so the one the pointer rests on is the one the tool
## says is under it. None while a holder owns the pointer, as with the ring.
func _show_tooltip() -> void:
    var canvas := (surface.view as SaCanvasView).canvas if surface.view is SaCanvasView else null
    var wanted := active_tool.tooltip() if active_tool != null and pointer_holder == &"" else ""
    if canvas != null and canvas.tooltip_text != wanted:
        canvas.tooltip_text = wanted


func _on_view_transform_changed() -> void:
    _update_cursor()


## Publishes the brush-ring radius and OS cursor shape for the active tool, both
## read from its descriptor, the shape from the tool first where it asks for one,
## and the picture the tool asks to stand in that shape's slot where it is.
##
## The note mode is the one thing that overrules the descriptor, because it puts
## a window of its own over the canvas and the canvas would otherwise go on
## claiming the pointer underneath it.
func _update_cursor() -> void:
    if surface == null:
        return
    var descriptor := get_descriptor(active_tool_name)

    surface.cursor_ring_radius = _wanted_ring_radius()
    surface.cursor_outline = _wanted_cursor_outline()

    var shape := _wanted_cursor_shape()
    _cursor_shape_shown = shape
    var picture := _wanted_cursor_picture()
    _cursor_picture_shown = picture
    if pointer_holder != &"":  # The same reason as the ring above.
        shape = pointer_holder_shape
    if surface.view is SaCanvasView:
        var canvas := (surface.view as SaCanvasView).canvas
        if canvas != null:
            SaCursorPolicy.apply_tool_cursor(canvas, descriptor, shape, picture)
            canvas.cursor_ring_radius = surface.cursor_ring_radius
            # Beside the radius and from the same descriptor, because a shape
            # is drawn at a radius and the two arriving separately is how a
            # ring comes to be the wrong size for its outline.
            canvas.cursor_outline = surface.cursor_outline

    SaCursorPolicy.sync_os_cursor_visibility()
