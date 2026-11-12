## Clear Layer under a selection lands on the paint the layer holds and makes
## no chunk. `fill_layer` allocated the whole grid before any
## fill, so a clear of a small selection on an empty layer left a transparent
## 256 by 256 tile at every position of the canvas, which hard rule 3 reads as
## paint where there is none.
extends "res://tests/test_framework.gd"


func test_a_clear_of_an_empty_layer_under_a_selection_leaves_it_empty() -> void:
    var easel := SaEasel.create_default(Vector2i(512, 512))
    var doc := easel.document
    doc.selection.select_rect(Rect2i(0, 0, 16, 16))
    doc.clear_layer()
    assert_eq(doc.active_layer.chunks.size(), 0, "Nothing was there to clear, so nothing is allocated")
    easel.free()


func test_a_clear_under_a_selection_keeps_to_the_chunks_the_layer_held() -> void:
    var easel := SaEasel.create_default(Vector2i(512, 512))
    var doc := easel.document
    doc.active_layer.get_or_create_chunk(Vector2i(1, 1))
    doc.selection.select_rect(Rect2i(256, 256, 16, 16))
    doc.clear_layer()
    assert_eq(doc.active_layer.chunks.keys(), [Vector2i(1, 1)], "The one chunk it held and no other")
    assert_true(doc.undo(), "The clear is still a step")
    assert_eq(doc.active_layer.chunks.keys(), [Vector2i(1, 1)], "and undoing it leaves the chunk it had")
    easel.free()


func test_a_coloured_fill_under_a_selection_takes_only_the_chunks_it_reaches() -> void:
    var easel := SaEasel.create_default(Vector2i(512, 512))
    var doc := easel.document
    doc.selection.select_rect(Rect2i(300, 300, 16, 16))
    doc.fill_layer(Color.RED)
    assert_eq(doc.active_layer.chunks.keys(), [Vector2i(1, 1)], "A fill with colour takes the one chunk the selection reaches")
    easel.free()
