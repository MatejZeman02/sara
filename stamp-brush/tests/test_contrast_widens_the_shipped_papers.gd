## Contrast raised on a shipped paper, with every other row where a new brush
## leaves it, widens the grain rather than lifting the paper to full.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **A shipped paper and not a test ramp.** The contrast suite puts the neutral
## point on its ramp's middle texel by hand, so it proves the pivot turns and
## says nothing about the pivot a painter gets without touching the row. Paper
## Grain sits between 0.71 and 0.89, so the pivot of a half a new brush had sent
## 82 % of it to one at a contrast of one, and its spread fell from 0.053 to
## 0.028. The widening test below failed on exactly that before the pivot moved.
## The papers are read back at nought and at one on fresh settings, through the
## store and `SaDabPattern`, which is the door a painter's paper comes in at.
extends "res://tests/test_framework.gd"

## A bake is a dispatch.
const REQUIRES_GPU := true

const SettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")

## The shipped papers whose grain is a continuous tone, which a contrast widens.
const CONTINUOUS: Array[String] = ["Paper Grain", "Canvas Weave", "Lit Grain"]

## The shipped halftone: nought or one almost everywhere, so a contrast has only
## its one-texel edges to move and no pivot widens or narrows it.
const DOT_SCREEN: String = "Dot Screen"

## How much wider a continuous paper's grain has to be at a contrast of one. The
## gain is two, so a paper nothing clamps doubles, and about a half Paper Grain
## came back at 0.53 of itself.
const WIDENING: float = 1.5

## The share of a paper the clamp may take at a contrast of one, for the papers
## whose grain sits clear of the ends: 2.8 % of Paper Grain and 1.4 % of Lit
## Grain about their means, against 81.7 % of Paper Grain about a half. Canvas
## Weave is not held to it. Its thread tops sit within a few hundredths of one,
## so a gain of two sends 43 % of it to one whatever the pivot, and it still
## widens from 0.145 to 0.252.
const CLAMPED_SHARE: float = 0.05
const HELD_TO_THE_CLAMP: Array[String] = ["Paper Grain", "Lit Grain"]


func _texels(dab_pattern: SaDabPattern, settings: Resource) -> PackedFloat32Array:
    var texture := dab_pattern.texture(settings)
    if texture == null:
        return PackedFloat32Array()
    return GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0).to_float32_array()


## Fresh settings naming *pattern_name*, which is a new brush with a paper picked.
func _settings(pattern_name: String) -> Resource:
    var settings := SettingsScript.new()
    settings.pattern_name = pattern_name
    return settings


static func _mean(texels: PackedFloat32Array) -> float:
    if texels.is_empty():
        return 0.0
    var total := 0.0
    for value in texels:
        total += value
    return total / float(texels.size())


## The grain's spread, the standard deviation of the texels about their own mean.
static func _spread(texels: PackedFloat32Array) -> float:
    if texels.is_empty():
        return 0.0
    var mean := _mean(texels)
    var squares := 0.0
    for value in texels:
        squares += (value - mean) * (value - mean)
    return sqrt(squares / float(texels.size()))


## The share of *toned* at nought or one where *plain* was not, which is what the
## clamp took.
static func _clamped_share(plain: PackedFloat32Array, toned: PackedFloat32Array) -> float:
    var count := 0
    for i in mini(plain.size(), toned.size()):
        if (toned[i] <= 0.0 or toned[i] >= 1.0) and not (plain[i] <= 0.0 or plain[i] >= 1.0):
            count += 1
    return float(count) / maxf(float(toned.size()), 1.0)


# --- A new brush --------------------------------------------------------------


func test_a_new_brush_turns_about_the_patterns_own_mean() -> void:
    var settings := _settings("Paper Grain")
    assert_true(settings.texture_neutral_from_pattern, "A new brush's contrast turns about the paper's own mean")
    assert_true(SaPatternTone.from_pattern_of(settings), "which is what the tone reads")
    settings.texture_contrast = 1.0
    var tone: Dictionary = (SaDabPattern.new().report(settings) as Dictionary)["tone"]
    assert_true(bool(tone["neutral_from_pattern"]), "and what the dump says, %s" % str(tone))


func test_full_contrast_widens_every_continuous_paper() -> void:
    for pattern_name: String in CONTINUOUS:
        var dab_pattern := SaDabPattern.new()
        var settings := _settings(pattern_name)
        var plain := _texels(dab_pattern, settings)
        settings.texture_contrast = 1.0
        var toned := _texels(dab_pattern, settings)
        assert_true(not plain.is_empty() and plain.size() == toned.size(), "%s came back at nought and at one" % pattern_name)
        if plain.is_empty() or plain.size() != toned.size():
            continue
        var before := _spread(plain)
        var after := _spread(toned)
        var share := _clamped_share(plain, toned)
        assert_true(
            after > before * WIDENING,
            (
                "%s widens at a contrast of one, from %.4f to %.4f with %.1f %% clamped"
                % [pattern_name, before, after, share * 100.0]
            )
        )
        if HELD_TO_THE_CLAMP.has(pattern_name):
            assert_true(share < CLAMPED_SHARE, "and the clamp takes %.1f %% of %s, under five" % [share * 100.0, pattern_name])


func test_the_paper_keeps_its_tone_as_the_tooth_grows() -> void:
    # The promise the tone's header makes, "that tone to stay put while the
    # grain's light and dark move apart around it", read as the paper's mean.
    var dab_pattern := SaDabPattern.new()
    var settings := _settings("Paper Grain")
    var plain := _texels(dab_pattern, settings)
    settings.texture_contrast = 1.0
    var toned := _texels(dab_pattern, settings)
    assert_almost_eq(_mean(toned), _mean(plain), 0.005, "Paper Grain's mean stays at %.4f" % _mean(plain))


func test_the_dot_screen_is_not_narrowed() -> void:
    var dab_pattern := SaDabPattern.new()
    var settings := _settings(DOT_SCREEN)
    var plain := _texels(dab_pattern, settings)
    settings.texture_contrast = 1.0
    var toned := _texels(dab_pattern, settings)
    assert_false(plain.is_empty(), "the dot screen came back")
    assert_true(
        _spread(toned) >= _spread(plain) - 1e-4, "and is no narrower, %.4f against %.4f" % [_spread(toned), _spread(plain)]
    )


# --- The row a painter names --------------------------------------------------


func test_a_named_pivot_turns_about_the_row_when_the_switch_is_off() -> void:
    var dab_pattern := SaDabPattern.new()
    var settings := _settings("Paper Grain")
    var plain := _texels(dab_pattern, settings)
    settings.texture_contrast = 1.0
    settings.texture_neutral_from_pattern = false
    var about_a_half := _texels(dab_pattern, settings)
    assert_true(
        _spread(about_a_half) < _spread(plain),
        (
            "About the row's half the paper is lifted to full and narrows, %.4f against %.4f"
            % [_spread(about_a_half), _spread(plain)]
        )
    )
    settings.texture_neutral = 0.8
    var about_its_mid := _texels(dab_pattern, settings)
    assert_true(_spread(about_its_mid) > _spread(plain) * WIDENING, "and about 0.8, the row set by hand, it widens")


# --- A preset saved before the switch ----------------------------------------


func test_a_preset_with_a_contrast_keeps_the_pivot_it_was_saved_with() -> void:
    var settings := _settings("Paper Grain")
    settings.format_version = 4
    settings.texture_contrast = 0.6
    settings.texture_neutral = 0.5
    assert_true(settings.migrate(), "A version 4 preset migrates")
    assert_false(settings.texture_neutral_from_pattern, "and its contrast still turns about the row it was saved with")
    assert_eq(settings.format_version, SaStampBrushSettings.FORMAT_VERSION, "stamped, so the step runs once")


func test_a_preset_at_nought_contrast_takes_the_patterns_mean() -> void:
    var settings := _settings("Paper Grain")
    settings.format_version = 4
    settings.texture_brightness = -0.2
    settings.migrate()
    assert_true(settings.texture_neutral_from_pattern, "A pivot with nothing turning about it is free to follow the pattern")
