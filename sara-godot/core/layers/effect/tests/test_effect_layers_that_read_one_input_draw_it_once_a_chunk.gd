## The first layer steps after a load of the nights file are
## not met by 20 s of slow frames.
##
## The nights file holds 219 effect layers over 96 inputs, and a load owes every
## effect every chunk. The first door step that showed a season paid the load's
## last 16 chunks in one frame, and 1.6 s of it was each effect drawing its
## input group again. The refresh now draws an input once a chunk for every
## effect that reads it the same way. This suite holds the runs to the order the
## refresh keeps, and each effect of a run to the cache it held when each drew
## its own.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const Fixtures = preload("res://tests/fixtures.gd")

const REQUIRES_GPU := true

const SIZE := Vector2i(768, 512)
const PAINT := Color(0.25, 0.5, 0.75, 1.0)
const LATER := Color(0.875, 0.125, 0.375, 1.0)
const TOLERANCE := 1.0e-4

var _types: SaLayerTypeRegistry


func before_each() -> void:
    _types = Fixtures.make_registries().layer_types
    SaProblems.pending_refusals = PackedStringArray()


## Paint in a group Shared, two effects First and Second reading Shared, and an
## effect Lone outside the group reading the paint itself.
func _painting(easel: SaEasel) -> Dictionary:
    var doc := easel.document
    (doc.get_node("Background") as SaLayer).visible = false
    var paint := doc.get_node("Layer 1") as SaLayer
    paint.name = "Paint"
    paint.get_or_create_chunk(Vector2i(0, 0)).clear(PAINT)
    var lone := _effect(doc, paint, "Lone")
    var shared := SaLayerOps.new(doc).group_layers([paint])
    shared.name = "Shared"
    var first := _effect(doc, shared, "First")
    var second := _effect(doc, shared, "Second")
    Bench.composite(easel)
    return {"paint": paint, "shared": shared, "first": first, "lone": lone, "second": second}


func _effect(doc: SaDocument, source: SaLayer, named: String) -> SaLayer:
    doc.set_active_layer(source)
    var effect := SaLayerOps.new(doc).add(SaEffectLayer.TYPE_ID, _types)
    effect.name = named
    assert_not_null(SaFilterOps.new(doc).attach(effect, Bench.INVERT), "The invert attaches to %s" % named)
    if effect.source != source:
        SaEffectLayer.read(doc, effect, source)
    assert_eq(SaEffectLayer.input_of(effect), source, "%s reads %s" % [named, source.name])
    return effect


static func _near(a: Color, b: Color) -> bool:
    return maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), maxf(absf(a.b - b.b), absf(a.a - b.a))) <= TOLERANCE


static func _keys(layer: SaLayer) -> Array[Vector2i]:
    var found: Array[Vector2i] = []
    found.assign(layer.chunks.keys())
    found.sort()
    return found


func test_effects_that_read_one_input_run_together_where_the_first_stands() -> void:
    var easel := Bench.easel(SIZE)
    var layers := _painting(easel)
    var first: SaLayer = layers["first"]
    var lone: SaLayer = layers["lone"]
    var second: SaLayer = layers["second"]
    assert_false(SaLayerStack.is_inside(lone, layers["shared"]), "Lone stands outside Shared")
    var order: Array[SaLayer] = [first, lone, second]
    var registry := easel.compositor.filter_chain.registry
    var shares := SaEffectLayer._shares(order, registry)
    assert_eq(shares, [[first, second], [lone]], "The two readers of Shared are one run, at the first's place")
    order = [lone, second]
    var said := "An effect the order leaves out is in no run"
    assert_eq(SaEffectLayer._shares(order, registry), [[lone], [second]], said)
    easel.free()


func test_every_effect_of_a_run_holds_its_input_and_follows_new_paint() -> void:
    var easel := Bench.easel(SIZE)
    var layers := _painting(easel)
    var doc := easel.document
    var first: SaLayer = layers["first"]
    var second: SaLayer = layers["second"]
    var held: Array[Vector2i] = [Vector2i(0, 0)]
    for effect: SaLayer in [first, second]:
        assert_eq(_keys(effect), held, "%s holds the chunk its input shows" % effect.name)
        var cached := Bench.texel(effect.get_field(Vector2i(0, 0)), Vector2i(9, 9))
        assert_true(_near(cached, PAINT), "%s's cache is the input's paint, %s" % [effect.name, cached])
    (layers["paint"] as SaLayer).get_or_create_chunk(Vector2i(2, 1)).clear(LATER)
    doc.invalidate_all_allocated_chunks()
    Bench.composite(easel)
    held = [Vector2i(0, 0), Vector2i(2, 1)]
    for effect: SaLayer in [first, second]:
        assert_eq(_keys(effect), held, "%s takes the chunk the input gained" % effect.name)
        var cached := Bench.texel(effect.get_field(Vector2i(2, 1)), Vector2i(9, 9))
        assert_true(_near(cached, LATER), "%s's new chunk is the new paint, %s" % [effect.name, cached])
    easel.free()
