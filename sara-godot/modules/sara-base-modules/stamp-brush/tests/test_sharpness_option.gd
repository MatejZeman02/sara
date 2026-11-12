## Sharpness as a curve option: the value per dab, the option that is off, and
## the Krita preset that keeps its sensor.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Sharpness is a curve option rather than two floats read once per dispatch, so a
## brush is not a pen or not for the whole of a stroke. The phrase "not carried"
## for a sensor on `PressureSharpness` is gone.
##
## **The evaluator is driven rather than the tool**, the way `test_dynamics.gd`
## drives it: what a dab reads is the seam, and a stroke over a canvas would
## prove the kernel as well and fail for the kernel's reasons. The stroke is the
## scenario `sharpness-follows-a-sensor`, which is where the soft end and the
## hard end of one drag are looked at.
extends "res://tests/test_framework.gd"

const ImportScript = preload("res://modules/sara-base-modules/stamp-brush/krita/sa_kpp_import.gd")

## The Sharpness row the option modulates, chosen away from 1 so that a bug
## multiplying by the wrong thing cannot answer the right number by accident.
const ROW: float = 0.8

## The four samples the unit's Done-when asks the dab to be read at.
const SAMPLES: Array[float] = [0.0, 1.0 / 3.0, 2.0 / 3.0, 1.0]

## A pressure the sensor path and the plain path both have to agree on.
const ONE_LEVEL: float = 1.0 / 255.0


func _settings() -> SaStampBrushSettings:
    var settings := SaStampBrushSettings.new()
    settings.sharpness = ROW
    return settings


func _sample(pressure: float) -> SaStrokeInfo:
    var info := SaStrokeInfo.new()
    info.begin(Vector2.ZERO, 4242)
    info.hovering = false
    info.position = Vector2.ZERO
    info.pressure = pressure
    return info


## The option on, one pressure sensor, the identity curve it is born with.
func _on_pressure(settings: SaStampBrushSettings) -> SaCurveOption:
    var option := settings.sharpness_option
    option.enabled = true
    option.set_sensor(SaSensor.create(SaSensor.Id.PRESSURE, true))
    return option


# --- The dab's own sharpness --------------------------------------------------


## Four samples, which is the Done-when's own list. A light touch takes none of
## the row and a full one takes all of it, so one drag is a soft edge that
## becomes a hard one without the painter moving a slider.
func test_the_dab_reads_the_row_through_the_sensor_at_four_samples() -> void:
    var settings := _settings()
    _on_pressure(settings)
    var dynamics := SaDynamics.new(settings)

    for pressure: float in SAMPLES:
        var dab := dynamics.evaluate(_sample(pressure), 40.0)
        assert_almost_eq(dab.sharpness, ROW * pressure, ONE_LEVEL, "at pressure %f the dab takes that much of the row" % pressure)


## The claim to be able to make: nothing a painter already owns
## paints differently. An option nobody switched on multiplies by the neutral 1
## `_size_like` answers, so the row goes through whole at every pressure.
func test_an_option_that_is_off_sends_the_row_through_unchanged() -> void:
    var settings := _settings()
    var dynamics := SaDynamics.new(settings)

    for pressure: float in SAMPLES:
        var dab := dynamics.evaluate(_sample(pressure), 40.0)
        assert_almost_eq(dab.sharpness, ROW, 1e-6, "the row itself at pressure %f" % pressure)


## A row of nought is a brush with no sharpness at all, and an option on top of
## it cannot invent any: the option is how much of the row a dab takes.
func test_a_row_of_nothing_stays_nothing_however_the_option_is_set() -> void:
    var settings := _settings()
    settings.sharpness = 0.0
    _on_pressure(settings)
    var dynamics := SaDynamics.new(settings)

    assert_almost_eq(dynamics.evaluate(_sample(1.0), 40.0).sharpness, 0.0, 1e-6, "full pressure over a row of nought is nought")


## A fresh dab paints nothing, which is `SaDabParams`' own rule, and for
## sharpness the value that does nothing is nought: no snap of the centre and no
## cut of the mask.
func test_a_fresh_dab_carries_no_sharpness() -> void:
    assert_almost_eq(SaDabParams.new().sharpness, 0.0, 1e-6, "the neutral value is the default")
    assert_true(SaDabParams.new().report().has("sharpness"), "and a state dump can see it")


# --- The Krita preset ---------------------------------------------------------


## The options dictionary `SaKppReader` hands the importer, in the shape
## `_text` reads: one entry per param, each a dictionary with a `value`.
func _preset(params: Dictionary) -> Dictionary:
    var options: Dictionary = {}
    for name: String in params:
        options[name] = {"value": String(params[name])}
    return {"options": options}


## `PressureSharpness` on with a sensor under it carries the sensor and writes
## no "sharpness by sensor" tag into the import report.
func test_an_imported_preset_carries_the_sensor_and_leaves_no_tag() -> void:
    var settings := SaStampBrushSettings.new()
    var result := (
        ImportScript
        . apply(
            _preset(
                {
                    "PressureSharpness": "true",
                    "SharpnessValue": "0.5",
                    "SharpnessUseCurve": "true",
                    "SharpnessSensor": '<!DOCTYPE params>\n<params id="pressure"/>\n',
                    "SharpnesscommonCurve": "0,0;1,1;",
                    "Sharpness/softness": "40",
                }
            ),
            settings
        )
    )

    assert_eq(result["not_carried"], [], "nothing about sharpness is left uncarried")
    assert_eq(result["unread"], [], "and every param the preset spelled was read")
    assert_almost_eq(settings.sharpness, 0.5, 1e-6, "the value is on the row")
    assert_almost_eq(settings.sharpness_softness, 0.4, 1e-6, "the softness is the file's over a hundred")
    assert_true(settings.sharpness_option.enabled, "the option is on")
    assert_true(settings.sharpness_option.sensor_for(SaSensor.Id.PRESSURE) != null, "with the preset's own sensor on it")


## Krita's one number split across two homes, which is the reason the stem is
## not in `SaKppSensors.OPTION_STEMS` with the other ten. `SharpnessValue` is
## the ceiling and it lands on the row, so leaving it on the option's strength
## as well would square it and a preset at 0.5 would paint at 0.25.
func test_the_imported_option_takes_all_of_the_row_rather_than_squaring_it() -> void:
    var settings := SaStampBrushSettings.new()
    (
        ImportScript
        . apply(
            _preset(
                {
                    "PressureSharpness": "true",
                    "SharpnessValue": "0.5",
                    "SharpnessSensor": '<!DOCTYPE params>\n<params id="pressure"/>\n',
                }
            ),
            settings
        )
    )

    assert_almost_eq(settings.sharpness_option.strength, 1.0, 1e-6, "the option's strength is one")
    var dab := SaDynamics.new(settings).evaluate(_sample(1.0), 40.0)
    assert_almost_eq(dab.sharpness, 0.5, ONE_LEVEL, "so a full press paints the preset's own 0.5 and not 0.25")


## A preset whose Sharpness checkbox is off has no sharpness at all, which is
## what the row said before this unit and still says: the option arrives off
## with it, so the fresh brush's own nought goes through.
func test_a_preset_with_the_option_off_imports_no_sharpness() -> void:
    var settings := SaStampBrushSettings.new()
    ImportScript.apply(_preset({"PressureSharpness": "false", "SharpnessValue": "0.9"}), settings)

    assert_almost_eq(settings.sharpness, 0.0, 1e-6, "the row is nought")
    assert_false(settings.sharpness_option.enabled, "and the option is off with it")
