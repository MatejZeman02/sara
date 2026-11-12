## A sharpen over the edge of opaque paint keeps its alpha within zero and one.
##
## The sharpen alone could lay alpha above one where its inputs were at most
## one: 2.5 at Amount 300 along a dark
## stripe on a transparent layer, and 1.36 from the Sharpen Filter brush. A
## layer of one opaque chunk beside an unallocated one is that edge, alpha one
## against nothing, and each kind of the sharpen is attached to it at the
## largest amount the slider gives. That the colour still overshoots across a
## step between two greys is `test_sharpen.gd`'s, which runs on unchanged.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

const REQUIRES_GPU := true

const OWNER: StringName = &"sara-base-modules"
const DARK := Color(0.06, 0.05, 0.08, 1.0)
const ROW := 128
## The columns either side of the seam the sharpen reaches at its radius.
const SPAN := 12
const SLACK := 0.0001

var _easel: SaEasel = null
var _layer: SaLayer = null


func after_each() -> void:
    _layer = null
    if _easel != null:
        _easel.free()
    _easel = null


## The left chunk cleared to *left* and the right one left with no chunk, the
## sharpen attached under *values*.
func _attach(values: Dictionary, left: Color) -> void:
    after_each()
    _easel = Bench.easel(Vector2i(2 * SaChunk.SIZE, SaChunk.SIZE))
    var filter := SaSharpenFilter.new()
    _easel.compositor.filter_chain.registry.register(filter, OWNER)
    _layer = _easel.document.get_node("Background") as SaLayer
    for grid_pos: Vector2i in _layer.chunks.keys():
        _layer.chunks.erase(grid_pos)
    _layer.get_or_create_chunk(Vector2i(0, 0)).clear(left)
    filter.set_parameters(values)
    SaFilterOps.new(_easel.document).attach(_layer, SaFilterRegistry.key_for(OWNER, filter), filter.parameters())
    Bench.composite(_easel)


## The chain's alpha at every column of [const ROW] within [const SPAN] of the
## seam, on both chunks.
func _alphas() -> Array[float]:
    var out: Array[float] = []
    var chain := _easel.compositor.filter_chain
    for x in range(SaChunk.SIZE - SPAN, SaChunk.SIZE + SPAN):
        var grid_pos := Vector2i(floori(float(x) / SaChunk.SIZE), 0)
        var answer := chain.filtered(_layer, _layer.get_field(grid_pos), grid_pos, SaDocument.WHOLE_CHUNK)
        if answer == null:
            out.append(0.0)
            continue
        out.append(Bench.texel(answer, Vector2i(x - grid_pos.x * SaChunk.SIZE, ROW)).a)
    return out


func _values(kind: String, amount: float, radius: float) -> Dictionary:
    return {"kind": kind, "amount": amount, "threshold": 0.0, "radius": radius}


func test_an_opaque_edge_sharpened_at_any_amount_holds_no_alpha_above_one() -> void:
    for kind: String in [SaSharpenFilter.SHARPEN, SaSharpenFilter.UNSHARP_MASK]:
        for amount: float in [100.0, 300.0]:
            _attach(_values(kind, amount, 3.0), DARK)
            var alphas := _alphas()
            assert_true(alphas.max() <= 1.0 + SLACK, "%s at %d holds alpha at most one, %f" % [kind, amount, alphas.max()])
            assert_true(alphas.min() >= -SLACK, "%s at %d holds no alpha below zero, %f" % [kind, amount, alphas.min()])
            assert_almost_eq(alphas[SPAN - 1], 1.0, SLACK, "%s at %d keeps the edge's inner texel opaque" % [kind, amount])


func test_an_alpha_the_painter_stored_above_one_is_kept() -> void:
    _attach(_values(SaSharpenFilter.UNSHARP_MASK, 300.0, 3.0), Color(0.5, 0.5, 0.5, 2.0))
    var alphas := _alphas()
    assert_almost_eq(alphas[0], 2.0, SLACK, "Far from the edge the stored alpha of two is left as it was")
    assert_true(alphas.max() <= 2.0 + SLACK, "and the edge lifts it no further, %f" % alphas.max())
