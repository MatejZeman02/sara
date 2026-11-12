## A choice button cleared to words of its own holds no value, so the row it last
## held is a pick again.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## On the running app: Preferences, Colour Spaces, a space with nothing
## larger to compare against, and then "Compare: Rec. 2020", the gamut compared a
## moment before, pressed. The button said Rec. 2020 and the diagram compared
## nothing, because `_apply_compare(null)` wrote the words and the mark and left
## the button holding Rec. 2020, and the guard reads a press on the value held
## as no move.
extends "res://tests/test_framework.gd"


func test_a_cleared_button_announces_the_row_it_last_held() -> void:
    var button := SaChoiceButton.new()
    button.set_choices([{"id": 0, "label": "Compare: Rec. 2020"}, {"id": 1, "label": "Compare: Display P3"}])
    button.select_value(0)
    var announced: Array = []
    button.choice_picked.connect(func(value: Variant) -> void: announced.append(value))

    button.clear_choice("Compare: nothing larger")

    assert_null(button.selected_value(), "A cleared button holds no value")
    assert_eq(button.text, "Compare: nothing larger", "and shows the words it was given")
    assert_false(button.popup.is_marked(SaChoiceButton.row_id_of(0)), "with no mark on the row it held")
    assert_false(button.popup.is_marked(SaChoiceButton.row_id_of(1)), "nor on the other")

    button.toggle_list()
    assert_true(button.popup.press_row(SaChoiceButton.row_id_of(0)), "The row it last held takes the press")
    assert_eq(announced, [0], "and is announced, because from nothing it is a move")
    assert_eq(button.selected_value(), 0, "The button holds it again")
    assert_eq(button.text, "Compare: Rec. 2020", "under its own words")
    assert_true(button.popup.is_marked(SaChoiceButton.row_id_of(0)), "and its row is marked")

    button.free()


## The sequence on the browser the page builds: a space compared
## against Rec. 2020, a space with nothing larger, and Rec. 2020 pressed again.
func test_the_browser_compares_the_gamut_it_compared_before_nothing_larger() -> void:
    var browser := SaColorSpaceBrowser.new()
    var rec2020 := SaGamut.rec2020()

    browser.select_space(_space_index(browser, SaColorSpace.oklab_p3()))
    assert_true(_compares(browser, rec2020), "Oklab over Display P3 compares Rec. 2020")

    browser.select_space(_space_index(browser, SaColorSpace.acescg()))
    assert_null(browser.diagram.compare, "ACEScg has nothing larger")
    assert_eq(browser.compare_option.text, "Compare: nothing larger", "and says so")
    assert_null(browser.compare_option.selected_value(), "holding no gamut behind the words")

    browser.compare_option.toggle_list()
    assert_true(browser.compare_option.popup.press_row(_compare_row(rec2020)), "Rec. 2020 takes the press")
    assert_true(_compares(browser, rec2020), "and the diagram compares it")
    assert_not_null(browser.solid.compare, "and so does the solid")

    browser.free()


## Where *space* sits in the browser's own list, found by id so a new preset does
## not move the test.
func _space_index(browser: SaColorSpaceBrowser, space: SaColorSpace) -> int:
    for i in browser.presets.size():
        if browser.presets[i].id == space.id:
            return i
    return -1


## The compare list's row for *gamut*, whose id is its place in `SaGamut.presets()`.
func _compare_row(gamut: SaGamut) -> StringName:
    var gamuts := SaGamut.presets()
    for i in gamuts.size():
        if gamuts[i].matches(gamut):
            return SaChoiceButton.row_id_of(i)
    return &""


func _compares(browser: SaColorSpaceBrowser, gamut: SaGamut) -> bool:
    return browser.diagram.compare != null and browser.diagram.compare.matches(gamut)
