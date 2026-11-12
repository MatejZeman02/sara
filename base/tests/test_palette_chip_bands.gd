## Each palette colour has its own bands.
##
## Each colour has its own shadows, midtones and highlights slider values and
## influence. The pass reads a
## colour's own three bands and an influence from the buffer, and the dialog
## keeps them per chip, shows the selected chip's on the sliders and hands them
## to the pass in the order of the palette.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

## A light yellow and a deep blue: black is nearer the blue and white nearer
## the yellow, so a pass that went to the nearest colour would map each to the
## wrong one of the two the bands ask for.
const YELLOW := Color(0.95, 0.85, 0.3, 1.0)
const NAVY := Color(0.05, 0.1, 0.4, 1.0)
const RED := Color(0.9, 0.15, 0.1, 1.0)
const BLUE := Color(0.1, 0.2, 0.85, 1.0)
## The grey at Oklab L one half, which is wholly midtones. An encoded 0.5 is
## not: its L is about 0.6, a tenth highlight, so a pass at full midtones moves
## it only nine tenths of the way.
const MIDDLE := Color(0.3886, 0.3886, 0.3886, 1.0)

var _easel: SaEasel = null
var _doc: SaDocument = null


func before_each() -> void:
    _easel = SaEasel.create_default(Vector2i(256, 256))
    _doc = _easel.document


func after_each() -> void:
    _easel.free()
    _easel = null
    _doc = null


func _texel(x: int, y: int) -> Color:
    var texture := _doc.active_layer.get_field(Vector2i.ZERO)
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return SaFieldSpec.decode_texel(bytes, texture.format, y * texture.size.x + x)


func _lab(color: Color) -> Vector3:
    return OkhsvConversions.linear_srgb_to_oklab(OkhsvConversions.srgb_transfer_function_inv(Vector3(color.r, color.g, color.b)))


## The colour lookup over the active layer as one step, the door a suite takes
## when no dialog is open.
func _lookup(values: Dictionary) -> bool:
    return SaPointAdjust.new().apply(_doc, _doc.active_layer, SaPointAdjust.PALETTE, values, "Colour Lookup")


func _dist(a: Color, b: Color) -> float:
    return _lab(a).distance_to(_lab(b))


## The first half: two chips with opposite bands, and a dark pixel
## maps to the first and a light one to the second, although each is nearer
## the other colour.
func test_a_dark_pixel_goes_to_the_shadow_chip_and_a_light_one_to_the_highlight_chip() -> void:
    assert_true(_dist(Color.BLACK, NAVY) < _dist(Color.BLACK, YELLOW), "the fixture: black is nearer the navy")
    assert_true(_dist(Color.WHITE, YELLOW) < _dist(Color.WHITE, NAVY), "and white is nearer the yellow")
    var values := {
        "palette": [YELLOW, NAVY],
        "bands":
        [
            {"shadows": 1.0, "midtones": 0.0, "highlights": 0.0, "influence": 1.0},
            {"shadows": 0.0, "midtones": 0.0, "highlights": 1.0, "influence": 1.0},
        ],
    }

    _doc.active_layer.fill(Color.BLACK)
    assert_true(_lookup(values), "the pass ran over black")
    var dark := _texel(64, 64)
    assert_true(_dist(dark, YELLOW) < 0.02, "and black went to the yellow, which owns the shadows, %s" % dark)

    _doc.active_layer.fill(Color.WHITE)
    assert_true(_lookup(values), "the pass ran over white")
    var light := _texel(64, 64)
    assert_true(_dist(light, NAVY) < 0.02, "and white went to the navy, which owns the highlights, %s" % light)

    _doc.active_layer.fill(MIDDLE)
    var grey := _lab(MIDDLE)
    assert_true(_lookup(values), "the pass ran over a middle grey")
    assert_true(
        _lab(_texel(64, 64)).distance_to(grey) < 1e-3, "and neither chip has any midtones, so the grey stayed where it was"
    )


## Influence is reach: twice the influence takes a pixel from a colour up to
## twice as near, and none takes nothing at all. The grey sits nearly on the
## line where the nearest of the two changes, so the pass blends them, and
## the colour that takes it is the one it lands nearer.
func test_influence_lets_the_further_colour_take_the_pixel() -> void:
    var grey := MIDDLE
    var near := RED if _dist(grey, RED) < _dist(grey, BLUE) else BLUE
    var far := BLUE if near == RED else RED
    var ratio := _dist(grey, far) / _dist(grey, near)
    assert_true(ratio < 1.8, "the fixture: the two are within the influence's reach of each other, %.2f" % ratio)
    var both := {"shadows": 0.0, "midtones": 1.0, "highlights": 0.0}

    _doc.active_layer.fill(grey)
    var even := {"palette": [near, far], "bands": [both.merged({"influence": 1.0}), both.merged({"influence": 1.0})]}
    assert_true(_lookup(even), "at even influence")
    var even_texel := _texel(10, 10)
    assert_true(_dist(even_texel, near) < _dist(even_texel, far), "the nearer colour takes the grey, %s" % even_texel)

    _doc.active_layer.fill(grey)
    var reach := {"palette": [near, far], "bands": [both.merged({"influence": 1.0}), both.merged({"influence": 2.0})]}
    assert_true(_lookup(reach), "with the further one at twice the influence")
    var reach_texel := _texel(10, 10)
    assert_true(_dist(reach_texel, far) < _dist(reach_texel, near), "the further colour takes it, %s" % reach_texel)

    _doc.active_layer.fill(grey)
    var none := {"palette": [near, far], "bands": [both.merged({"influence": 0.0}), both.merged({"influence": 1.0})]}
    assert_true(_lookup(none), "with the nearer one at no influence")
    assert_true(_dist(_texel(10, 10), far) < 0.02, "the nearer colour takes nothing")


## The buffer holds each colour's bands after the room for every colour, so
## the colours keep the offsets they had before bands, and a colour with no
## bands of its own takes the top-level three, clamped.
func test_the_bands_ride_the_buffer_after_the_colours() -> void:
    var values := {
        "palette": [RED, "not a colour", BLUE],
        "bands": [{"shadows": 0.25, "influence": 5.0}, {"shadows": 1.0}, {}],
        "midtones": 0.5,
        "highlights": 2.0,
    }
    var table := SaPointAdjust.table(values)
    var bands := SaPointAdjust.PALETTE_BANDS
    assert_eq(bands, SaPointAdjust.PALETTE_BASE + 1 + SaPointAdjust.PALETTE_MAX * 3, "the bands start after every colour's room")
    assert_almost_eq(table[SaPointAdjust.PALETTE_BASE], 2.0, 1e-6, "the word was skipped")
    assert_almost_eq(table[SaPointAdjust.PALETTE_BASE + 4], _lab(BLUE).x, 1e-5, "and blue is the second colour where F10 put it")
    assert_almost_eq(table[bands], 0.25, 1e-6, "red's own shadows")
    assert_almost_eq(table[bands + 1], 0.5, 1e-6, "its midtones from the top level")
    assert_almost_eq(table[bands + 2], 1.0, 1e-6, "its highlights from the top level, clamped")
    assert_almost_eq(table[bands + 3], SaPointAdjust.INFLUENCE_MAX, 1e-6, "and its influence clamped to the most")
    assert_almost_eq(table[bands + 4], 0.0, 1e-6, "blue took the entry after the word's, not the word's bands")
    assert_almost_eq(table[bands + 7], 1.0, 1e-6, "and the influence every colour starts at")


func _slide(dialog: SaPalettePanel, key: String, percent: float) -> void:
    var slider := dialog.find_child(key.capitalize() + "Slider", true, false) as FactorSlider
    slider.set_value_no_signal(percent)
    slider.value_changed.emit(percent)


func _slider(dialog: SaPalettePanel, key: String) -> float:
    return (dialog.find_child(key.capitalize() + "Slider", true, false) as FactorSlider).value


func _chip(dialog: SaPalettePanel, index: int) -> Button:
    return dialog.find_child("Chip%d" % index, true, false) as Button


## The second half: the table round-trips through the dialog's
## values. Each chip keeps its own sliders, a click on a chip selects it and
## nothing else, and the preview follows the selected chip's sliders.
func test_each_chip_keeps_its_own_sliders_and_the_table_round_trips() -> void:
    var dialog := SaPalettePanel.new([YELLOW, NAVY, Color.WHITE])
    var dummy := Control.new()
    dummy.add_child(dialog)
    var previews: Array[Dictionary] = []
    dialog.changed.connect(func() -> void: previews.append(dialog.values()))

    var rows := dialog.find_child("Rows", true, false) as Control
    assert_true(rows.modulate.a < 1.0, "with no chip selected the rows are dimmed")
    var first_slider := dialog.find_child("ShadowsSlider", true, false) as Control
    assert_eq(first_slider.mouse_filter, Control.MOUSE_FILTER_IGNORE, "and take no press")

    _chip(dialog, 0).pressed.emit()
    assert_true(rows.modulate.a > 0.99, "a click on a chip selects it and the rows come alive")
    _slide(dialog, "shadows", 100.0)
    assert_almost_eq(float(previews.back()["shadows"]), 1.0, 1e-6, "and the preview follows the selected chip's slider")

    _chip(dialog, 1).pressed.emit()
    assert_almost_eq(_slider(dialog, "shadows"), 0.0, 1e-6, "the second chip starts at the defaults")
    assert_almost_eq(_slider(dialog, "influence"), 100.0, 1e-6, "at the influence every colour starts at")
    _slide(dialog, "highlights", 100.0)
    _slide(dialog, "influence", 150.0)

    _chip(dialog, 0).pressed.emit()
    assert_almost_eq(_slider(dialog, "shadows"), 100.0, 1e-6, "and shows its own shadows again")
    assert_almost_eq(_slider(dialog, "highlights"), 0.0, 1e-6, "not the other chip's highlights")

    var values := dialog.values()
    assert_eq((values["palette"] as Array).size(), 3, "every chip in the palette")
    var table := SaPointAdjust.table(values)
    var bands := SaPointAdjust.PALETTE_BANDS
    assert_almost_eq(table[bands], 1.0, 1e-6, "the yellow's shadows reach the table")
    assert_almost_eq(table[bands + 2], 0.0, 1e-6, "with no highlights")
    assert_almost_eq(table[bands + 4], 0.0, 1e-6, "the navy's shadows are nothing")
    assert_almost_eq(table[bands + 6], 1.0, 1e-6, "its highlights are full")
    assert_almost_eq(table[bands + 7], 1.5, 1e-6, "and its influence is what the slider said")

    _chip(dialog, 0).pressed.emit()
    assert_eq((dialog.values()["palette"] as Array).size(), 3, "a click on the selected chip leaves it in")

    var double := InputEventMouseButton.new()
    double.button_index = MOUSE_BUTTON_LEFT
    double.pressed = true
    double.double_click = true
    _chip(dialog, 1).gui_input.emit(double)
    assert_eq(dialog._selected, 1, "a double click selects the chip under its picker")
    dialog.find_child("ChipEditor", true, false).set("visible", false)

    dialog.set_values({"select": 2, "midtones": 40})
    var set_values := dialog.values()
    assert_almost_eq(float(set_values["midtones"]), 0.4, 1e-6, "a scenario's select writes that chip alone")
    assert_almost_eq(float((set_values["bands"] as Array)[0]["midtones"]), 0.0, 1e-6, "and not the chips in the palette")

    # The window builds its page afresh on every open, so opening again is a
    # new panel.
    var reopened := SaPalettePanel.new([YELLOW])
    dummy.add_child(reopened)
    assert_almost_eq(_slider(reopened, "shadows"), 0.0, 1e-6, "opening again forgets every chip's bands")
    dummy.free()
