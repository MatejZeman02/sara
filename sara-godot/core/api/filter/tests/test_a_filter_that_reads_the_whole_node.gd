## A filter that reads the whole node reads a chunk as far away as it likes. The fixture shifts every texel by
## two chunks, so a texel of a
## chunk two chunks from the paint reads the paint, which no neighbourhood gather
## reaches. A layer holds one painted chunk and one empty one two chunks to its
## right, and the texel is read through the chain, the one-shot and the canvas.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const WholeShiftFilter = preload("res://tests/fixtures/modules/whole-fixture/whole_shift_filter.gd")

const REQUIRES_GPU := true

const OWNER: StringName = &"whole-fixture"
const KEY: StringName = &"whole-fixture.whole_fixture_shift"
const RED := Color(1.0, 0.0, 0.0, 1.0)
## Two chunks to the right, as far as the fixture reads.
const SHIFT := {"offset_x": 512.0, "offset_y": 0.0, "mode": 0, "reach": SaNeighbourhoodPass.WHOLE_NODE}
## A texel of the empty chunk, in chunk-local pixels, well inside it.
const PROBE := Vector2i(10, 128)
const FAR := Vector2i(2, 0)

var _easel: SaEasel = null
var _doc: SaDocument = null
var _layer: SaLayer = null


func before_each() -> void:
    _easel = Bench.easel(Vector2i(3 * SaChunk.SIZE, SaChunk.SIZE))
    _doc = _easel.document
    _easel.compositor.filter_chain.registry.register(WholeShiftFilter.new(), OWNER)
    _layer = _doc.get_node("Background") as SaLayer
    for grid_pos: Vector2i in _layer.chunks.keys():
        _layer.chunks.erase(grid_pos)
    _layer.get_or_create_chunk(Vector2i(0, 0)).clear(RED)
    _layer.get_or_create_chunk(FAR).clear(Color.TRANSPARENT)


func after_each() -> void:
    _easel.free()
    _easel = null
    _doc = null
    _layer = null


func _attach(values: Dictionary) -> SaAttachedFilter:
    var record := SaFilterOps.new(_doc).attach(_layer, KEY, values)
    Bench.composite(_easel)
    return record


## The chain's answer for the chunk at *grid_pos*, read at [const PROBE].
func _filtered(grid_pos: Vector2i) -> Color:
    var chain := _easel.compositor.filter_chain
    var answer := chain.filtered(_layer, _layer.get_field(grid_pos), grid_pos, SaDocument.WHOLE_CHUNK)
    return Bench.texel(answer, PROBE)


func test_the_record_evaluates_to_a_pass_that_reads_the_whole_node() -> void:
    var record := _attach(SHIFT)
    assert_true(record.cached_pass is SaNeighbourhoodPass, "The shift's run recorded a neighbourhood pass")
    if record.cached_pass is SaNeighbourhoodPass:
        var recorded := record.cached_pass as SaNeighbourhoodPass
        assert_true(recorded.whole(), "whose reach is the whole node")
        assert_eq(recorded.halo(), 0, "and which gathers no padding, since its source is gathered whole")


func test_attached_a_texel_two_chunks_away_reads_the_paint() -> void:
    _attach(SHIFT)
    assert_eq(_filtered(FAR), RED, "The empty chunk two chunks from the paint reads the paint through the chain")
    assert_eq(_filtered(Vector2i(0, 0)), Color(0, 0, 0, 0), "and the painted chunk reads past the node's left edge, transparent")


func test_attached_the_canvas_shows_it() -> void:
    _attach(SHIFT)
    var at := FAR * SaChunk.SIZE + PROBE
    assert_eq(Bench.texel(_easel.output, at), RED, "The canvas shows the paint two chunks from where it was painted")


func test_one_shot_writes_the_same_texel() -> void:
    var filter := WholeShiftFilter.new()
    filter.set_parameters(SHIFT)
    var ctx := SaFilterContext.new(_doc, _layer, OWNER, filter.title(), false)
    assert_true(SaFilterApply.call_run(filter, ctx), "The run records a pass")
    assert_true(SaFilterApply.apply(ctx, "Whole Fixture Shift"), "Apply writes it")
    assert_eq(Bench.texel(_layer.get_field(FAR), PROBE), RED, "The one-shot wrote the paint into the chunk two chunks away")
    assert_eq(Bench.texel(_layer.get_field(Vector2i(0, 0)), PROBE), Color(0, 0, 0, 0), "and read every chunk before writing any")
    assert_eq(_layer.chunks.size(), 2, "It wrote the chunks the layer holds and allocated none")


func test_the_chunk_param_reads_back_the_chunks_origin() -> void:
    _attach({"offset_x": 0.0, "offset_y": 0.0, "mode": 1, "reach": SaNeighbourhoodPass.WHOLE_NODE})
    var answer := _filtered(FAR)
    assert_eq(Vector2(answer.r, answer.g), Vector2(512, 0), "A whole-node kernel's chunk param is the chunk's origin")
    assert_eq(Vector2(answer.b, answer.a), Vector2(0, 0), "and its source param the first texel of the gathered node")


func test_the_chunk_param_on_a_neighbourhood_pass() -> void:
    _attach({"offset_x": 0.0, "offset_y": 0.0, "mode": 1, "reach": 4})
    var answer := _filtered(FAR)
    assert_eq(Vector2(answer.r, answer.g), Vector2(512, 0), "A neighbourhood kernel's chunk param is the chunk's origin")
    assert_eq(Vector2(answer.b, answer.a), Vector2(508, -4), "and its source param the padded texture's corner")


func test_paint_on_one_chunk_makes_every_chunk_of_the_node_stale() -> void:
    _attach(SHIFT)
    _doc.consume_dirty_chunks()
    _doc.invalidate_chunk_regions({Vector2i(0, 0): Rect2i(4, 4, 8, 8)})
    var dirty := _doc.consume_dirty_chunks()
    assert_eq(dirty.get(FAR, Rect2i()), SaDocument.WHOLE_CHUNK, "A dab on the painted chunk makes the far chunk stale whole")
    assert_false(dirty.has(Vector2i(1, 0)), "and not a position the node holds no chunk at")
