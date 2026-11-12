## Opening a large painting holds no frame for more than a
## second, at 1,945 blobs too.
##
## A large winter painting's 217 effect layers cost each composite after its
## open about 250 ms in their refresh. Their order was found by asking every
## effect whether it sat inside every other's input, and each group's reach by
## walking its members again for each effect that read it. Both are now found
## once a refresh, and this suite holds them to what the old searches answered,
## kept here as the reference. The composite's budget weighs each effect layer
## too, since each draws its input again before the walk.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const Fixtures = preload("res://tests/fixtures.gd")

const REQUIRES_GPU := true

const SIZE := Vector2i(768, 512)
const PAINT := Color(0.25, 0.5, 0.75, 1.0)

var _types: SaLayerTypeRegistry


func before_each() -> void:
    _types = Fixtures.make_registries().layer_types
    SaProblems.pending_refusals = PackedStringArray()


## Paint in a group Inner beside an effect reading the paint, Inner in a group
## Outer beside an effect reading Inner, and an effect on top reading Outer:
## each effect reads one that sits inside its input.
func _nested(easel: SaEasel) -> Dictionary:
    var doc := easel.document
    (doc.get_node("Background") as SaLayer).visible = false
    var paint := doc.get_node("Layer 1") as SaLayer
    paint.name = "Paint"
    for grid_pos: Vector2i in [Vector2i(0, 0), Vector2i(2, 1)]:
        paint.get_or_create_chunk(grid_pos).clear(PAINT)
    var ops := SaLayerOps.new(doc)
    doc.set_active_layer(paint)
    var low := _effect(doc, paint, "Low")
    var inner := ops.group_layers([paint, low])
    inner.name = "Inner"
    var middle := _effect(doc, inner, "Middle")
    var outer := ops.group_layers([inner, middle])
    outer.name = "Outer"
    var top := _effect(doc, outer, "Top")
    Bench.composite(easel)
    return {"paint": paint, "low": low, "inner": inner, "middle": middle, "outer": outer, "top": top}


func _effect(doc: SaDocument, source: SaLayer, named: String) -> SaLayer:
    doc.set_active_layer(source)
    var effect := SaLayerOps.new(doc).add(SaEffectLayer.TYPE_ID, _types)
    effect.name = named
    assert_not_null(SaFilterOps.new(doc).attach(effect, Bench.INVERT), "The invert attaches to %s" % named)
    if effect.source != source:
        SaEffectLayer.read(doc, effect, source)
    assert_eq(SaEffectLayer.input_of(effect), source, "%s reads %s" % [named, source.name])
    return effect


# The order as it was found before the fix, every effect asked of every other.
static func _old_ordered(effects: Array[SaLayer]) -> Array[SaLayer]:
    var found: Array[SaLayer] = []
    for layer in effects:
        _old_visit(effects, layer, found, 0)
    return found


static func _old_visit(effects: Array[SaLayer], effect: SaLayer, found: Array[SaLayer], depth: int) -> void:
    if found.has(effect) or depth > 64:
        return
    var source := SaEffectLayer.input_of(effect)
    if source != null:
        for other in effects:
            if other != effect and SaLayerStack.is_inside(other, source):
                _old_visit(effects, other, found, depth + 1)
    if not found.has(effect):
        found.append(effect)


# The reach as it was found before the fix, the members walked afresh each time.
static func _old_reach(
    compositor: SaCompositor, document: SaDocument, node: SaLayer, own: bool = true
) -> Dictionary[Vector2i, bool]:
    var found: Dictionary[Vector2i, bool] = {}
    if node.is_group:
        for member in SaLayerStack.members(document, node):
            if member.is_generated():
                for grid_pos in SaLayer.grid_positions(document.canvas_size):
                    found[grid_pos] = true
            elif not member.is_adjustment():
                found.merge(_old_reach(compositor, document, member))
    else:
        found = SaTyped.positions(SaLiveTransform.paint_of(node).chunks)
    return compositor.filter_chain.walked(node, found) if own else found


static func _sorted(positions: Dictionary) -> Array:
    var keys := positions.keys()
    keys.sort()
    return keys


func test_the_effects_come_after_those_inside_their_input_in_every_order_asked() -> void:
    var easel := Bench.easel(SIZE)
    var layers := _nested(easel)
    var low: SaLayer = layers["low"]
    var middle: SaLayer = layers["middle"]
    var top: SaLayer = layers["top"]
    var expected: Array[SaLayer] = [low, middle, top]
    assert_eq(SaEffectLayer.ordered(easel.document), expected, "The stack's effects come innermost first")
    for listed: Array in [[top, middle, low], [middle, top, low], [top, low, middle], [low, top]]:
        var asked: Array[SaLayer] = []
        asked.assign(listed)
        var names := asked.map(func(layer: SaLayer) -> String: return str(layer.name))
        var said := "Asked as %s, the order is the old search's" % [names]
        assert_eq(SaEffectLayer.ordered(easel.document, asked), _old_ordered(asked), said)
    easel.free()


func test_each_node_s_reach_is_the_old_search_s_with_and_without_its_own_records() -> void:
    var easel := Bench.easel(SIZE)
    var layers := _nested(easel)
    var reaches := SaEffectLayer.Reaches.new(easel.compositor, easel.document)
    for key: String in ["outer", "inner", "paint", "middle", "low"]:
        var node: SaLayer = layers[key]
        for own: bool in [true, false]:
            var found := reaches.of(node, own)
            var old := _old_reach(easel.compositor, easel.document, node, own)
            assert_eq(_sorted(found), _sorted(old), "%s's reach, own %s, is the old search's" % [node.name, own])
    assert_true(reaches.of(layers["outer"]).has(Vector2i(2, 1)), "A group reaches its members' paint")
    assert_true(is_same(reaches.of(layers["outer"]), reaches.of(layers["outer"])), "and is found once a refresh")
    easel.free()


func test_each_effect_layer_weighs_one_chunk_more_in_the_composite_s_budget() -> void:
    var easel := Bench.easel(SIZE)
    var before := SaCompositeBudget.weight(easel.document)
    _nested(easel)
    assert_eq(SaCompositeBudget.weight(easel.document), before + 3, "Three effect layers weigh three more")
    easel.free()
