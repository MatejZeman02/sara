## The presets chooser's two dropdowns each have room to say what they are.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## One row held the search field, the tag filter, the Strokes and Tip choice and
## the size slider. The field expands, and a `SaChoiceButton` clips its text so
## its minimum is its arrow, so at the docker's own 280 units the field took the
## row and both dropdowns were drawn as two identical arrows. The chooser now has
## a search row and a dropdown row, and what is graded here is the arrangement
## that makes the words fit: which controls share a row, and that the two
## dropdowns share theirs. The drawn widths are the running app's, in
## `scenarios/the-presets-choosers-two-dropdowns-are-two-bare-chevrons.json`.
extends "res://tests/test_framework.gd"

const BrushSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/tools/brush_settings.gd")
## The recipes the brush ships, and the rule about which of them a template
## can carry. Handed to `install_shipped`
## because a test machine holds no registries to ask for the role.
const ShippedPresetsScript = preload("res://modules/sara-base-modules/stamp-brush/presets/sa_shipped_presets.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")

## Binding a store renders thumbnails, which needs a RenderingDevice.
const REQUIRES_GPU := true

static var scratch_dir: String = SaDataRoot.path("test_d45_presets_chooser")


func after_each() -> void:
    if not DirAccess.dir_exists_absolute(scratch_dir):
        return
    var thumbs := SaPresetThumbs.thumbs_dir(scratch_dir)
    if DirAccess.dir_exists_absolute(thumbs):
        for file_name: String in DirAccess.get_files_at(thumbs):
            DirAccess.remove_absolute(thumbs.path_join(file_name))
        DirAccess.remove_absolute(thumbs)
    for file_name: String in DirAccess.get_files_at(scratch_dir):
        DirAccess.remove_absolute(scratch_dir.path_join(file_name))
    DirAccess.remove_absolute(scratch_dir)


## The search field and the size slider share a row of their own, so a dropdown
## is never beside the one control that expands.
func test_the_search_and_the_size_share_a_row_without_the_dropdowns() -> void:
    var chooser := SaBrushPresetsChooser.new()
    var search_row := chooser.search_field.get_parent()
    assert_eq(chooser.size_slider.get_parent(), search_row, "the size slider is on the search row")
    assert_true(search_row != chooser.tag_option.get_parent(), "and the tag dropdown is not")
    assert_true(search_row != chooser.thumb_option.get_parent(), "and neither is the Strokes and Tip choice")
    chooser.free()


## The two dropdowns share the second row and split it, which is what gives each
## the width to show its label at the docker's default size.
func test_the_two_dropdowns_share_their_row_and_split_it() -> void:
    var chooser := SaBrushPresetsChooser.new()
    assert_eq(chooser.tag_option.get_parent(), chooser.thumb_option.get_parent(), "both dropdowns are on one row")
    assert_eq(chooser.tag_option.size_flags_horizontal, Control.SIZE_EXPAND_FILL, "the tag filter takes its share")
    assert_eq(chooser.thumb_option.size_flags_horizontal, Control.SIZE_EXPAND_FILL, "and so does the Strokes and Tip choice")
    assert_eq(chooser.search_field.get_parent().get_index(), 0, "the search row comes first")
    assert_true(
        chooser.tag_option.get_parent().get_index() > chooser.search_field.get_parent().get_index(),
        "and the dropdown row under it"
    )
    chooser.free()


## The tag name field still lands beside the tag dropdown. `_bind_tags` counts the
## dropdown's index in the row it inserts into, so the row that holds the
## dropdown has to be the row the field goes into, or a rename opens its box on
## the wrong row.
func test_the_tag_name_field_still_lands_just_before_the_tag_dropdown() -> void:
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    store.install_shipped(BrushSettingsScript.new(), ShippedPresetsScript)
    var chooser := SaBrushPresetsChooser.new()
    chooser.bind_store(store, StateBrushScript, func() -> Resource: return BrushSettingsScript.new())

    var row := chooser.tag_option.get_parent()
    assert_not_null(chooser.tags, "binding a store builds the tag gesture")
    assert_eq(chooser.tags.field.get_parent(), row, "the tag name field is on the dropdown row")
    assert_eq(chooser.tags.field.get_index() + 1, chooser.tag_option.get_index(), "immediately before the tag dropdown")
    chooser.free()
