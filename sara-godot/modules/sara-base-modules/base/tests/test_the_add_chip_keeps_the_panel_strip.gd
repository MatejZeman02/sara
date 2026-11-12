## The palette panel's `+` adds to the panel's own strip and keeps what the
## strip held.
##
## The strip is the kept swatches when the filter opened, then a record's
## colours and chips edited on the panel. A close of the `+` must not copy the
## kept swatches over it, which would lose the record's colour and the edit and
## leave the chosen indexes naming other chips. Here a record ticks a colour the store does
## not keep, a chip is edited, a colour is added with the `+`, and all three are
## on the strip with the ticks on the record's chip and the new one. The store
## is the live one, so what the test adds it takes away again.
extends "res://tests/test_framework.gd"

const RED := Color(1.0, 0.0, 0.0, 1.0)
const BLUE := Color(0.0, 0.0, 1.0, 1.0)
const RECORDED := Color(0.2, 0.8, 0.4, 1.0)
const EDITED := Color(0.9, 0.7, 0.1, 1.0)
const PICKED := Color(0.1, 0.3, 0.6, 1.0)


func _chip(panel: SaPalettePanel, index: int) -> Button:
    return panel.find_child("Chip%d" % index, true, false) as Button


func test_a_record_colour_an_edit_and_an_added_colour_all_stay() -> void:
    var panel := SaPalettePanel.new([RED, BLUE])
    var dummy := Control.new()
    dummy.add_child(panel)
    var kept_before := SaColors.swatches.size()
    panel.set_parameters({"palette": ["#" + RECORDED.to_html(true)], "bands": [{"shadows": 0.5}]})
    assert_eq(panel.swatches.size(), 3, "the record's colour joins the strip")

    panel.edit_chip(0)
    var picker := panel.find_child("ChipPicker", true, false) as ColorPicker
    picker.color = EDITED
    picker.color_changed.emit(EDITED)
    assert_true(panel.swatches[0].is_equal_approx(EDITED), "the chip is edited on the panel")

    var plus := panel.find_child("AddChip", true, false) as ColorPickerButton
    plus.pressed.emit()
    plus.color = PICKED
    plus.color_changed.emit(PICKED)
    plus.popup_closed.emit()

    assert_eq(panel.swatches.size(), 4, "the strip grew by one and dropped nothing")
    assert_true(panel.swatches[0].is_equal_approx(EDITED), "the edited chip keeps its edit")
    assert_true(panel.swatches[1].is_equal_approx(BLUE), "the untouched chip stays")
    assert_true(panel.swatches[2].is_equal_approx(RECORDED), "the record's colour stays")
    assert_true(panel.swatches[3].is_equal_approx(PICKED), "and the added colour is last")
    assert_eq(SaColors.swatches.size(), kept_before + 1, "the store still gets the added colour")
    assert_true(SaColors.swatches[kept_before].is_equal_approx(PICKED), "and it is the picked one")

    # Every chip is in the palette, so the record holds the whole
    # strip, and the chips the record did not carry hold no bands.
    var taken := panel.parameters()
    var palette := taken["palette"] as Array
    assert_eq(palette.size(), 4, "the palette is every chip of the strip")
    assert_eq(palette[2], "#" + RECORDED.to_html(true), "the record's colour where the strip has it")
    assert_eq(palette[3], "#" + PICKED.to_html(true), "then the added one")
    var bands := taken["bands"] as Array
    assert_almost_eq(float((bands[2] as Dictionary)["shadows"]), 0.5, 0.0001, "the record's chip keeps its own bands")
    assert_almost_eq(float((bands[1] as Dictionary)["shadows"]), 0.0, 0.0001, "and the plain chip has none")

    SaColors.remove_swatch(kept_before)
    assert_eq(SaColors.swatches.size(), kept_before, "the test leaves the store as it found it")
    dummy.free()
