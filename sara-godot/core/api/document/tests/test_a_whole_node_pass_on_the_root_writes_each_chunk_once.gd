## A pass that reads the whole node, alone on the root, writes each chunk
## straight into the canvas under one compute list. Through the
## scratch it was the kernel and a copy back a chunk, two lists each. The fixture
## shifts every texel two chunks to the right. A redraw after the first chunk is
## painted blue takes one list of the shift for every chunk it writes, shows the
## blue where the shift carries it, and gives the bytes the scratch gives, which a
## mask on the record still takes, on a canvas that is and one that is not a
## multiple of the chunk.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const WholeShiftFilter = preload("res://tests/fixtures/modules/whole-fixture/whole_shift_filter.gd")

const REQUIRES_GPU := true

const OWNER: StringName = &"whole-fixture"
const KEY: StringName = &"whole-fixture.whole_fixture_shift"
const RED := Color(1.0, 0.0, 0.0, 1.0)
const BLUE := Color(0.0, 0.0, 1.0, 1.0)
const CLEAR := Color(0.0, 0.0, 0.0, 0.0)
const SHIFT := {"offset_x": 512.0, "offset_y": 0.0, "mode": 0, "reach": SaNeighbourhoodPass.WHOLE_NODE}
const PROBE := Vector2i(10, 20)

var _easel: SaEasel = null
var _layer: SaLayer = null


func after_each() -> void:
    _layer = null
    if _easel != null:
        _easel.free()
    _easel = null


## An easel of *size* whose Background holds every chunk the canvas meets, the
## first red, with the shift on the root, masked when *masked* says so, and
## composited whole.
func _bench(size: Vector2i, masked: bool) -> void:
    _easel = Bench.easel(size)
    var doc := _easel.document
    _easel.compositor.filter_chain.registry.register(WholeShiftFilter.new(), OWNER)
    _layer = doc.get_node("Background") as SaLayer
    for grid_pos: Vector2i in _layer.chunks.keys():
        _layer.chunks.erase(grid_pos)
    for y in ceili(size.y / float(SaChunk.SIZE)):
        for x in ceili(size.x / float(SaChunk.SIZE)):
            _layer.get_or_create_chunk(Vector2i(x, y)).clear(CLEAR)
    _layer.get_or_create_chunk(Vector2i.ZERO).clear(RED)
    SaFilterOps.new(doc).attach(null, KEY, SHIFT)
    if masked:
        # A mask that holds no chunk reads as one everywhere, so the picture is
        # the same and only the path differs.
        doc.root_filters[0].mask = SaMask.new()
    Bench.composite(_easel)


## Paints the first chunk blue and redraws what that dirtied, answering the
## lists and the dispatches of the shift the redraw took.
func _paint() -> Vector2i:
    _layer.get_or_create_chunk(Vector2i.ZERO).clear(BLUE)
    _easel.document.invalidate_chunk_regions({Vector2i.ZERO: Rect2i(4, 4, 32, 32)})
    var before := _shift_tally()
    _easel.process_pending_composite()
    return _shift_tally() - before


## The lists and the dispatches the shift kernel has taken this session.
static func _shift_tally() -> Vector2i:
    var tally := Vector2i.ZERO
    for key: String in SaCompute.by_kernel:
        if key.ends_with("/shift"):
            var entry: Dictionary = SaCompute.by_kernel[key]
            tally += Vector2i(int(entry["lists"]), int(entry["dispatches"]))
    return tally


func _bytes() -> PackedByteArray:
    return GlobalShaderCompiler.get_rd().texture_get_data(_easel.output.rid, 0)


## The redraw's tally, the bytes it shows, and whether they are the bytes a
## composite of everything gives.
func _redraw(size: Vector2i, masked: bool) -> Array:
    _bench(size, masked)
    var took := _paint()
    var lands := Vector2i(2 * SaChunk.SIZE, 0) + PROBE
    assert_eq(Bench.texel(_easel.output, lands), BLUE, "The blue shows where the shift carries it")
    var shown := _bytes()
    Bench.composite(_easel)
    assert_true(shown == _bytes(), "and the redraw is the bytes a composite of everything gives")
    after_each()
    return [took, shown]


func _straight_against_scratch(size: Vector2i, chunks: int, what: String) -> void:
    var straight := _redraw(size, false)
    var scratch := _redraw(size, true)
    assert_eq(straight[0], Vector2i(1, chunks), "%s: the root's shift wrote %d chunks under one list" % [what, chunks])
    assert_eq(scratch[0], Vector2i(chunks, chunks), "%s: a masked record goes through the scratch, a list a chunk" % what)
    assert_true(straight[1] == scratch[1], "%s: and both give the same bytes" % what)


func test_a_canvas_of_whole_chunks_is_written_straight() -> void:
    _straight_against_scratch(Vector2i(4 * SaChunk.SIZE, SaChunk.SIZE), 4, "Four whole chunks")


## The last column and row end inside their chunk, where a region's side is no
## multiple of the workgroup and the canvas's edge stops the groups.
func test_a_canvas_its_last_chunks_end_inside_is_written_straight() -> void:
    _straight_against_scratch(Vector2i(3 * SaChunk.SIZE + 100, SaChunk.SIZE + 37), 8, "A ragged canvas")
