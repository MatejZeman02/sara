## The colour source and the three colour offsets: what the evaluator answers
## and what those numbers do to a picked colour.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **The load-bearing case is the first one.** A brush nobody has switched a
## colour option on has to paint the colour it always painted, to the bit and
## not to a tolerance: the shift runs through Oklab and back, which is close to
## exact and is not exact, and a texel assertion anywhere else in the suite
## would start failing by a unit in the last place. `SaColorDynamics.apply`
## answers early for that reason and this is what holds it there.
##
## Everything here drives `SaDynamics` over a fixed sample rather than painting,
## because what a dab does with the three numbers is arithmetic and the stroke
## it makes is the scenario's job.
extends "res://tests/test_framework.gd"

## The picked colour every case starts from: a middling blue, chromatic enough
## that a hue turn and a chroma pull are both visible in the numbers, and clear
## of both ends so a value offset has room either way.
const PICKED := Color(0.25, 0.35, 0.75, 1.0)


func _settings() -> SaStampBrushSettings:
    return SaStampBrushSettings.new()


func _sample(pressure: float) -> SaStrokeInfo:
    var info := SaStrokeInfo.new()
    info.begin(Vector2.ZERO, 4242)
    info.hovering = false
    info.pressure = pressure
    return info


## An option switched on with one sensor under it, which is the shape
## `_modulates` asks for and the only shape that shifts a colour.
func _drive(option: SaCurveOption, strength: float, sensor: SaSensor.Id = SaSensor.Id.PRESSURE) -> void:
    option.enabled = true
    option.strength = strength
    option.set_sensor(SaSensor.create(sensor, true))


## The Oklab reading of a colour, so a case can say what moved rather than
## comparing two sRGB triples and hoping.
func _polar(color: Color) -> Vector3:
    var curve := SaTransferFunction.srgb()
    var linear := Vector3(curve.decode(color.r), curve.decode(color.g), curve.decode(color.b))
    return SaOklab.to_polar(SaOklab.from_linear_srgb(linear))


# --- The colour nobody modulated ---------------------------------------------


## A fresh settings resource answers the colour
## unchanged. To the bit, which is what `assert_eq` on a `Color` asks.
func test_a_fresh_settings_resource_leaves_the_picked_colour_alone() -> void:
    var dynamics := SaDynamics.new(_settings())
    var dab := dynamics.evaluate(_sample(0.8), 40.0)

    assert_almost_eq(dab.hue_shift, 0.0, 1e-9, "A fresh brush turns no hue")
    assert_almost_eq(dab.saturation_shift, 0.0, 1e-9, "moves no chroma")
    assert_almost_eq(dab.value_shift, 0.0, 1e-9, "and moves no lightness")
    assert_eq(SaColorDynamics.apply(PICKED, dab), PICKED, "so the picked colour comes back exactly, not nearly")
    assert_eq(_settings().color_source, SaColorDynamics.Source.PLAIN, "and the colour source is the plain one")


## An option that is on with nothing under it is a constant, and a constant
## colour shift is not the variation within a stroke the option exists for. The
## rule for rotation is applied to all three.
func test_an_option_with_no_sensor_shifts_nothing() -> void:
    var settings := _settings()
    for option: SaCurveOption in [settings.hue_option, settings.saturation_option, settings.value_option]:
        option.enabled = true
        option.strength = 1.0

    var dab := SaDynamics.new(settings).evaluate(_sample(0.8), 40.0)

    assert_almost_eq(dab.hue_shift, 0.0, 1e-9, "Hue with no sensor under it is no hue shift")
    assert_almost_eq(dab.saturation_shift, 0.0, 1e-9, "and so is saturation")
    assert_almost_eq(dab.value_shift, 0.0, 1e-9, "and so is value")
    assert_eq(SaColorDynamics.apply(PICKED, dab), PICKED, "so the colour is untouched")


# --- The three offsets --------------------------------------------------------


## For value, the offset is the sensor's reading
## moved onto -1 to 1, so half pressure is no shift and either end is a full
## one. A multiplier could only ever take lightness away, and the option exists
## for variation.
func test_value_is_a_signed_offset_around_the_middle_of_the_sensor() -> void:
    var settings := _settings()
    _drive(settings.value_option, 1.0)
    var dynamics := SaDynamics.new(settings)

    assert_almost_eq(dynamics.evaluate(_sample(0.5), 40.0).value_shift, 0.0, 0.02, "Half pressure moves no lightness")
    assert_almost_eq(dynamics.evaluate(_sample(1.0), 40.0).value_shift, 1.0, 0.02, "full pressure lifts it all the way")
    assert_almost_eq(dynamics.evaluate(_sample(0.0), 40.0).value_shift, -1.0, 0.02, "and none drops it all the way")


## The strength halves the shift rather than dragging it towards one end, which
## is the whole reason it is applied after the move onto -1 to 1 and not before.
func test_the_strength_scales_the_offset_in_both_directions() -> void:
    var settings := _settings()
    _drive(settings.value_option, 0.5)
    var dynamics := SaDynamics.new(settings)

    assert_almost_eq(dynamics.evaluate(_sample(1.0), 40.0).value_shift, 0.5, 0.02, "Half strength lifts half as far")
    assert_almost_eq(dynamics.evaluate(_sample(0.0), 40.0).value_shift, -0.5, 0.02, "and drops half as far")
    assert_almost_eq(dynamics.evaluate(_sample(0.5), 40.0).value_shift, 0.0, 0.02, "with the middle still the middle")


## Value moves Oklab's lightness and leaves the hue where the painter picked it,
## which is the reason the maths is not HSV on the picked sRGB.
func test_a_value_offset_moves_lightness_and_not_hue() -> void:
    var settings := _settings()
    _drive(settings.value_option, 1.0)
    var dab := SaDynamics.new(settings).evaluate(_sample(1.0), 40.0)

    var before := _polar(PICKED)
    var after := _polar(SaColorDynamics.apply(PICKED, dab))
    assert_true(after.x > before.x + 0.2, "Full pressure lifted the lightness: %f to %f" % [before.x, after.x])
    assert_almost_eq(after.z, before.z, 0.02, "and left the hue angle where it was")


## Saturation moves chroma, and one whole unit of it is worth the stated chroma
## rather than a raw 1.0, which would be three times the gamut.
func test_a_saturation_offset_moves_chroma_by_the_stated_scale() -> void:
    var settings := _settings()
    _drive(settings.saturation_option, 1.0)
    var dab := SaDynamics.new(settings).evaluate(_sample(1.0), 40.0)

    var before := _polar(PICKED)
    var after := _polar(SaColorDynamics.apply(PICKED, dab))
    assert_almost_eq(
        after.y - before.y,
        SaColorDynamics.MAX_CHROMA_SHIFT,
        0.02,
        "A full saturation offset is MAX_CHROMA_SHIFT of chroma, %f to %f" % [before.y, after.y]
    )


## Chroma has a floor and lightness has none. A negative chroma is the same
## colour with its hue turned half a circle, so pulling saturation past grey has
## to stop at grey, and a lightness pushed past one is a value the float canvas
## is meant to keep (hard rule 5).
func test_chroma_stops_at_grey_and_lightness_does_not_stop_at_one() -> void:
    var settings := _settings()
    _drive(settings.saturation_option, 1.0)
    var pulled := SaDynamics.new(settings).evaluate(_sample(0.0), 40.0)
    var grey := _polar(SaColorDynamics.apply(PICKED, pulled))

    assert_true(grey.y >= 0.0, "Chroma never goes negative: %f" % grey.y)
    assert_almost_eq(grey.y, 0.0, 1e-6, "and a full pull lands on grey rather than the opposite hue")

    var bright := SaDabParams.new()
    bright.value_shift = 1.0
    var lifted := SaColorDynamics.apply(Color(0.9, 0.9, 0.9, 1.0), bright)
    assert_true(lifted.r > 1.0, "A lightness pushed past one comes out above one rather than clamped: %f" % lifted.r)


# --- Hue wraps ----------------------------------------------------------------


## Hue wraps rather than clamps, because an angle
## has no ends. Half a turn past one limit is half a turn before the other, and
## a clamp would stick every dab at the same colour where turning it round is
## what the painter drew.
func test_hue_wraps_rather_than_clamping() -> void:
    var settings := _settings()
    _drive(settings.hue_option, 0.5)
    var dynamics := SaDynamics.new(settings)

    var top := dynamics.evaluate(_sample(1.0), 40.0).hue_shift
    var bottom := dynamics.evaluate(_sample(0.0), 40.0).hue_shift
    assert_almost_eq(top, 0.5, 0.02, "Half strength at full pressure is a quarter turn one way")
    assert_almost_eq(bottom, -0.5, 0.02, "and at no pressure a quarter turn the other")

    # At full strength the two ends are half a turn either way, which is the same
    # place: 1 and -1 name one direction and the reducer answers the negative of
    # the pair. That is the wrap doing its job rather than a reading stuck at a
    # limit, and it is the case a clamp would get wrong in the other direction.
    _drive(settings.hue_option, 1.0)
    var full := SaDynamics.new(settings)
    assert_almost_eq(full.evaluate(_sample(1.0), 40.0).hue_shift, -1.0, 0.02, "A full offset wraps onto the far side")
    assert_almost_eq(full.evaluate(_sample(0.0), 40.0).hue_shift, -1.0, 0.02, "from either end, because the two are one place")

    # The reducer's own wrap, on the number rather than through the sensors: an
    # offset of a turn and a half is half a turn the other way.
    assert_almost_eq(SaCurveOption.wrap_signed(1.5), -0.5, 1e-6, "A turn and a half wraps to half a turn back")
    assert_almost_eq(SaCurveOption.wrap_signed(-1.5), 0.5, 1e-6, "and the same the other way round")


## A whole unit of hue offset is the far side of the colour circle, and turning
## a colour a whole turn either way is where it started.
func test_a_hue_offset_turns_the_colour_circle_and_comes_back() -> void:
    var half := SaDabParams.new()
    half.hue_shift = 1.0
    var opposite := _polar(SaColorDynamics.apply(PICKED, half))
    var before := _polar(PICKED)

    assert_almost_eq(absf(SaCurveOption.wrap_signed((opposite.z - before.z) / PI)), 1.0, 0.02, "A full offset is half a circle")
    assert_almost_eq(opposite.y, before.y, 0.02, "with the chroma where it was")
    assert_almost_eq(opposite.x, before.x, 0.02, "and the lightness too, which HSV would not have managed")


## A grey has no hue, so turning it moves nothing. The honest consequence rather
## than a special case, and it is here so a reader finds it stated.
func test_a_hue_offset_on_a_grey_moves_nothing_visible() -> void:
    var turned := SaDabParams.new()
    turned.hue_shift = 0.5
    var grey := Color(0.5, 0.5, 0.5, 1.0)
    var after := SaColorDynamics.apply(grey, turned)

    assert_almost_eq(after.r, grey.r, 0.001, "A grey turned round the circle is still grey")
    assert_almost_eq(after.g, grey.g, 0.001, "on every channel")
    assert_almost_eq(after.b, grey.b, 0.001, "because it had no chroma to turn")


# --- The seam and the source --------------------------------------------------


## Alpha is coverage and never colour, so nothing here touches it. The dab's own
## alpha is built after this call, from the opacity option.
func test_the_shift_carries_alpha_through_untouched() -> void:
    var dab := SaDabParams.new()
    dab.value_shift = 0.4
    dab.saturation_shift = -0.3

    var half := Color(PICKED.r, PICKED.g, PICKED.b, 0.4)
    assert_almost_eq(SaColorDynamics.apply(half, dab).a, 0.4, 1e-6, "The alpha that went in comes out")


## The dab report carries the three, because a scenario's dump is how the
## stroke's colour is read back and a number nobody dumps is a number nobody
## can check against the picture.
func test_the_dab_report_carries_the_three_offsets() -> void:
    var dab := SaDabParams.new()
    dab.hue_shift = 0.25
    dab.saturation_shift = -0.5
    dab.value_shift = 0.75
    var report := dab.report()

    assert_almost_eq(float(report["hue_shift"]), 0.25, 1e-9, "The report names the hue offset")
    assert_almost_eq(float(report["saturation_shift"]), -0.5, 1e-9, "the saturation offset")
    assert_almost_eq(float(report["value_shift"]), 0.75, 1e-9, "and the value offset")


## The source is an enum whose first value is plain, and a second kind came in
## as a value and not a rewrite, the gradient, which its own suite reads.
func test_the_colour_source_is_an_enum_whose_first_value_is_plain() -> void:
    assert_eq(SaColorDynamics.Source.PLAIN, 0, "Plain is the first value, so a file that stored 0 still reads plain")
    assert_eq(SaColorDynamics.source_name(SaColorDynamics.Source.PLAIN), "plain", "and it names itself for a dump")
    assert_eq(SaColorDynamics.source_name(99), "unknown", "with anything else named rather than answered as plain")


## The three options are in the settings' own list under their own names, which
## is what the editor builds a page from and what a dump reports.
##
## No count here. `test_brush_settings_migration.gd` counts the options against
## its own bounds table, which is the one place that says how many there are,
## and a second number here was wrong within a merge of being written: the
## mirror made fourteen fifteen while the colour offsets were integrating.
func test_the_three_options_are_in_the_settings_list() -> void:
    var options := _settings().options()

    assert_true(options.has("hue"), "Hue is one of the options")
    assert_true(options.has("saturation"), "and so is saturation")
    assert_true(options.has("value"), "and so is value")
    for key: String in ["hue", "saturation", "value"]:
        assert_false(options[key].enabled, "%s is off for a new brush, so no preset moves" % key)
