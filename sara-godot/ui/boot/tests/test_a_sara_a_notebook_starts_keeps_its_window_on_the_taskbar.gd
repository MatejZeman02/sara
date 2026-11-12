## A Sara a notebook starts opens with its main window minimised and asks for
## no raise, and every other start is left as it was.
##
## `sara.py` puts `--in-background` after `--agent-door` when it starts Sara
## itself. These cases feed the reading lists, since a suite cannot start a
## process. The window on the taskbar under the nested weston is in the unit's
## record, read through the door.
extends "res://tests/test_framework.gd"

const BackgroundStart := preload("res://ui/boot/sa_background_start.gd")

static var scratch_probe: String = SaDataRoot.path("background_start_probe.sad")


func before_each() -> void:
    var file := FileAccess.open(scratch_probe, FileAccess.WRITE)
    file.store_string("not really a document")
    file.close()


func after_each() -> void:
    DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch_probe))


func test_the_flag_after_the_door_asks_for_the_window_minimised_and_no_raise() -> void:
    var asked := BackgroundStart.asks(PackedStringArray(["--agent-door", "--in-background"]))
    assert_eq(asked, {"minimised": true, "raise": false}, "the arguments `sara.py` starts Sara with")
    asked = BackgroundStart.asks(PackedStringArray(["--agent-door", "--in-background", "--agent-idle=300"]))
    assert_true(asked["minimised"], "with an option after it")


func test_the_door_without_the_flag_asks_for_neither() -> void:
    var neither := {"minimised": false, "raise": false}
    assert_eq(BackgroundStart.asks(PackedStringArray(["--agent-door"])), neither, "a painter's own door")


func test_a_file_s_path_alone_asks_for_neither() -> void:
    var neither := {"minimised": false, "raise": false}
    assert_eq(BackgroundStart.asks(PackedStringArray([scratch_probe])), neither, "a file from a file manager")
    assert_eq(BackgroundStart.asks(PackedStringArray()), neither, "the desktop entry")


## Only the whole flag keeps the window back: a longer option and a value that
## holds the word are not it.
func test_only_the_whole_flag_asks() -> void:
    assert_false(BackgroundStart.asks(PackedStringArray(["--in-background=0"]))["minimised"], "a flag with a value")
    assert_false(BackgroundStart.asks(PackedStringArray(["--in-backgrounds"]))["minimised"], "a longer option")


## Without the flag the window is left in its mode. With it, only under the
## headless display server, which has no window to minimise, since a run on
## the nested weston would send the suites' own window to the taskbar.
func test_applying_answers_what_was_asked_and_leaves_a_headless_run_alone() -> void:
    var mode_before := DisplayServer.window_get_mode()
    assert_false(BackgroundStart.apply(PackedStringArray(["--agent-door"])), "not asked")
    assert_eq(DisplayServer.window_get_mode(), mode_before, "the window kept its mode")
    if DisplayServer.get_name() == "headless":
        assert_true(BackgroundStart.apply(PackedStringArray(["--agent-door", "--in-background"])), "asked")
        assert_eq(DisplayServer.window_get_mode(), mode_before, "the headless window kept its mode")
