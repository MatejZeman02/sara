## A `.sad` that holds no module data opens into a document with nothing of the
## one before: the module data and the blend reference white of whatever
## document was open must not survive the read, or the next save writes that
## stale module data into the file. The fixture is the painted file the command
## line and the import suites already read.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice: loading a document touches chunk textures.
const REQUIRES_GPU := true

const PAINTED := "res://tests/data/painted_two_layers.sad"


func _stale_document() -> SaDocument:
    var doc := SaDocument.new()
    doc.setup_default_document(Vector2i(64, 64), SaCompositor.new())
    doc.module_data = {"sara-mixing-module": {"colour_set": "quinacridone-6"}}
    doc.blend_reference_white = 4.0
    return doc


func test_a_file_drops_the_last_documents_module_data_and_white() -> void:
    var doc := _stale_document()
    assert_eq(SaExport.load_sad(doc, PAINTED, SaCompositor.new()), OK, "The fixture opens")
    assert_eq(doc.module_data, {}, "with no module data from the document before it")
    assert_almost_eq(doc.blend_reference_white, 1.0, 1e-6, "and the default reference white")
    doc.free()


func test_the_next_save_writes_no_stale_module_data() -> void:
    var doc := _stale_document()
    assert_eq(SaExport.load_sad(doc, PAINTED, SaCompositor.new()), OK, "The fixture opens")
    var path := SaDataRoot.path("test_d4_resaved.sad")
    assert_eq(SaExport.save_sad(doc, path), OK, "and saves again")
    var reread := SaDocument.new()
    assert_eq(SaExport.load_sad(reread, path, SaCompositor.new()), OK, "and the save reads back")
    assert_eq(reread.module_data, {}, "without the module data it never had")
    assert_almost_eq(reread.blend_reference_white, 1.0, 1e-6, "or the white it never had")
    DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
    reread.free()
    doc.free()
