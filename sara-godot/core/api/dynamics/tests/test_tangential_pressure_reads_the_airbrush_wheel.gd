## Tangential pressure reads the airbrush's finger wheel.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The maintainers' ruling of 2026-10-07: "The wheel drives a curve option like any
## other sensor." The Linux pen module reads the wheel off the kernel's node
## and its source answers it through `SaContext.pens`. The stroke takes
## that source at its press and the sensor reads the wheel at every dab, and
## where no source reads a wheel the sensor answers nought and its row is
## greyed with a sentence. The suite hands the stroke a source of its own, so
## it needs neither the module nor a tablet. The stroke on the desktop is
## `scenarios/tangential-pressure-drives-a-curve-option-from-the-airbrush-wheel.json`.
extends "res://tests/test_framework.gd"


## A pen source whose wheel is wherever the suite turns it.
class Wheel:
    extends SaPenSource

    var at: float = 0.0
    var turns: bool = true

    func wheel() -> float:
        return at if turns else 0.0

    func reads() -> bool:
        return true

    func reads_wheel() -> bool:
        return turns


func _wheel(at: float, turns: bool = true) -> Wheel:
    var source := Wheel.new()
    source.at = at
    source.turns = turns
    return source


## A stroke begun and handed *source* as the pen it reads, which is what
## `begin` takes from the registry in the app.
func _stroke(source: SaPenSource) -> SaStrokeInfo:
    var info := SaStrokeInfo.new()
    info.begin(Vector2.ZERO, 1)
    info.pen = source
    info.feed_dab(Vector2(10.0, 0.0), 0.5, Vector2.ZERO, 0.0, 10.0)
    return info


func test_the_sensor_follows_the_wheel_from_a_fifth_to_nine_tenths() -> void:
    var source := _wheel(0.2)
    var info := _stroke(source)
    var sensor := SaSensor.create(SaSensor.Id.TANGENTIAL, true)

    assert_almost_eq(sensor.value(info), 0.2, 1e-6, "The wheel at a fifth reads a fifth")
    assert_almost_eq(sensor.parameter(info), 0.2, 1e-6, "and through the identity curve as well")
    source.at = 0.9
    assert_almost_eq(sensor.value(info), 0.9, 1e-6, "turned to nine tenths mid-stroke, the next dab reads it")
    assert_almost_eq(sensor.parameter(info), 0.9, 1e-6, "with no press between")


func test_the_curve_is_drawn_over_the_wheel_as_over_pressure() -> void:
    var source := _wheel(0.5)
    var info := _stroke(source)
    var sensor := SaSensor.create(SaSensor.Id.TANGENTIAL, true)
    sensor.curve = PackedVector2Array([Vector2(0.0, 1.0), Vector2(1.0, 0.0)])

    assert_false(sensor.is_additive(), "A plain sensor, 0 to 1 and multiplying, as the spec's table has it")
    assert_almost_eq(sensor.parameter(info), 0.5, 0.01, "An inverted curve at a half answers a half")
    source.at = 0.2
    assert_almost_eq(sensor.parameter(info), 0.8, 0.01, "and at a fifth four fifths")


func test_a_size_bound_to_the_wheel_grows_as_it_turns() -> void:
    var source := _wheel(0.2)
    var info := _stroke(source)
    var option := SaCurveOption.new()
    option.set_sensor(SaSensor.create(SaSensor.Id.TANGENTIAL, true))
    option.begin_stroke()

    var low := option.size_like(info)
    source.at = 0.9
    var high := option.size_like(info)

    assert_almost_eq(low, 0.2, 1e-6, "Size bound to the wheel alone is a fifth of itself at a fifth")
    assert_almost_eq(high, 0.9, 1e-6, "and nine tenths once the wheel is turned there")


## A Krita airbrush preset names the wheel `tangentialpressure`, and the
## importer has carried it onto this sensor since it was reserved. Built, the
## imported option follows the wheel, which is what the preset says.
func test_a_krita_preset_naming_tangential_pressure_follows_the_wheel() -> void:
    var option := SaCurveOption.new()
    # A preset's params as the importer reads them, each a value under its name.
    var options := {
        "PressureSize": {"value": "true"},
        "SizeUseCurve": {"value": "true"},
        "SizeSensor": {"value": '<params id="sensorslist"><sensor id="tangentialpressure"/></params>'},
    }
    SaKppSensors.apply(option, options, "Size", {})
    var source := _wheel(0.25)
    var info := _stroke(source)
    option.begin_stroke()

    var carried := option.active_sensors()
    assert_eq(carried.size(), 1, "The preset's one sensor is carried")
    assert_true(not carried.is_empty() and carried[0].id == SaSensor.Id.TANGENTIAL, "and it is tangential pressure")
    assert_almost_eq(option.size_like(info), 0.25, 1e-6, "which reads the wheel")
    source.at = 0.75
    assert_almost_eq(option.size_like(info), 0.75, 1e-6, "as it turns")


func test_with_no_source_it_reads_nought_and_is_unavailable_with_its_sentence() -> void:
    var info := _stroke(null)
    var sensor := SaSensor.create(SaSensor.Id.TANGENTIAL, true)

    assert_eq(sensor.value(info), 0.0, "No source, so the wheel's resting value")
    assert_null(SaPenSource.registered(), "A suite has no main scene, so nothing is registered")
    assert_false(SaSensor.is_available(SaSensor.Id.TANGENTIAL), "and the sensor is unavailable")
    var why := SaSensor.unavailable_reason(SaSensor.Id.TANGENTIAL)
    assert_true(why.contains("Linux pen module"), "Its sentence names the Linux pen module: %s" % why)
    assert_true(why.contains("airbrush"), "and the airbrush")


func test_a_source_that_reads_no_wheel_leaves_it_unavailable() -> void:
    var source := _wheel(0.7, false)
    var info := _stroke(source)
    var sensor := SaSensor.create(SaSensor.Id.TANGENTIAL, true)

    assert_eq(sensor.value(info), 0.0, "A pen whose node declares no wheel reads nought")
    assert_false(SaSensor.is_available(SaSensor.Id.TANGENTIAL, source), "and is unavailable")
    assert_false(SaSensor.unavailable_reason(SaSensor.Id.TANGENTIAL, source).is_empty(), "with its sentence")


func test_a_source_that_reads_the_wheel_makes_it_available() -> void:
    var source := _wheel(0.3)

    assert_true(SaSensor.is_available(SaSensor.Id.TANGENTIAL, source), "Available while the source reads a wheel")
    assert_eq(SaSensor.unavailable_reason(SaSensor.Id.TANGENTIAL, source), "", "and nothing to say why not")
    assert_false(SaSensor.is_available(SaSensor.Id.ROTATION, source), "while rotation's input still never arrives")


## It left the reserved ids, so it has a row a painter sees, and a fresh
## stroke info, the brush at rest an outline reads, answers the resting value.
func test_it_is_no_longer_reserved_and_the_list_has_its_row() -> void:
    assert_false(SaSensor.DEFERRED.has(SaSensor.Id.TANGENTIAL), "Tangential pressure is not reserved")
    assert_true(SaSensorList.LABELS.has("tangential"), "and the sensor list has its row")
    assert_eq(SaSensor.key_of(SaSensor.Id.TANGENTIAL), "tangential", "under the key a preset already stores")
    var sensor := SaSensor.create(SaSensor.Id.TANGENTIAL, true)
    assert_eq(sensor.value(SaStrokeInfo.new()), 0.0, "A sample no press began reads nought")


func test_the_list_greys_the_row_with_its_sentence_when_no_wheel_is_read() -> void:
    var list := SaSensorList.new()
    var row := {}
    for each: Dictionary in list.report():
        if String(each["key"]) == "tangential":
            row = each

    assert_false(row.is_empty(), "The row is there")
    assert_eq(String(row["label"]), "Tangential pressure", "named as Krita names it")
    assert_true(bool(row["disabled"]), "disabled")
    assert_true(bool(row["dimmed"]), "and dimmed")
    assert_true(String(row["tooltip"]).contains("Linux pen module"), "with the sentence on it")
    list.free()


func test_the_stroke_takes_the_registered_source_at_its_press() -> void:
    var info := SaStrokeInfo.new()
    info.pen = _wheel(0.4)
    info.begin(Vector2.ZERO, 1)

    assert_null(info.pen, "A press takes what the registry holds, nothing in a suite")
    assert_eq(info.wheel(), 0.0, "so the wheel reads nought")
