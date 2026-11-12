## A new document starts with nothing of the one it replaced but the window
## `reset_to_default` is the door File > New, an opened picture
## and an OpenRaster file all come through, and it put the layers, the
## selection and W back while the canvas filter, the modules' data and the
## Reference docker's boards stayed on the document object and carried over.
extends "res://tests/test_framework.gd"


func test_the_canvas_filter_does_not_follow_into_a_new_document() -> void:
    var easel := SaEasel.create_default(Vector2i(256, 256))
    var doc := easel.document
    doc.root_filters.append(SaAttachedFilter.new(&"blur"))
    doc.reset_to_default(Vector2i(128, 128))
    assert_eq(doc.root_filters.size(), 0, "A new document has no filter on its root")
    easel.free()


func test_the_modules_data_and_the_boards_do_not_follow_either() -> void:
    var easel := SaEasel.create_default(Vector2i(256, 256))
    var doc := easel.document
    doc.module_data["mixes"] = {"set": "earth"}
    doc.reference_boards = [{"path": SaDataRoot.path("board.png")}]
    doc.reset_to_default(Vector2i(128, 128))
    assert_true(doc.module_data.is_empty(), "No module has said anything about the new document")
    assert_true(doc.reference_boards.is_empty(), "and it has no reference boards")
    easel.free()
