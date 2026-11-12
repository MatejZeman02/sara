## Which starts look for a running Sara, and a lock that names no live
## Sara hands nothing over. The hand-over between two real Saras is
## `scripts/test_opening_a_file_while_sara_runs_hands_it_to_the_running_sara_as_a_tab.py`,
## since a suite cannot start a process.
extends "res://tests/test_framework.gd"

static var lock: String = SaDataRoot.path("probe_running.json")


func after_each() -> void:
    DirAccess.remove_absolute(ProjectSettings.globalize_path(lock))


func test_the_painters_sara_takes_part() -> void:
    assert_true(SaSingleInstance.wanted(PackedStringArray(["/tmp/a.sad"]), false), "a file from a file manager")
    assert_true(SaSingleInstance.wanted(PackedStringArray(["--agent-door", "/tmp/a.sad"]), false), "the painter's door")
    assert_true(SaSingleInstance.wanted(PackedStringArray(), false), "no arguments at all")


func test_an_agents_or_a_suites_sara_stays_apart() -> void:
    assert_false(SaSingleInstance.wanted(PackedStringArray(["/tmp/a.sad"]), true), "a moved data root")
    for flag: String in ["--capture", "--capture=/tmp/s.json", "--agent-socket=/tmp/s", "--agent-port-file=/tmp/p"]:
        assert_false(SaSingleInstance.wanted(PackedStringArray([flag, "/tmp/a.sad"]), false), flag)
    assert_true(SaSingleInstance.wanted(PackedStringArray(["--agent-socket="]), false), "an empty socket opens no door")


func test_a_lock_naming_a_gone_process_hands_nothing_over() -> void:
    var file := FileAccess.open(lock, FileAccess.WRITE)
    file.store_string(JSON.stringify({"pid": 2147483000, "port": 9, "token": "stale"}))
    file.close()
    var args := PackedStringArray(["res://project.godot"])
    assert_false(SaSingleInstance.handed(args, args, lock), "nothing runs there")


func test_no_listener_answers_on_a_closed_port() -> void:
    assert_false(SaSingleInstance.hand_over(9, "token", PackedStringArray(["/tmp/a.sad"])), "nothing listens")
    assert_false(SaSingleInstance.hand_over(0, "token", PackedStringArray(["/tmp/a.sad"])), "no port")
