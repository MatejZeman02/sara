## A pen switch writes its pressure curve in at most three control points, and
## a brush painted with it lays the dab the old nine-point curve laid at a
## quarter, a half and three quarters of a press.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The dab value is read the way a stroke reads it, an option's `size_like` over
## a pressure sensor carrying the option's curve, so the graph's spline and the
## sensor's table are both in what is measured.
extends "res://tests/test_framework.gd"

const SaShippedPresetsScript = preload("res://modules/sara-base-modules/stamp-brush/presets/sa_shipped_presets.gd")

## The pressures the note grades on, and how far the dab may move there.
const GRADED: Array[float] = [0.25, 0.5, 0.75]
const DAB_TOLERANCE: float = 0.02


func test_every_shipped_gamma_draws_its_curve_in_at_most_three_points() -> void:
    for gamma in _shipped_gammas():
        var curve := SaStampBrushSettings.pressure_curve(gamma)
        assert_true(curve.size() <= 3, "gamma %.2f is drawn with %d points" % [gamma, curve.size()])
        assert_eq(curve[0], Vector2.ZERO, "from nothing at no press")
        assert_eq(curve[curve.size() - 1], Vector2.ONE, "to everything at a full one")


func test_the_dab_at_each_graded_press_is_the_old_curves_within_two_hundredths() -> void:
    for gamma in _shipped_gammas():
        var short := _option(SaStampBrushSettings.pressure_curve(gamma))
        var nine := _option(_old_nine(gamma))
        for pressure: float in GRADED:
            var now := _dab(short, pressure)
            var before := _dab(nine, pressure)
            assert_true(
                absf(now - before) <= DAB_TOLERANCE,
                "gamma %.2f at %.2f: %.4f against the old %.4f" % [gamma, pressure, now, before]
            )


func test_the_short_curve_stays_within_a_tenth_of_the_power_everywhere() -> void:
    # The figure the record gives for the Size switch's curve, so a change to the
    # fit that loosens it shows here rather than on the graph.
    var size_gamma := SaStampBrushSettings.new().size_pressure_gamma.gamma()
    var exponent := size_gamma * SaStampBrushSettings.TOOL_PRESSURE_GAMMA
    var gap := SaPressureCurveFit.largest_gap(SaStampBrushSettings.pressure_curve(size_gamma), exponent)
    var bound := SaPressureCurveFit.LARGEST_GAP
    assert_true(gap <= bound, "the Size curve keeps within %.3f, %.4f" % [bound, gap])
    var opacity_gamma := SaStampBrushSettings.new().opacity_pressure_gamma.gamma()
    exponent = opacity_gamma * SaStampBrushSettings.TOOL_PRESSURE_GAMMA
    gap = SaPressureCurveFit.largest_gap(SaStampBrushSettings.pressure_curve(opacity_gamma), exponent)
    assert_true(gap <= 0.01, "and the Opacity curve within a hundredth, %.4f" % gap)


func test_the_diagonal_is_two_points() -> void:
    var curve := SaStampBrushSettings.pressure_curve(1.0 / SaStampBrushSettings.TOOL_PRESSURE_GAMMA)
    assert_eq(curve.size(), 2, "an exponent of one is the straight line, %s" % str(curve))


func test_switching_pressure_on_for_a_fresh_brush_writes_the_short_curve() -> void:
    var settings := SaStampBrushSettings.new()
    assert_true(settings.size_option.sensors.is_empty(), "A fresh brush's Size reads no sensor yet")
    settings.size_by_pressure = true
    var size_points := settings.size_option.common_curve.size()
    assert_true(size_points <= 3, "and Pressure on writes %d points" % size_points)
    var opacity_points := settings.opacity_option.common_curve.size()
    assert_true(opacity_points <= 3, "as Opacity's pen switch did, %d points" % opacity_points)


func test_a_saved_preset_keeps_the_nine_points_it_was_saved_with() -> void:
    var settings := SaStampBrushSettings.new()
    settings.opacity_by_pressure = true
    settings.opacity_option.common_curve = _old_nine(0.5)
    var path := SaDataRoot.path("a_saved_preset.tres")
    assert_eq(ResourceSaver.save(settings, path), OK, "The preset saves")
    var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as SaStampBrushSettings
    DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
    assert_not_null(loaded, "and loads")
    loaded.migrate()
    assert_eq(loaded.opacity_option.common_curve, _old_nine(0.5), "with the painter's nine points as they were")


## The gammas a preset ships with: both switches' defaults, and any a shipped
## recipe names.
func _shipped_gammas() -> Array[float]:
    var settings := SaStampBrushSettings.new()
    var gammas: Array[float] = [settings.size_pressure_gamma.gamma(), settings.opacity_pressure_gamma.gamma()]
    for entry: Dictionary in SaShippedPresetsScript.entries():
        for path: String in entry["settings"]:
            if path.contains("pressure_gamma") and path.ends_with("gamma_val") and not gammas.has(float(entry["settings"][path])):
                gammas.append(float(entry["settings"][path]))
    return gammas


## The old curve the switch wrote, the power at nine even pressures.
func _old_nine(gamma: float) -> PackedVector2Array:
    var points := PackedVector2Array()
    for i in range(9):
        var x := float(i) / 8.0
        points.append(Vector2(x, pow(x, gamma * SaStampBrushSettings.TOOL_PRESSURE_GAMMA)))
    return points


func _option(curve: PackedVector2Array) -> SaCurveOption:
    var option := SaCurveOption.new()
    option.enabled = true
    option.use_curve = true
    option.strength = 1.0
    option.use_same_curve = true
    option.common_curve = curve
    option.set_sensor(SaSensor.create(SaSensor.Id.PRESSURE, true))
    option.begin_stroke()
    return option


func _dab(option: SaCurveOption, pressure: float) -> float:
    var info := SaStrokeInfo.new()
    info.begin(Vector2.ZERO, 1)
    info.pressure = pressure
    return option.size_like(info)
