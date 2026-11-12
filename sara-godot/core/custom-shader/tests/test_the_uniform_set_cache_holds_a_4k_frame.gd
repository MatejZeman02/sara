## The uniform set cache holds a 4K layer, and evicts the set used longest ago
##
##
## At 64 sets the layer thumbnail's walk over the 135 chunks of a 4K layer evicted
## its own head and built a set on every dispatch, 4184 in one stroke of the
## `layers-10` window. The cache holds 512 now, and its use order moved from an
## Array into the Dictionary, so these hold both the size and the order.
extends "res://tests/test_framework.gd"

const PaintKernel = preload("res://tests/fixtures/paint_kernel.gd")
const UniformSets = preload("res://core/custom-shader/sa_uniform_sets.gd")

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true

## The chunks of one 3840 by 2160 layer at 256 texels a chunk, 15 by 9.
const LAYER_4K_CHUNKS: int = 135

## The selection mask the kernel binds, held here because a texture freed under a
## set leaves the set binding nothing.
var _mask: SaTexture = null


func after_each() -> void:
    _mask = null


## A paint kernel with its mask and push constant bound, so the one binding that
## moves between dispatches is binding 0.
func _kernel() -> SaCompute:
    var comp := PaintKernel.compute()
    _mask = SaTexture.new(Vector2i(1, 1), SaSelection.FORMAT)
    _mask.clear(Color(1.0, 1.0, 1.0, 1.0))
    comp.set_texture(SaSelection.BINDING, _mask.rid)
    var params := PackedFloat32Array()
    params.resize(16)
    comp.set_push_constant_float_array(params)
    return comp


func _textures(count: int) -> Array[SaTexture]:
    var made: Array[SaTexture] = []
    for i in count:
        made.append(SaTexture.new(Vector2i(1, 1)))
    return made


## Binds *texture* at 0, dispatches once, and answers how many sets that built.
func _built_by(comp: SaCompute, texture: SaTexture) -> int:
    var before := int(SaCompute.counters()["uniform_sets"])
    comp.set_texture(0, texture.rid)
    comp.dispatch_kernel("paint", 1, 1, 1)
    return int(SaCompute.counters()["uniform_sets"]) - before


## A second walk over a 4K layer's chunks builds nothing, which at 64 it built
## again in full.
func test_a_second_walk_over_a_4k_layer_builds_no_set() -> void:
    assert_true(UniformSets.UNIFORM_SET_CACHE_SIZE >= LAYER_4K_CHUNKS, "The cache holds one 4K layer's chunks")
    var comp := _kernel()
    var chunks := _textures(LAYER_4K_CHUNKS)

    var first := 0
    for chunk: SaTexture in chunks:
        first += _built_by(comp, chunk)
    assert_eq(first, LAYER_4K_CHUNKS, "The first walk builds one set a chunk")

    var second := 0
    for chunk: SaTexture in chunks:
        second += _built_by(comp, chunk)
    assert_eq(second, 0, "and the second walk finds every one of them")
    SaCompute.reset_counters()


## Past the ceiling the set used longest ago goes, not the one built first: a hit
## moves a set to the young end of the order.
func test_a_full_cache_evicts_the_set_used_longest_ago() -> void:
    var comp := _kernel()
    var held := _textures(UniformSets.UNIFORM_SET_CACHE_SIZE + 1)

    for i in UniformSets.UNIFORM_SET_CACHE_SIZE:
        _built_by(comp, held[i])
    assert_eq(_built_by(comp, held[0]), 0, "The first set built is found while the cache has room")

    assert_eq(_built_by(comp, held[-1]), 1, "One set past the ceiling is built")
    assert_eq(_built_by(comp, held[0]), 0, "and the first set, used a moment ago, survives it")
    assert_eq(_built_by(comp, held[1]), 1, "while the second, used longest ago, was the one let go")
    SaCompute.reset_counters()
