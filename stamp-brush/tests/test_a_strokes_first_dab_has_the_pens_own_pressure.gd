## A stroke's first dab under Windows Ink has the pen's own pressure.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A press carries no pressure, and Windows Ink hovers at 0, so the brush holds
## the press dab for the first motion's. Two cases could lay it at full
## pressure with a synthetic pen: a tap whose release came
## before any motion, which fell back to 1, and a pen that reports no tilt, whose
## hovers read as a mouse's after ten of them, so the press was not held at all
## and every stroke opened with a dark blot. What these hold is the pressure the
## brush lays the first dab at in each case, and that a mouse still paints at 1
## at once. A tiltless pen is told from a mouse only by its touch, so its first
## stroke still opens at 1, and every one after it at its own pressure.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

## More plain motions than the brush counts before it calls the pointer a mouse.
const PAST_THE_STREAK: int = 12
const LIGHT: float = 0.2

var _surface: SaSurface = null
var _machine: ToolMachine = null
var _brush: Object = null


func before_each() -> void:
    _surface = Fixtures.make_surface(Vector2i(256, 256))
    _machine = Fixtures.make_bound_machine(_surface)
    _machine.set_active_tool(&"brush")
    _brush = _machine.active_tool


func after_each() -> void:
    Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null
    _brush = null


func _hovers(tilt: Vector2) -> void:
    for i in PAST_THE_STREAK:
        var hover := InputEventMouseMotion.new()
        hover.tilt = tilt
        _surface.view.mouse_position = Vector2(40 + i, 40)
        _brush.handle_input(hover)


func _button(pressed: bool) -> void:
    var button := InputEventMouseButton.new()
    button.button_index = MOUSE_BUTTON_LEFT
    button.pressed = pressed
    _brush.handle_input(button)


func _motion(at: Vector2, pressure: float, tilt: Vector2) -> void:
    var motion := InputEventMouseMotion.new()
    motion.pressure = pressure
    motion.tilt = tilt
    _surface.view.mouse_position = at
    _brush.handle_input(motion)


## A press and a release with nothing between, and the pressure its dab took.
func _tap() -> float:
    _button(true)
    _button(false)
    assert_eq(_brush.stroke_info.dab_index, 1, "The tap lays its one dab")
    return _brush.stroke_info.pressure


## A short stroke from (60, 60), and the most pressure any of its dabs took.
func _stroke(pressure: float, tilt: Vector2) -> float:
    _surface.view.mouse_position = Vector2(60, 60)
    _button(true)
    for i in range(1, 6):
        _motion(Vector2(60 + 6 * i, 60), pressure, tilt)
    var most: float = _brush.stroke_info.max_pressure
    _button(false)
    return most


func test_a_tap_with_no_motion_is_not_laid_at_full_pressure() -> void:
    _hovers(Vector2(0.2, 0.1))
    assert_true(_brush.is_tablet, "A tilted pen's hovers keep the brush on the pen")
    var pressure := _tap()
    assert_true(pressure > 0.0 and pressure < 1.0, "A tap with no pressure reported for lays its dab at %f" % pressure)


func test_a_tap_takes_the_touch_of_the_pens_last_stroke() -> void:
    _hovers(Vector2(0.2, 0.1))
    _stroke(LIGHT, Vector2(0.2, 0.1))
    assert_almost_eq(_tap(), LIGHT, 1e-6, "A tap after a light stroke is as light as that stroke's touch")


func test_a_pen_with_no_tilt_opens_its_strokes_at_its_own_pressure_once_it_has_touched() -> void:
    _hovers(Vector2.ZERO)
    assert_false(_brush.is_tablet, "A pen with no tilt hovers as a mouse does")
    assert_almost_eq(_stroke(LIGHT, Vector2.ZERO), 1.0, 1e-6, "so its first stroke opens at a mouse's 1")
    _hovers(Vector2.ZERO)
    assert_almost_eq(_stroke(LIGHT, Vector2.ZERO), LIGHT, 1e-6, "and every stroke after it at the pen's pressure")
    _hovers(Vector2.ZERO)
    assert_almost_eq(_tap(), LIGHT, 1e-6, "and its next tap is as light as that touch")


func test_a_mouse_still_paints_at_full_pressure() -> void:
    _hovers(Vector2.ZERO)
    assert_almost_eq(_stroke(0.0, Vector2.ZERO), 1.0, 1e-6, "A mouse drag that reads no pressure paints at 1")
    assert_almost_eq(_tap(), 1.0, 1e-6, "and so does a click")
    _hovers(Vector2.ZERO)
    _stroke(1.0, Vector2.ZERO)
    assert_almost_eq(_brush._touch_pressure, 0.5, 1e-6, "Windows Ink's made-up 1 for a mouse drag is no pen's touch")
