## Colour Lookup opens with a hint, and Escape on the `+` adds no chip.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The filter on an empty palette says what to do, and pressing `+` and then
## Escape must not keep a `#121513` chip.
## A `ColorPickerButton` hands back the colour it opened on when Escape is
## pressed, so the cell has to open on the foreground, set before the popup
## takes the colour and not on `pressed`. This suite
## drives the panel through its capture door, `press_add`, `pick_add`, `add` and
## `close_add`, which closes the way Escape does, and counts chips. The real key
## on the running app is the scenario of the same name. The store is the live
## one, so what a test adds it takes away again.
extends "res://tests/test_framework.gd"

const RED := Color(1.0, 0.0, 0.0, 1.0)
const FLOAT_FOREGROUND := Color(0.2, 0.5, 0.9, 1.0)

var _foreground: Color = Color.BLACK
var _kept: int = 0


func before_each() -> void:
    _foreground = SaColors.foreground
    _kept = SaColors.swatches.size()


func after_each() -> void:
    SaColors.foreground = _foreground
    var removals := SaColors.swatches.size()
    while SaColors.swatches.size() > _kept and removals > 0:
        SaColors.remove_swatch(SaColors.swatches.size() - 1)
        removals -= 1
    assert_true(SaColors.swatches.size() <= _kept, "The swatches a test added go again")


func _empty_panel() -> SaPalettePanel:
    var none: Array[Color] = []
    var panel := SaPalettePanel.new(none)
    Control.new().add_child(panel)
    return panel


func _free(panel: SaPalettePanel) -> void:
    panel.get_parent().free()


func _hint(panel: SaPalettePanel) -> Label:
    return panel.find_child("EmptyHint", true, false) as Label


func _chips(panel: SaPalettePanel) -> int:
    return (panel.find_child("Chips", true, false) as HFlowContainer).get_child_count() - 2


func test_an_empty_strip_opens_with_the_hint() -> void:
    var panel := _empty_panel()
    var hint := _hint(panel)
    assert_not_null(hint, "the strip has a hint line")
    assert_true(hint.visible, "and shows it while there is no chip")
    var wanted := "No colours yet. Click + to add one, or save swatches in the Colour Picker docker and reopen this."
    assert_eq(hint.text, wanted, "saying how a colour gets there")
    assert_eq(_chips(panel), 0, "over the + alone")
    assert_eq(hint.get_parent(), panel, "in the panel's own column")
    _free(panel)


func test_a_strip_with_a_chip_shows_no_hint() -> void:
    var panel := SaPalettePanel.new([RED])
    Control.new().add_child(panel)
    assert_false(_hint(panel).visible, "a chip needs no telling")
    _free(panel)


func test_the_plus_then_escape_adds_no_chip_and_leaves_the_hint() -> void:
    var panel := _empty_panel()
    panel.capture_option_edit({"press_add": true})
    panel.capture_option_edit({"close_add": true})
    assert_eq(_chips(panel), 0, "no chip on the strip")
    assert_eq(SaColors.swatches.size(), _kept, "and no swatch in the store")
    assert_true((panel.values()["palette"] as Array).is_empty(), "and nothing in the palette")
    assert_true(_hint(panel).visible, "the hint stays")
    _free(panel)


func test_escape_on_a_foreground_that_is_not_eight_bit_adds_nothing() -> void:
    SaColors.foreground = FLOAT_FOREGROUND
    var panel := _empty_panel()
    panel.capture_option_edit({"press_add": true})
    var plus := panel.find_child("AddChip", true, false) as ColorPickerButton
    assert_true(plus.color.is_equal_approx(FLOAT_FOREGROUND), "the picker opens on the foreground")
    plus.color_changed.emit(Color.html(FLOAT_FOREGROUND.to_html(true)))
    panel.capture_option_edit({"close_add": true})
    assert_eq(_chips(panel), 0, "a colour a hex field would round is still no pick")
    _free(panel)


func test_a_look_at_the_picker_adds_nothing_twice_over() -> void:
    var panel := _empty_panel()
    for look in 2:
        panel.capture_option_edit({"press_add": true})
        panel.capture_option_edit({"close_add": true})
    assert_eq(_chips(panel), 0, "the second look is as empty as the first")
    assert_true(_hint(panel).visible, "and the hint is still up")
    _free(panel)


func test_the_plus_a_pick_and_a_close_adds_the_chip_and_removes_the_hint() -> void:
    var panel := _empty_panel()
    panel.capture_option_edit({"press_add": true})
    panel.capture_option_edit({"add": "#1a4d99"})
    assert_eq(_chips(panel), 1, "the strip has the chip")
    assert_eq(SaColors.swatches.size(), _kept + 1, "the store gained the swatch")
    assert_false(_hint(panel).visible, "and the hint goes")
    var palette := panel.values()["palette"] as Array
    assert_eq(palette.size(), 1, "the new chip is in the palette")
    assert_eq((palette[0] as Color).to_html(false), "1a4d99", "and it is the colour picked")
    _free(panel)


func test_a_pick_closed_with_escape_is_kept() -> void:
    var panel := _empty_panel()
    panel.capture_option_edit({"press_add": true})
    panel.capture_option_edit({"pick_add": "#1a4d99"})
    panel.capture_option_edit({"close_add": true})
    assert_eq(_chips(panel), 1, "closing is the choice, so the pick stays")
    var palette := panel.values()["palette"] as Array
    assert_eq((palette[0] as Color).to_html(false), "1a4d99", "and it is the picked colour, not the one Escape hands back")
    _free(panel)


func test_the_cell_goes_back_to_its_own_colour_after_a_close() -> void:
    var panel := _empty_panel()
    var plus := panel.find_child("AddChip", true, false) as ColorPickerButton
    var resting := plus.color
    panel.capture_option_edit({"press_add": true})
    assert_false(plus.color.is_equal_approx(resting), "open on the foreground")
    panel.capture_option_edit({"close_add": true})
    assert_true(plus.color.is_equal_approx(resting), "back to its own colour once shut")
    _free(panel)
