## Merge Down refuses a generated layer on either side and a group as the
## lower side, as Krita does. A group merged down onto paint
## takes, whose suite beside `SaGroupMerge` holds it.
##
## Before it, `can_merge_down` asked only that a layer sat below and
## `merge_down` folded the upper chunks into the lower. A group merged down was
## taken out while its members still named it as their parent, and a paint
## layer merged onto a group wrote its paint into the group node's own chunks,
## which the compositor never draws. Each case here finds the merge dimmed and
## refused, with the stack, every layer's chunks and the undo history as they
## were, and a plain merge between two paint layers still taking.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

const REQUIRES_GPU := true

const GROUND := Color(0.1, 0.3, 0.7, 1.0)
const PAINT := Color(0.8, 0.2, 0.1, 1.0)

var _easel: SaEasel
var _doc: SaDocument
var _ops: SaLayerOps
var _ground: SaLayer


func before_each() -> void:
    _easel = Bench.easel(Vector2i(512, 256))
    _doc = _easel.document
    _ops = SaLayerOps.new(_doc)
    _ground = _doc.active_layer
    _doc.fill_layer(GROUND, _ground)


func after_each() -> void:
    _ops = null
    _ground = null
    _doc = null
    _easel.free()
    _easel = null


## A paint layer filled with *color*, added above the active one.
func _painted(color: Color) -> SaLayer:
    var layer := _ops.add()
    _doc.fill_layer(color, layer)
    return layer


## A generated layer above the active one, of the background type the
## skeleton registers. A ground is added under the paint, so it is moved up over the active layer, which is
## where a merge meets it.
func _generated() -> SaLayer:
    var registries := SaRegistries.new()
    registries.build_context(func() -> Variant: return null, func() -> Array: return [])
    registries.register_builtins()
    var over := _doc.active_layer
    var layer := _ops.add(&"background", registries.layer_types)
    _ops.move(layer, over.get_index() - layer.get_index())
    assert_true(layer.is_generated(), "The background type makes a generated layer")
    return layer


## The stack, each layer's parent group and each layer's chunk positions.
func _picture() -> Array:
    var found: Array = []
    for layer in _ops.layers():
        var keys := layer.chunks.keys()
        keys.sort()
        found.append([layer, layer.group, keys])
    return found


## Merges *upper* down and expects the merge dimmed, refused and without a
## trace.
func _refused(upper: SaLayer, below: SaLayer, what: String) -> void:
    assert_eq(SaGroupMerge.lower_of(_doc, upper), below, "%s: the layer below is the one meant" % what)
    var before := _picture()
    var steps := _doc.history.step_count()
    assert_false(_ops.can_merge_down(upper), "%s: Merge Down is dimmed" % what)
    assert_false(_ops.merge_down(upper), "%s: Merge Down is refused" % what)
    assert_eq(_picture(), before, "%s: the stack and the chunks are as they were" % what)
    assert_eq(_doc.history.step_count(), steps, "%s: no step went into the history" % what)


func test_a_group_is_not_merged_onto_a_group() -> void:
    var lower := _ops.group_layers([_painted(PAINT)])
    _doc.set_active_layer(lower)
    var upper := _ops.group_layers([_painted(PAINT)])
    _refused(upper, lower, "A group onto a group")


func test_a_paint_layer_is_not_merged_onto_a_group() -> void:
    var member := _painted(PAINT)
    var group := _ops.group_layers([member])
    _doc.set_active_layer(group)
    var upper := _painted(PAINT)
    assert_null(upper.group, "The paint layer stands outside the group")
    _refused(upper, group, "A paint layer onto a group")


func test_a_paint_layer_is_not_merged_onto_a_generated_layer() -> void:
    var paper := _generated()
    var upper := _painted(PAINT)
    _refused(upper, paper, "A paint layer onto a generated layer")


func test_a_generated_layer_is_not_merged_onto_a_paint_layer() -> void:
    var paper := _generated()
    _refused(paper, _ground, "A generated layer onto a paint layer")


func test_a_plain_merge_still_takes() -> void:
    var upper := _painted(PAINT)
    var steps := _doc.history.step_count()
    assert_true(_ops.can_merge_down(upper), "Merge Down is offered between two paint layers")
    assert_true(_ops.merge_down(upper), "and it merges")
    assert_false(_ops.layers().has(upper), "The upper layer is gone into the one below")
    assert_eq(_doc.active_layer, _ground, "which is active now")
    assert_eq(_doc.history.step_count(), steps + 1, "as one step")
