## A door load that cannot open its file leaves the open
## document as it was and answers why.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A `{"load": "missing.sad"}` is a
## relative name read from Sara's own folder where no such file was, and the
## reader's failure reset the document in front to an empty one of two layers
## while the answer said `"ok": true`. These paint a stroke through a real door
## over TCP, send a load of a missing file, and read the same layers, pixels and
## undo count after, with the answer's `ok` false and its error naming the
## absolute path tried. A real `.sad` by its absolute path still loads.
extends "res://tests/test_framework.gd"

## The brush needs a RenderingDevice, and the window a display.
const REQUIRES_GPU := true

const AgentDoor := preload("res://harness/door/sa_agent_door.gd")
const StepTable := preload("res://harness/sa_step_table.gd")
const CaptureRun := preload("res://harness/sa_capture_run.gd")
const Fixtures := preload("res://tests/fixtures.gd")
const MainCanvasScript := preload("res://render/main_canvas.gd")
const PixelDriver := preload("res://harness/scenario/sa_scenario_pixels.gd")
const ScenarioDocument := preload("res://harness/scenario/sa_scenario_document.gd")
const DoorRunner := preload("res://tests/fixtures/door_runner.gd")

static var scratch_known: String = SaDataRoot.path("door/door.json")
static var scratch_port_file: String = SaDataRoot.path("door/door.port")
static var scratch_run_folder: String = SaDataRoot.path("door-run")

## Rounds of polling before a case gives up on an answer, a few milliseconds
## each.
const ROUNDS: int = 900

## The name the painter's slip stands for, a relative one in a folder that is
## not there.
const MISSING: String = "no-such-folder/missing.sad"

## A painted document of the fixtures, the real file a load still opens.
const SAVED: String = "res://tests/data/plain_v4.sad"

## Where the stroke starts from the canvas's corner in root units, and how far
## it runs, inside the part of the canvas the pixels are read over.
const FROM_CORNER := Vector2(40, 40)
const RUN := Vector2(120, 60)

## The part of the active layer read before and after, in canvas texels.
const READ_RECT: Array = [0, 0, 200, 160]

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


## Parented to an autoload, because the runner calls this from its own `_ready`
## and a parent mid-`_ready` rejects `add_child`.
func before_each() -> void:
    SaCursorPolicy.forget_pointer_device()
    _host = Node.new()
    _host.name = "U451DoorTestHost"
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


## The document's layers, by identity, so a reset to the same count shows.
func _layers() -> Array:
    return SaLayerOps.new(_document()).layers()


## The active layer's texels over [constant READ_RECT], as the `read_pixels`
## step reads them.
func _pixels(called: String) -> PackedByteArray:
    var doc := _document()
    var index := SaLayerOps.new(doc).layers().find(doc.active_layer)
    var spec := {"layer": index, "rect": READ_RECT, "file": "%s.npy" % called}
    var answer := PixelDriver.read_into(doc, spec, _folder)
    return FileAccess.get_file_as_bytes(String(answer.get("path", "")))


func _paint_a_stroke() -> void:
    var from := (_main.canvas as SaCanvas).get_global_rect().position + FROM_CORNER
    var to := from + RUN
    var answer := _ask({"stroke": {"from": [from.x, from.y], "to": [to.x, to.y], "steps": 12, "pressure": 1.0}})
    assert_eq(answer.get("errors"), [], "The stroke raises nothing: %s" % str(answer))


func test_a_load_of_a_missing_file_leaves_the_painting_and_answers_not_ok() -> void:
    _paint_a_stroke()
    var undo := _document().undo_redo.get_history_count()
    assert_true(undo > 0, "The stroke is a step to undo")
    var layers := _layers()
    var pixels := _pixels("before")
    var painted := false
    for at in range(0, pixels.size(), 4):
        if pixels[at] != 0:
            painted = true
            break
    assert_true(painted, "The stroke left paint where it is read")

    var answer := _ask({"load": MISSING})

    assert_false(bool(answer.get("ok", true)), "The answer is not ok: %s" % str(answer))
    var tried := ScenarioDocument.read_as(MISSING)
    assert_true(tried.is_absolute_path(), "The path tried is absolute: %s" % tried)
    assert_true(tried.ends_with(MISSING), "and ends in the name sent: %s" % tried)
    var error := String(answer.get("error", ""))
    assert_true(error.contains(tried), "The error names the path tried: %s" % error)
    assert_true(error.contains("no file"), "and says why: %s" % error)
    assert_eq(String((answer.get("load", {}) as Dictionary).get("path", "")), tried, "as the load's own entry does")
    assert_eq(_layers(), layers, "The document keeps its layers")
    assert_eq(_pixels("after"), pixels, "and its pixels")
    assert_eq(_document().undo_redo.get_history_count(), undo, "and its undo history")


func test_a_file_that_is_not_a_sad_leaves_the_painting_too() -> void:
    _paint_a_stroke()
    var layers := _layers()
    var undo := _document().undo_redo.get_history_count()
    var other := _folder.path_join("not-a-sad.sad")
    var file := FileAccess.open(other, FileAccess.WRITE)
    file.store_string("PNG and not a painting")
    file.close()

    var answer := _ask({"load": other})

    assert_false(bool(answer.get("ok", true)), "The answer is not ok: %s" % str(answer))
    assert_true(String(answer.get("error", "")).contains(other), "naming the file: %s" % str(answer))
    assert_eq(_layers(), layers, "The document keeps its layers")
    assert_eq(_document().undo_redo.get_history_count(), undo, "and its undo history")


func test_a_real_sad_by_its_absolute_path_loads_as_before() -> void:
    _paint_a_stroke()
    var layers := _layers()
    var path := ProjectSettings.globalize_path(SAVED)

    var answer := _ask({"load": path})

    assert_true(bool(answer.get("ok", false)), "The answer is ok: %s" % str(answer))
    assert_false(answer.has("error"), "with no error: %s" % str(answer))
    assert_false(_layers() == layers, "The document is the file's now")
    assert_eq(_document().undo_redo.get_history_count(), 0, "with the history of a file just opened")
