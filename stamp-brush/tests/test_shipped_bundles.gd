## A bundle file a module ships is installed at first run, once, by its
## title.
##
## The bundle is the committed fixture the reader's and the importer's suites
## read, copied into a folder of this suite's own so a bundle a test damages is
## never the one the others read. A suite of its own rather than lines on
## `test_kpp_import.gd`, which is long enough already.
extends "res://tests/test_framework.gd"

const KppFixtures = preload("res://modules/sara-base-modules/stamp-brush/tests/kpp_fixtures.gd")
const SettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")

const FIXTURE := "res://modules/sara-base-modules/stamp-brush/tests/fixtures/sara-fixtures.bundle"
static var scratch_preset_dir: String = SaDataRoot.path("test_shipped_bundles_presets")
static var scratch_module_dir: String = SaDataRoot.path("test_shipped_bundles_module")
# Written out rather than built from `SaShippedBundles.FOLDER`: a `const` whose
# initializer names a global class breaks the class cache.
static var scratch_bundle_dir := scratch_module_dir + "/bundles"
const MODULE_ID := &"test-shipped-bundles"


func before_each() -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(scratch_bundle_dir))
    DirAccess.copy_absolute(ProjectSettings.globalize_path(FIXTURE), ProjectSettings.globalize_path(_bundle()))


func after_each() -> void:
    ModuleLoader.loaded_modules.erase(MODULE_ID)
    ModuleLoader.module_dirs.erase(MODULE_ID)
    for folder: String in [scratch_preset_dir, scratch_bundle_dir, scratch_module_dir]:
        var dir := DirAccess.open(folder)
        if dir == null:
            continue
        for file in dir.get_files():
            dir.remove(file)
        DirAccess.remove_absolute(ProjectSettings.globalize_path(folder))
    for written: String in [
        SaBrushTipMask.saved_dir().path_join(KppFixtures.TIP_FILE),
        SaBrushTipMask.saved_dir().path_join(KppFixtures.SECOND_TIP_FILE),
    ]:
        if FileAccess.file_exists(written):
            DirAccess.remove_absolute(written)


func _bundle() -> String:
    return scratch_bundle_dir.path_join("sara-fixtures.bundle")


func _store() -> SaPresetStore:
    var store := SaPresetStore.new()
    store.dir = scratch_preset_dir
    return store


func _install(store: SaPresetStore) -> int:
    return SaShippedBundles.install(store, SettingsScript.new(), PackedStringArray([_bundle()]))


func test_a_bundle_nobody_was_offered_imports_its_presets_tagged_and_licensed() -> void:
    var store := _store()
    assert_eq(_install(store), 2, "The fixture's two presets are written")
    assert_true(store.has_preset(KppFixtures.ROUND_NAME) and store.has_preset(KppFixtures.PNG_NAME), "both by name")
    assert_true(store.tags_for(KppFixtures.ROUND_NAME).has(SaKppImport.IMPORTED_TAG), "with the tag a hand import gives")
    assert_eq(store.meta_for(KppFixtures.ROUND_NAME, SaKppImport.BUNDLE_META), "Sara fixtures", "the bundle's title")
    assert_eq(store.meta_for(KppFixtures.PNG_NAME, SaKppImport.LICENCE_META), KppFixtures.BUNDLE_LICENCE, "and its licence")
    assert_true(_store().offered(SaShippedBundles.RECORD).has("Sara fixtures"), "and the record is on disk")


## The Done-when's case: a bundle already in the marker is skipped, and what
## makes that worth having is a preset the painter deleted staying deleted.
func test_a_bundle_already_in_the_marker_is_skipped_and_a_deleted_preset_stays_deleted() -> void:
    _install(_store())
    var store := _store()
    assert_true(store.delete_preset(KppFixtures.ROUND_NAME), "The painter deletes one")
    assert_eq(_install(store), 0, "A later start, a store built afresh, writes nothing")
    assert_false(store.has_preset(KppFixtures.ROUND_NAME), "and the deleted one stays deleted")


## A marker written by an earlier start is read by a later one, rather than the
## record only living as long as the store that wrote it.
func test_the_title_in_the_marker_is_what_skips_it() -> void:
    var store := _store()
    _store().record_offered(SaShippedBundles.RECORD, "Sara fixtures")
    assert_eq(_install(store), 0, "A title already recorded is not imported")
    assert_true(store.list_names().is_empty(), "and nothing is written")


## The rule for a recipe held for a bundle: a preset of that name is the
## painter's, so a bundle that arrives later does not write over it.
func test_a_preset_of_the_same_name_is_left_as_the_painter_has_it() -> void:
    var store := _store()
    var own := SettingsScript.new()
    own.radius = 0.25
    store.save_preset(KppFixtures.ROUND_NAME, own, PackedStringArray(["mine"]))
    assert_eq(_install(store), 1, "Only the preset the painter has no copy of is written")
    assert_eq(Array(store.tags_for(KppFixtures.ROUND_NAME)), ["mine"], "and the painter's own keeps its tags")


## A bundle that could not be read is not recorded, so a build that ships the
## file mended offers it.
func test_a_bundle_that_cannot_be_read_is_not_recorded() -> void:
    var broken := scratch_bundle_dir.path_join("broken.bundle")
    var file := FileAccess.open(broken, FileAccess.WRITE)
    file.store_string("not a zip")
    file.close()
    var store := _store()
    assert_eq(SaShippedBundles.install(store, SettingsScript.new(), PackedStringArray([broken])), 0, "Nothing written")
    assert_true(_store().offered(SaShippedBundles.RECORD).is_empty(), "and nothing recorded")


func test_nothing_to_import_into_writes_nothing() -> void:
    assert_eq(SaShippedBundles.install(_store(), null, PackedStringArray([_bundle()])), 0, "No template, no import")
    assert_eq(SaShippedBundles.install(null, SettingsScript.new(), PackedStringArray([_bundle()])), 0, "No store either")


## The folder is found under a loaded module's own directory, and a module the
## loader refused offers nothing, the rule a module's layouts keep.
func test_a_loaded_modules_bundles_folder_is_found() -> void:
    ModuleLoader.module_dirs[MODULE_ID] = scratch_module_dir
    assert_false(SaShippedBundles.module_paths().has(_bundle()), "A folder on disk and no module loaded offers nothing")
    ModuleLoader.loaded_modules[MODULE_ID] = null
    assert_true(SaShippedBundles.module_paths().has(_bundle()), "Loaded, its bundle file is listed")
