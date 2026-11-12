## A pen on Android paints with its pressure and tilt, one finger paints
## nothing and two fingers move the view.
##
## The events are the shapes the emulator's trail showed Godot 4.7.2 handing
## Sara. A stylus is a left press, mouse motions and a left release from a
## device of its own, 32 on the emulator, carrying the pen's pressure and tilt.
## A finger is a screen touch and screen drags of device 0, index 0, and beside
## them the mouse Godot emulates from it, a left press and motions of device
## -1 at pressure 1. The eraser end is a motion with `pen_inverted` on, the
## shape Linux and Windows hand, since Godot's Android bridge carries no tool
## type and the tablet's eraser end reaches Sara as the tip.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StateEyedropperScript = preload("res://modules/sara-base-modules/base/tools/state_eyedropper.gd")

## The device the emulator's stylus came as.
const STYLUS := 32
## The row the strokes run along, its ends, and the tilt the pen holds.
const ROW_Y := 64.0
const FROM_X := 24.0
const TO_X := 232.0
const TILT := Vector2(0.31, -0.17)
## The paint the eraser end is given to take off.
const PAINT := Color(0.8, 0.2, 0.1, 1.0)
## Alpha above which a texel counts as painted.
const PAINTED := 0.05

var _surface: SaSurface = null
var _machine: ToolMachine = null
var _last_at: Vector2 = Vector2.ZERO
var _trail_was: bool = false


func before_each() -> void:
    _trail_was = SaInputTrail.trail
    SaCursorPolicy.forget_pointer_device()
    _surface = Fixtures.make_surface(Vector2i(256, 128))
    _surface.easel.compositor.set_registry(Fixtures.make_registries(_surface).blend_modes)
    _machine = Fixtures.make_bound_machine(_surface)
    _machine.set_active_tool(&"brush")
    var settings: SaStampBrushSettings = _machine.get_tool(&"brush").get("settings")
    settings.radius = 0.1
    settings.opacity_by_pressure = false
    SaBrushPenSettings.apply(settings, {"size": {"enabled": true, "sensors": ["pressure"]}})


func after_each() -> void:
    SaInputTrail.trail = _trail_was
    SaCursorPolicy.forget_pointer_device()
    Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null


func test_the_stylus_dabs_grow_with_its_pressure() -> void:
    _stylus_stroke(false)
    var widths: Array[int] = []
    for t: float in [0.65, 0.75, 0.85, 0.95]:
        widths.append(_width_at(_x_at(t)))
    assert_true(widths[0] > 0, "The stylus painted where its pressure was 0.69, %d texels wide" % widths[0])
    for i in range(1, widths.size()):
        assert_true(widths[i] > widths[i - 1], "and wider with more pressure, %s across 0.69, 0.78, 0.87 and 0.96" % [widths])


func test_the_stylus_tilt_reaches_the_brush() -> void:
    var brush := _machine.active_tool
    _stylus_down()
    _machine.handle_input(_motion(Vector2(FROM_X + 8.0, ROW_Y), 0.5, TILT, false, STYLUS, MOUSE_BUTTON_MASK_LEFT))
    assert_true(brush.get("is_tablet"), "The stylus is read as a pen")
    var tilt: Vector2 = brush.get("last_tilt")
    assert_true(tilt.is_equal_approx(TILT), "and the brush holds its tilt, %s" % tilt)
    assert_almost_eq(float(brush.get("last_pressure")), 0.5, 1e-4, "and its pressure")
    _machine.handle_input(_button(false, Vector2(FROM_X + 8.0, ROW_Y), STYLUS, 0))


func test_one_finger_paints_nothing() -> void:
    var steps := _steps()
    var start := Vector2(FROM_X, ROW_Y)
    _machine.handle_input(_button(true, start, InputEvent.DEVICE_ID_EMULATION, MOUSE_BUTTON_MASK_LEFT))
    _machine.handle_input(_touch(0, start, true))
    for i in range(1, 21):
        var at := Vector2(lerpf(FROM_X, TO_X, i / 20.0), ROW_Y)
        _machine.handle_input(_motion(at, 1.0, Vector2.ZERO, false, InputEvent.DEVICE_ID_EMULATION, MOUSE_BUTTON_MASK_LEFT))
        _machine.handle_input(_drag(0, at))
    _machine.handle_input(_touch(0, Vector2(TO_X, ROW_Y), false))
    _machine.handle_input(_button(false, Vector2(TO_X, ROW_Y), InputEvent.DEVICE_ID_EMULATION, 0))
    assert_eq(_width_at(128.0), 0, "A finger's swipe left no paint")
    assert_eq(_steps(), steps, "and no undo step")


func test_two_fingers_still_pan() -> void:
    var view := _surface.view as SaTestFixtures.FakeView
    var pan := view.pan
    _machine.handle_input(_touch(0, Vector2(100, 60), true))
    _machine.handle_input(_touch(1, Vector2(160, 60), true))
    _machine.handle_input(_drag(0, Vector2(120, 70)))
    _machine.handle_input(_drag(1, Vector2(180, 70)))
    var moved := view.pan - pan
    assert_true(moved.is_equal_approx(Vector2(20, 10)), "Two fingers moved the view by their midpoint's (20, 10), %s" % moved)
    _machine.handle_input(_touch(0, Vector2(120, 70), false))
    _machine.handle_input(_touch(1, Vector2(180, 70), false))
    assert_eq(_width_at(140.0), 0, "and painted nothing")


func test_the_eraser_end_erases() -> void:
    _surface.get_document().fill_layer(PAINT)
    assert_almost_eq(_alpha_at(Vector2(_x_at(0.9), ROW_Y)), 1.0, 0.001, "The layer starts painted")
    _stylus_stroke(true)
    var along := _alpha_at(Vector2(_x_at(0.9), ROW_Y))
    assert_true(along < 0.1, "The eraser end took the paint off along the stroke, %.3f left" % along)
    assert_almost_eq(_alpha_at(Vector2(_x_at(0.9), 8)), 1.0, 0.001, "and left it standing off the stroke")


func test_the_trail_names_each_event_only_when_on() -> void:
    var motion := _motion(Vector2(40, 50), 0.42, TILT, true, STYLUS, MOUSE_BUTTON_MASK_LEFT)
    SaInputTrail.trail = false
    assert_eq(SaInputTrail.note(motion), "", "Off, the trail prints nothing")
    SaInputTrail.trail = true
    var line := SaInputTrail.note(motion)
    assert_eq(
        line,
        "input MouseMotion device 32 index -1 at (40, 50) pressure 0.420 tilt (0.310, -0.170) inverted true buttons 1",
        "On, it names the class, the device, the index, the pressure and the tilt"
    )
    var finger := SaInputTrail.note(_drag(1, Vector2(5, 6)))
    assert_true(finger.begins_with("input ScreenDrag device 0 index 1"), "and a finger's drag")
    assert_eq(SaInputTrail.note(InputEventKey.new()), "", "and nothing for a key")


# --- Helpers --------------------------------------------------------------------


## A stylus stroke along the row with the pressure rising from 0.1 to 1.0.
func _stylus_stroke(inverted: bool) -> void:
    _stylus_down(inverted)
    for i in range(0, 41):
        var t := i / 40.0
        var at := Vector2(lerpf(FROM_X, TO_X, t), ROW_Y)
        _machine.handle_input(_motion(at, lerpf(0.1, 1.0, t), TILT, inverted, STYLUS, MOUSE_BUTTON_MASK_LEFT))
    _machine.handle_input(_button(false, Vector2(TO_X, ROW_Y), STYLUS, 0))


## The pen hovering in, then its tip down, as the emulator's stylus came. An
## eraser end is *inverted* from the hover on, as a pen reports it in the air.
func _stylus_down(inverted: bool = false) -> void:
    var start := Vector2(FROM_X, ROW_Y)
    _machine.handle_input(_motion(start - Vector2(4, 0), 0.0, TILT, inverted, STYLUS, 0))
    _machine.handle_input(_button(true, start, STYLUS, MOUSE_BUTTON_MASK_LEFT))


## Where along the row the pressure stood at fraction *t* of the stroke.
func _x_at(t: float) -> float:
    return lerpf(FROM_X, TO_X, t)


## How many texels of the column at *x* hold paint.
func _width_at(x: float) -> int:
    var reader := _reader()
    var count := 0
    for y in range(0, 128):
        if reader.pick_color_at_pos(Vector2(x, y + 0.5)).a > PAINTED:
            count += 1
    return count


func _alpha_at(at: Vector2) -> float:
    return _reader().pick_color_at_pos(at).a


func _reader() -> Object:
    var reader := StateEyedropperScript.new()
    reader.surface = _surface
    reader.sample_from = StateEyedropperScript.SampleFrom.LAYER
    return reader


func _steps() -> int:
    var history := _surface.get_document().history
    return history.step_count() if history != null else -1


func _motion(at: Vector2, pressure: float, tilt: Vector2, inverted: bool, device: int, mask: int) -> InputEventMouseMotion:
    (_surface.view as Fixtures.FakeView).mouse_position = at
    var event := InputEventMouseMotion.new()
    event.device = device
    event.position = at
    event.global_position = at
    event.relative = at - _last_at
    _last_at = at
    event.pressure = pressure
    event.tilt = tilt
    event.pen_inverted = inverted
    event.button_mask = mask
    return event


func _button(pressed: bool, at: Vector2, device: int, mask: int) -> InputEventMouseButton:
    (_surface.view as Fixtures.FakeView).mouse_position = at
    var event := InputEventMouseButton.new()
    event.device = device
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    event.position = at
    event.global_position = at
    event.button_mask = mask
    return event


func _touch(index: int, at: Vector2, pressed: bool) -> InputEventScreenTouch:
    var event := InputEventScreenTouch.new()
    event.index = index
    event.position = at
    event.pressed = pressed
    return event


func _drag(index: int, at: Vector2) -> InputEventScreenDrag:
    var event := InputEventScreenDrag.new()
    event.index = index
    event.position = at
    return event
