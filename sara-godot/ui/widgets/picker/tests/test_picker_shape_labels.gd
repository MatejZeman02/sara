## The picker's seven shapes are named for the colour model, which is what
## actually differs between them.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## HSV was named square and okHSV wheel while both are the same shape, and the
## geometry agrees that the names misled: the
## wheel and the HSV square take the same ring, the same inset, the same
## across-and-up read and the same shader mode, so the old labels named a
## shape two entries shared and hid the model that separates them. The row a
## painter sees is `scenarios/picker-shape-labels.json`, this file is the
## part no shot can show: that no key moved under the rename, and that the
## seven labels are still seven distinct things to choose between.
extends "res://tests/test_framework.gd"

const SaColorPickerScript = preload("res://ui/dockers/color/sa_color_picker.gd")

## The keys as they stood before the rename. Written out rather than read from
## the table under test, because a stored `color_picker_shape` is one of these
## strings and a test that compares the table to itself would let all seven
## move together.
const KEYS_BEFORE_P1: Array[String] = [
    "wheel",
    "okhsl",
    "triangle",
    "triangle_up",
    "hsv_square",
    "hsv_triangle",
    "hsl_square",
]


func test_the_rename_moved_no_key() -> void:
    assert_eq(SaPickerShape.KIND_KEYS, KEYS_BEFORE_P1, "the stored name of every shape is what it was")
    assert_eq(SaPickerShape.KIND_LABELS.size(), SaPickerShape.KIND_KEYS.size(), "and each of them still has exactly one label")


func test_no_two_shapes_are_offered_under_one_label() -> void:
    var seen: Dictionary = {}
    for label: String in SaPickerShape.KIND_LABELS:
        assert_false(label.strip_edges().is_empty(), "no shape is offered under an empty name")
        assert_false(seen.has(label), "no two shapes are offered under '%s'" % label)
        seen[label] = true


## The clause that matters. Both entries are one geometry, so neither may
## be named for that geometry alone: each label leads with its colour model.
func test_the_wheel_and_the_hsv_square_are_told_apart_by_their_model() -> void:
    var wheel: String = SaPickerShape.KIND_LABELS[SaPickerShape.Kind.WHEEL]
    var square: String = SaPickerShape.KIND_LABELS[SaPickerShape.Kind.HSV_SQUARE]

    assert_true(wheel.begins_with("OKHSV"), "the wheel says which model it reads first: %s" % wheel)
    assert_true(square.begins_with("HSV"), "and so does the classic square: %s" % square)
    assert_false(wheel.to_lower().contains("wheel"), "and neither is named for a shape the other has too")
    assert_eq(
        SaPickerShape.AREA_MODES[SaPickerShape.Kind.WHEEL],
        SaPickerShape.AREA_MODES[SaPickerShape.Kind.HSV_SQUARE],
        "which is the point: the two read their area through the same shader mode"
    )


## The list reads as one list: every label names a model, and the four models
## that appear twice or once all appear in the same position.
func test_every_label_leads_with_a_colour_model() -> void:
    var models: Array[String] = ["OKHSV", "OKHSL", "OKLCh", "OKLCh", "HSV", "HSV", "HSL"]
    for i in range(SaPickerShape.KIND_LABELS.size()):
        var label: String = SaPickerShape.KIND_LABELS[i]
        assert_true(label.begins_with(models[i] + ","), "'%s' opens with the model %s and a comma" % [label, models[i]])


## The Preferences row is generated from these tables, so the rename reaches
## the dropdown without the page being taught anything.
func test_the_type_row_carries_the_new_names() -> void:
    var picker := SaColorPickerScript.new()
    var dummy := Control.new()
    dummy.add_child(picker)
    picker._ready()
    var page := SaLayoutPage.new("ColorPicker", SaLayoutPage.OPTIONS)

    var row := page.below_control("Type") as SaChoiceButton

    assert_not_null(row, "the page draws a Type row")
    assert_eq(row.choice_labels().size(), SaPickerShape.KIND_KEYS.size(), "with one entry per shape")
    for i in range(SaPickerShape.KIND_LABELS.size()):
        assert_eq(row.choice_labels()[i], SaPickerShape.KIND_LABELS[i], "under the names the shape declares")
    page.free()
    dummy.free()
