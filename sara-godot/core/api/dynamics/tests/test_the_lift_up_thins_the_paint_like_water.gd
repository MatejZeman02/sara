## The lift-up sensor thins the paint like water.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## An older note asks for "a lift-up parameter" that "desaturates,
## like water", and the answer puts it on whichever engine deposits. The
## sensor is `SaSensor.Id.LIFT_UP` in the door, and the binding a painter makes
## by ticking it is `SaCurveOption.bind_lift_up`. The stroke below lands firm
## and lightens towards its end, and the suite reads the sensor rising while
## the saturation and the opacity fall, through the stamp's settings and the
## noise brush's alike, since both are read by the same `SaDynamics`.
extends "res://tests/test_framework.gd"

const NoiseSettingsScript = preload("res://modules/sara-noise-brush-engine/noise_brush_settings.gd")
const NoiseModuleScript = preload("res://modules/sara-noise-brush-engine/module.gd")

## The pen's pressure along the stroke: it lands at 0.8, presses on to 0.9
## and lets go towards 0.1. Set by hand after `feed` rather than through it,
## because `feed` runs its argument through the tablet's calibration.
const PRESSURES: Array[float] = [0.8, 0.9, 0.9, 0.7, 0.5, 0.3, 0.1]

## A saturated red, so a fall in chroma is large enough to read.
const RED: Color = Color(0.9, 0.1, 0.1, 1.0)


## A stroke walked sample by sample, each handed to *read*, whose answers come
## back in order.
func _stroke(read: Callable) -> Array:
    var info := SaStrokeInfo.new()
    info.begin(Vector2.ZERO, 7)
    var answers: Array = []
    var at := Vector2.ZERO
    for pressure: float in PRESSURES:
        at += Vector2(4.0, 0.0)
        info.feed(at, 0.0, Vector2.ZERO, 0.0, 0.0)
        info.pressure = pressure
        info.max_pressure = maxf(info.max_pressure, pressure)
        info.next_dab()
        answers.append(read.call(info))
    return answers


## The chroma of *color* in Oklab, which is what the colour dynamics move.
func _chroma(color: Color) -> float:
    var lab := _oklab(color)
    return Vector2(lab.y, lab.z).length()


func _oklab(color: Color) -> Vector3:
    var lin := color.srgb_to_linear()
    var l := 0.4122214708 * lin.r + 0.5363325363 * lin.g + 0.0514459929 * lin.b
    var m := 0.2119034982 * lin.r + 0.6806995451 * lin.g + 0.1073969566 * lin.b
    var s := 0.0883024619 * lin.r + 0.2817188376 * lin.g + 0.6299787005 * lin.b
    l = pow(l, 1.0 / 3.0)
    m = pow(m, 1.0 / 3.0)
    s = pow(s, 1.0 / 3.0)
    return Vector3(
        0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
        1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
        0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
    )


## Each sample from *from* on below the one before it, or at the floor of
## nought, where a chroma greyed out entirely has nowhere further to go.
func _falls(values: Array, from: int, label: String) -> void:
    for i in range(from + 1, values.size()):
        var ok := float(values[i]) < float(values[i - 1]) or absf(float(values[i])) < 1e-5
        assert_true(ok, "%s falls at sample %d" % [label, i])


# --- The sensor -------------------------------------------------------------------


func test_the_sensor_sits_after_depletion_and_the_list_shows_it() -> void:
    assert_eq(SaSensor.id_of("lift_up"), int(SaSensor.Id.LIFT_UP), "The key names the id")
    assert_eq(int(SaSensor.Id.LIFT_UP), int(SaSensor.Id.DEPLETION) + 1, "and it comes after depletion")
    assert_true(SaSensorList.LABELS.has("lift_up"), "The sensor list, which both engines' pages use, has a row")
    assert_true(SaSensor.is_available(SaSensor.Id.LIFT_UP), "and the row is not greyed")


func test_it_rises_from_nought_as_the_pen_lightens() -> void:
    var sensor := SaSensor.create(SaSensor.Id.LIFT_UP, true)
    var readings := _stroke(func(info: SaStrokeInfo) -> float: return sensor.value(info))

    assert_almost_eq(float(readings[0]), 0.0, 1e-6, "Nought where the pen lands")
    assert_almost_eq(float(readings[2]), 0.0, 1e-6, "and nought while it presses on")
    _falls(readings.map(func(v: float) -> float: return -v), 2, "The negated reading")
    assert_almost_eq(float(readings[6]), (0.9 - 0.1) / 0.9, 1e-6, "The lift is over the stroke's firmest point")


func test_a_hovering_pen_and_a_pen_that_never_pressed_read_nought() -> void:
    var sensor := SaSensor.create(SaSensor.Id.LIFT_UP, true)
    var info := SaStrokeInfo.new()
    info.begin(Vector2.ZERO, 1)
    assert_almost_eq(sensor.value(info), 0.0, 1e-6, "No pressure yet, nothing to let go of")
    info.max_pressure = 1.0
    info.pressure = 0.2
    info.hovering = true
    assert_almost_eq(sensor.value(info), 0.0, 1e-6, "and a hovering pen has lifted nothing")


# --- The binding ------------------------------------------------------------------


## The clause the suite is for: a stroke lightening towards its end, the sensor
## rising and the saturation falling with it, on both engines' settings.
func test_the_saturation_falls_with_it_on_both_engines() -> void:
    for settings: Resource in [SaStampBrushSettings.new(), NoiseSettingsScript.new()]:
        var option: SaCurveOption = settings.saturation_option
        option.enabled = true
        option.bind_lift_up(true)
        settings.color = RED
        var dynamics := SaDynamics.new()
        dynamics.settings = settings
        dynamics.begin_stroke()
        var chroma := _stroke(
            func(info: SaStrokeInfo) -> float: return _chroma(SaColorDynamics.apply(RED, dynamics.evaluate(info, 20.0)))
        )
        var name := String(settings.get_script().resource_path.get_file())
        assert_almost_eq(float(chroma[0]), _chroma(RED), 1e-4, "%s: the landing is the picked colour" % name)
        _falls(chroma, 2, "%s: the chroma" % name)
        assert_true(float(chroma[6]) < 0.5 * _chroma(RED), "%s: and the lifted end is greyed" % name)


func test_the_opacity_thins_with_it_and_pressure_keeps_its_curve() -> void:
    var settings := SaStampBrushSettings.new()
    var option: SaCurveOption = settings.opacity_option
    var shared := option.common_curve.duplicate()
    option.bind_lift_up(false)

    assert_false(option.use_same_curve, "The binding stops sharing one curve")
    var pressure := option.sensor_for(SaSensor.Id.PRESSURE)
    assert_eq(pressure.curve, shared, "and pressure is handed the curve it was read through")
    assert_eq(option.sensor_for(SaSensor.Id.LIFT_UP).curve, SaSensor.LIFT_UP_THINS, "while lift-up falls")

    var dynamics := SaDynamics.new()
    dynamics.settings = settings
    dynamics.begin_stroke()
    var alone := SaCurveOption.new()
    alone.bind_lift_up(false)
    alone.begin_stroke()
    var thinned := _stroke(func(info: SaStrokeInfo) -> float: return alone.size_like(info))
    assert_almost_eq(float(thinned[0]), 1.0, 1e-4, "A lift-up alone leaves the landing whole")
    _falls(thinned, 2, "and the opacity")


func test_ticking_it_on_a_page_binds_it_the_right_way_round() -> void:
    var specs: Dictionary = {}
    for spec: SaOptionSpec in NoiseModuleScript.options():
        specs[spec.key] = spec
    assert_true(specs.has(&"saturation_option"), "The noise brush's page offers Saturation")
    assert_true(specs.has(&"opacity_option"), "and Opacity")

    var settings := NoiseSettingsScript.new()
    for key: StringName in [&"saturation_option", &"opacity_option"]:
        var spec: SaOptionSpec = specs[key]
        var control: SaCurveOptionControl = spec.build_control.call(spec, Callable())
        spec.bind_value.call(control, settings.get(key))
        assert_true(control.set_sensor_active("lift_up", true), "%s: the tick is taken" % key)
        var lift: SaSensor = (settings.get(key) as SaCurveOption).sensor_for(SaSensor.Id.LIFT_UP)
        var expected := SaSensor.LIFT_UP_GREYS if key == &"saturation_option" else SaSensor.LIFT_UP_THINS
        assert_true(lift != null and lift.active, "%s: lift-up is on" % key)
        assert_eq(lift.curve, expected, "%s: on the curve its reducer reads as falling" % key)
        control.free()
