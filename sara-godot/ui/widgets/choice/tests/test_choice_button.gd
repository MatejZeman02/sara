## The control that replaced the engine's dropdown.
##
## Built detached: `SaChoiceButton` holds an `SaChoicePopup`, which is a `Window`
## and needs no tree to be filled or read, and `open_under` refuses to open one
## that is out of the tree, so nothing here pops anything.
extends "res://tests/test_framework.gd"


func _button(choices: Array) -> SaChoiceButton:
    var button := SaChoiceButton.new()
    button.set_choices(choices)
    return button


func _numbers() -> Array:
    return [
        {"id": 0, "label": "No Stabilizer"},
        {"id": 1, "label": "Average"},
        {"id": 2, "label": "Rope"},
    ]


## The button reads the chosen row and the list marks it, which is the whole of
## what a dropdown is. The first choice is what an empty button shows, the way
## an `OptionButton` selected its first item.
func test_the_button_reads_the_row_the_list_marks() -> void:
    var button := _button(_numbers())
    assert_eq(button.text, "No Stabilizer", "A fresh list shows its first row")
    assert_eq(button.selected_value(), 0, "and holds that row's own value")
    assert_true(button.popup.is_marked(&"0"), "which is the row the list marks")

    assert_true(button.select_value(2), "Choosing by value")
    assert_eq(button.text, "Rope", "moves the words on the button")
    assert_true(button.popup.is_marked(&"2"), "and the mark to that row")
    assert_false(button.popup.is_marked(&"0"), "off the row it was on")
    assert_false(button.select_value(7), "A value no row stands for is refused")
    assert_eq(button.text, "Rope", "and the button stays where it was")
    button.free()


## The signal carries the caller's own value and never an index, which is the
## line that let `_on_choice_selected` stop asking for the metadata back.
func test_a_press_carries_the_value_and_not_an_index() -> void:
    var button := _button(_numbers())
    var heard: Array = []
    button.choice_picked.connect(func(value: Variant) -> void: heard.append(value))

    assert_true(button.popup.press_row(&"1"), "A row's label takes a press")
    assert_eq(heard, [1], "and the signal is the row's value")
    assert_eq(button.selected_value(), 1, "which the button now holds")

    assert_true(button.pick_row("Rope"), "A row can be picked by its words")
    assert_eq(heard, [1, 2], "and answers with its own value too")
    assert_true(button.pick_row(0), "and by its index, which is what a scenario writes")
    assert_eq(heard, [1, 2, 0], "for the same signal")
    assert_false(button.pick_row("Nothing Like This"), "A row that is not there is refused")
    assert_eq(heard.size(), 3, "and fires nothing")
    button.free()


## A refill keeps the painter's choice when the new list still holds it, because
## a rebuild after a tool change is not a choice anybody made.
func test_a_refill_keeps_the_choice_it_still_has_a_row_for() -> void:
    var button := _button(_numbers())
    button.select_value(2)
    button.set_choices(_numbers())
    assert_eq(button.selected_value(), 2, "The same list keeps the same row")
    assert_true(button.popup.is_marked(&"2"), "and the mark with it")

    button.set_choices([{"id": 5, "label": "Five"}, {"id": 9, "label": "Nine"}])
    assert_eq(button.selected_value(), 5, "A list without that row falls to its first")
    assert_eq(button.text, "Five", "and says so")
    button.free()


## The rows are keyed on the value rather than on the label, so two rows reading
## the same words are still two rows and a dump names the thing the caller wrote.
func test_a_row_is_keyed_on_the_value_it_stands_for() -> void:
    var button := _button([{"id": &"free", "label": "Ratio"}, {"id": &"locked", "label": "Ratio"}])
    assert_eq(button.popup.row_ids(), [&"free", &"locked"], "Two rows, named for their values")
    assert_true(button.select_value(&"locked"), "and the second is reachable")
    assert_true(button.popup.is_marked(&"locked"), "and marked on its own")
    assert_false(button.popup.is_marked(&"free"), "not on the row that reads the same")
    button.free()


## One row is the answer, so the list is a `one_of` list: the mark is a pressed
## toggle in one group rather than a colour, which is the mark that survives the
## pointer moving over the rows.
func test_the_list_marks_the_way_a_one_of_list_does() -> void:
    var button := _button(_numbers())
    assert_true(button.popup.one_of, "The list is one-of")
    var row := button.popup.label_button(&"0")
    assert_true(row.toggle_mode, "so a row is a toggle")
    assert_not_null(row.button_group, "in a group")
    assert_true(row.button_pressed, "and the chosen row is the pressed one")
    button.free()
