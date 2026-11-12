## A noise brush saved with a Smudge
## Dilution loads with the Colour Rate that lays the same paint, and its
## shipped smudge carries the rate its dilution was.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The stamp brush's suite paints the turn. This one reads that the noise
## brush's migration runs it, since the two engines keep their settings apart
## and either could miss the step.
extends "res://tests/test_framework.gd"

const NoiseBrushSettingsScript = preload("res://modules/sara-noise-brush-engine/noise_brush_settings.gd")
const NoisePresetsScript = preload("res://modules/sara-noise-brush-engine/presets/noise_presets.gd")


func test_a_file_of_format_three_turns_its_dilution_over() -> void:
    var settings: Resource = NoiseBrushSettingsScript.new()
    settings.format_version = 3
    settings.smudge_dilution_option = SaSmudgePage.option(0.8, true)
    assert_true(settings.migrate(), "A noise brush of format 3 migrates")
    assert_null(settings.smudge_dilution_option, "and drops its dilution")
    assert_true(settings.smudge_color_rate_option.enabled, "Its colour rate is ticked, as the dilution was")
    assert_almost_eq(settings.smudge_color_rate_option.strength, 0.2, 1e-6, "at one less the 0.8 it carried")
    assert_eq(settings.format_version, NoiseBrushSettingsScript.FORMAT_VERSION, "stamped at the current format")


func test_an_unticked_dilution_stays_a_pure_smudge() -> void:
    var settings: Resource = NoiseBrushSettingsScript.new()
    settings.format_version = 3
    settings.smudge_dilution_option = SaSmudgePage.option(0.8)
    settings.migrate()
    assert_false(
        settings.smudge_color_rate_option.enabled, "An unticked dilution laid the carry in full, as an unticked rate does"
    )


func test_a_fresh_noise_brush_is_left_alone() -> void:
    var settings: Resource = NoiseBrushSettingsScript.new()
    assert_false(settings.migrate(), "A noise brush made now has nothing to migrate")
    assert_true(settings.smudge_color_rate_option.enabled, "and its colour rate waits ticked")
    assert_almost_eq(settings.smudge_color_rate_option.strength, 0.5, 1e-6, "at a half")


func test_wet_into_wet_ships_at_the_rate_its_dilution_was() -> void:
    for entry: Dictionary in NoisePresetsScript.entries():
        if String(entry["name"]) != "Wet Into Wet":
            continue
        var settings: Resource = NoisePresetsScript.build(NoiseBrushSettingsScript, entry)
        assert_true(settings.smudge_color_rate_option.enabled, "Wet Into Wet's colour rate is ticked")
        assert_almost_eq(settings.smudge_color_rate_option.strength, 0.5, 1e-6, "at one less the 0.5 it shipped as dilution")
        return
    assert_true(false, "Wet Into Wet is a shipped noise recipe")
