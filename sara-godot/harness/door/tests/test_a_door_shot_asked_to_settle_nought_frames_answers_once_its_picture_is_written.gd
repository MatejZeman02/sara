## A door shot asked to settle nought frames answers only once
## its picture is written.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## `{"shot": "x", "settle": 0}` after a fill answered in
## the frame it ran while `SaShotSettle` held the picture back for a later one,
## naming the file an earlier shot of the same label had left, or null when
## there was none, with `ok` true either way. These open the door in this
## process over TCP on a real main canvas, owe a fold that never pays so the
## settle holds every shot to its bound, and read the shot's file at the frame
## the door let the request go. A `write_pixels` with `"settle": 0` beside them
## still answers in the frame it ran.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const AgentDoor := preload("res://harness/door/sa_agent_door.gd")
const StepTable := preload("res://harness/sa_step_table.gd")
const CaptureRun := preload("res://harness/sa_capture_run.gd")
const Fixtures := preload("res://tests/fixtures.gd")
const MainCanvasScript := preload("res://render/main_canvas.gd")
const DoorRunner := preload("res://tests/fixtures/door_runner.gd")
const PixelDriver := preload("res://harness/scenario/sa_scenario_pixels.gd")

static var scratch_known: String = SaDataRoot.path("h1801-door/door.json")
static var scratch_port_file: String = SaDataRoot.path("h1801-door/door.port")
static var scratch_run_folder: String = SaDataRoot.path("h1801-door-run")

## Rounds of polling before a case gives up on an answer, a few milliseconds
## each.
const ROUNDS: int = 600
## The frames the settle holds a shot for while the fold is owed.
const BOUND: int = 6

var _host: Node = null
var _door: AgentDoor = null
var _run: CaptureRun = null
var _runner: DoorRunner = null
var _table: StepTable = null
var _front: Fixtures.FrontDocuments = null
var _canvas: SaCanvas = null
var _looks := 0
## Frames that ended with the request still held by the door.
var _held_frames := 0
## The size of the shot's file at the end of the frame the door let the
## request go, or a negative size before that.
var _size_at_answer := Vector2i(-1, -1)
## The file the case's shot writes.
var _shot_path := ""


## Parented to an autoload, because the runner calls this from its own `_ready`
## and a parent mid-`_ready` rejects `add_child`.
func before_each() -> void:
    _host = Node.new()
    _host.name = "H1801DoorHost"
    EventBus.add_child(_host)
    var main: Node = MainCanvasScript.new()
    _host.add_child(main)
    main.bind_tools(Fixtures.make_tool_registry())
    main.notification(Container.NOTIFICATION_SORT_CHILDREN)
    _canvas = main.canvas as SaCanvas
    _front = Fixtures.FrontDocuments.over(_canvas)
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(scratch_run_folder))
    _door = AgentDoor.new(scratch_known)
    _run = CaptureRun.new(scratch_run_folder)
    _table = StepTable.new(_run)
    _runner = DoorRunner.new(_door, _table, _run, ROUNDS, scratch_known, Callable(), _watch)
    _door.drawn_wait.frames = _a_look
    _held_frames = 0
    _size_at_answer = Vector2i(-1, -1)
    _shot_path = ""
    _clear_run_folder()


func after_each() -> void:
    SaShotSettle.owed_frames_bound = 600
    if _front != null:
        _front.put_back()
        _front = null
    _door.close()
    _door = null
    _table = null
    _runner = null
    _run = null
    _canvas = null
    if _host != null:
        _host.free()
        _host = null
    _clear_run_folder()


func _a_look() -> int:
    _looks += 1
    return _looks


static func _clear_run_folder() -> void:
    var globalized := ProjectSettings.globalize_path(scratch_run_folder)
    if not DirAccess.dir_exists_absolute(globalized):
        return
    for file: String in DirAccess.get_files_at(globalized):
        DirAccess.remove_absolute(globalized.path_join(file))


## After every frame of the runner: counts a frame that ended with the request
## held, and reads the shot's file at the first frame that ended with the
## request answered, once the request has run.
func _watch() -> void:
    if _run == null:
        return
    if not _door._pending.is_empty():
        _held_frames += 1
        return
    if _size_at_answer.x >= 0 or _shot_path.is_empty() or _run.last_shot.is_empty():
        return
    var image := Image.load_from_file(ProjectSettings.globalize_path(_shot_path))
    _size_at_answer = image.get_size() if image != null else Vector2i.ZERO


## Owes the front document a fold that never pays, so `SaShotSettle` holds every
## shot until the bound.
func _owe_a_fold() -> void:
    var document := _canvas.document
    var debt := document.fold.debt
    debt.quiet_msec = 1 << 40
    SaShotSettle.owed_frames_bound = BOUND
    debt.owe(document)
    assert_true(debt.is_owed(), "the fold is owed before the shot is asked for")


func _ask(request: Dictionary) -> Dictionary:
    assert_true(_door.open_port(scratch_port_file), "The TCP way in opens")
    var client := _runner.connect_client()
    return _runner.ask(client, request)


func test_a_held_shot_with_no_file_before_answers_with_the_file_it_wrote() -> void:
    _owe_a_fold()
    _shot_path = _run.shot_file("fresh")
    var answer := _ask({"id": 1, "shot": "fresh", "settle": 0})
    assert_eq(answer.get("ok"), true, "A shot that was written is ok: %s" % str(answer))
    assert_true(_held_frames >= BOUND, "the door held the answer while the settle held the shot: %d frames" % _held_frames)
    assert_eq(answer.get("shot"), ProjectSettings.globalize_path(_shot_path), "and names the file: %s" % str(answer))
    assert_true(_size_at_answer.x > 0, "which was on disk when the door let the request go: %s" % _size_at_answer)


func test_a_held_shot_over_an_earlier_file_answers_only_once_it_is_rewritten() -> void:
    _shot_path = _run.shot_file("again")
    # The earlier shot of the same label, a picture no viewport has.
    var earlier := Image.create(1, 1, false, Image.FORMAT_RGBA8)
    assert_eq(earlier.save_png(_shot_path), OK, "the earlier file is written")
    _owe_a_fold()
    var answer := _ask({"id": 1, "shot": "again", "settle": 0})
    assert_eq(answer.get("ok"), true, "A shot that was written is ok: %s" % str(answer))
    assert_true(_held_frames >= BOUND, "the door held the answer while the settle held the shot: %d frames" % _held_frames)
    assert_eq(answer.get("shot"), ProjectSettings.globalize_path(_shot_path), "and names the file: %s" % str(answer))
    assert_true(_size_at_answer.x > 1, "rewritten by this shot before the door let the request go: %s" % _size_at_answer)


func test_a_write_of_pixels_with_settle_nought_answers_in_the_frame_it_ran() -> void:
    var file := FileAccess.open(scratch_run_folder.path_join("small.npy"), FileAccess.WRITE)
    file.store_buffer(PixelDriver.Npy.header(Vector2i(2, 2)))
    var floats := PackedFloat32Array()
    for _i in 4:
        floats.append_array([0.8, 0.2, 0.1, 1.0])
    file.store_buffer(floats.to_byte_array())
    file.close()
    var answer := _ask({"id": 1, "write_pixels": {"rect": [0, 0, 2, 2], "file": "small.npy"}, "settle": 0})
    assert_eq(answer.get("ok"), true, "The write is ok: %s" % str(answer))
    assert_eq(answer.get("errors", []), [], "with no error: %s" % str(answer))
    assert_eq(_held_frames, 0, "and the door answered in the frame it ran")
