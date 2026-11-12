## The door's `canvas` and `document` steps refuse a size no
## dialog could have made.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Every size dialog takes a side from 1 to 16384, and the door took anything:
## `canvas: [0, 100]` was silently made 1, `[100000, 100000]` was taken as it
## was, and `document` with `size: [-5, 10]` reached an `assert` a release build
## strips. These open the door in this process over TCP, as the failed-stroke
## suite beside the door does, post each step through a real step table, and
## read the refusal under `errors` and the open document as it stood.
extends "res://tests/test_framework.gd"

const AgentDoor := preload("res://harness/door/sa_agent_door.gd")
const StepTable := preload("res://harness/sa_step_table.gd")
const CaptureRun := preload("res://harness/sa_capture_run.gd")
const Fixtures := preload("res://tests/fixtures.gd")
const SizeCheck := preload("res://harness/scenario/sa_scenario_size.gd")
const DoorRunner := preload("res://tests/fixtures/door_runner.gd")

static var scratch_known: String = SaDataRoot.path("door/door.json")
static var scratch_port_file: String = SaDataRoot.path("door/door.port")
static var scratch_run_folder: String = SaDataRoot.path("door-run")

## Rounds of polling before a case gives up on an answer, a few milliseconds
## each.
const ROUNDS: int = 600

## The canvas every case starts from.
const OPENED := Vector2i(640, 480)

var _host: Node = null
var _door: AgentDoor = null
var _run: CaptureRun = null
var _runner: DoorRunner = null
var _table: StepTable = null
var _canvas: SaCanvas = null
var _client: StreamPeerTCP = null
var _asked: int = 0

## The suite's canvas, held as the document in front, which is where a
## harness step and a door line look.
var _front: Fixtures.FrontDocuments = null


## Parented to an autoload, because the runner calls this from its own `_ready`
## and a parent mid-`_ready` rejects `add_child`.
func before_each() -> void:
    _host = Node.new()
    _host.name = "U219DoorTestHost"
    EventBus.add_child(_host)
    _canvas = SaCanvas.new()
    _canvas.canvas_size = OPENED
    _host.add_child(_canvas)
    _canvas.size = Vector2(OPENED)
    _door = AgentDoor.new(scratch_known)
    _run = CaptureRun.new(scratch_run_folder)
    _table = StepTable.new(_run)
    _runner = DoorRunner.new(_door, _table, _run, ROUNDS, scratch_known)
    _front = Fixtures.FrontDocuments.over(_canvas)
    _asked = 0
    assert_true(_door.open_port(scratch_port_file), "The TCP way in opens")
    _client = _runner.connect_client()


func after_each() -> void:
    if _front != null:
        _front.put_back()
        _front = null
    if _client != null:
        _client.disconnect_from_host()
        _client = null
    _door.close()
    _door = null
    _table = null
    _runner = null
    _run = null
    _canvas = null
    if _host != null:
        _host.free()
        _host = null


func _ask(step: Dictionary) -> Dictionary:
    _asked += 1
    var request := step.duplicate()
    request["id"] = _asked
    return _runner.ask(_client, request)


## The lines of *lines* that hold *text*.
static func _holding(lines: Variant, text: String) -> Array:
    var out: Array = []
    for line: Variant in lines if lines is Array else []:
        if String(line).contains(text):
            out.append(String(line))
    return out


## What the open document is made of, its children by identity, so a reset that
## swapped them shows even at the same count.
func _children() -> Array[Node]:
    return _canvas.document.get_children()


## *answer* carries one refusal naming *step*, *written* and the limit.
func _assert_refused(answer: Dictionary, step: String, written: String) -> void:
    var refused := _holding(answer.get("errors"), "refused")
    assert_eq(refused.size(), 1, "%s %s is refused under errors: %s" % [step, written, str(answer.get("errors"))])
    if refused.size() == 1:
        var line: String = refused[0]
        assert_true(line.contains(step), "naming the step: %s" % line)
        assert_true(line.contains(written), "the pair as written: %s" % line)
        assert_true(line.contains(str(SizeCheck.LIMIT)), "and the limit: %s" % line)


func test_a_canvas_step_outside_the_dialogs_box_is_refused_and_the_size_kept() -> void:
    for pair: Array in [[0, 100], [100, -1], [16385, 100]]:
        var before: Vector2i = _canvas.document.canvas_size
        var answer := _ask({"canvas": pair})
        _assert_refused(answer, "canvas", SizeCheck.written(pair))
        assert_eq(_canvas.document.canvas_size, before, "and %s left the document at %s" % [str(pair), before])


func test_a_canvas_step_inside_the_box_still_resizes() -> void:
    var answer := _ask({"canvas": [SizeCheck.LIMIT, 16]})
    assert_eq(answer.get("errors"), [], "the largest side is taken: %s" % str(answer.get("errors")))
    assert_eq(_canvas.document.canvas_size, Vector2i(SizeCheck.LIMIT, 16), "at the size asked for")


func test_a_document_step_outside_the_box_is_refused_and_the_document_kept() -> void:
    for pair: Array in [[-5, 10], [10, 0], [20000, 10]]:
        var before: Vector2i = _canvas.document.canvas_size
        var made := _children()
        var answer := _ask({"document": "srgb", "size": pair})
        _assert_refused(answer, "document srgb", SizeCheck.written(pair))
        assert_eq(_holding(answer.get("verdicts"), "a new").size(), 0, "nothing was made: %s" % str(answer.get("verdicts")))
        assert_eq(_canvas.document.canvas_size, before, "%s left the size at %s" % [str(pair), before])
        assert_eq(_canvas.canvas_size, before, "as it left the canvas's")
        assert_eq(_children(), made, "and %s left the open document's layers as they were" % str(pair))


func test_a_document_step_at_the_largest_side_opens_at_it() -> void:
    var answer := _ask({"document": "srgb", "size": [SizeCheck.LIMIT, 16]})
    assert_eq(answer.get("errors"), [], "the largest side is taken: %s" % str(answer.get("errors")))
    var wanted := Vector2i(SizeCheck.LIMIT, 16)
    assert_eq(_canvas.document.canvas_size, wanted, "the document opens at it")
    assert_eq(_canvas.canvas_size, wanted, "and the canvas with it")


func test_default_and_an_absent_size_open_as_they_did() -> void:
    var answer := _ask({"document": "srgb"})
    assert_eq(answer.get("errors"), [], "no size raises nothing: %s" % str(answer.get("errors")))
    assert_eq(_canvas.document.canvas_size, OPENED, "and keeps the canvas's own")
    answer = _ask({"document": "srgb", "size": "default"})
    assert_eq(answer.get("errors"), [], "default raises nothing: %s" % str(answer.get("errors")))
    assert_eq(_canvas.document.canvas_size, NewDocumentDialog.DEFAULT_SIZE, "and opens at File > New's size")


func test_the_limit_is_every_dialogs_limit() -> void:
    assert_eq(SizeCheck.LIMIT, SaResample.MAX_DIMENSION, "the resampler's, which Image Size reads")
    assert_eq(SizeCheck.LIMIT, SaImageSizeDialog.MAX_DIMENSION, "Image Size's")
    assert_eq(SizeCheck.LIMIT, SaCanvasSizeDialog.MAX_DIMENSION, "Canvas Size's")
    assert_eq(SizeCheck.LIMIT, NewDocumentDialog.MAX_DIMENSION, "and New Document's, so the four cannot drift apart")


func test_a_pair_is_written_as_the_scenario_wrote_it() -> void:
    assert_eq(SizeCheck.written([0.0, 100.0]), "[0, 100]", "a JSON number loses its .0")
    assert_eq(SizeCheck.written([16385, -1]), "[16385, -1]", "and an int is itself")
    assert_false(SizeCheck.is_pair(["a", "b"]), "two words are not a pair to judge")
    assert_false(SizeCheck.is_pair([1, 2, 3]), "nor three numbers")
