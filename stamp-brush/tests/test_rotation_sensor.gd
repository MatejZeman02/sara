## The Rotation sensor, which is read and has nothing feeding it.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A sensor a painter can tick and watch do nothing is worse
## than one they can see is unavailable. What is here is the flag, the row, and
## the two doors that have to refuse it. The screen is
## `scenarios/rotation-sensor-greyed.json`. Tangential pressure is greyed
## the same way wherever no pen source reads an airbrush's wheel, which is
## every suite, and its own suite is
## `core/api/dynamics/tests/test_tangential_pressure_reads_the_airbrush_wheel.gd`.
##
## In the module's own suite, with the list and the control it drives.
extends "res://tests/test_framework.gd"


func test_the_rotation_sensor_is_declared_unavailable_and_the_rest_are_not() -> void:
    assert_false(SaSensor.is_available(SaSensor.Id.ROTATION), "Rotation has no input behind it")
    assert_true(SaSensor.unavailable_reason(SaSensor.Id.ROTATION).to_lower().contains("barrel rotation"), "and says so")
    for key: String in ["pressure", "tilt_x", "tilt_direction", "speed", "drawing_angle", "distance", "fuzzy_per_dab"]:
        assert_true(SaSensor.is_available(SaSensor.id_of(key) as SaSensor.Id), "%s is available" % key)


## Unavailable is not deferred, and the difference is what a preset does. A
## deferred sensor has no `parameter` branch and never appears in the editor.
## This one is built and read, so a file that names it round-trips and means what
## it says the day the input arrives.
func test_an_unavailable_sensor_is_still_built_and_still_reads() -> void:
    assert_false(SaSensor.DEFERRED.has(SaSensor.Id.ROTATION), "Rotation is not one of the reserved ids")
    var sensor := SaSensor.create(SaSensor.Id.ROTATION, true)
    var info := SaStrokeInfo.new()
    info.begin(Vector2.ZERO, 1)

    assert_eq(sensor.value(info), 0.0, "and it answers the honest zero for an input that never arrives")
    assert_true(sensor.is_additive(), "with the kind the spec's table gives it, so a stored preset still means it")


func test_the_list_greys_the_row_and_puts_the_reason_on_it() -> void:
    var list := SaSensorList.new()

    var rows := list.report()
    var rotation := {}
    for row: Dictionary in rows:
        if String(row["key"]) == "rotation":
            rotation = row

    assert_false(rotation.is_empty(), "Rotation keeps its row rather than vanishing")
    assert_true(bool(rotation["disabled"]), "disabled")
    assert_true(bool(rotation["dimmed"]), "and dimmed, which here is the same word")
    assert_true(String(rotation["tooltip"]).to_lower().contains("barrel rotation"), "with the reason on it")
    list.free()


func test_every_other_row_is_live() -> void:
    var list := SaSensorList.new()

    for row: Dictionary in list.report():
        if String(row["key"]) in ["rotation", "tangential"]:
            continue
        assert_false(bool(row["disabled"]), "%s can be ticked" % row["key"])
        assert_false(bool(row["dimmed"]), "%s is drawn at full strength" % row["key"])
    list.free()


## The row is disabled, so a hand cannot reach it, and a scenario and the capture
## step do not come through a hand. This is the door they use.
func test_the_control_refuses_to_tick_the_unavailable_sensor() -> void:
    var control := SaCurveOptionControl.new()
    var option := SaCurveOption.new()
    control.bind_option(option, "Rotation")

    var took := control.set_sensor_active("rotation", true)

    assert_false(took, "the request is refused")
    assert_null(option.sensor_for(SaSensor.Id.ROTATION), "and no sensor was written onto the option")
    assert_true(control.set_sensor_active("tilt_direction", true), "while an available one still ticks")
    control.free()


## The two deferred ids stay out of the list entirely, which is the other half of
## the same statement: reserved is not the same as unavailable.
func test_the_deferred_two_are_not_in_the_list_at_all() -> void:
    for deferred: SaSensor.Id in SaSensor.DEFERRED:
        assert_false(SaSensorList.LABELS.has(SaSensor.key_of(deferred)), "%s has no row" % SaSensor.key_of(deferred))
    assert_eq(SaSensorList.LABELS.size(), SaSensor.KEYS.size() - SaSensor.DEFERRED.size(), "and everything else does")
