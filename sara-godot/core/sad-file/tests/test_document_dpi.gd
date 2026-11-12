## The document's resolution, and the additive header key that carries it.
##
## Nothing in the tree stored a physical size, so a document could not say how
## big it was on paper. The key is added now, while it is one additive
## entry in the v4 header, rather than after templates and a resize dialog
## exist and it would be a migration.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice: a round trip reads chunks back and writes them.
const REQUIRES_GPU := true

static var scratch_round_trip: String = SaDataRoot.path("test_dpi_round_trip.sad")
static var scratch_no_key: String = SaDataRoot.path("test_dpi_no_key.sad")


func after_each() -> void:
    for path: String in [scratch_round_trip, scratch_no_key]:
        DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_a_new_document_is_72_dpi_and_the_dialog_offers_the_same() -> void:
    var easel := SaEasel.create_default(Vector2i(64, 64))
    assert_almost_eq(easel.document.dpi, 72.0, 0.0, "72 is what every file before the key meant")
    easel.free()

    var dialog := NewDocumentDialog.new()
    assert_almost_eq(dialog.selected_dpi(), SaDocument.DEFAULT_DPI, 0.0, "and what File > New offers first")
    assert_eq((dialog.page.row(&"dpi").control as SpinBox).min_value, 1.0, "Zero pixels per inch is not a resolution")
    dialog.free()


func test_the_dpi_reaches_the_document_through_reset_and_is_not_inherited() -> void:
    var easel := SaEasel.create_default(Vector2i(64, 64))
    easel.document.reset_to_default(Vector2i(32, 32), null, 300.0)
    assert_almost_eq(easel.document.dpi, 300.0, 0.0, "File > New hands its third field to the document")

    easel.document.reset_to_default(Vector2i(32, 32))
    assert_almost_eq(easel.document.dpi, 72.0, 0.0, "and a document that names none does not keep the last one's")

    easel.document.reset_to_default(Vector2i(32, 32), null, -5.0)
    assert_almost_eq(easel.document.dpi, 72.0, 0.0, "A resolution below zero is read as none")
    easel.free()


func test_the_dpi_survives_a_sad_round_trip() -> void:
    var easel := SaEasel.create_default(Vector2i(64, 64))
    easel.document.dpi = 300.0
    assert_eq(SaExport.save_sad(easel.document, scratch_round_trip), OK, "Saving succeeds")

    var reopened := SaEasel.create_default(Vector2i(16, 16))
    assert_eq(SaExport.load_sad(reopened.document, scratch_round_trip), OK, "Loading succeeds")
    assert_almost_eq(reopened.document.dpi, 300.0, 1e-6, "The resolution came back")
    easel.free()
    reopened.free()


## A v4 file written before the key existed. Built here rather than kept as a
## fixture, because the file is the header alone and nothing about its chunks
## matters to the question.
func test_a_v4_file_without_the_key_reads_as_72() -> void:
    var header := {
        "format": "sad",
        "version": SaSadFile.SAD_VERSION,
        "width": 32,
        "height": 32,
        "layers": [{"name": "Layer 1", "visible": true, "opacity": 1.0, "chunks": []}],
    }
    var raw := JSON.stringify(header).to_utf8_buffer()
    var packed := raw.compress(SaSadFile.SAD_BLOB_COMPRESS)
    var file := FileAccess.open(scratch_no_key, FileAccess.WRITE)
    file.store_buffer(SaSadFile.SAD_MAGIC_V4.to_ascii_buffer())
    file.store_32(SaSadFile.SAD_VERSION)
    file.store_32(packed.size())
    file.store_32(raw.size())
    file.store_buffer(packed)
    file.close()

    var easel := SaEasel.create_default(Vector2i(16, 16))
    easel.document.dpi = 600.0
    assert_eq(SaExport.load_sad(easel.document, scratch_no_key), OK, "An older file still opens")
    assert_almost_eq(easel.document.dpi, 72.0, 0.0, "and reads as 72, not as whatever the last document was")
    easel.free()
