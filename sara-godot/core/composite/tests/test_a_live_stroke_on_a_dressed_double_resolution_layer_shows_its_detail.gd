## Zoomed in, a stroke held down on a layer at 2.0 that is
## masked, clipped, filtered or inside an isolated group shows at the layer's
## own detail before it commits, and matches the committed result.
##
## The plain path, `SaStrokeRun`, took, to the layer's density,
## and the four dressed cases are kept at it in a display chunk's walk. What
## still ran at the document's resolution was a neighbourhood filter over the
## layer and its stroke: the halo it reads the chunks beside from was a chunk
## across, so the chain brought the layer's scratch down to it and blurred at
## 1.0, and the output's chain scratch was a chunk across too. This suite holds
## a stroke over each dressed case and reads the display chunk and the output
## held against the same after the commit. The blurred case failed before.
##
## The document is two chunks across: a plain opaque layer under an active
## layer at 2.0 holding a one-texel checker at grid position 0. The stroke is
## a column of opaque texels every other texel across, which only a display
## chunk at 2.0 shows apart from the texels beside it.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

const REQUIRES_GPU := true

const SIZE := Vector2i(512, 256)
const ONE := Color(0.25, 0.5, 0.75, 1.0)
const TWO := Color(0.75, 0.25, 0.125, 0.25)
const UNDER := Color(0.125, 0.625, 0.25, 1.0)
const BASE := Color(0.875, 0.75, 0.125, 0.5)
const STROKE := Color(1.0, 0.0, 0.5, 1.0)
const CLEAR := Color(0.0, 0.0, 0.0, 0.0)
const AT := Vector2i(0, 0)
const NEXT := Vector2i(1, 0)
## The held and committed paths take different steps to the same picture,
## and a float composite rounds each of them.
const TOLERANCE := 1.0e-5
const DRESSES: Array[String] = ["masked", "clipped", "filtered", "blurred", "grouped"]


func _checker(x: int, y: int) -> Color:
    return ONE if (x + y) % 2 == 0 else TWO


func _upload(texture: SaTexture, texel: Callable) -> void:
    var image := Image.create_empty(texture.size.x, texture.size.y, false, Image.FORMAT_RGBAF)
    for y in texture.size.y:
        for x in texture.size.x:
            image.set_pixel(x, y, texel.call(x, y))
    image.convert(Image.FORMAT_RGBAH if texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT else Image.FORMAT_RGBAF)
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, image.get_data())


func _texels(texture: SaTexture) -> Array:
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var found: Array = []
    for i in texture.size.x * texture.size.y:
        found.append(SaFieldSpec.decode_texel(bytes, texture.format, i))
    return found


## The document of the header, its active layer at *scale* dressed as *dress*
## says: "plain", "masked" with a half mask, "clipped" onto a half clear base,
## "filtered" with the fixture invert, "blurred" with a Gaussian blur and the
## checker in both chunks, so a chunk's blur reads its neighbour, "grouped"
## inside an isolated group at half opacity.
func _easel(dress: String, scale: float) -> SaEasel:
    var easel := Bench.easel(SIZE)
    easel.compositor.filter_chain.registry.register(SaGaussianBlurFilter.new(), &"sara-base-modules")
    easel.shown_rect = func() -> Rect2: return Rect2(0, 0, 256, 256)
    easel.pixels_per_texel = func() -> float: return 4.0
    var doc := easel.document
    var ops := SaLayerOps.new(doc)
    var under := doc.get_node("Layer 1") as SaLayer
    for x in 2:
        under.get_or_create_chunk(Vector2i(x, 0)).clear(UNDER)
    doc.set_active_layer(under)
    if dress == "clipped":
        ops.add().get_or_create_chunk(AT).clear(BASE)
    var boat := ops.add(&"", null, scale)
    _upload(boat.get_or_create_chunk(AT).albedo(), _checker)
    if dress == "blurred":
        _upload(boat.get_or_create_chunk(NEXT).albedo(), _checker)
    doc.set_active_layer(boat)
    match dress:
        "masked":
            boat.add_mask(0.5)
        "clipped":
            SaLayerStack.set_clip_to_below(doc, boat, true)
        "filtered":
            assert_not_null(SaFilterOps.new(doc).attach(boat, Bench.INVERT), "The invert attaches")
        "blurred":
            var key := SaFilterRegistry.key_for(&"sara-base-modules", SaGaussianBlurFilter.new())
            assert_not_null(SaFilterOps.new(doc).attach(boat, key, {"radius": 6.0}), "The blur attaches")
        "grouped":
            var group := ops.group_active()
            ops.set_isolated(group, true)
            group.opacity = 0.5
    doc.set_active_layer(boat)
    doc.invalidate_chunks([AT, Vector2i(1, 0)])
    Bench.composite(easel)
    return easel


## Holds a stroke down over grid positions 0 and 1: every even column opaque,
## the odd ones clear, at the stroke layer's own density.
func _hold(easel: SaEasel) -> void:
    easel.document.begin_stroke(1.0, SaLayer.BLEND_MODE.NORMAL)
    for grid_pos: Vector2i in [AT, NEXT]:
        var chunk := easel.document.stroke_layer.get_or_create_chunk(grid_pos)
        _upload(chunk.albedo(), func(x: int, _y: int) -> Color: return STROKE if x % 2 == 0 else CLEAR)
    easel.document.invalidate_chunks([AT, NEXT])
    easel.process_pending_composite()


func _commit(easel: SaEasel) -> void:
    easel.document.commit_stroke()
    Bench.composite(easel)


## Whether *found* and *wanted* agree within *tolerance* on every channel,
## said aloud at the first texel that does not. True when they do.
func _same(found: Array, wanted: Array, tolerance: float, what: String) -> bool:
    assert_eq(found.size(), wanted.size(), "%s: as many texels" % what)
    for i in mini(found.size(), wanted.size()):
        var a: Color = found[i]
        var b: Color = wanted[i]
        var apart := maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), maxf(absf(a.b - b.b), absf(a.a - b.a)))
        if apart > tolerance:
            assert_true(false, "%s: texel %d is %s held and %s committed" % [what, i, a, b])
            return false
    assert_true(true, "%s: every texel agrees" % what)
    return true


## The held stroke of *dress* at 2.0 shows apart from the texel beside it in
## the display chunk, and the display chunk and the output match their
## committed selves.
func _held_matches_committed(dress: String) -> void:
    var easel := _easel(dress, 2.0)
    _hold(easel)
    var chunk: SaTexture = easel.detail.chunks.get(AT, null)
    assert_not_null(chunk, "%s: a display chunk under the held stroke" % dress)
    if chunk == null:
        easel.free()
        return
    var slot: SaTexture = easel.compositor._walk._pools.stroke[0]
    assert_eq(slot.size, Vector2i(SaChunk.SIZE * 2, SaChunk.SIZE * 2), "%s: the output's chain scratch is as fine" % dress)
    var held_detail := _texels(chunk)
    var held_output := _texels(easel.output)
    var even: Color = held_detail[10 * 512 + 10]
    var odd: Color = held_detail[10 * 512 + 11]
    var apart := "%s: a held stroke texel shows apart from its neighbour, %s and %s" % [dress, even, odd]
    assert_false(even.is_equal_approx(odd), apart)
    _commit(easel)
    _same(held_detail, _texels(easel.detail.chunks[AT]), TOLERANCE, "%s: the display chunk" % dress)
    _same(held_output, _texels(easel.output), TOLERANCE, "%s: the output" % dress)
    easel.free()


func test_a_held_stroke_on_a_masked_layer_at_2_matches_its_commit() -> void:
    _held_matches_committed("masked")


func test_a_held_stroke_on_a_clipped_layer_at_2_matches_its_commit() -> void:
    _held_matches_committed("clipped")


func test_a_held_stroke_on_a_filtered_layer_at_2_matches_its_commit() -> void:
    _held_matches_committed("filtered")


func test_a_held_stroke_on_a_blurred_layer_at_2_matches_its_commit() -> void:
    _held_matches_committed("blurred")


func test_a_held_stroke_in_an_isolated_group_at_2_matches_its_commit() -> void:
    _held_matches_committed("grouped")


## At 1.0 every dressed case paints as before: no display chunk, the stroke
## scratch a chunk across, and the held output the committed one to the bit.
func test_a_dressed_layer_at_1_paints_as_before() -> void:
    for dress: String in DRESSES:
        var easel := _easel(dress, 1.0)
        _hold(easel)
        assert_true(easel.detail.chunks.is_empty(), "%s: no display chunk without a layer at 2.0" % dress)
        for slot: SaTexture in easel.compositor._walk._pools.stroke:
            assert_eq(slot.size, Vector2i(SaChunk.SIZE, SaChunk.SIZE), "%s: the stroke scratch is a chunk across" % dress)
        var held_output := _texels(easel.output)
        _commit(easel)
        _same(held_output, _texels(easel.output), 0.0, "%s: the output at 1.0" % dress)
        easel.free()
