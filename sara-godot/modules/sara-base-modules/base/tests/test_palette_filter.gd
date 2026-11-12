## The palette filter: every pixel towards the nearest colour of a palette in
## Oklab, blended with the next nearest where the two are close, by three
## amounts weighted by the lightness bands.
##
## The filter applies a palette to a selected image, taking the shadows and
## moving their colour to the palette's. Read back pixel by pixel like the other passes,
## because the invariant is the same: a slider at nothing leaves the picture
## exactly as it was, the selection is honoured, and it is one history step.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const RED := Color(0.9, 0.15, 0.1, 1.0)
const BLUE := Color(0.1, 0.2, 0.85, 1.0)

var _easel: SaEasel = null
var _doc: SaDocument = null


func before_each() -> void:
    _easel = SaEasel.create_default(Vector2i(512, 512))
    _doc = _easel.document


func after_each() -> void:
    _easel.free()
    _easel = null
    _doc = null


func _texel(x: int, y: int) -> Color:
    @warning_ignore("integer_division")
    var grid := Vector2i(x / SaChunk.SIZE, y / SaChunk.SIZE)
    var texture := _doc.active_layer.get_field(grid)
    if texture == null:
        return Color.TRANSPARENT
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return SaFieldSpec.decode_texel(
        bytes, texture.format, (y - grid.y * SaChunk.SIZE) * texture.size.x + (x - grid.x * SaChunk.SIZE)
    )


## The colour lookup over the active layer as one step, the door a suite takes
## when no dialog is open.
func _lookup(values: Dictionary) -> bool:
    return SaPointAdjust.new().apply(_doc, _doc.active_layer, SaPointAdjust.PALETTE, values, "Colour Lookup")


func _dist(a: Color, b: Color) -> float:
    return Vector3(a.r, a.g, a.b).distance_to(Vector3(b.r, b.g, b.b))


func _lab(color: Color) -> Vector3:
    return OkhsvConversions.linear_srgb_to_oklab(OkhsvConversions.srgb_transfer_function_inv(Vector3(color.r, color.g, color.b)))


## The buffer's tail: a count, then each colour as Oklab L, a and b, strings
## read as colours and anything over the room cut, and the three amounts in
## the first three parameter slots, clamped.
func test_the_palette_rides_the_buffer_above_colour_balance() -> void:
    var values := {"palette": [RED, "#1933d9", "not a colour", 7], "shadows": 1.5, "midtones": 0.5, "highlights": -1.0}
    var table := SaPointAdjust.table(values)
    assert_eq(SaPointAdjust.EQUALIZE_BASE - SaPointAdjust.PALETTE_BASE, SaPointAdjust.PALETTE_FLOATS, "the palette took its room")
    assert_almost_eq(table[SaPointAdjust.PALETTE_BASE], 2.0, 1e-6, "two of the four entries are colours")
    var red := _lab(RED)
    assert_almost_eq(table[SaPointAdjust.PALETTE_BASE + 1], red.x, 1e-5, "the first is red's Oklab L")
    assert_almost_eq(table[SaPointAdjust.PALETTE_BASE + 2], red.y, 1e-5, "its a")
    assert_almost_eq(table[SaPointAdjust.PALETTE_BASE + 3], red.z, 1e-5, "and its b")
    var blue := _lab(Color.html("#1933d9"))
    assert_almost_eq(table[SaPointAdjust.PALETTE_BASE + 4], blue.x, 1e-5, "and the typed one follows it")

    var params := SaPointAdjust.params_for(SaPointAdjust.PALETTE, values)
    assert_eq(params, [1.0, 0.5, 0.0, 0.0, 0.0], "the amounts are the first three slots, clamped to 0 and 1")

    var many: Array = []
    for i in 40:
        many.append(Color(float(i) / 40.0, 0.5, 0.5))
    assert_eq(SaPointAdjust.palette_chips({"palette": many}).size(), SaPointAdjust.PALETTE_MAX, "and the room is the cap")


## The zero: every slider at nothing is the picture before, to the
## bit, whatever the palette.
func test_every_slider_at_nothing_changes_nothing() -> void:
    _doc.active_layer.fill(Color(0.3, 0.5, 0.2, 1.0))
    var values := {"palette": [RED, BLUE], "shadows": 0.0, "midtones": 0.0, "highlights": 0.0}
    assert_true(_lookup(values), "the pass ran")
    var texel := _texel(100, 100)
    assert_almost_eq(texel.r, 0.3, 1e-6, "and the red is what it was")
    assert_almost_eq(texel.g, 0.5, 1e-6, "the green")
    assert_almost_eq(texel.b, 0.2, 1e-6, "and the blue")


## Black is wholly a shadow, and the shadows slider at full takes it towards
## the palette colours, most of the way to the one nearest it in Oklab, which
## for black is the darker of a red and a blue. Black sits near the line where
## the nearest changes, so the pass blends the two rather than jumping to one,
## and it lands between them, nearer the nearest. The highlights slider at
## full leaves it alone, because black is no highlight. How far a pixel moves
## is read with the nearest colour alone, which the blend leaves as it was.
## Black rather than a dark grey, because the bands are colour balance's
## partition of Oklab lightness: a grey of 0.2 is only a third shadow and two
## thirds midtone, and the slider at full moves it a third of the way, which is
## the model answering rather than the model failing.
func test_the_shadows_slider_moves_a_shadow_to_the_nearest_palette_colour() -> void:
    _doc.active_layer.fill(Color(0.0, 0.0, 0.0, 1.0))
    var black := _lab(Color(0.0, 0.0, 0.0))
    var nearest := BLUE if black.distance_to(_lab(BLUE)) < black.distance_to(_lab(RED)) else RED
    var further := RED if nearest == BLUE else BLUE

    assert_true(_lookup({"palette": [RED, BLUE], "highlights": 1.0}), "highlights alone ran")
    var untouched := _texel(64, 64)
    assert_almost_eq(untouched.r, 0.0, 1e-4, "and black is no highlight, so it stayed")

    assert_true(_lookup({"palette": [RED, BLUE], "shadows": 1.0}), "then shadows at full")
    var moved := _lab(_texel(64, 64))
    var line := _lab(further) - _lab(nearest)
    var along := clampf((moved - _lab(nearest)).dot(line) / line.length_squared(), 0.0, 1.0)
    assert_true(
        moved.distance_to(_lab(nearest) + line * along) < 0.02, "and it lands on the line between the two colours, %s" % moved
    )
    assert_true(along < 0.5, "nearer the nearest palette colour, %.2f of the way to the other" % along)

    _doc.active_layer.fill(Color(0.2, 0.2, 0.2, 1.0))
    var grey := _lab(Color(0.2, 0.2, 0.2))
    var share := smoothstep(0.5, 0.0, grey.x)
    assert_true(_lookup({"palette": [nearest], "shadows": 1.0}), "and a dark grey")
    var part := _lab(_texel(64, 64))
    var expected := grey.lerp(_lab(nearest), share)
    assert_true(
        part.distance_to(expected) < 0.02, "moves its shadow share of the way, %.2f, %s against %s" % [share, part, expected]
    )


## Half the slider is half the way there, in Oklab, so the midpoint is the
## perceptual middle rather than an RGB average. Read with the nearest colour
## alone, so the blend between two colours does not move the target.
func test_half_the_slider_is_half_the_way_in_oklab() -> void:
    _doc.active_layer.fill(Color(0.5, 0.5, 0.5, 1.0))
    var grey := _lab(Color(0.5, 0.5, 0.5))
    var nearest := RED if grey.distance_to(_lab(RED)) < grey.distance_to(_lab(BLUE)) else BLUE
    assert_true(_lookup({"palette": [nearest], "midtones": 0.5}), "midtones at half ran")
    var moved := _lab(_texel(64, 64))
    var expected := grey.lerp(_lab(nearest), 0.5)
    assert_true(moved.distance_to(expected) < 0.02, "and the pixel sits halfway in Oklab, %s against %s" % [moved, expected])


## The pass honours the selection, dispatches over nothing outside it, and is
## one history step, the way every other adjustment is.
func test_the_pass_honours_the_selection_and_is_one_step() -> void:
    _doc.active_layer.fill(Color(0.0, 0.0, 0.0, 1.0))
    _doc.selection.select_rect(Rect2i(0, 0, 128, 128))
    var steps_before: int = _doc.history.step_count()

    assert_true(_lookup({"palette": [RED, BLUE], "shadows": 1.0}), "applied")

    assert_true(_dist(_texel(64, 64), Color.BLACK) > 0.3, "inside the selection the pass lands")
    assert_almost_eq(_texel(200, 64).b, 0.0, 1e-4, "outside it, in the same chunk, nothing changes")
    assert_almost_eq(_texel(300, 300).b, 0.0, 1e-4, "nor in a chunk the selection leaves out")
    assert_eq(_doc.history.step_count(), steps_before + 1, "and it is one history step")
    assert_true(_doc.undo(), "which undoes")
    assert_almost_eq(_texel(64, 64).b, 0.0, 1e-4, "putting the pixels back")


## The panel says what the pass takes: chips and a scenario's colours in order, and
## the sliders as fractions, and opens at nothing every time.
func test_the_dialog_reports_its_palette_and_its_sliders_in_the_units_the_pass_takes() -> void:
    var dialog := SaPalettePanel.new([RED, BLUE, Color.WHITE])
    var dummy := Control.new()
    dummy.add_child(dialog)
    var at_rest := dialog.values()
    assert_eq((at_rest["palette"] as Array).size(), 3, "every chip in the palette at first")
    for band: Dictionary in at_rest["bands"] as Array:
        assert_almost_eq(float(band["shadows"]) + float(band["midtones"]) + float(band["highlights"]), 0.0, 1e-6, "at no reach")
    assert_almost_eq(float(at_rest["shadows"]), 0.0, 1e-6, "and every slider at nothing")

    dialog.set_values({"chips": [2, 0], "colours": ["#102030", "junk"], "shadows": 100, "midtones": 25})
    var values := dialog.values()
    var palette := values["palette"] as Array
    assert_eq(palette.size(), 4, "three chips and one colour, the junk word dropped")
    assert_true((palette[0] as Color).is_equal_approx(RED), "chips in swatch order, red first")
    assert_true((palette[2] as Color).is_equal_approx(Color.WHITE), "white third")
    assert_almost_eq(float((values["bands"] as Array)[1]["shadows"]), 0.0, 1e-6, "the blue the step did not name holds no band")
    assert_true(
        (palette[3] as Color).is_equal_approx(Color.html("#102030")), "then the colour a scenario named, a chip of its own"
    )
    assert_almost_eq(float(values["shadows"]), 1.0, 1e-6, "a hundred percent is one")
    assert_almost_eq(float(values["midtones"]), 0.25, 1e-6, "and a quarter is a quarter")

    # The window builds its page afresh on every open, so opening again is a
    # new panel.
    var reopened := SaPalettePanel.new([RED])
    dummy.add_child(reopened)
    var again := reopened.values()
    assert_eq((again["palette"] as Array).size(), 1, "and opening again is the strip again")
    assert_almost_eq(float((again["bands"] as Array)[0]["shadows"]), 0.0, 1e-6, "at no bands")
    dummy.free()
