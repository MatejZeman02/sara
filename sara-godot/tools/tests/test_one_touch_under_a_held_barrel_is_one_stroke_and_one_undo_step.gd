## One touch under a held barrel button is one stroke and one undo step.
##
## Under XWayland the upper barrel is the middle button. Held to the eraser, the
## pen's first pressed motion opens the eraser's stroke and the tip's left press
## comes after it, and that press closed the stroke and opened a second,
## so one touch left two undo steps. The press is now taken into the stroke and
## the left release closes it. Windows' barrel stroke, a right mask with no
## left event, is held as it was.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

## The paint the eraser is given to take off.
const PAINT := Color(0.8, 0.2, 0.1, 1.0)
const ROW_Y := 64.0
const TOUCH := 0.6
const MIDDLE_AND_LEFT := MOUSE_BUTTON_MASK_MIDDLE | MOUSE_BUTTON_MASK_LEFT

var _stored: Dictionary = {}
var _surface: SaSurface = null
var _machine: ToolMachine = null


func before_each() -> void:
    _stored = SaSettings.pen_buttons.duplicate()
    _surface = Fixtures.make_surface(Vector2i(128, 128))
    _machine = Fixtures.make_bound_machine(_surface)
    _machine.set_active_tool(&"brush")


func after_each() -> void:
    SaCursorPolicy.forget_pointer_device()
    SaSettings.pen_buttons = _stored
    Fixtures.teardown(_surface, _machine)


## The held buttons alone, as the machine hands them the XWayland touch: the
## tool hears one press and one release, in that order.
func test_the_tip_s_press_under_an_open_held_stroke_joins_it() -> void:
    var held := SaHeldButtons.new(false)
    held.press(MOUSE_BUTTON_MIDDLE, &"eraser")
    var heard: Array[InputEvent] = []
    heard.append_array(held.route(_motion(24, TOUCH, MOUSE_BUTTON_MASK_MIDDLE), &"eraser"))
    heard.append_array(held.route(_button(MOUSE_BUTTON_LEFT, true, 24, MIDDLE_AND_LEFT), &"eraser"))
    for x: int in range(28, 100, 4):
        heard.append_array(held.route(_motion(x, TOUCH, MIDDLE_AND_LEFT), &"eraser"))
    heard.append_array(held.route(_button(MOUSE_BUTTON_LEFT, false, 100, MOUSE_BUTTON_MASK_MIDDLE), &"eraser"))
    var closing := held.release(_button(MOUSE_BUTTON_MIDDLE, false, 100, 0))
    assert_null(closing, "The barrel's release finds the stroke already closed")
    assert_eq(_lefts(heard), ["press", "release"], "One press and one release reach the tool")
    var last := heard[heard.size() - 1] as InputEventMouseButton
    assert_true(last != null and not last.pressed, "and the release comes last")


## Windows' barrel stroke sends no left event: the first pressed motion opens
## the stroke and the barrel's release closes it, as before.
func test_a_windows_barrel_stroke_is_as_it_was() -> void:
    var held := SaHeldButtons.new(false)
    held.press(MOUSE_BUTTON_RIGHT, &"eraser")
    var heard: Array[InputEvent] = []
    for x: int in range(24, 100, 4):
        heard.append_array(held.route(_motion(x, TOUCH, MOUSE_BUTTON_MASK_RIGHT), &"eraser"))
    heard.append(held.release(_button(MOUSE_BUTTON_RIGHT, false, 100, 0)))
    assert_eq(_lefts(heard), ["press", "release"], "One press and one release reach the tool")


## A left press with no held stroke open is passed on as it came.
func test_a_left_press_with_no_held_stroke_goes_on() -> void:
    var held := SaHeldButtons.new(false)
    held.press(MOUSE_BUTTON_MIDDLE, &"eraser")
    var press := _button(MOUSE_BUTTON_LEFT, true, 24, MIDDLE_AND_LEFT)
    var heard := held.route(press, &"eraser")
    assert_eq(heard.size(), 1, "The press is handed on")
    assert_true(heard.size() == 1 and heard[0] == press, "as itself")


## The whole machine under the XWayland touch, the upper held to the eraser:
## the touch erases and leaves one undo step.
func test_the_xwayland_touch_leaves_one_undo_step() -> void:
    _bind("middle", SaSettingsPenButtons.ERASER)
    _surface.get_document().fill_layer(PAINT)
    var steps := _steps()
    _machine.handle_input(_motion(24, 0.0, 0))
    _machine.handle_input(_button(MOUSE_BUTTON_MIDDLE, true, 24, MOUSE_BUTTON_MASK_MIDDLE))
    assert_eq(_machine.active_tool_name, &"eraser", "The upper held swaps the eraser in")
    _machine.handle_input(_motion(24, TOUCH, MOUSE_BUTTON_MASK_MIDDLE))
    _machine.handle_input(_button(MOUSE_BUTTON_LEFT, true, 24, MIDDLE_AND_LEFT))
    for x: int in range(28, 104, 4):
        _machine.handle_input(_motion(x, TOUCH, MIDDLE_AND_LEFT))
    assert_true(_machine.active_tool.get("is_drawing"), "The stroke is under way through the tip's press")
    _machine.handle_input(_button(MOUSE_BUTTON_LEFT, false, 104, MOUSE_BUTTON_MASK_MIDDLE))
    assert_eq(_steps(), steps + 1, "The tip's lift closes it as one undo step")
    _machine.handle_input(_button(MOUSE_BUTTON_MIDDLE, false, 104, 0))
    assert_eq(_steps(), steps + 1, "and the upper's release adds none")
    assert_eq(_machine.active_tool_name, &"brush", "and hands the brush back")


# --- Helpers --------------------------------------------------------------------


## The left presses and releases in *events*, as words.
func _lefts(events: Array[InputEvent]) -> Array[String]:
    var out: Array[String] = []
    for event: InputEvent in events:
        var button := event as InputEventMouseButton
        if button != null and button.button_index == MOUSE_BUTTON_LEFT:
            out.append("press" if button.pressed else "release")
    return out


func _bind(button_id: String, action: String) -> void:
    var table := SaSettings.pen_buttons.duplicate()
    table[button_id] = action
    SaSettings.pen_buttons = table


func _steps() -> int:
    var history := _surface.get_document().history
    assert_not_null(history, "The fixture's document keeps a history")
    return history.step_count() if history != null else -1


## A motion at *x* along the row, where the fake view puts the pointer too.
func _motion(x: int, pressure: float, mask: int) -> InputEventMouseMotion:
    var at := Vector2(x, ROW_Y)
    (_surface.view as Fixtures.FakeView).mouse_position = at
    var event := InputEventMouseMotion.new()
    event.position = at
    event.global_position = at
    event.pressure = pressure
    event.tilt = Vector2(0.2, 0.1)
    event.button_mask = mask
    # What the cursor overlay does with every motion in a window, so the pen's
    # middle press is told from a wheel press.
    SaCursorPolicy.note_pointer_device(event)
    return event


func _button(index: MouseButton, pressed: bool, x: int, mask: int) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = index
    event.pressed = pressed
    event.position = Vector2(x, ROW_Y)
    event.global_position = event.position
    event.button_mask = mask
    return event
