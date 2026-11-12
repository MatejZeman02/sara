## A double click on a palette chip edits its colour, a single click still
## toggles it, and the typed box is gone.
##
## Double clicking on the colour edits it and does not just toggle the selection,
## and the line edit under the chips is gone. Built detached the
## way `test_palette_add_chip.gd` builds the dialog, so the picker's popup is
## never mapped, and the claims are on the popup's visibility, the picker's
## colour and what the dialog reports to the pass. The picker on screen is
## `scenarios/the-palette-dialogs-chips-edit-on-a-double-click-and-the-typed-box-goes.json`.
extends "res://tests/test_framework.gd"

const RED := Color(1.0, 0.0, 0.0, 1.0)
const BLUE := Color(0.0, 0.0, 1.0, 1.0)
const GREEN := Color(0.0, 0.8, 0.2, 1.0)


func _dialog() -> Array:
    var dialog := SaPalettePanel.new([RED, BLUE])
    var dummy := Control.new()
    dummy.add_child(dialog)
    return [dialog, dummy]


func _chip(dialog: SaPalettePanel, index: int) -> Button:
    return dialog.find_child("Chip%d" % index, true, false) as Button


func _press(double: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = true
    event.double_click = double
    return event


func test_a_double_click_opens_the_picker_on_that_chips_colour() -> void:
    var built := _dialog()
    var dialog: SaPalettePanel = built[0]
    var chip := _chip(dialog, 1)
    assert_not_null(chip, "The dialog has a second chip")
    assert_false(dialog._chip_editor.visible, "The picker is shut to begin with")

    chip.gui_input.emit(_press(true))
    assert_true(dialog._chip_editor.visible, "A double click opens the picker")
    assert_eq(dialog._editing, 1, "on the chip that was double clicked")
    assert_true(dialog._chip_picker.color.is_equal_approx(BLUE), "at that chip's own colour")
    built[1].free()


func test_a_pick_writes_the_chip_and_the_palette_the_pass_takes() -> void:
    var built := _dialog()
    var dialog: SaPalettePanel = built[0]
    dialog.set_values({"chips": [1]})
    _chip(dialog, 1).gui_input.emit(_press(true))

    dialog._chip_picker.color = GREEN
    dialog._chip_picker.color_changed.emit(GREEN)
    assert_true(dialog.swatches[1].is_equal_approx(GREEN), "The chip being edited takes the picked colour")
    var palette := dialog.values()["palette"] as Array
    assert_eq(palette.size(), 2, "and every chip is still in the palette")
    assert_true((palette[1] as Color).is_equal_approx(GREEN), "which the pass now reads with the picked colour")
    assert_eq(_chip(dialog, 1).tooltip_text, "#" + GREEN.to_html(false), "and the chip says so")
    assert_true(dialog.swatches[0].is_equal_approx(RED), "The other chip is untouched")
    built[1].free()


func test_a_pick_does_not_rewrite_the_kept_swatches() -> void:
    var before := SaColors.swatches.duplicate()
    var dialog := SaPalettePanel.new(SaColors.swatches)
    var dummy := Control.new()
    dummy.add_child(dialog)
    if dialog.swatches.is_empty():
        dummy.free()
        return
    _chip(dialog, 0).gui_input.emit(_press(true))
    dialog._chip_picker.color = GREEN
    dialog._chip_picker.color_changed.emit(GREEN)
    assert_eq(SaColors.swatches, before, "Editing a chip in the filter leaves the painter's own swatches as they were")
    dummy.free()


func test_a_single_click_is_still_only_the_selection() -> void:
    var built := _dialog()
    var dialog: SaPalettePanel = built[0]
    var chip := _chip(dialog, 0)
    chip.gui_input.emit(_press(false))
    assert_false(dialog._chip_editor.visible, "A single press opens no picker")
    chip.pressed.emit()
    assert_eq(dialog._selected, 0, "and the click selects the chip")
    assert_eq((dialog.values()["palette"] as Array).size(), 2, "with the palette still every chip")
    built[1].free()


func test_the_typed_colours_box_is_gone() -> void:
    var built := _dialog()
    var dialog: SaPalettePanel = built[0]
    assert_null(dialog.find_child("TypedColours", true, false), "There is no TypedColours box")
    # Two kinds of line edit belong to other controls and stay. The engine's
    # own `ColorPicker` carries a hex field and its spin boxes' edits, in the `+`
    # chip's picker and the chip editor alike, and each of the three sliders is a
    # `FactorSlider` with a field for typing its value. The claim is that no line
    # edit stands in the dialog outside one of those.
    var loose := 0
    for node in dialog.find_children("*", "LineEdit", true, false):
        var owned := false
        var up := node.get_parent()
        while up != null and up != dialog:
            if up is ColorPicker or up is FactorSlider:
                owned = true
                break
            up = up.get_parent()
        if not owned:
            loose += 1
    assert_eq(loose, 0, "and no line edit in the dialog outside a colour picker or a slider's own field")
    built[1].free()


## A scenario's `colours` become a chip each, after
## the strip's, so a scenario that seeded a palette that way still seeds it.
func test_a_scenarios_colours_become_chips_after_the_strips() -> void:
    var built := _dialog()
    var dialog: SaPalettePanel = built[0]
    dialog.set_values({"chips": [1], "colours": ["#102030", "junk"]})
    var palette := dialog.values()["palette"] as Array
    assert_eq(palette.size(), 3, "the two chips and one colour, the junk word dropped")
    assert_true((palette[1] as Color).is_equal_approx(BLUE), "the strip's chips first")
    assert_true((palette[2] as Color).is_equal_approx(Color.html("#102030")), "then the colour, as a chip of its own")
    assert_not_null(_chip(dialog, 2), "which is on the strip")
    built[1].free()
