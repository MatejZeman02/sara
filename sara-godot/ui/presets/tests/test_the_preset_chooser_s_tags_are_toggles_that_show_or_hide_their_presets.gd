## The preset chooser's tags are toggles that show or hide their presets.
##
## The tags system is toggleable, so it
## acts as a filter, and a painter can filter out all filter brushes, all sketch
## brushes and so on. Presets are tagged Sketch and Filter, Filter is hidden, Sketch
## is shown only with Filter hidden, the profile is written and read back as a
## restart reads it, and one press clears the tags.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
const BrushSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/tools/brush_settings.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")

const REQUIRES_GPU := true

static var scratch_dir: String = SaDataRoot.path("test_tags")
static var scratch_path: String = SaDataRoot.path("test_tags.cfg")

var _was: Dictionary = {}


func before_each() -> void:
    ScratchFolder.remove_saved(scratch_path)
    ScratchFolder.clear(scratch_dir)
    _was = SaSettings.preset_tag_filter.duplicate()
    SaSettings.preset_tag_filter = {}


func after_each() -> void:
    SaSettings.preset_tag_filter = _was
    ScratchFolder.remove_saved(scratch_path)
    ScratchFolder.clear(scratch_dir)


## Four presets: two sketches, one of them a filter as well, one filter alone and
## one carrying neither.
func _store() -> SaPresetStore:
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    store.save_preset("Pencil", BrushSettingsScript.new(), PackedStringArray(["Sketch"]))
    store.save_preset("Liner", BrushSettingsScript.new(), PackedStringArray(["Sketch", "Filter"]))
    store.save_preset("Blur", BrushSettingsScript.new(), PackedStringArray(["Filter"]))
    store.save_preset("Round", BrushSettingsScript.new())
    return store


func _chooser(store: SaPresetStore) -> SaBrushPresetsChooser:
    var chooser := SaBrushPresetsChooser.new()
    chooser.bind_store(store, StateBrushScript, func() -> Resource: return BrushSettingsScript.new())
    return chooser


## Presses the row of *tag* in the tag list *times* times, as a hand does.
func _press(chooser: SaBrushPresetsChooser, tag: String, times: int = 1) -> void:
    for i in times:
        assert_true(chooser.tag_option.pick_row(tag), "The row %s takes press %d" % [tag, i + 1])


func _shown(chooser: SaBrushPresetsChooser) -> Array[String]:
    var names := chooser.visible_names()
    names.sort()
    return names


func _carrying(chooser: SaBrushPresetsChooser, tag: String) -> Array[String]:
    var out: Array[String] = []
    for shown_name: String in chooser.visible_names():
        if chooser.store.tags_for(shown_name).has(tag):
            out.append(shown_name)
    return out


## The row of *tag*'s mark in the open list.
func _icon_of(chooser: SaBrushPresetsChooser, tag: String) -> String:
    var row := chooser.tag_option.popup.row_of(SaChoiceButton.row_id_of(tag))
    return row.icon_name if row != null else "<no row>"


func test_a_click_cycles_a_tag_from_off_to_show_only_to_hide_and_back() -> void:
    var chooser := _chooser(_store())
    assert_eq(_shown(chooser), ["Blur", "Liner", "Pencil", "Round"] as Array[String], "No tag on lists every preset")
    _press(chooser, "Filter")
    assert_eq(chooser.chooser_report()["tag_filter"], {"Filter": "show"}, "One press shows only Filter")
    assert_eq(_shown(chooser), ["Blur", "Liner"] as Array[String], "over the presets carrying it")
    _press(chooser, "Filter")
    assert_eq(chooser.chooser_report()["tag_filter"], {"Filter": "hide"}, "A second press hides it")
    assert_eq(_carrying(chooser, "Filter"), [] as Array[String], "and no Filter preset is shown")
    assert_eq(_shown(chooser), ["Pencil", "Round"] as Array[String], "while every other one is")
    assert_eq(_icon_of(chooser, "Filter"), "guivisibilityhidden", "The hidden row carries the crossed eye")
    _press(chooser, "Filter")
    assert_eq(chooser.chooser_report()["tag_filter"], {}, "A third press turns it off")
    assert_eq(_shown(chooser).size(), 4, "and every preset is back")
    assert_eq(_icon_of(chooser, "Filter"), "", "with no mark on the row")
    chooser.free()


func test_sketch_shown_only_with_filter_hidden_lists_the_sketches_without_filter() -> void:
    var chooser := _chooser(_store())
    _press(chooser, "Filter", 2)
    _press(chooser, "Sketch")
    assert_eq(chooser.chooser_report()["tag_filter"], {"Filter": "hide", "Sketch": "show"}, "Two tags are on at once")
    assert_eq(_shown(chooser), ["Pencil"] as Array[String], "The Sketch presets without Filter, Liner left out")
    assert_eq(_icon_of(chooser, "Sketch"), "guivisibilityvisible", "The row shown only carries the open eye")
    assert_eq(_icon_of(chooser, "Filter"), "guivisibilityhidden", "and the hidden one the crossed eye")
    assert_eq(chooser.tag_option.text, "Tags: not Filter, Sketch", "The closed button names both")
    chooser.free()


## The profile is written through its file and read into a fresh set of values,
## which is what a restart does, and a chooser built afterwards reads the same.
func test_the_tags_survive_a_restart() -> void:
    var store := _store()
    var chooser := _chooser(store)
    _press(chooser, "Filter", 2)
    _press(chooser, "Sketch")
    chooser.free()

    var file := SaSettingsFile.new()
    file.settings_path = ProjectSettings.globalize_path(scratch_path)
    var values := SaSettingsValues.new()
    file.load_from_disk(values)
    values.preset_tag_filter = SaSettings.preset_tag_filter
    file.write(&"preset_tag_filter", values.stored("preset_tag_filter"))
    values.free()
    assert_eq(SaSettingsValues.place_of(&"preset_tag_filter"), ["tools", "preset_tag_filter"], "kept with the presets")

    var again_file := SaSettingsFile.new()
    again_file.settings_path = ProjectSettings.globalize_path(scratch_path)
    var again := SaSettingsValues.new()
    again_file.load_from_disk(again)
    assert_eq(again.preset_tag_filter, {"Filter": "hide", "Sketch": "show"}, "The profile reads the tags back")
    SaSettings.preset_tag_filter = {}
    SaSettings.preset_tag_filter = again.preset_tag_filter
    again.free()

    var restarted := _chooser(store)
    assert_eq(_shown(restarted), ["Pencil"] as Array[String], "and the chooser after the restart lists the same")
    restarted.free()


func test_a_filter_that_leaves_nothing_names_its_tags_and_one_press_clears_them() -> void:
    var chooser := _chooser(_store())
    _press(chooser, "Sketch")
    _press(chooser, "Filter")
    chooser.search_field.text = "Pencil"
    chooser.refresh()
    assert_eq(chooser.visible_names(), [] as Array[String], "Sketch and Filter both shown only, over Pencil, leave nothing")
    var line := String(chooser.chooser_report()["tags_empty_line"])
    assert_true(line.contains("Sketch") and line.contains("Filter"), "The line names the tags that are on: %s" % line)
    assert_true(chooser.tag_filter.empty_box.visible, "on the line that holds its press")
    chooser.tag_filter.clear_button.pressed.emit()
    assert_eq(chooser.chooser_report()["tag_filter"], {}, "One press clears every tag")
    assert_eq(SaSettings.preset_tag_filter, {}, "in the profile as well")
    assert_eq(chooser.visible_names(), ["Pencil"] as Array[String], "and the search alone is left")
    chooser.free()


func test_the_all_row_clears_them_too() -> void:
    var chooser := _chooser(_store())
    _press(chooser, "Sketch")
    _press(chooser, "Filter", 2)
    assert_true(chooser.tag_option.pick_row(tr("All")), "The All row takes the press")
    assert_eq(chooser.chooser_report()["tag_filter"], {}, "and turns every tag off")
    assert_eq(chooser.tag_option.text, "Tag: All", "so the button reads All")
    chooser.free()
