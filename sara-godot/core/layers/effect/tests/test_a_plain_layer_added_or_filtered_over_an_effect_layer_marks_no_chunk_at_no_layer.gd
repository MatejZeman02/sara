## A plain layer added to a stack that holds an effect layer, and a filter
## attached to that empty layer, change nothing the effect layer reads, so
## neither marks a chunk for redrawing. Both marked every chunk at no layer, and
## on a large night painting each of its 219 effect layers was
## drawn again a chunk a frame for seconds after.
##
## The painting: three chunks across and two down, the grey background hidden,
## a layer named Source holding paint in three chunks, and an effect layer
## above it reading Source through the fixture invert.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const Fixtures = preload("res://tests/fixtures.gd")

const REQUIRES_GPU := true

const SIZE := Vector2i(768, 512)
const HELD: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)]
const PAINT := Color(0.25, 0.5, 0.75, 1.0)

var _types: SaLayerTypeRegistry
var _easel: SaEasel = null


func before_each() -> void:
    _types = Fixtures.make_registries().layer_types
    SaProblems.pending_refusals = PackedStringArray()


## An easel is a Node that no tree owns here, so the suite frees it.
func after_each() -> void:
    if _easel != null:
        _easel.free()
        _easel = null


func _painting() -> SaEasel:
    var easel := Bench.easel(SIZE)
    _easel = easel
    var doc := easel.document
    (doc.get_node("Background") as SaLayer).visible = false
    var source := doc.get_node("Layer 1") as SaLayer
    source.name = "Source"
    doc.set_active_layer(source)
    for grid_pos in HELD:
        source.get_or_create_chunk(grid_pos).clear(PAINT)
    var effect := SaLayerOps.new(doc).add(SaEffectLayer.TYPE_ID, _types)
    effect.name = "Effect"
    assert_not_null(SaFilterOps.new(doc).attach(effect, Bench.INVERT), "The invert attaches to the effect layer")
    doc.set_active_layer(effect)
    Bench.composite(easel)
    doc.consume_dirty_chunks()
    return easel


func test_a_plain_layer_added_over_an_effect_layer_marks_nothing() -> void:
    var easel := _painting()
    var doc := easel.document
    var before := _bytes(easel.output)
    var added := SaLayerOps.new(doc).add(&"", _types)
    assert_true(added.chunks.is_empty(), "The layer comes holding no chunk")
    var dirty := doc.consume_dirty_chunks()
    assert_true(dirty.is_empty(), "and nothing is marked for redrawing, not every chunk at no layer: %s" % [dirty.keys()])
    Bench.composite(easel)
    assert_eq(_bytes(easel.output), before, "The picture stands as it was, byte for byte")


func test_a_filter_attached_to_the_empty_layer_marks_nothing() -> void:
    var easel := _painting()
    var doc := easel.document
    var before := _bytes(easel.output)
    var added := SaLayerOps.new(doc).add(&"", _types)
    doc.consume_dirty_chunks()
    assert_not_null(SaFilterOps.new(doc).attach(added, Bench.INVERT), "The invert attaches to the empty layer")
    var dirty := doc.consume_dirty_chunks()
    assert_true(dirty.is_empty(), "A filter on a layer that holds nothing marks nothing: %s" % [dirty.keys()])
    Bench.composite(easel)
    assert_eq(_bytes(easel.output), before, "and the picture stands as it was, byte for byte")


func test_a_filter_attached_to_a_painted_layer_marks_its_chunks_at_it() -> void:
    var easel := _painting()
    var doc := easel.document
    var source := doc.get_node("Source") as SaLayer
    assert_not_null(SaFilterOps.new(doc).attach(source, Bench.INVERT), "The invert attaches to Source")
    var dirty := doc.consume_dirty_chunks()
    var marked: Array[Vector2i] = []
    marked.assign(dirty.keys())
    marked.sort()
    var held := HELD.duplicate()
    held.sort()
    assert_eq(marked, held, "The chunks Source holds are marked")
    var at: Array = doc.moved_at.keys()
    assert_eq(at, [source.get_instance_id()], "at Source, so the effect layer reading it is the one drawn again")


static func _bytes(texture: SaTexture) -> PackedByteArray:
    return GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
