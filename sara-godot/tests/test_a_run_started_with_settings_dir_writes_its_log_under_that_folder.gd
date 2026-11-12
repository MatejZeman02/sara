## A run started with --settings-dir writes its log under that
## folder and leaves the user folder alone.
##
## With the flag given, the log and its rotated copies land under the moved
## data root, <settings-dir>/data/logs/, and without the flag under Godot's
## own user folder. The door's reader and the note box's Export both follow
## SaTrail.log_path() and find the log in that folder.
##
## In tests/ because it proves the integration between SaDataRoot, SaRunLog,
## SaTrail, the door's log reader and SaNoteFile.
extends "res://tests/test_framework.gd"

const RunLog := preload("res://core/app/sa_run_log.gd")
const DoorLog := preload("res://harness/door/sa_door_log.gd")

var _scratch: String = ""


func before_each() -> void:
    _scratch = OS.get_temp_dir().path_join("sara-test-%d" % OS.get_process_id())
    DirAccess.make_dir_recursive_absolute(_scratch)


func after_each() -> void:
    _remove_recursive(_scratch)


func _remove_recursive(path: String) -> void:
    if not DirAccess.dir_exists_absolute(path):
        return
    for file in DirAccess.get_files_at(path):
        DirAccess.remove_absolute(path.path_join(file))
    for dir in DirAccess.get_directories_at(path):
        _remove_recursive(path.path_join(dir))
    DirAccess.remove_absolute(path)


func test_data_root_log_path_follows_moved_folder() -> void:
    var default_path := SaDataRoot.ENGINE_LOG
    if not SaDataRoot.moved():
        assert_eq(SaDataRoot.log_path(), default_path, "Without the flag, log is in the default user folder")
    else:
        var expected := SaDataRoot.folder().path_join("logs/godot.log")
        assert_eq(SaDataRoot.log_path(), expected, "With the flag, log is under data root logs")
        assert_true(SaDataRoot.log_path().begins_with(SaDataRoot.flag() + "/"), "and under the flag directory")


func test_writer_opens_log_under_scratch_settings_dir() -> void:
    var log_dir := _scratch.path_join("data/logs")
    var base := log_dir.path_join("godot.log")
    var writer := RunLog.Writer.open(base, 5)
    assert_not_null(writer, "Writer opens the log file")
    assert_true(DirAccess.dir_exists_absolute(log_dir), "The logs directory was created")
    assert_true(FileAccess.file_exists(base), "The godot.log file exists")
    assert_eq(writer.path, base, "The writer path is the target file")
    writer = null


func test_writer_rotates_and_keeps_beside_held_log_under_scratch_dir() -> void:
    var log_dir := _scratch.path_join("data/logs")
    var base := log_dir.path_join("godot.log")
    var writer1 := RunLog.Writer.open(base, 5)
    assert_not_null(writer1, "First writer opens")
    var writer2 := RunLog.Writer.open(base, 5)
    assert_not_null(writer2, "Second writer opens while first is open")
    var files := DirAccess.get_files_at(log_dir)
    assert_eq(files.size(), 2, "Two log files exist under the folder")
    assert_true(files.has("godot.log"), "godot.log exists")
    writer1 = null
    writer2 = null


func test_the_doors_reader_finds_the_log_at_satrail_log_path() -> void:
    var asked := OS.get_environment("SARA_LOG_FILE")
    assert_eq(DoorLog.path(), SaTrail.log_path(), "The door asks SaTrail.log_path()")
    var log_dir := _scratch.path_join("door_logs")
    var base := log_dir.path_join("godot.log")
    DirAccess.make_dir_recursive_absolute(log_dir)
    var file := FileAccess.open(base, FileAccess.WRITE)
    file.store_string("line 1\nline 2\n")
    file.close()
    OS.set_environment("SARA_LOG_FILE", "")
    var prev_setting: Variant = ProjectSettings.get_setting("debug/file_logging/log_path")
    ProjectSettings.set_setting("debug/file_logging/log_path", base)
    assert_eq(DoorLog.path(), base, "The door sees the updated setting")
    var read := DoorLog.read_since(0)
    assert_eq(read["lines"], ["line 1", "line 2"], "The door reads the lines from the moved log")
    ProjectSettings.set_setting("debug/file_logging/log_path", prev_setting)
    OS.set_environment("SARA_LOG_FILE", asked)


func test_the_note_box_export_finds_the_log_directory() -> void:
    var current_log := SaTrail.log_path()
    assert_eq(SaNoteFile.engine_log_dir(), current_log.get_base_dir(), "The note export asks SaTrail.log_path().get_base_dir()")
    var log_dir := _scratch.path_join("export_logs")
    DirAccess.make_dir_recursive_absolute(log_dir)
    var log_file := FileAccess.open(log_dir.path_join("godot.log"), FileAccess.WRITE)
    log_file.store_string("log content\n")
    log_file.close()
    var rot_file := FileAccess.open(log_dir.path_join("godot2026-10-20T10.00.00.log"), FileAccess.WRITE)
    rot_file.store_string("rotated content\n")
    rot_file.close()
    var found := SaNoteFile.log_files_for(log_dir)
    assert_eq(found.size(), 2, "Note export finds the current and rotated logs")
    assert_true(found.has("godot.log"), "finds godot.log")
    assert_true(found.has("godot2026-10-20T10.00.00.log"), "finds rotated log")
