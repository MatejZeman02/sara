## The Layers docker's sync after a step that changes a few
## rows stays short on a large test document's 593 rows.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A layer added, a filter attached, a layer made active and a group's eye each
## drew every one of a large test document's rows again, about 48 ms a step. The rows
## now redraw what moved and keep the rest, the rows out of view owe their
## drawing until they come into view, and an activation moves the pick alone.
## What the painter sees has to be what the whole sync drew,
## so a stack of 593 rows plays each of the four steps on a list in the tree,
## laid out with a view, and reads its rows, their order, the picks, the active
## row and the folds, and every row's report, against a list outside the tree
## that a whole `sync()` draws after the same step.
##
## Every step is called straight, because a suite that awaits drops every
## assertion after the await.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const MirrorFilter = preload("res://modules/sara-base-modules/base/usual/mirror_filter.gd")

const MIRROR: StringName = &"sara-base-modules.mirror"
const ROWS := 593
const GROUP_EVERY := 25

## The picture's rim in a row's report, which a list in the tree draws and one
## outside it never does. Every key that ends in `rect` is a place, left out too.
const RIM := "thumb_rim"

var _easel: SaEasel
var _doc: SaDocument
var _canvas: SaCanvas
var _host: Control
var _stepped_list: SaLayerList
var _stepped: SaLayerListKeeper
var _whole_list: SaLayerList
var _whole: SaLayerListKeeper
var _folded: SaLayer


func before_each() -> void:
    _easel = Bench.easel(Vector2i(64, 64))
    _easel.compositor.filter_chain.registry.register(MirrorFilter.new(), &"sara-base-modules")
    _doc = _easel.document
    _stack()
    _canvas = SaCanvas.new()
    _canvas.easel = _easel
    # Parented to an autoload, because the runner calls this from its own
    # `_ready` and a parent mid-`_ready` rejects `add_child`.
    _host = Control.new()
    _host.name = "SyncHost"
    EventBus.add_child(_host)
    _doc.set_active_layer(_doc.get_node("L300") as SaLayer)
    _stepped_list = SaLayerList.new()
    _host.add_child(_stepped_list)
    _stepped = _keeper(_stepped_list)
    var parts := 0
    while _stepped._build.owing and parts < 400:
        _stepped.next_part()
        parts += 1
    _lay_out()
    _whole_list = SaLayerList.new()
    _whole = _keeper(_whole_list)
    for list: SaLayerList in [_stepped_list, _whole_list]:
        list.select_layers(_picked_set(), _doc.active_layer)


func after_each() -> void:
    _stepped = null
    _whole = null
    for list: SaLayerList in [_stepped_list, _whole_list]:
        if list != null:
            if list.get_parent() != null:
                list.get_parent().remove_child(list)
            list.free()
    _stepped_list = null
    _whole_list = null
    _host.free()
    _canvas.free()
    _easel.free()


## Groups of [constant GROUP_EVERY] layers, one group shut with a group's
## worth inside, and loose layers on top until the rows a sync draws are
## [constant ROWS], a large test document's count. Put in as a file's load puts them,
## members below their group.
func _stack() -> void:
    var made := 1
    for g in 20:
        var group := _layer("G%d" % g, true, null)
        for i in GROUP_EVERY:
            _doc.add_child(_layer("L%d" % made, false, group))
            made += 1
        _doc.add_child(group)
    _folded = _layer("Shut", true, null)
    for i in GROUP_EVERY:
        _doc.add_child(_layer("In%d" % i, false, _folded))
    _folded.folded = true
    _doc.add_child(_folded)
    var top := 0
    while _shown() < ROWS and top < ROWS:
        _doc.add_child(_layer("Top%d" % top, false, null))
        top += 1
    assert_eq(_shown(), ROWS, "The stack shows its rows")


func _layer(layer_name: String, is_group: bool, group: SaLayer) -> SaLayer:
    var layer := SaLayer.new()
    layer.name = layer_name
    layer.is_group = is_group
    layer.group = group
    layer.schema = SaFieldSpec.schema_for_space(_doc.color_space)
    return layer


## The layers whose rows a sync draws: every one but those in the shut group.
func _shown() -> int:
    var count := 0
    for child in _doc.get_children():
        var layer := child as SaLayer
        if layer == null or layer == _doc.stroke_layer:
            continue
        if layer == _folded or not SaLayerStack.is_inside(layer, _folded):
            count += 1
    return count


func _keeper(list: SaLayerList) -> SaLayerListKeeper:
    var keeper := SaLayerListKeeper.new(list, _canvas)
    keeper.filter_registry = _easel.compositor.filter_chain.registry
    keeper.listen()
    return keeper


## Lays the list in the tree out as a frame would, a docker's height of view
## over the rows, so the rows below the view are the ones a refresh owes.
func _lay_out() -> void:
    _stepped_list.size = Vector2(300.0, 350.0)
    _stepped_list.notification(Container.NOTIFICATION_SORT_CHILDREN)
    _stepped_list.vbox.notification(Container.NOTIFICATION_SORT_CHILDREN)


func _picked_set() -> Array[SaLayer]:
    var out: Array[SaLayer] = []
    for layer_name: String in ["L3", "L300", "Top1"]:
        out.append(_doc.get_node(layer_name) as SaLayer)
    return out


## What the painter sees in a list: each row's layer or record, indent and
## fold mark, the picked rows, the active row and the picked filter.
static func _seen(list: SaLayerList) -> Dictionary:
    var rows: Array = []
    for i in list.row_count():
        var row: SaRowFrame = list.rows[i]
        rows.append([list.layer_at(i), list.record_at(i), row.indent_depth, row.collapsed])
    return {
        "rows": rows,
        "picked": list.picked.selected_indices(),
        "active": list.picked.selected_idx,
        "record": list.picked.selected_record,
    }


## Every row's report with the places left out, after the rows a refresh owed
## are drawn, which is what the list answers a reader.
static func _drawn(list: SaLayerList) -> Array:
    var out: Array = []
    for report: Dictionary in list.row_report():
        report.erase(RIM)
        out.append(_unplaced(report))
    return out


## *report* with every place in it left out, the nested ones too.
static func _unplaced(report: Dictionary) -> Dictionary:
    var out := {}
    for key: String in report:
        if key.ends_with("rect"):
            continue
        var value: Variant = report[key]
        out[key] = _unplaced(value) if value is Dictionary else value
    return out


## Plays *step* on the document, lays the list in the tree out again, and
## reads it against a whole sync of the list outside the tree.
func _check(what: String, step: Callable, owes: bool = true) -> void:
    step.call()
    _stepped._flush_stale()
    _lay_out()
    assert_true(_stepped.rows_match_document(), "%s: the rows in the tree are the document's" % what)
    var owed := _stepped_list.rows.filter(func(row: SaRowFrame) -> bool: return _stepped_list._refreshes.owes(row))
    var seen := _seen(_stepped_list)
    var drawn := _drawn(_stepped_list)
    _whole.sync()
    assert_eq(_whole_list.row_count(), _stepped_list.row_count(), "%s: as many rows as a whole sync draws" % what)
    assert_eq(seen, _seen(_whole_list), "%s: the rows, their order, picks, active row and folds are a whole sync's" % what)
    assert_eq(drawn, _drawn(_whole_list), "%s: every row draws what a whole sync's row draws" % what)
    if owes:
        assert_true(owed.size() > 0, "%s: rows out of view waited for the view, %d of them" % [what, owed.size()])


func test_the_stack_draws_the_nights_files_rows_laid_out_with_a_view() -> void:
    assert_eq(_stepped_list.row_count(), ROWS, "The stack draws a large test document's rows")
    var last := _stepped_list.rows[ROWS - 1]
    assert_true(last.position.y > _stepped_list.size.y, "The rows are laid out below the view")
    assert_eq(_seen(_stepped_list)["rows"], _seen(_whole_list)["rows"], "The two lists start on the same rows")


func test_a_layer_added_draws_what_a_whole_sync_draws() -> void:
    _check("a layer added", func() -> void: SaLayerOps.new(_doc).add().name = "Added")
    assert_eq(_stepped_list.row_count(), ROWS + 1, "The new layer has its row")
    var lit: SaLayer = _stepped_list.layer_at(_stepped_list.picked.selected_idx)
    assert_eq(lit, _doc.get_node("Added"), "The new layer's row is the active one")


func test_a_filter_attached_draws_what_a_whole_sync_draws() -> void:
    var host := _doc.get_node("L300") as SaLayer
    _check("a filter attached", func() -> void: SaFilterOps.new(_doc).attach(host, MIRROR, {}))
    assert_eq(_stepped_list.row_count(), ROWS + 1, "The filter has its row")


func test_a_layer_made_active_draws_what_a_whole_sync_draws() -> void:
    _check("a layer made active", func() -> void: _doc.set_active_layer(_doc.get_node("L200") as SaLayer))
    var lit: SaLayer = _stepped_list.layer_at(_stepped_list.picked.selected_idx)
    assert_eq(lit, _doc.get_node("L200"), "The row made active is the active one")


func test_a_groups_eye_draws_what_a_whole_sync_draws() -> void:
    var group := _doc.get_node("G5") as SaLayer
    # The eye redraws its own row and asks no refresh of the rest.
    _check("a group's eye", func() -> void: SaLayerOps.new(_doc).set_visible(group, false), false)
    assert_false(group.visible, "The group is hidden")


func test_the_four_steps_one_after_another_draw_what_a_whole_sync_draws() -> void:
    _check("a layer added", func() -> void: SaLayerOps.new(_doc).add().name = "Added")
    _check("a filter attached", func() -> void: SaFilterOps.new(_doc).attach(_doc.get_node("Added") as SaLayer, MIRROR, {}))
    _check("a layer made active", func() -> void: _doc.set_active_layer(_doc.get_node("L200") as SaLayer))
    _check("a group's eye", func() -> void: SaLayerOps.new(_doc).set_visible(_doc.get_node("G5") as SaLayer, false), false)
    assert_eq(_stepped_list.row_count(), ROWS + 2, "The added layer and its filter have their rows")
