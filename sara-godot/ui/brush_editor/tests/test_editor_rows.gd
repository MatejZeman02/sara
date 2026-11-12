## The Brush Tip page's rows and the editor's bottom bar.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The rows are settled one by one, and every clause of the list
## is a claim about a spec: which page it is on, whether the editor draws it at
## all, which section it sits under, when it is drawn and when it is live. Those
## are read off `tip_options()` here, because a spec is where the tool says so
## and a page is only what it does about it. The page doing it is
## `scenarios/editor-chrome-and-advanced.json` on the running app.
extends "res://tests/test_framework.gd"

const StampModule = preload("res://modules/sara-base-modules/stamp-brush/module.gd")


func _spec(key: StringName) -> SaOptionSpec:
    for spec: SaOptionSpec in StampModule.tip_options():
        if spec.key == key:
            return spec
    return null


# --- Which page a row is on ---------------------------------------------------


func test_cross_and_the_airbrush_three_are_on_general() -> void:
    for key: StringName in [&"painting_mode", &"airbrush_enabled", &"airbrush_rate", &"airbrush_ignore_spacing"]:
        assert_eq(_spec(key).page, StampModule.GENERAL_PAGE, "%s is not a tip setting" % key)


func test_painting_is_called_cross() -> void:
    # The label says what the row settles: how a stroke that crosses its own path
    # composes.
    assert_eq(_spec(&"painting_mode").label, "Cross", "renamed, not just moved")


func test_the_rest_of_the_tip_rows_stay_on_the_brush_tip_page() -> void:
    for key: StringName in [&"tip_generator", &"tip_shape", &"tip_ratio", &"spacing", &"tip_image_path"]:
        assert_eq(_spec(key).page, StampModule.TIP_PAGE, "%s is a tip setting" % key)


# --- Which rows the editor draws at all ---------------------------------------


func test_five_rows_leave_the_editor_and_keep_their_specs() -> void:
    # Hidden is not deleted: a preset carries the number and a Krita import
    # writes it, only the page omits the row.
    for key: StringName in [&"tip_spikes", &"tip_density", &"tip_antialias", &"sharpness", &"sharpness_softness"]:
        var spec := _spec(key)
        assert_not_null(spec, "%s is still declared" % key)
        assert_false(spec.in_editor, "and the editor draws no row for it" % [])


func test_everything_else_keeps_its_row() -> void:
    for key: StringName in [&"tip_generator", &"tip_shape", &"tip_ratio", &"tip_softness", &"tip_randomness", &"spacing"]:
        assert_true(_spec(key).in_editor, "%s is a row a painter still meets" % key)


# --- The two sections ---------------------------------------------------------


func test_the_procedural_rows_go_when_the_tip_is_an_image() -> void:
    var image := func(_key: StringName) -> Variant: return StampModule.TIP_IMAGE_ID
    var formula := func(_key: StringName) -> Variant: return 0

    for key: StringName in [&"tip_shape", &"tip_ratio", &"tip_softness", &"tip_randomness"]:
        var spec := _spec(key)
        assert_eq(spec.section, StampModule.SECTION_PROCEDURAL, "%s is a Procedural row" % key)
        assert_true(spec.shown_under(formula), "%s is drawn for a generated tip" % key)
        assert_false(spec.shown_under(image), "and not for a picture" % [])


func test_the_mask_rows_arrive_when_the_tip_is_an_image() -> void:
    var image := func(_key: StringName) -> Variant: return StampModule.TIP_IMAGE_ID
    var formula := func(_key: StringName) -> Variant: return 0

    for key: StringName in [&"tip_image_path", &"tip_load", &"tip_mirror_horizontal", &"tip_mirror_vertical"]:
        var spec := _spec(key)
        assert_eq(spec.section, StampModule.SECTION_MASK, "%s is a Mask row" % key)
        assert_true(spec.shown_under(image), "%s is drawn for a picture" % key)
        assert_false(spec.shown_under(formula), "and never beside a generated tip" % [])


func test_the_rows_that_apply_to_both_sit_outside_them() -> void:
    for key: StringName in [&"tip_generator", &"spacing", &"tip_auto_spacing", &"tip_auto_spacing_coeff"]:
        var spec := _spec(key)
        assert_eq(spec.section, "", "%s is under no heading" % key)
        assert_true(spec.shown_when.is_empty(), "and is drawn whichever kind of tip is in" % [])


## A choice id arrives as an int from one surface and as a float from another,
## because a `FactorSlider` reads a float whatever the kind says. The rule has to
## hold either way or a section would flicker between two readers of one number.
func test_a_condition_reads_a_float_and_an_int_the_same() -> void:
    var spec := _spec(&"tip_image_path")

    assert_true(spec.shown_under(func(_k: StringName) -> Variant: return 3), "an int id")
    assert_true(spec.shown_under(func(_k: StringName) -> Variant: return 3.0), "and the same id as a float")
    assert_false(spec.shown_under(func(_k: StringName) -> Variant: return 2.0), "a different one is a different one")


# --- The pair and the dimming -------------------------------------------------


func test_mirror_tip_is_one_row_of_two_toggles() -> void:
    var h := _spec(&"tip_mirror_horizontal")
    var v := _spec(&"tip_mirror_vertical")

    assert_eq(h.pair_with, &"tip_mirror_vertical", "H names V as its partner")
    assert_eq(h.pair_label, "Mirror tip", "the row is called that once")
    assert_eq(h.label, "H", "and the toggles are the two letters")
    assert_eq(v.label, "V", "beside each other")
    assert_true(v.pair_with.is_empty(), "the second half names nobody, or the two would each claim a row")


## Through `SaOptionSpec.row_is_enabled`, which is the one rule and not a second
## one: the bar, the Tool Options docker and this page all read the same field,
## so the file that decides what dimmed means is the only file that says it.
func test_rate_and_ignore_spacing_are_dimmed_while_the_airbrush_is_off() -> void:
    for key: StringName in [&"airbrush_rate", &"airbrush_ignore_spacing"]:
        var spec := _spec(key)
        assert_eq(spec.enabled_when, &"airbrush_enabled", "%s waits on the toggle" % key)
        assert_false(SaOptionSpec.row_is_enabled(spec, false), "%s does nothing while Airbrush is off" % key)
        assert_true(SaOptionSpec.row_is_enabled(spec, true), "and is live once it is on" % [])
    var coeff := _spec(&"tip_auto_spacing_coeff")
    assert_false(SaOptionSpec.row_is_enabled(coeff, false), "and the Auto Spacing amount reads the same way")


## "Nothing under Airbrush" was a fragment that did not say what it meant. The
## tooltip is a sentence instead, on all three rows that had one, naming the
## switch the row is used with.
func test_the_nothing_under_tooltips_say_what_they_meant() -> void:
    for key: StringName in [&"airbrush_rate", &"airbrush_ignore_spacing", &"tip_auto_spacing_coeff"]:
        var tooltip := _spec(key).tooltip
        assert_false(tooltip.contains("Nothing under"), "%s says it in words" % key)
        assert_true(tooltip.contains("Only used with"), "and says which switch it waits on" % [])


## "Isn't it just our hardness?" Not the same number today, and the tooltip is
## where a painter finds that out.
func test_the_softness_tooltip_names_hardness() -> void:
    assert_true(_spec(&"tip_softness").tooltip.contains("Hardness"), "it says which is which")


# --- The chrome ---------------------------------------------------------------


## "These buttons (Reset, Close) are covering the rim of the dialog window." The
## bar was the last child of a column anchored to the window's full rect. The
## bar is now the one row of every button, pinned in a column of its own.
func test_the_bottom_bar_is_held_off_the_rim() -> void:
    var window := SaBrushEditorWindow.new()

    var margin := window.find_child("ButtonsMargin", true, false) as MarginContainer
    assert_not_null(margin, "the row sits in a margin")
    if margin == null:
        window.free()
        return
    var row := margin.find_child("Buttons", true, false)
    assert_not_null(row, "with the row inside it")
    for side: String in ["margin_left", "margin_right", "margin_bottom"]:
        assert_true(margin.get_theme_constant(side) > 0, "%s holds it off the frame" % side)
    window.free()
