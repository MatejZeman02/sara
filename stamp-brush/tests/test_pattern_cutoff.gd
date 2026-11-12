## The paper's cutoff band and its policy, baked and read back.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The unit's Done-when is one sentence: a pattern baked at three policies,
## where the texels outside the band follow the policy and those inside are
## untouched. Every case here is that sentence over a five-texel ramp, plus the
## two settings that are a cutoff on paper and no cutoff in the texels, plus the
## import's two bounds and its policy.
##
## **The same five-texel ramp `test_pattern_tone.gd` writes**, and for the same
## reason: the claim is about a painter's paper, so the test goes in at the door
## a painter's paper comes in at, through the store, the loader and
## `SaDabPattern`, and the five greys are exact eighth-bit values so a band put
## between two of them is an inequality rather than a tolerance argument.
##
## **The band is read against the toned value**, which is why the case that
## moves the brightness under a fixed band is here rather than in the tone's own
## file: it is the one assertion that says which of the two stages runs first,
## and reading it in either file would leave the other looking arbitrary.
extends "res://tests/test_framework.gd"

## A bake is a dispatch.
const REQUIRES_GPU := true

const SettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")

static var scratch_dir: String = SaDataRoot.path("test_pattern_cutoff")
const RAMP_NAME := "cutoff_ramp.png"

## What the store calls the file above, which is its stem made readable.
const RAMP_PATTERN := "Cutoff Ramp"

## The ramp's five 8-bit greys, left to right. Luminance's three weights sum to
## one, so a grey texel keeps its own encoded value and the mask is the byte
## over 255 exactly.
const GREYS: Array[int] = [0, 64, 128, 191, 255]


func after_each() -> void:
    if DirAccess.dir_exists_absolute(scratch_dir):
        var dir := DirAccess.open(scratch_dir)
        for file in dir.get_files():
            dir.remove(file)
        DirAccess.remove_absolute(scratch_dir)


## The mask value the *index*th grey becomes.
static func _grey(index: int) -> float:
    return float(GREYS[index]) / 255.0


## The ramp written to the scratch folder, one texel per grey.
func _write_ramp() -> void:
    DirAccess.make_dir_recursive_absolute(scratch_dir)
    var image := Image.create_empty(GREYS.size(), 1, false, Image.FORMAT_RGBA8)
    for x in GREYS.size():
        var level := _grey(x)
        image.set_pixel(x, 0, Color(level, level, level, 1.0))
    image.save_png(scratch_dir.path_join(RAMP_NAME))


## A brush's pattern half over the scratch folder alone, so no shipped pattern
## can answer the name.
func _dab_pattern() -> SaDabPattern:
    return SaDabPattern.new(SaPatternStore.new([scratch_dir]))


## Fresh settings naming the ramp, with a band that keeps the three middle
## texels and cuts the two ends. The bounds sit between greys rather than on
## one, so no case turns on which side of a bound an equal value falls.
func _settings() -> Resource:
    var settings := SettingsScript.new()
    settings.pattern_name = RAMP_PATTERN
    settings.texture_cutoff_left = (_grey(0) + _grey(1)) * 0.5
    settings.texture_cutoff_right = (_grey(3) + _grey(4)) * 0.5
    return settings


## The five texels of whatever *dab_pattern* binds for *settings*.
func _texels(dab_pattern: SaDabPattern, settings: Resource) -> PackedFloat32Array:
    var texture := dab_pattern.texture(settings)
    if texture == null:
        return PackedFloat32Array()
    return GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0).to_float32_array()


# --- The three policies ---------------------------------------------------------


func test_the_three_policies_each_do_their_own_thing_outside_the_band() -> void:
    _write_ramp()
    var dab_pattern := _dab_pattern()
    var settings := _settings()
    var outside: Dictionary = {}
    for policy: SaPatternTone.Policy in [SaPatternTone.Policy.OFF, SaPatternTone.Policy.DAB, SaPatternTone.Policy.PAPER]:
        settings.texture_cutoff_policy = policy
        var texels := _texels(dab_pattern, settings)
        assert_eq(texels.size(), GREYS.size(), "the ramp came back under policy %d" % policy)
        outside[policy] = [texels[0], texels[4]]
        for i: int in [1, 2, 3]:
            assert_almost_eq(texels[i], _grey(i), 1e-6, "the texel inside the band is untouched under policy %d" % policy)
    assert_eq(
        outside[SaPatternTone.Policy.OFF],
        [_grey(0), _grey(4)],
        "the off policy leaves the two texels outside the band as their author drew them"
    )
    assert_eq(outside[SaPatternTone.Policy.DAB], [0.0, 0.0], "cutting the dab takes them to nothing")
    assert_eq(outside[SaPatternTone.Policy.PAPER], [1.0, 1.0], "and cutting the paper takes them to full")


func test_a_bound_is_inclusive_so_a_texel_on_it_is_kept() -> void:
    _write_ramp()
    var dab_pattern := _dab_pattern()
    var settings := _settings()
    settings.texture_cutoff_policy = SaPatternTone.Policy.DAB
    settings.texture_cutoff_left = _grey(1)
    settings.texture_cutoff_right = _grey(3)
    var texels := _texels(dab_pattern, settings)
    assert_eq(texels.size(), GREYS.size(), "the ramp came back")
    assert_almost_eq(texels[1], _grey(1), 1e-6, "the texel sitting on the left bound is inside the band")
    assert_almost_eq(texels[3], _grey(3), 1e-6, "and so is the one sitting on the right bound")
    assert_eq([texels[0], texels[4]], [0.0, 0.0], "while the two beyond them are cut")


func test_a_crossed_band_cuts_the_whole_paper() -> void:
    # Two sliders a painter can drag past each other, and Krita paints nothing
    # through a crossed band either, so this is a setting rather than an error.
    _write_ramp()
    var dab_pattern := _dab_pattern()
    var settings := _settings()
    settings.texture_cutoff_policy = SaPatternTone.Policy.PAPER
    settings.texture_cutoff_left = 0.9
    settings.texture_cutoff_right = 0.1
    var texels := _texels(dab_pattern, settings)
    assert_eq(texels.size(), GREYS.size(), "the ramp came back")
    var kept := 0
    for value in texels:
        if absf(value - 1.0) > 1e-6:
            kept += 1
    assert_eq(kept, 0, "no texel is inside a band whose left has passed its right, %s" % str(texels))


# --- Where the cutoff sits in the pass ------------------------------------------


func test_the_band_is_read_against_the_toned_value_and_not_the_drawn_one() -> void:
    _write_ramp()
    var dab_pattern := _dab_pattern()
    var settings := _settings()
    settings.texture_cutoff_policy = SaPatternTone.Policy.DAB
    settings.texture_cutoff_left = 0.0
    settings.texture_cutoff_right = (_grey(2) + _grey(3)) * 0.5
    var plain := _texels(dab_pattern, settings)
    assert_eq(plain.size(), GREYS.size(), "the ramp came back with its top texel cut")
    assert_eq([plain[3], plain[4]], [0.0, 0.0], "the two texels above the right bound are cut")
    assert_almost_eq(plain[2], _grey(2), 1e-6, "and the middle one is not")
    settings.texture_brightness = 0.2
    var lifted := _texels(dab_pattern, settings)
    assert_eq(lifted.size(), GREYS.size(), "the ramp came back lifted")
    assert_eq(
        lifted[2],
        0.0,
        (
            "the middle texel is cut once the brightness has pushed it past the same bound, "
            + "which it could not be if the band were read before the tone"
        )
    )


# --- What counts as no cutoff at all -------------------------------------------


func test_a_policy_over_the_whole_range_bakes_nothing() -> void:
    var settings := SettingsScript.new()
    settings.texture_cutoff_policy = SaPatternTone.Policy.DAB
    assert_false(SaPatternTone.cuts(settings), "a band nobody narrowed cuts nothing")
    assert_true(SaPatternTone.is_neutral(settings), "so the paper is the one its author drew and no pass runs")
    settings.texture_cutoff_right = 0.75
    assert_true(SaPatternTone.cuts(settings), "one bound moved is a cutoff")
    assert_false(SaPatternTone.is_neutral(settings), "and a pass to run, with the tone rows still at nought")
    settings.texture_cutoff_policy = SaPatternTone.Policy.OFF
    assert_false(SaPatternTone.cuts(settings), "while the off policy cuts nothing whatever the bounds say")
    assert_true(SaPatternTone.is_neutral(settings), "and needs no pass either")


func test_a_settings_resource_written_before_this_unit_reads_as_no_cutoff() -> void:
    # The three keys are additive, the way the contrast's three are, so a
    # preset saved by a Sara without them loads and paints as it did.
    var older := Resource.new()
    assert_eq(SaPatternTone.cutoff_left_of(older), SaPatternTone.MIN_CUTOFF, "the left bound falls back to the floor")
    assert_eq(SaPatternTone.cutoff_right_of(older), SaPatternTone.MAX_CUTOFF, "the right one to the ceiling")
    assert_eq(SaPatternTone.cutoff_policy_of(older), SaPatternTone.Policy.OFF, "and the policy to off")
    assert_false(SaPatternTone.cuts(older), "which is no cutoff")


func test_a_policy_the_file_invented_is_clamped_rather_than_dispatched() -> void:
    var settings := SettingsScript.new()
    settings.texture_cutoff_policy = 7
    assert_eq(
        SaPatternTone.cutoff_policy_of(settings),
        SaPatternTone.Policy.PAPER,
        "a policy past the last one reads as the last one, so the kernel never sees a branch it has not got"
    )
    settings.texture_cutoff_policy = -3
    assert_eq(SaPatternTone.cutoff_policy_of(settings), SaPatternTone.Policy.OFF, "and one below the first as off")


# --- What it costs --------------------------------------------------------------


func test_each_cutoff_row_rebuilds_the_texture_once() -> void:
    _write_ramp()
    var dab_pattern := _dab_pattern()
    var settings := _settings()
    settings.texture_cutoff_policy = SaPatternTone.Policy.DAB
    for _dab in 40:
        assert_not_null(dab_pattern.texture(settings), "every dab of the stroke binds a texture")
    assert_eq(dab_pattern.builds, 1, "forty dabs over one band built one texture")
    settings.texture_cutoff_left = 0.3
    dab_pattern.texture(settings)
    settings.texture_cutoff_right = 0.7
    dab_pattern.texture(settings)
    settings.texture_cutoff_policy = SaPatternTone.Policy.PAPER
    dab_pattern.texture(settings)
    assert_eq(dab_pattern.builds, 4, "and each of the three rows moving built one more")


# --- The import ----------------------------------------------------------------


func test_the_import_carries_kritas_band_as_pattern_values() -> void:
    var settings := SettingsScript.new()
    # A `.kpp` option is a type and a value rather than a bare string, which is
    # what `SaKppReader` hands the import and what its `_float` reaches into.
    var written := {
        "Texture/Pattern/Enabled": "true",
        "Texture/Pattern/CutoffLeft": "51",
        "Texture/Pattern/CutoffRight": "204",
        "Texture/Pattern/CutoffPolicy": "2",
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
    assert_almost_eq(settings.texture_cutoff_left, 51.0 / 255.0, 1e-6, "Krita's byte divided by 255 is a pattern value")
    assert_almost_eq(settings.texture_cutoff_right, 204.0 / 255.0, 1e-6, "at both ends of the band")
    assert_eq(settings.texture_cutoff_policy, SaPatternTone.Policy.PAPER, "and the policy is Krita's own number")
    assert_false(
        Array(applied["not_carried"]).has("texture cutoff"),
        "so the phrase the mapping table printed is gone, %s" % str(applied["not_carried"])
    )
    assert_true(Array(applied["unread"]).is_empty(), "and all three params are read by a row, %s" % str(applied["unread"]))
