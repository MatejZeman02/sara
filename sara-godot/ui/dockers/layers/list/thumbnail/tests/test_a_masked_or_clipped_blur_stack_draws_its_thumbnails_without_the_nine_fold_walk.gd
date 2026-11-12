## A plain adjustment below a row's picture is drawn the
## quick way, but a masked or clipped one would take `SaTreeRender`'s walk,
## where a blur draws the chunks around its chunk again through the blur below.
## A stack of blurs as a layers scenario stacks them, each masked and the lowest
## clipped to the paint, is now drawn the quick way, and these read its
## dispatches against a bound and what a mask and a clip make of the picture.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const Fixtures = preload("res://tests/fixtures.gd")

const OWNER: StringName = &"sara-base-modules"
## Four chunks across and two down, so the picture is 64 texels by 32.
const SIZE := Vector2i(4 * SaChunk.SIZE, 2 * SaChunk.SIZE)
## Blurs of radius 2 to 20, as l1 stacks them.
const BLURS := 10
## The most dispatches the top blur's picture takes the quick way. Measured at
## 104 for this stack, and the walk took three of its masked blurs
## over a paint layer with a record in 1,335.
const BOUND := 200
## How many masked blurs the walk is given.
const WALKED := 3
## Where in the picture, as a part of its size, a texel over the left half
## lies, painted black, and one over the right, white.
const LEFT := Vector2(0.25, 0.5)
const RIGHT := Vector2(0.75, 0.5)

var _types: SaLayerTypeRegistry
var _easel: SaEasel = null
var _paint: SaLayer = null


func before_each() -> void:
    _types = Fixtures.make_registries().layer_types
    _easel = Bench.easel(SIZE)
    _easel.compositor.filter_chain.registry.register(SaGaussianBlurFilter.new(), OWNER)
    var doc := _easel.document
    (doc.get_node("Background") as SaLayer).visible = false
    _paint = doc.get_node("Layer 1") as SaLayer
    doc.set_active_layer(_paint)
    var whole := Rect2i(0, 0, SaChunk.SIZE, SaChunk.SIZE)
    var moved: Dictionary[Vector2i, Rect2i] = {}
    for x in 4:
        for y in 2:
            var white := 1.0 if x >= 2 else 0.0
            _paint.get_or_create_chunk(Vector2i(x, y)).clear(Color(white, white, white, 1.0))
            moved[Vector2i(x, y)] = whole
    doc.invalidate_chunk_regions(moved, _paint)


func after_each() -> void:
    _easel.free()
    _easel = null
    _paint = null


func _adjustment(title: String, key: StringName, values: Dictionary = {}) -> SaLayer:
    var layer := SaLayerOps.new(_easel.document).add(SaBackdropLayer.TYPE_ID, _types)
    layer.name = title
    assert_not_null(SaFilterOps.new(_easel.document).attach(layer, key, values), "%s attaches" % title)
    return layer


## A mask of its own on *layer* that hides the left half at *left* and shows
## the right whole.
static func _mask(layer: SaLayer, left: float) -> void:
    layer.mask = SaMask.own()
    for y in 2:
        for x in 2:
            layer.mask.get_or_create(Vector2i(x, y)).clear(Color(left, left, left, left))


## The l1 stack: ten blurs, radius 2 at the bottom to 20 at the top, each
## masked, and the lowest clipped to the paint. The top one is handed back.
func _blur_stack(count: int, clip: bool) -> SaLayer:
    var key := SaFilterRegistry.key_for(OWNER, SaGaussianBlurFilter.new())
    var top: SaLayer = null
    for i in count:
        var radius := 2 * (i + 1)
        top = _adjustment("Blur %d" % radius, key, {"radius": radius})
        _mask(top, 0.5)
        top.clip_to_below = clip and i == 0
    return top


func _thumbnail(layer: SaLayer) -> SaLayerThumbnail:
    var thumb := SaLayerThumbnail.new()
    thumb.bind_layer(layer, _easel.document)
    thumb.refresh()
    return thumb


## The dispatches *layer*'s picture takes when it is first drawn.
func _dispatches(layer: SaLayer) -> int:
    var before := SaCompute.dispatches
    var thumb := _thumbnail(layer)
    var spent := SaCompute.dispatches - before
    assert_not_null(thumb._texture, "%s's picture is drawn" % layer.name)
    thumb.free()
    return spent


static func _texel(thumb: SaLayerThumbnail, part: Vector2) -> Color:
    var texture := thumb._texture
    if texture == null:
        return Color(-1, -1, -1, -1)
    var at := Vector2i(Vector2(texture.size) * part)
    var data: PackedByteArray = GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var i := (at.y * texture.size.x + at.x) * 8
    return Color(data.decode_half(i), data.decode_half(i + 2), data.decode_half(i + 4), data.decode_half(i + 6))


static func _grey(texel: Color, value: float) -> bool:
    return absf(texel.r - value) < 0.05 and absf(texel.g - value) < 0.05 and absf(texel.b - value) < 0.05 and texel.a > 0.95


## The ten masked blurs, the lowest clipped, are the quick way, and the top
## one's picture is drawn under the bound.
func test_a_masked_and_clipped_blur_stack_is_drawn_under_the_bound() -> void:
    var top := _blur_stack(BLURS, true)
    assert_eq(
        SaBackdropThumbnail.Quick.layers_below(_easel.document, top).size(),
        BLURS,
        "The paint and the nine blurs below are the quick way"
    )
    var spent := _dispatches(top)
    assert_true(spent < BOUND, "The picture takes %d dispatches, under %d" % [spent, BOUND])


## A stack of masked blurs with a record on the paint takes the walk, and the
## walk is past the bound with fewer blurs than the stack above, so a return
## to it fails that test. The walk is not given the clip, under which a blur's
## halo renders the clip group that renders the blur again without end.
func test_the_same_stack_drawn_through_the_walk_is_past_the_bound() -> void:
    var top := _blur_stack(WALKED, false)
    assert_not_null(SaFilterOps.new(_easel.document).attach(_paint, Bench.INVERT), "The paint takes a record")
    assert_true(SaBackdropThumbnail.Quick.layers_below(_easel.document, top).is_empty(), "A record on the paint is the walk")
    var spent := _dispatches(top)
    assert_true(spent > BOUND, "The walk takes %d dispatches, past %d" % [spent, BOUND])


## A masked Invert below inverts where its mask shows and leaves the paint
## where it hides, and the Invert over it inverts what that left.
func test_a_masked_adjustment_below_shows_through_its_mask() -> void:
    var below := _adjustment("Invert 1", Bench.INVERT)
    _mask(below, 0.0)
    var top := _adjustment("Invert 2", Bench.INVERT)
    assert_eq(SaBackdropThumbnail.Quick.layers_below(_easel.document, top).size(), 2, "A masked adjustment is the quick way")
    var thumb := _thumbnail(top)
    var left := _texel(thumb, LEFT)
    var right := _texel(thumb, RIGHT)
    assert_true(_grey(left, 1.0), "Masked off below, the black is inverted once, white: %s" % left)
    assert_true(_grey(right, 1.0), "and shown below, the white is inverted twice, white: %s" % right)
    thumb.free()


## An Invert clipped to a dark grey base over the left half inverts the base
## alone, so the white paint beside it stays white, and the Invert over the
## stack reads that white black.
func test_a_clipped_adjustment_below_adjusts_its_base_alone() -> void:
    var base := SaLayerOps.new(_easel.document).add()
    base.name = "Base"
    var moved: Dictionary[Vector2i, Rect2i] = {}
    for y in 2:
        for x in 2:
            base.get_or_create_chunk(Vector2i(x, y)).clear(Color(0.2, 0.2, 0.2, 1.0))
            moved[Vector2i(x, y)] = Rect2i(0, 0, SaChunk.SIZE, SaChunk.SIZE)
    _easel.document.invalidate_chunk_regions(moved, base)
    var clipped := _adjustment("Invert 1", Bench.INVERT)
    clipped.clip_to_below = true
    var top := _adjustment("Invert 2", Bench.INVERT)
    assert_eq(SaBackdropThumbnail.Quick.layers_below(_easel.document, top).size(), 3, "A clip run is the quick way")
    var thumb := _thumbnail(top)
    var left := _texel(thumb, LEFT)
    var right := _texel(thumb, RIGHT)
    assert_true(_grey(left, 0.2), "The base inverted twice reads its grey: %s" % left)
    assert_true(_grey(right, 0.0), "and the white past it, never inverted below, reads black: %s" % right)
    thumb.free()


## A row's own layer clipped to a base still takes the walk, whose backdrop is
## the base's plate rather than the stack's.
func test_a_clipped_rows_own_layer_takes_the_walk() -> void:
    var top := _adjustment("Invert 1", Bench.INVERT)
    top.clip_to_below = true
    assert_true(SaBackdropThumbnail.Quick.layers_below(_easel.document, top).is_empty(), "A clipped row is the walk")
