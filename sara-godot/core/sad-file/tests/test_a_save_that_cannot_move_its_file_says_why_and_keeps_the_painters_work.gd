## A save whose side file cannot be moved onto its target
## names the step that failed and the engine's error, tries a copy instead,
## and leaves the side file beside the document when the copy fails too. A
## copy that takes leaves a whole file at the target and no side file.
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

var _said: Array[String] = []
var _last_step := LAST_STEP.new()


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
    for path: String in [at, at + "1", at + "2", at + SaSadFile.SAD_TEMP_SUFFIX]:
        DirAccess.remove_absolute(path)


func _heard(line: String, _kind: SaProblems.Kind) -> void:
    if line.begins_with("SaSadSave"):
        _said.append(line)


## Writes the document of that suite in *shade* over [member scratch] through
## *landing*, and answers the error.
func written_with(shade: float, landing: SaSadSave.Landing) -> Error:
    var doc := LAST_STEP.painted(shade)
    var blobs := PackedByteArray()
    var header := SaSadFile.header_of(doc, blobs, GlobalShaderCompiler.get_rd())
    var err := SaSadSave.write_out(scratch, header, blobs, VERSIONS, landing)
    doc.free()
    return err


## A folder at the target's name fails the move and the copy alike, whatever
## the platform. The painter's line names the move, the side file, the target
## and the engine's error of each step, and the side file is still there,
## whole.
func test_a_move_and_a_copy_that_both_fail_name_the_steps_and_keep_the_side_file() -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(scratch))
    var doc := LAST_STEP.painted(0.25)
    SaProblems.announce = false
    SaProblems.attach_sink(_heard)
    var ended: Array[Error] = []
    SaSadSave.start(doc, scratch, VERSIONS, null, false, func(err: Error) -> void: ended.append(err))
    assert_true(SaSadSave.finish_all(), "The save ends")
    SaProblems.detach_sink()
    assert_false(ended.is_empty() or ended[0] == OK, "with an error, a folder standing at its name")
    var kept := scratch + SaSadFile.SAD_TEMP_SUFFIX
    assert_true(_last_step.opens_as(kept, 0.25), "The side file is still at %s and opens as the document" % kept)
    assert_eq(_said.size(), 1, "One problem is reported, read %s" % [_said])
    var line := _said[0] if not _said.is_empty() else ""
    var moving := "Moving '%s' onto '%s' failed (" % [kept, scratch]
    assert_true(line.contains(moving), "The line names the move and both paths, read: %s" % line)
    assert_true(line.contains("Copying it into place failed too ("), "and the copy that followed, read: %s" % line)
    assert_false(line.contains("()"), "each with the engine's error named, read: %s" % line)
    assert_true(line.contains("kept at '%s'" % kept), "and says where the picture is, read: %s" % line)
    doc.free()


## The move onto the target alone is refused, the copy takes: the target
## holds the new picture whole, the previous one is at `.sad1`, and no side
## file is left.
func test_a_move_that_fails_and_a_copy_that_takes_leave_a_whole_file_and_no_side_file() -> void:
    var previous := written_with(0.5, SaSadSave.Landing.new())
    assert_eq(previous, OK, "The previous file is written")
    var before := FileAccess.get_file_as_bytes(scratch)
    var kept := scratch + SaSadFile.SAD_TEMP_SUFFIX
    var onto_the_target := func(from: String, to: String) -> Error:
        return ERR_FILE_CANT_WRITE if from == kept else DirAccess.rename_absolute(from, to)
    var landing := SaSadSave.Landing.new(onto_the_target)
    assert_eq(written_with(1.0, landing), OK, "The save takes through the copy")
    assert_eq(landing.move_error, ERR_FILE_CANT_WRITE, "after the move failed")
    assert_true(landing.copied, "and the landing says it copied")
    assert_true(_last_step.opens_as(scratch, 1.0), "The target opens as the new picture, whole")
    assert_false(FileAccess.file_exists(kept), "No side file is left")
    assert_eq(FileAccess.get_file_as_bytes(scratch + "1"), before, "The previous file is kept at .sad1")


## A folder at `.sad1` fails the keep of the previous version. The move still
## writes the new picture over the target, and the landing names the keep and
## its error.
func test_a_keep_that_fails_is_named_and_the_save_still_lands() -> void:
    assert_eq(written_with(0.5, SaSadSave.Landing.new()), OK, "The previous file is written")
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(scratch + "1"))
    var landing := SaSadSave.Landing.new()
    assert_eq(written_with(1.0, landing), OK, "The save lands")
    assert_eq(landing.step, &"keep", "and the step that failed is the keep")
    assert_false(landing.keep_error == OK, "with the engine's error")
    var why := landing.why()
    assert_true(why.begins_with("Keeping the previous version failed ("), "and the sentence names it, read: %s" % why)
    assert_true(_last_step.opens_as(scratch, 1.0), "The target holds the new picture")
