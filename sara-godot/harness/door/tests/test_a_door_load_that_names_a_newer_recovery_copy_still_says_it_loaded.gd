## A door `load` that names a newer recovery copy still says
## it loaded, in its verdicts and in fields of its own.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A door answered a load with the recovery copy's line
## alone, and a script waiting for "loaded" read a good load as a failed one.
## These save a document through a real door over TCP, write a newer recovery
## copy beside it, load the file and read the answer: the loaded line first
## among the verdicts, then the copy's, and the `load` entry's `loaded`,
## `canvas` and `recovery`. A load with no copy beside the file reads the same
## fields with no `recovery`. Main's autosave is stood in for on the runner, as
## the load reads the copy's path off it.
extends "res://tests/test_framework.gd"

## The brush needs a RenderingDevice, and the window a display.
const REQUIRES_GPU := true

const AgentDoor := preload("res://harness/door/sa_agent_door.gd")
const StepTable := preload("res://harness/sa_step_table.gd")
const CaptureRun := preload("res://harness/sa_capture_run.gd")
const Fixtures := preload("res://tests/fixtures.gd")
const MainCanvasScript := preload("res://render/main_canvas.gd")
const ScenarioDocument := preload("res://harness/scenario/sa_scenario_document.gd")
const DoorRunner := preload("res://tests/fixtures/door_runner.gd")

static var scratch_known: String = SaDataRoot.path("door/door.json")
static var scratch_port_file: String = SaDataRoot.path("door/door.port")
static var scratch_run_folder: String = SaDataRoot.path("door-run")

## Rounds of polling before a case gives up on an answer, a few milliseconds
## each.
const ROUNDS: int = 900

## The name the saved document takes in the case's folder.
const NAME: String = "probe.sad"

## The suffix of a recovery copy beside its file, `SaAutosave`'s own.
const RECOVERY_SUFFIX: String = ".autosave.sad"

var _host: Node = null
var _main: Node = null
var _door: AgentDoor = null
var _run: CaptureRun = null
var _runner: DoorRunner = null
var _table: StepTable = null
var _front: Fixtures.FrontDocuments = null
var _client: StreamPeerTCP = null
var _folder: String = ""
var _asked: int = 0
var _autosave: SaAutosave = null


## Parented to an autoload, because the runner calls this from its own `_ready`
## and a parent mid-`_ready` rejects `add_child`.
func before_each() -> void:
    SaCursorPolicy.forget_pointer_device()
    _host = Node.new()
    _host.name = "U576DoorTestHost"
    EventBus.add_child(_host)
    _main = MainCanvasScript.new()
    _host.add_child(_main)
    _main.bind_tools(Fixtures.make_tool_registry())
    _main.notification(Container.NOTIFICATION_SORT_CHILDREN)
    _front = Fixtures.FrontDocuments.over(_main.canvas as SaCanvas)
    _door = AgentDoor.new(scratch_known)
    _run = CaptureRun.new(scratch_run_folder)
    _table = StepTable.new(_run)
    _runner = DoorRunner.new(_door, _table, _run, ROUNDS, scratch_known)
    _folder = OS.get_temp_dir().path_join("sara-door-%d" % OS.get_process_id())
    DirAccess.make_dir_recursive_absolute(_folder)
    _asked = 0
    assert_true(_door.open_port(scratch_port_file), "The TCP way in opens")
    _client = _runner.connect_client()


func after_each() -> void:
    if _client != null:
        _client.disconnect_from_host()
        _client = null
    _door.close()
    _door = null
    _table = null
    _runner = null
    _run = null
    if _front != null:
        _front.put_back()
        _front = null
    if _host != null:
        _host.free()
        _host = null
    _main = null
    var scene := (Engine.get_main_loop() as SceneTree).current_scene
    if scene != null and "autosave" in scene:
        scene.set("autosave", null)
    if _autosave != null:
        _autosave.free()
        _autosave = null
    SaCursorPolicy.forget_pointer_device()
    for name in DirAccess.get_files_at(_folder):
        DirAccess.remove_absolute(_folder.path_join(name))
    DirAccess.remove_absolute(_folder)


func _ask(step: Dictionary) -> Dictionary:
    _asked += 1
    var request := step.duplicate()
    request["id"] = _asked
    var answer := _runner.ask(_client, request)
    return answer.get("body", answer) as Dictionary


func _document() -> SaDocument:
    return (_main.canvas as SaCanvas).document


## Hands the runner an autosave watching the document in front, as main's
## watches the painter's, so the load reads the copy's path where it does in
## the app.
func _stand_in_for_mains_autosave() -> void:
    var scene := (Engine.get_main_loop() as SceneTree).current_scene
    assert_true(scene != null and "autosave" in scene, "The runner holds a place for main's autosave")
    _autosave = SaAutosave.new()
    _autosave.attach(_document())
    scene.set("autosave", _autosave)


## Saves the document in front through the door into the case's folder, and
## answers the file's path.
func _save() -> String:
    var path := _folder.path_join(NAME)
    # Composited first, since the save's preview composites what is pending and a suite draws no frame for the answer to wait on.
    (_document().get_parent() as SaEasel).process_pending_composite()
    var answer := _ask({"save": path})
    assert_eq(String((answer.get("save", {}) as Dictionary).get("error", "")), "OK", "The save took: %s" % str(answer))
    assert_true(FileAccess.file_exists(path), "and wrote %s" % path)
    return path


## The verdict lines of *answer* that open with *prefix*.
static func _lines(answer: Dictionary, prefix: String) -> Array:
    return (answer.get("verdicts", []) as Array).filter(func(line: Variant) -> bool: return String(line).begins_with(prefix))


func test_a_load_with_a_newer_copy_says_it_loaded_and_names_the_copy() -> void:
    _stand_in_for_mains_autosave()
    var path := _save()
    var copy := path.get_basename() + RECOVERY_SUFFIX
    # Written after the file, so at least as new, which is what is named.
    assert_eq(DirAccess.copy_absolute(path, copy), OK, "A recovery copy is written beside the file")

    var answer := _ask({"load": path})

    assert_true(bool(answer.get("ok", false)), "The load is ok: %s" % str(answer))
    var verdicts := answer.get("verdicts", []) as Array
    assert_true(verdicts.size() >= 2, "The answer carries the load's lines: %s" % str(verdicts))
    var first := "SaCapture: loaded %s, canvas " % path
    assert_true(String(verdicts[0]).begins_with(first), "the loaded line first: %s" % str(verdicts))
    assert_eq(_lines(answer, "SaCapture: loaded").size(), 1, "and once")
    var named := _lines(answer, "SaCapture: a recovery copy newer than")
    assert_eq(named.size(), 1, "The copy is named once: %s" % str(verdicts))
    assert_true(String(named[0]).contains(copy), "at its path: %s" % str(named))
    var entry := answer.get("load", {}) as Dictionary
    assert_eq(String(entry.get("loaded", "")), path, "`loaded` is the file's path: %s" % str(entry))
    var size := _document().canvas_size
    assert_eq(entry.get("canvas"), [float(size.x), float(size.y)], "`canvas` is the document's size, numbers in JSON")
    assert_eq(String(entry.get("recovery", "")), copy, "`recovery` is the copy's path")
    assert_false(entry.has("error"), "with no error")


func test_a_load_with_no_copy_says_it_loaded_and_names_none() -> void:
    _stand_in_for_mains_autosave()
    var path := _save()

    var answer := _ask({"load": path})

    assert_true(bool(answer.get("ok", false)), "The load is ok: %s" % str(answer))
    var verdicts := answer.get("verdicts", []) as Array
    var first := "SaCapture: loaded %s, canvas " % path
    var opened := not verdicts.is_empty() and String(verdicts[0]).begins_with(first)
    assert_true(opened, "The loaded line comes first: %s" % str(verdicts))
    assert_eq(_lines(answer, "SaCapture: a recovery copy newer than"), [], "and no copy is named")
    var entry := answer.get("load", {}) as Dictionary
    assert_eq(String(entry.get("loaded", "")), path, "`loaded` is the file's path: %s" % str(entry))
    var size := _document().canvas_size
    assert_eq(entry.get("canvas"), [float(size.x), float(size.y)], "`canvas` is the document's size, numbers in JSON")
    assert_false(entry.has("recovery"), "and there is no `recovery`")
