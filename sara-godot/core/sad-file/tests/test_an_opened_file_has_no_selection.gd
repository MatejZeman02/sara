## A `.sad` file opens with no selection, as a new document does.
##
## `_replace_layers` cleared the layers and left `document.selection` alone, so a
## rectangle selected before an open stood active over the new picture. Every
## other door that replaces a document goes through `reset_to_default`, which
## makes a fresh selection. Both containers are opened here, since the version 3
## and the version 4 reader each call `_replace_layers` on their own.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice: a selection's chunks and a load's layers are textures.
const REQUIRES_GPU := true


func _document() -> SaDocument:
    var doc := SaDocument.new()
    doc.setup_default_document(Vector2i(64, 64), SaCompositor.new())
    return doc


## A version 4 file, the plain container the writer picks for a document with no
## mask, filter or height.
func _write_v4(path: String) -> void:
    var source := _document()
    assert_eq(SaSadFile.version_for(source), SaSadFile.SAD_VERSION_PLAIN, "The fixture is a version 4 document")
    assert_eq(SaExport.save_sad(source, path), OK, "The version 4 fixture saves")
    source.free()


func _selected(doc: SaDocument) -> void:
    doc.selection.select_rect(Rect2i(8, 8, 24, 24))
    assert_true(doc.selection.active, "The rectangle is active before the open")
    assert_false(doc.selection.chunks.is_empty(), "and holds a chunk")


func _opens_clear(path: String, version: String) -> void:
    var doc := _document()
    _selected(doc)
    assert_eq(SaExport.load_sad(doc, path, SaCompositor.new()), OK, "The %s file opens" % version)
    assert_false(doc.selection.active, "A %s file opens with no selection" % version)
    assert_true(doc.selection.chunks.is_empty(), "and with no selection chunk")
    assert_eq(doc.selection.bounds, Rect2i(), "and no selection bounds")
    DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
    doc.free()


func test_a_version_4_file_opens_with_no_selection() -> void:
    var path := SaDataRoot.path("test_d5_v4.sad")
    _write_v4(path)
    _opens_clear(path, "version 4")
