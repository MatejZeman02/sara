## Merge Down on a group merges it into the paint layer under
## it, as Krita's Merge with Layer Below does, where Sara refused a group on
## either side of a merge.
##
## A group of two painted layers goes down onto a paint layer and one layer is
## left, holding what the three showed and the same pixels a Flatten of the
## same stack writes, in one step whose undo puts the three back. A group onto
## a group stays refused with the line that names the lower one, and the stack
## and the history are as they were.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

const REQUIRES_GPU := true

const GROUND := Color(0.1, 0.3, 0.7, 1.0)
const FIRST := Color(0.8, 0.2, 0.1, 1.0)
const SECOND := Color(0.2, 0.9, 0.4, 0.6)
## Shown by the dressed group's mask, hidden by it, and in the chunk it holds
## nothing at, which reads as shown.
const NEAR := Vector2i(40, 10)
const HIDDEN := Vector2i(200, 10)
const FAR := Vector2i(300, 10)
const POINTS: Array[Vector2i] = [NEAR, HIDDEN, FAR]

var _easel: SaEasel
var _doc: SaDocument
var _ops: SaLayerOps
var _bottom: SaLayer


func before_each() -> void:
    _easel = Bench.easel(Vector2i(512, 256))
    _doc = _easel.document
    _ops = SaLayerOps.new(_doc)
    _bottom = _ops.layers()[0]
    # The easel comes with an empty layer over its background, which a Flatten
    # would take into the bottom layer and a merge of the group would not.
    for layer: SaLayer in _ops.layers().slice(1):
        _ops.remove(layer)
    _doc.set_active_layer(_bottom)
    _doc.fill_layer(GROUND, _bottom)


func after_each() -> void:
    _ops = null
    _bottom = null
    _doc = null
    _easel.free()
    _easel = null


## A layer filled with *color* above the active one.
func _painted(color: Color) -> SaLayer:
    var layer := _ops.add()
    _doc.fill_layer(color, layer)
    return layer


## A group at half opacity over a plain layer and a Multiply one, isolated
## with an invert and a mask over the right half of the first chunk when
## *dressed*, pass-through otherwise.
func _group(dressed: bool) -> SaLayer:
    var first := _painted(FIRST)
    var second := _painted(SECOND)
    _ops.set_blend_mode(second, &"multiply")
    var group := _ops.group_layers([first, second])
    _ops.set_opacity(group, 0.5)
    if dressed:
        _ops.set_isolated(group, true)
        SaFilterOps.new(_doc).attach(group, Bench.INVERT, {"strength": 1.0})
        assert_true(SaMaskOps.new(_doc).add(group), "The group takes a mask")
        _write_half(group.mask.get_or_create(Vector2i(0, 0)))
        SaLayerStack.invalidate_layer_chunks(_doc, group)
    _doc.update_caches()
    return group


## One over the left half of the first chunk and nought over the right half.
func _write_half(coverage: SaTexture) -> void:
    var values := PackedFloat32Array()
    values.resize(coverage.size.x * coverage.size.y)
    for y in coverage.size.y:
        for x in coverage.size.x:
            values[y * coverage.size.x + x] = 1.0 if x < floori(coverage.size.x / 2.0) else 0.0
    GlobalShaderCompiler.get_rd().texture_update(coverage.rid, 0, values.to_byte_array())


## The canvas at every point.
func _output() -> Array:
    Bench.composite(_easel)
    var found: Array = []
    for at in POINTS:
        found.append(Bench.texel(_easel.output, at))
    return found


## The bottom layer's own paint at every point.
func _paint() -> Array:
    var found: Array = []
    for at in POINTS:
        var chunk := _bottom.get_field(Vector2i((Vector2(at) / SaLayer.CHUNK_SIZE).floor()))
        assert_not_null(chunk, "The bottom layer holds paint at %s" % at)
        found.append(Bench.texel(chunk, at % SaLayer.CHUNK_SIZE) if chunk != null else Color())
    return found


func _same(before: Array, after: Array, what: String) -> void:
    for i in before.size():
        var was: Color = before[i]
        var now: Color = after[i]
        var moved := maxf(maxf(absf(was.r - now.r), absf(was.g - now.g)), maxf(absf(was.b - now.b), absf(was.a - now.a)))
        assert_true(moved < 0.01, "%s, point %d: %s became %s" % [what, i, was, now])


## What the corner says while *work* runs.
func _refusals_during(work: Callable) -> PackedStringArray:
    var kept := SaProblems.pending_refusals
    var announcing := SaProblems.announce
    SaProblems.pending_refusals = PackedStringArray()
    SaProblems.announce = false
    work.call()
    var said := SaProblems.pending_refusals
    SaProblems.pending_refusals = kept
    SaProblems.announce = announcing
    return said


## Merges *group* down onto the bottom layer and holds it to what the feature promises:
## one layer, the picture unmoved, one step that undoes to the three layers,
## and the pixels a Flatten of the same stack writes.
func _merges_as_a_flatten(group: SaLayer, what: String) -> void:
    var members := SaLayerStack.members(_doc, group)
    var held := _ops.layers()
    var before := _output()
    var steps := _doc.history.step_count()

    assert_true(_ops.can_merge_down(group), "%s: Merge Down is offered on the group" % what)
    assert_true(_ops.merge_down(group), "%s: and it merges" % what)
    assert_eq(_ops.layers(), [_bottom] as Array[SaLayer], "%s: one layer is left, the paint layer under the group" % what)
    assert_eq(_doc.active_layer, _bottom, "%s: which is active" % what)
    assert_eq(_doc.history.step_count(), steps + 1, "%s: as one step" % what)
    _same(before, _output(), "%s: all three drawn as they showed" % what)
    var merged := _paint()

    assert_true(_doc.undo(), "%s: Undo" % what)
    assert_eq(_ops.layers(), held, "%s: puts the three back in their places" % what)
    for member in members:
        assert_eq(SaLayerStack.parent_of(member), group, "%s: each member inside the group" % what)
    _same(before, _output(), "%s: with the picture they had" % what)

    assert_true(_ops.flatten(), "%s: a Flatten of the same stack runs" % what)
    _same(merged, _paint(), "%s: and writes the same pixels the merge did" % what)
    assert_true(_doc.undo(), "%s: and undoes" % what)
    assert_true(_doc.redo(), "%s: Redo of the flatten" % what)
    assert_true(_doc.undo(), "%s: and its undo again" % what)
    assert_eq(_ops.layers(), held, "%s: leave the stack as it was" % what)


func test_a_pass_through_group_merges_down_as_a_flatten_of_the_same_stack() -> void:
    _merges_as_a_flatten(_group(false), "A pass-through group")


func test_a_masked_filtered_isolated_group_merges_down_as_a_flatten_of_the_same_stack() -> void:
    _merges_as_a_flatten(_group(true), "A dressed group")


func test_a_redo_merges_the_group_again() -> void:
    var group := _group(false)
    var before := _output()
    assert_true(_ops.merge_down(group), "The group merges")
    var merged := _paint()
    assert_true(_doc.undo(), "Undo")
    assert_true(_doc.redo(), "Redo")
    assert_eq(_ops.layers(), [_bottom] as Array[SaLayer], "takes the group and its members out again")
    _same(merged, _paint(), "with the same paint in the layer under it")
    _same(before, _output(), "and the same picture")


## A group clipped to the paint layer under it shows only where that layer
## holds paint, and merges the way it showed.
func test_a_clipped_group_merges_the_way_it_showed() -> void:
    var group := _group(false)
    SaLayerStack.set_clip_to_below(_doc, group, true)
    var before := _output()
    assert_true(_ops.merge_down(group), "The clipped group merges")
    assert_eq(_ops.layers(), [_bottom] as Array[SaLayer], "into the layer it was clipped to")
    _same(before, _output(), "as it showed")


## A pick of the paint layer and the group over it merges the same way, and the
## group's members, picked with it, go with it rather than standing as uppers.
func test_a_picked_group_and_the_layer_under_it_merge_as_one() -> void:
    var group := _group(false)
    var picked: Array = [_bottom, group]
    picked.append_array(SaLayerStack.members(_doc, group))
    var before := _output()
    var steps := _doc.history.step_count()
    assert_true(_ops.can_merge_down(group, picked), "Merge Down is offered on the pick")
    assert_true(_ops.merge_down(group, picked), "and it merges")
    assert_eq(_ops.layers(), [_bottom] as Array[SaLayer], "into the lowest")
    assert_eq(_doc.history.step_count(), steps + 1, "as one step")
    _same(before, _output(), "as the rows showed")


func test_a_group_is_not_merged_onto_a_group() -> void:
    var lower := _ops.group_layers([_painted(FIRST)])
    _doc.set_active_layer(lower)
    var upper := _ops.group_layers([_painted(SECOND)])
    assert_null(SaLayerStack.parent_of(upper), "The upper group stands beside the lower one")
    assert_eq(SaGroupMerge.lower_of(_doc, upper), lower, "and the lower group is under it")
    var stack := _ops.layers()
    var parents: Array = []
    for layer in stack:
        parents.append(layer.group)
    var steps := _doc.history.step_count()

    assert_false(_ops.can_merge_down(upper), "Merge Down onto a group is dimmed")
    var said := _refusals_during(func() -> void: assert_false(_ops.merge_down(upper), "and refused"))
    assert_eq(said.size(), 1, "The corner says one thing")
    var expected := "'%s' is a group. A group merges down into the paint layer under it, but nothing merges onto a group."
    assert_true(said.size() == 1 and said[0].contains(expected % lower.name), "naming the lower group: %s" % [said])
    assert_eq(_ops.layers(), stack, "The stack is as it was")
    for i in stack.size():
        assert_eq(stack[i].group, parents[i], "with every layer in its group")
    assert_eq(_doc.history.step_count(), steps, "and no step went into the history")
