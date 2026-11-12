## Every row of a list is one height, whatever state it is drawn in.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A `Button` is as tall as the box of the state it is in. A row's hovered,
## chosen and disabled boxes had two pixels top and bottom where the resting box
## has four, so on the View menu the three greyed rows stood 31 pixels apart among
## live ones 35 apart and the list stepped under them. The keyboard's mark, which
## `SaChoiceRow.set_highlighted` puts in the `normal` slot with no margin at all,
## stood a row at 29 pixels among rows of 33.
##
## The rows are built on their own under a holder carrying Sara's theme, the way
## a list builds them, because a list in the tree is a Window and hangs a
## headless run. The holder is in the tree, because a button out of it has
## shaped no text and every row reads the 24 pixels its floor gives it, which
## passed against the stepping list. The picture is
## `scenarios/a-greyed-row-of-a-list-is-as-tall-as-a-live-one.json`.
extends "res://tests/test_framework.gd"

var _kept_theme: Theme = null
var _holder: VBoxContainer = null


func before_each() -> void:
    # The resting box is the shared theme's push button, which a run of the
    # suites has not built.
    _kept_theme = SaUI.shared_theme
    SaUI.init_global_theme(null)
    _holder = VBoxContainer.new()
    _holder.theme = SaUI.shared_theme
    EventBus.add_child(_holder)


func after_each() -> void:
    _holder.free()
    _holder = null
    SaUI.shared_theme = _kept_theme


func _row(id: StringName, disabled: bool, group: ButtonGroup) -> SaChoiceRow:
    var row := SaChoiceRow.new(id, String(id), group == null, false, "", "", disabled, group, "")
    _holder.add_child(row)
    return row


func _height(row: SaChoiceRow) -> float:
    return row.label_button().get_combined_minimum_size().y


func test_a_greyed_row_is_as_tall_as_a_resting_one_in_a_list_of_switches() -> void:
    var resting := _row(&"live", false, null)
    var greyed := _row(&"greyed", true, null)
    assert_true(greyed.label_button().disabled, "the greyed row is drawn in its disabled state")
    assert_eq(_height(greyed), _height(resting), "a greyed row is as tall as a live one")


func test_a_chosen_and_a_greyed_row_of_a_one_of_list_are_as_tall_as_a_resting_one() -> void:
    var group := ButtonGroup.new()
    var resting := _row(&"resting", false, group)
    var chosen := _row(&"chosen", false, group)
    var greyed := _row(&"greyed", true, group)
    chosen.label_button().button_pressed = true
    assert_true(chosen.label_button().button_pressed, "the chosen row is drawn pressed")
    assert_false(resting.label_button().button_pressed, "and the resting row is not")
    assert_eq(_height(chosen), _height(resting), "a chosen row is as tall as a resting one")
    assert_eq(_height(greyed), _height(resting), "and so is a greyed one")


func test_the_keyboards_mark_does_not_shorten_its_row() -> void:
    var resting := _row(&"resting", false, null)
    var marked := _row(&"marked", false, null)
    marked.set_highlighted(true)
    assert_eq(_height(marked), _height(resting), "a row the keyboard rests on keeps its height")
    marked.set_highlighted(false)
    assert_eq(_height(marked), _height(resting), "and keeps it when the keyboard leaves")


## Hover cannot be put on a row without a pointer, so its box is held to the
## resting one's height directly, with the two other boxes a row sets.
func test_every_box_a_row_sets_is_as_tall_as_its_resting_box() -> void:
    var button := _row(&"live", false, null).label_button()
    var rest := button.get_theme_stylebox("normal").get_minimum_size().y
    for state: String in ["hover", "pressed", "disabled"]:
        var box := button.get_theme_stylebox(state).get_minimum_size().y
        assert_eq(box, rest, "the %s box is as tall as the resting one" % state)
