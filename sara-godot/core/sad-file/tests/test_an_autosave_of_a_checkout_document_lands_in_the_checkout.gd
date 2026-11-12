## A document opened from `res://` autosaves under the recovery folder, as an
## untitled one does, and never beside its file in the checkout.
##
## The Voronoi notebook's test ran four minutes against the
## box blur fixture and left `box-blur-exercise.autosave.sad` in the clone,
## because the copy went beside any saved document, a `res://` one included.
## In an exported build `res://` is read only and that write fails. The clock
## is handed to `tick()`, so the interval passes in a call, and the quiet the
## save waits for is the Idle After preference's, read from it.
extends "res://tests/test_framework.gd"

## The autosave writes a `.sad`, which reads every chunk back off the GPU.
const REQUIRES_GPU := true

const FIXTURE := "res://scenarios/fixtures/box-blur-exercise.sad"
const BESIDE := "res://scenarios/fixtures/box-blur-exercise.autosave.sad"


func _remove(path: String) -> void:
    if FileAccess.file_exists(path):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## The fixture opened as the app opens a file, then painted on, so the
## document is the fixture's with unsaved changes.
func _open_fixture(write_working_file: bool) -> Array:
    var easel := SaEasel.create_default(Vector2i(128, 128))
    var doc: SaDocument = easel.document
    assert_eq(SaExport.load_sad(doc, FIXTURE), OK, "the fixture opens")
    doc.mark_saved(FIXTURE)
    var autosave := SaAutosave.new()
    autosave.follow_settings = false
    autosave.interval_seconds = 60.0
    autosave.write_working_file = write_working_file
    autosave.attach(doc)
    easel.add_child(autosave)
    doc.fill_layer(Color.RED)
    autosave.note_activity(0)
    return [easel, autosave]


## The moment the painter has been quiet long enough, counted from the last
## activity at nothing, whatever Idle After the profile holds.
func _quiet_passed() -> int:
    return int(SaSettings.idle_after_seconds * 1000.0)


func after_each() -> void:
    _remove(BESIDE)
    _remove(SaAutosave.recovery_path_for(FIXTURE))


func test_the_copy_of_a_fixture_lands_under_the_recovery_folder() -> void:
    var fixture_time := FileAccess.get_modified_time(FIXTURE)
    var pair := _open_fixture(false)
    var doc: SaDocument = pair[0].document
    var autosave: SaAutosave = pair[1]
    assert_true(autosave.tick(120.0, _quiet_passed()), "Two minutes of work and the painter stopped, and it fires")
    assert_true(SaSadFile.finish_saves(), "and the save in the background ends")
    var copy := autosave.last_written
    assert_true(copy.begins_with(SaAutosave.recovery_dir()), "under the recovery folder, as an untitled one: %s" % copy)
    assert_true(FileAccess.file_exists(autosave.last_written), "onto disk")
    assert_false(FileAccess.file_exists(BESIDE), "and nothing beside the fixture")
    assert_eq(FileAccess.get_modified_time(FIXTURE), fixture_time, "the fixture itself untouched")
    assert_eq(doc.file_path, FIXTURE, "the document still the fixture's")
    assert_true(doc.modified, "with its changes unsaved")
    autosave.discard_recovery()
    assert_false(FileAccess.file_exists(SaAutosave.recovery_path_for(FIXTURE)), "and discarding removes the copy")
    pair[0].free()


func test_writing_the_working_file_never_writes_a_fixture() -> void:
    var fixture_time := FileAccess.get_modified_time(FIXTURE)
    var pair := _open_fixture(true)
    var doc: SaDocument = pair[0].document
    var autosave: SaAutosave = pair[1]
    assert_true(autosave.tick(120.0, _quiet_passed()), "The working file setting on, it still fires")
    assert_true(SaSadFile.finish_saves(), "and the save in the background ends")
    assert_true(autosave.last_written.begins_with(SaAutosave.recovery_dir()), "into the recovery folder, not the fixture")
    assert_eq(FileAccess.get_modified_time(FIXTURE), fixture_time, "the fixture untouched")
    assert_false(FileAccess.file_exists(BESIDE), "and nothing beside it")
    assert_true(doc.modified, "and the document not marked saved, since its file was not written")
    autosave.discard_recovery()
    pair[0].free()


func test_two_fixtures_of_one_name_keep_two_copies() -> void:
    var one := SaAutosave.recovery_path_for("res://a/doc.sad")
    var two := SaAutosave.recovery_path_for("res://b/doc.sad")
    assert_true(one != two, "a copy named for the whole path")
    assert_true(one.begins_with(SaAutosave.recovery_dir()), "and under the recovery folder")
    var beside := SaAutosave.recovery_path_for(SaDataRoot.path("doc.sad"))
    assert_eq(beside, SaDataRoot.path("doc.autosave.sad"), "a file outside res:// keeps its copy beside it")


func test_the_copy_is_offered_once_with_its_fixture() -> void:
    var pair := _open_fixture(false)
    var autosave: SaAutosave = pair[1]
    assert_true(autosave.tick(120.0, _quiet_passed()), "the copy written")
    assert_true(SaSadFile.finish_saves(), "and the save in the background ends")
    var copy := autosave.last_written
    var with_recent := SaAutosave.find_recoveries([FIXTURE]).filter(func(entry: Dictionary) -> bool: return entry["copy"] == copy)
    assert_eq(with_recent.size(), 1, "the fixture among the recent files, its copy offered once")
    assert_eq(with_recent[0]["original"], FIXTURE, "as the fixture's")
    var alone := SaAutosave.find_recoveries([]).filter(func(entry: Dictionary) -> bool: return entry["copy"] == copy)
    assert_eq(alone.size(), 1, "without it, still offered")
    assert_eq(alone[0]["original"], "", "as an untitled copy")
    autosave.discard_recovery()
    pair[0].free()
