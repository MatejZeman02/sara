## A second Sara never takes the log of one already running.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Each case opens a writer on a log folder of its own under the temporary
## folder, with the log in it written as a Sara would have left it, and reads
## what the open did to the folder. The gate's own run has `SARA_LOG_FILE`
## set, so its `SaRunLog` opened nothing and no case here touches the gate's
## log. `scripts/test_agent_help_leaves_a_running_saras_log_alone.py` starts
## two real Saras, the one this was filed from.
extends "res://tests/test_framework.gd"

const RunLog := preload("res://core/app/sa_run_log.gd")

var _folder: String = ""
var _base: String = ""


func before_each() -> void:
    _folder = OS.get_temp_dir().path_join("sara-d17-log-%d" % OS.get_process_id())
    DirAccess.make_dir_recursive_absolute(_folder)
    for name in DirAccess.get_files_at(_folder):
        DirAccess.remove_absolute(_folder.path_join(name))
    _base = _folder.path_join("godot.log")


func after_each() -> void:
    for name in DirAccess.get_files_at(_folder):
        DirAccess.remove_absolute(_folder.path_join(name))
    DirAccess.remove_absolute(_folder)


## A process that runs for as long as the machine does and is never this one:
## init on Linux, and System on Windows.
static func _always_running() -> int:
    return 4 if OS.get_name() == "Windows" else 1


## A log as a Sara leaves it: its opening line naming *pid*, a line of its own,
## and the closing line when *closed*.
func _leave_log(pid: int, closed: bool) -> String:
    var text := "%s%d at 2026-09-29 12:13:40\nSaAgentDoor: client connected\n" % [RunLog.Writer.OPENED, pid]
    if closed:
        text += "%s%d\n" % [RunLog.Writer.CLOSED, pid]
    _write(_base, text)
    return text


static func _write(at: String, text: String) -> void:
    var file := FileAccess.open(at, FileAccess.WRITE)
    file.store_string(text)
    file.close()


func _names() -> PackedStringArray:
    var names := DirAccess.get_files_at(_folder)
    names.sort()
    return names


func test_a_log_another_running_sara_holds_is_left_whole_and_in_place() -> void:
    var holder := _always_running()
    assert_true(SaProcess.another_runs(holder), "Process %d runs and is not this one" % holder)
    var left := _leave_log(holder, false)
    assert_eq(RunLog.Writer.holder(_base), holder, "The log names the Sara holding it")

    var writer := RunLog.Writer.open(_base, 10)
    assert_not_null(writer, "The second Sara opens a log")
    assert_eq(FileAccess.get_file_as_string(_base), left, "The first one's log is whole and in place")
    var own := writer.path.get_file()
    assert_true(own.begins_with("godot2") and own.ends_with(".%d.log" % OS.get_process_id()), "Its own is %s" % own)
    assert_eq(_names(), PackedStringArray(["godot.log", own]), "and nothing is set aside")
    writer = null
    var text := FileAccess.get_file_as_string(_folder.path_join(own))
    assert_true(text.begins_with("%s%d at " % [RunLog.Writer.OPENED, OS.get_process_id()]), "It names this Sara")
    assert_true(text.ends_with("%s%d\n" % [RunLog.Writer.CLOSED, OS.get_process_id()]), "and says it closed")


func test_a_closed_log_is_set_aside_and_opened_afresh() -> void:
    var left := _leave_log(_always_running(), true)
    assert_eq(RunLog.Writer.holder(_base), 0, "A closed log names no holder")
    var writer := RunLog.Writer.open(_base, 10)
    assert_eq(writer.path, _base, "The start takes the log")
    var names := _names()
    assert_eq(names.size(), 2, "beside the one it set aside: %s" % ", ".join(names))
    assert_eq(FileAccess.get_file_as_string(_folder.path_join(names[1])), left, "whole")
    assert_true(names[1].begins_with("godot2") and names[1].count(".") == 3, "under the time: %s" % names[1])
    writer = null


func test_a_log_whose_sara_died_is_set_aside() -> void:
    # Above any process id Linux or Windows hands out.
    var gone := 0x7ffffff0
    assert_false(SaProcess.runs(gone), "Process %d does not run" % gone)
    _leave_log(gone, false)
    assert_eq(RunLog.Writer.holder(_base), gone, "The log of a Sara that crashed names it")
    var writer := RunLog.Writer.open(_base, 10)
    assert_eq(writer.path, _base, "and the next start takes the log")
    writer = null


func test_a_log_the_engine_wrote_is_set_aside() -> void:
    _write(_base, "Godot Engine v4.7.stable.official.5b4e0cb0f - https://godotengine.org\n\n")
    assert_eq(RunLog.Writer.holder(_base), 0, "A log without the opening line names no holder")
    var writer := RunLog.Writer.open(_base, 10)
    assert_eq(writer.path, _base, "and a start takes it")
    writer = null


func test_the_folder_keeps_as_many_logs_as_the_setting_says() -> void:
    for second in 12:
        _write(_folder.path_join("godot2026-09-01T00.00.%02d.log" % second), "old\n")
    _leave_log(_always_running(), true)
    assert_not_null(RunLog.Writer.open(_base, 10), "A start opens the log")
    var names := _names()
    assert_eq(names.size(), 10, "Ten logs, the current one among them: %s" % ", ".join(names))
    assert_false(names.has("godot2026-09-01T00.00.02.log"), "The oldest go")
    assert_true(names.has("godot2026-09-01T00.00.11.log"), "and the newest stay")


## What the engine's logger wrote for the same calls, read off its own file
## under `--log-file` on 2026-09-29. The coloured line is what the engine
## handed a logger for `print_rich("[color=#ff0000]red[/color] and [b]bold[/b]")`
## that day, handed over here so the gate's output carries no line of it.
func test_the_log_reads_as_the_engines_did() -> void:
    var writer := RunLog.Writer.open(_base, 10)
    writer._log_message("\u001b[38;2;255;0;0mred\u001b[39m and \u001b[1mbold\u001b[22m\u001b[0m\n", false)
    var here := Engine.capture_script_backtraces()
    var raised_at := "core/variant/variant_utility.cpp"
    writer._log_error("push_error", raised_at, 1023, "an error", "", false, Logger.ERROR_TYPE_ERROR, here)
    writer._log_error("f", "a.gd", 7, "p_code", "a warning", false, Logger.ERROR_TYPE_WARNING, [])
    writer._log_error("g", "b.gd", 9, "", "a script error", false, Logger.ERROR_TYPE_SCRIPT, [])
    writer = null
    var lines := FileAccess.get_file_as_string(_base).split("\n")
    assert_eq(lines[1], "red and bold", "A print_rich line reaches the file without its colour codes")
    assert_eq(lines[2], "ERROR: an error", "An error without a rationale says its code")
    assert_eq(lines[3], "   at: push_error (core/variant/variant_utility.cpp:1023)", "and where it was raised")
    assert_eq(lines[4], "   GDScript backtrace (most recent call first):", "then the script's backtrace")
    assert_true(lines[5].begins_with("       [0] test_the_log_reads_as_the_engines_did ("), "from its top frame: %s" % lines[5])
    var at := lines.find("WARNING: a warning")
    assert_true(at > 5, "A warning says its rationale")
    assert_eq(lines[at + 1], "   at: f (a.gd:7)", "and where")
    assert_eq(lines[at + 2], "SCRIPT ERROR: a script error", "A script error is named as the engine names it")


func test_the_engine_opens_no_log_of_its_own() -> void:
    assert_false(
        bool(ProjectSettings.get_setting_with_override("debug/file_logging/enable_file_logging")),
        "The engine's file logging is off on this platform, its .pc override included"
    )
    var project := FileAccess.get_file_as_string("res://project.godot")
    var autoloads := project.get_slice("[autoload]", 1).strip_edges()
    assert_true(autoloads.begins_with('SaRunLog="*res://core/app/sa_run_log.gd"'), "and the run log is the first autoload")
