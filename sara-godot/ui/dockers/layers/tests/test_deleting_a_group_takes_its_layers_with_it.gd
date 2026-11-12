## Deleting a group takes the group and everything in it, as one undo step,
## through the door and through the docker's minus alike.
##
## A script's `{"layer": {"of": "ref", "delete":
## true}}` took out the group `ref` and left its layer and that layer's two
## filters at the top of the stack. The door called `SaLayerOps.remove`, which
## took the group node alone, while the minus and the Layer menu already went
## through `remove_many` and so through `remove_group`. `remove` now hands a
## group to `remove_group` too. The running app's half is
## `scenarios/deleting-a-group-takes-its-layers-with-it.json`.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

var _easel: SaEasel
var _doc: SaDocument
var _canvas: SaCanvas
var _layers: LayersDocker
var _group: SaLayer
var _filter: SaAttachedFilter


func before_each() -> void:
    _easel = Bench.easel(Vector2i(128, 128))
    _doc = _easel.document
    _doc.active_layer.name = "Base"
    var kept_ref := SaLayerOps.new(_doc).add()
    kept_ref.name = "Reference"
    var sketch := SaLayerOps.new(_doc).add()
    sketch.name = "Sketch"
    _filter = SaFilterOps.new(_doc).attach(kept_ref, Bench.INVERT)
    _group = SaLayerOps.new(_doc).group_layers([kept_ref, sketch])
    _group.name = "ref"
    _canvas = SaCanvas.new()
    _canvas.easel = _easel
    _layers = LayersDocker.new()
    _layers.target_canvas = _canvas
    _layers.list_keeper.listen()
    _layers.sync_layer_list()


func after_each() -> void:
    _layers.free()
    _canvas.free()
    _easel.free()
    _group = null
    _filter = null


func _names() -> PackedStringArray:
    var names := PackedStringArray()
    for layer in SaLayerOps.new(_doc).layers():
        names.append(str(layer.name))
    return names


func _reference() -> SaLayer:
    return _doc.get_node_or_null("Reference") as SaLayer


func _done(line: String) -> Array:
    var said: Variant = JSON.parse_string(line.trim_prefix("SaCapture: layer "))
    return said["done"] if said is Dictionary and said.has("done") else []


## The stack, the parenting and the filter as they stood before the delete.
func _assert_back(before: PackedStringArray) -> void:
    assert_eq(_names(), before, "one Ctrl+Z puts every layer back in its place")
    var kept_ref := _reference()
    assert_true(kept_ref != null and SaLayerStack.is_inside(kept_ref, _group), "Reference is inside the group again")
    assert_true(kept_ref != null and kept_ref.filters.has(_filter), "with its filter still on it")


func test_the_door_deletes_the_group_with_its_layers_and_their_filter() -> void:
    var before := _names()
    assert_eq(before, PackedStringArray(["Background", "Base", "Reference", "Sketch", "ref"]), "the group holds both layers")
    var steps := _doc.history.step_count()

    var line := SaCaptureLayers.run(_doc, {"of": "ref", "delete": true})

    assert_eq(_names(), PackedStringArray(["Background", "Base"]), "the group, both layers and the filtered one are gone")
    assert_eq(_done(line), ["deleted ref with Sketch, Reference (%s)" % Bench.INVERT], "the answer names what went")
    assert_eq(_doc.history.step_count(), steps + 1, "as one step")
    assert_eq(_doc.undo_redo.get_current_action_name(), "Delete Group", "named for the group")
    assert_true(_doc.undo(), "one Ctrl+Z")
    _assert_back(before)


func test_the_dockers_minus_deletes_the_group_with_its_layers() -> void:
    var before := _names()
    _doc.set_active_layer(_group)
    _layers.sync_layer_list()
    var steps := _doc.history.step_count()

    _layers.actions.del_btn.pressed.emit()

    assert_eq(_names(), PackedStringArray(["Background", "Base"]), "the minus takes the group and everything in it")
    assert_eq(_doc.history.step_count(), steps + 1, "as one step")
    assert_true(_doc.undo(), "one Ctrl+Z")
    _assert_back(before)


## The core call the door makes, asked directly, so a caller of `remove` other
## than the door gets the same.
func test_remove_on_a_group_is_remove_group() -> void:
    assert_true(SaLayerOps.new(_doc).remove(_group), "the group goes")
    assert_eq(_names(), PackedStringArray(["Background", "Base"]), "with its members")
