## Zoomed in, a stroke held down on a layer at 2.0 shows at the
## layer's own detail before it commits, not only after.
##
## The live stroke and the active layer meet in a stroke scratch, which used
## to be a chunk across whatever the layer's density, so a held stroke reached
## the display chunks of a double-resolution layer averaged and magnified. The scratch is now as fine
## as the stroke. The lifted picture of a transform is the same stroke layer,
## so this suite covers its preview too.
##
## The document is two chunks across: a plain layer in Normal under an active
## layer at 2.0 that holds a one-texel checker at grid position 0. The stroke
## is a column of opaque texels every other texel across, which only a
## display chunk at 2.0 can show apart from the texels beside it.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

const REQUIRES_GPU := true

const SIZE := Vector2i(512, 256)
const ONE := Color(0.25, 0.5, 0.75, 0.5)
const TWO := Color(0.75, 0.25, 0.125, 0.5)
const UNDER := Color(0.125, 0.625, 0.25, 1.0)
const STROKE := Color(1.0, 0.0, 0.5, 1.0)
const CLEAR := Color(0.0, 0.0, 0.0, 0.0)

var _zoom := 4.0


func _upload(texture: SaTexture, texel: Callable) -> void:
    var image := Image.create_empty(texture.size.x, texture.size.y, false, Image.FORMAT_RGBAF)
    for y in texture.size.y:
        for x in texture.size.x:
            image.set_pixel(x, y, texel.call(x, y))
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, image.get_data())


func _checker(x: int, y: int) -> Color:
    return ONE if (x + y) % 2 == 0 else TWO


func _texels(texture: SaTexture) -> Array:
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var found: Array = []
    for i in texture.size.x * texture.size.y:
        found.append(SaFieldSpec.decode_texel(bytes, texture.format, i))
    return found


## The document of the header with its active layer at *scale*.
func _easel(scale: float) -> SaEasel:
    var easel := SaEasel.create_default(SIZE)
    easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    easel.shown_rect = func() -> Rect2: return Rect2(0, 0, 256, 256)
    easel.pixels_per_texel = func() -> float: return _zoom
    var doc := easel.document
    var under := doc.get_node("Layer 1") as SaLayer
    for grid_pos: Vector2i in [Vector2i(0, 0), Vector2i(1, 0)]:
        under.get_or_create_chunk(grid_pos).clear(UNDER)
    doc.set_active_layer(under)
    var boat := SaLayerOps.new(doc).add(&"", null, scale)
    _upload(boat.get_or_create_chunk(Vector2i(0, 0)).albedo(), _checker)
    doc.set_active_layer(boat)
    doc.invalidate_chunks([Vector2i(0, 0), Vector2i(1, 0)])
    _composite(easel)
    return easel


func _composite(easel: SaEasel) -> void:
    easel.document.update_caches()
    easel.request_full_composite()
    easel.process_pending_composite()


## Holds a stroke down over *positions*: every even column opaque, the odd
## ones clear, at the stroke layer's own density.
func _hold(easel: SaEasel, positions: Array) -> void:
    easel.document.begin_stroke(1.0, SaLayer.BLEND_MODE.NORMAL)
    for grid_pos: Vector2i in positions:
        var chunk := easel.document.stroke_layer.get_or_create_chunk(grid_pos)
        _upload(chunk.albedo(), func(x: int, _y: int) -> Color: return STROKE if x % 2 == 0 else CLEAR)
    easel.document.invalidate_chunks(positions)
    easel.process_pending_composite()


## Whether *found* and *wanted*, two lists of texels, agree within *tolerance*
## on every channel, said aloud at the first that does not.
func _same(found: Array, wanted: Array, tolerance: float, what: String) -> void:
    assert_eq(found.size(), wanted.size(), "%s: as many texels" % what)
    for i in mini(found.size(), wanted.size()):
        var a: Color = found[i]
        var b: Color = wanted[i]
        var apart := maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), maxf(absf(a.b - b.b), absf(a.a - b.a)))
        if apart > tolerance:
            assert_true(false, "%s: texel %d is %s held and %s committed" % [what, i, a, b])
            return
    assert_true(true, "%s: every texel agrees" % what)


func before_each() -> void:
    _zoom = 4.0


func test_a_held_stroke_on_a_layer_at_2_shows_its_own_texels() -> void:
    var easel := _easel(2.0)
    _hold(easel, [Vector2i(0, 0)])
    var chunk: SaTexture = easel.detail.chunks.get(Vector2i(0, 0), null)
    assert_true(chunk != null, "A display chunk under the held stroke")
    if chunk != null:
        var texels := _texels(chunk)
        var even: Color = texels[10 * 512 + 10]
        var odd: Color = texels[10 * 512 + 11]
        assert_true(even.is_equal_approx(STROKE), "An even display texel is the stroke's own, %s" % even)
        assert_false(odd.is_equal_approx(even), "The odd texel beside it is the checker under, %s" % odd)
    easel.free()


func test_the_held_stroke_matches_the_committed_result() -> void:
    var easel := _easel(2.0)
    _hold(easel, [Vector2i(0, 0)])
    var held_detail := _texels(easel.detail.chunks[Vector2i(0, 0)])
    var held_output := _texels(easel.output)
    easel.document.commit_stroke()
    _composite(easel)
    _same(held_detail, _texels(easel.detail.chunks[Vector2i(0, 0)]), 1.0e-5, "The display chunk")
    _same(held_output, _texels(easel.output), 1.0e-5, "The output at the document's resolution")
    easel.free()


## A stroke where the layer at 2.0 holds nothing yet still has a display chunk
## to show in, so it is at its detail before the commit makes the chunk.
func test_a_stroke_past_the_layers_chunks_is_shown_at_its_detail() -> void:
    var easel := _easel(2.0)
    assert_false(easel.detail.chunks.has(Vector2i(1, 0)), "The layer holds nothing at grid 1")
    easel.shown_rect = func() -> Rect2: return Rect2(256, 0, 256, 256)
    _hold(easel, [Vector2i(1, 0)])
    var chunk: SaTexture = easel.detail.chunks.get(Vector2i(1, 0), null)
    assert_true(chunk != null, "The held stroke's own chunk has a display chunk")
    if chunk != null:
        var texels := _texels(chunk)
        assert_true((texels[10 * 512 + 10] as Color).is_equal_approx(STROKE), "An even texel is the stroke")
        assert_true((texels[10 * 512 + 11] as Color).is_equal_approx(UNDER), "An odd texel is the layer under")
    easel.free()


## At 1.0 the scratch is a chunk across as it always was, and the held stroke
## reaches the output exactly as its commit does.
func test_a_layer_at_1_paints_as_before() -> void:
    var easel := _easel(1.0)
    _hold(easel, [Vector2i(0, 0)])
    assert_true(easel.detail.chunks.is_empty(), "No display chunk without a layer at 2.0")
    var slot: SaTexture = easel.compositor._walk._pools.stroke[0]
    assert_eq(slot.size, Vector2i(SaChunk.SIZE, SaChunk.SIZE), "The stroke scratch is a chunk across")
    var held_output := _texels(easel.output)
    easel.document.commit_stroke()
    _composite(easel)
    _same(held_output, _texels(easel.output), 0.0, "The output at 1.0")
    easel.free()


func test_a_scratch_follows_the_density_it_is_asked_for() -> void:
    var pools := SaScratchPools.new()
    var coarse := pools.stroke_slot(0, RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT)
    assert_eq(coarse.size, Vector2i(SaChunk.SIZE, SaChunk.SIZE), "At 1.0 a chunk across")
    var fine := pools.stroke_slot(0, RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT, 2.0)
    assert_eq(fine.size, Vector2i(SaChunk.SIZE * 2, SaChunk.SIZE * 2), "At 2.0 twice that")
    assert_true(pools.stroke_slot(0, fine.format, 2.0) == fine, "Asked again, the same texture")
    assert_eq(SaStrokeRun.finer(Rect2i(3, 4, 5, 6), 2.0), Rect2i(6, 8, 10, 12), "A region in a scratch at 2.0")
    assert_eq(SaStrokeRun.finer(Rect2i(3, 4, 5, 6), 1.0), Rect2i(3, 4, 5, 6), "And at 1.0 itself")
