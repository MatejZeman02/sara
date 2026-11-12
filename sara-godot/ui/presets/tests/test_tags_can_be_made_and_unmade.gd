## Making and unmaking a preset's tags: the store's four writes, and the
## chooser's gesture over them.
##
## The note is "missing option to delete/assing/rename tags", against a filter
## row that could only ever say All, so the claims here are that each of the
## three acts reaches the file on disk and that the row offering them follows.
##
## Two halves, on purpose. The store half writes and reads back through
## `tags_for`, which is what the dropdown asks, and re-reads with the cache
## dropped, which is what a fresh session asks: a tag that only lives in the
## cache would pass the first and fail the second.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
const BrushSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/tools/brush_settings.gd")
## The recipes the brush ships, and the rule about which of them a template
## can carry, out of `core/`. Handed to `install_shipped`
## because a test machine holds no registries to ask for the role.
const ShippedPresetsScript = preload("res://modules/sara-base-modules/stamp-brush/presets/sa_shipped_presets.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")

## A cell's picture is a rendered stroke through the real paint path, and the
## chooser half builds cells.
const REQUIRES_GPU := true

## Never the real `user://brush_presets`, for `test_brush_presets.gd`'s reason:
## a suite that wrote there would tag a painter's own library.
static var scratch_dir: String = SaDataRoot.path("test_o4_tags")

## The profile's tag filter as it stood, put back after each test, since a press
## on a tag writes it for every chooser after this one.
var _tag_filter_was: Dictionary = {}


func before_each() -> void:
    _tag_filter_was = SaSettings.preset_tag_filter.duplicate()
    SaSettings.preset_tag_filter = {}
    ScratchFolder.clear(scratch_dir)


func after_each() -> void:
    SaSettings.preset_tag_filter = _tag_filter_was
    ScratchFolder.clear(scratch_dir)


## A store holding the three presets Sara ships, which are tagged already.
func _store() -> SaPresetStore:
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    store.install_shipped(BrushSettingsScript.new(), ShippedPresetsScript)
    return store


## The tags on disk, read with the cache dropped, which is what a fresh session
## would see.
func _tags_on_disk(store: SaPresetStore, preset_name: String) -> Array:
    store.forget_tags()
    return Array(store.tags_for(preset_name))


func test_a_tag_is_assigned_and_unassigned_on_one_preset() -> void:
    var store := _store()
    assert_true(store.assign_tag("Sketch", "wet"), "Assigning a tag the preset lacks writes")
    assert_false(store.assign_tag("Sketch", "wet"), "and assigning it again writes nothing")
    assert_eq(_tags_on_disk(store, "Sketch"), ["lines", "wet"], "The tag is on the file, sorted")
    assert_eq(_tags_on_disk(store, "Paint"), ["paint"], "and only on the preset it was put on")

    assert_true(store.unassign_tag("Sketch", "wet"), "Unassigning it writes")
    assert_false(store.unassign_tag("Sketch", "wet"), "and unassigning it again writes nothing")
    assert_eq(_tags_on_disk(store, "Sketch"), ["lines"], "and the file is back to what it shipped with")


## The last tag off a preset erases the key rather than leaving an empty array,
## so an untagged preset reads like one that was never tagged.
func test_the_last_tag_off_a_preset_leaves_no_tags_at_all() -> void:
    var store := _store()
    store.unassign_tag("Sketch", "lines")
    assert_eq(_tags_on_disk(store, "Sketch"), [], "No tags left")
    assert_false(store.all_tags().has("lines"), "and the library stops offering the one nothing carries")
    assert_true(store.has_preset("Sketch"), "The preset itself is untouched")


func test_a_rename_moves_every_preset_that_carries_the_tag() -> void:
    var store := _store()
    assert_eq(store.rename_tag("paint", "colour"), 2, "Both carriers are rewritten")
    assert_eq(_tags_on_disk(store, "Paint"), ["colour"], "Paint carries the new word")
    assert_eq(_tags_on_disk(store, "Fill"), ["colour"], "and so does Fill")
    assert_false(store.all_tags().has("paint"), "The old word is gone from the library")
    assert_eq(store.rename_tag("nothing-carries-this", "x"), 0, "A tag nobody carries moves nothing")
    assert_eq(store.rename_tag("colour", "colour"), 0, "and renaming a tag onto itself is not a write")


## A rename onto a tag that already exists merges rather than duplicating, which
## is the one case a set can get wrong and the one the record has to say.
func test_a_rename_onto_an_existing_tag_merges() -> void:
    var store := _store()
    store.assign_tag("Paint", "soft")
    store.assign_tag("Paint", "wet")
    assert_eq(store.rename_tag("soft", "wet"), 1, "The one preset carrying both is rewritten")
    assert_eq(_tags_on_disk(store, "Paint"), ["paint", "wet"], "and comes out with one wet rather than two")


func test_a_deleted_tag_leaves_the_presets_alone() -> void:
    var store := _store()
    store.assign_tag("Paint", "soft")
    store.assign_tag("Fill", "hard")
    assert_eq(store.delete_tag("paint"), 2, "Both carriers are rewritten")
    assert_eq(_tags_on_disk(store, "Paint"), ["soft"], "Paint keeps its other tag")
    assert_eq(_tags_on_disk(store, "Fill"), ["hard"], "and so does Fill")
    assert_true(store.has_preset("Paint") and store.has_preset("Fill"), "Both presets are still there")
    assert_eq(store.delete_tag("paint"), 0, "and deleting it again writes nothing")


## A tag is metadata inside a file rather than a file name, so it keeps the
## punctuation a preset name would lose, and only its blank is tidied.
func test_a_tag_keeps_what_a_preset_name_would_lose() -> void:
    assert_eq(SaPresetStore.sanitize_tag("  inks / wet  "), "inks / wet", "The edges go and the slash stays")
    assert_eq(SaPresetStore.sanitize_tag("two   words"), "two words", "An inner run of blank is one space")
    assert_eq(SaPresetStore.sanitize_tag("   "), "", "and blank alone is no tag")

    var store := _store()
    assert_true(store.assign_tag("Sketch", " inks / wet "), "A tag with punctuation is written")
    assert_true(_tags_on_disk(store, "Sketch").has("inks / wet"), "and comes back as the words that were typed")


## A tag write leaves everything else in the file where it was, which is what a
## Krita import's licence and source file depend on.
func test_a_tag_write_keeps_the_rest_of_the_file() -> void:
    var store := _store()
    var settings := BrushSettingsScript.new()
    settings.radius = 0.077
    store.save_preset("Imported", settings, PackedStringArray(["krita"]), {&"licence": "CC0", &"source": "bundle.bundle"})
    store.assign_tag("Imported", "wet")

    assert_eq(_tags_on_disk(store, "Imported"), ["krita", "wet"], "The tag landed")
    assert_eq(store.meta_for("Imported", &"licence", ""), "CC0", "and the licence beside it is still there")
    assert_eq(store.meta_for("Imported", &"source", ""), "bundle.bundle", "and so is the file it came from")
    var restored := BrushSettingsScript.new()
    store.apply_preset("Imported", restored)
    assert_almost_eq(restored.radius, 0.077, 0.00001, "and the brush the preset describes is unchanged")


# --- The chooser's gesture over it ---------------------------------------------


func _chooser() -> SaBrushPresetsChooser:
    var chooser := SaBrushPresetsChooser.new()
    chooser.bind_store(_store(), StateBrushScript, func() -> Resource: return BrushSettingsScript.new())
    return chooser


## The menu offers every tag in the library, ticked where this preset carries it.
func test_the_cell_menu_ticks_the_tags_the_preset_carries() -> void:
    var chooser := _chooser()
    chooser.tags.open_menu_for("Sketch", null)
    var report := chooser.tags.tags_report()
    assert_eq(
        report["menu_rows"],
        ["New Preset...", "lines", "paint", "New tag..."],
        "New preset... at the head, every tag, and the way to a new one"
    )
    assert_eq(report["ticked"], ["lines"] as Array[String], "ticked on the one Sketch carries")
    chooser.queue_free()


## A tick writes at once rather than on a close, because a popup clicked away
## from never answers.
func test_a_tick_writes_the_library_and_the_grid_follows() -> void:
    var chooser := _chooser()
    chooser.tags.open_menu_for("Sketch", null)
    assert_true(chooser.tags.menu.press_check(&"paint"), "The row takes a tick")
    assert_true(chooser.store.tags_for("Sketch").has("paint"), "and the preset carries it at once")

    chooser.capture_tag("paint")
    assert_eq(chooser.visible_names(), ["Fill", "Paint", "Sketch"] as Array[String], "so the filter now finds three")
    chooser.queue_free()


## The New tag row opens the field, and Enter writes what was typed.
func test_a_new_tag_is_typed_into_the_field() -> void:
    var chooser := _chooser()
    chooser.tags.open_menu_for("Fill", null)
    assert_false(chooser.tags.naming(), "Nothing is being typed before the row is pressed")
    assert_true(chooser.tags.menu.press_row(SaBrushPresetTags.NEW_TAG_ID), "The row presses")
    assert_true(chooser.tags.naming(), "and the field is open")
    assert_true(chooser.tags.field.visible, "and visible")

    chooser.tags.field.text = "wash"
    assert_true(chooser.tags.commit(), "Enter writes it")
    assert_false(chooser.tags.naming(), "and closes the field")
    assert_true(chooser.store.tags_for("Fill").has("wash"), "The preset carries the new tag")
    chooser.queue_free()


## An empty name writes nothing, and Escape throws away what was typed.
func test_an_empty_name_and_an_escape_both_write_nothing() -> void:
    var chooser := _chooser()
    chooser.tags.open_menu_for("Fill", null)
    chooser.tags.menu.press_row(SaBrushPresetTags.NEW_TAG_ID)
    chooser.tags.field.text = "   "
    assert_false(chooser.tags.commit(), "Blank is not a tag")
    assert_eq(Array(chooser.store.tags_for("Fill")), ["paint"], "so nothing was written")

    chooser.tags.open_menu_for("Fill", null)
    chooser.tags.menu.press_row(SaBrushPresetTags.NEW_TAG_ID)
    chooser.tags.field.text = "wash"
    chooser.tags.cancel()
    assert_false(chooser.tags.naming(), "Escape closes the field")
    assert_eq(Array(chooser.store.tags_for("Fill")), ["paint"], "and writes nothing either")
    chooser.queue_free()


## The two acts are on the dropdown only while a tag is being filtered by, and
## the filter follows a rename rather than dropping back to All.
func test_the_dropdown_offers_the_acts_and_the_filter_follows_a_rename() -> void:
    var chooser := _chooser()
    assert_false(chooser.tag_option.choice_values().has(SaBrushPresetsChooser.TAG_RENAME_ID), "All offers no rename")

    chooser.capture_tag("paint")
    assert_true(chooser.tag_option.choice_values().has(SaBrushPresetsChooser.TAG_RENAME_ID), "A chosen tag offers one")
    assert_true(chooser.tag_option.choice_values().has(SaBrushPresetsChooser.TAG_DELETE_ID), "and a delete")

    assert_true(chooser.tag_option.pick_row(tr("Rename tag...")), "The row presses")
    assert_true(chooser.tags.naming(), "and the field opens")
    assert_eq(chooser.tags.field.text, "paint", "seeded with the tag being renamed")
    chooser.tags.field.text = "colour"
    assert_true(chooser.tags.commit(), "Enter renames it")
    assert_eq(chooser.chooser_report()["tag"], "colour", "and the filter follows the new word")
    assert_eq(chooser.visible_names(), ["Fill", "Paint"] as Array[String], "over the same two presets")
    chooser.queue_free()


## The capture door drives the same gesture a hand does, which is what the
## scenario leans on.
func test_the_capture_door_opens_ticks_and_names() -> void:
    var chooser := _chooser()
    var report := chooser.capture_tags({"menu": "Sketch", "tick": "paint", "on": true})
    assert_true(Array(report["ticked"]).has("paint"), "The door ticks a row")
    assert_true(chooser.store.tags_for("Sketch").has("paint"), "and the write reaches the file")

    chooser.capture_tags({"menu": "Sketch", "new": "wash"})
    assert_true(chooser.store.tags_for("Sketch").has("wash"), "and types a new tag")

    chooser.capture_tag("wash")
    chooser.capture_tags({"rename": "washes"})
    assert_true(chooser.store.tags_for("Sketch").has("washes"), "and renames the one being filtered by")
    assert_eq(chooser.chooser_report()["tag"], "washes", "with the filter following")
    chooser.queue_free()
