## `SaMake` makes one of every kind it offers, and each comes back added to its
## parent, under its name, with the properties it was given and as its own type.
##
## SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/test_framework.gd"

var _parent: VBoxContainer = null


func before_each() -> void:
    _parent = VBoxContainer.new()


func after_each() -> void:
    if _parent != null and is_instance_valid(_parent):
        _parent.free()
    _parent = null


## The part every kind shares: the parent holds it and it carries the name.
func _placed(made: Control, node_name: String) -> void:
    assert_true(made != null, "%s was made" % node_name)
    assert_true(made.get_parent() == _parent, "%s is a child of the parent it was handed" % node_name)
    assert_eq(String(made.name), node_name, "%s keeps the name it was given" % node_name)


func test_label() -> void:
    var made := SaMake.label(_parent, "WhitePointValue", "D65")
    _placed(made, "WhitePointValue")
    assert_true(made is Label, "a label is a Label")
    assert_eq(made.text, "D65")


func test_button() -> void:
    var made := SaMake.button(_parent, "ResetBtn", "Reset", "Put it back")
    _placed(made, "ResetBtn")
    assert_true(made is Button, "a button is a Button")
    assert_eq(made.text, "Reset")
    assert_eq(made.tooltip_text, "Put it back")


func test_check_box() -> void:
    var made := SaMake.check_box(_parent, "KeepChk", "Keep", true)
    _placed(made, "KeepChk")
    assert_true(made is CheckBox, "a check box is a CheckBox")
    assert_eq(made.text, "Keep")
    assert_true(made.button_pressed, "the check box starts ticked when asked")


func test_line_edit() -> void:
    var made := SaMake.line_edit(_parent, "NameEdit", "Layer 1", "A name")
    _placed(made, "NameEdit")
    assert_true(made is LineEdit, "a line edit is a LineEdit")
    assert_eq(made.text, "Layer 1")
    assert_eq(made.placeholder_text, "A name")


## A value past the engine's default range of 0 to 100 survives, which is what
## setting the range before the value is for.
func test_spin_box() -> void:
    var made := SaMake.spin_box(_parent, "WidthSpin", 1.0, 16384.0, 1.0, 4096.0)
    _placed(made, "WidthSpin")
    assert_true(made is SpinBox, "a spin box is a SpinBox")
    assert_eq(made.min_value, 1.0)
    assert_eq(made.max_value, 16384.0)
    assert_eq(made.step, 1.0)
    assert_eq(made.value, 4096.0)


func test_slider() -> void:
    var made := SaMake.slider(_parent, "AngleSlider", -180.0, 180.0, 1.0, 45.0)
    _placed(made, "AngleSlider")
    assert_true(made is FactorSlider, "a slider is Sara's FactorSlider")
    assert_eq(made.min_value, -180.0)
    assert_eq(made.max_value, 180.0)
    assert_eq(made.step, 1.0)
    assert_eq(made.value, 45.0)


func test_choice() -> void:
    var made := SaMake.choice(_parent, "ModeOpt", [{"id": &"a", "label": "First"}, {"id": &"b", "label": "Second"}])
    _placed(made, "ModeOpt")
    assert_true(made is SaChoiceButton, "a choice is a SaChoiceButton")
    assert_eq(made.selected_value(), &"a", "the first choice is the one shown")
    assert_true(made.select_value(&"b"), "the second choice is in the list")


func test_row_and_column() -> void:
    var row := SaMake.row(_parent, "Row", SaTheme.GAP_TIGHT)
    _placed(row, "Row")
    assert_true(row is HBoxContainer, "a row is an HBoxContainer")
    assert_eq(row.get_theme_constant("separation"), SaUI.px(SaTheme.GAP_TIGHT), "the gap is scaled once")
    var column := SaMake.column(_parent, "Column", SaTheme.GAP)
    _placed(column, "Column")
    assert_true(column is VBoxContainer, "a column is a VBoxContainer")
    assert_eq(column.get_theme_constant("separation"), SaUI.px(SaTheme.GAP))


## No gap named means no override, so the theme pass still owns the spacing.
func test_a_container_with_no_gap_keeps_the_theme() -> void:
    var row := SaMake.row(_parent, "Themed")
    assert_false(row.has_theme_constant_override("separation"), "an unnamed gap writes no override")


func test_grid() -> void:
    var made := SaMake.grid(_parent, "Fields", 2, SaTheme.GAP)
    _placed(made, "Fields")
    assert_true(made is GridContainer, "a grid is a GridContainer")
    assert_eq(made.columns, 2)
    assert_eq(made.get_theme_constant("h_separation"), SaUI.px(SaTheme.GAP))
    assert_eq(made.get_theme_constant("v_separation"), SaUI.px(SaTheme.GAP))


func test_margin() -> void:
    var made := SaMake.margin(_parent, "Margin", SaTheme.PAD)
    _placed(made, "Margin")
    assert_true(made is MarginContainer, "a margin is a MarginContainer")
    for side: String in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
        assert_eq(made.get_theme_constant(side), SaUI.px(SaTheme.PAD), "%s is the named pad" % side)


func test_scroll() -> void:
    var made := SaMake.scroll(_parent, "Scroll")
    _placed(made, "Scroll")
    assert_true(made is ScrollContainer, "a scroll is a ScrollContainer")


func test_separator() -> void:
    var across := SaMake.separator(_parent, "Across")
    _placed(across, "Across")
    assert_true(across is HSeparator, "a separator is horizontal by default")
    var upright := SaMake.separator(_parent, "Upright", true)
    _placed(upright, "Upright")
    assert_true(upright is VSeparator, "and vertical when asked")


## A null parent makes and names the control and adds it nowhere, for a control
## whose place is decided later.
func test_a_null_parent_adds_nothing() -> void:
    var made := SaMake.button(null, "Loose", "Loose")
    assert_eq(String(made.name), "Loose")
    assert_true(made.get_parent() == null, "no parent was handed, so none is set")
    made.free()


## The children land in the order they were made, which is the order a
## conversion keeps when it swaps `add_child` for a call.
func test_children_keep_the_order_they_were_made_in() -> void:
    SaMake.label(_parent, "One")
    SaMake.button(_parent, "Two")
    SaMake.row(_parent, "Three")
    var names: Array[String] = []
    for child in _parent.get_children():
        names.append(String(child.name))
    assert_eq(names, ["One", "Two", "Three"])


## The three named sizes are the values the tree counted, in logical pixels.
func test_the_named_sizes() -> void:
    assert_eq(SaTheme.GAP_TIGHT, 4)
    assert_eq(SaTheme.GAP, 8)
    assert_eq(SaTheme.PAD, 12)
