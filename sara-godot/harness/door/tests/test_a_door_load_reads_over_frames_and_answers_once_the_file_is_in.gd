## The door's `load` reads its file over frames, as File >
## Open does, and holds its answer until the file is in.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A door `load` that read all 305 layers in one call logged a frame of 2.6 s. These read the
## step the door hands the table: a `load` by name or by a path in a dictionary
## comes out reading over frames, one that says `"over_frames": false` keeps
## it, and any other step is untouched. A load holds the door's answer only
## while an open is in flight, and no other step is held by one.
extends "res://tests/test_framework.gd"

const ScenarioDocument := preload("res://harness/scenario/sa_scenario_document.gd")

const PATH := "/abs/deep.sad"


func test_a_load_by_name_reads_over_frames() -> void:
    var step := ScenarioDocument.as_the_door_runs({"load": PATH})
    assert_eq(step["load"], {"path": PATH, "over_frames": true}, "A name becomes a path read over frames")


func test_a_load_by_dictionary_reads_over_frames_and_keeps_its_keys() -> void:
    var given := {"load": {"path": PATH}}
    var step := ScenarioDocument.as_the_door_runs(given)
    assert_eq(step["load"], {"path": PATH, "over_frames": true}, "The path is kept and the open is over frames")
    assert_eq(given["load"], {"path": PATH}, "and the request itself is left as the client sent it")


func test_a_load_that_asks_for_one_call_keeps_it() -> void:
    var step := ScenarioDocument.as_the_door_runs({"load": {"path": PATH, "over_frames": false}})
    assert_eq(step["load"], {"path": PATH, "over_frames": false}, "A client that asks for one call gets one")


func test_any_other_step_is_untouched() -> void:
    var given := {"zoom": 2.0}
    assert_eq(ScenarioDocument.as_the_door_runs(given), given, "A step with no load comes back as it was")


func test_no_step_is_held_while_no_file_is_opening() -> void:
    assert_false(SaSadFile.opening(), "No open is in flight in a suite that started none")
    assert_false(ScenarioDocument.still_loading({"load": PATH}), "so a load's answer is not held")
    assert_false(ScenarioDocument.still_loading({"zoom": 2.0}), "and nor is any other step's")
