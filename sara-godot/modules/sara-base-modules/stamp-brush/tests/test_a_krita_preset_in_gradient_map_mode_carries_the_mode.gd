## A Krita preset whose image tip is in gradient map mode carries the mode and is not tagged as lost.
##
## Krita can apply a tip's picture as a gradient map, the picture's lightness
## picking a colour from a gradient. The stamp brush has such a mode, so the import lands there and no
## `not carried: tip gradient map mode` tag is written. The same png tip
## fixture is written in each of Krita's modes through its `brushApplication`
## number. Gradient map reads the stamp brush's Gradient Map mode, no phrase in
## the result, the tags or the console line, and the report's sentence about
## where its gradient came from. The plain mask and the lightness map read
## neither the mode nor the sentence.
extends "res://tests/test_framework.gd"

const KppFixtures = preload("res://modules/sara-base-modules/stamp-brush/tests/kpp_fixtures.gd")

static var scratch_preset_dir: String = SaDataRoot.path("test_b4_presets")
static var scratch_dir: String = SaDataRoot.path("test_b4_kpp")

## Krita's `enumBrushApplication` numbers.
const ALPHA_MASK: int = 0
const LIGHTNESS_MAP: int = 2
const GRADIENT_MAP: int = 3

## The phrase and the tag an import once wore, which no preset wears now.
const PHRASE := "tip gradient map mode"
const TAG := "not carried: tip gradient map mode"
## The tag of the colour option, which a gradient map tip must not wear either.
const COLOUR_GRADIENT_TAG := "not carried: colour gradient"


func after_each() -> void:
    for folder: String in [scratch_preset_dir, scratch_dir]:
        if DirAccess.dir_exists_absolute(folder):
            var dir := DirAccess.open(folder)
            for file in dir.get_files():
                dir.remove(file)
            DirAccess.remove_absolute(folder)
    for written: String in [
        SaBrushTipMask.saved_dir().path_join(KppFixtures.TIP_FILE),
        SaPatternStore.saved_dir().path_join(KppFixtures.PATTERN_FILE),
    ]:
        if FileAccess.file_exists(written):
            DirAccess.remove_absolute(written)


func test_a_tip_in_gradient_map_mode_carries_the_mode() -> void:
    var store := _store()
    var result := _import(store, GRADIENT_MAP)
    assert_eq(result["error"], "", "imported")
    var loaded := store.load_preset(KppFixtures.PNG_NAME)
    assert_eq(loaded.get("tip_mode"), SaStampBrushSettings.TipMode.GRADIENT_MAP, "The preset is in the Gradient Map mode")
    assert_eq(loaded.get("gradient"), [], "through the empty gradient that reads the painter's pair")
    assert_false(Array(result["not_carried"]).has(PHRASE), "The result names no lost mode: %s" % [result["not_carried"]])
    var tags := Array(store.tags_for(KppFixtures.PNG_NAME))
    assert_false(tags.has(TAG), "the preset's tags do not: %s" % [tags])
    assert_false(tags.has(COLOUR_GRADIENT_TAG), "nor the colour option's phrase")
    var line := SaKppImport.describe(result)
    assert_false(line.contains(PHRASE), "nor the console line")
    assert_true(line.contains(SaKppImport.GRADIENT_FROM_THE_PAINTER), "which says where the gradient came from: %s" % line)


func test_the_same_tip_in_plain_mask_mode_says_nothing_of_the_kind() -> void:
    var store := _store()
    var result := _import(store, ALPHA_MASK)
    assert_eq(result["error"], "", "imported")
    assert_eq(store.load_preset(KppFixtures.PNG_NAME).get("tip_mode"), SaStampBrushSettings.TipMode.MASK, "A mask stays a mask")
    assert_false(Array(result["not_carried"]).has(PHRASE), "no phrase in the result: %s" % [result["not_carried"]])
    assert_eq(result["notes"], [], "and no sentence about a gradient")
    var tags := Array(store.tags_for(KppFixtures.PNG_NAME))
    for tag: String in tags:
        assert_false(tag.contains("gradient"), "and no gradient tag: %s" % tag)


func test_the_lightness_map_mode_which_the_import_carries_wears_no_tag() -> void:
    var store := _store()
    var result := _import(store, LIGHTNESS_MAP)
    assert_eq(result["error"], "", "imported")
    var mode: Variant = store.load_preset(KppFixtures.PNG_NAME).get("tip_mode")
    assert_true(mode != SaStampBrushSettings.TipMode.GRADIENT_MAP, "Not in the Gradient Map mode: %s" % mode)
    assert_false(Array(result["not_carried"]).has(PHRASE), "no phrase in the result: %s" % [result["not_carried"]])
    assert_eq(result["notes"], [], "no sentence about a gradient")
    assert_false(Array(store.tags_for(KppFixtures.PNG_NAME)).has(TAG), "and no tag")


func test_the_reader_keeps_the_mode_of_each_number_krita_writes() -> void:
    var wanted := {
        0: SaKppReader.APPLICATION_ALPHA_MASK,
        1: SaKppReader.APPLICATION_IMAGE_STAMP,
        2: SaKppReader.APPLICATION_LIGHTNESS_MAP,
        3: SaKppReader.APPLICATION_GRADIENT_MAP,
    }
    for number: int in wanted:
        var preset := SaKppReader.read_bytes(KppFixtures.png_kpp(number), "mode-%d.kpp" % number)
        assert_eq(preset["tip"]["application"], wanted[number], "number %d" % number)
    assert_eq(SaKppReader.application_of({}), SaKppReader.APPLICATION_UNSTATED, "no attribute, no mode")
    var unknown := SaKppReader.application_of({"brushApplication": "9"})
    assert_eq(unknown, SaKppReader.APPLICATION_UNSTATED, "a number Krita does not write")


func _store() -> SaPresetStore:
    var store := SaPresetStore.new()
    store.dir = scratch_preset_dir
    return store


func _import(store: SaPresetStore, application: int) -> Dictionary:
    DirAccess.make_dir_recursive_absolute(scratch_dir)
    var path := scratch_dir.path_join("sara-mode-%d.kpp" % application)
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_buffer(KppFixtures.png_kpp(application))
    file.close()
    var results := SaKppImport.import_path(path, store)
    assert_eq(results.size(), 1, "one preset read")
    return results[0]
