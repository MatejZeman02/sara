## The paper's brightness, contrast and neutral point, baked and read
## back.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Every claim is a test here: one pattern at three
## contrasts widens its spread about the neutral point while the texel sitting
## on that point does not move, brightness shifts the whole paper, and the
## texture is rebuilt once per change of a row rather than once per dab.
##
## **The pattern is a five-texel grey ramp written as a PNG**, the way
## `test_pattern.gd` writes its own, rather than a texture filled by hand: the
## claim is about what a painter's paper does when the rows move, so the test
## goes in at the door a painter's paper comes in at, through the store, the
## loader and `SaDabPattern`. The middle texel is 128 of 255 and the neutral
## point is set to exactly that, so "does not move" is an equality rather than
## a tolerance argument.
extends "res://tests/test_framework.gd"

## A bake is a dispatch.
const REQUIRES_GPU := true

const SettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")

static var scratch_dir: String = SaDataRoot.path("test_pattern_tone")
const RAMP_NAME := "tone_ramp.png"

## What the store calls the file above, which is its stem made readable.
const RAMP_PATTERN := "Tone Ramp"

## The ramp's five 8-bit greys, left to right, and the mask value each becomes.
## Luminance's three weights sum to one, so a grey texel keeps its own encoded
## value and the mask is the byte over 255 exactly.
const GREYS: Array[int] = [0, 64, 128, 191, 255]

## The middle grey as a mask value, which is where the neutral point is put.
const MID: float = 128.0 / 255.0


func after_each() -> void:
    if DirAccess.dir_exists_absolute(scratch_dir):
        var dir := DirAccess.open(scratch_dir)
        for file in dir.get_files():
            dir.remove(file)
        DirAccess.remove_absolute(scratch_dir)


## The ramp written to the scratch folder, one texel per grey.
func _write_ramp() -> void:
    DirAccess.make_dir_recursive_absolute(scratch_dir)
    var image := Image.create_empty(GREYS.size(), 1, false, Image.FORMAT_RGBA8)
    for x in GREYS.size():
        var level := float(GREYS[x]) / 255.0
        image.set_pixel(x, 0, Color(level, level, level, 1.0))
    image.save_png(scratch_dir.path_join(RAMP_NAME))


## A brush's pattern half over the scratch folder alone, so no shipped pattern
## can answer the name.
func _dab_pattern() -> SaDabPattern:
    return SaDabPattern.new(SaPatternStore.new([scratch_dir]))


## Fresh settings naming the ramp, with the neutral point on its middle texel and
## the pivot switched from the ramp's own mean onto it.
func _settings() -> Resource:
    var settings := SettingsScript.new()
    settings.pattern_name = RAMP_PATTERN
    settings.texture_neutral_from_pattern = false
    settings.texture_neutral = MID
    return settings


## The five texels of whatever *dab_pattern* binds for *settings*, read back the
## way `test_pattern.gd` reads an `r32f` tile.
func _texels(dab_pattern: SaDabPattern, settings: Resource) -> PackedFloat32Array:
    var texture := dab_pattern.texture(settings)
    if texture == null:
        return PackedFloat32Array()
    return GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0).to_float32_array()


## How far the paper's texels sit from the neutral point on average, which is
## the number the contrast is supposed to move and the only honest way to say
## "the spread widened" over a ramp that clamps at both ends.
static func _spread(texels: PackedFloat32Array) -> float:
    if texels.is_empty():
        return 0.0
    var total := 0.0
    for value in texels:
        total += absf(value - MID)
    return total / float(texels.size())


# --- The bake -------------------------------------------------------------------


func test_three_contrasts_widen_the_spread_about_the_neutral_point() -> void:
    _write_ramp()
    var dab_pattern := _dab_pattern()
    var settings := _settings()
    var spreads: Array[float] = []
    var middles: Array[float] = []
    for contrast: float in [0.0, 0.4, 1.0]:
        settings.texture_contrast = contrast
        var texels := _texels(dab_pattern, settings)
        assert_eq(texels.size(), GREYS.size(), "the ramp came back at a contrast of %.1f" % contrast)
        spreads.append(_spread(texels))
        middles.append(texels[2] if texels.size() > 2 else -1.0)
    assert_true(
        spreads[1] > spreads[0] and spreads[2] > spreads[1],
        "the spread about the neutral point widens with the contrast, %s" % str(spreads)
    )
    for i in middles.size():
        assert_almost_eq(middles[i], MID, 1e-6, "and the texel on the neutral point does not move, reading %f" % middles[i])


func test_a_negative_contrast_flattens_the_grain_towards_the_neutral_point() -> void:
    _write_ramp()
    var dab_pattern := _dab_pattern()
    var settings := _settings()
    settings.texture_contrast = -1.0
    var texels := _texels(dab_pattern, settings)
    assert_eq(texels.size(), GREYS.size(), "the ramp came back")
    var wrong := 0
    for value in texels:
        if absf(value - MID) > 1e-6:
            wrong += 1
    assert_eq(wrong, 0, "a gain of nought is the paper flat at its own mid tone, %s" % str(texels))


func test_brightness_lifts_every_texel_the_grain_still_fits_under() -> void:
    _write_ramp()
    var dab_pattern := _dab_pattern()
    var settings := _settings()
    var plain := _texels(dab_pattern, settings)
    settings.texture_brightness = 0.1
    var lifted := _texels(dab_pattern, settings)
    assert_eq(lifted.size(), plain.size(), "the ramp came back lifted")
    var wrong := 0
    for i in plain.size():
        # The top texel is already one and clamps, so it is the one exception
        # and it is asserted as such rather than skipped quietly.
        var expected: float = clampf(plain[i] + 0.1, 0.0, 1.0)
        if absf(lifted[i] - expected) > 1e-6:
            wrong += 1
    assert_eq(wrong, 0, "brightness adds to every texel and the top one clamps, %s" % str(lifted))


func test_the_neutral_point_moves_which_tone_stays_put() -> void:
    _write_ramp()
    var dab_pattern := _dab_pattern()
    var settings := _settings()
    settings.texture_neutral = 1.0
    settings.texture_contrast = 1.0
    var texels := _texels(dab_pattern, settings)
    assert_eq(texels.size(), GREYS.size(), "the ramp came back")
    assert_almost_eq(texels[4], 1.0, 1e-6, "the pivot moved to the top texel, which is the one that stays")
    assert_true(texels[2] < MID - 0.1, "and the middle fell away from it rather than staying, reading %f" % texels[2])


func test_the_tone_survives_a_scale_that_makes_the_tile_first() -> void:
    # At a scale of one the thing being toned is `SaPattern`'s own cached
    # texture, which outlives the bake. At any other scale it is a texture
    # `_sized` just made and nothing keeps afterwards, and this is the test that
    # a dispatch reading a texture dropped in the same frame still reads it.
    _write_ramp()
    var dab_pattern := _dab_pattern()
    var settings := _settings()
    settings.texture_scale = 3.0
    settings.texture_contrast = 1.0
    var texels := _texels(dab_pattern, settings)
    assert_eq(texels.size(), GREYS.size() * 3 * 3, "the ramp came back resampled to three times its width and its height")
    var below := 0
    var above := 0
    for value in texels:
        if value < MID - 1e-6:
            below += 1
        elif value > MID + 1e-6:
            above += 1
    assert_true(below > 0 and above > 0, "with a light half and a dark half rather than a blank tile, %s" % str(texels))


# --- What it costs --------------------------------------------------------------


func test_the_pattern_is_built_once_per_change_and_not_once_per_dab() -> void:
    _write_ramp()
    var dab_pattern := _dab_pattern()
    var settings := _settings()
    settings.texture_contrast = 0.5
    for _dab in 40:
        assert_not_null(dab_pattern.texture(settings), "every dab of the stroke binds a texture")
    assert_eq(dab_pattern.builds, 1, "forty dabs over one setting built one texture")
    settings.texture_contrast = 0.8
    dab_pattern.texture(settings)
    assert_eq(dab_pattern.builds, 2, "and moving the contrast built the second")
    settings.texture_brightness = 0.2
    dab_pattern.texture(settings)
    settings.texture_neutral = 0.25
    dab_pattern.texture(settings)
    assert_eq(dab_pattern.builds, 4, "as does each of the other two rows")


func test_a_neutral_tone_bakes_nothing_and_hands_back_the_patterns_own_texture() -> void:
    _write_ramp()
    var dab_pattern := _dab_pattern()
    var settings := _settings()
    var report: Dictionary = dab_pattern.report(settings)
    var tone: Dictionary = report["tone"]
    assert_false(bool(tone["baked"]), "a brush that never touched the three rows bakes nothing")
    assert_almost_eq(float(tone["neutral"]), MID, 1e-6, "and the dump still carries the three numbers")
    var texels := _texels(dab_pattern, settings)
    assert_eq(texels.size(), GREYS.size(), "the paper is still the paper")
    for i in GREYS.size():
        assert_almost_eq(texels[i], float(GREYS[i]) / 255.0, 1e-6, "texel %d is the file's own grey" % i)


func test_the_dump_carries_the_tone_beside_the_scale() -> void:
    _write_ramp()
    var dab_pattern := _dab_pattern()
    var settings := _settings()
    settings.texture_brightness = -0.25
    settings.texture_contrast = 0.5
    var tone: Dictionary = (dab_pattern.report(settings) as Dictionary)["tone"]
    assert_almost_eq(float(tone["brightness"]), -0.25, 1e-6, "the brightness")
    assert_almost_eq(float(tone["contrast"]), 0.5, 1e-6, "the contrast")
    assert_true(bool(tone["baked"]), "and the dump says the pass ran")
    assert_eq(int((dab_pattern.report(settings) as Dictionary)["builds"]), 1, "the dump's build count is the stroke's cost")


# --- The rows and the import ----------------------------------------------------


func test_the_three_rows_are_declared_on_the_texture_page() -> void:
    var by_key: Dictionary = {}
    for spec: SaOptionSpec in SaTexturePage.rows():
        by_key[String(spec.key)] = spec
    for key: String in ["texture_brightness", "texture_contrast", "texture_neutral"]:
        var row: SaOptionSpec = by_key.get(key)
        assert_not_null(row, "%s is a declared row" % key)
        if row != null:
            assert_eq(row.page, SaTexturePage.PAGE, "%s names the Texture page" % key)
            assert_false(row.bar, "%s stays off the bar" % key)
            assert_true(row.advanced, "%s sits behind Advanced with the rest of the page" % key)
    assert_almost_eq((by_key["texture_neutral"] as SaOptionSpec).max_value, 1.0, 1e-6, "the neutral point is a paper value")
    assert_almost_eq((by_key["texture_contrast"] as SaOptionSpec).min_value, -1.0, 1e-6, "and the contrast is symmetric")


func test_a_new_brush_has_the_paper_as_drawn() -> void:
    var settings := SettingsScript.new()
    assert_almost_eq(settings.texture_brightness, 0.0, 1e-6, "no brightness")
    assert_almost_eq(settings.texture_contrast, 0.0, 1e-6, "no contrast")
    assert_almost_eq(settings.texture_neutral, 0.5, 1e-6, "and the pivot in the middle")
    assert_true(SaPatternTone.is_neutral(settings), "which together is a tone that bakes nothing")


func test_the_import_carries_kritas_three_numbers() -> void:
    var settings := SettingsScript.new()
    # A `.kpp` option is a type and a value rather than a bare string, which is
    # what `SaKppReader` hands the import and what its `_text` reaches into.
    var written := {
        "Texture/Pattern/Enabled": "true",
        "Texture/Pattern/Brightness": "0.25",
        "Texture/Pattern/Contrast": "1.5",
        "Texture/Pattern/NeutralPoint": "0.4",
    }
    var options := {}
    for named: String in written:
        options[named] = {"type": "string", "value": String(written[named])}
    var preset := {
        "name": "made",
        "source": "made.kpp",
        "engine": "paintbrush",
        "options": options,
        "resources": {},
        "tags": PackedStringArray(),
        "licence": "",
        "error": "",
        "tip": {"kind": SaKppReader.TIP_NONE},
    }
    var applied := SaKppImport.apply(preset, settings)
    assert_almost_eq(settings.texture_brightness, 0.25, 1e-6, "brightness is the same number in both programs")
    assert_almost_eq(settings.texture_contrast, 0.5, 1e-6, "Krita's multiplier of 1.5 is Sara's widening of 0.5")
    assert_almost_eq(settings.texture_neutral, 0.4, 1e-6, "and the neutral point is a pattern value either way")
    assert_false(settings.texture_neutral_from_pattern, "and a file that names its neutral point turns about it (d39)")
    assert_false(
        Array(applied["not_carried"]).has("texture brightness and contrast"),
        "so the phrase the import printed is gone: %s" % str(applied["not_carried"])
    )
    assert_true(Array(applied["unread"]).is_empty(), "and all three params are read by a row, %s" % str(applied["unread"]))
