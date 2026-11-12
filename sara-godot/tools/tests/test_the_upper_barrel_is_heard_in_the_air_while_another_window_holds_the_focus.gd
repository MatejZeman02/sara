## The upper barrel is told from the tip while another window holds the focus.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## On an Intuos Pro under GNOME's Wayland, with the Middle row on the
## eraser, the upper held in the air and one touch across a stroke painted
## whenever Preferences had been clicked into. The engine hands every motion to
## the focused embedded window before any control hears it, so the pen's hover
## never reached `SaHeldButtons.UpperBarrel`, which holds a left press back
## only after a hover in the air, and the press that took the focus back went
## on as the tip. The canvas's window route runs before that forwarding and now
## tells the upper of each motion. These hand the hover to that route alone, as
## the engine does while Preferences holds the focus, then the press and the
## motions to both routes, as it does once the press has taken the focus back.
##
## The tool machine tells the upper under Wayland only, because it asks the
## display server, so away from Wayland the suite is skipped.
extends "res://tests/test_framework.gd"

## The eraser needs a RenderingDevice, and the window a display.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const MainCanvasScript = preload("res://render/main_canvas.gd")
const StateEyedropperScript = preload("res://modules/sara-base-modules/base/tools/state_eyedropper.gd")

## The paint the eraser is given to take off.
const PAINT := Color(0.8, 0.2, 0.1, 1.0)
## What an erased texel's alpha is under, at the touch's pressure. The eraser
## is a wash stroke now that wash is the brush's default, so it takes
## the coverage once at the commit: a half-pressure touch carves part of the
## paint rather than the whole of it, where build-up bit it down to 0.07 with
## a second pass over every dab. All the assertion needs is that the paint
## came off, as the sibling barrel suites read it.
const ERASED := 0.9
## The row the touch runs along in the root window's units, and a point well
## off it, both inside the canvas's control.
const ROW_Y := 300.0
const FROM_X := 150
const TO_X := 450
const OFF_THE_ROW := Vector2(300.0, 120.0)
## A pen's tilt in the air, which no mouse reports.
const TILT := Vector2(0.13, -0.08)
## The pressure the measured tip touched at.
const TOUCH := 0.6

var _stored: Dictionary = {}
var _host: Node = null
var _canvas: Node = null
var _last_at: Vector2 = Vector2.ZERO


func before_each() -> void:
    _stored = SaSettings.pen_buttons.duplicate()
    SaCursorPolicy.forget_pointer_device()
    _host = Node.new()
    _host.name = "UpperBarrelFocusHost"
    EventBus.add_child(_host)
    _canvas = MainCanvasScript.new()
    _host.add_child(_canvas)
    _canvas.bind_tools(Fixtures.make_tool_registry())
    _canvas.notification(Container.NOTIFICATION_SORT_CHILDREN)
    # The built-in blend modes, as `main.gd` wires them. Wash is the brush's
    # default, so an eraser gathers in the stroke buffer and lands
    # under Erase at the commit, and a compositor without the registry would
    # resolve that mode to Normal and leave the paint standing.
    _canvas.surface.easel.compositor.set_registry(Fixtures.make_registries(_canvas.surface).blend_modes)
    _machine().set_active_tool(&"brush")


func after_each() -> void:
    SaSettings.pen_buttons = _stored
    SaPointerDevice.suite_pointer = null
    if _host != null and is_instance_valid(_host):
        _host.free()
    _host = null
    _canvas = null


## The hover reaches the window route alone, and the press after it is the
## upper's: the hover that follows hands it on as the middle button, which
## holds the Middle row's eraser.
func test_a_hover_the_window_route_alone_heard_holds_the_bound_tool() -> void:
    if not _on_wayland():
        return
    _bind(SaSettingsPenButtons.ERASER)
    _upper_down_past_another_window(Vector2(FROM_X, ROW_Y))
    assert_eq(_machine().active_tool_name, &"eraser", "The upper's press after a hover only the window heard holds the eraser")
    assert_false(_machine().active_tool.get("is_drawing"), "and opens no stroke in the air")
    _both(_button(false, Vector2(FROM_X + 4, ROW_Y), 0))
    assert_eq(_machine().active_tool_name, &"brush", "and its release hands the brush back")


## Then one touch across the paint and a lift: the eraser takes the paint off
## along the row, and the lift closes it as one undo step.
func test_a_touch_under_it_erases_and_is_one_undo_step() -> void:
    if not _on_wayland():
        return
    _bind(SaSettingsPenButtons.ERASER)
    _paint_the_layer()
    var steps := _steps()
    _upper_down_past_another_window(Vector2(FROM_X, ROW_Y))
    assert_eq(_machine().active_tool_name, &"eraser", "The upper holds the eraser")
    for x: int in range(FROM_X + 4, TO_X + 1, 4):
        _both(_motion(Vector2(x, ROW_Y), TOUCH, MOUSE_BUTTON_MASK_LEFT))
    var middle := Vector2((FROM_X + TO_X) / 2.0, ROW_Y)
    _both(_button(false, Vector2(TO_X, ROW_Y), 0))
    # Wash gathers the eraser's coverage in the stroke buffer and lands it at
    # the commit, which the lift is, so the layer reads painted until then.
    assert_true(_alpha_at(middle) < ERASED, "The touch erases along the row, alpha %f" % _alpha_at(middle))
    assert_almost_eq(_alpha_at(OFF_THE_ROW), 1.0, 0.001, "and leaves the paint off it alone")
    assert_eq(_steps(), steps + 1, "The lift closes the eraser's stroke as one undo step")
    assert_eq(_machine().active_tool_name, &"brush", "and hands the brush back")


## The window route learns only that the pen is in the air: the tool hears a
## motion once, through the GUI route, and a hover only the window heard
## reaches no tool at all.
func test_the_tool_hears_each_motion_once() -> void:
    if not _on_wayland():
        return
    var seen := _machine().motion_samples_seen
    _window(_motion(Vector2(FROM_X, ROW_Y), 0.0, 0))
    assert_eq(_machine().motion_samples_seen, seen, "A hover only the window heard reaches no tool")
    _both(_motion(Vector2(FROM_X + 4, ROW_Y), 0.0, 0))
    assert_eq(_machine().motion_samples_seen, seen + 1, "and one both routes heard reaches it once")


# --- Helpers --------------------------------------------------------------------


## Whether the machine tells the upper here.
func _on_wayland() -> bool:
    if DisplayServer.get_name() != "Wayland":
        skip("the tool machine tells the upper barrel under Wayland only, and this is %s" % DisplayServer.get_name())
        return false
    return true


func _machine() -> ToolMachine:
    return _canvas.tool_machine


## The measured upper in the air while another window holds the focus: a
## hover the window route alone hears, then the left press that takes the
## focus back and a hover at no pressure, which both routes hear.
func _upper_down_past_another_window(at: Vector2) -> void:
    _window(_motion(at, 0.0, 0))
    _both(_button(true, at, MOUSE_BUTTON_MASK_LEFT))
    _both(_motion(at + Vector2(4, 0), 0.0, MOUSE_BUTTON_MASK_LEFT))


## *event*, in the root window's units, to the canvas's window route only, as
## the signal carries it before the viewport un-scales it.
func _window(event: InputEventMouse) -> void:
    var root := (Engine.get_main_loop() as SceneTree).root
    var to_desktop: Transform2D = SaPointerDevice.desktop_transform(root)
    SaPointerDevice.suite_pointer = to_desktop * event.position
    _canvas.call("_on_window_input", event.xformed_by(root.get_final_transform()))


## *event* to the window route and then the GUI route, local to the canvas's
## control, the two the engine hands it to once the canvas has the focus.
func _both(event: InputEventMouse) -> void:
    _window(event)
    var control: Control = _canvas.control_node
    _canvas.call("_on_canvas_gui_input", event.xformed_by(control.get_global_transform().affine_inverse()))


func _bind(action: String) -> void:
    var table := SaSettings.pen_buttons.duplicate()
    table["middle"] = action
    SaSettings.pen_buttons = table


func _surface() -> SaSurface:
    return _canvas.surface


## The active layer filled with opaque paint, and the eraser wide enough that
## the row's middle is well inside its stroke.
func _paint_the_layer() -> void:
    _surface().get_document().fill_layer(PAINT)
    assert_almost_eq(_alpha_at(OFF_THE_ROW), 1.0, 0.001, "The layer starts painted")
    var settings: Resource = _machine().get_tool(&"eraser").get("settings")
    settings.set("radius", 0.08)


func _steps() -> int:
    var history := _surface().get_document().history
    return history.step_count() if history != null else -1


## The alpha the active layer holds under *at*, a point of the root window.
func _alpha_at(at: Vector2) -> float:
    var reader := StateEyedropperScript.new()
    reader.surface = _surface()
    reader.sample_from = StateEyedropperScript.SampleFrom.LAYER
    var canvas: Control = _canvas.canvas
    return reader.pick_color_at_pos(canvas.get_global_transform().affine_inverse() * at).a


## A pen's motion at *at*, in the root window's units.
func _motion(at: Vector2, pressure: float, mask: int) -> InputEventMouseMotion:
    var event := InputEventMouseMotion.new()
    event.position = at
    event.global_position = at
    event.relative = at - _last_at
    _last_at = at
    event.pressure = pressure
    event.tilt = TILT
    event.button_mask = mask
    return event


func _button(pressed: bool, at: Vector2, mask: int) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    event.position = at
    event.global_position = at
    event.button_mask = mask
    return event
