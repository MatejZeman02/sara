## Krita's colour smudge engine imported onto the smudge stage: the engine
## ticks the stage, the two rates carry, the radius lands on the brush, and the
## preset wears `smudge`.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Its own file rather than cases in `test_smudge_stage.gd`, because that suite
## needs a RenderingDevice and an import is a table of numbers that does not.
extends "res://tests/test_framework.gd"

const SettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")

static var scratch_preset_dir: String = SaDataRoot.path("test_smudge_import_presets")


func after_each() -> void:
    if DirAccess.dir_exists_absolute(scratch_preset_dir):
        var dir := DirAccess.open(scratch_preset_dir)
        for file in dir.get_files():
            dir.remove(file)
        DirAccess.remove_absolute(scratch_preset_dir)


## A read preset of *engine* whose options are *params*, each written the way
## the reader hands a param over.
func _preset(engine: String, params: Dictionary) -> Dictionary:
    var options := {}
    for name: String in params:
        options[name] = {"value": String(params[name])}
    return {"name": "Smudge Import", "engine": engine, "options": options}


func _smudge_params() -> Dictionary:
    return {
        "ColorRateValue": "0.25",
        "PressureSmudgeRate": "true",
        "SmudgeRateValue": "0.6",
        "SmudgeRateMode": "0",
    }


func test_a_colour_smudge_preset_ticks_the_stage_and_carries_its_rates() -> void:
    var settings: Resource = SettingsScript.new()
    var result := SaKppImport.apply(_preset(SaKppImport.SMUDGE_ENGINE, _smudge_params()), settings)

    assert_true(settings.smudge_pickup_option.enabled, "The engine is the switch, so Smudge Pickup is ticked")
    assert_true(settings.smudge_color_rate_option.enabled, "Colour Rate is ticked")
    assert_almost_eq(settings.smudge_color_rate_option.strength, 0.25, 1e-5, "at Krita's own rate, straight through")
    assert_true(settings.smudge_length_option.enabled, "The smear length came across through the option table")
    assert_almost_eq(settings.smudge_length_option.strength, 0.6, 1e-5, "at Krita's own value")
    assert_eq(settings.smudge_mode, SettingsScript.SmudgeMode.SMEARING, "Krita's nought is the mode that drags")
    assert_true((result["not_carried"] as Array).is_empty(), "Smearing with the dab's own radius leaves nothing behind")
    for name: String in _smudge_params():
        assert_false((result["unread"] as Array).has(name), "%s was read" % name)


func test_a_stamp_preset_leaves_the_stage_off() -> void:
    var settings: Resource = SettingsScript.new()
    SaKppImport.apply(_preset("paintbrush", {"ColorRateValue": "0.25"}), settings)

    assert_false(settings.smudge_pickup_option.enabled, "A paintbrush preset does not smudge")
    assert_almost_eq(settings.smudge_color_rate_option.strength, 0.5, 1e-5, "and its colour rate is the new brush's own")


func test_the_two_rates_and_a_wide_pickup_carry() -> void:
    var params := _smudge_params()
    params["SmudgeRateMode"] = "1"
    params["SmudgeRadiusValue"] = "2.0"
    params["SmudgeRadiusVersion"] = "2"
    var settings: Resource = SettingsScript.new()
    var result := SaKppImport.apply(_preset(SaKppImport.SMUDGE_ENGINE, params), settings)

    assert_eq(settings.smudge_mode, SettingsScript.SmudgeMode.DULLING, "Krita's one is the mode that averages")
    assert_almost_eq(settings.smudge_radius, 2.0, 1e-5, "read as the fraction, since the file says version 2")
    assert_true((result["not_carried"] as Array).is_empty(), "Dulling and a wide pickup both have a home now")
    for name: String in ["SmudgeRateMode", "SmudgeRadiusValue", "SmudgeRadiusVersion"]:
        assert_false((result["unread"] as Array).has(name), "%s was read" % name)


## The other half of the radius: a preset saved before Krita's own range fix
## stores a hundred times the fraction, and reading it as it stands would put a
## pickup a hundredth of a texel across under every dab.
func test_a_legacy_pickup_is_read_at_a_hundredth() -> void:
    var params := _smudge_params()
    params["SmudgeRadiusValue"] = "300.0"
    var settings: Resource = SettingsScript.new()
    SaKppImport.apply(_preset(SaKppImport.SMUDGE_ENGINE, params), settings)

    assert_almost_eq(settings.smudge_radius, 3.0, 1e-5, "the old engine's widest, three hundred, is three times the dab")

    var elsewhere: Resource = SettingsScript.new()
    var narrow := _smudge_params()
    narrow["SmudgeRadiusValue"] = "50.0"
    SaKppImport.apply(_preset(SaKppImport.SMUDGE_ENGINE, narrow), elsewhere)

    assert_almost_eq(elsewhere.smudge_radius, 0.5, 1e-5, "and half the dab reads as half, not as fifty")


## The row's neutral, and the file below the version that added it.
func test_a_file_below_the_radius_version_comes_back_at_the_dab_itself() -> void:
    var settings: Resource = SettingsScript.new()
    settings.smudge_radius = 2.5
    settings.format_version = 6

    assert_true(settings.migrate(), "A resource below version 7 migrates")

    assert_almost_eq(settings.smudge_radius, 1.0, 1e-6, "and the pickup reaches no further than the dab it did")
    assert_eq(settings.format_version, SettingsScript.FORMAT_VERSION, "stamped at the current version")


## The row's neutral, and the file below the version that added it.
func test_a_file_below_the_mode_version_comes_back_smearing() -> void:
    var settings: Resource = SettingsScript.new()
    settings.smudge_mode = SettingsScript.SmudgeMode.DULLING
    settings.format_version = 8

    assert_true(settings.migrate(), "A resource below version 9 migrates")

    assert_eq(settings.smudge_mode, SettingsScript.SmudgeMode.SMEARING, "and the stage drags, which is what it did")
    assert_eq(settings.format_version, SettingsScript.FORMAT_VERSION, "stamped at the current version")


func test_an_imported_smudge_preset_wears_the_smudge_tag() -> void:
    var store := SaPresetStore.new()
    store.dir = scratch_preset_dir
    var result := SaKppImport.import_preset(_preset(SaKppImport.SMUDGE_ENGINE, _smudge_params()), store, SettingsScript.new())

    assert_eq(result["error"], "", "The preset was stored")
    assert_true((result["tags"] as Array).has(SaKppImport.SMUDGE_TAG), "wearing the smudge tag the chooser shows")
    assert_true((result["tags"] as Array).has(SaKppImport.IMPORTED_TAG), "beside the imported tag every import wears")
