## The ten blur layers of the l1 scenario ran a shot run out
## of 16G of memory. An adjustment layer's picture walked the stack below it a
## chunk at a time, and a blur over a blur drew the chunks around each chunk
## again through the blur below, so ten of them never finished a refresh. An
## adjustment below with no mask and no clip is now run over the plate where it
## stands, the quick way, and these read what it makes.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const Fixtures = preload("res://tests/fixtures.gd")

const OWNER: StringName = &"sara-base-modules"
## Two chunks across and one down, so the picture is 32 texels by 16.
const SIZE := Vector2i(2 * SaChunk.SIZE, SaChunk.SIZE)
## A curve that lifts black to a half.
const LIFT := {"curves": {"master": [[0.0, 0.5], [1.0, 1.0]]}}
## A texel over the first chunk, painted black, and one over the second, white.
const LEFT := Vector2i(8, 8)
const RIGHT := Vector2i(24, 8)

var _types: SaLayerTypeRegistry
var _easel: SaEasel = null


func before_each() -> void:
    _types = Fixtures.make_registries().layer_types
    _easel = Bench.easel(SIZE)
    _easel.compositor.filter_chain.registry.register(SaCurvesFilter.new(), OWNER)
    var doc := _easel.document
    (doc.get_node("Background") as SaLayer).visible = false
    var paint := doc.get_node("Layer 1") as SaLayer
    doc.set_active_layer(paint)
    paint.get_or_create_chunk(Vector2i(0, 0)).clear(Color(0.0, 0.0, 0.0, 1.0))
    paint.get_or_create_chunk(Vector2i(1, 0)).clear(Color(1.0, 1.0, 1.0, 1.0))
    var whole := Rect2i(0, 0, SaChunk.SIZE, SaChunk.SIZE)
    doc.invalidate_chunk_regions({Vector2i(0, 0): whole, Vector2i(1, 0): whole}, paint)


func after_each() -> void:
    _easel.free()
    _easel = null


func _adjustment(title: String, key: StringName, values: Dictionary = {}) -> SaLayer:
    var layer := SaLayerOps.new(_easel.document).add(SaBackdropLayer.TYPE_ID, _types)
    layer.name = title
    assert_not_null(SaFilterOps.new(_easel.document).attach(layer, key, values), "%s attaches" % title)
    return layer


func _thumbnail(layer: SaLayer) -> SaLayerThumbnail:
    var thumb := SaLayerThumbnail.new()
    thumb.bind_layer(layer, _easel.document)
    thumb.refresh()
    return thumb


static func _texel(thumb: SaLayerThumbnail, at: Vector2i) -> Color:
    var texture := thumb._texture
    if texture == null:
        return Color(-1, -1, -1, -1)
    var data: PackedByteArray = GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var i := (at.y * texture.size.x + at.x) * 8
    return Color(data.decode_half(i), data.decode_half(i + 2), data.decode_half(i + 4), data.decode_half(i + 6))


static func _grey(texel: Color, value: float) -> bool:
    return absf(texel.r - value) < 0.05 and absf(texel.g - value) < 0.05 and absf(texel.b - value) < 0.05 and texel.a > 0.95


## An Invert over an Invert gives the paint back, and the top one's picture
## is drawn the quick way with both below it.
func test_an_invert_over_an_invert_reads_the_paint_as_painted() -> void:
    _adjustment("Invert 1", Bench.INVERT)
    var top := _adjustment("Invert 2", Bench.INVERT)
    assert_eq(
        SaBackdropThumbnail.Quick.layers_below(_easel.document, top).size(), 2, "The paint and the adjustment are the quick way"
    )
    var thumb := _thumbnail(top)
    var left := _texel(thumb, LEFT)
    var right := _texel(thumb, RIGHT)
    assert_true(_grey(left, 0.0), "Inverted twice the black half reads black: %s" % left)
    assert_true(_grey(right, 1.0), "and the white half white: %s" % right)
    thumb.free()


## The order counts: an Invert over a lift reads the lifted black inverted,
## a half, and the white black.
func test_the_adjustments_below_run_in_their_order() -> void:
    _adjustment("Curves", SaFilterRegistry.key_for(OWNER, SaCurvesFilter.new()), LIFT)
    var top := _adjustment("Invert", Bench.INVERT)
    var thumb := _thumbnail(top)
    var left := _texel(thumb, LEFT)
    var right := _texel(thumb, RIGHT)
    assert_true(left.r > 0.2 and left.r < 0.8 and left.a > 0.95, "The lifted black reads between, inverted: %s" % left)
    assert_true(_grey(right, 0.0), "and the white black: %s" % right)
    thumb.free()


## A hidden adjustment below is left out, as the canvas leaves it out.
func test_a_hidden_adjustment_below_is_left_out() -> void:
    var below := _adjustment("Invert 1", Bench.INVERT)
    below.visible = false
    var thumb := _thumbnail(_adjustment("Invert 2", Bench.INVERT))
    assert_true(_grey(_texel(thumb, LEFT), 1.0), "One invert alone reads the black half white")
    thumb.free()


## An adjustment below lifted by Affect all still takes the walk, which lifts
## it out of its place. A masked or clipped one is the quick way.
func test_a_lifted_adjustment_below_takes_the_walk() -> void:
    var below := _adjustment("Invert 1", Bench.INVERT)
    assert_true(SaBackdropLayer.affect_all(_easel.document, below, true), "Affect all goes on")
    var top := _adjustment("Invert 2", Bench.INVERT)
    assert_true(
        SaBackdropThumbnail.Quick.layers_below(_easel.document, top).is_empty(), "A lifted adjustment is not the quick way"
    )
