## File > Open on a picture makes a document of it, where File > Import
## puts one into the document that is already open.
##
## `SaDocumentFiles.open_image_into` is the document half of the flow's own path,
## public for exactly this: the flow's `_document()` asks Sara's main scene for
## its canvas, and no suite builds that. What the flow adds around it is the canvas resize and the recent-files entry,
## and `scenarios/open-image-as-document.json` is what proves those.
extends "res://tests/test_framework.gd"

## Chunk uploads are real textures, so this needs a RenderingDevice.
const REQUIRES_GPU := true

const PICTURE := "res://tests/data/import_gradient.png"
## What `import_gradient.png` is, and the whole point of the size assertions:
## neither number is the 256 the easel below starts at.
const PICTURE_SIZE := Vector2i(300, 200)


func _names(doc: SaDocument) -> Array:
    var out: Array = []
    for layer in SaLayerOps.new(doc).layers():
        out.append(String(layer.name))
    return out


func test_a_picture_becomes_the_whole_document() -> void:
    var easel := SaEasel.create_default(Vector2i(256, 256))
    var doc := easel.document
    assert_eq(SaLayerOps.new(doc).layers().size(), 2, "A fresh document is a background and an empty paint layer")

    var layer := SaDocumentFiles.open_image_into(doc, PICTURE)
    assert_not_null(layer, "The picture is read and placed")
    assert_eq(doc.canvas_size, PICTURE_SIZE, "The canvas is the picture's size, not the one it replaced")
    assert_eq(SaLayerOps.new(doc).layers().size(), 1, "and the picture is the only layer on it")
    assert_eq(_names(doc), ["import_gradient"], "named after the file")
    assert_true(doc.active_layer == layer, "and active, which is also what rebuilds the layers docker")

    easel.free()


## Nothing `open_image_into` does is an edit a painter made, so nothing it does
## is one to take back. The reset, the place and the two removals each leave a
## history step behind them, and a first Ctrl+Z that brings back a grey layer
## nobody saw is not what opening a file means.
func test_opening_a_picture_leaves_nothing_to_undo() -> void:
    var easel := SaEasel.create_default(Vector2i(256, 256))
    var doc := easel.document

    SaDocumentFiles.open_image_into(doc, PICTURE)

    assert_eq(doc.history.step_count(), 0, "The history is empty")
    assert_false(doc.undo_redo.has_undo(), "and there is nothing to undo")

    easel.free()


## The document has no file of its own, so Save asks where: `open_path` marks
## a `.sad` saved because that file is the document, and a PNG is not. It holds
## the picture exactly, so it is clean and closing asks nothing, and it
## goes by the picture's name.
func test_the_document_a_picture_makes_has_no_file_yet() -> void:
    var easel := SaEasel.create_default(Vector2i(256, 256))
    var doc := easel.document

    SaDocumentFiles.open_image_into(doc, PICTURE)

    assert_eq(doc.file_path, "", "The document is not the picture's file")
    assert_false(doc.modified, "and has nothing to lose, so closing asks nothing")
    assert_eq(SaDocumentSource.name_of(doc), PICTURE.get_file(), "and goes by the picture's name")

    easel.free()


func test_a_path_that_is_not_a_picture_changes_nothing() -> void:
    var easel := SaEasel.create_default(Vector2i(256, 256))
    var doc := easel.document

    var layer := SaDocumentFiles.open_image_into(doc, "res://tests/data/there-is-no-such-file.png")

    assert_null(layer, "Nothing is placed")
    assert_eq(doc.canvas_size, Vector2i(256, 256), "and the document is untouched")
    assert_eq(SaLayerOps.new(doc).layers().size(), 2, "with the layers it had")

    easel.free()
