## A `.sad` header whose width or height is under 1 or past
## the 16384 the dialogs allow is refused where it is read, with the file's
## name and the size it said, and the document the read was handed is left as
## it was. A side of 16384 still opens, and a header with no size still means
## 1024 by 1024.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice: a save reads chunks back and a load writes them.
const REQUIRES_GPU := true

static var saved: String = SaDataRoot.path("test_saved.sad")
static var rewritten: String = SaDataRoot.path("test_rewritten.sad")

## The sides no dialog could have made, each tried as the width and then as
## the height.
const REFUSED: Array[int] = [0, -1, 16385, 2000000000]


func after_each() -> void:
    for path: String in [saved, rewritten]:
        DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _small_document() -> SaDocument:
    var doc := SaDocument.new()
    doc.setup_default_document(Vector2i(64, 48), SaCompositor.new())
    return doc


func _layer_names(doc: SaDocument) -> Array[String]:
    var found: Array[String] = []
    for child in doc.get_children():
        if child is SaLayer:
            found.append(str(child.name))
    return found


## What the suite reads to say a document is unchanged: its layers in order,
## its canvas size and the name of its active layer.
func _state(doc: SaDocument) -> Array:
    return [_layer_names(doc), doc.canvas_size, str(doc.active_layer.name) if doc.active_layer != null else ""]


## The v4 file at *from* written again at *to*, its header's keys set from
## *changes*, where a null value takes the key out. The blobs follow as they
## were, because the header addresses them from where they start.
func _rewrite_v4(from: String, to: String, changes: Dictionary) -> void:
    var file := FileAccess.open(from, FileAccess.READ)
    assert_eq(file.get_buffer(4).get_string_from_ascii(), SaSadFile.SAD_MAGIC_V4, "The saved file is a v4 container")
    var version := file.get_32()
    var packed_size := file.get_32()
    var raw_size := file.get_32()
    var header: Dictionary = JSON.parse_string(
        file.get_buffer(packed_size).decompress(raw_size, SaSadFile.SAD_BLOB_COMPRESS).get_string_from_utf8()
    )
    var blobs := file.get_buffer(file.get_length() - file.get_position())
    file.close()
    _change(header, changes)
    var raw := JSON.stringify(header).to_utf8_buffer()
    var packed := raw.compress(SaSadFile.SAD_BLOB_COMPRESS)
    var out := FileAccess.open(to, FileAccess.WRITE)
    out.store_buffer(SaSadFile.SAD_MAGIC_V4.to_ascii_buffer())
    out.store_32(version)
    out.store_32(packed.size())
    out.store_32(raw.size())
    out.store_buffer(packed)
    out.store_buffer(blobs)
    out.close()


func _change(header: Dictionary, changes: Dictionary) -> void:
    for key: String in changes:
        if changes[key] == null:
            header.erase(key)
        else:
            header[key] = changes[key]


## The note's own case: each side refused as the width and then as the height,
## with `ERR_FILE_CORRUPT`, and the document handed to the read left as it was.
func test_a_side_no_dialog_could_make_is_refused_and_the_document_is_left_alone() -> void:
    var source := _small_document()
    assert_eq(SaExport.save_sad(source, saved), OK, "A small document saves")
    source.free()
    for key: String in ["width", "height"]:
        for side: int in REFUSED:
            _rewrite_v4(saved, rewritten, {key: side})
            var doc := _small_document()
            var before := _state(doc)
            var said := "%s %d" % [key, side]
            assert_eq(SaExport.load_sad(doc, rewritten), ERR_FILE_CORRUPT, "A header of %s is refused as corrupt" % said)
            assert_eq(_state(doc), before, "and with %s the layers, the size and the active layer are as they were" % said)
            doc.free()


## The text the read pushes names the file and the size the header said, so
## the painter can tell which file and what was wrong with it.
func test_the_refusal_names_the_file_and_the_size() -> void:
    var text := SaSadHeaderNumbers.refusal({"width": 0, "height": 48}, "/tmp/hand-made.sad")
    assert_true(text.contains("/tmp/hand-made.sad"), "The refusal names the file: %s" % text)
    assert_true(text.contains("0 by 48"), "and the size it said")
    text = SaSadHeaderNumbers.refusal({"width": 64, "height": 16385}, "/tmp/hand-made.sad")
    assert_true(text.contains("64 by 16385"), "the height as well as the width: %s" % text)
    text = SaSadHeaderNumbers.refusal({"width": -1, "height": 2000000000}, "x.sad")
    assert_true(text.contains("-1 by 2000000000"), "and a negative or a huge side as it stood: %s" % text)
    assert_eq(SaSadHeaderNumbers.refusal({"width": 16384, "height": 1}, "x.sad"), "", "A size at the limits is no refusal")


func test_a_side_of_16384_still_opens() -> void:
    var source := _small_document()
    assert_eq(SaExport.save_sad(source, saved), OK, "A small document saves")
    source.free()
    _rewrite_v4(saved, rewritten, {"width": 16384, "height": 16})
    var doc := _small_document()
    assert_eq(SaExport.load_sad(doc, rewritten), OK, "A header of 16384 by 16 opens")
    assert_eq(doc.canvas_size, Vector2i(16384, 16), "at the size it said")
    doc.free()


func test_a_header_with_no_size_still_opens_at_1024() -> void:
    var source := _small_document()
    assert_eq(SaExport.save_sad(source, saved), OK, "A small document saves")
    source.free()
    _rewrite_v4(saved, rewritten, {"width": null, "height": null})
    var doc := _small_document()
    assert_eq(SaExport.load_sad(doc, rewritten), OK, "A header with no width or height opens")
    assert_eq(doc.canvas_size, Vector2i(1024, 1024), "at 1024 by 1024, as it always did")
    doc.free()


## A file that starts with the early container's magic is no file this build
## reads, so it gets the refusal any unknown magic does, and the document the
## read was handed is left as it was.
func test_a_file_of_the_early_container_is_refused_as_unrecognised() -> void:
    var file := FileAccess.open(rewritten, FileAccess.WRITE)
    file.store_buffer("SAD1".to_ascii_buffer())
    file.store_32(2)
    file.store_buffer(PackedByteArray([1, 2]))
    file.close()
    var doc := _small_document()
    var before := _state(doc)
    assert_eq(SaExport.load_sad(doc, rewritten), ERR_FILE_UNRECOGNIZED, "A file with the early magic is refused")
    assert_eq(_state(doc), before, "and leaves the document as it was")
    assert_eq(SaSadFile.version_at(rewritten), 0, "and has no version a caller could trust")
    doc.free()


## One limit, so the reader and the three dialogs cannot drift apart.
func test_the_limit_is_the_dialogs_limit() -> void:
    assert_eq(SaSadHeaderNumbers.MAX_SIDE, NewDocumentDialog.MAX_DIMENSION, "The new document dialog's")
    assert_eq(SaSadHeaderNumbers.MAX_SIDE, SaCanvasSizeDialog.MAX_DIMENSION, "the canvas size dialog's")
    assert_eq(SaSadHeaderNumbers.MAX_SIDE, SaImageSizeDialog.MAX_DIMENSION, "and the image size dialog's")
