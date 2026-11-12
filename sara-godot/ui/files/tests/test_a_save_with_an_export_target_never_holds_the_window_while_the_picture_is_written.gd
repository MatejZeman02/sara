## A save with an export target never holds the window while
## the picture is written.
##
## A surface the files flow drives the way main builds it, and File > Export
## Target's dialog naming a 16-bit target. The `.sad` is driven to its end
## with `SaSadSave.finish_all` alone, which leaves the target's encode on its
## worker, and `SaExportTargets.finish_writes` then waits for it, as the frames
## after a save would.
extends "res://tests/test_framework.gd"

## The saves and the target are read back off the card.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

## Large enough that the 16-bit encoder takes far longer than a turn of this
## suite, so the target is still being written when the `.sad` has ended.
const SIDE := 1024
## The last chunk every PNG ends with, its length, type and CRC.
const IEND := [0, 0, 0, 0, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82]

var _surface: SaSurface = null
var _documents: SaDocuments = null
var _flow: SaDocumentFiles = null
var _dialog: SaExportTargetsDialog = null
var _line: SaStatusLine = null
var _folder := ""
var _saved_recent: Array = []
## What the save's `then` found on disk when it ran, the file's bytes.
var _found_then := PackedByteArray()
var _then_ran := false


func before_each() -> void:
    _saved_recent = SaSettings.recent_files()
    _surface = Fixtures.make_surface(Vector2i(SIDE, SIDE))
    _surface.get_document().fill_layer(Color(0.2, 0.5, 0.7, 1.0))
    _documents = SaDocuments.new()
    _documents.add(_surface)
    _folder = OS.get_temp_dir().path_join("sara-%d" % OS.get_process_id())
    DirAccess.make_dir_recursive_absolute(_folder)
    _flow = SaDocumentFiles.new(Callable(), _documents)
    EventBus.add_child(_flow)
    _dialog = SaExportTargetsDialog.new()
    _flow.add_child(_dialog)
    _line = SaStatusLine.new(func() -> SaSurface: return _surface)
    EventBus.add_child(_line)
    _found_then = PackedByteArray()
    _then_ran = false


func after_each() -> void:
    SaSadFile.finish_saves()
    if _line != null:
        _line.free()
        _line = null
    if _flow != null:
        _flow.free()
        _flow = null
    _dialog = null
    Fixtures.teardown(_surface)
    _surface = null
    _documents = null
    for file in DirAccess.get_files_at(_folder):
        DirAccess.remove_absolute(_folder.path_join(file))
    DirAccess.remove_absolute(_folder)
    for path: String in SaSettings.recent_files():
        SaSettings.remove_recent_file(str(path))
    for i in range(_saved_recent.size() - 1, -1, -1):
        SaSettings.add_recent_file(str(_saved_recent[i]))


## Saves the document at *sad* as Ctrl+S does once it has a file, with *then*
## after it, and drives the `.sad` alone to its end.
func _save(sad: String, then: Callable) -> void:
    _surface.get_document().mark_saved(sad)
    _surface.get_document().modified = true
    _flow.save_document(then, _surface.get_document())
    assert_true(SaSadSave.finish_all(), "The .sad is written")


func _then_reads(target: String) -> void:
    _then_ran = true
    _found_then = FileAccess.get_file_as_bytes(target)


func _whole_png(bytes: PackedByteArray) -> bool:
    return bytes.size() > IEND.size() and bytes.slice(bytes.size() - IEND.size()) == PackedByteArray(IEND)


func test_the_quit_after_save_waits_until_the_target_is_whole() -> void:
    var target := _folder.path_join("hero.png")
    _dialog.open_for(_surface.get_document())
    _dialog.add_target(target, 16)
    _save(_folder.path_join("hero.sad"), _then_reads.bind(target))
    assert_true(SaExportTargets.writing(), "With the .sad whole the target is still being written, on its worker")
    assert_true(SaSadFile.saving(), "and the save door says a save is still under way")
    assert_false(_then_ran, "so the quit after the save has not run")
    assert_true(SaExportTargets.finish_writes(), "The target's write ends")
    assert_true(_then_ran, "and then the quit runs")
    assert_true(_whole_png(_found_then), "finding the target whole on disk, %d bytes" % _found_then.size())
    assert_eq(_found_then, FileAccess.get_file_as_bytes(target), "the file as it stays")
    assert_false(SaSadFile.saving(), "and nothing is left being written")


func test_the_target_is_the_png_file_export_writes() -> void:
    var target := _folder.path_join("sky.png")
    _dialog.open_for(_surface.get_document())
    _dialog.add_target(target, 16)
    _save(_folder.path_join("sky.sad"), Callable())
    assert_true(SaExportTargets.finish_writes(), "The target's write ends")
    var exported := _folder.path_join("exported.png")
    var write := SaImageFormat.Write.new()
    write.depth = 16
    write.mapping = SaGamutMapping.for_export(SaSettings.gamut_mapping, false)
    var format := SaImageFormatRegistry.shared().find(&"png")
    assert_eq(format.writer.call(_surface.get_document().get_parent() as SaEasel, exported, write), OK, "File > Export writes")
    # The metadata names the second the file was made, so the picture alone
    # is compared, and the header that names its depth.
    var written := Image.load_from_file(target)
    var expected := Image.load_from_file(exported)
    assert_not_null(written, "The target opens as a picture")
    assert_eq(FileAccess.get_file_as_bytes(target)[24], 16, "at 16 bits a channel")
    assert_eq(written.get_data(), expected.get_data(), "holding the pixels File > Export writes")


func test_a_quit_asked_while_the_target_is_written_waits_for_it() -> void:
    var target := _folder.path_join("tree.png")
    _dialog.open_for(_surface.get_document())
    _dialog.add_target(target, 16)
    _save(_folder.path_join("tree.sad"), Callable())
    var quit := [false]
    SaSadFile.after_saves(func() -> void: quit[0] = true, "quitting")
    assert_false(quit[0], "A quit asked once the .sad is whole waits for the target")
    assert_true(SaExportTargets.finish_writes(), "The target's write ends")
    assert_true(quit[0], "and then the quit runs")
    assert_true(_whole_png(FileAccess.get_file_as_bytes(target)), "with the target whole")


func test_a_target_that_fails_on_the_worker_is_named_on_the_status_line() -> void:
    var blocker := _folder.path_join("blocker")
    var file := FileAccess.open(blocker, FileAccess.WRITE)
    file.store_string("a file where the target's folder would be")
    file.close()
    var target := blocker.path_join("sea.png")
    _dialog.open_for(_surface.get_document())
    _dialog.add_target(target, 16)
    var sad := _folder.path_join("sea.sad")
    _save(sad, _then_reads.bind(target))
    assert_true(SaExportTargets.finish_writes(), "The target's write ends")
    assert_true(_then_ran, "The quit after the save still runs")
    assert_true(FileAccess.file_exists(sad), "The .sad is written")
    assert_false(_surface.get_document().modified, "and the document is saved")
    assert_false(FileAccess.file_exists(target), "The target is not")
    assert_true(_line.save_label.visible, "The status line speaks")
    assert_true(_line.save_label.text.contains(target), "and names the target as the dialog made it: %s" % _line.save_label.text)
    assert_true(_line.save_label.text.contains("sea.sad"), "beside the file saved")
