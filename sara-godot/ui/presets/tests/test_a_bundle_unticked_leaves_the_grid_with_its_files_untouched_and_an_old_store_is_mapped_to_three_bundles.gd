## The stock presets ship as three bundles, a menu in the Brush Presets
## panel loads and unloads a bundle, and a store of the seven old bundles is
## mapped to the three.
##
## The bundles are one for only basic brushes (round, erase), one for filters,
## and one for advanced paint brushes, with a menu to quickly un/load them. Every shelf
## the app installs is installed here into an empty folder: the stamp brush's,
## the noise module's, the filter brush's and liquify's. Unticking Sara Filters
## leaves the grid and the bar's list with none of its presets, every file the
## same bytes, and the tick brings them back. A store whose presets and markers
## carry the seven old names reads the three after one install, and an imported
## bundle keeps its own.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
const ShippedPresetsScript = preload("res://modules/sara-base-modules/stamp-brush/presets/sa_shipped_presets.gd")
const StampSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")
const NoisePresetsScript = preload("res://modules/sara-noise-brush-engine/presets/noise_presets.gd")
const NoiseSettingsScript = preload("res://modules/sara-noise-brush-engine/noise_brush_settings.gd")
const FilterPresetsScript = preload("res://modules/sara-base-modules/filter-brush/presets/filter_brush_presets.gd")
const FilterSettingsScript = preload("res://modules/sara-base-modules/filter-brush/filter_brush_settings.gd")
const LiquifyPresetsScript = preload("res://modules/sara-base-modules/base/liquify/liquify_presets.gd")
const LiquifySettingsScript = preload("res://modules/sara-base-modules/base/liquify/liquify_settings.gd")

const REQUIRES_GPU := true

const BASIC: String = "Sara Basic"
const FILTERS: String = "Sara Filters"
const ADVANCED: String = "Sara Advanced Paint"

## The rounds and erasers Sara Basic holds, the "only basic brushes
## (round, erase)".
const BASIC_NAMES: Array[String] = ["Airbrush", "Eraser", "Fill", "Paint", "Sketch", "Soft Eraser"]

## The seven names the shelves shipped under in the old layout, sorted.
const OLD_NAMES: Array[String] = [
    "Sara Essentials",
    "Sara author",
    "Sara drawn",
    "Sara filter brush",
    "Sara liquify",
    "Sara noise",
    "Sara residency",
]

## A bundle a painter imported, which the mapping leaves as it is.
const IMPORTED: String = "Kit From A Friend"

static var scratch_dir: String = SaDataRoot.path("test_bundles")

var _was: Array = []
var _was_tags: Dictionary = {}


func before_each() -> void:
    ScratchFolder.clear(scratch_dir)
    _was = SaSettings.preset_bundles_off.duplicate()
    _was_tags = SaSettings.preset_tag_filter.duplicate()
    SaSettings.preset_bundles_off = []
    SaSettings.preset_tag_filter = {}


func after_each() -> void:
    SaSettings.preset_bundles_off = _was
    SaSettings.preset_tag_filter = _was_tags
    ScratchFolder.clear(scratch_dir)


## Every shelf the app installs, each with the settings its recipes build on.
func _shelves() -> Array:
    return [
        [StampSettingsScript, ShippedPresetsScript],
        [NoiseSettingsScript, NoisePresetsScript],
        [FilterSettingsScript, FilterPresetsScript],
        [LiquifySettingsScript, LiquifyPresetsScript],
    ]


## Every stock recipe, of every shelf.
func _entries() -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    for shelf: Array in _shelves():
        out.append_array((shelf[1] as Script).call("entries"))
    return out


## A store with every shelf installed into the scratch folder.
func _store() -> SaPresetStore:
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    for shelf: Array in _shelves():
        store.install_shipped((shelf[0] as Script).new(), shelf[1])
    return store


func _chooser(store: SaPresetStore) -> SaBrushPresetsChooser:
    var chooser := SaBrushPresetsChooser.new()
    chooser.bind_store(store, StateBrushScript, func() -> Resource: return StampSettingsScript.new())
    return chooser


## Each preset file of the folder to its digest, so a step that must leave the
## files alone can be held to it.
func _digests() -> Dictionary:
    var out: Dictionary = {}
    for file_name: String in DirAccess.get_files_at(scratch_dir):
        out[file_name] = FileAccess.get_md5(scratch_dir.path_join(file_name))
    return out


## How many preset files the folder holds, the markers left out.
func _preset_files() -> int:
    var count := 0
    for file_name: String in DirAccess.get_files_at(scratch_dir):
        count += 1 if file_name.ends_with(SaPresetStore.EXTENSION) else 0
    return count


## The names of the filter brush's and liquify's shelves.
func _filter_names() -> Array[String]:
    var out: Array[String] = []
    for entry: Dictionary in FilterPresetsScript.entries() + LiquifyPresetsScript.entries():
        out.append(String(entry["name"]))
    return out


func test_a_fresh_store_holds_exactly_the_three_bundles_and_every_stock_preset_is_in_one() -> void:
    var store := _store()
    var bundles := SaBrushPresetBundles.bundles_of(store)
    assert_eq(bundles.keys(), [ADVANCED, BASIC, FILTERS], "Three bundles and no more")
    var basic: Array[String] = []
    for preset_name: String in bundles[BASIC]:
        basic.append(preset_name)
    basic.sort()
    assert_eq(basic, BASIC_NAMES, "Sara Basic is the rounds and the erasers")
    for entry: Dictionary in _entries():
        var preset_name := String(entry["name"])
        assert_true(store.has_preset(preset_name), "%s is installed" % preset_name)
        var bundle := store.origin_for(preset_name)[0]
        assert_true(bundle in [BASIC, FILTERS, ADVANCED], "%s is in one of the three, got %s" % [preset_name, bundle])
    for preset_name: String in _filter_names():
        assert_eq(store.origin_for(preset_name)[0], FILTERS, "%s is of Sara Filters" % preset_name)


func test_every_preset_of_a_bundle_carries_the_bundle_s_one_version_author_and_sentence() -> void:
    var seen: Dictionary = {}
    for entry: Dictionary in _entries():
        var fields := [entry.get("bundle_version"), entry.get("bundle_author"), entry.get("bundle_about")]
        var bundle := String(entry["bundle"])
        assert_false(String(fields[2]).is_empty(), "%s says what its bundle holds" % entry["name"])
        if not seen.has(bundle):
            seen[bundle] = fields
        assert_eq(fields, seen[bundle], "%s carries %s's fields, as every other of it does" % [entry["name"], bundle])
    assert_eq(
        NoisePresetsScript.FIELDS,
        ShippedPresetsScript.FIELDS[ADVANCED],
        "The noise module spells Sara Advanced Paint's fields the same"
    )


func test_unticking_a_bundle_hides_its_presets_and_ticking_it_brings_them_back_with_their_files_untouched() -> void:
    var store := _store()
    var chooser := _chooser(store)
    var popup := chooser.bundle_menu.button.popup
    assert_eq(popup.row_labels(), [ADVANCED, BASIC, FILTERS] as Array[String], "The menu lists the three")
    for title: String in [ADVANCED, BASIC, FILTERS]:
        assert_true(popup.is_checked(StringName(title)), "%s is ticked" % title)
    var before := _digests()
    var everything := chooser.visible_names().size()

    assert_true(popup.press_row(StringName(FILTERS)), "A press on Sara Filters' row")
    assert_eq(SaSettings.preset_bundles_off, [FILTERS], "unticks it in the profile")
    chooser.refresh()
    assert_false(popup.is_checked(StringName(FILTERS)), "and its box is empty")
    var shown := chooser.visible_names()
    for preset_name: String in _filter_names():
        assert_false(shown.has(preset_name), "%s left the grid" % preset_name)
        assert_false(SaBrushPresetBundles.loaded(store, preset_name), "and the bar's list and the search")
        assert_true(store.has_preset(preset_name), "and is still in the store")
    assert_eq(shown.size(), everything - _filter_names().size(), "and every other preset is there")
    assert_true(SaBrushPresetBundles.loaded(store, "Sketch"), "Sketch, of Sara Basic, is still offered")
    assert_eq(_digests(), before, "No file changed")
    assert_false(bool(chooser.chooser_report()["bundle_menu"][FILTERS]["loaded"]), "and the dump says it is unloaded")

    assert_true(popup.press_row(StringName(FILTERS)), "A second press")
    chooser.refresh()
    assert_true(SaSettings.preset_bundles_off.is_empty(), "ticks it again")
    assert_eq(chooser.visible_names().size(), everything, "and every preset is back")
    assert_eq(_digests(), before, "with no file changed")
    chooser.free()


func test_the_bar_s_list_offers_what_the_ticks_leave() -> void:
    var group := ToolOptionsPresets.new()
    group.preset_store.dir = scratch_dir
    _store()
    group.preset_store.forget_tags()
    SaSettings.preset_bundles_off = [FILTERS]
    group.refresh()
    for preset_name: String in _filter_names():
        assert_false(group.preset_names().has(preset_name), "%s is not in the bar's list" % preset_name)
    assert_true(group.preset_names().has("Sketch"), "Sketch is")
    group.free()


func test_a_store_of_the_seven_old_bundles_reads_the_three_after_one_install() -> void:
    _store()
    var formers := _old_store()
    var mine := StampSettingsScript.new()
    mine.radius = 0.2
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    store.save_preset("Kit Round", mine, PackedStringArray(), {SaPresetMeta.BUNDLE_META: IMPORTED})
    var before := _preset_files()
    for shelf: Array in _shelves():
        store.install_shipped((shelf[0] as Script).new(), shelf[1])
    assert_eq(store.origin_for("Kit Round")[0], IMPORTED, "The imported bundle keeps its name")
    for entry: Dictionary in _entries():
        var preset_name := String(entry["name"])
        assert_eq(
            store.origin_for(preset_name)[0],
            String(entry["bundle"]),
            "%s, once of %s, is filed under its new bundle" % [preset_name, formers[preset_name]]
        )
        assert_eq(
            String(store.meta_for(preset_name, SaPresetMeta.BUNDLE_ABOUT_META, "")),
            String(entry["bundle_about"]),
            "and carries its sentence"
        )
    var bundles := SaBrushPresetBundles.bundles_of(store)
    assert_eq(bundles.keys(), [IMPORTED, ADVANCED, BASIC, FILTERS], "Three stock bundles and the imported one")
    assert_eq(_preset_files(), before, "and no preset was written twice or lost")
    assert_true(store.offered(BASIC).has("Sketch"), "Sara Basic's record holds what Sara Essentials offered")
    assert_true(store.offered(FILTERS).has(_filter_names()[0]), "and Sara Filters' what the filter shelves did")


## An old store: Sara Essentials was Sara basic renamed, so both
## records are on disk with the same names, and the basic presets' files still
## say Sara basic. Sara basic's record grows nothing the first name did not, and
## its presets move all the same.
func test_presets_under_a_second_old_name_whose_record_adds_nothing_move_too() -> void:
    _store()
    var formers := _old_store()
    var older := PackedStringArray()
    for preset_name: String in formers:
        if formers[preset_name] != OLD_NAMES[0]:
            continue
        older.append(preset_name)
        var path := scratch_dir.path_join(preset_name + SaPresetStore.EXTENSION)
        var text := FileAccess.get_file_as_string(path)
        var file := FileAccess.open(path, FileAccess.WRITE)
        file.store_string(text.replace('"%s"' % OLD_NAMES[0], '"%s"' % ShippedPresetsScript.FORMERLY[1]))
        file.close()
    older.sort()
    var marker := FileAccess.open(SaPresetLedger.path_for(scratch_dir, ShippedPresetsScript.FORMERLY[1]), FileAccess.WRITE)
    marker.store_string("\n".join(older) + "\n")
    marker.close()
    assert_false(older.is_empty(), "Some presets are filed under Sara basic")
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    for shelf: Array in _shelves():
        store.install_shipped((shelf[0] as Script).new(), shelf[1])
    for entry: Dictionary in _entries():
        var preset_name := String(entry["name"])
        if older.has(preset_name):
            assert_eq(store.origin_for(preset_name)[0], String(entry["bundle"]), "%s leaves Sara basic" % preset_name)
    var bundles := SaBrushPresetBundles.bundles_of(store)
    assert_eq(bundles.keys(), [ADVANCED, BASIC, FILTERS], "Only the three stock bundles are left")


## Turns the installed folder into one the seven old bundles wrote: each stock
## preset's bundle line is the name its shelf had, and the markers are the old
## names'. Answers each preset's old bundle by name.
func _old_store() -> Dictionary:
    var formers: Dictionary = {}
    var offered: Dictionary = {}
    for entry: Dictionary in _entries():
        var former := String(SaPresetBundleMap.formers_of(entry)[0])
        var preset_name := String(entry["name"])
        formers[preset_name] = former
        var names: PackedStringArray = offered.get(former, PackedStringArray())
        names.append(preset_name)
        offered[former] = names
        var path := scratch_dir.path_join(preset_name + SaPresetStore.EXTENSION)
        var text := FileAccess.get_file_as_string(path)
        var line := RegEx.create_from_string('metadata/bundle = "[^"]*"')
        var file := FileAccess.open(path, FileAccess.WRITE)
        file.store_string(line.sub(text, 'metadata/bundle = "%s"' % former))
        file.close()
    var olds: Array[String] = []
    olds.assign(offered.keys())
    olds.sort()
    assert_eq(olds, OLD_NAMES, "The shelves name the seven old bundles")
    for title: String in [BASIC, FILTERS, ADVANCED]:
        var marker := SaPresetLedger.path_for(scratch_dir, title)
        assert_true(FileAccess.file_exists(marker), "%s has a marker to take away" % title)
        DirAccess.remove_absolute(marker)
        DirAccess.remove_absolute(marker.get_basename() + SaPresetLedger.WRITTEN_SUFFIX)
    for former: String in offered:
        var marker := FileAccess.open(SaPresetLedger.path_for(scratch_dir, former), FileAccess.WRITE)
        marker.store_string("\n".join(offered[former]) + "\n")
        marker.close()
    return formers
