## The first dab of a stroke takes the pen's pressure.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Under Windows Ink a hover reports a pressure of 0, so the press had nothing
## to read and laid its dab at 1.0, and every later dab followed the pen at
## 0.2: each light stroke began with a dark blot. The press dab now waits for
## the first motion's pressure in the stamp brush and in the noise brush alike.
## Each suite below hovers at 0, presses, moves at 0.2 and reads every dab. A
## tap still leaves one dab and a mouse still paints at its press.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

## The pen's pressure on every motion of the stroke.
const LIGHT := 0.2
## Where the stroke starts and how far each motion carries it.
const FROM := Vector2(40.0, 40.0)
const STEP := Vector2(6.0, 0.0)
const MOTIONS := 6


## The noise brush with every point's pressure written down, since it keeps no
## point dump of its own.
class NoiseRecorder:
    extends "res://modules/sara-noise-brush-engine/state_noise_brush.gd"

    var pressures: Array[float] = []

    func _point(at: Vector2, pressure: float, tilt: Vector2, time_ms: float) -> void:
        pressures.append(pressure)
        super(at, pressure, tilt, time_ms)


func _hover(tool: Object, pressure: float, tilt: Vector2 = Vector2.ZERO) -> void:
    var hover := InputEventMouseMotion.new()
    hover.pressure = pressure
    hover.tilt = tilt
    tool.handle_input(hover)


func _button(tool: Object, pressed: bool) -> void:
    var button := InputEventMouseButton.new()
    button.button_index = MOUSE_BUTTON_LEFT
    button.pressed = pressed
    tool.handle_input(button)


## A light stroke: a hover at 0, the press at [constant FROM], and motions at
## [constant LIGHT] along x.
func _light_stroke(surface: SaSurface, tool: Object, tilt: Vector2 = Vector2.ZERO) -> void:
    surface.view.mouse_position = FROM
    _hover(tool, 0.0, tilt)
    _button(tool, true)
    for i in range(1, MOTIONS + 1):
        surface.view.mouse_position = FROM + STEP * i
        _hover(tool, LIGHT, tilt)
    _button(tool, false)


func _stamp_brush(machine: ToolMachine) -> Object:
    machine.set_active_tool(&"brush")
    var brush: Object = machine.active_tool
    brush.settings.opacity_by_pressure = true
    return brush


func test_the_stamp_brushs_first_dab_is_as_light_as_the_rest() -> void:
    var surface := Fixtures.make_surface(Vector2i(256, 256))
    var machine := Fixtures.make_bound_machine(surface)
    var brush := _stamp_brush(machine)
    assert_true(brush.is_tablet, "A fresh brush takes the pointer for a pen, the branch this is about")
    _light_stroke(surface, brush)
    var dabs: Array = brush.sampled_dabs
    assert_true(dabs.size() > 2, "The stroke laid several dabs, %d" % dabs.size())
    var later: float = dabs[dabs.size() - 1].opacity
    assert_true(later < 0.9, "A dab at %.1f is light, %f" % [LIGHT, later])
    for i in range(dabs.size()):
        assert_almost_eq(dabs[i].opacity, later, 1e-4, "Dab %d is as light as the last" % i)
    assert_eq(dabs[0].position, FROM, "and the first is still the press's")
    Fixtures.teardown(surface, machine)


func test_a_stamp_tap_still_leaves_one_dab() -> void:
    var surface := Fixtures.make_surface(Vector2i(128, 128))
    var machine := Fixtures.make_bound_machine(surface)
    var brush := _stamp_brush(machine)
    surface.view.mouse_position = FROM
    _hover(brush, 0.0)
    _button(brush, true)
    assert_eq(brush.sampled_dabs.size(), 0, "A pen's press waits for a pressure")
    _button(brush, false)
    assert_eq(brush.sampled_dabs.size(), 1, "and the release lays the one dab")
    assert_true(brush.sampled_dabs[0].opacity > 0.9, "at full pressure, since none came")
    Fixtures.teardown(surface, machine)


func test_the_stamp_brushs_mouse_paints_at_its_press() -> void:
    var surface := Fixtures.make_surface(Vector2i(128, 128))
    var machine := Fixtures.make_bound_machine(surface)
    var brush := _stamp_brush(machine)
    brush.is_tablet = false
    surface.view.mouse_position = FROM
    _button(brush, true)
    assert_eq(brush.sampled_dabs.size(), 1, "A mouse's press lays its dab at once")
    assert_true(brush.sampled_dabs[0].opacity > 0.9, "at full pressure")
    _button(brush, false)
    Fixtures.teardown(surface, machine)


func _noise_brush(surface: SaSurface) -> NoiseRecorder:
    var brush := NoiseRecorder.new()
    brush.surface = surface
    brush.stroke_seed = 7
    brush.settings.radius = 8.0 / 256.0
    return brush


func test_the_noise_brushs_first_dab_takes_the_pens_pressure() -> void:
    var surface := Fixtures.make_surface()
    var brush := _noise_brush(surface)
    # Ink's hover reports a lean, which is how the brush learns it is a pen.
    _light_stroke(surface, brush, Vector2(0.1, 0.0))
    assert_true(brush.pressures.size() > 2, "The stroke laid several dabs, %d" % brush.pressures.size())
    for i in range(brush.pressures.size()):
        assert_almost_eq(brush.pressures[i], LIGHT, 1e-4, "Dab %d is at the pen's pressure" % i)
    brush = null
    Fixtures.teardown(surface)


func test_a_noise_tap_still_leaves_one_dab() -> void:
    var surface := Fixtures.make_surface()
    var brush := _noise_brush(surface)
    surface.view.mouse_position = FROM
    _hover(brush, 0.0, Vector2(0.1, 0.0))
    _button(brush, true)
    assert_eq(brush.pressures.size(), 0, "A pen's press waits for a pressure")
    _button(brush, false)
    assert_eq(brush.pressures, [1.0] as Array[float], "and the release lays the one dab at full pressure")
    brush = null
    Fixtures.teardown(surface)


## A pointer the brush has not seen yet may be a pen pressed from no pressure,
## so its press waits, and a mouse is the one a run of
## plain motions has shown.
func test_the_noise_brushs_mouse_paints_at_its_press() -> void:
    var surface := Fixtures.make_surface()
    var brush := _noise_brush(surface)
    surface.view.mouse_position = FROM
    _button(brush, true)
    for i in range(1, brush.MOUSE_MOTIONS + 2):
        surface.view.mouse_position = FROM + STEP * i
        _hover(brush, 0.0)
    _button(brush, false)
    assert_false(brush.is_tablet, "A run of plain motions showed a mouse")
    brush.pressures.clear()
    surface.view.mouse_position = FROM
    _button(brush, true)
    assert_eq(brush.pressures, [1.0] as Array[float], "A mouse's press lays its dab at once, at full pressure")
    _button(brush, false)
    brush = null
    Fixtures.teardown(surface)
