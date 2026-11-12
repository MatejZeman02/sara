## A save to a content address, what Android's picker hands
## for a file in a shared folder, is written in Sara's own storage and poured
## into the address in one write, with no side file and no numbered copies
## there. A save to an ordinary path lands as before, its `.sad1` kept.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice: a save reads chunks back and a load writes them.
const REQUIRES_GPU := true
## The older copies a save keeps.
const VERSIONS := 1
## The suite of a save whose last step fails, whose documents and reading this one shares.
const LAST_STEP := preload(
    "res://core/sad-file/tests/test_a_save_whose_last_step_fails_keeps_the_written_file_and_says_where_it_is.gd"
)

static var scratch: String = SaDataRoot.path("test_save.sad")

var _last_step := LAST_STEP.new()
## The renames and copies the stand-in for a content address was asked for.
var _asked: Array[String] = []


func before_each() -> void:
    SaSadSave.finish_all()
    _asked.clear()
    _clear()


func after_each() -> void:
    SaSadSave.finish_all()
    _clear()


func _clear() -> void:
    var at := ProjectSettings.globalize_path(scratch)
    for path: String in [at, at + "1", at + "2", at + SaSadFile.SAD_TEMP_SUFFIX, _side()]:
        DirAccess.remove_absolute(path)


## Where the stand-in's side file is written, in Sara's own storage.
func _side() -> String:
    return SaSadSave.Landing.new(Callable(), Callable(), true).side_of(scratch)


## A rename or a copy into a content address, which takes none, noted.
func _refused(from: String, to: String) -> Error:
    _asked.append("%s -> %s" % [from, to])
    return ERR_FILE_CANT_WRITE


## Writes the document of that suite in *shade* over [member scratch] landed as a
## content address, and answers the error and the landing.
func poured(shade: float) -> Array:
    var doc := LAST_STEP.painted(shade)
    var blobs := PackedByteArray()
    var header := SaSadFile.header_of(doc, blobs, GlobalShaderCompiler.get_rd())
    var landing := SaSadSave.Landing.new(_refused, _refused, true)
    var err := SaSadSave.write_out(scratch, header, blobs, VERSIONS, landing)
    doc.free()
    return [err, landing]


## The address a content target names takes neither a side file beside it nor
## a rename, so the stand-in refuses both. Over a previous file the save still
## lands whole and reopens as the new picture, and nothing else is left beside
## it or in Sara's storage.
func test_a_save_to_a_content_address_lands_whole_with_nothing_beside_it() -> void:
    var first := LAST_STEP.painted(0.5)
    assert_eq(SaExport.save_sad(first, scratch, 0), OK, "A previous file is written at the target")
    first.free()
    var landing_and_error := poured(1.0)
    var landing: SaSadSave.Landing = landing_and_error[1]
    assert_eq(landing_and_error[0], OK, "The save to the content address takes")
    assert_true(landing.pours(scratch), "the target landed as a content address")
    assert_true(_asked.is_empty(), "with no rename or copy asked of it, read %s" % [_asked])
    assert_true(_last_step.opens_as(scratch, 1.0), "The file at the address reopens as the new picture, whole")
    assert_false(FileAccess.file_exists(scratch + SaSadFile.SAD_TEMP_SUFFIX), "No side file stands beside it")
    assert_false(FileAccess.file_exists(scratch + "1"), "and no numbered copy")
    assert_false(landing.side.begins_with(scratch), "The side file was written elsewhere, at %s" % landing.side)
    assert_false(FileAccess.file_exists(landing.side), "and is gone once poured")
    assert_true(SaSadSave.Landing.new().pours("content://com.android.externalstorage.documents/document/x.sad"))
    assert_false(SaSadSave.Landing.new().pours(scratch), "An ordinary path lands as before")


## A pour the address refuses, here a folder at the stand-in's name, keeps the
## whole picture in Sara's storage, and the painter's sentence names it and
## the address, never the previous file the address alone could tell of.
func test_a_pour_that_fails_keeps_the_picture_in_sara_s_storage_and_says_where() -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(scratch))
    var landing_and_error := poured(0.25)
    var landing: SaSadSave.Landing = landing_and_error[1]
    assert_false(landing_and_error[0] == OK, "The pour fails")
    assert_eq(landing.step, &"pour", "and the landing names the pour")
    assert_true(_last_step.opens_as(landing.side, 0.25), "The picture is kept whole at %s" % landing.side)
    var line := " ".join([landing.why(), SaSadFile.why_not_saved(scratch, landing.side)])
    assert_true(line.contains("Writing it into '%s' failed" % scratch), "The sentence names the address, read: %s" % line)
    assert_true(line.contains("kept at '%s'" % landing.side), "and where the picture is kept, read: %s" % line)
    assert_false(line.contains("previous file"), "and says nothing of a previous file, read: %s" % line)
    DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch))


## Two saves to an ordinary path keep the first at `.sad1`, byte for byte,
## and the second at the target, as every save did before.
func test_a_save_to_an_ordinary_path_keeps_its_sad1() -> void:
    var bytes: Array[PackedByteArray] = []
    for shade: float in [0.5, 0.75]:
        var doc := LAST_STEP.painted(shade)
        assert_eq(SaExport.save_sad(doc, scratch, VERSIONS), OK, "The file in %.2f is written" % shade)
        bytes.append(FileAccess.get_file_as_bytes(scratch))
        doc.free()
    assert_eq(FileAccess.get_file_as_bytes(scratch + "1"), bytes[0], "The first save is kept at .sad1")
    assert_true(_last_step.opens_as(scratch, 0.75), "and the second reopens at the target")
    assert_false(FileAccess.file_exists(scratch + SaSadFile.SAD_TEMP_SUFFIX), "with no side file left")
