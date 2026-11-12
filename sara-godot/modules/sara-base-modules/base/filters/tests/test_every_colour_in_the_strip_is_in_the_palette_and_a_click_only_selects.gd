## Every colour in the Colour Lookup's strip is in the palette, and a click
## only selects.
##
## A note on a picture of three spheres: "when
## clicking the color it does two things, it enables this colour and it also
## focuses the sliders for this colour. All the colours listed should be active
## and there should be a way to remove some." So a click on a chip selects it
## and leaves the palette as it was, and the `-` after the `+` takes the
## selected chip out of this filter's strip, which hands the pass the palette
## a strip without that colour would, and leaves the painter's kept swatches
## alone.
extends "res://tests/test_framework.gd"

const RED := Color(0.9, 0.15, 0.1, 1.0)
const GREEN := Color(0.2, 0.7, 0.25, 1.0)
const BLUE := Color(0.1, 0.2, 0.85, 1.0)

## Each chip's own bands, as percentages, all three apart so the sliders tell
## them apart.
const BANDS: Array[Dictionary] = [
    {"shadows": 100, "midtones": 10, "highlights": 0, "influence": 50},
    {"shadows": 20, "midtones": 100, "highlights": 30, "influence": 100},
    {"shadows": 0, "midtones": 40, "highlights": 100, "influence": 150},
]

var _dummy: Control = null


func after_each() -> void:
    if _dummy != null:
        _dummy.free()
        _dummy = null


func _panel(kept: Array[Color]) -> SaPalettePanel:
    var panel := SaPalettePanel.new(kept)
    _dummy = Control.new()
    _dummy.add_child(panel)
    for index in BANDS.size():
        if index < kept.size():
            var wanted := BANDS[index].duplicate()
            wanted["select"] = index
            panel.set_values(wanted)
    panel.select_chip(-1)
    return panel


func _chip(panel: SaPalettePanel, index: int) -> Button:
    return panel.find_child("Chip%d" % index, true, false) as Button


func _slider(panel: SaPalettePanel, key: String) -> float:
    return (panel.find_child(key.capitalize() + "Slider", true, false) as FactorSlider).value


func _hexes(values: Dictionary) -> Array:
    return SaPalettePanel.readable(values)["palette"]


func test_a_click_on_each_chip_selects_it_and_keeps_every_chip_in_the_palette() -> void:
    var panel := _panel([RED, GREEN, BLUE])
    var before := _hexes(panel.values())
    assert_eq(before.size(), 3, "the three colours of the strip are the palette before any click")
    var heard: Array = [0]
    panel.changed.connect(func() -> void: heard[0] += 1)
    for index in 3:
        _chip(panel, index).pressed.emit()
        assert_eq(panel._selected, index, "a click on chip %d selects it" % index)
        assert_eq(_hexes(panel.values()), before, "and every chip is still in the palette after it")
        for key: String in BANDS[index]:
            var said := "the %s slider shows chip %d's own" % [key, index]
            assert_almost_eq(_slider(panel, key), float(BANDS[index][key]), 1e-4, said)
    _chip(panel, 2).pressed.emit()
    assert_eq(panel._selected, 2, "a second click on the selected chip leaves it selected")
    assert_eq(_hexes(panel.values()), before, "and in the palette")
    assert_eq(heard[0], 0, "and no click asks the pass to run again, since the palette did not move")


func test_the_minus_takes_the_selected_chip_out_of_the_filter_and_not_out_of_the_swatches() -> void:
    var at := SaColors.swatches.size()
    for color: Color in [RED, GREEN, BLUE]:
        SaColors.add_swatch(color)
    var kept := SaColors.swatches.duplicate()
    var panel := _panel(SaColors.swatches.slice(at))
    var minus := panel.find_child("RemoveChip", true, false) as Button
    assert_not_null(minus, "the strip has a way to take a colour out")
    assert_true(minus.disabled, "which takes nothing while no chip is selected")

    _chip(panel, 1).pressed.emit()
    assert_false(minus.disabled, "and is live once one is")
    minus.pressed.emit()

    var values := panel.values()
    assert_eq(
        _hexes(values), ["#" + RED.to_html(false), "#" + BLUE.to_html(false)], "the palette the pass is handed has no green"
    )
    assert_eq(panel._selected, -1, "and no chip is selected after")
    assert_null(_chip(panel, 2), "the strip is two chips")
    assert_eq(SaColors.swatches, kept, "and the painter's kept swatches are as they were")

    # The picture moves as if the green had never been there: the table the
    # pass reads is the one a strip of the red and the blue alone gives.
    var without := SaPalettePanel.new([RED, BLUE])
    without.set_values({"select": 0, "shadows": 100, "midtones": 10, "highlights": 0, "influence": 50})
    without.set_values({"select": 1, "shadows": 0, "midtones": 40, "highlights": 100, "influence": 150})
    without.select_chip(-1)
    var alone := SaPointAdjust.table(without.values())
    assert_eq(SaPointAdjust.table(values), alone, "the pass reads what it would without the green")
    without.free()

    for i in 3:
        SaColors.remove_swatch(at)
    assert_eq(SaColors.swatches.size(), at, "the suite leaves the store as it found it")


func test_the_capture_step_takes_a_chip_out_the_way_the_minus_does() -> void:
    var panel := _panel([RED, GREEN, BLUE])
    var said := panel.capture_option_edit({"remove": 0})
    assert_true(said.contains("chips=2"), "the step says the strip is two chips: %s" % said)
    assert_eq(_hexes(panel.values()), ["#" + GREEN.to_html(false), "#" + BLUE.to_html(false)], "and the red is gone")
    _chip(panel, 0).pressed.emit()
    assert_almost_eq(_slider(panel, "midtones"), 100.0, 1e-4, "the green kept its own bands as it moved to the front")


## The pass takes at most `PALETTE_MAX` colours, so a strip of more would show
## chips that move nothing. It holds no more than that, the `+` goes dim once
## it is full, and a record opened over a full strip keeps its own colours.
func test_the_strip_holds_no_more_chips_than_the_pass_takes() -> void:
    var many: Array[Color] = []
    for i in SaPointAdjust.PALETTE_MAX + 8:
        many.append(Color(float(i) / 64.0, 0.5, 0.25, 1.0))
    var panel := _panel(many)
    assert_eq(panel.swatches.size(), SaPointAdjust.PALETTE_MAX, "the strip shows the first %d" % SaPointAdjust.PALETTE_MAX)
    assert_eq((panel.values()["palette"] as Array).size(), SaPointAdjust.PALETTE_MAX, "and every one is in the palette")
    assert_true((panel.find_child("AddChip", true, false) as Button).disabled, "the + takes no colour past the cap")
    panel.set_values({"colours": ["#ff00ff"]})
    assert_eq(panel.swatches.size(), SaPointAdjust.PALETTE_MAX, "and neither does the step")

    var record := SaPalettePanel.new(many)
    record.set_parameters({"palette": ["#102030ff", "#405060ff"], "bands": [{"shadows": 0.5}, {"highlights": 1.0}]})
    var hexes := _hexes(record.values())
    assert_eq(hexes.size(), SaPointAdjust.PALETTE_MAX, "a record over a full strip keeps it at the cap")
    assert_true(hexes.has("#102030") and hexes.has("#405060"), "with both of the record's colours in it")
    var table := SaPointAdjust.table(record.values())
    assert_almost_eq(table[SaPointAdjust.PALETTE_BASE], float(SaPointAdjust.PALETTE_MAX), 1e-6, "all of which the pass reads")
    record.free()
