## The stamp module converts its presets to the noise brush and back.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## the answer: a converted preset carries "the name, the tags, the brush tip
## and the icon", and invents its field and strength from a chaos metric over
## the stamp preset's randomness, scatter, density and tip. Three stamp presets
## of known character, a soft round, a textured flat and a scattered splatter,
## go through the store and the stamp module's converter, and each comes out
## with the field and strength the metric names, written as the shift the
## noise brush reads as its pressure cut, so it paints what the metric names.
## Both modules
## register through the door here, as in the app, so the converter finds the
## noise brush's settings the way it does there. In the skeleton's tests rather
## than a module's, since it names both modules and neither module names the
## other.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
const StampModuleScript = preload("res://modules/sara-base-modules/stamp-brush/module.gd")
const NoiseModuleScript = preload("res://modules/sara-noise-brush-engine/module.gd")
const ConversionScript = preload("res://modules/sara-base-modules/stamp-brush/presets/sa_noise_conversion.gd")
const Fixtures = preload("res://tests/fixtures.gd")
const SaBrushTipScript = preload("res://core/api/tip/sa_brush_tip.gd")

## Never the real `user://brush_presets`, for `test_brush_presets.gd`'s reason.
static var scratch_dir: String = SaDataRoot.path("test_s3_converters")

## A ragged picture tip and a regular one, both shipped.
const RAGGED_TIP: String = "res://tips/tree.png"
const SQUARE_TIP: String = "res://tips/square.png"

## The pattern the textured flat paints through, one the store ships.
const PATTERN: String = "Canvas Weave"

var _registries: SaRegistries = null
var _stamp: SaModule = null
var _noise: SaModule = null


func before_each() -> void:
    ScratchFolder.clear(scratch_dir)
    _registries = Fixtures.make_registries()
    _noise = NoiseModuleScript.new()
    _noise.register(_registries.context.for_module(_noise.get_id()))
    _stamp = StampModuleScript.new()
    _stamp.register(_registries.context.for_module(_stamp.get_id()))


func after_each() -> void:
    for module: SaModule in [_stamp, _noise]:
        module.unregister(_registries.context)
    _registries.context.for_module(_stamp.get_id()).remove_all_registrations()
    _registries.context.for_module(_noise.get_id()).remove_all_registrations()
    _stamp = null
    _noise = null
    _registries = null
    ScratchFolder.clear(scratch_dir)


# --- The door ---------------------------------------------------------------


## The stamp module registers both directions, and the noise module neither.
func test_the_stamp_module_registers_both_directions() -> void:
    var converters := _registries.context.converters
    assert_true(converters.converts(&"stamp", &"noise"), "Stamp converts to noise")
    assert_true(converters.converts(&"noise", &"stamp"), "and noise to stamp")
    assert_eq(converters.owner_of(&"stamp", &"noise"), _stamp.get_id(), "both the stamp module's")
    assert_eq(converters.owner_of(&"noise", &"stamp"), _stamp.get_id(), "by the flagship ruling")
    assert_eq(ConversionScript.TAGS_META, SaPresetMeta.TAGS_META, "The converter spells the store's tags key as the store does")


# --- Stamp to noise ---------------------------------------------------------


## A soft round is calm: Grain at low contrast, a low cut, and a pressure line
## that fills the stroke in at a full press. Its cut fell to nought, the old
## default's line, so it carries exactly: a shift of the cut less one at no
## pressure, falling to none at a full press.
func test_a_soft_round_becomes_a_low_contrast_grain() -> void:
    var store := _store()
    store.save_preset("Soft Round", _soft_round(), PackedStringArray(["round", "soft"]))
    var metric := ConversionScript.chaos_of(store.load_preset("Soft Round"))
    assert_almost_eq(float(metric["chaos"]), 0.0, 0.0001, "A soft round reads no chaos: %s" % [metric])
    var converted := _convert(store, "Soft Round", &"noise")
    assert_eq(converted.get("texture_field"), "grain", "Grain, the smooth field")
    assert_almost_eq(float(converted.get("grain_contrast")), ConversionScript.CONTRAST_CALM, 0.0001, "at low contrast")
    assert_true(float(converted.get("grain_contrast")) < 2.0, "under the noise brush's own default")
    assert_almost_eq(
        float(converted.get("strength")),
        ConversionScript.STRENGTH_CALM - 1.0,
        0.0001,
        "The cut is low, so the shift is well below nought"
    )
    assert_almost_eq(_floor_of(converted), 0.0, 0.0001, "and a full press takes it to nought")
    _assert_carried(store, "Soft Round", converted, ["round", "soft"])


## A textured flat keeps its pattern as the Picture field, and the metric reads
## its sparse tip into the strength. Its cut stops short of nought at a full
## press, a shift a hair over it there, which the carried curve meets at
## nought.
func test_a_textured_flat_keeps_its_pattern_as_a_picture() -> void:
    var store := _store()
    store.save_preset("Textured Flat", _textured_flat(), PackedStringArray(["flat"]))
    var metric := ConversionScript.chaos_of(store.load_preset("Textured Flat"))
    assert_almost_eq(float(metric["sparseness"]), 0.2, 0.0001, "Its tip leaves a fifth of its texels bare")
    assert_almost_eq(float(metric["chaos"]), 0.2, 0.0001, "and that is all its chaos")
    var converted := _convert(store, "Textured Flat", &"noise")
    assert_eq(converted.get("texture_field"), "picture", "The pattern it painted through is its field")
    assert_eq(converted.get("picture_name"), PATTERN, "the same pattern")
    assert_almost_eq(float(converted.get("picture_scale")), 2.0, 0.0001, "at the same scale")
    var strength := lerpf(ConversionScript.STRENGTH_CALM, ConversionScript.STRENGTH_WILD, 0.2)
    assert_almost_eq(
        float(converted.get("strength")), strength - 1.0, 0.0001, "The cut the metric names, less one at no pressure"
    )
    assert_almost_eq(_floor_of(converted), 0.0, 0.0001, "and nought where a full press leaves it")
    _assert_carried(store, "Textured Flat", converted, ["flat"])


## A splatter, a ragged tip scattered two diameters wide, is as chaotic as a
## brush gets: Bristle at its widest spread and a high cut a press cannot
## close, so the shift a full press meets is the cut it left, and the curve
## rises to it.
func test_a_scattered_splatter_becomes_a_wide_bristle() -> void:
    var store := _store()
    store.save_preset("Splatter", _splatter(), PackedStringArray(["wet", "texture"]))
    var metric := ConversionScript.chaos_of(store.load_preset("Splatter"))
    assert_almost_eq(float(metric["scatter"]), 1.0, 0.0001, "Two diameters of scatter is all the scatter there is")
    assert_true(float(metric["irregularity"]) > 0.2, "and the tree tip reads ragged: %s" % [metric])
    assert_almost_eq(float(metric["chaos"]), 1.0, 0.0001, "so the brush reads fully chaotic")
    var converted := _convert(store, "Splatter", &"noise")
    assert_eq(converted.get("texture_field"), "bristle", "Bristle, the ragged field")
    assert_almost_eq(float(converted.get("bristle_spread")), ConversionScript.SPREAD_WILD, 0.0001, "with a wide spread")
    var kept := ConversionScript.STRENGTH_WILD * ConversionScript.FLOOR_WILD
    assert_almost_eq(float(converted.get("strength")), kept, 0.0001, "The cut is high, half of it left at a full press")
    assert_almost_eq(_floor_of(converted), 1.0, 0.0001, "where the curve reaches all of it")
    _assert_carried(store, "Splatter", converted, ["wet", "texture"])


## A stamp's per dab roll on an option both engines share moves along the
## stroke on its way to the noise brush, which rolls nothing per dab, at the amount it had.
func test_a_per_dab_roll_moves_along_the_stroke() -> void:
    var store := _store()
    var rolled := _soft_round()
    rolled.size_option.bind_random(0.6, SaSensor.Id.FUZZY_PER_DAB, "size")
    store.save_preset("Rolled Round", rolled, PackedStringArray())
    var size_option := _convert(store, "Rolled Round", &"noise").get("size_option") as SaCurveOption
    assert_null(size_option.sensor_for(SaSensor.Id.FUZZY_PER_DAB), "The noise brush's Size rolls nothing per dab")
    assert_eq(size_option.random_clock(), SaSensor.Id.FUZZY_ALONG_STROKE, "and rolls along the stroke instead")
    assert_almost_eq(size_option.random_amount(), 0.6, 0.0001, "as far below the row as the stamp's roll reached")
    assert_eq(size_option.sensor_for(SaSensor.Id.FUZZY_ALONG_STROKE).resource_name, "size", "under the option's name")


## Each reading of the metric on its own: the tip's randomness, a fuzzy roll
## on an option, and a ragged picture against a square one.
func test_the_metric_reads_each_trait() -> void:
    var rolled := _soft_round()
    rolled.tip.randomness = 0.4
    assert_almost_eq(float(ConversionScript.chaos_of(rolled)["randomness"]), 0.4, 0.0001, "The tip's Randomness")
    var fuzzy := _soft_round()
    fuzzy.size_option.bind_random(0.6, SaSensor.Id.FUZZY_PER_DAB, "size")
    assert_almost_eq(float(ConversionScript.chaos_of(fuzzy)["randomness"]), 0.6, 0.0001, "and a fuzzy roll on Size")
    var one_axis := _splatter()
    one_axis.scatter_axis_x = false
    assert_almost_eq(float(ConversionScript.chaos_of(one_axis)["scatter"]), 1.0, 0.0001, "One axis still scatters")
    one_axis.scatter_axis_y = false
    assert_almost_eq(float(ConversionScript.chaos_of(one_axis)["scatter"]), 0.0, 0.0001, "and none is no scatter")
    var ragged := ConversionScript.tip_irregularity(_image_tip(RAGGED_TIP))
    var square := ConversionScript.tip_irregularity(_image_tip(SQUARE_TIP))
    assert_true(square < 0.1, "A square picture is a regular tip: %.3f" % square)
    assert_true(ragged > square + 0.1, "and the tree well more ragged: %.3f against %.3f" % [ragged, square])
    assert_almost_eq(ConversionScript.tip_irregularity(_soft_round().tip), 0.0, 0.0001, "A procedural tip is not ragged")


## With no tool of the noise engine registered there is nothing to build a
## noise preset from, and the store writes nothing.
func test_without_the_noise_brush_nothing_is_written() -> void:
    _noise.unregister(_registries.context)
    _registries.context.for_module(_noise.get_id()).remove_all_registrations()
    var store := _store()
    store.save_preset("Soft Round", _soft_round())
    assert_eq(store.convert_preset("Soft Round", &"noise", _registries.context.converters), "", "Nothing converts")
    assert_eq(Array(store.list_names()), ["Soft Round"], "and the library is as it was")


# --- Noise to stamp ---------------------------------------------------------


## A Picture field becomes the stamp's pattern, with the cut and its pressure
## line as the Texture option, read back the old way round from the noise
## brush's shift, and nothing is tagged as lost.
func test_a_picture_becomes_the_stamps_pattern() -> void:
    var store := _store()
    store.save_preset("Textured Flat", _textured_flat(), PackedStringArray(["flat"]))
    var noise_name := store.convert_preset("Textured Flat", &"noise", _registries.context.converters)
    var back_name := store.convert_preset(noise_name, &"stamp", _registries.context.converters)
    var back := store.load_preset(back_name)
    assert_eq(SaPresetMeta.engine_of(back), &"stamp", "A stamp preset")
    assert_eq(back.get("pattern_name"), PATTERN, "painting through the picture's pattern")
    assert_almost_eq(float(back.get("texture_scale")), 2.0, 0.0001, "at its scale")
    var texture := back.get("texture_option") as SaCurveOption
    assert_true(texture.enabled, "with the Texture option on")
    var cut := lerpf(ConversionScript.STRENGTH_CALM, ConversionScript.STRENGTH_WILD, 0.2)
    assert_almost_eq(texture.strength, cut, 0.001, "at the cut the stamp went over at")
    var line := texture.common_curve
    assert_almost_eq(line[0].y, 1.0, 0.001, "along a pressure line from all of it")
    var floor_at := line[line.size() - 1].y
    assert_true(
        floor_at <= ConversionScript.FLOOR_WILD * 0.2 + 0.001,
        "and down to no more than the floor it went over with, %.3f" % floor_at
    )
    for tag: String in store.tags_for(back_name):
        assert_false(tag.begins_with(SaKppImport.NOT_CARRIED_PREFIX), "Nothing lost: %s" % tag)


## A Grain or a Bristle has no pattern to become, and the preset says so in
## its not-carried tags.
func test_a_field_the_stamp_cannot_hold_is_tagged_not_carried() -> void:
    var store := _store()
    store.save_preset("Splatter", _splatter(), PackedStringArray(["wet"]))
    var noise_name := store.convert_preset("Splatter", &"noise", _registries.context.converters)
    var back_name := store.convert_preset(noise_name, &"stamp", _registries.context.converters)
    var tags := Array(store.tags_for(back_name))
    assert_true(tags.has("not carried: bristle field"), "The field is named as not carried: %s" % [tags])
    assert_true(tags.has("not carried: strength"), "and the cut with it")
    var back := store.load_preset(back_name)
    assert_false((back.get("texture_option") as SaCurveOption).enabled, "The stamp paints untextured")


## Stamp to noise and back keeps the name, the tags and the tip, for each of
## the three.
func test_a_round_trip_keeps_the_name_tags_and_tip() -> void:
    var store := _store()
    var presets := {"Soft Round": _soft_round(), "Textured Flat": _textured_flat(), "Splatter": _splatter()}
    for preset_name: String in presets:
        store.save_preset(preset_name, presets[preset_name], PackedStringArray(["kept", preset_name.to_lower()]))
        var noise_name := store.convert_preset(preset_name, &"noise", _registries.context.converters)
        var back_name := store.convert_preset(noise_name, &"stamp", _registries.context.converters)
        assert_eq(back_name, "%s (Noise) (Stamp)" % preset_name, "The name is kept, each engine's label after it")
        var tags := Array(store.tags_for(back_name))
        assert_true(tags.has("kept") and tags.has(preset_name.to_lower()), "The tags are kept: %s" % [tags])
        var original := store.load_preset(preset_name)
        var back := store.load_preset(back_name)
        _assert_same_tip(original.get("tip"), back.get("tip"), "%s's round trip" % preset_name)
        assert_almost_eq(float(back.get("radius")), float(original.get("radius")), 0.000001, "and the size")


# --- Presets of known character ---------------------------------------------


## A soft round: the Gaussian generator, solid, no scatter, no roll.
func _soft_round() -> SaStampBrushSettings:
    var settings := SaStampBrushSettings.new()
    settings.radius = 0.03
    settings.opacity = 0.8
    settings.tip.generator = SaDabGeometry.Generator.GAUSS
    return settings


## A textured flat: a narrow rectangle at a fifth sparse, through a pattern.
func _textured_flat() -> SaStampBrushSettings:
    var settings := SaStampBrushSettings.new()
    settings.radius = 0.04
    settings.tip.shape = SaBrushTipScript.Shape.RECTANGLE
    settings.tip.ratio = 0.25
    settings.tip.density = 0.8
    settings.pattern_name = PATTERN
    settings.texture_scale = 2.0
    settings.texture_option.enabled = true
    return settings


## A splatter: the ragged tree tip, scattered two diameters wide.
func _splatter() -> SaStampBrushSettings:
    var settings := SaStampBrushSettings.new()
    settings.radius = 0.02
    settings.tip = _image_tip(RAGGED_TIP)
    settings.scatter_option.enabled = true
    settings.scatter_option.strength = 2.0
    return settings


func _image_tip(path: String) -> Resource:
    var tip: Resource = SaBrushTipScript.new()
    tip.kind = SaBrushTipScript.Kind.IMAGE
    tip.generator = SaDabGeometry.Generator.IMAGE
    tip.image_path = path
    return tip


# --- Helpers ----------------------------------------------------------------


## Converts through the store and answers the new preset as loaded.
func _convert(store: SaPresetStore, preset_name: String, engine: StringName) -> Resource:
    var written := store.convert_preset(preset_name, engine, _registries.context.converters)
    assert_false(written.is_empty(), "'%s' converts to %s" % [preset_name, engine])
    return store.load_preset(written)


## Where Strength's pressure line ends at a full press.
func _floor_of(converted: Resource) -> float:
    var curve := (converted.get("strength_option") as SaCurveOption).common_curve
    return curve[curve.size() - 1].y


## The name, the tags and the tip, and the icon's two inputs, the tip and the
## size, since an icon is a stroke rendered from the settings.
func _assert_carried(store: SaPresetStore, preset_name: String, converted: Resource, tags: Array) -> void:
    var written := "%s (Noise)" % preset_name
    assert_true(store.has_preset(written), "The new preset is named after the original: %s" % written)
    assert_eq(store.engine_for(written), &"noise", "and is a noise preset")
    var carried := Array(store.tags_for(written))
    for tag: String in tags:
        assert_true(carried.has(tag), "'%s' is carried: %s" % [tag, carried])
    var original := store.load_preset(preset_name)
    _assert_same_tip(original.get("tip"), converted.get("tip"), preset_name)
    assert_almost_eq(float(converted.get("radius")), float(original.get("radius")), 0.000001, "The size is carried")
    assert_almost_eq(float(converted.get("opacity")), float(original.get("opacity")), 0.000001, "and the opacity")
    var size_option := converted.get("size_option") as SaCurveOption
    assert_eq(size_option.enabled, (original.get("size_option") as SaCurveOption).enabled, "and Size's binding")
    var opacity_option := converted.get("opacity_option") as SaCurveOption
    assert_eq(opacity_option.enabled, (original.get("opacity_option") as SaCurveOption).enabled, "and Opacity's")


func _assert_same_tip(original: Resource, carried: Resource, what: String) -> void:
    assert_not_null(carried, "%s carries a tip" % what)
    if carried == null:
        return
    for key: String in ["kind", "generator", "shape", "ratio", "density", "randomness", "image_path", "softness"]:
        assert_eq(carried.get(key), original.get(key), "%s: the tip's %s" % [what, key])


func _store() -> SaPresetStore:
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    return store
