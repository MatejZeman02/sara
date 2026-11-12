## Two fingers that tap undo once, and two that move only move the view. The door suite of the same name reads
## it on a running Sara,
## this one the edges a door's touch step cannot time: a hold, a wander inside
## the slop, a finger that moves past it and a third finger.
##
## The touches go through the tool machine as the canvas hands them, local to
## its control, and the steps are two pen strokes painted the same way.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

## The device the emulator's stylus came as.
const STYLUS := 32
## Longer than a two-finger tap may last, in seconds.
const PAST_THE_TAP := 0.7

var _surface: SaSurface = null
var _machine: ToolMachine = null


func before_each() -> void:
    _surface = Fixtures.make_surface(Vector2i(256, 128))
    _surface.easel.compositor.set_registry(Fixtures.make_registries(_surface).blend_modes)
    _machine = Fixtures.make_bound_machine(_surface)
    _machine.set_active_tool(&"brush")
    var settings: SaStampBrushSettings = _machine.get_tool(&"brush").get("settings")
    settings.radius = 0.1
    _stroke(40)
    _stroke(90)


func after_each() -> void:
    Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null


func test_two_fingers_that_land_and_lift_still_undo_once() -> void:
    var at := _position()
    _land(0, Vector2(80, 60), true)
    _land(1, Vector2(160, 60), true)
    _land(0, Vector2(80, 60), false)
    _land(1, Vector2(160, 60), false)
    assert_eq(_position(), at - 1, "The tap took back one step, %d to %d" % [at, _position()])


func test_a_wander_inside_the_slop_still_undoes_and_puts_the_view_back() -> void:
    var at := _position()
    _land(0, Vector2(80, 60), true)
    _land(1, Vector2(160, 60), true)
    _drag(0, Vector2(84, 62))
    _drag(1, Vector2(155, 57))
    _land(1, Vector2(155, 57), false)
    _land(0, Vector2(84, 62), false)
    assert_eq(_position(), at - 1, "A tap's few pixels of wander still undo")
    assert_eq(_view().pan, Vector2.ZERO, "and the view is back where it was")
    assert_eq(_view().zoom, 1.0, "at the zoom it had")


func test_two_fingers_that_move_past_the_slop_undo_nothing() -> void:
    var at := _position()
    _land(0, Vector2(80, 60), true)
    _land(1, Vector2(160, 60), true)
    _drag(0, Vector2(60, 60))
    _drag(1, Vector2(180, 60))
    _land(0, Vector2(60, 60), false)
    _land(1, Vector2(180, 60), false)
    assert_eq(_position(), at, "A pinch undoes nothing")
    assert_almost_eq(_view().zoom, 1.5, 0.001, "and zooms by the spread")


func test_the_finger_left_behind_moving_spoils_the_tap() -> void:
    var at := _position()
    _land(0, Vector2(80, 60), true)
    _land(1, Vector2(160, 60), true)
    _land(1, Vector2(160, 60), false)
    _drag(0, Vector2(120, 60))
    _land(0, Vector2(120, 60), false)
    assert_eq(_position(), at, "One finger moving on after the other lifted is no tap")


func test_a_third_finger_spoils_the_tap() -> void:
    var at := _position()
    _land(0, Vector2(80, 60), true)
    _land(1, Vector2(160, 60), true)
    _land(2, Vector2(120, 90), true)
    for index in 3:
        _land(index, Vector2(80 + 40 * index, 60), false)
    assert_eq(_position(), at, "Three fingers undo nothing")


func test_a_hold_longer_than_a_tap_undoes_nothing() -> void:
    var at := _position()
    _land(0, Vector2(80, 60), true)
    _land(1, Vector2(160, 60), true)
    await Engine.get_main_loop().create_timer(PAST_THE_TAP).timeout
    _land(0, Vector2(80, 60), false)
    _land(1, Vector2(160, 60), false)
    assert_eq(_position(), at, "A hold is no tap")


func test_two_taps_undo_twice() -> void:
    var at := _position()
    for tap in 2:
        _land(0, Vector2(80, 60), true)
        _land(1, Vector2(160, 60), true)
        _land(0, Vector2(80, 60), false)
        _land(1, Vector2(160, 60), false)
    assert_eq(_position(), at - 2, "Each tap is one undo")


# --- Helpers --------------------------------------------------------------------


func _view() -> SaTestFixtures.FakeView:
    return _surface.view as SaTestFixtures.FakeView


func _position() -> int:
    return _surface.get_document().history.position()


func _land(index: int, at: Vector2, pressed: bool) -> void:
    var event := InputEventScreenTouch.new()
    event.index = index
    event.position = at
    event.pressed = pressed
    _machine.handle_input(event)


func _drag(index: int, at: Vector2) -> void:
    var event := InputEventScreenDrag.new()
    event.index = index
    event.position = at
    _machine.handle_input(event)


## A pen stroke along the row at *y*, one undo step.
func _stroke(y: float) -> void:
    _pen_motion(Vector2(20, y), 0)
    _pen(true, Vector2(24, y))
    for i in range(1, 11):
        _pen_motion(Vector2(lerpf(24, 232, i / 10.0), y))
    _pen(false, Vector2(232, y))


func _pen(pressed: bool, at: Vector2) -> void:
    _view().mouse_position = at
    var event := InputEventMouseButton.new()
    event.device = STYLUS
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
    event.position = at
    event.global_position = at
    _machine.handle_input(event)


func _pen_motion(at: Vector2, mask: int = MOUSE_BUTTON_MASK_LEFT) -> void:
    _view().mouse_position = at
    var event := InputEventMouseMotion.new()
    event.device = STYLUS
    event.position = at
    event.global_position = at
    event.pressure = 0.8
    event.button_mask = mask
    _machine.handle_input(event)
