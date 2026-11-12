## A layer's own property draws its own row and leaves the other rows alone.
##
## Setting the opacity of one light in a stack of 540
## took 1.39 to 1.46 s, where the same step at 305 layers took
## 0.03 s. One cost that grew with the stack was here: every change of a
## layer's eye, opacity, mode, lock or name ended in a `document_changed`, and
## the keeper answered that by reading the rows against the document and
## drawing all of them, 13 ms a step on 540 layers and 5 ms more reading them.
##
## `SaDocument.layer_changed` now names the layer whose property moved, the
## keeper draws that row and the rows inside it when it is a group, and the
## `document_changed` of the same frame draws no other row and does not read
## the rows against the document at all.
##
## A row is caught up or stale by its label: a layer renamed behind the
## docker's back leaves the row showing the old name until something draws it,
## and `refresh` is what writes the new one.
##
## A docker is a `Window` and adding one to the tree in a headless test hangs,
## so nothing here enters the tree, as in `test_a_second_layer_list_shows_and_changes_the_same_stack.gd`,
## and the keeper is told to listen, which the docker's `_ready` does in the app.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

var _easel: SaEasel
var _canvas: SaCanvas
var _doc: SaDocument
var _list: SaLayerList
var _keeper: SaLayerListKeeper
var _ops: SaLayerOps

## Two plain layers over the default document's ground, and a group holding one
## more, so a property change can be read on a layer, on a layer beside it and
## on a group's member.
var _bottom: SaLayer
var _beside: SaLayer
var _group: SaLayer
var _inside: SaLayer


func before_each() -> void:
    _easel = SaEasel.create_default(Vector2i(64, 64))
    _easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    _doc = _easel.document
    _ops = SaLayerOps.new(_doc)
    _bottom = _doc.active_layer
    _bottom.name = "Bottom"
    _beside = _ops.add()
    _beside.name = "Beside"
    _inside = _ops.add()
    _inside.name = "Inside"
    _group = _ops.group_layers([_inside])
    _group.name = "Group"
    _canvas = SaCanvas.new()
    _canvas.easel = _easel
    _list = SaLayerList.new()
    _keeper = SaLayerListKeeper.new(_list, _canvas)
    _keeper.listen()


func after_each() -> void:
    _keeper = null
    _list.free()
    _canvas.free()
    _easel.free()
    _list = null
    _canvas = null
    _ops = null
    _doc = null
    _easel = null


## The row of *layer*, or null when the list draws none.
func _row_of(layer: SaLayer) -> SaRowFrame:
    for index in _list.row_count():
        if _list.layer_at(index) == layer:
            return _list.rows[index]
    return null


## Renames every layer behind the docker's back, so a row that is drawn again
## takes the new name and a row that is not keeps the old one. The node's name
## is written directly, which fires nothing the keeper hears.
func _mark_rows_stale() -> void:
    for layer: SaLayer in [_bottom, _beside, _group, _inside]:
        layer.name = "%s-fresh" % layer.name


## Which of the four layers' rows show the name the mark gave them.
func _drawn_again() -> Array[String]:
    var caught: Array[String] = []
    for layer: SaLayer in [_bottom, _beside, _group, _inside]:
        var row := _row_of(layer)
        if row != null and row.label == String(layer.name):
            caught.append(String(layer.name))
    return caught


func test_an_opacity_on_one_layer_draws_that_row_and_no_other() -> void:
    assert_eq(_list.row_count(), 5, "the list draws the ground, the two layers, the group and its member")
    _mark_rows_stale()
    _ops.set_opacity(_beside, 0.25)
    assert_eq(_drawn_again(), ["Beside-fresh"], "the layer whose opacity moved is the one row drawn again")


func test_an_eye_on_a_group_draws_its_row_and_the_rows_inside_it() -> void:
    _mark_rows_stale()
    _ops.set_visible(_group, false)
    assert_eq(_drawn_again(), ["Group-fresh", "Inside-fresh"], "a group's eye dims the rows it holds, so those are drawn")


func test_a_name_a_lock_and_a_mode_each_draw_their_own_row() -> void:
    for change: Callable in [
        func() -> void: _ops.set_locked(_beside, true),
        func() -> void: _ops.set_alpha_locked(_beside, true),
        func() -> void: _ops.set_blend_mode(_beside, &"multiply"),
    ]:
        _mark_rows_stale()
        change.call()
        assert_eq(_drawn_again(), ["Beside-fresh"], "the changed layer's row is drawn and no other")
        for layer: SaLayer in [_bottom, _beside, _group, _inside]:
            layer.name = String(layer.name).trim_suffix("-fresh")
        _list.refresh_all()


## The structure path is untouched: a layer added or gone still draws every
## row, because the rows are no longer the document's.
func test_a_layer_added_still_draws_every_row() -> void:
    _mark_rows_stale()
    var added := _ops.add()
    added.name = "Added"
    _keeper.sync()
    assert_eq(_drawn_again(), ["Bottom-fresh", "Beside-fresh", "Group-fresh", "Inside-fresh"], "every row follows an add")
