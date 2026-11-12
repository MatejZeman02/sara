## The layers docker lists a node's attached filters under it, reorders them by
## a drag, toggles them, and refuses a drop that would make a filter a member
## of the layer order.
##
## The gesture is driven the way `test_layer_drag.gd` drives a layer's: the
## drag is named row by row through `begin_drag`, `drag_over` and `drop`,
## because a row never laid out by a live viewport has no rect to hit. The real
## mouse over a real layout is the scenario's half,
## `scenarios/the-layers-docker-lists-a-nodes-filters-under-it.json`.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

const BRIGHTNESS := &"base.brightness_contrast"
const BLUR := &"sara-base-modules.box_blur"
const LEVELS := &"base.levels"

var _easel: SaEasel
var _doc: SaDocument
var _canvas: SaCanvas
var _docker: LayersDocker
var _rows: SaLayerList


## The default document's two layers and a third on top carrying three
## records, and the docker over them. Row 0 is the top layer, rows 1 to 3 its
## filters with the one that runs last nearest the layer, and row 4 the layer
## under it.
func before_each() -> void:
    _easel = SaEasel.create_default(Vector2i(128, 128))
    _easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    _doc = _easel.document
    _doc.active_layer.name = "Bottom"
    SaLayerOps.new(_doc).add().name = "Top"
    var ops := SaFilterOps.new(_doc)
    ops.attach(_top(), BRIGHTNESS, {"brightness": 0.2})
    ops.attach(_top(), BLUR, {"radius": 3.0})
    ops.attach(_top(), LEVELS)
    _canvas = SaCanvas.new()
    _canvas.easel = _easel
    _docker = LayersDocker.new()
    _docker.target_canvas = _canvas
    _rows = _docker.item_list
    _docker.sync_layer_list()


func after_each() -> void:
    _docker.free()
    _canvas.free()
    _easel.free()


func _top() -> SaLayer:
    for child in _doc.get_children():
        if str(child.name) == "Top":
            return child as SaLayer
    return null


func _keys(records: Array[SaAttachedFilter]) -> Array:
    var keys: Array = []
    for record in records:
        keys.append(record.key)
    return keys


func test_the_rows_name_the_filters_in_order_under_their_node() -> void:
    _docker.free()
    SaFilterOps.new(_doc).attach(null, LEVELS)
    _docker = LayersDocker.new()
    _docker.target_canvas = _canvas
    _rows = _docker.item_list
    _docker.sync_layer_list()

    var report := _rows.row_report()
    assert_eq(report.size(), 7, "Three layers, three filters and the root's one are seven rows")
    assert_eq(report[0]["kind"], "filter", "The root's filter sits above every layer")
    assert_eq(report[0]["node"], "", "and names no node")
    assert_eq(report[1]["name"], "Top", "then the node")
    var listed: Array = []
    for i in range(2, 5):
        assert_eq(report[i]["kind"], "filter", "then its filters")
        assert_eq(report[i]["node"], "Top", "each under its node")
        listed.append(StringName(String(report[i]["filter"])))
    assert_eq(listed, [LEVELS, BLUR, BRIGHTNESS], "the one that runs last nearest the node, as a stack reads")
    assert_eq(_rows.layer_at(5), _doc.get_child(_top().get_index() - 1), "and the next layer after them")
    assert_false(report[5].has("kind"), "A layer's row says nothing about a filter")


func test_a_filter_row_carries_no_layer() -> void:
    assert_null(_rows.layer_at(1), "layer_at answers null for a filter's row")
    assert_eq(_rows.record_at(1), _top().filters[2], "and record_at answers the record, the one that runs last")
    assert_null(_rows.record_at(0), "which a layer's row has none of")
    _rows.picked.select(0)
    _rows.picked.select_to(4)
    assert_eq(_rows.picked.selected_indices(), [0, 4] as Array[int], "A Shift run across the filters leaves them out of the set")
    _rows.picked.select(2)
    assert_eq(_rows.picked.selected_idx, 0, "and a plain select of a filter's row moves nothing")
    assert_false(_rows.begin_rename(2), "A filter's row has no name to edit")


func test_the_third_dragged_onto_the_first_reorders_in_one_step() -> void:
    var top := _top()
    var steps := _doc.undo_redo.get_history_count()
    _rows.begin_drag(3)
    _rows.drag_over(1, SaLayerList.Drop.ABOVE)
    assert_eq(_rows.drop_row, 1, "A filter of the same node takes the mark")
    _rows.drop()
    assert_eq(_keys(top.filters), [BLUR, LEVELS, BRIGHTNESS], "Above the top row is after it in the order they run")
    assert_eq(_doc.undo_redo.get_history_count(), steps + 1, "as one step on the history")
    assert_eq(_rows.record_at(1), top.filters[2], "and the rows followed the document")

    _rows.begin_drag(1)
    _rows.drag_over(2, SaLayerList.Drop.BELOW)
    _rows.drop()
    assert_eq(_keys(top.filters), [BLUR, BRIGHTNESS, LEVELS], "Below a row further down lands just under it, so runs before it")
    _doc.undo()
    _doc.undo()
    assert_eq(_keys(top.filters), [BRIGHTNESS, BLUR, LEVELS], "and undo puts both back")
    assert_eq(_rows.record_at(3), top.filters[0], "with the rows following again")


func test_the_eye_toggles_the_record_as_a_step() -> void:
    var record := _top().filters[1]
    var steps := _doc.undo_redo.get_history_count()
    _rows._on_filter_eye_pressed(2)
    assert_false(record.enabled, "The eye of a filter's row switches the record off")
    assert_eq(_doc.undo_redo.get_history_count(), steps + 1, "as one step")
    assert_false(_rows.row_report()[2]["enabled"], "and the row says so")
    assert_eq(_rows.row_count(), 6, "A disabled record keeps its row")
    _doc.undo()
    assert_true(record.enabled, "Undo switches it back on")


func test_a_drop_between_two_layer_rows_moves_nothing() -> void:
    var top := _top()
    var steps := _doc.undo_redo.get_history_count()
    var children := _doc.get_children()
    _rows.begin_drag(2)
    # The edge of a layer's row is between two layers, which no filter may be.
    _rows.drag_over(4, SaLayerList.Drop.ABOVE)
    assert_eq(_rows.drop_row, -1, "Between the two layer rows the mark does not appear")
    _rows.drag_over(0, SaLayerList.Drop.INTO)
    assert_eq(_rows.drop_row, -1, "and its own node's row has nowhere new to put it")
    _rows.drag_over(4, SaLayerList.Drop.BELOW)
    _rows.drop()
    assert_eq(_keys(top.filters), [BRIGHTNESS, BLUR, LEVELS], "Nothing moved")
    assert_eq(_doc.get_children(), children, "in the layer order either")
    assert_eq(_doc.undo_redo.get_history_count(), steps, "and the history has no step")

    _rows.begin_drag(0)
    _rows.drag_over(2, SaLayerList.Drop.ABOVE)
    assert_eq(_rows.drop_row, -1, "A layer dragged over a filter's row finds no mark")
    _rows.drop()
    assert_eq(_doc.get_children(), children, "and lands nowhere")


func test_a_drop_on_another_nodes_row_moves_the_filter_there_in_one_step() -> void:
    var top := _top()
    var bottom := _rows.layer_at(4)
    var record := top.filters[1]
    var steps := _doc.undo_redo.get_history_count()
    _rows.begin_drag(2)
    _rows.drag_over(4, SaLayerList.Drop.INTO)
    assert_eq(_rows.drop_row, 4, "The middle of another node's row takes the filter")
    _rows.drop()
    assert_eq(_keys(top.filters), [BRIGHTNESS, LEVELS], "The record left its node")
    assert_eq(bottom.filters, [record] as Array[SaAttachedFilter], "and hangs on the other, the same record")
    assert_eq(_doc.undo_redo.get_history_count(), steps + 1, "One detach and one attach are one step")
    assert_eq(_rows.record_at(4), record, "and its row is under the other node now")
    _doc.undo()
    assert_eq(_keys(top.filters), [BRIGHTNESS, BLUR, LEVELS], "Undo carries it back to where it was")
    assert_true(bottom.filters.is_empty(), "and off the other")


func test_a_folded_group_hides_its_filters() -> void:
    var group := SaLayerOps.new(_doc).group_active()
    SaFilterOps.new(_doc).attach(group, BLUR)
    _docker.sync_layer_list()
    var at := -1
    for i in _rows.row_count():
        if _rows.layer_at(i) == group:
            at = i
    assert_eq(_rows.record_at(at + 1), group.filters[0], "An open group lists its filter under its own row")
    _docker._on_group_toggled(at)
    assert_eq(_rows.layer_at(at), group, "A folded group keeps its own row")
    var still_listed := false
    for i in _rows.row_count():
        still_listed = still_listed or _rows.record_at(i) == group.filters[0]
    assert_false(still_listed, "and skips its filter, the way it skips a member")
