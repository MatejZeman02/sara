## A save whose last step, the rename of the side file onto
## the target, fails keeps the side file, which holds the whole picture, and the
## painter's sentence names it. A previous file moved aside to `.sad1` is put
## back, or the sentence says where it is.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice: a save reads chunks back and a load writes them.
const REQUIRES_GPU := true
## The layers of the document saved, each filled with its own colour.
const LAYERS := 3
## The older copies the second test keeps.
const VERSIONS := 2

static var scratch: String = SaDataRoot.path("test_save.sad")

var _said: Array[String] = []


func before_each() -> void:
    SaSadSave.finish_all()
    _said.clear()
    _clear()


func after_each() -> void:
    SaSadSave.finish_all()
    if SaProblems.has_sink():
        SaProblems.detach_sink()
    SaProblems.announce = true
    _clear()


func _clear() -> void:
    var at := ProjectSettings.globalize_path(scratch)
    for path: String in [at, at + "1", at + "2", at + "3", at + SaSadFile.SAD_TEMP_SUFFIX]:
        DirAccess.remove_absolute(path)


## The colour layer *index* is filled with, *shade* telling one save's document
## from another's.
static func colour_of(index: int, shade: float) -> Color:
    return Color(shade, index / 4.0, 1.0 - index / 4.0, 1.0)


## A document of [constant LAYERS] paint layers in the colours of *shade*.
static func painted(shade: float) -> SaDocument:
    var doc := SaDocument.new()
    doc.setup_default_document(Vector2i(256, 256), SaCompositor.new(), SaColorSpace.srgb())
    var ops := SaLayerOps.new(doc)
    var adds := 0
    while layers_of(doc).size() < LAYERS and adds < LAYERS:
        ops.add()
        adds += 1
    var layers := layers_of(doc)
    for index in layers.size():
        layers[index].get_or_create_field(Vector2i.ZERO, SaFieldSpec.ALBEDO).clear(colour_of(index, shade))
    return doc


## Every layer of *doc* but the stroke buffer, bottom first.
static func layers_of(doc: SaDocument) -> Array[SaLayer]:
    var found: Array[SaLayer] = []
    for child in doc.get_children():
        if child is SaLayer and child != doc.stroke_layer:
            found.append(child as SaLayer)
    return found


## Whether the file at *path* opens as the document [method painted] made in
## *shade*, every layer holding its colour.
func opens_as(path: String, shade: float) -> bool:
    var reopened := SaDocument.new()
    var err := SaExport.load_sad(reopened, path, SaCompositor.new())
    var same := 0
    for index in layers_of(reopened).size() if err == OK else 0:
        var texture := layers_of(reopened)[index].get_field(Vector2i.ZERO, SaFieldSpec.ALBEDO)
        var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0) if texture != null else PackedByteArray()
        var texel := (
            Color(bytes.decode_float(0), bytes.decode_float(4), bytes.decode_float(8), 1.0) if bytes.size() >= 12 else Color()
        )
        if texel.is_equal_approx(colour_of(index, shade)):
            same += 1
    reopened.free()
    return same == LAYERS


## Keeps the save's own lines, never the ones an earlier suite left pending,
## which the sink is handed first.
func _heard(line: String, _kind: SaProblems.Kind) -> void:
    if line.begins_with("SaSadSave"):
        _said.append(line)


## A folder standing at the target's name is a rename that fails whatever the
## platform. The background save ends with an error, the side file is still
## there and opens as the document, and the problem's line names it.
func test_a_folder_at_the_target_keeps_the_side_file_and_the_line_names_it() -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(scratch))
    var doc := painted(0.25)
    assert_eq(layers_of(doc).size(), LAYERS, "The document has its layers")
    SaProblems.announce = false
    SaProblems.attach_sink(_heard)
    var ended: Array[Error] = []
    SaSadSave.start(doc, scratch, 0, null, false, func(err: Error) -> void: ended.append(err))
    assert_true(SaSadSave.finish_all(), "The save ends")
    SaProblems.detach_sink()
    assert_eq(ended.size(), 1, "once")
    assert_false(ended.is_empty() or ended[0] == OK, "with an error, a folder standing at its name")
    var kept := scratch + SaSadFile.SAD_TEMP_SUFFIX
    assert_true(FileAccess.file_exists(kept), "The side file is still on disk at %s" % kept)
    assert_true(opens_as(kept, 0.25), "and opens as the same document, every layer in its colour")
    assert_eq(_said.size(), 1, "One problem is reported, read %s" % [_said])
    var line := _said[0] if not _said.is_empty() else ""
    assert_true(line.contains("kept at '%s'" % kept), "naming the kept file, read: %s" % line)
    assert_true(line.contains("A folder stands at '%s'" % scratch), "and the folder in the way, read: %s" % line)
    doc.free()


## Writes [constant VERSIONS] files over [member scratch], *shades* in order, so
## the last is at the target and the one before it at `.sad1`, and answers
## their bytes, newest first.
func saved_in_turn(shades: Array[float]) -> Array[PackedByteArray]:
    for shade in shades:
        var doc := painted(shade)
        assert_eq(layers_of(doc).size(), LAYERS, "The document has its layers")
        assert_eq(SaExport.save_sad(doc, scratch, VERSIONS), OK, "The file in %.2f is written" % shade)
        doc.free()
    return [FileAccess.get_file_as_bytes(scratch), FileAccess.get_file_as_bytes(scratch + "1")]


## Writes a document in *shade* over [member scratch] through `write_out`, with
## *rename* standing in for each rename, and answers the error. The copy that
## follows a failed rename is refused as well, which is the case
## this suite was written for.
func written_with(shade: float, rename: Callable) -> Error:
    var doc := painted(shade)
    assert_eq(layers_of(doc).size(), LAYERS, "The document has its layers")
    var blobs := PackedByteArray()
    var header := SaSadFile.header_of(doc, blobs, GlobalShaderCompiler.get_rd())
    var refused := func(_from: String, _to: String) -> Error: return ERR_FILE_CANT_WRITE
    var err := SaSadSave.write_out(scratch, header, blobs, VERSIONS, SaSadSave.Landing.new(rename, refused))
    doc.free()
    return err


## Over an existing file with versions kept, the target is moved to `.sad1`
## before the rename, and that rename alone is made to fail. The previous file
## is back at the target, the chain of older copies as it was, the new picture
## kept in the side file, and the sentence says both.
func test_a_failed_rename_over_a_kept_version_puts_the_previous_file_back() -> void:
    var before := saved_in_turn([0.5, 0.75])
    var kept := scratch + SaSadFile.SAD_TEMP_SUFFIX
    var onto_the_target := func(from: String, to: String) -> Error:
        return ERR_FILE_CANT_WRITE if from == kept else DirAccess.rename_absolute(from, to)
    assert_eq(written_with(1.0, onto_the_target), ERR_FILE_CANT_WRITE, "The rename onto the target fails")
    var line := SaSadFile.why_not_saved(scratch)
    assert_eq(FileAccess.get_file_as_bytes(scratch), before[0], "The previous file is back at the target")
    assert_true(line.contains("The previous file is untouched"), "and the sentence says so, read: %s" % line)
    assert_eq(FileAccess.get_file_as_bytes(scratch + "1"), before[1], "The oldest copy is back at .sad1")
    assert_false(FileAccess.file_exists(scratch + "2"), "and no copy was pushed down to .sad2")
    assert_true(opens_as(kept, 1.0), "The new picture is kept whole at %s" % kept)
    assert_true(line.contains("kept at '%s'" % kept), "and the sentence names it, read: %s" % line)


## The same save with every rename refused after the target was moved aside,
## so the previous file cannot be put back. It stays at `.sad1`, whole, and the
## sentence names that path as well as the kept side file.
func test_a_previous_file_that_cannot_go_back_is_named_where_it_is() -> void:
    var before := saved_in_turn([0.5, 0.75])
    var kept := scratch + SaSadFile.SAD_TEMP_SUFFIX
    var refused := func(_from: String, _to: String) -> Error: return ERR_FILE_CANT_WRITE
    assert_eq(written_with(1.0, refused), ERR_FILE_CANT_WRITE, "The rename onto the target fails")
    var line := SaSadFile.why_not_saved(scratch)
    assert_false(FileAccess.file_exists(scratch), "Nothing stands at the target")
    assert_eq(FileAccess.get_file_as_bytes(scratch + "1"), before[0], "The previous file is whole at .sad1")
    assert_true(line.contains("The previous file is at '%s1'." % scratch), "and the sentence names it, read: %s" % line)
    assert_true(opens_as(kept, 1.0), "The new picture is kept whole at %s" % kept)
    assert_true(line.contains("kept at '%s'" % kept), "and the sentence names that too, read: %s" % line)
