## The first export after a load takes about as long as the
## fifth. An export rounds the live colour as a save rounds the file,
## `SaSadSnapshot.round_live`, and it rounded every colour chunk a layer held,
## an effect layer's too, whose chunks are a cache the file never stores. Its
## redraw refreshed that cache from the input unrounded, so the next export
## rounded it again, and an effect reading it after that. On a large painting,
## 217 effect layers deep, the first export rounded 886 chunks over 19 s, the
## second 445 over 8 s, and only the fifth rounded none.
##
## The painting: a layer named Source holding colour that is not rounded in two
## chunks, and an effect layer above it reading Source through the fixture
## invert, and a second effect reading the first.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const Fixtures = preload("res://tests/fixtures.gd")

const REQUIRES_GPU := true

const SIZE := Vector2i(512, 256)
const HELD: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0)]
## A colour with bits past the twelve a save keeps, so rounding moves it.
const PAINT := Color(0.4123457, 0.3141593, 0.7777777, 1.0)


## The painting of the header, composited once so both effects hold their
## caches, and each name to its layer.
func _painting() -> Dictionary[String, Variant]:
    var types := Fixtures.make_registries().layer_types
    var easel := Bench.easel(SIZE)
    var doc := easel.document
    (doc.get_node("Background") as SaLayer).visible = false
    var source := doc.get_node("Layer 1") as SaLayer
    source.name = "Source"
    doc.set_active_layer(source)
    for grid_pos in HELD:
        source.get_or_create_chunk(grid_pos).clear(PAINT)
    var effect := SaLayerOps.new(doc).add(SaEffectLayer.TYPE_ID, types)
    effect.name = "Effect"
    assert_true(effect.source == source, "The effect reads the layer it was made above")
    assert_not_null(SaFilterOps.new(doc).attach(effect, Bench.INVERT), "The invert attaches to the effect layer")
    doc.set_active_layer(effect)
    var above := SaLayerOps.new(doc).add(SaEffectLayer.TYPE_ID, types)
    above.name = "Above"
    assert_true(above.source == effect, "The second effect reads the first, made above it")
    assert_not_null(SaFilterOps.new(doc).attach(above, Bench.INVERT), "The invert attaches to the second effect")
    Bench.composite(easel)
    var made: Dictionary[String, Variant] = {"easel": easel, "source": source, "effect": effect, "above": above}
    return made


static func _bytes(layer: SaLayer, grid_pos: Vector2i) -> PackedByteArray:
    var texture := layer.get_field(grid_pos)
    return GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0) if texture != null else PackedByteArray()


func test_the_rounding_moves_only_what_the_file_stores_and_settles_at_once() -> void:
    var made := _painting()
    var easel: SaEasel = made["easel"]
    var doc := easel.document
    var source: SaLayer = made["source"]
    var effect: SaLayer = made["effect"]
    var above: SaLayer = made["above"]
    assert_eq(source.get_field(HELD[0]).format, SaSadSnapshot.FULL, "The painting is at full precision, which a save rounds")
    for layer: SaLayer in [effect, above]:
        for grid_pos in HELD:
            assert_not_null(layer.get_field(grid_pos), "%s caches its input at %s" % [layer.name, grid_pos])
    assert_eq(SaSadSnapshot.round_live(doc), HELD.size(), "The source's chunks are rounded and no effect's cache is")
    Bench.composite(easel)
    assert_eq(SaSadSnapshot.round_live(doc), 0, "Once the effects have refreshed, a second rounding moves nothing")
    Bench.composite(easel)
    var held := _bytes(above, HELD[0])
    assert_eq(SaSadSnapshot.round_live(doc), 0, "and neither does a third")
    Bench.composite(easel)
    assert_eq(_bytes(above, HELD[0]), held, "and the second effect's cache is what it was")
    easel.free()
