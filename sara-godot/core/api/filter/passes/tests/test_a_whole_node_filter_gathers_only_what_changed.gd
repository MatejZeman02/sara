## A filter that reads the whole node keeps what it gathered between
## composites and copies again only the chunks that changed.
## The fixture shifts every texel two chunks to the right. A layer holds a row of
## chunks, the first red, and the shift hangs on the root, on the layer, or on
## both. The first chunk is painted blue and redrawn alone: the canvas shows the
## blue where the shift carries it, the same bytes a composite of everything
## gives, and with fewer dispatches than the same redraw after a composite the
## chain never saw, which gathers the node anew.
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
const PROBE := Vector2i(10, 128)

enum Where { ROOT, LAYER, BOTH }

var _easel: SaEasel = null
var _layer: SaLayer = null


func after_each() -> void:
    _layer = null
    if _easel != null:
        _easel.free()
    _easel = null


## An easel *wide* chunks across whose Background holds every chunk of the row,
## the first red, with the shift attached *where* and composited whole.
func _bench(where: Where, wide: int) -> void:
    _easel = Bench.easel(Vector2i(wide * SaChunk.SIZE, SaChunk.SIZE))
    var doc := _easel.document
    _easel.compositor.filter_chain.registry.register(WholeShiftFilter.new(), OWNER)
    _layer = doc.get_node("Background") as SaLayer
    for grid_pos: Vector2i in _layer.chunks.keys():
        _layer.chunks.erase(grid_pos)
    for x in wide:
        _layer.get_or_create_chunk(Vector2i(x, 0)).clear(CLEAR)
    _layer.get_or_create_chunk(Vector2i.ZERO).clear(RED)
    var ops := SaFilterOps.new(doc)
    if where != Where.LAYER:
        ops.attach(null, KEY, SHIFT)
    if where != Where.ROOT:
        ops.attach(_layer, KEY, SHIFT)
    Bench.composite(_easel)


## Paints the first chunk *colour* and redraws what that dirtied, answering
## the dispatches the redraw took. With *seen* false the chain misses a
## consume first, the way a composite it never ran leaves it.
func _paint(colour: Color, seen: bool) -> int:
    var doc := _easel.document
    if not seen:
        doc.consume_dirty_chunks()
    _layer.get_or_create_chunk(Vector2i.ZERO).clear(colour)
    doc.invalidate_chunk_regions({Vector2i.ZERO: Rect2i(4, 4, 32, 32)})
    var before := SaCompute.dispatches
    _easel.process_pending_composite()
    return SaCompute.dispatches - before


func _bytes() -> PackedByteArray:
    return GlobalShaderCompiler.get_rd().texture_get_data(_easel.output.rid, 0)


## Paints twice, the second time after a missed consume, and checks each
## redraw against a composite of everything.
func _kept_against_anew(where: Where, wide: int, lands: Vector2i, what: String) -> void:
    _bench(where, wide)
    _paint(RED, true)
    var kept := _paint(BLUE, true)
    var at := lands * SaChunk.SIZE + PROBE
    assert_eq(Bench.texel(_easel.output, at), BLUE, "%s: the blue shows where the shift carries it" % what)
    var shown := _bytes()
    Bench.composite(_easel)
    assert_true(shown == _bytes(), "%s: the kept redraw is the bytes a composite of everything gives" % what)
    var anew := _paint(RED, false)
    assert_eq(Bench.texel(_easel.output, at), RED, "%s: a redraw after a missed consume shows the red" % what)
    assert_true(kept < anew, "%s: the kept redraw took %d dispatches and the one that gathered anew %d" % [what, kept, anew])


func test_on_the_root_a_redraw_copies_again_only_what_changed() -> void:
    _kept_against_anew(Where.ROOT, 4, Vector2i(2, 0), "On the root")


func test_on_the_layer_a_redraw_copies_again_only_what_changed() -> void:
    _kept_against_anew(Where.LAYER, 4, Vector2i(2, 0), "On the layer")


## The layer's shift makes every chunk of it stale, so the composite under the
## root changes far from the paint, and the root's kept gather copies those
## positions as well.
func test_on_both_the_root_copies_what_the_layer_changed() -> void:
    _kept_against_anew(Where.BOTH, 5, Vector2i(4, 0), "On both")


## A displacement of (384, 128) on a canvas three chunks by two carries a
## texel painted at (0, 0) to (384, 128), in the chunk at (1, 0).
func test_a_layer_that_moves_its_paint_makes_stale_only_where_it_lands() -> void:
    var held: Dictionary[Vector2i, bool] = {}
    for y in 2:
        for x in 3:
            held[Vector2i(x, y)] = true
    var regions: Dictionary[Vector2i, Rect2i] = {Vector2i.ZERO: Rect2i(0, 0, 10, 10)}
    var canvas := Vector2i(3, 2) * SaChunk.SIZE
    var moved := _records(SaNeighbourhoodPass.WRITES_DISPLACED)
    var stale := SaNeighbourhoodPass.stale_under(moved, held, regions, canvas)
    assert_eq(stale.keys(), [Vector2i(1, 0)], "A wrap on a layer makes stale where the paint lands and nothing else")
    var wrapped := SaNeighbourhoodPass.stale_under(moved, held, {Vector2i(2, 1): Rect2i(250, 250, 6, 6)}, canvas)
    assert_eq(wrapped.keys(), [Vector2i(1, 0)], "and a region carried past the corner lands wrapped round it")
    # The root under a wrap made every position stale here,
    # whose suite reads the root now.
    var node := SaNeighbourhoodPass.stale_under(_records(SaNeighbourhoodPass.WRITES_NODE), held, regions, canvas)
    assert_eq(node.size(), held.size(), "and so does a layer whose pass writes its node")


func _records(writes: int) -> Array[SaAttachedFilter]:
    var recorded := SaNeighbourhoodPass.new("fixture", "fixture", {}, SaNeighbourhoodPass.WHOLE_NODE, {}, writes)
    recorded.displacement = Vector2i(384, 128)
    var record := SaAttachedFilter.new(&"fixture.wrap")
    record.cached_pass = recorded
    var records: Array[SaAttachedFilter] = [record]
    return records


func test_a_kept_node_owes_what_was_marked_and_what_was_replaced() -> void:
    var ledger := SaGatherLedger.new()
    var first := SaTexture.new(Vector2i(4, 4), RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT)
    var second := SaTexture.new(Vector2i(4, 4), RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT)
    var held: Dictionary[Vector2i, SaTexture] = {Vector2i(0, 0): first, Vector2i(1, 0): second}
    assert_eq(ledger.owed(held, true).size(), 2, "A gather anew owes every position")
    assert_eq(ledger.owed(held, false), [], "and the next owes nothing when nothing changed")
    ledger.mark({Vector2i(1, 0): true})
    assert_eq(ledger.owed(held, false), [Vector2i(1, 0)], "A marked position is owed")
    held[Vector2i(0, 0)] = SaTexture.new(Vector2i(4, 4), RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT)
    assert_eq(ledger.owed(held, false), [Vector2i(0, 0)], "and so is one whose chunk was replaced")
    held[Vector2i(2, 0)] = first
    assert_eq(ledger.owed(held, false), [Vector2i(2, 0)], "A position the last gather did not hold owes itself alone")
    held.erase(Vector2i(1, 0))
    assert_eq(ledger.owed(held, false).size(), 2, "and one it held and is gone owes every one, so the gather clears its cell")
