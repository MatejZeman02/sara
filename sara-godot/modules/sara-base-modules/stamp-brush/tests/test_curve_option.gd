## The curve option's two reducers and its five combination modes.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Every expected number is worked out by hand from
## the two reducers
## rather than recomputed from the code under test, because the risk of a port is a constant
## read wrong, and a test that recomputes cannot see one.
##
## The reducers are where a sign error hides, because both of them look
## plausible with the sign flipped. So the rotation-like tests below are written
## as the catch: the drawing angle alone, everything else off, has to
## come out as the negated angle modulo a turn.
extends "res://tests/test_framework.gd"


func _info(pressure: float = 1.0) -> SaStrokeInfo:
    var info := SaStrokeInfo.new()
    info.begin(Vector2.ZERO, 4242)
    info.pressure = pressure
    return info


## An option with the sensors named and nothing else on, each at full strength
## with the identity curve, so what comes out is the reducer and not a curve.
func _option(ids: Array) -> SaCurveOption:
    var option := SaCurveOption.new()
    for id: SaSensor.Id in ids:
        option.set_sensor(SaSensor.create(id, true))
    option.begin_stroke()
    return option


# --- The five combination modes ---------------------------------------------------


## Two plain sensors, so the switch is reached: one sensor bypasses it.
## Pressure reads 0.5 and tilt x reads 0.75, from 1 - 15 / 60.
func _two_plain() -> Array:
    var info := _info(0.5)
    info.tilt_x = 15.0
    var option := _option([SaSensor.Id.PRESSURE, SaSensor.Id.TILT_X])
    return [option, info]


func test_multiply_is_the_default_and_is_the_product() -> void:
    var pair := _two_plain()
    var option: SaCurveOption = pair[0]
    var info: SaStrokeInfo = pair[1]

    assert_eq(int(option.combine), int(SaCurveOption.Combine.MULTIPLY), "Multiply is what an option starts as")
    # 0.5 * 0.75.
    assert_almost_eq(option.size_like(info), 0.375, 1e-6, "and 0.5 by 0.75 is 0.375")


func test_add_sums_and_the_bound_catches_it() -> void:
    var pair := _two_plain()
    var option: SaCurveOption = pair[0]
    var info: SaStrokeInfo = pair[1]
    option.combine = SaCurveOption.Combine.ADD

    # 0.5 + 0.75 is 1.25, which the default maximum of 1 clamps.
    assert_almost_eq(option.size_like(info), 1.0, 1e-6, "The sum is past the option's ceiling and stops there")

    option.strength_max = 4.0
    assert_almost_eq(option.size_like(info), 1.25, 1e-6, "and a wider option lets the whole sum through")


func test_maximum_and_minimum_take_one_of_the_two() -> void:
    var pair := _two_plain()
    var option: SaCurveOption = pair[0]
    var info: SaStrokeInfo = pair[1]

    option.combine = SaCurveOption.Combine.MAXIMUM
    assert_almost_eq(option.size_like(info), 0.75, 1e-6, "The larger of 0.5 and 0.75")

    option.combine = SaCurveOption.Combine.MINIMUM
    assert_almost_eq(option.size_like(info), 0.5, 1e-6, "and the smaller")


func test_difference_is_the_spread_between_them() -> void:
    var pair := _two_plain()
    var option: SaCurveOption = pair[0]
    var info: SaStrokeInfo = pair[1]
    option.combine = SaCurveOption.Combine.DIFFERENCE

    # 0.75 - 0.5.
    assert_almost_eq(option.size_like(info), 0.25, 1e-6, "0.75 less 0.5 is a quarter")


func test_the_modes_are_in_kritas_order_so_a_stored_number_travels() -> void:
    assert_eq(int(SaCurveOption.Combine.MULTIPLY), 0, "0 is multiply")
    assert_eq(int(SaCurveOption.Combine.ADD), 1, "1 add")
    assert_eq(int(SaCurveOption.Combine.MAXIMUM), 2, "2 maximum")
    assert_eq(int(SaCurveOption.Combine.MINIMUM), 3, "3 minimum")
    assert_eq(int(SaCurveOption.Combine.DIFFERENCE), 4, "and 4 the difference")


func test_one_sensor_bypasses_the_switch() -> void:
    var info := _info(0.5)
    var option := _option([SaSensor.Id.PRESSURE])

    for mode: SaCurveOption.Combine in [
        SaCurveOption.Combine.MULTIPLY,
        SaCurveOption.Combine.ADD,
        SaCurveOption.Combine.MAXIMUM,
        SaCurveOption.Combine.MINIMUM,
        SaCurveOption.Combine.DIFFERENCE
    ]:
        option.combine = mode
        assert_almost_eq(option.size_like(info), 0.5, 1e-6, "One sensor reads the same under mode %d" % int(mode))


# --- The buckets ------------------------------------------------------------------


func test_an_additive_sensor_sums_while_a_plain_one_multiplies() -> void:
    var info := _info(0.5)
    info.barrel_rotation = 90.0
    var option := _option([SaSensor.Id.PRESSURE, SaSensor.Id.ROTATION])

    # Pressure is the only scaling sensor, so scaling is 0.5. Rotation is
    # additive at 90 / 180 = 0.5, which additiveToScaling maps to 0.75.
    # 1 * 1 * 0.5 * 0.75.
    assert_almost_eq(option.size_like(info), 0.375, 1e-6, "The additive part is mapped in before it multiplies")


func test_the_absolute_rotation_sensor_overwrites_the_offset() -> void:
    var info := _info(0.5)
    info.last_position = Vector2.ZERO
    info.position = Vector2(10.0, 0.0)
    var option := _option([SaSensor.Id.PRESSURE, SaSensor.Id.DRAWING_ANGLE])

    # The drawing angle reads 0.5 and becomes the offset, so the size-like value
    # is offset 0.5 times scaling 0.5 rather than the 1.0 an absent offset gives.
    assert_almost_eq(option.size_like(info), 0.25, 1e-6, "The offset replaces the 1 an option without one uses")


func test_an_absent_part_is_one_rather_than_nothing() -> void:
    var info := _info(0.5)
    var option := _option([SaSensor.Id.PRESSURE])

    # No offset, no additive: both are 1, so the answer is the scaling alone.
    assert_almost_eq(option.size_like(info), 0.5, 1e-6, "An option with one plain sensor is that sensor")


# --- The rotation-like reducer ----------------------------------------------------


func test_the_drawing_angle_alone_is_the_negated_angle_modulo_a_turn() -> void:
    var option := _option([SaSensor.Id.DRAWING_ANGLE])

    for degrees: float in [0.0, 45.0, 90.0, 135.0, 180.0, 225.0, 315.0]:
        var radians := deg_to_rad(degrees)
        var info := _info()
        info.last_position = Vector2.ZERO
        info.position = Vector2(cos(radians), sin(radians)) * 10.0

        # The sensor answers 0.5 + angle / TAU, which lands in the offset, and
        # the reducer doubles it: 1 + angle / PI, wrapped into -1 to 1. That is
        # the angle in half-turns plus one turn, so it comes back as the angle
        # itself measured the other way round, which is the sign the port has to
        # get right.
        var expected := SaCurveOption.wrap_signed(1.0 + radians / PI)

        assert_almost_eq(
            option.rotation_like(info, 0.0, false),
            expected,
            1e-5,
            "%d degrees reduces to %f half-turns" % [int(degrees), expected]
        )


func test_without_an_absolute_sensor_the_base_angle_is_the_offset() -> void:
    var info := _info(1.0)
    var option := _option([SaSensor.Id.PRESSURE])

    # Base angle 0.25 doubles to 0.5, and pressure at 1 is a scaling of 1, which
    # scalingToAdditive maps to 1, so 0.5 + 1 is 1.5 and wraps to -0.5.
    assert_almost_eq(
        option.rotation_like(info, 0.25, false),
        -0.5,
        1e-5,
        "The canvas rotation is what an option with no angle sensor turns about"
    )


func test_the_flip_mirrors_the_offset_about_a_quarter_turn() -> void:
    var info := _info()
    info.last_position = Vector2.ZERO
    info.position = Vector2(10.0, 0.0)
    var option := _option([SaSensor.Id.DRAWING_ANGLE])

    var upright := option.rotation_like(info, 0.0, false)
    var mirrored := option.rotation_like(info, 0.0, true)

    # The offset is 0.5, so flipped it is 0.5 - 0.5 = 0, and the reducer doubles
    # each: 1 wraps to -1, and 0 stays 0.
    assert_almost_eq(upright, -1.0, 1e-5, "A stroke going right is a half turn")
    assert_almost_eq(mirrored, 0.0, 1e-5, "and on a mirrored canvas it is none")


func test_the_coefficient_turns_the_scaling_part_the_other_way() -> void:
    var info := _info(1.0)
    var option := _option([SaSensor.Id.PRESSURE])

    var forwards := option.rotation_like(info, 0.0, false, 1.0)
    var backwards := option.rotation_like(info, 0.0, false, -1.0)

    # Pressure at 1 is a scaling of 1, which maps to an additive 1. With the
    # coefficient at 1 that is 1, wrapping to -1, and at -1 it is -1.
    assert_almost_eq(forwards, -1.0, 1e-5, "A positive coefficient turns one way")
    assert_almost_eq(backwards, -1.0, 1e-5, "and -1 the other, which meets it at the wrap")

    info.pressure = 0.5
    assert_almost_eq(option.rotation_like(info, 0.0, false, 1.0), 0.0, 1e-5, "Half pressure with the coefficient at 1 is nothing")
    assert_almost_eq(option.rotation_like(info, 0.0, false, -1.0), 0.0, 1e-5, "and the same the other way, being the middle")

    info.pressure = 0.75
    assert_almost_eq(option.rotation_like(info, 0.0, false, 1.0), 0.5, 1e-5, "Three quarters turns one way")
    assert_almost_eq(option.rotation_like(info, 0.0, false, -1.0), -0.5, 1e-5, "and the coefficient turns it the other")


func test_disabling_the_scaling_part_drops_it_and_keeps_the_rest() -> void:
    var info := _info(1.0)
    var option := _option([SaSensor.Id.PRESSURE])

    assert_almost_eq(option.rotation_like(info, 0.0, false, 1.0, false), -1.0, 1e-5, "With the scaling part in")
    assert_almost_eq(option.rotation_like(info, 0.0, false, 1.0, true), 0.0, 1e-5, "and without it, which is what hovering does")


func test_rotation_like_wraps_and_does_not_clamp() -> void:
    assert_almost_eq(SaCurveOption.wrap_signed(1.5), -0.5, 1e-6, "Past the end comes back at the start")
    assert_almost_eq(SaCurveOption.wrap_signed(-1.5), 0.5, 1e-6, "and before it, at the end")
    assert_almost_eq(SaCurveOption.wrap_signed(3.0), -1.0, 1e-6, "and a value more than a turn out still lands inside")
    assert_almost_eq(SaCurveOption.wrap_signed(0.25), 0.25, 1e-6, "while a value inside is left alone")


# --- The bounds -------------------------------------------------------------------


func test_the_bounds_hold_the_size_like_value_and_not_the_rotation_like_one() -> void:
    var info := _info(1.0)
    var option := _option([SaSensor.Id.PRESSURE])
    option.strength_min = 0.4
    option.strength_max = 0.6

    assert_almost_eq(option.size_like(info), 0.6, 1e-6, "A size-like value is clamped to the option's range")

    info.pressure = 0.0
    assert_almost_eq(option.size_like(info), 0.4, 1e-6, "at both ends")

    info.pressure = 1.0
    assert_almost_eq(
        option.rotation_like(info, 0.0, false),
        -1.0,
        1e-5,
        "and the rotation-like one is not, being an angle: 0.6 would be a brush stuck at its limit"
    )


func test_the_default_bounds_are_nought_to_one() -> void:
    var option := SaCurveOption.create_default()

    assert_almost_eq(option.strength_min, 0.0, 1e-6, "Krita's KisCurveOptionDataCommon defaults")
    assert_almost_eq(option.strength_max, 1.0, 1e-6, "which are the range most options carry")
    assert_almost_eq(option.strength, 1.0, 1e-6, "and a strength of one, which changes nothing")


# --- The two flags ----------------------------------------------------------------


func test_use_curve_off_answers_the_strength_whatever_the_sensors_say() -> void:
    var info := _info(0.1)
    var option := _option([SaSensor.Id.PRESSURE])
    option.strength = 0.8
    option.use_curve = false

    assert_almost_eq(option.size_like(info), 0.8, 1e-6, "A constant, and the sensor at 0.1 is not read")

    option.strength = 4.0
    assert_almost_eq(option.size_like(info), 1.0, 1e-6, "and the constant is still clamped to the option's range")


func test_use_curve_off_is_not_the_same_as_enabled_off() -> void:
    var option := SaCurveOption.create_default()
    option.use_curve = false

    assert_true(option.enabled, "The option is still on")
    assert_false(option.use_curve, "and is a constant rather than switched off, which is the pair Krita keeps apart")


func test_the_strength_multiplies_what_the_sensors_reduced_to() -> void:
    var info := _info(0.5)
    var option := _option([SaSensor.Id.PRESSURE])
    option.strength = 0.5

    # 0.5 * 0.5.
    assert_almost_eq(option.size_like(info), 0.25, 1e-6, "The constant is a multiplier on the reduced value")
    assert_almost_eq(option.size_like(info, false), 0.5, 1e-6, "and dropping it leaves the sensors alone")


# --- The sensor set ---------------------------------------------------------------


func test_a_default_option_is_pressure_active_with_an_identity_curve() -> void:
    var option := SaCurveOption.create_default()

    var active := option.active_sensors()
    assert_eq(active.size(), 1, "One sensor")
    assert_eq(int(active[0].id), int(SaSensor.Id.PRESSURE), "and it is pressure")
    assert_true(SaSensor.is_identity_curve(active[0].curve), "with the curve that does nothing")


func test_an_option_that_arrives_with_no_active_sensor_gets_pressure_back() -> void:
    var option := SaCurveOption.new()
    option.set_sensor(SaSensor.create(SaSensor.Id.SPEED, false))
    assert_true(option.active_sensors().is_empty(), "A preset can arrive with everything off")

    option.ensure_one_active()

    var active := option.active_sensors()
    assert_eq(active.size(), 1, "and one sensor is switched on")
    assert_eq(int(active[0].id), int(SaSensor.Id.PRESSURE), "which is pressure, Krita's own rule")


## The prepared list reads the common curve, and **the stored sensors do not**.
## Requiring `active_sensors()` to carry the common curve would be wrong, which is
## exactly the write that destroys a painter's per-sensor curves and puts the loss in the next `.tres`.
func test_use_same_curve_hands_every_prepared_sensor_the_common_one() -> void:
    var option := SaCurveOption.new()
    option.set_sensor(SaSensor.create(SaSensor.Id.PRESSURE, true))
    option.set_sensor(SaSensor.create(SaSensor.Id.SPEED, true))
    var drawn := PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.25, 0.9), Vector2(1.0, 1.0)])
    for sensor in option.active_sensors():
        sensor.curve = drawn.duplicate()
    option.common_curve = PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.5, 0.9), Vector2(1.0, 1.0)])

    option.begin_stroke()

    for sensor in option._prepared:
        assert_eq(sensor.curve, option.common_curve, "%s is read through the shared curve" % SaSensor.key_of(sensor.id))
    for sensor in option.active_sensors():
        assert_eq(sensor.curve, drawn, "and %s keeps its own" % SaSensor.key_of(sensor.id))


## The round trip a painter makes: draw a curve per sensor, turn sharing on to
## compare, paint, turn it off again. The drawn curve is still there, and there
## is no undo in that window, which is why this is a defect rather than a
## surprise.
func test_a_stroke_with_sharing_on_leaves_the_drawn_curve_alone() -> void:
    var option := SaCurveOption.create_default()
    option.use_same_curve = false
    var pressure := option.sensor_for(SaSensor.Id.PRESSURE)
    var drawn := PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.25, 0.9), Vector2(1.0, 1.0)])
    pressure.curve = drawn.duplicate()

    option.use_same_curve = true
    option.common_curve = PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.75, 0.1), Vector2(1.0, 1.0)])
    option.begin_stroke()
    option.use_same_curve = false

    assert_eq(pressure.curve, drawn, "The sensor still carries the curve the painter drew")


## Sharing still changes what the option answers, which is the half that has to
## keep working: a fix that stopped writing the sensor and also stopped reading
## the shared curve would pass the case above and paint the wrong stroke.
func test_sharing_still_decides_which_curve_the_reading_goes_through() -> void:
    var info := _info(0.5)
    var option := SaCurveOption.create_default()
    option.use_same_curve = false
    # Flat at nought up to the middle, so a pressure of 0.5 reads far from 0.5
    # through it and exactly 0.5 through the identity.
    option.sensor_for(SaSensor.Id.PRESSURE).curve = PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.5, 0.0), Vector2(1.0, 1.0)])
    option.begin_stroke()
    var through_its_own := option.size_like(info)
    assert_true(through_its_own < 0.2, "The sensor's own curve is read while sharing is off, %.4f" % through_its_own)

    option.use_same_curve = true
    option.common_curve = PackedVector2Array([Vector2(0.0, 0.0), Vector2(1.0, 1.0)])
    option.begin_stroke()
    assert_almost_eq(option.size_like(info), 0.5, 1e-6, "and the shared identity is read while it is on")

    option.use_same_curve = false
    option.begin_stroke()
    assert_almost_eq(option.size_like(info), through_its_own, 1e-6, "and turning it off again gives the same answer as before")


## The shipped brush, which is what makes this live rather than theoretical.
## `SaStampBrushSettings.opacity_option` ships with `enabled`, `use_curve` and
## `use_same_curve` all true, so `SaDynamics` prepares it on every press.
func test_the_shipped_opacity_option_keeps_a_drawn_sensor_curve() -> void:
    var settings := SaStampBrushSettings.new()
    var option: SaCurveOption = settings.opacity_option
    assert_true(option.use_same_curve, "The shipped option shares, which is the case that bites")
    var pressure := option.sensor_for(SaSensor.Id.PRESSURE)
    assert_not_null(pressure, "and it listens to pressure")
    var drawn := PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.25, 0.9), Vector2(1.0, 1.0)])
    pressure.curve = drawn.duplicate()

    var dynamics := SaDynamics.new()
    dynamics.settings = settings
    dynamics.begin_stroke()

    assert_eq(pressure.curve, drawn, "One press leaves the drawn curve where the painter put it")


func test_the_prepared_list_is_built_once_and_not_per_dab() -> void:
    var info := _info(0.5)
    var option := SaCurveOption.create_default()

    # Never begun, so the first read has to prepare itself rather than answer
    # from an empty list, which would be a silent constant.
    assert_almost_eq(option.size_like(info), 0.5, 1e-6, "A read before the press still works")

    option.set_sensor(SaSensor.create(SaSensor.Id.SPEED, true))
    option.begin_stroke()

    assert_eq(option.active_sensors().size(), 2, "and a sensor added afterwards is picked up at the next press")
