## Merge Down onto a hidden layer is dimmed and refused, leaving the composite
## canvas and the hidden layer's texels as they were, because merging onto a
## hidden layer would make the merged paint disappear from the screen.
## Merging onto a shown layer composites the paint and takes the upper layer out.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

const REQUIRES_GPU := true

const CANVAS := Vector2i(512, 256)
const BLUE := Color(0.0, 0.0, 1.0, 1.0)
const RED := Color(1.0, 0.0, 0.0, 1.0)
const GREEN := Color(0.0, 1.0, 0.0, 1.0)

var _easel: SaEasel
var _doc: SaDocument
var _ops: SaLayerOps


func before_each() -> void:
    _easel = Bench.easel(CANVAS)
    _doc = _easel.document
    _ops = SaLayerOps.new(_doc)


func after_each() -> void:
    _ops = null
    _doc = null
    _easel.free()
    _easel = null


func _texel(layer: SaLayer, at: Vector2i = Vector2i(10, 10)) -> Color:
    var chunk: SaChunk = layer.chunks.get(Vector2i(0, 0), null)
    if chunk == null:
        return Color(-1, -1, -1, -1)
    return Bench.texel(chunk.albedo(), at)


func _composite_texel(at: Vector2i = Vector2i(10, 10)) -> Color:
    Bench.composite(_easel)
    return Bench.texel(_easel.output, at)


func test_merge_down_onto_a_hidden_layer_leaves_canvas_and_paint_as_they_were() -> void:
    var lower := _doc.get_node("Layer 1") as SaLayer
    _doc.fill_layer(BLUE, lower)
    var upper := _ops.add(&"")
    _doc.fill_layer(RED, upper)
    lower.visible = false

    var composite_before := _composite_texel()
    var lower_before := _texel(lower)

    assert_false(_ops.can_merge_down(upper), "Merge Down is dimmed when the layer below is hidden")
    var refusals := SaLayerRefusals.new(_doc)
    var why := refusals.merge(upper, lower)
    assert_eq(why, ["'%s' is hidden. Show it first.", lower.name], "refusal names the layer and says to show it first")

    var steps_before := _doc.history.step_count()
    var announcing := SaProblems.announce
    SaProblems.announce = false
    SaProblems.pending_refusals = PackedStringArray()
    var merged := _ops.merge_down(upper)
    assert_false(merged, "Merge Down onto a hidden layer is refused")
    assert_true(SaProblems.pending_refusals.size() > 0, "refusal was announced in the corner")
    assert_true(
        SaProblems.pending_refusals[-1].contains("'%s' is hidden. Show it first." % lower.name),
        "corner notice names the layer and says to show it first"
    )

    var composite_after := _composite_texel()
    var lower_after := _texel(lower)
    assert_almost_eq(composite_after.r, composite_before.r, 0.001, "composite canvas red is unchanged")
    assert_almost_eq(composite_after.g, composite_before.g, 0.001, "composite canvas green is unchanged")
    assert_almost_eq(composite_after.b, composite_before.b, 0.001, "composite canvas blue is unchanged")
    assert_almost_eq(composite_after.a, composite_before.a, 0.001, "composite canvas alpha is unchanged")

    assert_almost_eq(lower_after.r, lower_before.r, 0.001, "hidden layer red is unchanged")
    assert_almost_eq(lower_after.g, lower_before.g, 0.001, "hidden layer green is unchanged")
    assert_almost_eq(lower_after.b, lower_before.b, 0.001, "hidden layer blue is unchanged")
    assert_almost_eq(lower_after.a, lower_before.a, 0.001, "hidden layer alpha is unchanged")

    assert_true(is_instance_valid(upper) and upper.get_parent() == _doc, "upper layer was not taken out")
    assert_eq(_doc.history.step_count(), steps_before, "no step was recorded in history")

    assert_false(_ops.can_merge_down(upper, [lower, upper]), "multi-select merge is dimmed when lower is hidden")
    assert_false(_ops.merge_down(upper, [lower, upper]), "multi-select merge is refused when lower is hidden")
    SaProblems.announce = announcing


func test_merge_down_onto_a_shown_layer_merges_paint() -> void:
    var lower := _doc.get_node("Layer 1") as SaLayer
    _doc.fill_layer(BLUE, lower)
    var upper := _ops.add(&"")
    _doc.fill_layer(RED, upper)

    var steps_before := _doc.history.step_count()
    assert_true(_ops.can_merge_down(upper), "Merge Down is offered when the layer below is shown")
    assert_true(_ops.merge_down(upper), "Merge Down onto a shown layer takes")
    assert_false(_ops.layers().has(upper), "upper layer was taken out of the document")
    assert_eq(_doc.active_layer, lower, "lower layer is active now")
    assert_eq(_doc.history.step_count(), steps_before + 1, "one step recorded in history")

    var lower_paint := _texel(lower)
    assert_almost_eq(lower_paint.r, 1.0, 0.01, "lower layer holds the merged red paint")
    var composite := _composite_texel()
    assert_almost_eq(composite.r, 1.0, 0.01, "composite canvas shows the merged red paint")


func test_merge_down_of_a_hidden_upper_layer_draws_nothing_and_takes_the_upper_layer_out() -> void:
    var lower := _doc.get_node("Layer 1") as SaLayer
    _doc.fill_layer(BLUE, lower)
    var upper := _ops.add(&"")
    _doc.fill_layer(GREEN, upper)
    upper.visible = false

    assert_true(_ops.can_merge_down(upper), "Merge Down is offered when the upper layer is hidden")
    assert_true(_ops.merge_down(upper), "Merge Down takes")
    assert_false(_ops.layers().has(upper), "hidden upper layer was taken out")

    var lower_paint := _texel(lower)
    assert_almost_eq(lower_paint.b, 1.0, 0.01, "lower layer retains blue paint")
    assert_almost_eq(lower_paint.g, 0.0, 0.01, "lower layer took no green paint from the hidden upper layer")
