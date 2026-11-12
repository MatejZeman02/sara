## F3: the scratch an isolated group composites through is reused chunk after
## chunk, so whatever it held for the previous chunk has to be gone before this
## one is composited into it.
##
## The two-chunk case is the whole test. A scope whose layer paints the first
## chunk and not the second leaves the second's scratch with nothing to cover
## the first's red, so a clear that has not landed shows as the first chunk's
## paint repeated in the second, which is the symptom once called "fragments of the painting drawn in three places at once".
##
## A CPU readback cannot see the ordering bug itself, because `texture_get_data`
## synchronises and the pitfall says so outright. What it can hold is the
## arithmetic the fix must not change, and nothing in the suite covered a scope
## over more than one chunk before this.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true

const GREEN := Color(0, 1, 0, 1)
const RED := Color(1, 0, 0, 1)


## Two chunks wide and one high, which is the smallest canvas that makes the
## compositor reuse one scope scratch twice in a single pass.
func _easel() -> SaEasel:
    var easel := SaEasel.create_default(Vector2i(SaLayer.CHUNK_SIZE * 2, SaLayer.CHUNK_SIZE))
    easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    return easel


func _texel(texture: SaTexture, x: int, y: int) -> Color:
    var data: PackedByteArray = GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var at := (y * texture.size.x + x) * 16
    return Color(data.decode_float(at), data.decode_float(at + 4), data.decode_float(at + 8), data.decode_float(at + 12))


func _composite(easel: SaEasel) -> void:
    easel.request_full_composite()
    easel.process_pending_composite()


func test_a_scope_leaves_the_chunk_it_does_not_paint_alone() -> void:
    var easel := _easel()
    var doc := easel.document
    doc.fill_layer(GREEN, doc.active_layer)

    var inside := SaLayerOps.new(doc).add()
    # The left chunk only. The right one is never allocated on this layer, so
    # the scope has nothing to put over the scratch there.
    inside.get_or_create_chunk(Vector2i.ZERO).clear(RED)
    doc.invalidate_chunks([Vector2i.ZERO])

    var groups := SaLayerOps.new(doc)
    var group := groups.group_active()
    groups.set_isolated(group, true)
    # The active layer inside an isolated group is what makes it a scope, which
    # is the path this test exists for. Without it the group folds into a cache
    # and the scratch is never touched.
    doc.set_active_layer(inside)
    _composite(easel)

    assert_almost_eq(_texel(easel.output, 10, 10).r, 1.0, 0.02, "The chunk the scope paints is the scope's red")
    assert_almost_eq(_texel(easel.output, 10, 10).g, 0.0, 0.02, "and holds none of the green under it")

    var right := SaLayer.CHUNK_SIZE + 10
    assert_almost_eq(_texel(easel.output, right, 10).g, 1.0, 0.02, "The chunk it does not paint is the green under it")
    assert_almost_eq(_texel(easel.output, right, 10).r, 0.0, 0.02, "and holds no red from the chunk composited before it")

    easel.free()


## The same claim with the scope's own opacity in the way, because a half
## transparent scope reads the scratch rather than overwriting it, which is the
## case where a stale texel survives into the result instead of being covered.
func test_a_half_opaque_scope_leaves_the_chunk_it_does_not_paint_alone() -> void:
    var easel := _easel()
    var doc := easel.document
    doc.fill_layer(GREEN, doc.active_layer)

    var inside := SaLayerOps.new(doc).add()
    inside.get_or_create_chunk(Vector2i.ZERO).clear(RED)
    doc.invalidate_chunks([Vector2i.ZERO])

    var groups := SaLayerOps.new(doc)
    var group := groups.group_active()
    SaLayerOps.new(doc).set_opacity(group, 0.5)
    groups.set_isolated(group, true)
    doc.set_active_layer(inside)
    _composite(easel)

    var right := SaLayer.CHUNK_SIZE + 10
    assert_almost_eq(_texel(easel.output, right, 10).g, 1.0, 0.02, "Half of nothing over green is still green")
    assert_almost_eq(_texel(easel.output, right, 10).r, 0.0, 0.02, "and no half of the chunk before it")

    easel.free()
