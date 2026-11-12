## A save asked for while another runs waits for it, a quit
## asked for during a save waits for every save to end, and a save that fails
## says so in the problems line and leaves the old file whole.
##
## The quit is `SaSadSave.after_all`, the call `SaDocumentFiles.confirm_discard`
## hands every quit, File > New and File > Open to.
extends "res://tests/test_framework.gd"

const SaveSuite = preload(
    "res://core/sad-file/tests/test_a_save_in_the_background_holds_the_document_as_it_was_at_the_snapshot.gd"
)

## Needs the main RenderingDevice, for the reads the saves ask.
const REQUIRES_GPU := true

static var scratch: Array[String] = [
    SaDataRoot.path("test_row_1.sad"), SaDataRoot.path("test_row_2.sad"), SaDataRoot.path("test_row_3.sad")
]

## What happened, in order: a save's number as it ended, and "quit".
var _heard: Array[String] = []


func before_each() -> void:
    SaSadSave.finish_all()
    _heard.clear()


func after_each() -> void:
    SaSadSave.finish_all()
    for path in scratch:
        DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
        DirAccess.remove_absolute(ProjectSettings.globalize_path(path + "1"))
        DirAccess.remove_absolute(ProjectSettings.globalize_path(path + SaSadFile.SAD_TEMP_SUFFIX))


func _ended(err: Error, number: int) -> void:
    _heard.append("%d %s" % [number, error_string(err)])


func _quit() -> void:
    _heard.append("quit")


func test_two_saves_in_a_row_and_a_quit_during_a_third_write_three_whole_files() -> void:
    var doc := SaveSuite.sixty_layers()
    assert_eq(SaveSuite.paint_layers(doc).size(), SaveSuite.LAYERS, "The document has its sixty layers")
    SaSadSave.start(doc, scratch[0], 0, null, false, _ended.bind(1))
    SaSadSave.start(doc, scratch[1], 0, null, false, _ended.bind(2))
    assert_eq(_heard, [] as Array[String], "Two saves asked in a row run one after the other, neither ended yet")
    var until := Time.get_ticks_msec() + 60000
    while _heard.size() < 2 and Time.get_ticks_msec() < until:
        SaSadSave.turn()
        OS.delay_usec(500)
    assert_eq(_heard, ["1 OK", "2 OK"] as Array[String], "The first ends before the second, both without an error")

    SaSadSave.start(doc, scratch[2], 0, null, false, _ended.bind(3))
    assert_true(SaSadSave.is_running(), "The third save runs")
    SaSadSave.after_all(_quit, "quitting")
    assert_eq(_heard.size(), 2, "and the quit asked during it waits for it")
    assert_true(SaSadSave.finish_all(), "The third save ends")
    assert_eq(_heard, ["1 OK", "2 OK", "3 OK", "quit"] as Array[String], "and the quit goes on only after it")

    for path in scratch:
        assert_false(FileAccess.file_exists(path + SaSadFile.SAD_TEMP_SUFFIX), "No side file is left beside %s" % path.get_file())
        var reopened := SaDocument.new()
        assert_eq(SaExport.load_sad(reopened, path, SaCompositor.new()), OK, "%s opens" % path.get_file())
        var back := SaveSuite.paint_layers(reopened)
        var same := 0
        for index in back.size():
            if SaveSuite.texel(back[index]).is_equal_approx(SaveSuite.colour_of(index)):
                same += 1
        assert_eq(same, SaveSuite.LAYERS, "%s is whole, every layer holding its colour" % path.get_file())
        reopened.free()
    doc.free()


func test_a_quit_with_no_save_running_goes_on_at_once() -> void:
    SaSadSave.after_all(_quit, "quitting")
    assert_eq(_heard, ["quit"] as Array[String], "A quit waits for nothing when no save runs")


func test_a_save_that_fails_says_so_and_leaves_the_old_file_whole() -> void:
    var doc := SaveSuite.sixty_layers()
    assert_eq(SaveSuite.paint_layers(doc).size(), SaveSuite.LAYERS, "The document has its sixty layers")
    assert_eq(SaExport.save_sad(doc, scratch[0], 0), OK, "The old file is written")
    var old := FileAccess.get_file_as_bytes(scratch[0])
    # A folder where the side file goes, so the save cannot open it.
    DirAccess.make_dir_recursive_absolute(scratch[0] + SaSadFile.SAD_TEMP_SUFFIX)
    var kept := SaProblems.pending.size()
    var sink_was_there := SaProblems.has_sink()
    SaProblems.announce = false
    doc.modified = true
    SaSadSave.start(doc, scratch[0], 0, null, true, _ended.bind(1))
    assert_true(SaSadSave.finish_all(), "The save ends")
    SaProblems.announce = true
    assert_eq(_heard.size(), 1, "once")
    assert_false(_heard[0] == "1 OK" if not _heard.is_empty() else true, "with an error")
    if not sink_was_there:
        var said := SaProblems.pending.slice(kept)
        assert_eq(said.size(), 1, "The problems line says so")
        assert_true(said[0].contains("previous file is untouched") if not said.is_empty() else false, "naming the old file")
        SaProblems.pending = SaProblems.pending.slice(0, kept)
    assert_true(doc.modified, "The document is not marked saved by a save that failed")
    assert_eq(FileAccess.get_file_as_bytes(scratch[0]), old, "and the old file is as it was")
    doc.free()
