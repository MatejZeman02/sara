## Hosts a canvas view and routes input to its ToolMachine.
##
## Owns the surface: an easel (document + compositor, no UI), the view over
## it, and the tool machine driving it. The same class serves the main canvas and
## the info docker's scratchpad, `embedded` decides which tools are offered.
extends VBoxContainer

## How near a symmetry handle a press has to land to take it, then how near a
## drawn axis, in screen pixels at every zoom.
const AXIS_HANDLE_REACH: float = 8.0
const AXIS_LINE_REACH: float = 6.0
## The name the axes hold the pointer under, in `ToolMachine.pointer_holder`.
const AXES_HOLDER := &"symmetry_axes"
## How far in from the window's top and bottom edge a finger's landing belongs
## to the system's swipe rather than the canvas, in logical pixels. See
## `at_system_edge`.
const SYSTEM_EDGE: float = 24.0

var control_node: Control
var canvas: SaCanvas
var tool_machine: ToolMachine

## Handed to tools instead of a Control. Built in _ready once the canvas has a
## easel.
var surface: SaSurface

## Embedded surfaces offer only tools whose descriptor allows it.
var embedded: bool = false

## True between a painting tool's press and its release, while this surface owns
## the pointer regardless of what it is currently over.
var _capturing_stroke: bool = false

## The stroke recording of the learned lead spec, open only when the process
## asked for one and this is the main surface, see SaStrokeRecorder.
var _stroke_recorder: SaStrokeRecorder

## The buttons held since a press this surface took at the window, each as
## `1 << (index - 1)`, so a drag of the middle, right or an extra button is
## followed at the window wherever it goes, see _on_window_input.
var _dragging: int = 0

## True between a left press on the symmetry axes and its release, while the
## axes own the pointer and the tool sees none of it.
var _axes_held: bool = false
## What the held press grips, `SaSymmetry.HIT_*`: a handle, a line, or nothing
## after a double click put the axes back.
var _axes_grip: int = SaSymmetry.HIT_NONE
## Where that press landed and the axes as they stood, in document pixels, so a
## line drag moves the centre by the pointer's travel and a release that moved
## nothing marks nothing.
var _axes_press: Vector2 = Vector2.ZERO
var _axes_before: Array = []
## The line of an effect layer while a press holds it, `SaEffectGuide`, which
## shares `_axes_held` with the symmetry axes: one drag at a time, the tool
## sees none of it.
var _guide: SaEffectGuide = null

## The buttons, a mask of `MOUSE_BUTTON_MASK_*`, and the fingers, by index, whose
## press put a top menu or the Welcome window away and so reached no tool, each
## kept from the tool until it lifts. See `_hold_back`.
var _held_buttons: int = 0
var _held_fingers: Dictionary = {}

## The id the surface is built under: `main` for the canvas Sara starts with,
## and one of its own for every further document's view, see `SaDocumentTabs`.
var _surface_id: StringName = &"main"


## *surface_id* names the surface this view builds. Only the first view keeps
## the node name `MainCanvas`, which main finds it by.
func _init(surface_id: StringName = &"main") -> void:
    _surface_id = surface_id
    name = "MainCanvas" if surface_id == &"main" else String(surface_id).to_pascal_case()
    set_anchors_preset(Control.PRESET_FULL_RECT)
    size_flags_horizontal = SIZE_EXPAND_FILL
    size_flags_vertical = SIZE_EXPAND_FILL

    control_node = Control.new()
    control_node.name = "Control"
    control_node.size_flags_horizontal = SIZE_EXPAND_FILL
    control_node.size_flags_vertical = SIZE_EXPAND_FILL
    control_node.mouse_filter = MOUSE_FILTER_PASS
    add_child(control_node)

    canvas = SaCanvas.new()
    canvas.name = "Canvas"
    control_node.add_child(canvas)
    canvas.unique_name_in_owner = true
    canvas.owner = self

    tool_machine = preload("res://tools/tool_machine.gd").new()
    tool_machine.name = "ToolMachine"
    tool_machine.process_mode = PROCESS_MODE_ALWAYS
    canvas.add_child(tool_machine)
    tool_machine.unique_name_in_owner = true
    tool_machine.owner = self


func _ready() -> void:
    # Listen on the full-rect Control rather than on the canvas itself.
    #
    # SaCanvas is a TextureRect sized to the document, so its rect covers only the
    # painted area. Connecting gui_input there meant tools stopped receiving input
    # the moment the pointer left the document, panning and zooming died in the
    # surrounding grey, which is exactly where you reach for them when zoomed in.
    #
    # The canvas keeps MOUSE_FILTER_PASS, so events over it pass up to this Control
    # and are delivered exactly once from here, whether or not they were over the
    # document. Tools work in document space via canvas.get_local_mouse_position(),
    # which stays correct outside the canvas rect (it simply returns coordinates
    # outside the document bounds).
    control_node.gui_input.connect(_on_canvas_gui_input)
    control_node.mouse_exited.connect(_on_pointer_left)
    _build_surface()
    # The quick mask's own line over the picture. Only the main surface: the
    # scratchpad has no selection a painter edits.
    if not embedded:
        for factory in SaCanvas.surface_overlay_factories:
            factory.call(control_node, canvas)
        if not RenderingServer.frame_post_draw.is_connected(SaStrokeLedger.frame_drawn):
            RenderingServer.frame_post_draw.connect(SaStrokeLedger.frame_drawn)
        var loop := Engine.get_main_loop() as SceneTree
        if loop != null and not loop.process_frame.is_connected(SaStrokeLedger.frame_ticked):
            loop.process_frame.connect(SaStrokeLedger.frame_ticked)


## The window's input signal is the one hook that runs before the engine routes
## an event, and a docker can be moved between windows, so the connection follows
## the surface in and out of the tree.
func _enter_tree() -> void:
    var window := get_window()
    if window != null and not window.window_input.is_connected(_on_window_input):
        window.window_input.connect(_on_window_input)
    if _stroke_recorder == null and not embedded and _surface_id == &"main":
        var folder := SaStrokeRecorder.requested_folder()
        if not folder.is_empty():
            _stroke_recorder = SaStrokeRecorder.new(folder, _recording_session(window))
            if _stroke_recorder.is_recording():
                print("SaStrokeRecorder: recording every pointer reading to ", _stroke_recorder.path)


func _exit_tree() -> void:
    var window := get_window()
    if window != null and window.window_input.is_connected(_on_window_input):
        window.window_input.disconnect(_on_window_input)
    _dragging = 0
    _axes_held = false
    _guide = null
    _held_buttons = 0
    _held_fingers.clear()
    if ToolMachine.pointer_holder == AXES_HOLDER:
        ToolMachine.pointer_holder = &""
    if _stroke_recorder != null:
        _stroke_recorder.close()
        _stroke_recorder = null


## What the header of a stroke recording says about this run: the driver, the
## screen and its refresh rate, the window's scale and the prediction setting,
## because a recording with the prediction on is another data set.
func _recording_session(window: Window) -> Dictionary[String, Variant]:
    var screen := DisplayServer.window_get_current_screen()
    return {
        "display_driver": DisplayServer.get_name(),
        "screen_size": [DisplayServer.screen_get_size(screen).x, DisplayServer.screen_get_size(screen).y],
        "refresh_hz": DisplayServer.screen_get_refresh_rate(screen),
        "content_scale": window.content_scale_factor if window != null else 1.0,
        "cursor_prediction_ms": SaSettings.cursor_prediction_ms,
        "version": ProjectSettings.get_setting("application/config/version", ""),
    }


## Creates the surface over this canvas's easel. Safe to call again once the
## easel exists.
func _build_surface() -> SaSurface:
    if surface != null:
        return surface
    if canvas == null:
        return null
    # Not canvas.easel: binding must work before the canvas enters the tree,
    # or tool registration silently does nothing depending on _ready order.
    if canvas.ensure_easel() == null:
        return null
    # The document Sara starts with is in the same space File > New opens on,
    # read from one place, because `create_default` names no space and two
    # defaults kept apart agree only by coincidence. Only the main canvas,
    # because the Info docker's scratchpad is a swatch rather than a document
    # and every suite that builds a canvas wants the plain sRGB one
    # `create_default` gives.
    if not embedded:
        canvas.document.reset_to_default(canvas.canvas_size, SaEasel.default_space())
        # `create_default` above allocates the output at its own null-space
        # F32 default, before this reset moves the document to F16, and
        # nothing else re-derives the output from the document it now holds.
        # Without this every stroke's scratch chunk (F16, following the
        # document) meets the compositor's storage-format guard against the
        # stale F32 canvas and silently never draws.
        # `resize_canvas` is the same size, but it is also the sanctioned way
        # to rebind the view's Texture2DRD to a re-allocated output, which a
        # bare `easel.resize_output` here does not do.
        canvas.resize_canvas(canvas.canvas_size)
    surface = SaSurface.create(&"scratchpad" if embedded else _surface_id, canvas.easel, SaCanvasView.for_canvas(canvas))
    surface.is_embedded = embedded
    return surface


## Shows this view as the document in front, or hides it behind another's tab.
## A hidden view runs nothing: its tool machine, which runs even while the
## tree is paused, stops with it, so no cursor and no airbrush tick of a
## document out of sight competes with the one in front.
func show_as_front(front: bool) -> void:
    visible = front
    process_mode = PROCESS_MODE_INHERIT if front else PROCESS_MODE_DISABLED
    if tool_machine != null:
        tool_machine.process_mode = PROCESS_MODE_ALWAYS if front else PROCESS_MODE_DISABLED
    if not front:
        _dragging = 0


## Instantiates this surface's tools from the registry. Called by the host after
## modules have registered, so the tools a module adds appear here too.
func bind_tools(registry: SaToolRegistry, roles: SaRoleRegistry = null, pens: SaPenRegistry = null) -> void:
    if _build_surface() == null:
        return
    tool_machine.bind(surface, registry, roles, pens)


func _on_canvas_gui_input(event: InputEvent) -> void:
    # The view gestures and the right button were already taken at the window,
    # and a window handler cannot mark an event handled, so the same event
    # arrives here a second time whenever no docker held focus. Once is enough.
    if _is_view_gesture(event) or _is_right_button(event) or (_dragging != 0 and event is InputEventMouseMotion):
        return
    # A finger's mouse copy must not start a capture the tool machine will
    # never see the end of.
    if event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION:
        return
    event = _past_the_hold(event)
    if event == null or _take_axes(event):
        return
    var button := event as InputEventMouseButton
    if button != null and button.button_index == MOUSE_BUTTON_LEFT:
        _capturing_stroke = button.pressed and _active_tool_paints()
    tool_machine.handle_input(event)


## Gives a press on the symmetry axes to the axes rather than to the tool, and
## answers whether it did. Asked ahead of the tool machine, whose tool would
## paint the press or sample it, and only while the axes are drawn and the tool
## in hand works on the paint at a point. Hovering a handle or a line holds the
## pointer for a move cursor in place of the brush ring, and a double click puts
## the axes back.
func _take_axes(event: InputEvent) -> bool:
    var mouse := event as InputEventMouse
    if mouse == null or _capturing_stroke or _axes_held:
        return false
    var guide_grip := SaEffectGuide.HIT_NONE
    var guide := _guide_at(mouse.position)
    if guide != null:
        guide_grip = guide.hit(_document_point(mouse.position), AXIS_HANDLE_REACH * _per_pixel(), AXIS_LINE_REACH * _per_pixel())
    var grip := _axes_hit(mouse.position) if guide_grip == SaEffectGuide.HIT_NONE else guide_grip
    _hold_pointer_for_axes(grip != SaSymmetry.HIT_NONE)
    var button := event as InputEventMouseButton
    if grip == SaSymmetry.HIT_NONE or button == null or button.button_index != MOUSE_BUTTON_LEFT or not button.pressed:
        return false
    if guide_grip != SaEffectGuide.HIT_NONE:
        _axes_held = true
        _guide = guide
        guide.press(guide_grip, _document_point(mouse.position))
        return true
    var symmetry := canvas.document.symmetry
    _axes_held = true
    _axes_grip = grip
    _axes_press = _document_point(mouse.position)
    _axes_before = [symmetry.center, symmetry.angle, symmetry.reach]
    if button.double_click:
        _axes_grip = SaSymmetry.HIT_NONE
        symmetry.reset_axes(Vector2(canvas.document.canvas_size))
        _mark_axes_moved()
    return true


## Follows the held axes with a motion or ends them with the release, from
## `_input`, so a drag over a docker keeps them. A handle follows the pointer,
## turned in whole steps while Shift is held, and a line moves the centre by the
## pointer's travel without turning.
func _drag_axes(event: InputEvent) -> void:
    var button := event as InputEventMouseButton
    var is_release: bool = button != null and button.button_index == MOUSE_BUTTON_LEFT and not button.pressed
    if not (event is InputEventMouseMotion or is_release):
        return
    var mouse := event as InputEventMouse
    var local: Vector2 = (_local(event) as InputEventMouse).position
    var symmetry := canvas.document.symmetry
    var bounds := Vector2(canvas.document.canvas_size)
    var point := _document_point(local)
    if _guide != null:
        _guide.drag(point, mouse.shift_pressed)
    elif _axes_grip == SaSymmetry.HIT_LINE:
        var start: Vector2 = _axes_before[0]
        symmetry.center = (start + point - _axes_press).clamp(Vector2.ZERO, bounds)
    elif _axes_grip != SaSymmetry.HIT_NONE:
        symmetry.move_handle(_axes_grip, point, bounds, mouse.shift_pressed)
    if is_release:
        _axes_held = false
        _axes_grip = SaSymmetry.HIT_NONE
        if _guide != null:
            _guide.release()
            _guide = null
        else:
            _mark_axes_moved()
        _hold_pointer_for_axes(_axes_hit(local) != SaSymmetry.HIT_NONE or _guide_at(local) != null)
    var viewport := get_viewport()
    if viewport != null:
        viewport.set_input_as_handled()


## What of the symmetry axes is under *local*, a point in this surface's
## control, as `SaSymmetry.hit` answers, or `HIT_NONE` while the axes are not
## drawn or the tool in hand is not one a press on them would reach.
func _axes_hit(local: Vector2) -> int:
    if canvas == null or canvas.document == null or tool_machine == null:
        return SaSymmetry.HIT_NONE
    var symmetry := canvas.document.symmetry
    if not symmetry.is_active() or not _tool_works_on_paint():
        return SaSymmetry.HIT_NONE
    var per_pixel := _per_pixel()
    var bounds := Vector2(canvas.document.canvas_size)
    return symmetry.hit(_document_point(local), AXIS_HANDLE_REACH * per_pixel, AXIS_LINE_REACH * per_pixel, bounds)


## Whether the tool in hand acts on the paint under a point: the painting tools
## and the eyedropper. A selection, a transform or a crop drag owns its own press.
func _tool_works_on_paint() -> bool:
    var descriptor := tool_machine.get_descriptor(tool_machine.active_tool_name) if tool_machine != null else null
    return descriptor != null and (descriptor.is_painting or descriptor.category == &"sample")


## The line of the active effect layer, when it is drawn and the tool in hand is
## one a press on it would reach, as `SaEffectGuide.of` answers, and *local*, a
## point in this surface's control, is on it or one of its handles.
func _guide_at(local: Vector2) -> SaEffectGuide:
    if canvas == null or canvas.document == null or canvas.compositor == null or not _tool_works_on_paint():
        return null
    var guide := SaEffectGuide.of(canvas.document, canvas.compositor.filter_chain.registry)
    if guide == null:
        return null
    var grip := guide.hit(_document_point(local), AXIS_HANDLE_REACH * _per_pixel(), AXIS_LINE_REACH * _per_pixel())
    return guide if grip != SaEffectGuide.HIT_NONE else null


## Document pixels to a screen pixel at the current zoom.
func _per_pixel() -> float:
    return 1.0 / maxf(absf(canvas.scale.x), 0.01)


## *local*, a point in this surface's control, in document pixels.
func _document_point(local: Vector2) -> Vector2:
    return canvas.get_transform().affine_inverse() * local


## Raises the document's modified mark when the held axes moved. The axes are
## saved with the document and are not a history step, so this is the raise a
## colour space change makes.
func _mark_axes_moved() -> void:
    var symmetry := canvas.document.symmetry
    if _axes_before != [symmetry.center, symmetry.angle, symmetry.reach]:
        canvas.document.modified = true


## Takes the pointer from the tool for the axes or hands it back, through the
## holder the note mode uses, so the ring gives way to a move cursor. A holder
## other than the axes is left alone.
func _hold_pointer_for_axes(holding: bool) -> void:
    var held := ToolMachine.pointer_holder == AXES_HOLDER
    if holding == held or (holding and ToolMachine.pointer_holder != &""):
        return
    ToolMachine.pointer_holder = AXES_HOLDER if holding else &""
    ToolMachine.pointer_holder_shape = Control.CURSOR_MOVE
    tool_machine.refresh_cursor()


## The pointer left the surface for a docker or the bar, where no handle is.
func _on_pointer_left() -> void:
    if not _axes_held:
        _hold_pointer_for_axes(false)


## Keeps a stroke alive when the pointer crosses onto a docker or the top bar.
##
## Godot forwards motion to whichever Control received the press, but an
## embedded subwindow is hit-tested before the host's GUI and takes the events
## instead, so a stroke would die the moment the pointer touched a docker,
## mid-line, with the button still down. _input runs ahead of that hit-test, so
## while a stroke owns the pointer its events are delivered here and marked
## handled, which also stops the docker underneath reacting to a drag that was
## never meant for it.
##
## Only motion and the release are captured. The pointer still reverts to the
## system cursor over UI (the ring is suppressed there), so the user can see what
## they are about to interact with once they let go.
func _input(event: InputEvent) -> void:
    if _axes_held:
        _drag_axes(event)
        return
    if not _capturing_stroke:
        return

    # Annotated, not inferred: a comparison chain starting from a bare InputEvent
    # has no set type, which is a parse error rather than a warning.
    var button := event as InputEventMouseButton
    var is_release: bool = button != null and button.button_index == MOUSE_BUTTON_LEFT and not button.pressed
    if not (event is InputEventMouseMotion or is_release):
        return

    tool_machine.handle_input(event)
    if is_release:
        _capturing_stroke = false

    var vp := get_viewport()
    if vp != null:
        vp.set_input_as_handled()


## Takes a wheel notch, a middle drag or a trackpad gesture that lands over this
## surface, at the window, before the engine routes the event anywhere.
##
## A focused embedded docker receives every mouse event except a left press
## outside it, which is the one thing that unfocuses it, and that forwarding runs
## before any node's _input. So after one click on a docker, a wheel over the
## canvas goes to the docker and a middle drag moves nothing, until a left click
## lands on the canvas. The window's
## input signal fires first of all, so the gestures that move the view are taken
## here whenever the point is this surface's own: inside its control, under no
## docker, and under no other control such as a slider on the bar. The copy the
## engine goes on to route lands on a docker that has nothing at that position,
## or on this control's gui_input, which skips it.
func _on_window_input(raw: InputEvent) -> void:
    # A document behind another's tab still hears the window, and takes nothing.
    if tool_machine == null or control_node == null or not is_visible_in_tree():
        return
    # The window's signal runs before a gate of the lock can turn the event away.
    if SaCursorPolicy.drops_system_pointer(raw):
        return
    ToolMachine.InputTrail.note(raw)
    var window := get_window()
    if window == null:
        return
    if raw is InputEventScreenTouch or raw is InputEventScreenDrag:
        var finger := raw.xformed_by(window.get_final_transform().affine_inverse())
        if not _hold_back(raw, finger):
            _take_touch(finger)
        return
    if not (raw is InputEventMouse or raw is InputEventGesture):
        return
    SaStrokeLedger.event_arrived(raw is InputEventMouseMotion)
    SaStrokeLedger.left_button(raw as InputEventMouseButton)
    # The signal carries the event as the window received it, before the
    # viewport un-scales it, so on a 2x display the position is twice the
    # logical one every rect here is measured in.
    var event := raw.xformed_by(window.get_final_transform().affine_inverse())
    if _stroke_recorder != null and control_node != null:
        _stroke_recorder.record(
            event, window.get_visible_rect().size, control_node.get_global_rect(), canvas.get_global_transform()
        )

    # The upper barrel's hover, which never reaches the GUI while another window holds the focus.
    if event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION:
        tool_machine.pen_moved(event as InputEventMouseMotion)

    if _hold_back(raw, event):
        return

    var button := event as InputEventMouseButton
    var bit := 0 if button == null else 1 << (button.button_index - 1)
    if _dragging != 0 and _follow_drag(event, bit):
        return

    # The right button is taken here for the reason the view gestures are, and
    # then some. Godot moves the embedded subwindow focus on a left press and
    # on nothing else, so every other button is handed to whichever docker
    # already holds that focus and, when the point is not inside it, given to
    # nobody at all. A docker holds it from startup, so the right press that
    # opens the Brush Presets docker and the tool context menu would both be
    # dead until the painter left-clicked the canvas once. Taken at the window
    # this runs before that forwarding, and `_owns_point` refuses every point
    # a docker covers, so the two routes cannot both answer one press.
    if _is_right_button(event):
        if _owns_point(_point_of(event)) or not button.pressed:
            tool_machine.handle_input(_local(event))
            if button.pressed:
                _dragging |= bit
        return

    if not _is_view_gesture(event) or not _owns_point(_point_of(event)):
        return
    tool_machine.handle_input(_local(event))
    if button != null and button.button_index == MOUSE_BUTTON_MIDDLE and button.pressed:
        _dragging |= bit


## Gives the tool the motions and the release of a button whose press this took
## at the window, wherever they land, and answers whether *event* was one. A
## docker holding the subwindow focus is handed every mouse event before the
## GUI, and only a left press moves that focus, so a drag of any other button
## begun under it reaches the GUI nowhere. A stroke under a left press is
## `_input`'s, and hears each motion once.
##
## The motion is noted first, since this signal fires before the cursor overlay
## has seen it, and a tool asking where the pointer is would be a motion behind.
func _follow_drag(event: InputEvent, bit: int) -> bool:
    if event is InputEventMouseMotion:
        if not _capturing_stroke:
            SaCursorPolicy.note_pointer_device(event, get_window())
            tool_machine.handle_input(_local(event))
        return true
    var released := event as InputEventMouseButton
    if released == null or released.pressed or (_dragging & bit) == 0:
        return false
    _dragging &= ~bit
    tool_machine.handle_input(_local(event))
    return true


## Keeps a press that put a top menu or the Welcome window away from the tool,
## with the release and the drag of the button or finger it pressed with, and
## answers whether it kept *event*, the event *raw* its window heard, in this
## surface's space. A press on a docker or on a title is not this surface's and
## goes on, so the main surface asks only for a point `_owns_point` gives it,
## and the Info docker's scratchpad never asks.
##
## **Decided here, at the window, for every button**, because this is the one
## place every press of the main window reaches before anything acts on it: the
## right button and the view gestures are taken here, and the left button's
## press is on its way to the control. `SaPutAway.is_spent` answers whichever of
## this surface, the bar and the Welcome window heard the press first. The left
## button's release and drag go to the control as its press does, and
## `_past_the_hold` keeps them there, so this lets go of every other button.
func _hold_back(raw: InputEvent, event: InputEvent) -> bool:
    if embedded:
        return false
    var button := event as InputEventMouseButton
    if button != null:
        var bit := 1 << (button.button_index - 1)
        if SaPutAway.is_press(button):
            var spent := SaPutAway.is_spent(raw, get_tree()) and _owns_point(button.position)
            _held_buttons = (_held_buttons | bit) if spent else (_held_buttons & ~bit)
            return spent
        # A release, or the wheel, whose bit no press ever set.
        var held := (_held_buttons & bit) != 0
        if held and button.button_index != MOUSE_BUTTON_LEFT:
            _held_buttons &= ~bit
        return held
    var landing := event as InputEventScreenTouch
    if landing != null and landing.pressed:
        var spent := SaPutAway.is_spent(raw, get_tree()) and _owns_point(landing.position)
        if spent:
            _held_fingers[landing.index] = true
        return spent
    if landing != null:
        return _held_fingers.erase(landing.index)
    var drag := event as InputEventScreenDrag
    return drag != null and _held_fingers.has(drag.index)


## The control's half of `_hold_back`. The left press it kept arrives here too
## and goes no further, a drag of it reaches the tool as a hover with the button
## up, which is what moves the ring and samples nothing, and its release lets go.
## Null for an event that goes no further.
func _past_the_hold(event: InputEvent) -> InputEvent:
    if (_held_buttons & MOUSE_BUTTON_MASK_LEFT) == 0:
        return event
    var button := event as InputEventMouseButton
    if button != null and button.button_index == MOUSE_BUTTON_LEFT:
        if not button.pressed:
            _held_buttons &= ~MOUSE_BUTTON_MASK_LEFT
        return null
    var motion := event as InputEventMouseMotion
    if motion == null:
        return event
    var hover := motion.duplicate() as InputEventMouseMotion
    hover.button_mask &= ~MOUSE_BUTTON_MASK_LEFT
    return hover


## A finger on a touch screen, taken at the window for the reason the view
## gestures are. A finger that lands on a docker or another control is not the
## canvas's, and every drag and lift is passed on, because the tool machine
## only follows the fingers it saw land. Nor is a finger that lands on the
## window's top or bottom edge, which is the swipe that calls Android's system
## bars back over a full-screen Sara.
func _take_touch(event: InputEvent) -> void:
    var landing := event as InputEventScreenTouch
    if landing != null and landing.pressed:
        if not _owns_point(landing.position) or at_system_edge(landing.position.y, get_viewport().get_visible_rect().size.y):
            return
    tool_machine.handle_input(_local(event))


## Whether a finger landing *y* logical pixels down a window *height* tall
## lands where Android's own edge swipe begins. Android draws its bars over a
## full-screen app for a moment when a finger swipes in from the top or the
## bottom edge, and the app hears the same swipe, so the canvas leaves that
## finger alone rather than pan the view under the bars. The band is
## `SYSTEM_EDGE` wide, which on a tablet is about Android's 24 dp, since Sara's
## logical pixel there is the screen's dots per inch over 160.
static func at_system_edge(y: float, height: float) -> bool:
    return y < SYSTEM_EDGE or y > height - SYSTEM_EDGE


## A right press or release, which is the tool context menu's gesture and the
## Brush Presets docker's. Motion is not in it: no right drag belongs to the
## tool machine, and the ALT one that resizes a docker is the drag handle's.
static func _is_right_button(event: InputEvent) -> bool:
    var button := event as InputEventMouseButton
    return button != null and button.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_XBUTTON1, MOUSE_BUTTON_XBUTTON2]


## The gestures that move the view whatever the tool: the wheel, the middle
## button, and the two trackpad gestures.
static func _is_view_gesture(event: InputEvent) -> bool:
    var button := event as InputEventMouseButton
    if button != null:
        return (
            button.button_index == MOUSE_BUTTON_MIDDLE
            or button.button_index == MOUSE_BUTTON_WHEEL_UP
            or button.button_index == MOUSE_BUTTON_WHEEL_DOWN
        )
    return (
        event is InputEventMagnifyGesture
        or event is InputEventPanGesture
        or event is InputEventScreenTouch
        or event is InputEventScreenDrag
    )


## Where *event* happened, for the four kinds `_is_view_gesture` and
## `_is_right_button` let through, which share a `position` and no base class
## that declares it.
static func _point_of(event: InputEvent) -> Vector2:
    var mouse := event as InputEventMouse
    if mouse != null:
        return mouse.position
    var gesture := event as InputEventGesture
    if gesture != null:
        return gesture.position
    var touch := event as InputEventScreenTouch
    if touch != null:
        return touch.position
    var drag := event as InputEventScreenDrag
    if drag != null:
        return drag.position
    return Vector2.ZERO


## The event as gui_input would hand it over, local to the control, so the view's
## anchor needs no second convention.
##
## The global position is set as well, to the point in the window's logical
## coordinates *event* is in, because `xformed_by` moves `position` alone and
## leaves the physical pixels the window heard there. The tool machine hands that
## number to the context menu, which opened twice as far from the corner as the
## pointer on a window scaled by 2.
func _local(event: InputEvent) -> InputEvent:
    var local := event.xformed_by(control_node.get_global_transform().affine_inverse())
    var mouse := local as InputEventMouse
    if mouse != null:
        mouse.global_position = (event as InputEventMouse).position
    return local


## Whether *point*, in this viewport's coordinates, is this surface's to act on:
## inside its control, and under no docker and no other control drawn over it.
func _owns_point(point: Vector2) -> bool:
    if not control_node.get_global_rect().has_point(point):
        return false
    var viewport := get_viewport()
    for sub in SaCursorPolicy.embedded_subwindows(viewport):
        if Rect2(Vector2(sub.position), Vector2(sub.size)).has_point(point):
            return false
    return not _other_control_at(viewport, point)


## A visible Control outside this surface that would take a click at *point*.
## Walked rather than asked, because the GUI's own answer follows the real
## pointer and a wheel notch carries a position of its own.
func _other_control_at(node: Node, point: Vector2) -> bool:
    if node == self:
        return false
    for child in node.get_children():
        if child is Window or child == self:
            continue
        var control := child as Control
        # A container this surface sits inside is not over it, whatever its rect.
        if (
            control != null
            and not control.is_ancestor_of(self)
            and control.is_visible_in_tree()
            and control.mouse_filter != Control.MOUSE_FILTER_IGNORE
            and control.get_global_rect().has_point(point)
        ):
            return true
        if _other_control_at(child, point):
            return true
    return false


## Whether the active tool is one that paints, and so owns the pointer until the
## button is released.
func _active_tool_paints() -> bool:
    if tool_machine == null:
        return false
    var descriptor := tool_machine.get_descriptor(tool_machine.active_tool_name)
    return descriptor != null and descriptor.is_painting
