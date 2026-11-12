## A neighbourhood filter reads past the document's edge as the edge continued. An opaque layer of one
## flat grey under the sharpens: a flat
## field is left alone by both, so every texel of the answer is the layer's own,
## the four corners of the document included. Read as transparent, the padding
## past the edge made the corner an edge against nothing, and the sharpen drew a
## rim there. A position inside the document that holds no chunk still reads as
## transparent, which the seam of a half covered layer against an unallocated
## chunk shows.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

const REQUIRES_GPU := true

const OWNER: StringName = &"sara-base-modules"
const GREY := Color(0.6, 0.6, 0.6, 1.0)
const ROW := 128

var _easel: SaEasel = null
var _layer: SaLayer = null
var _filter: SaSharpenFilter = null


func after_each() -> void:
    _release()


func _release() -> void:
    _layer = null
    _filter = null
    if _easel != null:
        _easel.free()
    _easel = null


## A document of *size* with the background cleared to [const GREY] on every
## grid position in *held*, and nothing anywhere else.
func _build(size: Vector2i, held: Array[Vector2i]) -> void:
    _release()
    _easel = Bench.easel(size)
    _filter = SaSharpenFilter.new()
    _easel.compositor.filter_chain.registry.register(_filter, OWNER)
    _layer = _easel.document.get_node("Background") as SaLayer
    for grid_pos: Vector2i in _layer.chunks.keys():
        _layer.chunks.erase(grid_pos)
    for grid_pos: Vector2i in held:
        _layer.get_or_create_chunk(grid_pos).clear(GREY)


func _values(kind: String) -> Dictionary:
    return {"kind": kind, "amount": 300.0, "threshold": 0.0, "radius": 4.0}


func _attach(kind: String) -> void:
    _filter.set_parameters(_values(kind))
    var key := SaFilterRegistry.key_for(OWNER, _filter)
    SaFilterOps.new(_easel.document).attach(_layer, key, _filter.parameters())
    Bench.composite(_easel)


## The chain's answer at the document pixel *at*.
func _attached(at: Vector2i) -> Color:
    var grid_pos := Vector2i(floori(float(at.x) / SaChunk.SIZE), floori(float(at.y) / SaChunk.SIZE))
    var chain := _easel.compositor.filter_chain
    var answer := chain.filtered(_layer, _layer.get_field(grid_pos), grid_pos, SaDocument.WHOLE_CHUNK)
    return Bench.texel(answer, at - grid_pos * SaChunk.SIZE)


## The layer's own texel at the document pixel *at*, after a one-shot.
func _stored(at: Vector2i) -> Color:
    var grid_pos := Vector2i(floori(float(at.x) / SaChunk.SIZE), floori(float(at.y) / SaChunk.SIZE))
    return Bench.texel(_layer.get_field(grid_pos), at - grid_pos * SaChunk.SIZE)


func _corners(size: Vector2i) -> Array[Vector2i]:
    return [Vector2i.ZERO, Vector2i(size.x - 1, 0), Vector2i(0, size.y - 1), size - Vector2i.ONE]


func _assert_grey(got: Color, what: String) -> void:
    assert_almost_eq(got.r, GREY.r, 0.001, "%s reads as the layer's own grey, %s" % [what, got])
    assert_almost_eq(got.a, 1.0, 0.001, "%s stays opaque, %s" % [what, got])


func test_the_corners_of_an_attached_sharpen_are_the_layers_own() -> void:
    var size := Vector2i(2 * SaChunk.SIZE, SaChunk.SIZE)
    for kind: String in [SaSharpenFilter.SHARPEN, SaSharpenFilter.UNSHARP_MASK]:
        _build(size, [Vector2i(0, 0), Vector2i(1, 0)])
        _attach(kind)
        for corner in _corners(size):
            _assert_grey(_attached(corner), "%s attached, at the corner %s" % [kind, corner])
        _assert_grey(_attached(Vector2i(0, ROW)), "%s attached, on the left edge" % kind)


func test_a_one_shot_sharpen_writes_the_corners_as_they_were() -> void:
    var size := Vector2i(2 * SaChunk.SIZE, SaChunk.SIZE)
    for kind: String in [SaSharpenFilter.SHARPEN, SaSharpenFilter.UNSHARP_MASK]:
        _build(size, [Vector2i(0, 0), Vector2i(1, 0)])
        _filter.set_parameters(_values(kind))
        var ctx := SaFilterContext.new(_easel.document, _layer, OWNER, _filter.title(), false)
        assert_true(SaFilterApply.call_run(_filter, ctx), "%s records a pass" % kind)
        assert_true(SaFilterApply.apply(ctx, "Sharpen"), "and Apply writes it")
        for corner in _corners(size):
            _assert_grey(_stored(corner), "%s one-shot, at the corner %s" % [kind, corner])


func test_a_canvas_that_ends_inside_a_chunk_clamps_at_its_own_edge() -> void:
    # 300 by 200 ends inside the chunks it holds, so the paint the clear put past
    # the canvas is not what the right and bottom edges read, the edge is.
    var size := Vector2i(300, 200)
    _build(size, [Vector2i(0, 0), Vector2i(1, 0)])
    _attach(SaSharpenFilter.UNSHARP_MASK)
    for corner in _corners(size):
        _assert_grey(_attached(corner), "At the corner %s of a canvas that ends mid-chunk" % corner)


func test_a_position_inside_the_document_with_no_chunk_still_reads_as_transparent() -> void:
    # The right chunk is never allocated, so the seam is an edge against nothing
    # inside the document. The layer is half covered, because a sharpen holds an
    # opaque texel's coverage at one and keeps its straight colour, so against
    # nothing an opaque grey shows no edge at all. Half covered, its coverage
    # rises at the seam and stays put at the document's own edge.
    _build(Vector2i(2 * SaChunk.SIZE, SaChunk.SIZE), [Vector2i(0, 0)])
    _layer.get_or_create_chunk(Vector2i(0, 0)).clear(Color(GREY, 0.5))
    _attach(SaSharpenFilter.SHARPEN)
    var seam := _attached(Vector2i(SaChunk.SIZE - 1, ROW))
    assert_true(seam.a > 0.51, "The seam against no chunk is an edge, %s" % seam)
    assert_true(seam.a <= 1.0001, "whose coverage stays at most one, %s" % seam)
    var left := _attached(Vector2i(0, ROW))
    assert_almost_eq(left.a, 0.5, 0.001, "while the document's own left edge keeps its coverage, %s" % left)
    assert_almost_eq(left.r, GREY.r, 0.001, "and its grey, %s" % left)
