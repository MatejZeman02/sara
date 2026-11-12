## The Palette dialog's strip ends in a `+` that keeps a picked colour as a
## swatch.
##
## The scenario of the same name is the other half, the
## picker open on screen and the chip in the row after a close and a reopen.
## Here the wiring: the `+` is the cell after the last chip, the `-` that takes one out
## after it, it reflows with
## them, a close after a pick adds through `SaColors.add_swatch` and selects the
## new chip, and a close with nothing picked adds nothing. The store is the
## live one, so what a test adds it takes away again.
extends "res://tests/test_framework.gd"

const RED := Color(1.0, 0.0, 0.0, 1.0)
const BLUE := Color(0.0, 0.0, 1.0, 1.0)


func _add_chip(dialog: SaPalettePanel) -> ColorPickerButton:
    return dialog.find_child("AddChip", true, false) as ColorPickerButton


func test_the_plus_is_the_cell_after_the_last_chip() -> void:
    var dialog := SaPalettePanel.new([RED, BLUE])
    var dummy := Control.new()
    dummy.add_child(dialog)
    var chips := dialog.find_child("Chips", true, false) as HFlowContainer
    assert_eq(chips.get_child_count(), 4, "two chips, the + and the -")
    assert_eq(String(chips.get_child(2).name), "AddChip", "and the + is after the chips")
    var reopened := SaPalettePanel.new([RED])
    dummy.add_child(reopened)
    chips = reopened.find_child("Chips", true, false) as HFlowContainer
    assert_eq(chips.get_child_count(), 3, "one chip, the + and the - after a reopen")
    assert_eq(String(chips.get_child(1).name), "AddChip", "still after the chips")
    assert_eq((chips.get_child(1) as Control).tooltip_text, "Pick a colour to keep as a swatch.", "and it says what it does")
    dummy.free()


func test_closing_the_picker_after_a_pick_keeps_the_colour_and_selects_it() -> void:
    var dialog := SaPalettePanel.new(SaColors.swatches)
    var dummy := Control.new()
    dummy.add_child(dialog)
    var before := SaColors.swatches.size()
    var plus := _add_chip(dialog)
    var picked := Color(0.1, 0.6, 0.3, 1.0)
    plus.pressed.emit()
    plus.color = picked
    plus.color_changed.emit(picked)
    plus.popup_closed.emit()
    assert_eq(SaColors.swatches.size(), before + 1, "the store is one swatch longer")
    assert_true(SaColors.swatches[before].is_equal_approx(picked), "and it is the picked colour")
    var chips := dialog.find_child("Chips", true, false) as HFlowContainer
    assert_eq(chips.get_child_count(), before + 3, "the strip grew a chip, the + and the - still after it")
    assert_eq(String(chips.get_child(before + 1).name), "AddChip", "the + is after the chips")
    var palette := dialog.values()["palette"] as Array
    assert_eq(palette.size(), before + 1, "the new chip is in the palette with every other")
    assert_true((palette[before] as Color).is_equal_approx(picked), "and it is the picked colour")
    assert_eq(dialog._selected, before, "selected, so its bands are under the strip")
    SaColors.remove_swatch(before)
    assert_eq(SaColors.swatches.size(), before, "the test leaves the store as it found it")
    dummy.free()


func test_closing_an_untouched_picker_adds_nothing() -> void:
    var dialog := SaPalettePanel.new(SaColors.swatches)
    var dummy := Control.new()
    dummy.add_child(dialog)
    var before := SaColors.swatches.size()
    var plus := _add_chip(dialog)
    plus.pressed.emit()
    plus.popup_closed.emit()
    assert_eq(SaColors.swatches.size(), before, "a look costs no swatch")
    dummy.free()
