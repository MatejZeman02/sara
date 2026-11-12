## What the capture harness puts past the `--`, read by the app's own parser.
##
## `SaBoot.document_path` walks `OS.get_cmdline_user_args()` and takes the
## first entry that does not begin with a dash. `scripts/sara_shot.py` appends a
## scenario's `{"args": [...]}` entry at the end of that list, after
## `--capture=`, `--capture-out=` and `--settings-dir=`, and the two halves of
## that arrangement are asserted in two languages because the bug was the
## arrangement rather than either half: the parser worked from the File menu, the
## harness ran every scenario, and no scenario could reach the parser at all.
##
## `scripts/test_shot_problems.py` holds the other half, that the harness builds
## that list. This holds that the list means what the harness thinks it does.
extends "res://tests/test_framework.gd"

## The harness's own flags, in the order `child_command` writes them, followed by
## whatever a scenario asked for. A literal rather than a call, because a test
## that asked Python for the list would prove only that one file agrees with
## itself.
const HARNESS_FLAGS: Array[String] = [
    "--capture=/tmp/scenario.json",
    "--capture-out=/home/painter/captures/f100",
    "--settings-dir=/project/scratch/xdg/config/sara",
]


func _user_args(app_args: Array[String]) -> PackedStringArray:
    var args := PackedStringArray()
    for flag in HARNESS_FLAGS:
        args.append(flag)
    for arg in app_args:
        args.append(arg)
    return args


## The claim the whole unit rests on. Every harness flag begins with a dash, so
## the scenario's path is the first thing the parser accepts even though it is
## last on the line.
func test_the_harness_flags_do_not_shadow_the_scenarios_path() -> void:
    var path := "res://tests/data/painted_two_layers.sad"
    assert_true(FileAccess.file_exists(path), "the fixture the suite reads back")
    assert_eq(
        SaBoot.document_path(_user_args([path] as Array[String])),
        path,
        "appended last and still the first entry document_path accepts"
    )


## The case every other scenario is, which is the one that must not
## have moved: no argument, three flags, nothing opened.
func test_a_run_with_no_scenario_argument_opens_nothing() -> void:
    assert_eq(SaBoot.document_path(_user_args([] as Array[String])), "", "the harness flags on their own are options, not paths")


## The second proof of the unit, as the app sees it. A path with nothing behind
## it is reported rather than ignored, and reported once.
func test_a_path_with_no_file_behind_it_is_reported_and_opens_nothing() -> void:
    var announcing := SaProblems.announce
    SaProblems.announce = false
    SaProblems.detach_sink()
    var kept := SaProblems.pending.size()
    var missing := SaDataRoot.path("f100-there-is-no-file-here.sad")
    assert_false(FileAccess.file_exists(missing), "and nothing has put one there")
    assert_eq(SaBoot.document_path(_user_args([missing] as Array[String])), "", "so nothing is opened")
    assert_eq(SaProblems.pending.size(), kept + 1, "and the painter is told, which is the run.log line the capture harness reads")
    assert_true(
        String(SaProblems.pending[kept]).contains(missing), "the report names the path that was typed, not a generic failure"
    )
    SaProblems.announce = announcing


## The first argument wins, so a scenario that names two documents opens the one
## it wrote first rather than an arbitrary one.
func test_the_first_argument_is_the_one_that_opens() -> void:
    var path := "res://tests/data/painted_two_layers.sad"
    assert_eq(
        SaBoot.document_path(_user_args([path, "res://project.godot"] as Array[String])),
        path,
        "the order a scenario writes its args in is the order they are read"
    )
