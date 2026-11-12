## The evaluator: the read order, the options that are skipped, and the claim
## that a migrated preset paints what it painted.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The load-bearing test here is `test_a_migrated_preset_answers_the_old_alpha`,
## which is the whole switch as one number. The old path was
## `opacity_pressure_gamma.apply(SaTablet.normalize(raw, max, 2.4))`, two
## exponents applied in two places, and the new one is a curve over calibrated
## pressure. They agreed inside a unit of 8-bit quantisation while the curve was
## nine points. With the curve drawn in three, since nine were too many, they
## agree inside three units, 0.0084 at worst, which is under the 0.02 the note
## grades the dab to. A preset already saved keeps the curve it was saved with,
## so only a preset migrated from the old toggles moves.
##
## **The comparison names the pen maximum it runs at**. Reading
## `SaSettings.tablet_max_pressure`, a live preference, would measure whatever
## the runner's scratch profile happened to hold, and a fresh profile's value is
## 0.73. At 0.73 more than a quarter of the samples clamp to full pressure and
## the two paths agree trivially. At the default of 1.0, which is what an
## uncalibrated pen gets, the nine points were 0.0043 out and the three are
## 0.0084, and that is what
## `test_the_fit_at_an_uncalibrated_pen_is_wider_than_two_levels` pins rather
## than hides.
extends "res://tests/test_framework.gd"

## One unit of 8-bit quantisation, which the switch's note graded it to, and
## three of them are what the three-point curve is held to.
const ONE_LEVEL: float = 1.0 / 255.0

## The pen maximum the migration's nine points were fitted against.
const LEGACY_MAX: float = 0.73

## The maximum a pen nobody has swept reports through, which is the whole range.
const UNCALIBRATED_MAX: float = 1.0


func _settings() -> SaStampBrushSettings:
    return SaStampBrushSettings.new()


func _sample(pressure: float, at: Vector2 = Vector2.ZERO) -> SaStrokeInfo:
    var info := SaStrokeInfo.new()
    info.begin(Vector2.ZERO, 4242)
    info.hovering = false
    info.position = at
    info.pressure = pressure
    return info


# --- The switch, as one number ------------------------------------------------


## The worst gap between the two paths over 21 samples, at a stated pen maximum.
##
## Taken as an argument rather than off `SaSettings`, so this measures the
## migration and not the profile the runner happens to have written.
func _worst_gap(max_pressure: float) -> float:
    var settings := _settings()
    var dynamics := SaDynamics.new(settings)
    var worst := 0.0

    for i in range(21):
        var raw := float(i) / 20.0
        # What the old path does, in one line: normalize with the tool's own 2.4,
        # then the preset's gamma.
        var old_alpha: float = settings.opacity_pressure_gamma.apply(SaTablet.normalize(raw, max_pressure, 2.4))
        # What it does now: the sensor takes calibrated pressure with no gamma
        # and the migrated curve carries the product of the two.
        var info := _sample(SaTablet.normalize(raw, max_pressure, 1.0))
        worst = maxf(worst, absf(dynamics.evaluate(info, 40.0).opacity - old_alpha))

    return worst


func test_a_migrated_preset_answers_the_old_alpha() -> void:
    var worst := _worst_gap(LEGACY_MAX)

    assert_true(worst <= 3.0 * ONE_LEVEL, "The migrated opacity is within three 8-bit levels of the old path, worst %f" % worst)


## The same measurement at the maximum a pen nobody has calibrated reports
## through, where the three points are over two levels out.
##
## Pinned as a number rather than left as a passing test at a maximum that
## flatters it: a quarter of the samples clamp to full pressure at 0.73 and none
## does at 1.0, so the fit is being read over its whole domain here for the first
## time. Bounded on both sides, so a unit that changes the curve's points fails
## this and has to come and say so.
func test_the_fit_at_an_uncalibrated_pen_is_wider_than_two_levels() -> void:
    var worst := _worst_gap(UNCALIBRATED_MAX)

    assert_true(worst > 2.0 * ONE_LEVEL, "It is over two levels, which is the recorded fit, worst %f" % worst)
    assert_true(worst < 3.0 * ONE_LEVEL, "and under three, so a migrated preset is off by two levels and not by a band")


func test_a_mouse_stroke_is_unchanged_because_pressure_is_one_throughout() -> void:
    var settings := _settings()
    var dynamics := SaDynamics.new(settings)
    var info := _sample(SaTablet.normalize(1.0, SaSettings.tablet_max_pressure, 1.0))

    var dab := dynamics.evaluate(info, 40.0)

    # Every one of these is what the old path sent for a mouse: full alpha, the
    # base diameter, no rotation, no scatter and a spacing multiplier of one.
    assert_almost_eq(dab.opacity, 1.0, ONE_LEVEL, "Full alpha")
    assert_almost_eq(dab.size, 40.0, 1e-6, "the base diameter")
    assert_almost_eq(dab.rotation, 0.0, 1e-6, "no rotation")
    assert_almost_eq(dab.ratio, 1.0, 1e-6, "a round tip")
    assert_eq(dab.scatter, Vector2.ZERO, "no scatter")
    assert_almost_eq(dab.spacing, 1.0, 1e-6, "and the tip's own spacing")


func test_size_by_pressure_changes_the_diameter_along_the_stroke() -> void:
    var settings := _settings()
    settings.size_by_pressure = true
    var dynamics := SaDynamics.new(settings)
    dynamics.begin_stroke()

    var light := dynamics.evaluate(_sample(0.25), 40.0)
    var heavy := dynamics.evaluate(_sample(1.0), 40.0)

    assert_true(light.size < heavy.size, "A lighter touch is a smaller dab: %f against %f" % [light.size, heavy.size])
    assert_almost_eq(heavy.size, 40.0, 1e-4, "and full pressure is the base diameter")
    # pow(0.25, 4.8) is about 0.00046, so a quarter of the pen's travel is
    # essentially nothing at the default gamma. That steepness is the old
    # behaviour rather than a new one.
    assert_true(light.size < 1.0, "A quarter of the travel is under a pixel at the default gamma, %f" % light.size)


func test_size_by_pressure_off_leaves_the_diameter_alone() -> void:
    var dynamics := SaDynamics.new(_settings())

    assert_almost_eq(dynamics.evaluate(_sample(0.1), 40.0).size, 40.0, 1e-6, "A light touch")
    assert_almost_eq(dynamics.evaluate(_sample(1.0), 40.0).size, 40.0, 1e-6, "and a heavy one, both the base diameter")


# --- The order ----------------------------------------------------------------


func test_scatter_is_measured_against_the_dab_it_scatters() -> void:
    var settings := _settings()
    settings.scatter_option.enabled = true
    settings.scatter_option.use_curve = false
    settings.scatter_option.strength = 1.0
    var dynamics := SaDynamics.new(settings)

    var small := dynamics.evaluate(_sample(1.0), 10.0)
    var large := dynamics.evaluate(_sample(1.0), 200.0)

    # Not a comparison of two draws, which would be a comparison of two random
    # numbers. The bound is what the amplitude promises, and the small dab's
    # bound has to be inside the large one's.
    assert_true(absf(small.scatter.x) <= 10.0, "A ten pixel dab scatters at most ten pixels, %f" % small.scatter.x)
    assert_true(absf(large.scatter.x) <= 200.0, "and a two hundred pixel dab, at most two hundred")


func test_a_switched_off_option_is_skipped_rather_than_read() -> void:
    var settings := _settings()
    var dynamics := SaDynamics.new(settings)

    # The canvas rotated a quarter turn. The rotation option is off, so the dab
    # must not turn. Reading `rotation_like` on it anyway would fold the base
    # angle in and rotate every brush on a rotated canvas, which the old path
    # never did and which is the reason the skip is a skip.
    var dab := dynamics.evaluate(_sample(1.0), 40.0, 0.25, false)

    assert_almost_eq(dab.rotation, 0.0, 1e-6, "An option nobody switched on contributes nothing")


## **The option needs a sensor for any of this to happen**, which is what this
## suite did not say before. It set `use_curve = false` and asserted only that
## the two readings differ, and they did: 3.14 against 1.57, because an option
## with nothing to modulate with answers a half turn. Both numbers were wrong
## and the assertion could not see it.
func test_the_rotation_option_reads_the_canvas_angle_once_it_is_on() -> void:
    var settings := _settings()
    settings.rotation_option.enabled = true
    settings.rotation_option.set_sensor(SaSensor.create(SaSensor.Id.PRESSURE, true))
    var dynamics := SaDynamics.new(settings)
    dynamics.begin_stroke()

    var upright := dynamics.evaluate(_sample(1.0), 40.0, 0.0, false).rotation
    var turned := dynamics.evaluate(_sample(1.0), 40.0, 0.25, false).rotation

    assert_true(absf(upright - turned) > 1e-3, "The base angle reaches the dab: %f against %f" % [upright, turned])
    assert_true(turned >= 0.0 and turned <= TAU, "and the answer is radians in one turn, %f" % turned)


## The defect this guards: switched on, no sensor ticked, and every dab
## stamped upside down.
##
## `rotation_like` answers 0 for an option with nothing to modulate with, and the
## expression that reads it is `(1 + value) * PI`, so 0 is a half turn and the
## value meaning *no turn* is 1. An unmodulated rotation is no rotation, which is
## the same neutral every other option has and the same one a switched-off
## rotation already had.
func test_a_rotation_with_no_sensor_is_no_rotation_rather_than_a_half_turn() -> void:
    var settings := _settings()
    settings.rotation_option.enabled = true
    var dynamics := SaDynamics.new(settings)
    dynamics.begin_stroke()

    assert_true(settings.rotation_option.active_sensors().is_empty(), "Nothing was ticked and nothing was invented")
    assert_almost_eq(dynamics.evaluate(_sample(1.0), 40.0).rotation, 0.0, 1e-6, "so the dab is not turned")
    assert_almost_eq(
        dynamics.evaluate(_sample(1.0), 40.0, 0.25, false).rotation,
        0.0,
        1e-6,
        "and a rotated canvas does not turn it either, the way a switched-off option already did not"
    )


## The curve switched off is the same state by another door: `_components` never
## reads a sensor, so the option is a constant, and a constant rotation is none.
func test_a_rotation_with_the_curve_off_is_no_rotation_either() -> void:
    var settings := _settings()
    settings.rotation_option.enabled = true
    # After the sensor, not before it: `set_sensor` switches the curve back on
    # for an active sensor, which is right for a painter ticking one and is what
    # made the first draft of this case read 2 PI rather than 0.
    settings.rotation_option.set_sensor(SaSensor.create(SaSensor.Id.PRESSURE, true))
    settings.rotation_option.use_curve = false
    var dynamics := SaDynamics.new(settings)
    dynamics.begin_stroke()

    assert_almost_eq(dynamics.evaluate(_sample(1.0), 40.0).rotation, 0.0, 1e-6, "A sensor nobody reads turns nothing")


# --- Scatter ------------------------------------------------------------------


func _scattering(axis_x: bool, axis_y: bool) -> SaDynamics:
    var settings := _settings()
    settings.scatter_option.enabled = true
    settings.scatter_option.use_curve = false
    settings.scatter_option.strength = 1.0
    settings.scatter_axis_x = axis_x
    settings.scatter_axis_y = axis_y
    return SaDynamics.new(settings)


func test_scatter_with_both_axes_off_moves_nothing() -> void:
    var dynamics := _scattering(false, false)

    for i in range(20):
        assert_eq(dynamics.evaluate(_sample(1.0), 40.0).scatter, Vector2.ZERO, "Neither axis, no offset")


func test_scatter_with_both_axes_on_moves_the_dab_off_the_path() -> void:
    var dynamics := _scattering(true, true)
    var moved := 0

    for i in range(40):
        if dynamics.evaluate(_sample(1.0), 40.0).scatter.length() > 0.0:
            moved += 1

    # Every draw, not most of them. A uniform draw is exactly zero with
    # probability nothing, so a run that did not move is a run that did not draw.
    assert_eq(moved, 40, "Every dab is offset")


func test_one_axis_scatters_along_the_stroke_and_the_other_across_it() -> void:
    var info := _sample(1.0)
    info.last_position = Vector2.ZERO
    info.position = Vector2(10.0, 0.0)

    var along := _scattering(true, false).evaluate(info, 40.0).scatter
    var across := _scattering(false, true).evaluate(info, 40.0).scatter

    # The stroke runs along x, so its left normal is y. One draw each, so the
    # offset is on one axis rather than in a disc.
    assert_almost_eq(along.y, 0.0, 1e-4, "Along the drawing direction, nothing across it")
    assert_almost_eq(across.x, 0.0, 1e-4, "and across it, nothing along")
    assert_true(absf(along.x) > 0.0, "Both of them move")
    assert_true(absf(across.y) > 0.0, "the dab somewhere")


# --- What preparing a stroke must not do --------------------------------------


func test_preparing_a_stroke_does_not_give_an_untouched_option_a_sensor() -> void:
    var settings := _settings()
    var dynamics := SaDynamics.new(settings)

    dynamics.begin_stroke()

    # `SaCurveOption.begin_stroke` guarantees one active sensor, so preparing
    # every option would put pressure into the seven nobody switched on, and the
    # next save would write seven sensor entries into the file. A save that
    # writes only the sensors a painter chose is only true while this stays
    # true.
    for key: String in ["ratio", "softness", "rotation", "scatter", "spacing", "rate"]:
        assert_true(settings.options()[key].sensors.is_empty(), "%s is still empty after a press" % key)


func test_preparing_a_stroke_does_prepare_the_options_that_are_on() -> void:
    var settings := _settings()
    settings.size_by_pressure = true
    var dynamics := SaDynamics.new(settings)

    dynamics.begin_stroke()

    assert_eq(settings.size_option.active_sensors().size(), 1, "The size option is prepared")
    assert_eq(settings.opacity_option.active_sensors().size(), 1, "and so is opacity")


# --- The bar's two switches ---------------------------------------------------


func test_the_bar_switches_still_reach_the_option_they_name() -> void:
    var settings := _settings()

    settings.size_by_pressure = true

    assert_true(settings.size_option.enabled, "Size by Pressure on the bar switches the option on")
    assert_true(settings.size_option.use_curve, "and has it read its sensor")
    assert_eq(settings.size_option.active_sensors().size(), 1, "which is pressure")

    settings.size_by_pressure = false

    assert_false(settings.size_option.enabled, "and off switches it off")


func test_switching_pressure_off_and_on_keeps_the_curve_that_was_there() -> void:
    var settings := _settings()
    var drawn := PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.3, 0.8), Vector2(1.0, 1.0)])
    settings.opacity_option.common_curve = drawn

    settings.opacity_by_pressure = false
    settings.opacity_by_pressure = true

    assert_eq(settings.opacity_option.common_curve, drawn, "The painter's curve, not the exponent it came from")


# --- The airbrush interval ----------------------------------------------------


func test_the_rate_option_can_only_lengthen_the_interval() -> void:
    var settings := _settings()
    var dynamics := SaDynamics.new(settings)
    var info := _sample(1.0)

    assert_almost_eq(dynamics.airbrush_interval(info, 20.0), 50.0, 1e-6, "Twenty dabs a second is fifty milliseconds")

    settings.rate_option.enabled = true
    settings.rate_option.use_curve = false
    settings.rate_option.strength = 0.5

    assert_almost_eq(dynamics.airbrush_interval(info, 20.0), 100.0, 1e-6, "and half the rate is twice the wait")
