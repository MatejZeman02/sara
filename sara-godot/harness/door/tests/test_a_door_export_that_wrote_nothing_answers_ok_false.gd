## A door export that wrote nothing answers ok false.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## An export into a folder that was not
## there answered `ok: true` with the writer's error under `errors`, and a
## script that read only `ok` lost three exports without a word. These open the
## door in this process over TCP, as the door's other suites do, on a real main
## canvas, and export once into a missing folder and once into a present one.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const AgentDoor := preload("res://harness/door/sa_agent_door.gd")
const StepTable := preload("res://harness/sa_step_table.gd")
const CaptureRun := preload("res://harness/sa_capture_run.gd")
const Fixtures := preload("res://tests/fixtures.gd")
const MainCanvasScript := preload("res://render/main_canvas.gd")
const DoorRunner := preload("res://tests/fixtures/door_runner.gd")

static var scratch_known: String = SaDataRoot.path("door/door.json")
static var scratch_port_file: String = SaDataRoot.path("door/door.port")
static var scratch_run_folder: String = SaDataRoot.path("door-run")
static var scratch_exports: String = SaDataRoot.path("exports")

## Rounds of polling before a case gives up on an answer, a few milliseconds
## each.
const ROUNDS: int = 600

var _host: Node = null
var _door: AgentDoor = null
var _run: CaptureRun = null
var _runner: DoorRunner = null
var _table: StepTable = null
var _front: Fixtures.FrontDocuments = null
## The frames the door's drawn wait is told have been drawn, one more at each
## look, since a suite draws none.
var _looks := 0


## Parented to an autoload, because the runner calls this from its own `_ready`
## and a parent mid-`_ready` rejects `add_child`.
func before_each() -> void:
    _host = Node.new()
    _host.name = "U653DoorHost"
    EventBus.add_child(_host)
    var main: Node = MainCanvasScript.new()
    _host.add_child(main)
    main.bind_tools(Fixtures.make_tool_registry())
    main.notification(Container.NOTIFICATION_SORT_CHILDREN)
    _front = Fixtures.FrontDocuments.over(main.canvas as SaCanvas)
    _door = AgentDoor.new(scratch_known)
    _run = CaptureRun.new(scratch_run_folder)
    _table = StepTable.new(_run)
    _runner = DoorRunner.new(_door, _table, _run, ROUNDS, scratch_known, Callable(), Input.flush_buffered_events)
    # An export over frames rounds the live textures and composites what moved,
    # so its answer waits for a drawn frame (a drawn-frame wait), and a suite draws none.
    _door.drawn_wait.frames = _a_look
    _clear_exports()


func after_each() -> void:
    if _front != null:
        _front.put_back()
        _front = null
    _door.close()
    _door = null
    _table = null
    _runner = null
    _run = null
    if _host != null:
        _host.free()
        _host = null
    _clear_exports()


func _a_look() -> int:
    _looks += 1
    return _looks


## Takes away the folder the cases export into and what it holds, so a missing
## folder is missing and a written file is this run's.
static func _clear_exports() -> void:
    for folder: String in [scratch_exports.path_join("missing"), scratch_exports]:
        var globalized := ProjectSettings.globalize_path(folder)
        if not DirAccess.dir_exists_absolute(globalized):
            continue
        for file: String in DirAccess.get_files_at(globalized):
            DirAccess.remove_absolute(globalized.path_join(file))
        DirAccess.remove_absolute(globalized)


## The answer to one door export to *path*, held until the export written over
## frames has ended, as the door holds it in the app.
func _export(path: String) -> Dictionary:
    assert_true(_door.open_port(scratch_port_file), "The TCP way in opens")
    var client := _runner.connect_client()
    return _runner.ask(client, {"id": 1, "export": path, "settle": 0})


func test_an_export_into_a_missing_folder_answers_ok_false_with_the_reason() -> void:
    var path := ProjectSettings.globalize_path(scratch_exports.path_join("missing/autumn-test.png"))
    var answer := _export(path)
    assert_eq(answer.get("ok"), false, "An export that wrote nothing is no success: %s" % str(answer))
    assert_true(String(answer.get("error", "")).contains(path), "The reason names the path: %s" % str(answer))
    assert_false(FileAccess.file_exists(path), "and nothing reached the disk")
    var errors: Array = answer.get("errors", []) as Array
    assert_false(errors.is_empty(), "The writer's own line stands under errors as before: %s" % str(answer))
    assert_false(DirAccess.dir_exists_absolute(path.get_base_dir()), "The door made no folder of its own")


func test_an_export_into_a_present_folder_answers_ok_true_with_the_file_on_disk() -> void:
    var folder := ProjectSettings.globalize_path(scratch_exports)
    DirAccess.make_dir_recursive_absolute(folder)
    var path := folder.path_join("autumn-test.png")
    var answer := _export(path)
    assert_eq(answer.get("ok"), true, "An export that wrote its file is ok: %s" % str(answer))
    assert_false((answer.get("export", {}) as Dictionary).has("error"), "with no error: %s" % str(answer))
    assert_true(FileAccess.file_exists(path), "The file is on disk")
    var bytes := int((answer.get("export", {}) as Dictionary).get("bytes", 0))
    assert_true(bytes > 0, "and the answer says its size: %s" % str(answer))
