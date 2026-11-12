## A filter asks the canvas size and may write past the layer.
## The context answers `canvas_size()` from the document, whatever is selected
## or painted, and `neighbourhood_pass` takes where a whole-layer pass writes,
## so a filter's `run` never measures the canvas through a huge margin or casts
## the record to set it. The fixture shifts every texel two chunks to the right,
## over a layer holding one painted chunk on a canvas three chunks wide.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

const REQUIRES_GPU := true

const OWNER: StringName = &"whole-fixture"
const RED := Color(1.0, 0.0, 0.0, 1.0)
const CLEAR := Color(0.0, 0.0, 0.0, 0.0)
## A canvas three chunks across and one down, and a little past a chunk's edge
## each way, so the answer cannot be a count of chunks.
const CANVAS := Vector2i(3 * 256 - 40, 256 + 20)
## The chunk two chunks right of the paint, which the layer does not hold.
const FAR := Vector2i(2, 0)
## A texel of that chunk, in chunk-local pixels, well inside the canvas.
const PROBE := Vector2i(10, 128)


## The fixture's shift, recorded with *lands* as where it writes, through the
## option alone.
class Shift:
    extends "res://tests/fixtures/modules/whole-fixture/whole_shift_filter.gd"

    var lands: int = SaFilterContext.WRITES_LAYER

    func _init(where: int) -> void:
        lands = where

    func run(ctx: SaFilterContext) -> void:
        ctx.neighbourhood_pass("shift", "shift", {"offset": offset, "mode": mode}, SaFilterContext.WHOLE_NODE, {}, lands)


var _easel: SaEasel = null
var _doc: SaDocument = null
var _layer: SaLayer = null


func before_each() -> void:
    _easel = Bench.easel(CANVAS)
    _doc = _easel.document
    _layer = _doc.get_node("Background") as SaLayer
    for grid_pos: Vector2i in _layer.chunks.keys():
        _layer.chunks.erase(grid_pos)
    _layer.get_or_create_chunk(Vector2i(0, 0)).clear(RED)


func after_each() -> void:
    _easel.free()
    _easel = null
    _doc = null
    _layer = null


## A context over the layer, the way a one-shot from a script builds one.
func _context() -> SaFilterContext:
    return SaFilterContext.new(_doc, _layer, OWNER, "Whole Fixture Shift", false)


## The shift with *lands* run and applied once, answering the context.
func _apply(lands: int) -> SaFilterContext:
    var ctx := _context()
    assert_true(SaFilterApply.call_run(Shift.new(lands), ctx), "The run records a pass")
    assert_true(SaFilterApply.apply(ctx, "Whole Fixture Shift"), "and Apply writes it")
    return ctx


func test_the_canvas_size_is_the_documents() -> void:
    assert_eq(_context().canvas_size(), CANVAS, "The context answers the document's canvas, not a count of chunks")
    assert_eq(_context().canvas_size(), _doc.canvas_size, "which is the document's own field")


func test_the_canvas_size_ignores_the_selection_and_the_paint() -> void:
    var ctx := _context()
    assert_eq(ctx.rect_for(0), Rect2i(0, 0, 256, 256), "The run's rectangle is the one painted chunk")
    assert_eq(ctx.canvas_size(), CANVAS, "while the canvas size is the canvas")
    _doc.selection.select_rect(Rect2i(20, 30, 40, 50))
    assert_eq(ctx.rect_for(0), Rect2i(20, 30, 40, 50), "A selection moves the run's rectangle")
    assert_eq(ctx.canvas_size(), CANVAS, "and not the canvas size")


func test_the_canvas_size_without_a_document_is_zero() -> void:
    var ctx := SaFilterContext.new(null, null)
    assert_eq(ctx.canvas_size(), Vector2i.ZERO, "A context with no document has no canvas to answer")


func test_the_option_is_what_the_pass_records() -> void:
    var ctx := _context()
    SaFilterApply.call_run(Shift.new(SaFilterContext.WRITES_CANVAS), ctx)
    assert_true(ctx.point is SaNeighbourhoodPass, "The run recorded a neighbourhood pass")
    if ctx.point is SaNeighbourhoodPass:
        var recorded := ctx.point as SaNeighbourhoodPass
        assert_true(recorded.whole(), "that reads the whole layer")
        assert_eq(recorded.writes, SaNeighbourhoodPass.WRITES_CANVAS, "and writes the canvas, as the option said")
    var plain := _context()
    plain.neighbourhood_pass("shift", "shift", {}, SaFilterContext.WHOLE_NODE)
    assert_eq((plain.point as SaNeighbourhoodPass).writes, SaNeighbourhoodPass.WRITES_NODE, "Left out, it writes the layer")


func test_with_the_option_a_pass_writes_a_chunk_the_layer_did_not_have() -> void:
    assert_false(_layer.chunks.has(FAR), "The layer holds no chunk two chunks right of the paint")
    _apply(SaFilterContext.WRITES_CANVAS)
    assert_true(_layer.chunks.has(FAR), "With the option the pass allocated the chunk it wrote")
    if _layer.chunks.has(FAR):
        assert_eq(Bench.texel(_layer.get_field(FAR), PROBE), RED, "and wrote the shifted paint into it")


func test_without_the_option_a_pass_writes_the_layers_chunks_alone() -> void:
    _apply(SaFilterContext.WRITES_LAYER)
    assert_eq(_layer.chunks.size(), 1, "Without the option the pass allocated nothing")
    assert_false(_layer.chunks.has(FAR), "and the chunk two chunks away is still not held")
    assert_eq(Bench.texel(_layer.get_field(Vector2i(0, 0)), PROBE), CLEAR, "while the held chunk read past the left edge")
