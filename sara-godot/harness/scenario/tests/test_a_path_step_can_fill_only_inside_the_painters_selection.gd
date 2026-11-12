## A `path` step given `inside_selection` keeps only the part of
## its shape inside the painter's selection, the way a stroke is clipped by
## one. Without the argument the shape fills whole, as it always has.
##
## Everything here goes through `SaScenarioPath.fill`, the door the step itself
## calls once it has found the main canvas, so the suite needs a document and
## no window.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const ScenarioPath = preload("res://harness/scenario/sa_scenario_path.gd")
const Fixtures = preload("res://tests/fixtures.gd")

const BLUE := Color(0.0, 0.0, 1.0, 1.0)

## Spans x 300 to 500 inside the chunk at (1, 1), across the selection's edge.
const CIRCLE: Array = [400, 400, 100]

## The left half of the canvas, its edge at x = 384, halfway through a chunk.
const LEFT_HALF := Rect2i(0, 0, 384, 768)

var _surface: SaSurface = null
var _doc: SaDocument = null
var _kept_foreground: Color


func before_each() -> void:
    _surface = Fixtures.make_surface(Vector2i(768, 768))
    _doc = _surface.get_document()
    _kept_foreground = SaColors.foreground
    SaColors.foreground = BLUE


func after_each() -> void:
    SaColors.foreground = _kept_foreground
    _doc.free()
    _surface.easel.free()
    _surface = null
    _doc = null


func _texel(x: int, y: int) -> Color:
    @warning_ignore("integer_division")
    var grid := Vector2i(x / SaChunk.SIZE, y / SaChunk.SIZE)
    var chunk: SaChunk = _doc.active_layer.chunks.get(grid, null)
    if chunk == null:
        return Color(0, 0, 0, 0)
    var texture: SaTexture = chunk.field(SaFieldSpec.ALBEDO)
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var at := ((y % SaChunk.SIZE) * texture.size.x + x % SaChunk.SIZE) * 16
    return Color(bytes.decode_float(at), bytes.decode_float(at + 4), bytes.decode_float(at + 8), bytes.decode_float(at + 12))


func test_the_argument_keeps_paint_inside_the_selection_and_none_outside() -> void:
    _doc.selection.select_rect(LEFT_HALF)
    var touched := ScenarioPath.fill(_doc, {"circle": CIRCLE, "inside_selection": true})
    assert_eq(touched, 1, "The circle reached its one chunk")

    assert_almost_eq(_texel(350, 400).a, 1.0, 0.02, "Left of the selection's edge the circle is filled")
    assert_almost_eq(_texel(350, 400).b, 1.0, 0.02, "with the foreground colour")
    assert_almost_eq(_texel(383, 400).a, 1.0, 0.02, "up to the last column the selection holds")
    assert_almost_eq(_texel(384, 400).a, 0.0, 0.001, "and the first column past it is bare")
    assert_almost_eq(_texel(450, 400).a, 0.0, 0.001, "as is the part of the circle well outside it")
    assert_almost_eq(_texel(490, 400).a, 0.0, 0.001, "out to its rim")


func test_the_same_fill_without_the_argument_covers_the_whole_circle() -> void:
    _doc.selection.select_rect(LEFT_HALF)
    ScenarioPath.fill(_doc, {"circle": CIRCLE})
    _assert_whole_circle("Without the argument")

    _doc.undo()
    assert_almost_eq(_texel(450, 400).a, 0.0, 0.001, "The undo emptied the layer")
    ScenarioPath.fill(_doc, {"circle": CIRCLE, "inside_selection": false})
    _assert_whole_circle("With the argument false")


## Every point of the circle `CIRCLE` on both sides of the selection's edge is
## filled, and the corners of its box are not, so the disc is whole and round.
func _assert_whole_circle(how: String) -> void:
    for point: Vector2i in [
        Vector2i(400, 400),
        Vector2i(310, 400),
        Vector2i(383, 400),
        Vector2i(384, 400),
        Vector2i(450, 400),
        Vector2i(490, 400),
        Vector2i(400, 310),
        Vector2i(400, 490),
        Vector2i(450, 350),
        Vector2i(350, 450),
    ]:
        assert_almost_eq(_texel(point.x, point.y).a, 1.0, 0.02, "%s the circle is filled at %s" % [how, point])
    for corner: Vector2i in [Vector2i(305, 305), Vector2i(495, 305), Vector2i(305, 495), Vector2i(495, 495)]:
        assert_almost_eq(_texel(corner.x, corner.y).a, 0.0, 0.001, "%s the corner of its box %s is bare" % [how, corner])


func test_with_nothing_selected_the_argument_fills_the_whole_shape() -> void:
    ScenarioPath.fill(_doc, {"circle": CIRCLE, "inside_selection": true})
    assert_almost_eq(_texel(350, 400).a, 1.0, 0.02, "No selection holds everything, so the left of the circle is filled")
    assert_almost_eq(_texel(450, 400).a, 1.0, 0.02, "and so is the right")


func test_a_shape_wholly_outside_the_selection_fills_nothing() -> void:
    _doc.selection.select_rect(Rect2i(0, 0, 200, 200))
    var start := _doc.history.position()
    var touched := ScenarioPath.fill(_doc, {"circle": CIRCLE, "inside_selection": true})
    assert_eq(touched, 0, "The circle does not touch the selection, so no chunk is written")
    assert_eq(_doc.active_layer.chunks.size(), 0, "and none is allocated")
    assert_eq(_doc.history.position(), start, "and no step is left")


func test_the_clipped_fill_is_one_undo_step_and_undoes_clean() -> void:
    _doc.selection.select_rect(LEFT_HALF)
    var start := _doc.history.position()
    ScenarioPath.fill(_doc, {"circle": CIRCLE, "inside_selection": true})
    assert_eq(_doc.history.position(), start + 1, "The clipped fill is one step")
    assert_true(_doc.undo(), "and it undoes")
    assert_almost_eq(_texel(350, 400).a, 0.0, 0.001, "taking its paint with it")
    assert_eq(_doc.history.position(), start, "back where it began")


func test_the_painters_selection_is_left_as_it_was_and_gains_no_step() -> void:
    _doc.selection.select_rect(LEFT_HALF)
    var chunks_before: Dictionary = _doc.selection.chunks
    var keys_before := chunks_before.keys()
    var bounds_before := _doc.selection.bounds
    var mask_before := _mask_at_edge()
    var start := _doc.history.position()

    ScenarioPath.fill(_doc, {"circle": CIRCLE, "inside_selection": true})

    assert_true(_doc.selection.active, "The selection is still there")
    assert_true(is_same(_doc.selection.chunks, chunks_before), "holding the very chunks it held")
    assert_eq(_doc.selection.chunks.keys(), keys_before, "at the same positions")
    assert_eq(_doc.selection.bounds, bounds_before, "with the bounds it had")
    assert_eq(_mask_at_edge(), mask_before, "and the mask itself was not written into")
    assert_eq(_doc.history.position(), start + 1, "and the only step is the paint's")


func test_a_soft_shape_edge_survives_the_clip() -> void:
    _doc.selection.select_rect(LEFT_HALF)
    # A circle whose rim lies wholly inside the selection, so any softness at
    # the rim is the shape's own and the clip has nothing to do with it.
    ScenarioPath.fill(_doc, {"circle": [150, 150, 60], "inside_selection": true})
    var partial := 0
    for x in range(205, 214):
        var alpha := _texel(x, 150).a
        if alpha > 0.05 and alpha < 0.95:
            partial += 1
    assert_true(partial > 0, "The rim is still antialiased, the clip took none of it")
    assert_almost_eq(_texel(150, 150).a, 1.0, 0.02, "and the inside is filled")


## The painter's mask at the edge column, read straight off the GPU.
func _mask_at_edge() -> float:
    var grid := Vector2i(1, 1)
    var chunk: SaChunk = _doc.selection.chunks.get(grid, null)
    if chunk == null:
        return -1.0
    var texture: SaTexture = chunk.field(SaSelection.FIELD)
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var row := 400 % SaChunk.SIZE
    var column := 383 % SaChunk.SIZE
    return bytes.decode_float((row * texture.size.x + column) * 4)
