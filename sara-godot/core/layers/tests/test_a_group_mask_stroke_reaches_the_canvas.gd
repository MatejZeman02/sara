## A stroke on a group's mask reaches the canvas.
##
## A group that is not the scope of the active layer is folded into a cache of
## its own, and that cache into the cache below the active layer, so what the
## canvas shows of the group is baked when the fold runs. A stroke on the
## group's mask wrote the mask, invalidated the chunks and redrew them from the
## caches, which still held the group as it was before the stroke, and the band
## appeared only when something else rebuilt the fold. The same held for the
## undo of that stroke, and for a filter's mask when the filter hangs on a folded
## group.
##
## Every case composites without `update_caches` after the stroke, because a
## rebuild in the suite is exactly what hid the fault.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const PaintKernel = preload("res://tests/fixtures/paint_kernel.gd")

const GREY := Color(0.5, 0.5, 0.5, 1.0)
const RED := Color(1.0, 0.0, 0.0, 1.0)
## Red through the fixture invert.
const CYAN := Color(0.0, 1.0, 1.0, 1.0)
## Black coverage, which hides what the mask's owner shows where it lands.
const HIDE := Color(0.0, 0.0, 0.0, 1.0)

const AT := Vector2i(100, 100)
const RADIUS := 12.0
## A texel the stroke never reaches.
const OUTSIDE := Vector2i(160, 100)

var _easel: SaEasel = null
var _doc: SaDocument = null
var _group: SaLayer = null
var _member: SaLayer = null


## Grey paint below, a red layer in a group over it, and the group active, so
## the group folds into the cache below the live tier: what a painter has under
## them when they press the group's mask picture in the Layers docker.
func before_each() -> void:
    _easel = Bench.easel(Vector2i(256, 256))
    _doc = _easel.document
    _doc.fill_layer(GREY, _doc.active_layer)
    var ops := SaLayerOps.new(_doc)
    _member = ops.add()
    _doc.fill_layer(RED, _member)
    _group = ops.group_active()
    _doc.set_active_layer(_group)


func after_each() -> void:
    _easel.free()
    _easel = null
    _doc = null
    _group = null
    _member = null


## The composite as the canvas makes it after a stroke: the dirty chunks drawn
## again from whatever the fold holds, with no rebuild asked for by the suite.
func _shown(at: Vector2i) -> Color:
    _easel.request_full_composite()
    _easel.process_pending_composite()
    return Bench.texel(_easel.output, at)


func _assert_colour(actual: Color, expected: Color, what: String) -> void:
    assert_almost_eq(actual.r, expected.r, 0.02, what + ", red")
    assert_almost_eq(actual.g, expected.g, 0.02, what + ", green")
    assert_almost_eq(actual.b, expected.b, 0.02, what + ", blue")


## One hard dab on the document's mask target, the way `test_filter_mask.gd`
## drives the paint context, committed as the brush commits it.
func _stroke(color: Color) -> void:
    var compute := PaintKernel.compute()
    var pos := Vector2(AT)
    _doc.begin_stroke(1.0, SaLayer.BLEND_MODE.NORMAL)
    var region := Rect2(pos.x - RADIUS, pos.y - RADIUS, RADIUS * 2.0, RADIUS * 2.0)
    var paint := SaPaintContext.for_region(_doc, region, false)
    paint.dispatch_batch(
        compute,
        "paint",
        func(target: SaPaintContext.Target) -> void:
            compute.set_texture(0, target.texture.rid)
            compute.set_push_constant_float_array(
                PaintKernel.pack_params(paint.local_point(target, pos), target.render_offset, color, RADIUS, 1.0, 1.0, 1.0)
            )
    )
    paint.commit_invalidation()
    _doc.commit_stroke()


## The note's case: the band shows the moment the stroke ends, with nothing
## between the stroke and the composite.
func test_a_stroke_on_a_folded_groups_mask_moves_the_canvas() -> void:
    _doc.mask_target = _group.add_mask()
    Bench.composite(_easel)
    _assert_colour(_shown(AT), RED, "The group shows whole before the stroke")

    _stroke(HIDE)

    _assert_colour(_shown(AT), GREY, "The stroke hid the group where it crossed, and the canvas says so")
    _assert_colour(_shown(OUTSIDE), RED, "and nowhere else")


## The stroke is one history step, and stepping over it moves the canvas both
## ways, because the undo writes the same mask the stroke did.
func test_the_undo_and_redo_of_the_stroke_move_the_canvas() -> void:
    _doc.mask_target = _group.add_mask()
    Bench.composite(_easel)
    _stroke(HIDE)
    _assert_colour(_shown(AT), GREY, "The stroke hid the group")

    assert_true(_doc.undo(), "The stroke is a step to undo")
    _assert_colour(_shown(AT), RED, "The undo gave the group back on the canvas")

    assert_true(_doc.redo(), "and one to redo")
    _assert_colour(_shown(AT), GREY, "The redo hid it again")


## A filter's mask on a folded group is the same store in the same place, and
## the row's ask names it: a record has no cache of its own, its group does.
func test_a_stroke_on_a_filters_mask_on_a_folded_group_moves_the_canvas() -> void:
    var record := SaFilterOps.new(_doc).attach(_group, Bench.INVERT)
    assert_true(SaMaskOps.new(_doc).add(record), "The record takes a mask")
    _doc.mask_target = record.mask
    Bench.composite(_easel)
    _assert_colour(_shown(AT), CYAN, "The group is inverted before the stroke")

    _stroke(HIDE)

    _assert_colour(_shown(AT), RED, "The stroke kept the filter off where it crossed, and the canvas says so")
    _assert_colour(_shown(OUTSIDE), CYAN, "and the filter stays on everywhere else")


## A layer's own mask, the field form, is the control: its layer is the live
## tier and never folded, and it moved the canvas before this row too.
func test_a_stroke_on_the_active_layers_mask_still_moves_the_canvas() -> void:
    _doc.set_active_layer(_member)
    _doc.mask_target = _member.add_mask()
    Bench.composite(_easel)
    _assert_colour(_shown(AT), RED, "The layer shows whole before the stroke")

    _stroke(HIDE)

    _assert_colour(_shown(AT), GREY, "The stroke on the layer's mask hid it")
