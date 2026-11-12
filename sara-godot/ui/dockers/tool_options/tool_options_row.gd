## A Tool Options row of a label and the control beside it, which gives the
## control its whole width first and the label what is left.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## An `HBoxContainer` gives a label that does not expand exactly its minimum,
## so a label column either asked for its longest label or cut every label at
## the floor, and it asks for the label and the control side by side however
## wide the control is. Here the control gets the width its text wants, the
## label the rest down to `ToolOptionsDocker.LABEL_WIDTH`, and a value is cut only when the row is
## narrower than both. A control too wide to sit beside the label at all, a
## curve's graph or the stamp's pattern chooser, goes under it instead, so the
## row asks for the wider of the two rather than for their sum. A cut value
## says its whole text in the tooltip.
##
## **Its own class rather than lines in `tool_options_docker.gd`**, because it
## owns one thing, how a row divides its width, and the docker owns which rows
## there are and what they say.
class_name ToolOptionsRow
extends Container

## The control's own tooltip, what the option does, kept to follow the
## whole value when the value is cut.
var description: String

## Whether the control is a button whose text this docker writes, and so a
## value that may be cut.
var cuts_value: bool

## Whether the control sits under the label, from the last sort. The height
## the row asks for depends on it, so a change is announced.
var _stacked: bool = false


func _init(row_description: String, row_cuts_value: bool) -> void:
    description = row_description
    cuts_value = row_cuts_value


func _notification(what: int) -> void:
    if what == NOTIFICATION_SORT_CHILDREN:
        _place()


func _get_minimum_size() -> Vector2:
    var label := _label()
    var control := _control()
    if control == null:
        return Vector2.ZERO
    var control_floor := control.get_combined_minimum_size()
    if label == null:
        return control_floor
    var label_floor := label.get_combined_minimum_size()
    if _stacked:
        return Vector2(maxf(label_floor.x, control_floor.x), label_floor.y + _gap() + control_floor.y)
    return Vector2(maxf(label_floor.x, control_floor.x), maxf(label_floor.y, control_floor.y))


func _place() -> void:
    var label := _label()
    var control := _control()
    if control == null:
        return
    if label == null:
        fit_child_in_rect(control, Rect2(Vector2.ZERO, size))
        return
    var gap := _gap()
    var label_floor := label.get_combined_minimum_size()
    var control_floor := control.get_combined_minimum_size().x
    # A control that asks for the whole width stacks at any width.
    var stacked := control.has_meta(ToolOptionControls.UNDER_LABEL_META) or size.x < label_floor.x + gap + control_floor
    if stacked != _stacked:
        _stacked = stacked
        update_minimum_size()
    if stacked:
        fit_child_in_rect(label, Rect2(0, 0, size.x, label_floor.y))
        var top := label_floor.y + gap
        fit_child_in_rect(control, Rect2(0, top, size.x, maxf(size.y - top, 0.0)))
        return
    # The words as the label draws them, through the catalogue, since the row
    # was written in the language Sara started in.
    var label_whole := maxf(label_floor.x, _text_width(label, label.atr(label.text), label.get_theme_stylebox("normal")))
    var control_whole := control_floor
    var button := control as Button
    if cuts_value and button != null:
        control_whole = maxf(control_whole, _text_width(button, button.atr(button.text), button.get_theme_stylebox("normal")))
    var label_width := clampf(size.x - gap - control_whole, label_floor.x, label_whole)
    var control_width := maxf(size.x - gap - label_width, control_floor)
    # The rectangles are the columns, and each child's own vertical flags
    # place it inside its own, the way an `HBoxContainer` would.
    fit_child_in_rect(label, Rect2(0, 0, label_width, size.y))
    fit_child_in_rect(control, Rect2(label_width + gap, 0, control_width, size.y))
    if cuts_value and button != null:
        var cut := control_width < control_whole - 0.5
        var whole := button.text + ("\n\n" + description if not description.is_empty() else "")
        button.tooltip_text = whole if cut else description


func _label() -> Label:
    return get_node_or_null("Label") as Label


func _control() -> Control:
    for child in get_children():
        if child is Control and not child is Label:
            return child
    return null


## The gap a row of the theme's puts between two controls.
func _gap() -> float:
    return float(get_theme_constant("separation", "HBoxContainer"))


## How wide *text* draws on *control* at its own font, with *box*'s margins.
static func _text_width(control: Control, text: String, box: StyleBox) -> float:
    var font := control.get_theme_font("font")
    var font_size := control.get_theme_font_size("font_size")
    var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x if font != null else 0.0
    return ceilf(width + (box.get_minimum_size().x if box != null else 0.0))
