## The magic wand: a contiguous flood over the mask, one chunk at a time,
## that crosses chunk seams, stops at a colour edge, honours the tolerance,
## reads the merged picture or the layer alone, joins the selection in the
## three modes, and allocates only the chunks it reaches.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

const RED := Color(1.0, 0.0, 0.0, 1.0)
const NEAR_RED := Color(0.9, 0.0, 0.0, 1.0)
const BLUE := Color(0.0, 0.0, 1.0, 1.0)

var _easel: SaEasel = null
var _doc: SaDocument = null


## Three by three chunks, so a region can sit in a corner and leave most
## chunks untouched.
func before_each() -> void:
    _easel = SaEasel.create_default(Vector2i(768, 768))
    _doc = _easel.document


func after_each() -> void:
    _easel.free()
    _easel = null
    _doc = null


func _coverage(x: int, y: int) -> float:
    @warning_ignore("integer_division")
    var chunk: SaChunk = _doc.selection.chunks.get(Vector2i(x / SaChunk.SIZE, y / SaChunk.SIZE), null)
    if chunk == null:
        return 0.0
    var texture := chunk.field(SaSelection.FIELD)
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return bytes.decode_float(((y % SaChunk.SIZE) * texture.size.x + x % SaChunk.SIZE) * 4)


## Fills *rect* of the active layer with *color* through a masked fill, then
## drops the selection, so a region can cross seams on a transparent layer.
func _paint_rect(rect: Rect2i, color: Color) -> void:
    _doc.selection.select_rect(rect)
    _doc.fill_layer(color, _doc.active_layer)
    _doc.selection.deselect()


func _flood(start: Vector2i, tolerance: float = 0.05, mode: int = SaSelection.Mode.REPLACE, merged: bool = false) -> int:
    var wand := SaWand.new()
    var output: SaTexture = null
    if merged:
        _easel.request_full_composite()
        _easel.process_pending_composite()
        output = _easel.output
    return wand.flood(_doc, start, tolerance, mode, output, _doc.active_layer)


func test_the_flood_fills_a_region_across_seams_and_stops_at_its_edge() -> void:
    _paint_rect(Rect2i(100, 100, 300, 300), RED)
    var reached := _flood(Vector2i(250, 250))
    assert_eq(reached, 4, "A square over one seam each way reaches four chunks")
    assert_eq(_doc.selection.chunks.size(), 4, "and the mask holds those four, not the nine of the canvas")
    assert_almost_eq(_coverage(250, 250), 1.0, 0.001, "The start is selected")
    assert_almost_eq(_coverage(110, 110), 1.0, 0.001, "and the far corner of the region")
    assert_almost_eq(_coverage(390, 390), 1.0, 0.001, "across both seams")
    assert_almost_eq(_coverage(256, 300), 1.0, 0.001, "on the seam itself")
    assert_almost_eq(_coverage(50, 50), 0.0, 0.001, "and nothing outside the red")
    assert_almost_eq(_coverage(410, 250), 0.0, 0.001, "just past its edge either")
    # The box is the coverage and not the chunks that hold it. This read (0, 0,
    # 512, 512), the union of the four chunk rectangles, until `_merge` was
    # made to measure every branch the way the subtract branch already did.
    # `SaCrop.crop_to_selection` resizes to this and to nothing else, so the
    # difference was a canvas with a band of unselected ground on two sides.
    assert_eq(_doc.selection.bounds, Rect2i(100, 100, 300, 300), "The bounds are the red square, not the chunks it sits in")


func test_the_flood_from_outside_goes_around_and_not_into_a_hole() -> void:
    _paint_rect(Rect2i(100, 100, 300, 300), RED)
    _paint_rect(Rect2i(200, 200, 100, 100), Color(0.0, 0.0, 0.0, 0.0))
    var reached := _flood(Vector2i(20, 20))
    assert_eq(reached, 9, "The transparent outside reaches every chunk")
    assert_almost_eq(_coverage(20, 20), 1.0, 0.001, "The outside is selected")
    assert_almost_eq(_coverage(700, 700), 1.0, 0.001, "all the way round")
    assert_almost_eq(_coverage(150, 150), 0.0, 0.001, "The red ring is not")
    assert_almost_eq(_coverage(250, 250), 0.0, 0.001, "and the transparent hole inside it is not reached")


func test_the_tolerance_decides_what_joins() -> void:
    _paint_rect(Rect2i(100, 100, 200, 300), RED)
    _paint_rect(Rect2i(300, 100, 200, 300), NEAR_RED)
    _flood(Vector2i(150, 250), 0.05)
    assert_almost_eq(_coverage(150, 250), 1.0, 0.001, "The red is selected")
    assert_almost_eq(_coverage(400, 250), 0.0, 0.001, "and the nearly red is not at a tight tolerance")
    _flood(Vector2i(150, 250), 0.2)
    assert_almost_eq(_coverage(400, 250), 1.0, 0.001, "but joins at a loose one")


func test_merged_reads_the_picture_and_the_layer_reads_itself() -> void:
    _paint_rect(Rect2i(100, 100, 200, 200), RED)
    _flood(Vector2i(50, 50), 0.05, SaSelection.Mode.REPLACE, true)
    assert_almost_eq(_coverage(50, 50), 1.0, 0.001, "Merged, the grey background around the red is one region")
    assert_almost_eq(_coverage(150, 150), 0.0, 0.001, "that stops at the red")
    _flood(Vector2i(50, 50), 0.05, SaSelection.Mode.REPLACE, false)
    assert_almost_eq(_coverage(50, 50), 1.0, 0.001, "On the layer alone the transparent outside is the region")
    assert_almost_eq(_coverage(150, 150), 0.0, 0.001, "and the red is still not it")


func test_add_and_subtract_join_the_selection() -> void:
    _paint_rect(Rect2i(100, 100, 100, 100), RED)
    _paint_rect(Rect2i(400, 400, 100, 100), BLUE)
    _flood(Vector2i(150, 150))
    _flood(Vector2i(450, 450), 0.05, SaSelection.Mode.ADD)
    assert_almost_eq(_coverage(150, 150), 1.0, 0.001, "The red stays selected")
    assert_almost_eq(_coverage(450, 450), 1.0, 0.001, "and the blue joins it")
    _flood(Vector2i(150, 150), 0.05, SaSelection.Mode.SUBTRACT)
    assert_almost_eq(_coverage(150, 150), 0.0, 0.001, "Subtracting the red takes it out")
    assert_almost_eq(_coverage(450, 450), 1.0, 0.001, "and leaves the blue")


func test_a_seed_off_the_canvas_selects_nothing() -> void:
    assert_eq(_flood(Vector2i(-5, 10)), 0, "Nothing to flood from")
    assert_false(_doc.selection.active, "and the selection is untouched")


## The tool registers with its three options and floods on a click.
func test_the_wand_tool_floods_where_it_is_clicked() -> void:
    var surface := Fixtures.make_surface(Vector2i(512, 512))
    var machine := Fixtures.make_bound_machine(surface)
    var doc := surface.get_document()
    var registry := machine.registry
    assert_true(registry.has(&"wand"), "The wand is a registered tool")
    var keys: Array = []
    for spec: SaOptionSpec in registry.get_descriptor(&"wand").options:
        keys.append(spec.key)
    assert_eq(
        keys,
        [&"wand_tolerance", &"wand_contiguous", &"sample_merged", &"selection_mode", &"feather"],
        "with its tolerance, its Contiguous, the two shared keys and the feather the selection tools share"
    )

    doc.selection.select_rect(Rect2i(100, 100, 200, 200))
    doc.fill_layer(RED, doc.active_layer)
    doc.selection.deselect()
    machine.set_active_tool(&"wand")
    var tool := machine.active_tool
    tool.sample_merged = false
    surface.view.mouse_position = Vector2(150, 150)
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    tool.handle_input(press)
    assert_true(doc.selection.active, "A click makes a selection")
    assert_eq(doc.selection.chunks.size(), 4, "of the chunks the red reaches")
    Fixtures.teardown(surface, machine)


## A chunk stored smaller than the mask is read at its own scale. The chunk at
## the origin is built at half resolution by hand, 128 texels across, red on
## its left half and blue on its right, which in document pixels is red to x
## 127 and blue from x 128 on. Read at the mask's own coordinates, the red would end at x 63 and the
## flood with it.
func test_a_half_resolution_chunk_is_read_at_its_own_scale() -> void:
    var layer := _doc.active_layer
    var chunk := SaChunk.create(layer.schema, 0.5)
    var edge := chunk.pixel_size()
    assert_eq(edge, 128, "Half of the chunk's side")
    var texture := chunk.field(SaFieldSpec.ALBEDO)
    @warning_ignore("integer_division")
    var half_way := edge / 2
    var texels := _texels(edge, texture.format, func(x: int, _y: int) -> Color: return RED if x < half_way else BLUE)
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, texels)
    layer.chunks[Vector2i.ZERO] = chunk

    var reached := _flood(Vector2i(10, 10))
    # Two rather than one: the red runs to the chunk's bottom edge, so the
    # schedule adds the chunk below and sweeps it, and finds nothing there.
    assert_eq(reached, 2, "The red half reaches its own chunk and the edge below it")
    assert_almost_eq(_coverage(10, 300), 0.0, 0.001, "and nothing is selected in the chunk below")
    assert_almost_eq(_coverage(10, 10), 1.0, 0.001, "The seed is selected")
    assert_almost_eq(_coverage(100, 10), 1.0, 0.001, "Red runs to x 127 of the document, not to x 63")
    assert_almost_eq(_coverage(127, 200), 1.0, 0.001, "on every row of the chunk")
    assert_almost_eq(_coverage(128, 10), 0.0, 0.001, "and stops where the blue starts")


## The bytes of an *edge* by *edge* texture in *format*, coloured by *at*,
## for the two float formats a document may declare.
func _texels(edge: int, format: int, at: Callable) -> PackedByteArray:
    var bytes_per_texel: int = SaFieldSpec.BYTES_PER_TEXEL[format]
    var half := bytes_per_texel == 8
    var bytes := PackedByteArray()
    bytes.resize(edge * edge * bytes_per_texel)
    for y in edge:
        for x in edge:
            var color: Color = at.call(x, y)
            var offset := (y * edge + x) * bytes_per_texel
            for channel in 4:
                var value: float = color[channel]
                if half:
                    bytes.encode_half(offset + channel * 2, value)
                else:
                    bytes.encode_float(offset + channel * 4, value)
    return bytes
