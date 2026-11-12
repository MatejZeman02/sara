## Three fingers that tap redo once, as Procreate's do, and two that tap still
## undo. The touches go through the tool machine as the
## canvas hands them, the way the two-finger suite plays them, and the steps are two
## pen strokes painted the same way.
##
## SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

## The device the emulator's stylus came as.
const STYLUS := 32
## Longer than a tap may last, in seconds.
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


func test_two_fingers_undo_and_three_redo() -> void:
    var at := _position()
    _tap(2)
    assert_eq(_position(), at - 1, "Two fingers took one step back")
    _tap(3)
    assert_eq(_position(), at, "and three put it again, %d" % _position())
    assert_eq(_view().pan, Vector2.ZERO, "with the view where it was")
    assert_eq(_view().zoom, 1.0, "at the zoom it had")


func test_each_three_finger_tap_redoes_one_step() -> void:
    var at := _position()
    _tap(2)
    _tap(2)
    _tap(3)
    assert_eq(_position(), at - 1, "One redo a tap")
    _tap(3)
    assert_eq(_position(), at, "and the second the step after it")
    _tap(3)
    assert_eq(_position(), at, "and a third with nothing to redo does nothing")


func test_three_fingers_that_move_redo_nothing() -> void:
    var at := _position()
    _tap(2)
    _land(0, Vector2(80, 60), true)
    _land(1, Vector2(160, 60), true)
    _land(2, Vector2(120, 90), true)
    _drag(2, Vector2(120, 40))
    for index in 3:
        _land(index, Vector2(80 + 40 * index, 60), false)
    assert_eq(_position(), at - 1, "A third finger that swipes is no tap")


func test_a_fourth_finger_spoils_the_tap() -> void:
    var at := _position()
    _tap(2)
    _tap(4)
    assert_eq(_position(), at - 1, "Four fingers redo nothing")


func test_a_three_finger_hold_redoes_nothing() -> void:
    var at := _position()
    _tap(2)
    _land(0, Vector2(80, 60), true)
    _land(1, Vector2(160, 60), true)
    _land(2, Vector2(120, 90), true)
    await Engine.get_main_loop().create_timer(PAST_THE_TAP).timeout
    for index in 3:
        _land(index, Vector2(80 + 40 * index, 60), false)
    assert_eq(_position(), at - 1, "A hold is no tap")


## *count* fingers landing in a row and lifting in the same order.
func _tap(count: int) -> void:
    for index in count:
        _land(index, Vector2(80 + 40 * index, 60 + 10 * (index % 2)), true)
    for index in count:
        _land(index, Vector2(80 + 40 * index, 60 + 10 * (index % 2)), false)


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
