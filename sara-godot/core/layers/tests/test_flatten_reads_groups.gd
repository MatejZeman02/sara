## A flatten draws a group the way the compositor does, an ungroup writes the
## group's filters, mask, opacity and mode into its members, and a merge down
## onto a masked layer applies that mask first.
##
## Before it, `flatten` composited every layer's chunks into the bottom one
## with that layer's own mode and opacity, so a group's members went in as if
## they stood at the top level and the group's opacity, isolation, mask and
## filters were dropped. `ungroup` took the group out and left its members, so
## the group's records vanished unapplied. And `merge_down` composited into a
## lower layer that kept its mask, so the merged paint was hidden wherever that
## mask was zero. Each case reads the easel's output before and after, through
## an undo and a redo: the step is right when no texel moved.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

const REQUIRES_GPU := true

const GROUND := Color(0.1, 0.3, 0.7, 1.0)
const FIRST := Color(0.8, 0.2, 0.1, 1.0)
const SECOND := Color(0.2, 0.9, 0.4, 0.6)
## Shown by the group's mask, hidden by it, and in the chunk it holds nothing
## at, which reads as shown.
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


## One over the left half of the first chunk and zero over the right half.
func _write_half(coverage: SaTexture) -> void:
    var values := PackedFloat32Array()
    values.resize(coverage.size.x * coverage.size.y)
    for y in coverage.size.y:
        for x in coverage.size.x:
            values[y * coverage.size.x + x] = 1.0 if x < 128 else 0.0
    GlobalShaderCompiler.get_rd().texture_update(coverage.rid, 0, values.to_byte_array())


## An isolated group at half opacity over *members*, with an invert attached
## and a mask hiding the right half of the first chunk.
func _dressed_group(members: Array) -> SaLayer:
    var group := _ops.group_layers(members)
    _ops.set_isolated(group, true)
    _ops.set_opacity(group, 0.5)
    SaFilterOps.new(_doc).attach(group, Bench.INVERT, {"strength": 1.0})
    assert_true(SaMaskOps.new(_doc).add(group), "The group takes a mask")
    _write_half(group.mask.get_or_create(Vector2i(0, 0)))
    SaLayerStack.invalidate_layer_chunks(_doc, group)
    _doc.update_caches()
    return group


func _output() -> Array:
    Bench.composite(_easel)
    var found: Array = []
    for at in POINTS:
        found.append(Bench.texel(_easel.output, at))
    return found


func _same(before: Array, after: Array, what: String) -> void:
    for i in before.size():
        var was: Color = before[i]
        var now: Color = after[i]
        var moved := maxf(maxf(absf(was.r - now.r), absf(was.g - now.g)), maxf(absf(was.b - now.b), absf(was.a - now.a)))
        assert_true(moved < 0.01, "%s, point %d: %s became %s" % [what, i, was, now])


func _differs(before: Array, after: Array) -> bool:
    for i in before.size():
        var was: Color = before[i]
        var now: Color = after[i]
        if maxf(maxf(absf(was.r - now.r), absf(was.g - now.g)), absf(was.b - now.b)) > 0.05:
            return true
    return false


func test_a_flatten_draws_a_masked_filtered_isolated_group() -> void:
    var first := _painted(FIRST)
    var second := _painted(SECOND)
    _ops.set_blend_mode(second, &"multiply")
    var group := _dressed_group([first, second])
    var held := _ops.layers().size()
    var before := _output()
    var flat := [GROUND, GROUND, GROUND]
    assert_true(_differs(before, flat), "The group shows over the ground before the flatten")

    assert_true(_ops.flatten(), "The flatten runs")
    assert_eq(_ops.layers(), [_bottom] as Array[SaLayer], "One layer is left, the bottom one")
    _same(before, _output(), "No texel moved")

    assert_true(_doc.undo(), "One step")
    assert_eq(_ops.layers().size(), held, "whose undo brings the group and its members back")
    assert_eq(group.filters.size(), 1, "the group with its filter")
    assert_not_null(group.mask, "and its mask")
    assert_eq(SaLayerStack.parent_of(second), group, "and its members inside it")
    _same(before, _output(), "with the picture it had")
    assert_true(_doc.redo(), "Redo")
    _same(before, _output(), "flattens to the same picture again")


func test_a_flatten_multiplies_a_pass_through_groups_opacity_into_its_members() -> void:
    var first := _painted(FIRST)
    var second := _painted(SECOND)
    var group := _ops.group_layers([first, second])
    _ops.set_opacity(group, 0.5)
    _ops.set_blend_mode(_bottom, &"multiply")
    _ops.set_opacity(_bottom, 0.75)
    var before := _output()

    assert_true(_ops.flatten(), "The flatten runs")
    assert_eq(_bottom.opacity, 1.0, "The bottom layer shows its paint whole")
    assert_eq(_bottom.blend_mode, SaLayer.BLEND_MODE.NORMAL, "and plainly")
    _same(before, _output(), "No texel moved")
    assert_true(_doc.undo(), "Undo")
    assert_eq(_bottom.opacity, 0.75, "gives the bottom layer its opacity back")
    assert_eq(_bottom.blend_mode, &"multiply", "and its mode")
    assert_false(SaLayerStack.isolates(group), "and the group stays pass-through")
    _same(before, _output(), "with the picture it had")


func test_an_ungroup_writes_the_groups_filter_mask_opacity_and_mode_into_its_member() -> void:
    _painted(FIRST)
    var member := _painted(SECOND)
    _ops.set_blend_mode(member, &"multiply")
    var group := _dressed_group([member])
    var before := _output()
    var steps := _doc.history.step_count()

    assert_true(_ops.ungroup(group), "The ungroup runs")
    assert_null(group.get_parent(), "The group leaves")
    assert_null(SaLayerStack.parent_of(member), "and its member stands at the top level")
    assert_almost_eq(member.opacity, 0.5, 1e-6, "carrying the group's opacity")
    assert_eq(member.blend_mode, SaLayer.BLEND_MODE.NORMAL, "and its mode, the one its own never read inside it")
    assert_eq(_doc.history.step_count(), steps + 1, "as one step")
    _same(before, _output(), "No texel moved")

    assert_true(_doc.undo(), "Undo")
    assert_eq(SaLayerStack.parent_of(member), group, "puts the member back in the group")
    assert_almost_eq(member.opacity, 1.0, 1e-6, "at its own opacity")
    assert_eq(member.blend_mode, &"multiply", "and its own mode")
    assert_eq(group.filters.size(), 1, "and the group keeps its filter")
    _same(before, _output(), "with the picture it had")
    assert_true(_doc.redo(), "Redo")
    _same(before, _output(), "ungroups to the same picture again")


func test_a_merge_down_applies_the_lower_layers_mask_first() -> void:
    var lower := _painted(FIRST)
    assert_true(SaMaskOps.new(_doc).add(lower), "The lower layer takes a mask")
    _write_half(lower.mask.get_or_create(Vector2i(0, 0)))
    SaLayerStack.invalidate_layer_chunks(_doc, lower)
    var upper := _painted(SECOND)
    var before := _output()
    assert_almost_eq((before[1] as Color).b, SECOND.b * SECOND.a + GROUND.b * (1.0 - SECOND.a), 0.02, "hidden under the mask")

    assert_true(_ops.merge_down(upper), "The merge runs")
    assert_null(lower.mask, "The mask is applied and taken off")
    _same(before, _output(), "No texel moved, the merged paint showing where the mask was zero")

    assert_true(_doc.undo(), "Undo")
    assert_not_null(lower.mask, "gives the lower layer its mask back")
    assert_eq(upper.get_parent(), _doc, "and the upper layer")
    assert_almost_eq(Bench.texel(lower.mask.texture_for(Vector2i(0, 0)), HIDDEN).r, 0.0, 0.001, "with its zero")
    _same(before, _output(), "with the picture it had")
    assert_true(_doc.redo(), "Redo")
    assert_null(lower.mask, "takes the mask off again")
    _same(before, _output(), "and merges to the same picture")
