## A Preferences choice whose stored value no row stands for takes a press
## on the row it shows.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## `SaPage._select_choice` found no row for such a value and returned, so
## the button kept the words of the row it last showed and the value behind
## them too. The guard in `SaChoiceButton._on_row_chosen` then read a press on
## that row as no move, and the binding stayed on the value nothing stands for.
## The words stay, and the value goes, through `clear_choice`.
##
## Built detached, the way `test_page_choice_buttons.gd` builds its page,
## because the list is a Window and one in the tree hangs a headless run.
extends "res://tests/test_framework.gd"


class Knobs:
    extends RefCounted

    var mode: int = 4


var _knobs: Knobs = null
var _host: VBoxContainer = null
var _page: SaPage = null


func before_each() -> void:
    _knobs = Knobs.new()
    _host = VBoxContainer.new()
    _page = SaPage.new()
    var rows := _page.section("Choices")
    rows.choice("Mode", [{"id": 4, "label": "Normal"}, {"id": 9, "label": "Raw"}], _knobs, ^"mode")
    _page.realize(_host)


## The host owns every control the page realized, and `SaPage` is RefCounted,
## so the one `free` is the container's.
func after_each() -> void:
    _host.free()
    _host = null
    _page = null
    _knobs = null


func _button() -> SaChoiceButton:
    var row := _page.row(&"mode")
    return (row.control if row != null else null) as SaChoiceButton


func test_a_press_on_the_row_the_button_shows_writes_the_setting() -> void:
    var button := _button()
    assert_eq(button.selected_value(), 4, "The page opened on the bound value")

    _knobs.mode = 77
    _page.refresh()
    assert_eq(button.text, "Normal", "A value no row stands for keeps the words the button showed")
    assert_null(button.selected_value(), "and lets go of the value behind them")

    assert_true(button.pick_row("Normal"), "The row the button names takes a press")
    assert_eq(_knobs.mode, 4, "and the press writes that row's id into the setting")
    assert_eq(button.selected_value(), 4, "with the button holding it again")


## The other row was never swallowed, and still is not.
func test_a_press_on_another_row_still_writes_it() -> void:
    var button := _button()
    _knobs.mode = 77
    _page.refresh()
    assert_true(button.pick_row("Raw"), "A row the button does not show takes a press")
    assert_eq(_knobs.mode, 9, "and writes its id")


## A value a row stands for is shown and held exactly as before.
func test_a_value_a_row_stands_for_is_held() -> void:
    var button := _button()
    _knobs.mode = 9
    _page.refresh()
    assert_eq(button.text, "Raw", "A stored value a row stands for is shown by that row")
    assert_eq(button.selected_value(), 9, "and held")
    assert_true(button.pick_row("Raw"), "so a press on it is a press")
    assert_eq(_knobs.mode, 9, "that leaves the setting where it is")
