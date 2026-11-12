## The preset chooser's header names its controls.
##
## The header was a search field, a slider with no label, a dropdown reading All,
## a star and a dropdown reading Strokes, three of them learned by trying. So
## the claims are that the size control is the kit's slider with its word in
## its bar and still sizes the cells, that the tag dropdown says it is about
## tags, and that every control on the header says what it does when hovered.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
const ControlWalker := preload("res://harness/controls/sa_control_walker.gd")
const BrushSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/tools/brush_settings.gd")
const ShippedPresetsScript = preload("res://modules/sara-base-modules/stamp-brush/presets/sa_shipped_presets.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")

## A cell's picture is a rendered stroke through the real paint path.
const REQUIRES_GPU := true

## Never the real `user://brush_presets`, for `test_preset_chooser.gd`'s reason.
static var scratch_dir: String = SaDataRoot.path("test_n36_header")

var _saved_icon_size: int = 48

## The profile's tag filter as it stood, put back after each test, since a press
## on a tag writes it for every chooser after this one.
var _tag_filter_was: Dictionary = {}


func before_each() -> void:
    _tag_filter_was = SaSettings.preset_tag_filter.duplicate()
    SaSettings.preset_tag_filter = {}
    _saved_icon_size = SaSettings.preset_icon_size
    ScratchFolder.clear(scratch_dir)


func after_each() -> void:
    SaSettings.preset_tag_filter = _tag_filter_was
    SaSettings.preset_icon_size = _saved_icon_size
    ScratchFolder.clear(scratch_dir)


## A chooser over the three presets Sara ships, which carry tags, so the tag
## dropdown is drawn.
func _chooser() -> SaBrushPresetsChooser:
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    store.install_shipped(BrushSettingsScript.new(), ShippedPresetsScript)
    var chooser := SaBrushPresetsChooser.new()
    chooser.bind_store(store, StateBrushScript, func() -> Resource: return BrushSettingsScript.new())
    return chooser


## The kit's slider, so the harness lists it, with "Size" in its bar.
func test_the_size_control_is_the_kits_slider_and_reads_size() -> void:
    SaSettings.preset_icon_size = 64
    var chooser := _chooser()
    assert_true(chooser.size_slider is FactorSlider, "The size control is a FactorSlider")
    assert_eq(SaMake.kind_of(chooser.size_slider), SaMake.Kind.SLIDER, "made through SaMake.slider")
    assert_eq(chooser.size_slider.prefix, "Size: ", "and its bar reads Size")
    assert_eq(chooser.size_slider.value, 64.0, "on the size the profile holds")
    var listed := ControlWalker.describe_all(chooser).map(func(row: Dictionary) -> String: return row["name"])
    assert_true(listed.has("ChooserIconSize"), "The harness's control list carries it")
    chooser.free()


## A move of the slider still resizes the cells, the job it had before.
func test_the_size_slider_still_resizes_the_cells() -> void:
    SaSettings.preset_icon_size = 48
    var chooser := _chooser()
    assert_true(ControlWalker.move(chooser.size_slider, 96), "The slider takes 96")
    assert_eq(SaSettings.preset_icon_size, 96, "and the profile follows")
    var button := (chooser.grid.get_child(0) as Control).get_node("Icon") as Button
    assert_almost_eq(button.custom_minimum_size.x, float(SaUI.px(96)), 0.5, "and so does the cell")
    chooser.free()


## "All" alone was a word a painter learned the meaning of by opening it.
func test_the_tag_dropdown_reads_tag_all_and_the_chosen_tag_the_same_way() -> void:
    var chooser := _chooser()
    assert_true(chooser.tag_option.visible, "The shipped presets are tagged, so the dropdown is drawn")
    assert_eq(chooser.tag_option.text, "Tag: All", "and it reads Tag: All")
    chooser.capture_tag("paint")
    assert_eq(chooser.tag_option.text, "Tag: paint", "and a chosen tag reads the same way")
    chooser.free()


## Each control on the header says what it does when hovered.
func test_every_header_control_carries_a_tooltip() -> void:
    var chooser := _chooser()
    var controls := {
        "search": chooser.search_field,
        "size": chooser.size_slider,
        "tag": chooser.tag_option,
        "star": chooser.stars.filter,
        "strokes or tip": chooser.thumb_option,
    }
    for word: String in controls:
        assert_false((controls[word] as Control).tooltip_text.is_empty(), "The %s control carries a tooltip" % word)
    assert_eq(chooser.size_slider.tooltip_text, "How large each preset is drawn.", "the size's says what it sizes")
    assert_eq(
        chooser.tag_option.tooltip_text,
        "Click a tag to show only its presets, again to hide them, a third time to let them be.",
        "and the tag's what a click on a tag does"
    )
    chooser.free()
