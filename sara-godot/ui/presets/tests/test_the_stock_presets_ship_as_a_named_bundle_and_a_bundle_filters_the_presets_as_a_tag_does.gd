## The stock presets ship as a named bundle, and a bundle filters the
## presets as a tag does.
##
## A bundle has a proper name and can be a tag to filter with. The basic
## stock presets are installed into an empty folder and every one reads its
## bundle, Sara Basic or Sara Advanced Paint, its version, author and
## licence. The chooser lists the bundles under a heading of their own, a bundle
## shown only lists that bundle's presets alone, the noise module's with the
## advanced ones, and a bundle hidden leaves them out. A profile that knew the
## bundle as Sara basic keeps its record across the rename.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
const ShippedPresetsScript = preload("res://modules/sara-base-modules/stamp-brush/presets/sa_shipped_presets.gd")
const StampSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")
const NoisePresetsScript = preload("res://modules/sara-noise-brush-engine/presets/noise_presets.gd")
const NoiseBrushSettingsScript = preload("res://modules/sara-noise-brush-engine/noise_brush_settings.gd")

const REQUIRES_GPU := true

const ESSENTIALS: String = ShippedPresetsScript.BASIC

static var scratch_dir: String = SaDataRoot.path("test_bundles")

var _was: Dictionary = {}


func before_each() -> void:
    ScratchFolder.clear(scratch_dir)
    _was = SaSettings.preset_tag_filter.duplicate()
    SaSettings.preset_tag_filter = {}


func after_each() -> void:
    SaSettings.preset_tag_filter = _was
    ScratchFolder.clear(scratch_dir)


## The names of the basic table, the presets Sara Basic holds, sorted.
func _essentials() -> Array[String]:
    var out := ShippedPresetsScript.basic_names()
    out.sort()
    return out


## The names Sara Advanced Paint holds in the store `_store` builds: the rest of
## the stamp brush's and the noise module's shelf, sorted.
func _noise() -> Array[String]:
    var out: Array[String] = []
    for entry: Dictionary in ShippedPresetsScript.entries() + NoisePresetsScript.entries():
        if String(entry["bundle"]) == ShippedPresetsScript.ADVANCED:
            out.append(String(entry["name"]))
    out.sort()
    return out


## A store holding every stock preset of the stamp brush and the noise module's
## shelf, and one the painter saved, which carries no bundle.
func _store() -> SaPresetStore:
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    store.install_shipped(StampSettingsScript.new(), ShippedPresetsScript)
    store.install_shipped(NoiseBrushSettingsScript.new(), NoisePresetsScript)
    store.save_preset("Mine", StampSettingsScript.new())
    return store


func _chooser(store: SaPresetStore) -> SaBrushPresetsChooser:
    var chooser := SaBrushPresetsChooser.new()
    chooser.bind_store(store, StateBrushScript, func() -> Resource: return StampSettingsScript.new())
    return chooser


func _shown(chooser: SaBrushPresetsChooser) -> Array[String]:
    var names := chooser.visible_names()
    names.sort()
    return names


func test_every_essential_preset_reads_the_bundle_its_version_author_and_licence() -> void:
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    store.install_shipped(StampSettingsScript.new(), ShippedPresetsScript)
    assert_eq(ShippedPresetsScript.ENTRIES.size(), 21, "The basic table holds the twenty-one")
    for entry: Dictionary in ShippedPresetsScript.ENTRIES:
        var preset_name := String(entry["name"])
        var bundle := ESSENTIALS if _essentials().has(preset_name) else ShippedPresetsScript.ADVANCED
        var about := String(ShippedPresetsScript.FIELDS[bundle]["bundle_about"])
        var said := store.origin_for(preset_name)
        assert_eq(said[0], bundle, "%s is of %s" % [preset_name, bundle])
        assert_eq(said[1], "GPL-3.0-or-later", "%s carries the bundle's licence" % preset_name)
        assert_eq(said[3], "1.0", "%s carries the bundle's version" % preset_name)
        assert_eq(said[4], "Matěj Zeman", "%s carries the bundle's author" % preset_name)
        assert_eq(said[5], about, "%s carries the bundle's sentence" % preset_name)
        assert_false(about.is_empty(), "The bundle says what it holds in one sentence")
        assert_eq(
            store.provenance_for(preset_name),
            "From %s 1.0 by Matěj Zeman, GPL-3.0-or-later" % bundle,
            "and %s's provenance line says all of it" % preset_name
        )
    for former: String in ShippedPresetsScript.FORMERLY:
        var old_marker := SaPresetLedger.path_for(scratch_dir, former)
        assert_false(FileAccess.file_exists(old_marker), "and nothing is filed under %s" % former)


func test_the_filter_lists_the_bundles_under_a_heading_after_the_tags() -> void:
    var store := _store()
    var chooser := _chooser(store)
    var words: PackedStringArray = chooser.chooser_report()["bundles"]
    var essentials_word := SaBrushPresetTagFilter.bundle_word(ESSENTIALS)
    assert_true(words.has(essentials_word), "Sara Basic is a bundle of the filter, got %s" % [words])
    assert_true(words.has(SaBrushPresetTagFilter.bundle_word(NoisePresetsScript.BUNDLE)), "and so is the noise module's")
    var popup := chooser.tag_option.popup as SaChoicePopup
    # The engines sit under a heading of their own after the bundles.
    assert_eq(popup.section_titles(), ["Bundles", "Engines"] as Array[String], "Bundles, then Engines")
    var labels := popup.row_labels()
    var first_bundle := labels.find(ESSENTIALS)
    assert_true(first_bundle > 0, "Sara Basic is a row of the list, got %s" % [labels])
    for tag: String in store.all_tags():
        assert_true(labels.find(tag) < first_bundle, "The tag %s comes before the bundles" % tag)
    assert_true(chooser.tag_option.visible, "and the filter is drawn while there are bundles to filter by")
    chooser.free()


func test_a_bundle_shown_only_lists_that_bundle_alone() -> void:
    var store := _store()
    var chooser := _chooser(store)
    assert_true(chooser.tag_option.pick_row(ESSENTIALS), "A press on Sara Basic")
    assert_eq(_shown(chooser), _essentials(), "lists the stock presets of Sara Basic and nothing else")
    assert_eq(chooser.tag_option.text, "Tag: Sara Basic", "and the button names the bundle by its title")
    assert_true(chooser.tag_option.pick_row(ESSENTIALS), "A second press")
    var shown := _shown(chooser)
    for preset_name: String in _essentials():
        assert_false(shown.has(preset_name), "hides %s" % preset_name)
    assert_true(shown.has("Mine"), "and leaves the painter's own")
    assert_true(chooser.tag_option.pick_row(ESSENTIALS), "A third press")
    assert_true(SaSettings.preset_tag_filter.is_empty(), "lets the bundle be")
    assert_true(chooser.tag_option.pick_row(NoisePresetsScript.BUNDLE), "A press on the noise bundle")
    assert_eq(_shown(chooser), _noise(), "lists only Sara Advanced Paint's presets, the noise module's among them")
    chooser.free()


func test_a_bundle_and_a_tag_filter_together() -> void:
    var store := _store()
    var chooser := _chooser(store)
    var tag := store.tags_for(_essentials()[0])[0]
    tag_bundle(chooser, tag)
    for preset_name: String in _shown(chooser):
        assert_true(_essentials().has(preset_name), "%s is of Sara Basic" % preset_name)
        assert_true(store.tags_for(preset_name).has(tag), "and carries %s" % tag)
    assert_false(chooser.visible_names().is_empty(), "and some preset passes both")
    chooser.free()


## Shows Sara Basic and the tag *tag* only, each by a press.
func tag_bundle(chooser: SaBrushPresetsChooser, tag: String) -> void:
    assert_true(chooser.tag_option.pick_row(ESSENTIALS), "A press on Sara Basic")
    assert_true(chooser.tag_option.pick_row(tag), "and one on %s" % tag)


func test_a_profile_that_knew_sara_basic_keeps_its_record_under_the_new_name() -> void:
    DirAccess.make_dir_recursive_absolute(scratch_dir)
    var names := _essentials()
    names.erase("Sketch")
    var marker := FileAccess.open(SaPresetLedger.path_for(scratch_dir, ShippedPresetsScript.FORMERLY[1]), FileAccess.WRITE)
    marker.store_string("\n".join(names) + "\nSketch\n")
    marker.close()
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    store.install_shipped(StampSettingsScript.new(), ShippedPresetsScript)
    assert_false(store.has_preset("Sketch"), "Sketch, offered under Sara basic and deleted, stays deleted")
    assert_false(store.has_preset("Paint"), "and so does every other the old record offered")
    assert_true(store.offered(ESSENTIALS).has("Sketch"), "The record is Sara Basic's now")
    assert_true(FileAccess.file_exists(SaPresetLedger.path_for(scratch_dir, ESSENTIALS)), "and filed under its name")
