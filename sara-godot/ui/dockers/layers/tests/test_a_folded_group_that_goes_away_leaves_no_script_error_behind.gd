## A folded group that goes away leaves no script error behind.
##
## A group folded by its fold mark, then deleted or
## replaced by a new document, would raise `Trying to assign invalid previously freed
## instance` on every add, fill, click and group after it, and the docker then
## lit Layer 1 while the document's active layer was another. The keeper looped
## over its folded groups with a variable typed `SaLayer`, which a freed key
## cannot be assigned to, and the error stopped `_on_active_layer_changed`
## before its `sync()`.
##
## The script errors are read off a logger attached for the whole case, since a
## script error stops the function it is raised in and lets the caller go on.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

var _easel: SaEasel
var _doc: SaDocument
var _canvas: SaCanvas
var _docker: LayersDocker
var _errors: SaErrorCatcher


func before_each() -> void:
    _easel = SaEasel.create_default(Vector2i(128, 128))
    _easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    _doc = _easel.document
    _doc.active_layer.name = "Background"
    SaLayerOps.new(_doc).add().name = "Sky"
    SaLayerOps.new(_doc).add().name = "Hills"
    _canvas = SaCanvas.new()
    _canvas.easel = _easel
    _docker = LayersDocker.new()
    _docker.target_canvas = _canvas
    _docker.list_keeper.listen()
    _docker.sync_layer_list()
    _errors = SaErrorCatcher.new()
    OS.add_logger(_errors)


func after_each() -> void:
    OS.remove_logger(_errors)
    _errors = null
    _docker.free()
    _canvas.free()
    _easel.free()
    _doc = null


func _list() -> SaLayerList:
    return _docker.item_list


func _row_of(layer: SaLayer) -> int:
    for i in _list().rows.size():
        if _list().layer_at(i) == layer:
            return i
    return -1


func _lit_layers() -> Array:
    var out: Array = []
    for i in _list().rows.size():
        if _list().rows[i].lit:
            out.append(_list().layer_at(i))
    return out


func _named(layer_name: String) -> SaLayer:
    return _doc.find_child(layer_name, true, false) as SaLayer


## Groups Sky and Hills and folds the group by its fold mark, and returns it.
func _fold_a_group() -> SaLayer:
    var picked: Array[SaLayer] = [_named("Sky"), _named("Hills")]
    _list().select_layers(picked, picked[1])
    _docker.actions.toggle_group()
    var group := SaLayerStack.parent_of(picked[1])
    assert_true(group != null and group.is_group, "Sky and Hills are in a group")
    _docker._on_group_toggled(_row_of(group))
    assert_true(_docker._closed_groups.has(group), "the group is folded")
    assert_eq(_row_of(picked[0]), -1, "and its rows are folded away")
    return group


func _press(idx: int) -> void:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = true
    _list()._on_row_gui_input(event, idx)


## A new document, a layer added on it and a click on its first row, reading the
## lit row against the document's active layer after each, and no script error.
func _new_document_add_and_click(case: String) -> void:
    _doc.reset_to_default(Vector2i(128, 128))
    assert_eq(_lit_layers(), [_doc.active_layer], "%s, the new document: the lit row is the active layer" % case)
    var added := SaLayerOps.new(_doc).add()
    added.name = "D"
    assert_eq(_doc.active_layer, added, "%s: the added layer is the active one" % case)
    assert_eq(_lit_layers(), [added], "%s, a layer added: its row is the one lit" % case)
    var first := _list().layer_at(_list().rows.size() - 1)
    _press(_list().rows.size() - 1)
    assert_eq(_doc.active_layer, first, "%s: a click on the bottom row makes its layer active" % case)
    assert_eq(_lit_layers(), [first], "%s, a click: the lit row is the active layer" % case)
    assert_true(_docker._closed_groups.is_empty(), "%s: the keeper holds no folded group" % case)
    assert_eq(_errors.described([SaErrorCatcher.SCRIPT]), PackedStringArray(), "%s: no script error in the log" % case)


func test_a_folded_group_deleted_then_a_new_document() -> void:
    var group := _fold_a_group()
    assert_eq(_doc.active_layer, group, "the fold moved the active mark onto the group")
    _docker.actions.delete_layer()
    assert_false(_doc.is_ancestor_of(group), "the group is deleted")
    assert_true(_docker._closed_groups.is_empty(), "and the keeper forgets it the moment it leaves")
    _new_document_add_and_click("deleted, then a new document")


func test_a_folded_group_then_a_new_document_straight_away() -> void:
    _fold_a_group()
    _new_document_add_and_click("a new document straight away")


## Flatten, the other way a group leaves the document besides a delete. Merge
## Down refuses a group on either side (`SaLayerRefusals.merge`), so a merge
## never takes one out.
func test_a_folded_group_flattened_is_forgotten() -> void:
    var group := _fold_a_group()
    _docker.actions.flatten()
    assert_false(_doc.is_ancestor_of(group), "Flatten takes the group out of the document")
    assert_true(_docker._closed_groups.is_empty(), "and the keeper forgets it")
    assert_eq(_lit_layers(), [_doc.active_layer], "the lit row is the active layer after Flatten")
    assert_eq(_errors.described([SaErrorCatcher.SCRIPT]), PackedStringArray(), "and no script error in the log")
    _new_document_add_and_click("flattened, then a new document")
