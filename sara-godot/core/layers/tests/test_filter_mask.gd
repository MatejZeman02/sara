## A filter's mask is painted and operated like a layer's.
##
## The record's mask is the own form, painted through `mask_target` and
## operated by the seven mask calls with the record as the owner, and the chain
## binds it where a point kernel reads its coverage. The fixture is an
## invert, whose kernel mixes towards the inverse by the coverage, so a texel of
## the composite says how much of the filter reached it: all of it where the
## mask is one, none where it is zero, and a part on the stroke's soft edge.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const PaintKernel = preload("res://tests/fixtures/paint_kernel.gd")

const PAINT := Color(0.25, 0.5, 0.75, 1.0)
const INVERTED := Color(0.75, 0.5, 0.25, 1.0)
## Black coverage, which keeps the filter off where it lands.
const HIDE := Color(0.0, 0.0, 0.0, 1.0)

## The stroke's centre and radius. The fixture's dab has a two pixel ramp at
## its rim, so one pixel inside the rim is half covered.
const AT := Vector2i(100, 100)
const RADIUS := 12.0
const EDGE := Vector2i(111, 100)
const OUTSIDE := Vector2i(140, 100)

var _easel: SaEasel = null
var _doc: SaDocument = null
var _background: SaLayer = null
var _record: SaAttachedFilter = null


func before_each() -> void:
    _easel = Bench.easel(Vector2i(512, 512))
    _doc = _easel.document
    _background = _doc.get_node("Background") as SaLayer
    _doc.fill_layer(PAINT, _background)
    _record = SaFilterOps.new(_doc).attach(_background, Bench.INVERT)
    Bench.composite(_easel)


func after_each() -> void:
    _easel.free()
    _easel = null
    _doc = null
    _background = null
    _record = null


func _ops() -> SaMaskOps:
    return SaMaskOps.new(_doc)


## How much of the invert reached *at*: zero is the paint, one the inverse.
func _filtered(at: Vector2i) -> float:
    Bench.composite(_easel)
    var found := Bench.texel(_easel.output, at)
    return (found.r - PAINT.r) / (INVERTED.r - PAINT.r)


## One stroke of one hard dab on whatever the document's mask target is, the
## way `test_mask_painting.gd` drives the paint context.
func _stroke(pos: Vector2, radius: float, color: Color) -> void:
    var compute := PaintKernel.compute()
    _doc.begin_stroke(1.0, SaLayer.BLEND_MODE.NORMAL)
    var region := Rect2(pos.x - radius, pos.y - radius, radius * 2.0, radius * 2.0)
    var paint := SaPaintContext.for_region(_doc, region, false)
    paint.dispatch_batch(
        compute,
        "paint",
        func(target: SaPaintContext.Target) -> void:
            compute.set_texture(0, target.texture.rid)
            compute.set_push_constant_float_array(
                PaintKernel.pack_params(paint.local_point(target, pos), target.render_offset, color, radius, 1.0, 1.0, 1.0)
            )
    )
    paint.commit_invalidation()
    _doc.commit_stroke()


func _assert_three(centre: float, edge: float, outside: float, what: String) -> void:
    assert_almost_eq(_filtered(AT), centre, 0.02, "%s: the stroke's centre" % what)
    var at_edge := _filtered(EDGE)
    if edge > 0.0 and edge < 1.0:
        assert_true(at_edge > 0.1 and at_edge < 0.9, "%s: the stroke's edge is between the two, %s" % [what, at_edge])
    else:
        assert_almost_eq(at_edge, edge, 0.02, "%s: the stroke's edge" % what)
    assert_almost_eq(_filtered(OUTSIDE), outside, 0.02, "%s: outside the stroke" % what)


func test_a_stroke_on_a_filters_mask_keeps_the_filter_off_under_it() -> void:
    assert_true(_ops().add(_record), "Add Mask runs on a filter's record")
    assert_true(_record.mask.is_own(), "and gives it a mask of its own chunks")
    _assert_three(1.0, 1.0, 1.0, "A new mask hides nothing")

    _doc.mask_target = _record.mask
    var steps := _doc.history.step_count()
    _stroke(Vector2(AT), RADIUS, HIDE)
    assert_eq(_doc.history.step_count(), steps + 1, "The stroke on the mask is one history step")
    _assert_three(0.0, 0.5, 1.0, "After the stroke")
    var stored := Bench.texel(_background.get_field(Vector2i.ZERO), AT)
    assert_almost_eq(stored.r, PAINT.r, 1e-5, "and the layer's own texel is untouched")

    assert_true(_doc.undo(), "The stroke undoes")
    _assert_three(1.0, 1.0, 1.0, "After the undo all three are back")
    assert_true(_doc.redo(), "and redoes")
    _assert_three(0.0, 0.5, 1.0, "After the redo")


func test_a_mask_switched_off_lets_the_filter_through_and_back() -> void:
    _ops().add(_record)
    _doc.mask_target = _record.mask
    _stroke(Vector2(AT), RADIUS, HIDE)
    var steps := _doc.history.step_count()
    assert_true(_ops().run(SaMaskOps.DISABLE, _record), "Disable Mask runs on a record")
    assert_eq(_doc.history.step_count(), steps + 1, "as one step")
    assert_false(_record.mask.enabled, "and switches the mask off")
    _assert_three(1.0, 1.0, 1.0, "A mask switched off hides nothing")
    _doc.undo()
    _assert_three(0.0, 0.5, 1.0, "and its undo hides again")


func test_invert_and_delete_are_one_step_each() -> void:
    _ops().add(_record)
    _doc.mask_target = _record.mask
    _stroke(Vector2(AT), RADIUS, HIDE)
    var steps := _doc.history.step_count()
    assert_true(_ops().invert(_record), "Invert Mask runs on a record")
    assert_eq(_doc.history.step_count(), steps + 1, "as one step")
    _assert_three(1.0, 0.5, 0.0, "Inverted, the filter works under the stroke alone")

    assert_true(_ops().remove(_record), "Delete Mask runs on a record")
    assert_eq(_doc.history.step_count(), steps + 2, "as one step")
    assert_null(_record.mask, "and takes the mask away")
    assert_null(_doc.mask_target, "and the brush off it")
    _assert_three(1.0, 1.0, 1.0, "With no mask the filter works everywhere")

    _doc.undo()
    assert_not_null(_record.mask, "The undo of the delete brings the mask back")
    _assert_three(1.0, 0.5, 0.0, "as it was")
    _doc.undo()
    _assert_three(0.0, 0.5, 1.0, "and the undo of the invert the stroke's")


func test_add_from_the_selection_and_mask_to_the_selection() -> void:
    _doc.selection.select_rect(Rect2i(0, 0, 64, 64))
    var steps := _doc.history.step_count()
    assert_true(_ops().add_from_selection(_record), "Add Mask from Selection runs on a record")
    assert_eq(_doc.history.step_count(), steps + 1, "as one step")
    assert_almost_eq(_filtered(Vector2i(10, 10)), 1.0, 0.02, "The filter works where the selection was")
    assert_almost_eq(_filtered(Vector2i(300, 300)), 0.0, 0.02, "and nowhere else")

    _doc.selection.deselect()
    assert_true(_ops().to_selection(_record), "Mask to Selection runs on a record")
    assert_eq(_doc.history.step_count(), steps + 2, "as one step")
    assert_true(_doc.selection.active, "and selects")
    assert_eq(_doc.selection.bounds, Rect2i(0, 0, 64, 64), "what the mask shows")

    _doc.undo()
    _doc.undo()
    assert_null(_record.mask, "Two undos leave the record with no mask")


func test_apply_is_not_offered_on_a_record() -> void:
    assert_true(SaMaskOps.can(SaMaskOps.ADD, _record), "A record with no mask can take one")
    assert_false(SaMaskOps.can(SaMaskOps.DELETE, _record), "and has none to delete")
    _ops().add(_record)
    for command_id: StringName in SaMaskOps.ALL:
        var expected := command_id not in [SaMaskOps.ADD, SaMaskOps.ADD_FROM_SELECTION, SaMaskOps.APPLY]
        assert_eq(SaMaskOps.can(command_id, _record), expected, "%s on a record with a mask" % command_id)
    assert_false(_ops().run(SaMaskOps.APPLY, _record), "A filter has no paint to apply a mask into")


func test_a_press_on_a_filter_rows_mask_aims_the_brush_at_it() -> void:
    _ops().add(_record)
    SaFilterRowView.aim_brush_at_filter(_doc, _record, &"mask")
    assert_true(_doc.mask_target == _record.mask, "The mask's picture makes it the mask target")
    SaFilterRowView.aim_brush_at_filter(_doc, _record, &"")
    assert_true(_doc.mask_target == _record.mask, "a press on the same row's name keeps it")
    var other := SaFilterOps.new(_doc).attach(_background, Bench.INVERT)
    SaFilterRowView.aim_brush_at_filter(_doc, other, &"")
    assert_null(_doc.mask_target, "and a press on another filter's row gives the brush back to the paint")
    SaFilterRowView.aim_brush_at_filter(_doc, other, &"mask")
    assert_null(_doc.mask_target, "A filter with no mask has no picture to aim at")


func test_the_docker_draws_the_mask_and_offers_the_seven_on_a_filter_row() -> void:
    var canvas := SaCanvas.new()
    canvas.easel = _easel
    var docker := LayersDocker.new()
    docker.target_canvas = canvas
    docker.sync_layer_list()
    var rows := docker.item_list
    var at := -1
    for i: int in rows.row_count():
        if rows.record_at(i) == _record:
            at = i
    assert_true(at >= 0, "The record has a row")
    assert_false(rows.row_report()[at]["has_mask"], "with no mask picture before it has a mask")

    rows.picked.pick_filter(_record)
    docker.actions.sync_from_active_layer()
    var titles := docker.actions.menu_titles()
    assert_eq(
        titles.size(),
        SaMaskOps.ALL.size() + 2,
        "A picked filter's menu is Delete Filter, Convert to Adjustment Layer, the mask's rows but Add and the colour range",
    )
    var add_btn := docker.actions.on_row(SaLayerActions.Item.MASK_ADD)
    assert_not_null(add_btn, "Add Mask stands on the row as a button")
    assert_false(add_btn.disabled, "live on a filter with no mask")
    assert_true(docker.actions.menu.is_disabled(SaMaskOps.DELETE), "Delete is dimmed with no mask")
    assert_true(docker.actions.press_item(SaLayerActions.Item.MASK_ADD), "a press on Add Mask takes")
    assert_not_null(_record.mask, "and gives the record its mask, not the layer")
    assert_null(_background.mask, "whose layer keeps none")

    rows.refresh_all()
    var report: Dictionary = rows.row_report()[at]
    assert_true(report["has_mask"], "The row now draws the mask's picture")
    assert_true(report["mask_enabled"], "switched on")
    docker.actions.sync_from_active_layer()
    assert_true(docker.actions.menu.is_disabled(SaMaskOps.APPLY), "Apply is dimmed on a filter")
    assert_false(docker.actions.menu.is_disabled(SaMaskOps.INVERT), "and Invert is live")

    SaFilterRowView.aim_brush_at_filter(_doc, _record, &"mask")
    assert_eq(rows.row_report()[at]["picked"], "mask", "The row says the brush paints its mask")

    rows.picked.pick_filter(null)
    docker.actions.sync_from_active_layer()
    assert_true(docker.actions.menu_titles().size() > SaMaskOps.ALL.size(), "A layer's row has the whole menu back")
    docker.free()
    canvas.free()
