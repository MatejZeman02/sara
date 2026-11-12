## A `path` step fills a closed polygon or a circle in document
## pixels, with the foreground colour, on the active layer, as one undo step,
## and leaves the selection as it found it.
##
## Everything here goes through `SaScenarioPath.fill`, the door the step itself
## calls once it has found the main canvas, so the suite needs a document and
## no window.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const ScenarioPath = preload("res://harness/scenario/sa_scenario_path.gd")
const Fixtures = preload("res://tests/fixtures.gd")

const BLUE := Color(0.0, 0.0, 1.0, 1.0)

## A right triangle in the first chunk, its hypotenuse on x + y = 240.
const TRIANGLE: Array = [[40, 40], [200, 40], [40, 200]]

## A circle wholly inside the chunk at (1, 1), its rightmost column at x = 499.
const CIRCLE: Array = [400, 400, 100]

var _surface: SaSurface = null
var _doc: SaDocument = null
var _kept_foreground: Color


## Three by three chunks, so each shape sits in one chunk and leaves eight with
## nothing in them.
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


## The softest alpha along row *y* from *from_x* to *to_x*, strictly between
## the two ends when the edge is antialiased.
func _partial_on_row(y: int, from_x: int, to_x: int) -> Array[float]:
    var partial: Array[float] = []
    for x in range(from_x, to_x + 1):
        var alpha := _texel(x, y).a
        if alpha > 0.05 and alpha < 0.95:
            partial.append(alpha)
    return partial


func test_a_triangle_fills_inside_leaves_outside_and_softens_its_edge() -> void:
    var touched := ScenarioPath.fill(_doc, {"polygon": TRIANGLE})
    assert_eq(touched, 1, "The triangle reached its one chunk")
    assert_eq(_doc.active_layer.chunks.size(), 1, "and allocated no other")

    var inside := _texel(80, 80)
    assert_almost_eq(inside.b, 1.0, 0.02, "Inside the triangle is the foreground colour")
    assert_almost_eq(inside.a, 1.0, 0.02, "and opaque")
    assert_almost_eq(_texel(180, 180).a, 0.0, 0.001, "Past the hypotenuse is untouched")
    assert_almost_eq(_texel(20, 100).a, 0.0, 0.001, "and so is left of the upright")

    # Along the diagonal row 120 the hypotenuse crosses at x = 120.
    var partial := _partial_on_row(120, 116, 124)
    assert_false(partial.is_empty(), "The edge is antialiased by default, found partial alphas %s" % [partial])


func test_a_circle_fills_inside_leaves_outside_and_softens_its_edge() -> void:
    var touched := ScenarioPath.fill(_doc, {"circle": CIRCLE})
    assert_eq(touched, 1, "The circle reached its one chunk")
    assert_eq(_doc.active_layer.chunks.size(), 1, "and allocated no other")

    assert_almost_eq(_texel(400, 400).a, 1.0, 0.02, "The centre is filled")
    assert_almost_eq(_texel(400, 400).b, 1.0, 0.02, "with the foreground colour")
    assert_almost_eq(_texel(450, 350).a, 1.0, 0.02, "and so is a point well inside the rim")
    assert_almost_eq(_texel(480, 480).a, 0.0, 0.001, "The corner of its box is outside it")
    assert_almost_eq(_texel(510, 400).a, 0.0, 0.001, "and so is a point past the rim")

    var partial := _partial_on_row(400, 495, 504)
    assert_false(partial.is_empty(), "The rim is antialiased by default, found partial alphas %s" % [partial])


func test_antialias_off_leaves_a_hard_edge() -> void:
    ScenarioPath.fill(_doc, {"circle": CIRCLE, "antialias": false})
    assert_eq(_partial_on_row(400, 495, 504), [] as Array[float], "Every texel of the rim is in or out")
    assert_almost_eq(_texel(499, 400).a, 1.0, 0.02, "The last column inside is filled")
    assert_almost_eq(_texel(500, 400).a, 0.0, 0.001, "and the next is not")


func test_each_shape_is_one_undo_step() -> void:
    var start := _doc.history.position()
    ScenarioPath.fill(_doc, {"polygon": TRIANGLE})
    assert_eq(_doc.history.position(), start + 1, "The triangle is one step")
    ScenarioPath.fill(_doc, {"circle": CIRCLE})
    assert_eq(_doc.history.position(), start + 2, "and the circle one more")

    assert_true(_doc.undo(), "The circle undoes")
    assert_almost_eq(_texel(400, 400).a, 0.0, 0.001, "and takes its paint with it")
    assert_almost_eq(_texel(80, 80).a, 1.0, 0.02, "leaving the triangle")
    assert_true(_doc.undo(), "The triangle undoes")
    assert_almost_eq(_texel(80, 80).a, 0.0, 0.001, "and the layer is empty again")
    assert_eq(_doc.history.position(), start, "back where it began")


func test_the_painters_selection_is_left_as_it_was() -> void:
    _doc.selection.select_rect(Rect2i(0, 0, 300, 300))
    var chunks_before: Dictionary = _doc.selection.chunks
    var bounds_before := _doc.selection.bounds
    var keys_before := chunks_before.keys()

    ScenarioPath.fill(_doc, {"circle": CIRCLE})
    ScenarioPath.fill(_doc, {"polygon": TRIANGLE})

    assert_true(_doc.selection.active, "The selection is still there")
    assert_true(is_same(_doc.selection.chunks, chunks_before), "holding the very chunks it held")
    assert_eq(_doc.selection.chunks.keys(), keys_before, "at the same positions")
    assert_eq(_doc.selection.bounds, bounds_before, "with the bounds it had")
    assert_almost_eq(_texel(480, 400).a, 1.0, 0.02, "The circle past the selection is filled whole, the step names its region")


func test_no_selection_stays_no_selection() -> void:
    ScenarioPath.fill(_doc, {"polygon": TRIANGLE})
    assert_false(_doc.selection.active, "A path fill makes no selection")
    assert_true(_doc.selection.chunks.is_empty(), "and leaves no mask chunks behind")


func test_a_spec_with_no_shape_fills_nothing() -> void:
    var start := _doc.history.position()
    assert_eq(ScenarioPath.fill(_doc, {"polygon": [[0, 0], [10, 10]]}), 0, "Two points are not a polygon")
    assert_eq(ScenarioPath.fill(_doc, {"square": [0, 0, 10]}), 0, "and a square is not a shape the step knows")
    assert_eq(_doc.history.position(), start, "and neither left a step")
    assert_eq(_doc.active_layer.chunks.size(), 0, "or a chunk")
