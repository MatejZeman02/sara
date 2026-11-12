## Every sensor's value against the spec's table, and the curve mapping.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **The numbers are written out rather than computed by the same code twice.**
## A test that recomputes `1 - abs(x) / 60` asserts that the file is
## self-consistent and nothing else, and the whole risk of a port is a constant
## that was read wrong. So the expected values below are worked out by hand from
## Krita's sensor table and the tolerance is tight enough that a wrong divisor
## cannot hide in it.
extends "res://tests/test_framework.gd"


## A sample with nothing in it: at the origin, no pressure, no tilt, painting.
func _info() -> SaStrokeInfo:
    var info := SaStrokeInfo.new()
    info.begin(Vector2.ZERO, 12345)
    return info


func _sensor(id: SaSensor.Id) -> SaSensor:
    return SaSensor.create(id, true)


# --- The fourteen values ---------------------------------------------------------


func test_pressure_is_the_sample_s_own() -> void:
    var info := _info()
    info.pressure = 0.375

    assert_almost_eq(_sensor(SaSensor.Id.PRESSURE).value(info), 0.375, 1e-6, "Pressure is read straight through")


func test_pressure_in_is_the_highest_so_far_and_nothing_while_hovering() -> void:
    var info := _info()
    info.max_pressure = 0.8
    var sensor := _sensor(SaSensor.Id.PRESSURE_IN)

    assert_almost_eq(sensor.value(info), 0.8, 1e-6, "Pressure in is the stroke's highest")

    info.hovering = true

    assert_almost_eq(sensor.value(info), 0.0, 1e-6, "and nothing at all while hovering")


func test_the_two_tilt_axes_run_from_one_at_upright_to_zero_at_sixty() -> void:
    var info := _info()
    info.tilt_x = 15.0
    info.tilt_y = -60.0

    # 1 - 15 / 60 and 1 - 60 / 60.
    assert_almost_eq(_sensor(SaSensor.Id.TILT_X).value(info), 0.75, 1e-6, "15 degrees of x tilt is 0.75")
    assert_almost_eq(_sensor(SaSensor.Id.TILT_Y).value(info), 0.0, 1e-6, "and 60 degrees is 0, whichever way it leans")


func test_tilt_direction_is_a_whole_turn_mapped_additively() -> void:
    var info := _info()
    var sensor := _sensor(SaSensor.Id.TILT_DIRECTION)

    # atan2(-0, 30) is 0, so the scaled value is 0.5 and the additive one is 0.
    info.tilt_x = 0.0
    info.tilt_y = 30.0
    assert_almost_eq(sensor.value(info), 0.0, 1e-6, "A pen leaning straight up the y axis is the middle of the range")

    # atan2(-30, 0) is -PI/2, so -0.25 + 0.5 is 0.25 scaled and -0.5 additive.
    info.tilt_x = 30.0
    info.tilt_y = 0.0
    assert_almost_eq(sensor.value(info), -0.5, 1e-6, "and a quarter turn from it is half way to the end")


func test_tilt_elevation_is_one_upright_and_zero_flat() -> void:
    var info := _info()
    var sensor := _sensor(SaSensor.Id.TILT_ELEVATION)

    assert_almost_eq(sensor.value(info), 1.0, 1e-6, "No tilt at all is a pen standing straight up")

    # x = 1, y = 0, so e = sqrt(1 + 0) = 1, cos alpha = 1, acos = 0.
    info.tilt_x = 60.0
    info.tilt_y = 0.0
    assert_almost_eq(sensor.value(info), 0.0, 1e-6, "and a pen flat on the tablet is nothing")

    # x = y = 1, so e = sqrt(2), cos alpha = sqrt(2) / sqrt(2) = 1, acos = 0.
    info.tilt_x = 60.0
    info.tilt_y = 60.0
    assert_almost_eq(sensor.value(info), 0.0, 1e-6, "and so is a pen flat along the diagonal")


func test_rotation_is_the_barrel_in_half_turns() -> void:
    var info := _info()
    info.barrel_rotation = 90.0

    assert_almost_eq(_sensor(SaSensor.Id.ROTATION).value(info), 0.5, 1e-6, "90 degrees of barrel is half a half-turn")

    info.barrel_rotation = -180.0

    assert_almost_eq(_sensor(SaSensor.Id.ROTATION).value(info), -1.0, 1e-6, "and -180 is the end of the range")


func test_the_drawing_angle_puts_zero_in_the_middle() -> void:
    var info := _info()
    var sensor := _sensor(SaSensor.Id.DRAWING_ANGLE)

    # 0.5 + 0 / TAU + 0 / 360.
    info.last_position = Vector2.ZERO
    info.position = Vector2(10.0, 0.0)
    assert_almost_eq(sensor.value(info), 0.5, 1e-6, "A stroke going right is the middle of the range")

    # atan2(10, 0) is PI/2, so 0.5 + 0.25.
    info.position = Vector2(0.0, 10.0)
    assert_almost_eq(sensor.value(info), 0.75, 1e-6, "and a quarter turn from it is three quarters")


func test_the_angle_offset_wraps_rather_than_running_past_one() -> void:
    var info := _info()
    info.last_position = Vector2.ZERO
    info.position = Vector2(0.0, 10.0)
    var sensor := _sensor(SaSensor.Id.DRAWING_ANGLE)
    sensor.angle_offset = 180.0

    # 0.75 + 0.5 is 1.25, which is past the end and comes back as 0.25.
    assert_almost_eq(sensor.value(info), 0.25, 1e-6, "An offset that pushes past 1 subtracts one turn")


func test_a_stroke_that_did_not_move_keeps_the_angle_it_had() -> void:
    var info := _info()
    info.last_position = Vector2(5.0, 5.0)
    info.position = Vector2(5.0, 5.0)
    info.last_angle = PI

    assert_almost_eq(info.drawing_angle(false), PI, 1e-6, "A held pen has no angle of its own, so it keeps the last")


func test_the_locked_angle_is_taken_once_and_never_overwritten() -> void:
    var info := _info()
    info.last_position = Vector2.ZERO
    info.position = Vector2(10.0, 0.0)

    info.next_dab()
    var first := info.locked_angle
    info.last_position = Vector2(10.0, 0.0)
    info.position = Vector2(10.0, 10.0)
    info.next_dab()

    assert_almost_eq(first, 0.0, 1e-6, "The lock is the angle of the first painted dab")
    assert_almost_eq(info.locked_angle, first, 1e-6, "and a later dab at a new angle does not move it")
    assert_almost_eq(info.drawing_angle(true), first, 1e-6, "so the whole stroke can ask for the angle it started at")
    assert_almost_eq(info.drawing_angle(false), PI * 0.5, 1e-6, "while the live angle still answers where it is going")


# --- The three that sweep ---------------------------------------------------------


func test_distance_sweeps_over_its_length_and_wraps_when_periodic() -> void:
    var info := _info()
    var sensor := _sensor(SaSensor.Id.DISTANCE)
    sensor.length = 30

    info.total_length = 15.0
    assert_almost_eq(sensor.value(info), 0.5, 1e-6, "Half of 30 pixels is half way through the sweep")

    info.total_length = 45.0
    assert_almost_eq(sensor.value(info), 0.5, 1e-6, "and 45 wraps to the same place, being periodic")

    sensor.periodic = false
    assert_almost_eq(sensor.value(info), 1.0, 1e-6, "while without the wrap it sweeps once and stays at the end")


func test_time_sweeps_over_milliseconds() -> void:
    var info := _info()
    var sensor := _sensor(SaSensor.Id.TIME)
    sensor.length = 30

    info.elapsed_ms = 7.5
    assert_almost_eq(sensor.value(info), 0.25, 1e-6, "7.5 of 30 milliseconds is a quarter")

    info.elapsed_ms = 67.5
    assert_almost_eq(sensor.value(info), 0.25, 1e-6, "and it wraps twice to the same quarter")


func test_fade_counts_dabs_with_an_integer_modulo() -> void:
    var info := _info()
    var sensor := _sensor(SaSensor.Id.FADE)
    sensor.length = 4

    info.dab_index = 3
    assert_almost_eq(sensor.value(info), 0.75, 1e-6, "Dab 3 of 4 is three quarters")

    info.dab_index = 7
    assert_almost_eq(sensor.value(info), 0.75, 1e-6, "and dab 7 is the same place one sweep later")

    info.dab_index = 4
    assert_almost_eq(sensor.value(info), 0.0, 1e-6, "and the wrap lands exactly on zero rather than near it")


func test_all_three_answer_one_while_hovering() -> void:
    var info := _info()
    info.hovering = true
    info.total_length = 15.0
    info.elapsed_ms = 15.0
    info.dab_index = 500

    for id: SaSensor.Id in [SaSensor.Id.DISTANCE, SaSensor.Id.TIME, SaSensor.Id.FADE]:
        assert_almost_eq(_sensor(id).value(info), 1.0, 1e-6, "%s answers 1 while hovering" % SaSensor.key_of(id))


func test_their_defaults_are_krita_s_thirty_thirty_and_a_thousand() -> void:
    assert_eq(SaSensor.create(SaSensor.Id.DISTANCE).length, 30, "Distance sweeps over 30 pixels")
    assert_eq(SaSensor.create(SaSensor.Id.TIME).length, 30, "Time over 30 milliseconds")
    assert_eq(SaSensor.create(SaSensor.Id.FADE).length, 1000, "and fade over a thousand dabs")
    assert_eq(SaSensor.create(SaSensor.Id.PRESSURE).length, 0, "A sensor with no length carries none rather than a 30")


# --- The two random ones ----------------------------------------------------------


func test_fuzzy_per_dab_is_a_new_number_each_dab_and_nothing_while_hovering() -> void:
    var info := _info()
    var sensor := _sensor(SaSensor.Id.FUZZY_PER_DAB)

    var readings: Array[float] = []
    for i in range(6):
        info.next_dab()
        readings.append(sensor.value(info))

    for reading in readings:
        assert_true(reading >= -1.0 and reading <= 1.0, "Every reading is in the additive range: %f" % reading)
    assert_true(readings[0] != readings[1] or readings[1] != readings[2], "and the dabs do not all agree")

    info.hovering = true
    assert_almost_eq(sensor.value(info), 0.0, 1e-6, "A hovering pen is not fuzzy, it is nothing")


func test_fuzzy_per_stroke_is_one_number_for_the_whole_stroke_and_one_per_option() -> void:
    var info := _info()
    var first := _sensor(SaSensor.Id.FUZZY_PER_STROKE)
    first.resource_name = "size"
    var second := _sensor(SaSensor.Id.FUZZY_PER_STROKE)
    second.resource_name = "opacity"

    var a := first.value(info)
    info.next_dab()
    info.next_dab()

    assert_almost_eq(first.value(info), a, 1e-6, "The same option reads the same number two dabs later")
    assert_true(first.value(info) != second.value(info), "and a second option reads its own, or two would move together")


# --- Speed ------------------------------------------------------------------------


func test_speed_is_zero_for_a_first_sample_and_rises_with_a_faster_one() -> void:
    var slow := _info()
    var fast := _info()

    assert_almost_eq(slow.drawing_speed(), 0.0, 1e-6, "A stroke with one sample has no speed")

    # Twenty samples each, the same clock, ten times the distance.
    for i in range(1, 21):
        slow.feed(Vector2(float(i) * 2.0, 0.0), 1.0, Vector2.ZERO, 0.0, float(i))
        fast.feed(Vector2(float(i) * 20.0, 0.0), 1.0, Vector2.ZERO, 0.0, float(i))

    assert_true(slow.drawing_speed() > 0.0, "A moving stroke has one: %f" % slow.drawing_speed())
    assert_true(
        fast.drawing_speed() > slow.drawing_speed(),
        "and the faster hand reads higher: %f against %f" % [fast.drawing_speed(), slow.drawing_speed()]
    )
    assert_true(fast.drawing_speed() <= 1.0, "with the ceiling holding at 1")


func test_the_running_totals_advance_with_the_stroke() -> void:
    var info := _info()

    info.feed(Vector2(3.0, 4.0), 0.5, Vector2.ZERO, 0.0, 10.0)
    info.next_dab()
    info.feed(Vector2(3.0, 8.0), 0.9, Vector2.ZERO, 0.0, 20.0)
    info.next_dab()

    assert_almost_eq(info.total_length, 9.0, 1e-6, "Five pixels then four is nine of stroke")
    assert_eq(info.dab_index, 2, "and two dabs")
    assert_almost_eq(info.elapsed_ms, 20.0, 1e-6, "and the clock is the sample's own")
    assert_almost_eq(info.max_pressure, info.pressure, 1e-6, "The highest pressure is the last one, it having risen")


# --- The curve --------------------------------------------------------------------


func test_an_identity_curve_is_the_value_itself() -> void:
    var info := _info()
    info.pressure = 0.3
    var sensor := _sensor(SaSensor.Id.PRESSURE)

    assert_true(SaSensor.is_identity_curve(sensor.curve), "A fresh sensor carries the identity")
    assert_almost_eq(sensor.parameter(info), 0.3, 1e-6, "so parameter() is value() and the lookup is skipped")


func test_the_additive_round_trip_is_exact_for_the_identity() -> void:
    var info := _info()
    info.barrel_rotation = 90.0
    var sensor := _sensor(SaSensor.Id.ROTATION)
    # A curve with the same shape as the identity but three points, so the
    # short circuit does not fire and the mapping is exercised.
    sensor.curve = PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.5, 0.5), Vector2(1.0, 1.0)])

    assert_false(SaSensor.is_identity_curve(sensor.curve), "Three points are not the identity by the cheap test")
    assert_almost_eq(sensor.parameter(info), 0.5, 1e-5, "but the additive round trip still lands where it started")


func test_the_absolute_rotation_round_trip_is_exact_for_the_identity() -> void:
    var info := _info()
    info.last_position = Vector2.ZERO
    info.position = Vector2(0.0, 10.0)
    var sensor := _sensor(SaSensor.Id.DRAWING_ANGLE)
    sensor.curve = PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.5, 0.5), Vector2(1.0, 1.0)])

    assert_almost_eq(sensor.parameter(info), 0.75, 1e-5, "The half turn on both sides cancels for a flat curve")


func test_the_two_mappings_are_each_other_s_inverse() -> void:
    for value: float in [-1.0, -0.25, 0.0, 0.5, 1.0]:
        var there := SaSensor.additive_to_scaling(value)
        assert_almost_eq(SaSensor.scaling_to_additive(there), value, 1e-6, "%f survives the round trip" % value)


func test_the_wrap_brings_a_value_back_into_one_turn() -> void:
    assert_almost_eq(SaSensor.wrap_unit(1.25), 0.25, 1e-6, "Past the end comes back to the start")
    assert_almost_eq(SaSensor.wrap_unit(-0.25), 0.75, 1e-6, "and before it comes back to the end")
    assert_almost_eq(SaSensor.wrap_unit(0.5), 0.5, 1e-6, "and inside is left alone")


func test_a_curve_that_is_not_the_identity_bends_the_reading() -> void:
    var info := _info()
    info.pressure = 0.5
    var sensor := _sensor(SaSensor.Id.PRESSURE)
    # Half way along, twice as high: a curve that makes a light touch count.
    sensor.curve = PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.5, 0.9), Vector2(1.0, 1.0)])

    assert_almost_eq(sensor.parameter(info), 0.9, 0.01, "A control point at (0.5, 0.9) answers 0.9 at 0.5")
    assert_almost_eq(sensor.value(info), 0.5, 1e-6, "while value() is still the sensor's own reading")


# --- The set ----------------------------------------------------------------------


## Sixteen from Krita and four of Sara's own, and the sixteen come first. One is
## reserved, perspective.
## `sa_kpp_sensors.gd` maps a preset by name rather than by ordinal, so the order
## is not what a `.kpp` depends on, but the Krita mapping table is written in it
## and a Sara sensor sitting among the sixteen would read as one of them.
func test_there_are_twenty_ids_of_which_one_is_reserved() -> void:
    assert_eq(SaSensor.KEYS.size(), 20, "Twenty ids")
    assert_eq(SaSensor.DEFERRED.size(), 1, "one of them reserved")
    assert_eq(SaSensor.KEYS.size() - SaSensor.DEFERRED.size(), 19, "so nineteen answer a real input")
    assert_eq(SaSensor.KEYS[16], "depletion", "and the seventeenth is Sara's own, after the sixteen")
    assert_eq(SaSensor.KEYS[17], "lift_up", "and so is the eighteenth, lift-up")
    assert_eq(SaSensor.KEYS[18], "texture", "and the nineteenth, texture")
    assert_eq(SaSensor.KEYS[19], "fuzzy_along_stroke", "and the twentieth, roll along the stroke")


func test_a_reserved_sensor_answers_its_neutral_value_rather_than_failing() -> void:
    var info := _info()

    assert_almost_eq(_sensor(SaSensor.Id.PERSPECTIVE).value(info), 1.0, 1e-6, "Perspective is 1 with no assistant")
    assert_almost_eq(_sensor(SaSensor.Id.TANGENTIAL).value(info), 0.0, 1e-6, "and the built wheel is 0 with no wheel")


func test_every_id_has_a_stored_key_that_round_trips() -> void:
    for i in range(SaSensor.KEYS.size()):
        var key := SaSensor.key_of(i as SaSensor.Id)
        assert_false(key.is_empty(), "id %d has a key" % i)
        assert_eq(SaSensor.id_of(key), i, "and '%s' names it back" % key)
    assert_eq(SaSensor.id_of("no_such_sensor"), -1, "A key nothing answers to reports as missing rather than as zero")


func test_the_kinds_are_the_ones_the_spec_names() -> void:
    var additive: Array[String] = []
    var absolute: Array[String] = []
    for i in range(SaSensor.KEYS.size()):
        var sensor := SaSensor.create(i as SaSensor.Id)
        if sensor.is_additive():
            additive.append(SaSensor.key_of(i as SaSensor.Id))
        if sensor.is_absolute_rotation():
            absolute.append(SaSensor.key_of(i as SaSensor.Id))

    assert_eq(
        additive,
        ["tilt_direction", "rotation", "fuzzy_per_dab", "fuzzy_per_stroke", "fuzzy_along_stroke"] as Array[String],
        "Five sensors sum rather than multiply"
    )
    assert_eq(absolute, ["drawing_angle"] as Array[String], "and exactly one is an absolute rotation")
