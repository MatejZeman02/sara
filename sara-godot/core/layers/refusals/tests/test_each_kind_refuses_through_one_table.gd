## What each layer kind refuses to a merge, a flatten and a
## filter is read out of one table in `SaLayerRefusals`, and each act answers
## the sentence the three operations said before the move, in their order.
##
## Bare layers with no document, because every row is decided by the kind
## alone. The suites that drive Merge Down, Flatten and Flatten Filter through
## a document, the effect layer's and the adjustment layer's among them, hold
## the corner lines themselves.
extends "res://tests/test_framework.gd"

const GROUP := "'G' is a group. A group merges down into the paint layer under it, but nothing merges onto a group."
const GENERATED := "'N' is a generated layer, and it stores no paint to merge."
const ONTO_ADJUSTMENT := "'A' is an adjustment layer and holds no paint to merge onto."
const ONTO_EFFECT := "'E' is an effect layer, so nothing can be merged onto it."

var _made: Array[SaLayer] = []


func after_each() -> void:
    for layer in _made:
        layer.free()
    _made.clear()


func _layer(named: String) -> SaLayer:
    var layer := SaLayer.new()
    layer.name = named
    _made.append(layer)
    return layer


func _kinds() -> Dictionary[String, SaLayer]:
    var group := _layer("G")
    group.is_group = true
    var generated := _layer("N")
    generated.generator = "paper"
    var adjustment := _layer("A")
    adjustment.input = SaLayerTypeDescriptor.INPUT_BELOW
    var effect := _layer("E")
    effect.input = SaLayerTypeDescriptor.INPUT_NAMED
    return {"group": group, "generated": generated, "adjustment": adjustment, "effect": effect, "paint": _layer("P")}


func _said(found: Array) -> String:
    return "" if found.is_empty() else str(found[0]) % found[1]


func test_a_generated_layer_refuses_either_side_and_a_group_the_lower_side() -> void:
    var refusals := SaLayerRefusals.new(null)
    var kinds := _kinds()
    var paint := kinds["paint"]
    assert_eq(refusals.sentence(SaLayerRefusals.Act.MERGE, kinds["group"]), "", "A group merges down")
    assert_eq(_said(refusals.merge(paint, kinds["group"])), GROUP, "and refuses to be merged onto")
    assert_eq(_said(refusals.merge(kinds["group"], kinds["group"])), GROUP, "by a group as well")
    assert_eq(_said(refusals.merge(kinds["generated"], paint)), GENERATED, "A generated layer refuses to merge down")
    assert_eq(_said(refusals.merge(paint, kinds["generated"])), GENERATED, "and to be merged onto")
    assert_eq(_said(refusals.merge(kinds["generated"], kinds["group"])), GENERATED, "Either side is asked first")


func test_an_adjustment_and_an_effect_layer_refuse_only_the_lower_side() -> void:
    var refusals := SaLayerRefusals.new(null)
    var kinds := _kinds()
    var onto_adjustment := _said(refusals.merge(kinds["paint"], kinds["adjustment"]))
    assert_eq(onto_adjustment, ONTO_ADJUSTMENT, "Nothing merges onto an adjustment layer")
    assert_eq(_said(refusals.merge(kinds["paint"], kinds["effect"])), ONTO_EFFECT, "Nothing merges onto an effect layer")
    var upper := SaLayerRefusals.Act.MERGE
    assert_eq(refusals.sentence(upper, kinds["adjustment"]), "", "An adjustment layer merges down")
    assert_eq(refusals.sentence(upper, kinds["effect"]), "", "and so does an effect layer, as far as its kind goes")
    assert_eq(_said(refusals.merge(kinds["generated"], kinds["effect"])), GENERATED, "Either side comes before the lower side")


func test_only_paint_is_written_into_by_a_flatten() -> void:
    var refusals := SaLayerRefusals.new(null)
    var kinds := _kinds()
    for kind: String in ["group", "generated", "adjustment", "effect"]:
        assert_false(refusals.stores_paint(kinds[kind]), "A %s layer stores no paint" % kind)
        assert_eq(
            refusals.sentence(SaLayerRefusals.Act.STORE, kinds[kind]),
            "'%s' stores no paint.",
            "and the table says so of a %s layer" % kind
        )
    assert_true(refusals.stores_paint(kinds["paint"]), "A paint layer stores paint")


func test_a_filter_flattens_off_everything_but_an_adjustment_or_an_effect_layer() -> void:
    var refusals := SaLayerRefusals.new(null)
    var kinds := _kinds()
    var write := SaLayerRefusals.Act.WRITE_FILTER
    var whole := SaLayerRefusals.Act.READ_WHOLE
    var holds := "'%s' holds no paint to write into. Merge Down applies it to the layer below."
    assert_eq(refusals.sentence(write, kinds["adjustment"]), holds, "An adjustment layer's record does not flatten")
    assert_eq(refusals.sentence(write, kinds["effect"]), holds, "nor an effect layer's")
    assert_eq(refusals.sentence(write, kinds["group"]), "", "A group's flattens into its members")
    assert_eq(refusals.sentence(write, null), "", "and the root's into every layer")
    assert_false(refusals.sentence(whole, kinds["adjustment"]).is_empty(), "A whole-layer read is the adjustment layer's refusal")
    assert_eq(refusals.sentence(whole, kinds["effect"]), "", "and not the effect layer's")
