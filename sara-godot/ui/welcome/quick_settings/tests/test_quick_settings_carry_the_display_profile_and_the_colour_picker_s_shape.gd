## The welcome window's display profile and colour picker rows:
## each writes the one `SaSettings` value its Preferences row writes, and each
## reads back what the other wrote.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Both directions are driven through the controls a painter presses, the
## pane's dropdown and the Preferences row's, rather than through the setting,
## because two surfaces that disagree is a claim about the controls. The
## pane is never added to a tree, for the reason `test_quick_settings_pane.gd`
## gives, and the Colour Picker is built only so that its Type row is
## registered, as a running app has done before Preferences opens.
extends "res://tests/test_framework.gd"

const SaColorPickerScript = preload("res://ui/dockers/color/sa_color_picker.gd")

var _pane: WelcomeQuickSettingsPane = null
var _saved_profile: String = "srgb"
var _saved_shape: String = "wheel"


func before_each() -> void:
    _saved_profile = SaSettings.display_profile
    _saved_shape = SaSettings.color_picker_shape
    _pane = WelcomeQuickSettingsPane.new()


## The running app's settings are put back even after a failed assertion.
func after_each() -> void:
    SaSettings.display_profile = _saved_profile
    SaSettings.color_picker_shape = _saved_shape
    if _pane != null:
        _pane.free()
        _pane = null


## The two rows stand at the foot of the pane, under the titles the Done clause
## names, with the five that were there before still above them.
func test_the_pane_carries_seven_rows_the_two_new_ones_last() -> void:
    var titles: Array[String] = []
    for node in _pane.find_children("*", "HBoxContainer", true, false):
        if node.has_meta(SaSettingsRows.ROW_META):
            titles.append(String(node.get_meta(SaSettingsRows.TITLE_META)))
    # Nine, the Font size slider among them.
    assert_eq(titles.size(), 9, "seven rows and the one above them")
    assert_eq(titles.slice(7), ["Display profile", "Colour picker"], "the display profile and the picker's shape last")


## The question the welcome window's spec settled: a wide gamut only helps on a
## monitor that shows it, and the row's tooltip says so.
func test_the_display_profile_tooltip_says_a_wide_gamut_needs_a_monitor_that_shows_it() -> void:
    var tip := _pane.profile_opt.tooltip_text
    assert_true(tip.contains("Display P3"), "the tooltip names the wide profiles")
    assert_true(tip.contains("only on a monitor that shows that gamut"), "and says when one helps")


## Every profile the Display page offers is on the pane, and nothing else.
func test_the_profile_row_lists_the_display_pages_profiles() -> void:
    var page := SaDisplayPage.new()
    # Less the monitor profile file and Custom..., which each need a picker the
    # pane does not have, so both stay on the Display page.
    var theirs: Array[String] = _profile_control(page).choice_labels()
    theirs.erase(tr("Monitor profile file"))
    theirs.erase(tr(SaColorSpaceRow.ASK_LABEL))
    assert_eq(_pane.profile_opt.choice_labels(), theirs, "the same profiles under the same names")
    page.free()


func test_a_profile_set_on_the_pane_reads_on_the_display_page() -> void:
    SaSettings.display_profile = "srgb"
    _pane.profile_opt.choice_picked.emit("rec2020")
    assert_eq(SaSettings.display_profile, "rec2020", "the pane writes the setting")
    var page := SaDisplayPage.new()
    page.page.refresh()
    assert_eq(_profile_control(page).selected_value(), "rec2020", "and the Display page's row shows it")
    page.free()


func test_a_profile_set_on_the_display_page_reads_on_the_pane() -> void:
    SaSettings.display_profile = "srgb"
    _pane.refresh()
    var page := SaDisplayPage.new()
    _profile_control(page).choice_picked.emit("display_p3")
    assert_eq(SaSettings.display_profile, "display_p3", "the page writes the setting")
    _pane.refresh()
    assert_eq(_pane.profile_opt.selected_value(), "display_p3", "and the pane shows it once it is shown again")
    page.free()


## The shapes are the picker's own, under the labels its Type row shows.
func test_the_shape_row_lists_the_pickers_shapes() -> void:
    assert_eq(_pane.picker_shape_opt.choice_labels().size(), SaPickerShape.KIND_KEYS.size(), "one entry per shape")
    assert_eq(_pane.picker_shape_opt.choice_labels()[0], SaPickerShape.KIND_LABELS[0], "under the shape's own label")


func test_a_shape_set_on_the_pane_reads_on_the_colour_pickers_type_row() -> void:
    var holder := _register_picker()
    SaSettings.color_picker_shape = "wheel"
    _pane.picker_shape_opt.choice_picked.emit("hsl_square")
    assert_eq(SaSettings.color_picker_shape, "hsl_square", "the pane writes the setting")
    var page := SaLayoutPage.new("ColorPicker", SaLayoutPage.OPTIONS)
    var row := page.below_control("Type") as SaChoiceButton
    assert_not_null(row, "the Colour Picker's options carry the Type row")
    if row != null:
        assert_eq(row.selected_value(), "hsl_square", "and the Type row shows it")
    page.free()
    holder.free()


func test_a_shape_set_on_the_type_row_reads_on_the_pane() -> void:
    var holder := _register_picker()
    SaSettings.color_picker_shape = "wheel"
    _pane.refresh()
    var page := SaLayoutPage.new("ColorPicker", SaLayoutPage.OPTIONS)
    page.drive_gesture(null, Vector2.ZERO, {"option": "shape", "value": "triangle"})
    assert_eq(SaSettings.color_picker_shape, "triangle", "the Type row writes the setting")
    _pane.refresh()
    assert_eq(_pane.picker_shape_opt.selected_value(), "triangle", "and the pane shows it once it is shown again")
    page.free()
    holder.free()


## The Display page's profile dropdown, by the row key Help > Display Settings...
## opens the page on.
func _profile_control(page: SaDisplayPage) -> SaChoiceButton:
    return page.page.row(SaDisplayPage.PROFILE_ROW).control as SaChoiceButton


## A Colour Picker under a holder, its `_ready` run so the Type row is
## registered. The caller frees the holder.
func _register_picker() -> Control:
    var picker := SaColorPickerScript.new()
    var holder := Control.new()
    holder.add_child(picker)
    picker._ready()
    return holder
