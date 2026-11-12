## A Tool Options row built on `SaChoiceButton` dumps the id it has chosen.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Every `ENUM` row is built on
## `SaChoiceButton`, which is a `Button`, so `_row_value` walked past the
## dropdown branch and read it as an action button that is not a toggle. A
## scenario chose Rope and the dump's Stabilizer row said null while the screen
## said Rope. The rows are built the way
## `ToolOptionsDocker._place_control` builds them, and filled the way
## `ToolOptionControls._build_choice` fills one.
extends "res://tests/test_framework.gd"

## The ids the stamp brush's stabilizer enum declares, numbers on purpose, since
## the dump is meant to carry these.
const NONE := 0
const WEIGHTED := 1
const ROPE := 2


## A row as the docker builds one for anything that is not a slider.
func _row(control: Control) -> HBoxContainer:
    var box := HBoxContainer.new()
    box.name = "StabilizerRow"
    var label := Label.new()
    label.name = "Label"
    label.text = "Stabilizer"
    box.add_child(label)
    box.add_child(control)
    return box


func _stabilizers() -> SaChoiceButton:
    var choice := SaChoiceButton.new()
    choice.name = "StabilizerOpt"
    choice.set_choices(
        [{"id": NONE, "label": "No Stabilizer"}, {"id": WEIGHTED, "label": "Weighted"}, {"id": ROPE, "label": "Rope"}]
    )
    return choice


## A step, Rope chosen the way `ToolOptionControls._show_value` sets it.
func test_a_choice_row_reads_the_id_it_has_chosen() -> void:
    var choice := _stabilizers()
    assert_true(choice.select_value(ROPE), "the button holds a Rope row")
    var row := _row(choice)

    assert_eq(ToolOptionsDocker.row_value(row), ROPE, "Rope's id, not null and not the word on the button")
    row.free()


func test_each_choice_reads_a_different_value() -> void:
    var seen: Array = []
    for value: int in [NONE, WEIGHTED, ROPE]:
        var choice := _stabilizers()
        choice.select_value(value)
        var row := _row(choice)
        seen.append(ToolOptionsDocker.row_value(row))
        row.free()
    assert_eq(seen, [NONE, WEIGHTED, ROPE], "three choices, three values")


## The id and not the place in the list, which is the distinction kept.
func test_the_value_is_the_choice_id_and_not_its_row() -> void:
    var choice := SaChoiceButton.new()
    choice.name = "FilterOpt"
    choice.set_choices([{"id": 10, "label": "Nearest"}, {"id": 20, "label": "Bilinear"}, {"id": 30, "label": "Bicubic"}])
    choice.select_value(30)
    var row := _row(choice)

    assert_eq(ToolOptionsDocker.row_value(row), 30, "the id behind the row")
    row.free()


## A button with no choices has chosen nothing, and reads null rather than the
## text it happens to show.
func test_a_choice_button_with_nothing_chosen_is_null() -> void:
    var choice := SaChoiceButton.new()
    choice.name = "EmptyOpt"
    choice.text = "Something"
    var row := _row(choice)

    assert_null(ToolOptionsDocker.row_value(row), "nothing chosen is nothing to report")
    row.free()
