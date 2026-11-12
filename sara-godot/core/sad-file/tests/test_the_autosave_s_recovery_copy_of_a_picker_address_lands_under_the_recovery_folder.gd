## A document opened or saved through Android's picker keeps its `content://`
## address, and a recovery copy made up beside it names no document and was
## never granted, so the write failed and the work since the last Save was lost
## to a crash. The copy goes under the recovery folder, named for the whole
## address, and the next start finds it there for a Recent entry of that
## address. On Linux the address opens nothing, which is as an ungranted one
## behaves on the tablet, so the suite reads the paths and the folder.
extends "res://tests/test_framework.gd"

## The autosave writes a `.sad`, which reads every chunk back off the GPU.
const REQUIRES_GPU := true

const NAMED := "content://com.android.externalstorage.documents/document/primary%3ADocuments%2Fstudy.sad"
const NUMBERED := "content://com.android.providers.downloads.documents/document/msf%3A1000000033"


func _remove(path: String) -> void:
    if FileAccess.file_exists(path):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func after_each() -> void:
    _remove(SaAutosave.recovery_path_for(NAMED))
    _remove(SaAutosave.recovery_path_for(NUMBERED))


func test_two_addresses_have_two_copies_under_the_recovery_folder() -> void:
    var named := SaAutosave.recovery_path_for(NAMED)
    var numbered := SaAutosave.recovery_path_for(NUMBERED)
    var folder := SaAutosave.recovery_dir()
    assert_true(named.begins_with(folder), "an address with an extension under the recovery folder: %s" % named)
    assert_true(numbered.begins_with(folder), "a Downloads msf address under it too: %s" % numbered)
    assert_true(named != numbered, "two addresses, two copies")
    assert_false(named.begins_with("content://"), "and neither poured into an address")
    assert_true(named.get_file().contains("study"), "the copy says which document it was: %s" % named.get_file())
    assert_true(named.ends_with(SaAutosave.RECOVERY_SUFFIX), "and ends as every recovery copy does")
    var same_name := SaAutosave.recovery_path_for(NAMED.replace("Documents", "Pictures"))
    assert_true(same_name != named, "two documents of one name in two folders keep two copies")
    var beside := SaAutosave.recovery_path_for(SaDataRoot.path("doc.sad"))
    assert_eq(beside, SaDataRoot.path("doc.autosave.sad"), "a plain path keeps its copy beside the file")


func test_an_autosave_of_an_address_is_written_and_offered_at_the_next_start() -> void:
    var easel := SaEasel.create_default(Vector2i(128, 128))
    var doc: SaDocument = easel.document
    doc.mark_saved(NAMED)
    var autosave := SaAutosave.new()
    autosave.follow_settings = false
    autosave.write_working_file = false
    autosave.attach(doc)
    easel.add_child(autosave)
    doc.fill_layer(Color.RED)
    assert_true(doc.modified, "the document has unsaved work")
    assert_eq(autosave.save_now(), OK, "the autosave is asked for")
    assert_true(SaSadFile.finish_saves(), "and the save in the background ends")
    var copy := autosave.last_written
    assert_eq(copy, SaAutosave.recovery_path_for(NAMED), "the copy kept is the address's: %s" % copy)
    assert_true(copy.begins_with(SaAutosave.recovery_dir()), "under the recovery folder")
    assert_true(FileAccess.file_exists(copy), "and on disk")
    var offered := SaAutosave.find_recoveries([NAMED]).filter(func(entry: Dictionary) -> bool: return entry["copy"] == copy)
    assert_eq(offered.size(), 1, "the next start offers it once")
    assert_eq(offered[0]["original"], NAMED, "as the address's own")
    assert_eq(doc.file_path, NAMED, "the document still the address's")
    autosave.discard_recovery()
    assert_false(FileAccess.file_exists(copy), "and discarding removes the copy")
    easel.free()
