## An autosave rounds full precision colour as a save the
## painter asked for does, and leaves half precision colour as it was. Before
## the unit both autosave targets called `SaSadFile.save_in_background` with
## *rounds* false, so a save of the same document with *rounds* false is the
## file the integration tip's autosave wrote, and the autosave of a half
## precision document now writes those bytes exactly.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice: a save hashes and reads chunks back.
const REQUIRES_GPU := true

const Kept = preload("res://core/sad-file/tests/test_half_precision_and_the_autosaves_keep_every_bit.gd")

static var working: String = SaDataRoot.path("test_working.sad")
static var before_unit: String = SaDataRoot.path("test_before_the_unit.sad")

var _autosave: SaAutosave = null
var _doc: SaDocument = null


func after_each() -> void:
    SaSadFile.finish_saves()
    if _autosave != null:
        _autosave.discard_recovery()
        _autosave.free()
        _autosave = null
    if _doc != null:
        _doc.free()
        _doc = null
    for path: String in [working, working + "1", before_unit, SaAutosave.recovery_path_for(working)]:
        DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## Runs the autosave of *doc* once, to the working file when *to_working_file*
## holds and otherwise to the recovery copy, and answers its save.
func _autosave_now(doc: SaDocument, to_working_file: bool) -> SaSadSave:
    if _autosave == null:
        _autosave = SaAutosave.new()
        _autosave.follow_settings = false
        _autosave.attach(doc)
    _autosave.write_working_file = to_working_file
    doc.modified = true
    assert_eq(_autosave.save_now(), OK, "The autosave is asked for")
    var save: SaSadSave = SaSadSave._saves.back() if not SaSadSave._saves.is_empty() else null
    assert_true(SaSadFile.finish_saves(), "and it ends")
    assert_true(save != null and save.error == OK, "and writes its file")
    return save


## The bytes of the file at *path*.
static func _bytes(path: String) -> PackedByteArray:
    return FileAccess.get_file_as_bytes(path)


func test_an_autosave_of_a_half_precision_document_writes_the_bytes_it_wrote_before_the_unit() -> void:
    for to_working_file: bool in [false, true]:
        var where := "the working file" if to_working_file else "the recovery copy"
        _doc = Kept.painted(SaColorSpace.Depth.F16)
        _doc.file_path = working
        var old := SaSadFile.save_in_background(_doc, before_unit, 0, null, false, Callable(), false)
        assert_true(SaSadFile.finish_saves() and old.error == OK, "The save as the tip's autosave made it lands")
        _doc.file_path = working
        var save := _autosave_now(_doc, to_working_file)
        assert_true(save.rounds, "The autosave to %s is a rounding save" % where)
        var path := working if to_working_file else SaAutosave.recovery_path_for(working)
        var wrote := _bytes(path)
        assert_true(wrote.size() > 0, "The autosave to %s is on disk" % where)
        assert_eq(wrote, _bytes(before_unit), "The autosave to %s writes the bytes it wrote before the unit" % where)
        _autosave.discard_recovery()
        _autosave.free()
        _autosave = null
        _doc.free()
        _doc = null
        for gone: String in [working, working + "1", before_unit]:
            DirAccess.remove_absolute(ProjectSettings.globalize_path(gone))


func test_a_second_autosave_of_full_precision_colour_with_nothing_painted_copies_every_blob() -> void:
    _doc = Kept.painted(SaColorSpace.Depth.F32)
    _doc.file_path = working
    var first := _autosave_now(_doc, false)
    assert_true(first.rounds and first.reuse.encoded > 0, "The first autosave rounds and compresses the colour")
    var again := _autosave_now(_doc, false)
    assert_eq(again.reuse.encoded, 0, "The second autosave compresses nothing")
    assert_eq(again.reuse.copied, first.reuse.encoded, "and copies every blob the first wrote, rounded")
