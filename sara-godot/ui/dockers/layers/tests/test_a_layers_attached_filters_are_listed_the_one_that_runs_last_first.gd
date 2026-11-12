## A layer's attached filters are listed the way a stack reads, the one that
## runs last nearest the layer's row. The order the records ran in was right and the list showed it the
## other way up from the layers around it, so Levels and then Curves read as
## Levels on top.
##
## The drag is named row by row through `begin_drag`, `drag_over` and `drop`,
## as `test_filter_rows.gd` does, and what the order means for the picture is
## read off the composite and held against both orders applied by hand, one
## filter written into the pixels and the other attached over it. The running
## app's half is `scenarios/a-layer-s-attached-filters-are-listed-in-the-order-a-painter-reads-a.json`.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

const OWNER := &"sara-base-modules"
const LEVELS_VALUES := {
    "in_black": 0.3, "gamma": 1.6, "in_white": 0.85, "out_black": 0.05, "out_white": 0.95, "channel": "master"
}
const CURVES_VALUES := {"curves": {"master": [[0.0, 0.0], [0.375, 0.75], [1.0, 1.0]], "blue": [[0.0, 0.25], [1.0, 0.75]]}}
const PAINT := Color(0.55, 0.4, 0.3, 1.0)
const AT := Vector2i(40, 40)

var _easel: SaEasel = null
var _doc: SaDocument = null
var _layer: SaLayer = null
var _registry: SaFilterRegistry = null
var _levels: StringName = &""
var _curves: StringName = &""
var _canvas: SaCanvas = null
var _docker: LayersDocker = null


func before_each() -> void:
    _easel = _easel_over_paint()
    _doc = _easel.document
    _layer = _doc.get_node("Background") as SaLayer
    _registry = _easel.compositor.filter_chain.registry
    _levels = SaFilterRegistry.key_for(OWNER, SaLevelsFilter.new())
    _curves = SaFilterRegistry.key_for(OWNER, SaCurvesFilter.new())
    _canvas = SaCanvas.new()
    _canvas.easel = _easel
    _docker = LayersDocker.new()
    _docker.filter_registry = _registry
    _docker.target_canvas = _canvas


func after_each() -> void:
    _docker.free()
    _canvas.free()
    _easel.free()
    _docker = null
    _canvas = null
    _easel = null
    _doc = null
    _layer = null
    _registry = null


## An easel whose one layer is painted and whose registry answers to Levels and
## Curves. The hand-applied orders are read from a second one of these.
func _easel_over_paint() -> SaEasel:
    var made := Bench.easel(Vector2i(256, 256))
    var registry := made.compositor.filter_chain.registry
    registry.register(SaLevelsFilter.new(), OWNER)
    registry.register(SaCurvesFilter.new(), OWNER)
    made.document.fill_layer(PAINT, made.document.get_node("Background") as SaLayer)
    return made


## The records the docker lists under *node*, top to bottom, *node* null for the
## document's root.
func _listed_under(node: SaLayer) -> Array[SaAttachedFilter]:
    var found: Array[SaAttachedFilter] = []
    var rows: SaLayerList = _docker.item_list
    for i: int in rows.row_count():
        var view := rows.filter_at(i)
        if view != null and view.node == node:
            found.append(view.record)
    return found


## The row *record* is drawn on, or -1.
func _row_of(record: SaAttachedFilter) -> int:
    for i: int in _docker.item_list.row_count():
        if _docker.item_list.record_at(i) == record:
            return i
    return -1


## The composite's texel at AT after *first* and then *second* ran over the
## paint, worked out by hand in an easel of its own: *first* is written into the
## pixels by the one-shot, which the chain has no part in, and *second* is
## attached over them. A copy of the order, and not of the chain's loop.
func _by_hand(first: StringName, first_values: Dictionary, second: StringName, second_values: Dictionary) -> Color:
    var hand := _easel_over_paint()
    var layer := hand.document.get_node("Background") as SaLayer
    var ops := SaFilterOps.new(hand.document)
    assert_true(ops.apply_once(layer, first, first_values, "By hand"), "The first filter writes into the pixels by hand")
    ops.attach(layer, second, second_values)
    Bench.composite(hand)
    var read := Bench.texel(hand.output, AT)
    hand.free()
    return read


func _shown() -> Color:
    Bench.composite(_easel)
    return Bench.texel(_easel.output, AT)


func _is(found: Color, expected: Color, what: String) -> void:
    assert_almost_eq(found.r, expected.r, 0.01, "%s, red: %s against %s" % [what, found, expected])
    assert_almost_eq(found.g, expected.g, 0.01, "%s, green: %s against %s" % [what, found, expected])
    assert_almost_eq(found.b, expected.b, 0.01, "%s, blue: %s against %s" % [what, found, expected])


func test_levels_then_curves_lists_curves_above_levels() -> void:
    var levels := SaFilterOps.new(_doc).attach(_layer, _levels, LEVELS_VALUES)
    var curves := SaFilterOps.new(_doc).attach(_layer, _curves, CURVES_VALUES)
    _docker.sync_layer_list()
    assert_eq(_layer.filters, [levels, curves] as Array[SaAttachedFilter], "The layer runs them in the order they were attached")
    assert_eq(_listed_under(_layer), [curves, levels] as Array[SaAttachedFilter], "and the list shows Curves above Levels")
    var layer_row := -1
    for i: int in _docker.item_list.row_count():
        if _docker.item_list.layer_at(i) == _layer:
            layer_row = i
    assert_eq(_row_of(curves), layer_row + 1, "The one that runs last is nearest the layer's row")
    assert_eq(_row_of(levels), layer_row + 2, "and the first one is under it")


func test_dragging_levels_above_curves_makes_levels_run_last() -> void:
    var levels := SaFilterOps.new(_doc).attach(_layer, _levels, LEVELS_VALUES)
    var curves := SaFilterOps.new(_doc).attach(_layer, _curves, CURVES_VALUES)
    _docker.sync_layer_list()
    var before := _shown()
    var levels_last := _by_hand(_curves, CURVES_VALUES, _levels, LEVELS_VALUES)
    var curves_last := _by_hand(_levels, LEVELS_VALUES, _curves, CURVES_VALUES)
    assert_true(
        absf(levels_last.r - curves_last.r) + absf(levels_last.g - curves_last.g) + absf(levels_last.b - curves_last.b) > 0.03,
        "The two orders are two pictures, or the read proves nothing: %s and %s" % [levels_last, curves_last]
    )
    _is(before, curves_last, "Curves listed above Levels is Curves running last")

    var steps := _doc.history.step_count()
    var rows: SaLayerList = _docker.item_list
    rows.begin_drag(_row_of(levels))
    rows.drag_over(_row_of(curves), SaLayerList.Drop.ABOVE)
    assert_eq(rows.drop_row, _row_of(curves), "Curves' row takes the mark")
    rows.drop()
    assert_eq(_layer.filters, [curves, levels] as Array[SaAttachedFilter], "Levels runs last once it is dropped above Curves")
    assert_eq(_doc.history.step_count(), steps + 1, "as one step")
    assert_eq(_listed_under(_layer), [levels, curves] as Array[SaAttachedFilter], "and the list follows, Levels on top")
    _is(_shown(), levels_last, "The composite is Curves applied first and Levels over it")

    assert_true(_doc.undo(), "Undo of the drag")
    assert_eq(_layer.filters, [levels, curves] as Array[SaAttachedFilter], "restores the order the records run in")
    assert_eq(_listed_under(_layer), [curves, levels] as Array[SaAttachedFilter], "and the list")
    _is(_shown(), curves_last, "and the picture")
    assert_true(_doc.redo(), "Redo")
    assert_eq(_layer.filters, [curves, levels] as Array[SaAttachedFilter], "takes it again")


func test_a_drop_below_a_row_runs_the_record_before_it() -> void:
    var ops := SaFilterOps.new(_doc)
    var first := ops.attach(_layer, _levels, LEVELS_VALUES)
    var second := ops.attach(_layer, _curves, CURVES_VALUES)
    var third := ops.attach(_layer, _levels, LEVELS_VALUES)
    _docker.sync_layer_list()
    assert_eq(_listed_under(_layer), [third, second, first] as Array[SaAttachedFilter], "Three records are listed newest first")
    var rows: SaLayerList = _docker.item_list
    rows.begin_drag(_row_of(third))
    rows.drag_over(_row_of(second), SaLayerList.Drop.BELOW)
    rows.drop()
    assert_eq(_layer.filters, [first, third, second] as Array[SaAttachedFilter], "Below the middle row is before it in the array")
    rows.begin_drag(_row_of(first))
    rows.drag_over(_row_of(second), SaLayerList.Drop.ABOVE)
    rows.drop()
    assert_eq(_layer.filters, [third, second, first] as Array[SaAttachedFilter], "Above the top row is last in the array")


func test_the_delete_and_the_pick_follow_the_record_and_not_its_place() -> void:
    var ops := SaFilterOps.new(_doc)
    var levels := ops.attach(_layer, _levels, LEVELS_VALUES)
    var curves := ops.attach(_layer, _curves, CURVES_VALUES)
    _docker.sync_layer_list()
    _docker.item_list.picked.pick_filter(levels)
    assert_true(_docker.actions.delete_filter(), "Delete Filter takes the picked record off")
    assert_eq(_layer.filters, [curves] as Array[SaAttachedFilter], "and it was Levels, the row at the bottom, that went")
    _docker.sync_layer_list()
    _docker.item_list.picked.pick_filter(curves)
    ops.attach(_layer, _levels, LEVELS_VALUES)
    _docker.sync_layer_list()
    assert_eq(_docker.item_list.picked.selected_record, curves, "A refresh keeps the pick on its record, which moved a row down")
    assert_eq(_docker.item_list.record_at(_row_of(curves)), curves, "and its row is the one that holds it")


func test_the_roots_filters_read_the_same_way() -> void:
    var ops := SaFilterOps.new(_doc)
    var levels := ops.attach(null, _levels, LEVELS_VALUES)
    var curves := ops.attach(null, _curves, CURVES_VALUES)
    _docker.sync_layer_list()
    assert_eq(_listed_under(null), [curves, levels] as Array[SaAttachedFilter], "The root lists the one that runs last first")
    assert_eq(_row_of(curves), 0, "at the very top, over every layer")
    var rows: SaLayerList = _docker.item_list
    rows.begin_drag(_row_of(levels))
    rows.drag_over(_row_of(curves), SaLayerList.Drop.ABOVE)
    rows.drop()
    var swapped: Array[SaAttachedFilter] = [curves, levels]
    assert_eq(_doc.root_filters, swapped, "Levels dropped above Curves runs last on the root too")
    assert_eq(_listed_under(null), [levels, curves] as Array[SaAttachedFilter], "and heads the list")
    assert_true(_doc.undo(), "Undo")
    assert_eq(_doc.root_filters, [levels, curves] as Array[SaAttachedFilter], "restores the root's order")
