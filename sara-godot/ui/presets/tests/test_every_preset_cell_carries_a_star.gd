## Every preset cell carries a star, and the grid filters by it.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## "some star or heart that you can always click and then filter",
## over a store of the shipped presets. An outline on every cell, a filled star
## once clicked, and the click loading nothing. The Starred filter alone, with
## a tag, and disabled with nothing starred. The cell pitch and the column count
## the stars leave alone, a foreign cell's star at full strength, and a second
## chooser following a star made in the first. The profile's list is put back
## after each test, and a chooser out of the tree is found hearing none of it.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
const BrushSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/tools/brush_settings.gd")
const ShippedPresetsScript = preload("res://modules/sara-base-modules/stamp-brush/presets/sa_shipped_presets.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")
const StampSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")
const PresetEngineMarks := preload("res://ui/dockers/presets/preset_engine_marks.gd")
const ControlWalker := preload("res://harness/controls/sa_control_walker.gd")

## A cell's picture is a rendered stroke through the real paint path.
const REQUIRES_GPU := true

static var scratch_dir: String = SaDataRoot.path("test_p2_preset_stars")

var _was: Array = []
var _saved_icon_size: int = 48

## The profile's tag filter as it stood, put back after each test, since a press
## on a tag writes it for every chooser after this one.
var _tag_filter_was: Dictionary = {}


func before_each() -> void:
    _tag_filter_was = SaSettings.preset_tag_filter.duplicate()
    SaSettings.preset_tag_filter = {}
    _was = SaSettings.preset_favorites
    _saved_icon_size = SaSettings.preset_icon_size
    SaSettings.preset_favorites = []
    ScratchFolder.clear(scratch_dir)


func after_each() -> void:
    SaSettings.preset_tag_filter = _tag_filter_was
    SaSettings.preset_favorites = _was
    SaSettings.preset_icon_size = _saved_icon_size
    ScratchFolder.clear(scratch_dir)


func _store(settings_script: GDScript = BrushSettingsScript) -> SaPresetStore:
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    store.install_shipped(settings_script.new(), ShippedPresetsScript)
    return store


## A chooser in the tree, under `EventBus` as every suite parks one, because a
## chooser hears the profile's stars while it is in the tree and only then.
func _chooser(store: SaPresetStore) -> SaBrushPresetsChooser:
    var chooser := SaBrushPresetsChooser.new()
    chooser.bind_store(store, StateBrushScript, func() -> Resource: return BrushSettingsScript.new())
    EventBus.add_child(chooser)
    return chooser


func _cell(chooser: SaBrushPresetsChooser, preset_name: String) -> Control:
    for child: Node in chooser.grid.get_children():
        if (child.get_node("Name") as Label).text == preset_name:
            return child as Control
    return null


func _star_icon(chooser: SaBrushPresetsChooser, preset_name: String) -> Texture2D:
    var star := chooser.stars.star_of(preset_name)
    return star.icon if star != null else null


func test_every_cell_carries_an_outline_star() -> void:
    var chooser := _chooser(_store())
    var outline := SaUI.get_icon("star_outline")
    assert_not_null(outline, "The outline star ships")
    for preset_name: String in chooser.visible_names():
        var star := chooser.stars.star_of(preset_name)
        assert_not_null(star, "%s carries a star" % preset_name)
        assert_eq(star.icon, outline, "%s's is an outline while it is not starred" % preset_name)
        assert_eq(star.get_parent().name, "Icon", "drawn on the picture")
        assert_eq(star.mouse_filter, Control.MOUSE_FILTER_STOP, "taking the press, so the picture never hears it")
        assert_false(star.disabled, "always clickable")
        assert_eq(star.modulate.a, 1.0, "at full strength")
        assert_false(star.tooltip_text.is_empty(), "with a tooltip saying what a click does")
    chooser.free()


func test_a_click_stars_the_preset_and_loads_nothing() -> void:
    var chooser := _chooser(_store())
    var chosen: Array[String] = []
    chooser.preset_chosen.connect(func(preset_name: String) -> void: chosen.append(preset_name))
    chooser.stars.star_of("Sketch").pressed.emit()
    assert_true(SaSettings.preset_favorites.has("Sketch"), "The click stars the preset in the profile")
    assert_eq(_star_icon(chooser, "Sketch"), SaUI.get_icon("star"), "and its cell shows a filled star")
    assert_eq(_star_icon(chooser, "Paint"), SaUI.get_icon("star_outline"), "while the others stay outlines")
    assert_eq(chosen.size(), 0, "and the preset is not loaded")
    chooser.stars.star_of("Sketch").pressed.emit()
    assert_false(SaSettings.preset_favorites.has("Sketch"), "A second click unstars it")
    assert_eq(_star_icon(chooser, "Sketch"), SaUI.get_icon("star_outline"), "back to an outline")
    chooser.free()


func test_the_filter_lists_the_starred_alone() -> void:
    var chooser := _chooser(_store())
    SaSettings.preset_favorites = ["Fill", "Sketch"]
    chooser.stars.capture_filter(true)
    assert_true(chooser.stars.starred_only, "The filter is on")
    assert_eq(chooser.visible_names(), ["Fill", "Sketch"] as Array[String], "and the grid lists the starred alone")
    chooser.stars.capture_filter(false)
    assert_eq(chooser.visible_names().size(), 3, "and off lists them all")
    chooser.free()


func test_the_filter_combines_with_the_tag_and_the_search() -> void:
    var chooser := _chooser(_store())
    SaSettings.preset_favorites = ["Fill", "Sketch"]
    chooser.stars.capture_filter(true)
    chooser.capture_tag("paint")
    assert_eq(chooser.visible_names(), ["Fill"] as Array[String], "Starred and tagged paint is Fill alone")
    chooser.capture_tag("")
    ControlWalker.move(chooser.search_field, "sk")
    assert_eq(chooser.visible_names(), ["Sketch"] as Array[String], "and starred matching 'sk' is Sketch")
    chooser.free()


func test_the_filter_is_disabled_while_nothing_is_starred() -> void:
    var chooser := _chooser(_store())
    assert_true(chooser.stars.filter.disabled, "Nothing starred, the filter is disabled")
    assert_true(chooser.stars.filter.tooltip_text.contains("Nothing is starred"), "with a tooltip saying why")
    assert_true(chooser.stars.filter.is_inside_tree() or chooser.stars.filter.get_parent() != null, "and it is still shown")
    SaSettings.preset_favorites = ["A Name The Store Does Not Hold"]
    assert_true(chooser.stars.filter.disabled, "a star on a name the store lacks does not count")
    chooser.stars.star_of("Paint").pressed.emit()
    assert_false(chooser.stars.filter.disabled, "one star and it can be pressed")
    chooser.stars.capture_filter(true)
    assert_eq(chooser.visible_names(), ["Paint"] as Array[String], "the filter on lists it")
    chooser.stars.star_of("Paint").pressed.emit()
    assert_false(chooser.stars.starred_only, "unstarring the last one turns the filter off")
    assert_true(chooser.stars.filter.disabled, "and disables it")
    assert_eq(chooser.visible_names().size(), 3, "rather than leaving an empty grid")
    chooser.free()


func test_the_stars_leave_the_pitch_and_the_columns_alone() -> void:
    var host := VBoxContainer.new()
    host.custom_minimum_size = Vector2(float(SaUI.px(300)), 0.0)
    host.size = Vector2(float(SaUI.px(300)), 400.0)
    var chooser := SaBrushPresetsChooser.new()
    chooser.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    host.add_child(chooser)
    chooser.bind_store(_store(), StateBrushScript, func() -> Resource: return BrushSettingsScript.new())
    for icon: int in [SaBrushPresetsChooser.MIN_ICON, 48, SaBrushPresetsChooser.MAX_ICON]:
        SaSettings.preset_icon_size = icon
        chooser.refresh()
        var with_stars: Array = []
        for child: Node in chooser.grid.get_children():
            with_stars.append((child as Control).get_combined_minimum_size())
        var columns := chooser.grid.columns
        for preset_name: String in chooser.visible_names():
            var star := chooser.stars.star_of(preset_name)
            star.get_parent().remove_child(star)
            star.free()
        var without: Array = []
        for child: Node in chooser.grid.get_children():
            without.append((child as Control).get_combined_minimum_size())
        assert_eq(with_stars, without, "At %d the cells ask for the same room with their stars as without" % icon)
        chooser.resized.emit()
        assert_eq(chooser.grid.columns, columns, "and the grid counts the same columns")
    host.free()


func test_the_star_reads_at_the_smallest_icon() -> void:
    SaSettings.preset_icon_size = SaBrushPresetsChooser.MIN_ICON
    var chooser := _chooser(_store())
    var star := chooser.stars.star_of("Paint")
    var picture := star.get_parent() as Button
    var side := float(SaUI.px(SaBrushPresetStars.STAR_SIZE))
    assert_eq(star.offset_right - star.offset_left, side, "The star is its logical size, scaled by the one writer")
    assert_true(side <= picture.custom_minimum_size.y, "and fits inside the picture's height at the smallest icon")
    chooser.free()


func test_a_foreign_cells_star_stays_at_full_strength() -> void:
    var store := _store(StampSettingsScript)
    var chooser := SaBrushPresetsChooser.new()
    var marks := PresetEngineMarks.new(chooser, func() -> SaPresetStore: return store, func() -> StringName: return &"noise")
    chooser.bind_store(store, StateBrushScript, func() -> Resource: return StampSettingsScript.new())
    for cell: Node in chooser.grid.get_children():
        marks.mark(cell)
    var cell := _cell(chooser, "Sketch")
    var picture := cell.get_node("Icon") as Button
    assert_true(picture.self_modulate.a < 1.0, "A stamp preset under a noise tool has its picture dimmed")
    assert_true((cell.get_node("Name") as Control).modulate.a < 1.0, "and its name")
    assert_eq(cell.modulate.a, 1.0, "but not the cell")
    assert_eq(picture.modulate.a, 1.0, "nor anything the picture carries")
    assert_eq(chooser.stars.star_of("Sketch").modulate.a, 1.0, "so its star is at full strength")
    assert_true(bool((marks.report()["cells"] as Dictionary)["Sketch"]["dimmed"]), "and the report still says dimmed")
    chooser.free()


func test_a_chooser_out_of_the_tree_hears_no_profile_load() -> void:
    var chooser := SaBrushPresetsChooser.new()
    chooser.bind_store(_store(), StateBrushScript, func() -> Resource: return BrushSettingsScript.new())
    var rebuilt: Array[int] = [0]
    chooser.stars.changed.connect(func() -> void: rebuilt[0] += 1)
    SaSettings.preset_favorites = ["Fill"]
    assert_eq(rebuilt[0], 0, "A chooser no host has shown rebuilds nothing when the profile moves")
    chooser.stars.star_of("Paint").pressed.emit()
    assert_eq(rebuilt[0], 1, "but its own star still rebuilds it once")
    assert_eq(_star_icon(chooser, "Paint"), SaUI.get_icon("star"), "filled")
    chooser.free()


func test_a_profile_load_that_moves_no_star_rebuilds_nothing() -> void:
    var chooser := _chooser(_store())
    var rebuilt: Array[int] = [0]
    chooser.stars.changed.connect(func() -> void: rebuilt[0] += 1)
    SaSettings.preset_favorites = []
    assert_eq(rebuilt[0], 0, "Writing the same stars again rebuilds no grid")
    chooser.free()


func test_a_second_chooser_follows_a_star_made_in_the_first() -> void:
    var store := _store()
    var first := _chooser(store)
    var second := _chooser(store)
    first.stars.star_of("Fill").pressed.emit()
    assert_eq(_star_icon(second, "Fill"), SaUI.get_icon("star"), "The other host's cell is filled too")
    assert_false(second.stars.filter.disabled, "and its filter can be pressed")
    assert_eq((second.chooser_report()["stars"] as Dictionary)["starred"], ["Fill"], "and its report names the star")
    first.free()
    second.free()
