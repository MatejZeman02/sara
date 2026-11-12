## A Watery Lift stroke ends on its faded tail.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## One Watery Lift stroke in four ended with a
## full-colour dab after its faded tail. A release that reads a pressure of 0
## already ends on the tail, since the sample walks in at that pressure and the
## lift-up reads it against the stroke's peak. The full-strength dab is the pen
## bouncing as it lifts: it touches again where it let go and leaves before any
## motion, so under Ink the press hears no pressure, and the tap rule laid it
## at 1.0 as a stroke of its own. A press that soon and that near now takes the
## tail's pressure against the tail's peak, and a tap of its own keeps the tap rule's.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const NoisePresetsScript = preload("res://modules/sara-noise-brush-engine/presets/noise_presets.gd")
const NoiseSettingsScript = preload("res://modules/sara-noise-brush-engine/noise_brush_settings.gd")

const FROM := Vector2(40.0, 40.0)
const STEP := Vector2(6.0, 0.0)
const PRESSURES: Array[float] = [0.8, 0.7, 0.6, 0.5, 0.4, 0.3, 0.2]


## The noise brush with every point's pressure and opacity written down, as the
## sensors read them.
class NoiseRecorder:
    extends "res://modules/sara-noise-brush-engine/state_noise_brush.gd"

    var pressures: Array[float] = []
    var opacities: Array[float] = []

    func _point(at: Vector2, pressure: float, tilt: Vector2, time_ms: float) -> void:
        super(at, pressure, tilt, time_ms)
        pressures.append(stroke_info.pressure)
        opacities.append(settings.opacity_option.size_like(stroke_info))


func _watery_lift() -> Resource:
    for entry: Dictionary in NoisePresetsScript.entries():
        if entry["name"] == "Watery Lift":
            return NoisePresetsScript.build(NoiseSettingsScript, entry)
    return null


func _motion(tool: Object, pressure: float) -> void:
    var motion := InputEventMouseMotion.new()
    motion.pressure = pressure
    motion.tilt = Vector2(0.1, 0.0)
    tool.handle_input(motion)


func _button(tool: Object, pressed: bool) -> void:
    var button := InputEventMouseButton.new()
    button.button_index = MOUSE_BUTTON_LEFT
    button.pressed = pressed
    tool.handle_input(button)


func _brush(surface: SaSurface) -> NoiseRecorder:
    var brush := NoiseRecorder.new()
    brush.surface = surface
    brush.stroke_seed = 7
    brush.settings = _watery_lift()
    return brush


## A stroke that lightens along x and ends with a motion at pressure 0, the way
## Windows Ink reports the pen leaving the paper, and then the release.
func _lifting_stroke(surface: SaSurface, brush: Object) -> void:
    surface.view.mouse_position = FROM
    _motion(brush, 0.0)
    _button(brush, true)
    for i in PRESSURES.size():
        surface.view.mouse_position = FROM + STEP * (i + 1)
        _motion(brush, PRESSURES[i])
    _motion(brush, 0.0)
    _button(brush, false)


func _fades(brush: NoiseRecorder, label: String) -> void:
    var count := brush.opacities.size()
    assert_true(count > 2, "%s laid several dabs, %d" % [label, count])
    var last: float = brush.opacities[count - 1]
    var before: float = brush.opacities[count - 2]
    assert_true(last <= before + 1e-6, "%s ends no stronger than the dab before, %f after %f" % [label, last, before])
    assert_true(last < 0.1, "and on the faded tail, %f" % last)


func test_the_release_at_pressure_nought_ends_on_the_faded_tail() -> void:
    var surface := Fixtures.make_surface()
    var brush := _brush(surface)
    assert_true(brush.settings != null, "The shelf builds Watery Lift")
    _lifting_stroke(surface, brush)
    _fades(brush, "The stroke")
    assert_almost_eq(brush.pressures[brush.pressures.size() - 1], 0.0, 0.01, "Its last dab reads the release's pressure")
    brush = null
    Fixtures.teardown(surface)


func test_the_pen_bouncing_as_it_lifts_lays_the_tails_strength() -> void:
    var surface := Fixtures.make_surface()
    var brush := _brush(surface)
    _lifting_stroke(surface, brush)
    var tail: float = brush.opacities[brush.opacities.size() - 1]
    # The pen touches again where it let go and lifts before any motion, so
    # the press hears no pressure, which is what a tap at full strength was.
    _motion(brush, 0.0)
    _button(brush, true)
    _button(brush, false)
    _fades(brush, "The stroke and its bounce")
    var bounce: float = brush.opacities[brush.opacities.size() - 1]
    assert_true(bounce <= tail + 1e-6, "The bounce's dab is no stronger than the tail's, %f after %f" % [bounce, tail])
    brush = null
    Fixtures.teardown(surface)


func test_a_tap_of_its_own_still_lays_full_strength() -> void:
    var surface := Fixtures.make_surface()
    var brush := _brush(surface)
    brush.begin_stroke(FROM, 0.8, Vector2.ZERO, 1000.0)
    brush.add_sample(FROM + STEP, 0.4, Vector2.ZERO, 1010.0)
    brush.add_sample(FROM + STEP * 2.0, 0.0, Vector2.ZERO, 1020.0)
    brush.end_stroke()
    var later := 1020.0 + brush.BOUNCE_MS + 50.0
    brush.begin_stroke(FROM + STEP * 2.0, 0.0, Vector2.ZERO, later, true)
    brush.end_stroke()
    var tap: float = brush.opacities[brush.opacities.size() - 1]
    assert_almost_eq(tap, 1.0, 1e-4, "A press long after the lift is a tap, at full strength")
    brush.begin_stroke(FROM + Vector2(0.0, 150.0), 0.0, Vector2.ZERO, later + 20.0, true)
    brush.end_stroke()
    assert_almost_eq(brush.pressures[brush.pressures.size() - 1], 1.0, 1e-4, "and so is one far from where the pen let go")
    brush = null
    Fixtures.teardown(surface)
