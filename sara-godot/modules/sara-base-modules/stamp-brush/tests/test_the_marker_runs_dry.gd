## The marker that runs dry: the depletion sensor, its reservoir and its
## refill.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A marker runs dry along the stroke, through a depletion sensor on the opacity
## and flow curves. What a dab costs the pen is measured rather than declared:
## the stroke never sees a dab's width, but the walk steps by it, so the step
## the sample just took is the dab's own size up to the spacing fraction the
## painter set.
##
## Its own file rather than more of `test_sensors.gd`, which is a table of the
## spec's sensor values read one by one. A reservoir spent by a walk is a
## different shape of test.
extends "res://tests/test_framework.gd"


## A sample with nothing in it: at the origin, no pressure, no tilt, painting.
func _info() -> SaStrokeInfo:
    var info := SaStrokeInfo.new()
    info.begin(Vector2.ZERO, 12345)
    return info


func _sensor(id: SaSensor.Id) -> SaSensor:
    return SaSensor.create(id, true)


# --- Where the id sits ------------------------------------------------------------


func test_the_sixteen_krita_ids_are_still_where_the_import_expects_them() -> void:
    var krita: Array[String] = []
    for key: String in SaKppSensors.SENSOR_IDS.values():
        krita.append(key)

    assert_eq(krita.size(), 16, "Krita names sixteen sensors")
    for i in range(16):
        assert_eq(SaSensor.KEYS[i], krita[i], "and Sara's id %d is still the one it maps onto" % i)
    assert_eq(SaSensor.id_of("depletion"), 16, "while depletion is past the end of that table")
    assert_false(SaKppSensors.SENSOR_IDS.values().has("depletion"), "and no Krita name reaches it")


# --- The reservoir ----------------------------------------------------------------


## Walks a fixed sequence of samples and reads the sensor after each, which is
## the shape of a stroke rather than a table of totals set by hand: the point of
## the sensor is that the walk spends the pen, so the walk is what the test does.
##
## The pressure is written on after `feed` rather than handed to it, because
## `feed` puts its argument through `SaTablet.normalize` and the numbers below
## are worked out by hand from a pressure, not from a calibration. The positions
## still go through `feed`, which is the part being tested.
func _walk(info: SaStrokeInfo, steps: Array, pressure: float) -> Array[float]:
    var readings: Array[float] = []
    var sensor := _sensor(SaSensor.Id.DEPLETION)
    sensor.length = 100
    var at := Vector2.ZERO
    for step: float in steps:
        at += Vector2(step, 0.0)
        info.feed(at, 0.0, Vector2.ZERO, 0.0, 0.0)
        info.pressure = pressure
        info.next_dab()
        readings.append(sensor.value(info))
    return readings


func test_the_reservoir_starts_full_and_only_falls() -> void:
    var info := _info()

    var readings := _walk(info, [0.0, 5.0, 5.0, 5.0, 5.0, 5.0], 1.0)

    assert_almost_eq(readings[0], 1.0, 1e-6, "A dab that has not moved yet has spent nothing")
    for i in range(1, readings.size()):
        assert_true(readings[i] < readings[i - 1], "and reading %d is lower than the one before it" % i)
    assert_almost_eq(readings[5], 0.75, 1e-6, "25 pressure-pixels of a hundred leaves three quarters")


## The clause the note turns on: "a wide dab at full pressure empties the pen
## faster than a hairline does". The stroke never sees a dab's width, but the
## walk steps by it, because `SaStrokeDistance.effective_spacing` is the tip's
## own size times the spacing fraction. So a wide tip is a long step here.
func test_a_wider_dab_spends_more_of_it_than_a_hairline() -> void:
    var wide := _walk(_info(), [0.0, 20.0], 1.0)
    var hairline := _walk(_info(), [0.0, 2.0], 1.0)

    assert_almost_eq(wide[1], 0.8, 1e-6, "A 20 pixel step at full pressure spends a fifth of a hundred")
    assert_almost_eq(hairline[1], 0.98, 1e-6, "and a 2 pixel step spends a fiftieth")
    assert_true(wide[1] < hairline[1], "so the wide tip is the drier of the two")


func test_a_lighter_hand_spends_less_over_the_same_distance() -> void:
    var heavy := _walk(_info(), [0.0, 10.0, 10.0], 1.0)
    var light := _walk(_info(), [0.0, 10.0, 10.0], 0.25)

    assert_almost_eq(heavy[2], 0.8, 1e-6, "Twenty pixels at full pressure spends twenty")
    assert_almost_eq(light[2], 0.95, 1e-6, "and the same twenty at a quarter pressure spends five")


func test_lifting_the_pen_fills_it_again() -> void:
    var info := _info()
    _walk(info, [0.0, 40.0, 40.0], 1.0)
    var sensor := _sensor(SaSensor.Id.DEPLETION)
    sensor.length = 100

    assert_almost_eq(sensor.value(info), 0.2, 1e-6, "Eighty of a hundred leaves a fifth")

    info.begin(Vector2(500.0, 500.0), 999)

    assert_almost_eq(sensor.value(info), 1.0, 1e-6, "and the next press is a full pen again")


func test_it_runs_dry_rather_than_going_negative() -> void:
    var info := _info()

    var readings := _walk(info, [0.0, 90.0, 90.0], 1.0)

    assert_almost_eq(readings[2], 0.0, 1e-6, "A pen spent past its capacity is empty")
    assert_true(readings[2] >= 0.0, "and not less than empty")


func test_a_hover_spends_nothing_and_reads_full() -> void:
    var info := _info()
    _walk(info, [0.0, 50.0], 1.0)
    var spent := info.total_ink
    var sensor := _sensor(SaSensor.Id.DEPLETION)
    sensor.length = 100

    info.hovering = true

    assert_almost_eq(sensor.value(info), 1.0, 1e-6, "A pen held over the canvas reads full, like the three sweeps")

    info.feed(Vector2(400.0, 0.0), 0.0, Vector2.ZERO, 0.0, 0.0)

    assert_almost_eq(info.total_ink, spent, 1e-6, "and carrying it across the canvas spends none of it")


## Periodic is the field the three Krita sweeps carry and depletion borrows, so
## the default matters: a marker that refills itself halfway along a stroke is a
## rhythm rather than a marker.
func test_it_does_not_refill_itself_unless_the_painter_asks() -> void:
    var sensor := SaSensor.create(SaSensor.Id.DEPLETION)

    assert_eq(sensor.length, 1000, "A fresh pen holds a thousand pressure-pixels")
    assert_false(sensor.periodic, "and does not sweep again on its own")
    assert_true(SaSensor.create(SaSensor.Id.DISTANCE).periodic, "while distance still does, which is what a .kpp means")

    var info := _info()
    sensor.length = 100
    sensor.periodic = true
    var at := Vector2.ZERO
    for step: float in [0.0, 60.0, 60.0]:
        at += Vector2(float(step), 0.0)
        info.feed(at, 0.0, Vector2.ZERO, 0.0, 0.0)
        info.pressure = 1.0
        info.next_dab()

    assert_almost_eq(sensor.value(info), 0.8, 1e-6, "and a painter who ticks it gets 120 wrapped back to 20 spent")
