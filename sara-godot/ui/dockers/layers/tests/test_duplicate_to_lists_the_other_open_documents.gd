## The menu's half: Layer > Duplicate To, and the same row in
## the menu a right click opens on the Layers docker, lists every open document
## but the one in front, dims while there is no other, and a pick copies the
## active layer or group into the document picked, `SaDuplicateToChoice`.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

const REQUIRES_GPU := true

const SIZE := Vector2i(256, 256)


## What the app's main is to the choice: a node holding the open documents.
class Host:
    extends Node

    var documents := SaDocuments.new()


var _host: Host
var _easels: Array[SaEasel] = []


func before_each() -> void:
    _host = Host.new()
    _easels = [Bench.easel(SIZE), Bench.easel(SIZE)]
    _host.documents.add(SaSurface.create(&"document_1", _easels[0], null))


func after_each() -> void:
    for easel in _easels:
        easel.free()
    _easels.clear()
    _host.free()


func test_one_document_open_dims_the_row() -> void:
    var choice := SaDuplicateToChoice.new(_easels[0].document, _host)
    assert_eq(choice.targets().size(), 0, "No other document to copy into")
    assert_false(choice.live(), "The row is dimmed")


func test_a_pick_copies_the_active_layer_into_the_other_document() -> void:
    _host.documents.add(SaSurface.create(&"document_2", _easels[1], null))
    var from := _easels[0].document
    var to := _easels[1].document
    var layer := from.get_node("Layer 1") as SaLayer
    layer.name = "Sky"
    layer.get_or_create_chunk(Vector2i.ZERO).clear(Color(0.3, 0.5, 1.7, 1.0))
    from.set_active_layer(layer)
    var choice := SaDuplicateToChoice.new(from, _host)
    assert_true(choice.live(), "The row is live with a second document open")
    assert_eq(choice.targets().size(), 1, "The list holds the other document alone")
    assert_eq(choice.targets()[0].id, &"document_2", "By its surface's id")
    var answer := choice.pick(&"document_2")
    assert_eq(answer.get("copied"), ["Sky"], "Sky is copied: %s" % str(answer))
    var copy := to.get_node_or_null("Sky") as SaLayer
    assert_not_null(copy, "The other document holds Sky")
    assert_eq(to.active_layer, copy, "The copy is the target's active layer")
    assert_eq(copy.get_index(), to.get_child_count() - 1, "On top of the target's stack")
    assert_eq(_host.documents.front.get_document(), from, "The source stays in front")
    assert_true(to.undo(), "One undo in the target")
    assert_null(to.get_node_or_null("Sky"), "takes the copy away")


func test_the_layer_menu_rows_hold_the_row_after_duplicate_layer() -> void:
    var ids: Array[StringName] = []
    for entry: Variant in SaLayerMenuRows.ROWS:
        if entry is Array:
            ids.append(entry[0])
    assert_eq(ids.find(SaLayerMenuRows.DUPLICATE_TO), ids.find(&"layer_duplicate") + 1, "Duplicate To follows Duplicate Layer")
    assert_eq(SaLayerMenuRows.number_of(SaLayerMenuRows.DUPLICATE_TO), 428, "Pressed by 428")
