## A preset imported again is refreshed rather than left wearing an older
## importer's tags.
##
## A store imported before lightness and height had arithmetic,
## so its tags said a preset lost what the importer carries now. The first
## import here is written the way that older importer left it, a setting it
## could not carry at its default and a "not carried" tag for it, and the second
## is today's importer over the same file. The result is one preset
## with the new settings and no stale tag, and the painter's own tag and a copy
## saved under another name are the two things a refresh must not take.
extends "res://tests/test_framework.gd"

const KppFixtures = preload("res://modules/sara-base-modules/stamp-brush/tests/kpp_fixtures.gd")
const SettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")

const ROUND := "res://modules/sara-base-modules/stamp-brush/tests/fixtures/sara-round.kpp"
static var scratch_preset_dir: String = SaDataRoot.path("test_k5_presets")
const STALE_TAG := "not carried: colour lightness"
const OWN_TAG := "my inks"
const COPY_NAME := "Sara fixture round, mine"

## The radius the older import is left with, anything but the fixture's.
const OLD_RADIUS: float = 0.25


func after_each() -> void:
    if DirAccess.dir_exists_absolute(scratch_preset_dir):
        var dir := DirAccess.open(scratch_preset_dir)
        for file in dir.get_files():
            dir.remove(file)
        DirAccess.remove_absolute(scratch_preset_dir)


func _store() -> SaPresetStore:
    var store := SaPresetStore.new()
    store.dir = scratch_preset_dir
    return store


## The store as an older importer left it: the round fixture imported, then its
## radius put back to what an importer without the row would have written, a
## tag for the loss, the painter's own tag, and a copy under another name.
func _older_import(store: SaPresetStore) -> void:
    SaKppImport.import_path(ROUND, store)
    var settings := SettingsScript.new()
    SaPresetStore.copy_settings(store.load_preset(KppFixtures.ROUND_NAME), settings)
    settings.radius = OLD_RADIUS
    var tags := PackedStringArray([SaKppImport.IMPORTED_TAG, STALE_TAG, OWN_TAG])
    store.save_preset(KppFixtures.ROUND_NAME, settings, tags)
    store.save_preset(COPY_NAME, settings, PackedStringArray([OWN_TAG]))


func _radius(store: SaPresetStore, preset_name: String) -> float:
    var settings := SettingsScript.new()
    SaPresetStore.copy_settings(store.load_preset(preset_name), settings)
    return settings.radius


func _bytes(store: SaPresetStore, preset_name: String) -> PackedByteArray:
    return FileAccess.get_file_as_bytes(store.dir.path_join(preset_name + SaPresetStore.EXTENSION))


func test_the_second_import_replaces_the_settings_and_drops_the_stale_tag() -> void:
    var store := _store()
    _older_import(store)
    var copy_before := _bytes(store, COPY_NAME)
    assert_true(Array(store.tags_for(KppFixtures.ROUND_NAME)).has(STALE_TAG), "the older import wears the stale tag")

    var results := SaKppImport.import_path(ROUND, store, null, true)
    assert_eq(results.size(), 1, "one preset in the file")
    assert_true(results[0].get("replaced", false), "and it was the one already held")
    assert_eq(Array(store.list_names()), [KppFixtures.ROUND_NAME, COPY_NAME], "one preset of the name, not two")
    assert_almost_eq(_radius(store, KppFixtures.ROUND_NAME), 20.0 / SaKppImport.DOCUMENT_LOWER, 1e-9, "with today's settings")
    assert_eq(
        Array(store.tags_for(KppFixtures.ROUND_NAME)),
        [SaKppImport.IMPORTED_TAG, OWN_TAG],
        "no stale tag, and the painter's own tag kept"
    )
    assert_eq(_bytes(store, COPY_NAME), copy_before, "the copy under another name byte for byte as it was")
    assert_true(SaKppImport.describe(results[0]).contains(" replaced '"), "the line says it replaced one")


func test_an_import_that_does_not_replace_leaves_the_held_preset_alone() -> void:
    var store := _store()
    _older_import(store)
    var before := _bytes(store, KppFixtures.ROUND_NAME)

    var results := SaKppImport.import_path(ROUND, store, null, false)
    assert_eq(results.size(), 1, "one preset in the file")
    assert_eq(results[0].get("kept", ""), KppFixtures.ROUND_NAME, "kept under the name it is held by")
    assert_eq(results[0]["name"], "", "and stored under no name, so the bar selects nothing")
    assert_eq(_bytes(store, KppFixtures.ROUND_NAME), before, "the held file untouched")
    assert_true(
        SaKppImport.describe(results[0]).ends_with(SaKppImport.KEPT_PHRASE), "the line ends as the presets page counts it"
    )


func test_a_first_import_is_neither_kept_nor_replaced() -> void:
    var store := _store()
    var results := SaKppImport.import_path(ROUND, store, null, false)
    assert_eq(results[0]["name"], KppFixtures.ROUND_NAME, "stored when nothing of the name is held")
    assert_false(results[0].has("kept"), "not kept")
    assert_false(results[0].has("replaced"), "and not a replacement")
    assert_true(SaKppImport.describe(results[0]).contains(" imported as '"), "the line as it always was")
