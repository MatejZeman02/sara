## A noise preset loaded again keeps its Chroma variation.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The row is a binding written at the press, and the settings remembered the
## row's number it last bound. A preset loaded again over the brush puts copies
## of its own Hue and Saturation options in place, which carry no binding, and
## leaves the row at the number already bound, so the press found nothing moved
## and Living Colour painted its variation on the first load alone. The brush
## atlas paints every cell from a fresh load, and only its first cell of Living
## Colour, at 6 px, came out red. Here the shelf is installed into a scratch
## store, Living Colour is applied onto one settings object the way the bar
## applies it, and the press's binding is read after each load.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
const NoiseBrushSettingsScript = preload("res://modules/sara-noise-brush-engine/noise_brush_settings.gd")
const NoisePresetsScript = preload("res://modules/sara-noise-brush-engine/presets/noise_presets.gd")

## The shelf's preset whose row is on.
const LIVING_COLOUR: String = "Living Colour"

## A shelf preset whose row is at nought.
const PLAIN: String = "Grain Round"

## Never the profile's own folder, for `test_brush_presets.gd`'s reason.
static var scratch_dir: String = SaDataRoot.path("test_r3_chroma_reload")

var _store: SaPresetStore = null


func before_each() -> void:
    ScratchFolder.clear(scratch_dir)
    _store = SaPresetStore.new()
    _store.dir = scratch_dir
    _store.install_shipped(NoiseBrushSettingsScript.new(), NoisePresetsScript)


func after_each() -> void:
    _store = null
    ScratchFolder.clear(scratch_dir)


func test_the_second_load_binds_hue_and_saturation_as_the_first_did() -> void:
    var settings := NoiseBrushSettingsScript.new()
    assert_true(_store.apply_preset(LIVING_COLOUR, settings), "Living Colour loads")
    assert_true(settings.chroma_variation > 0.0, "with its row on")
    settings.bind_chroma()
    _assert_bound(settings, "after the first load")
    for load_count in range(2, 5):
        assert_true(_store.apply_preset(LIVING_COLOUR, settings), "and loads again")
        settings.bind_chroma()
        _assert_bound(settings, "after load %d" % load_count)


func test_a_preset_with_the_row_off_between_two_loads_leaves_the_second_bound() -> void:
    var settings := NoiseBrushSettingsScript.new()
    _store.apply_preset(LIVING_COLOUR, settings)
    settings.bind_chroma()
    _store.apply_preset(PLAIN, settings)
    settings.bind_chroma()
    assert_null(settings.hue_option.sensor_for(SaSensor.Id.TEXTURE), "The plain preset paints no variation")
    _store.apply_preset(LIVING_COLOUR, settings)
    settings.bind_chroma()
    _assert_bound(settings, "after the plain one")


func test_a_hand_tick_at_nought_on_options_a_preset_brought_survives_the_press() -> void:
    var settings := NoiseBrushSettingsScript.new()
    _store.apply_preset(PLAIN, settings)
    settings.bind_chroma()
    var ticked := settings.saturation_option.duplicate(true) as SaCurveOption
    ticked.set_sensor(SaSensor.create(SaSensor.Id.TEXTURE, true))
    settings.saturation_option = ticked
    settings.bind_chroma()
    assert_not_null(settings.saturation_option.sensor_for(SaSensor.Id.TEXTURE), "The row at nought binds nothing over it")


func test_a_hand_untick_on_the_options_bound_survives_the_press() -> void:
    var settings := NoiseBrushSettingsScript.new()
    _store.apply_preset(LIVING_COLOUR, settings)
    settings.bind_chroma()
    settings.hue_option.sensor_for(SaSensor.Id.TEXTURE).active = false
    settings.bind_chroma()
    assert_false(settings.hue_option.sensor_for(SaSensor.Id.TEXTURE).active, "The press does not tick it again")


## Both options carry the texture sensor at the row's swing.
func _assert_bound(settings: Resource, when: String) -> void:
    var amount: float = settings.chroma_variation
    var swings := {
        "Hue": [settings.hue_option, NoiseBrushSettingsScript.HUE_SWING],
        "Saturation": [settings.saturation_option, NoiseBrushSettingsScript.SATURATION_SWING],
    }
    for page: String in swings:
        var option: SaCurveOption = swings[page][0]
        var sensor := option.sensor_for(SaSensor.Id.TEXTURE)
        assert_not_null(sensor, "%s follows the texture %s" % [page, when])
        if sensor == null:
            continue
        assert_true(sensor.active and option.enabled, "%s's sensor is on %s" % [page, when])
        var rise: float = sensor.curve[1].y - sensor.curve[0].y
        assert_almost_eq(rise, amount * float(swings[page][1]), 1e-6, "%s at its swing %s" % [page, when])
