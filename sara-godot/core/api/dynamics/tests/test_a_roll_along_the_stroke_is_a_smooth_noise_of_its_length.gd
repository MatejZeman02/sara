## A roll along the stroke is a smooth noise of how far the stroke has come
##
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The door's half of design 5 of the noise brush's rework: "A random row draws
## a smooth noise in the along coordinate, so a stroke changes slowly as it
## goes." The sensor is `SaSensor.Id.FUZZY_ALONG_STROKE`, read off a sample
## walked along a straight line a pixel at a time, and the binding a randomise
## control makes on it is `SaCurveOption.bind_random` with that clock.
extends "res://tests/test_framework.gd"

## The tip's diameter the samples carry, in pixels, and how far the line runs,
## in features of [constant SaSensor.ALONG_SPACING] diameters.
const DIAMETER := 8.0
const FEATURES := 30


## The sensor's reading at every pixel of a straight stroke of *features*
## features, drawn with *seed_value* and named *key*.
func _walk(seed_value: int, key: String = "hardness", diameter: float = DIAMETER, features: int = FEATURES) -> Array[float]:
    var sensor := SaSensor.create(SaSensor.Id.FUZZY_ALONG_STROKE, true)
    sensor.resource_name = key
    var info := SaStrokeInfo.new()
    info.begin(Vector2.ZERO, seed_value)
    info.tip_diameter = diameter
    var readings: Array[float] = []
    var length := int(features * SaSensor.ALONG_SPACING * diameter)
    for x in range(1, length + 1):
        info.feed(Vector2(float(x), 0.0), 1.0, Vector2.ZERO, 0.0, float(x))
        info.next_dab()
        readings.append(sensor.value(info))
    return readings


## The reading stays in the additive range, crosses at least half of it over
## thirty features, and moves by a tenth at most over a quarter diameter, a
## twentieth of its width of two and so of a roll's range once a curve maps the
## two ends onto it.
func test_the_reading_is_smooth_and_wanders_across_its_range() -> void:
    for seed_value: int in [3, 11, 4242]:
        var readings := _walk(seed_value)
        var label := "Seed %d" % seed_value
        assert_true(readings.min() >= -1.0 and readings.max() <= 1.0, "%s reads inside -1 to 1" % label)
        assert_true(
            readings.max() - readings.min() >= 1.0,
            "%s crosses half the range or more, %.3f to %.3f" % [label, readings.min(), readings.max()]
        )
        var quarter := int(DIAMETER / 4.0)
        var worst := 0.0
        for index in range(quarter, readings.size()):
            worst = maxf(worst, absf(readings[index] - readings[index - quarter]))
        assert_true(worst <= 0.1, "%s moves %.4f at most over a quarter diameter, a twentieth of a roll" % [label, worst])


## The bound in the sensor's own header, read off the noise itself: over every
## sixteenth of a unit, the farthest neighbours drawn at both ends of the range
## move it by less than three thirty-seconds.
func test_the_noise_never_moves_faster_than_its_bound() -> void:
    var worst := 0.0
    for seed_value in range(1, 40):
        var last := SaSensor.along_noise(0.0, seed_value)
        for step in range(1, 16 * 20):
            var here := SaSensor.along_noise(float(step) / 16.0, seed_value)
            worst = maxf(worst, absf(here - last))
            last = here
    assert_true(worst <= 1.5 / 16.0 + 0.0001, "The noise moves %.4f at most a sixteenth" % worst)


## Measured in tip diameters: a brush twice as wide rolls the same numbers over
## twice the length, so a stroke changes over a few widths of itself.
func test_the_roll_is_measured_in_tip_diameters() -> void:
    var narrow := _walk(7, "size", DIAMETER, 4)
    var wide := _walk(7, "size", 2.0 * DIAMETER, 4)
    for index in range(0, narrow.size(), 5):
        var label := "pixel %d of the narrow stroke reads as pixel %d of the wide" % [index + 1, 2 * index + 2]
        assert_almost_eq(wide[2 * index + 1], narrow[index], 0.0001, label)


## Seeded by the stroke and by the option: the same seed rolls the same way,
## another seed another, and two options of one stroke apart.
func test_the_seed_is_the_strokes_and_the_options() -> void:
    var first := _walk(11)
    assert_eq(_walk(11), first, "One seed rolls one way")
    assert_true(_walk(12) != first, "another seed another")
    assert_true(_walk(11, "opacity") != first, "and another option of the same stroke its own")


## Nothing while hovering, as the other rolls, and a stroke whose engine wrote
## no tip diameter reads as one of [constant SaSensor.ALONG_FALLBACK_DIAMETER].
func test_hovering_reads_nought_and_an_unwritten_diameter_falls_back() -> void:
    var sensor := SaSensor.create(SaSensor.Id.FUZZY_ALONG_STROKE, true)
    var info := SaStrokeInfo.new()
    info.begin(Vector2.ZERO, 5)
    info.feed(Vector2(70.0, 0.0), 1.0, Vector2.ZERO, 0.0, 1.0)
    var unwritten := sensor.value(info)
    info.tip_diameter = SaSensor.ALONG_FALLBACK_DIAMETER
    assert_almost_eq(unwritten, sensor.value(info), 0.000001, "No diameter reads as the fallback's")
    info.hovering = true
    assert_almost_eq(sensor.value(info), 0.0, 0.000001, "and a hovering pen reads nought")
    info.begin(Vector2.ZERO, 5)
    assert_almost_eq(info.tip_diameter, 0.0, 0.000001, "A press forgets the last stroke's diameter")


## It sums as the other rolls do, is stored after the texture so no stored
## ordinal moves, and both engines' sensor list shows it.
func test_it_is_an_additive_sensor_after_the_texture() -> void:
    assert_true(SaSensor.create(SaSensor.Id.FUZZY_ALONG_STROKE).is_additive(), "It sums rather than multiplies")
    assert_eq(int(SaSensor.Id.FUZZY_ALONG_STROKE), int(SaSensor.Id.TEXTURE) + 1, "It comes after the texture")
    assert_eq(SaSensor.key_of(SaSensor.Id.FUZZY_ALONG_STROKE), "fuzzy_along_stroke", "under its own key")
    assert_eq(SaSensorList.LABELS.get("fuzzy_along_stroke", ""), "Fuzzy along the stroke", "with a row in the sensor list")


## The randomise binding takes a clock: each of the three binds its own sensor
## and drops the others, a clock that is not a roll binds nothing, and an
## option rolling on none reads as along the stroke.
func test_the_binding_takes_a_clock() -> void:
    var option := SaCurveOption.new()
    assert_eq(option.random_clock(), SaSensor.Id.FUZZY_ALONG_STROKE, "An option rolling on no clock reads as along the stroke")
    for clock: SaSensor.Id in SaCurveOption.RANDOM_CLOCKS:
        option.bind_random(0.5, clock, "size")
        assert_eq(option.random_clock(), clock, "%s binds its own sensor" % SaSensor.key_of(clock))
        assert_eq(option.active_sensors().size(), 1, "and drops the others")
        assert_almost_eq(option.random_amount(), 0.5, 0.0001, "at the amount asked")
    option.bind_random(0.5, SaSensor.Id.PRESSURE, "size")
    assert_true(option.sensors.is_empty(), "A clock that is not a roll binds nothing and drops the roll there was")
