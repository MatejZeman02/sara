## The door answers a stroke a docker took once, with its error, and a
## `document` step with a verdict.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A stroke whose press a docker took answered its failure line twice under
## `verdicts` and nothing under `errors`, while the session's list held the
## error, and `{"document": "srgb"}` answered no verdict at all. These open the
## door in this process over TCP, as `test_the_door_reports_the_engines_errors.gd`
## does, and post the two steps through a real step table.
extends "res://tests/test_framework.gd"

const AgentDoor := preload("res://harness/door/sa_agent_door.gd")
const StepTable := preload("res://harness/sa_step_table.gd")
const CaptureRun := preload("res://harness/sa_capture_run.gd")
const Fixtures := preload("res://tests/fixtures.gd")
const DoorRunner := preload("res://tests/fixtures/door_runner.gd")

static var scratch_known: String = SaDataRoot.path("d9-door/door.json")
static var scratch_port_file: String = SaDataRoot.path("d9-door/door.port")
static var scratch_run_folder: String = SaDataRoot.path("d9-door-run")

## Rounds of polling before a case gives up on an answer, a few milliseconds
## each.
const ROUNDS: int = 600

## The title of the window that stands in for a docker over the press point.
const DOCKER := "Docker"

var _host: Node = null
var _door: AgentDoor = null
var _run: CaptureRun = null
var _runner: DoorRunner = null
var _table: StepTable = null

## The suite's canvas, held as the document in front, which is where a
## harness step and a door line look.
var _front: Fixtures.FrontDocuments = null


## Parented to an autoload, because the runner calls this from its own `_ready`
## and a parent mid-`_ready` rejects `add_child`.
func before_each() -> void:
    _host = Node.new()
    _host.name = "D9DoorTestHost"
    EventBus.add_child(_host)
    var canvas := SaCanvas.new()
    canvas.canvas_size = Vector2i(640, 480)
    _host.add_child(canvas)
    canvas.size = Vector2(640, 480)
    _door = AgentDoor.new(scratch_known)
    _run = CaptureRun.new(scratch_run_folder)
    _table = StepTable.new(_run)
    _runner = DoorRunner.new(_door, _table, _run, ROUNDS, scratch_known)
    _front = Fixtures.FrontDocuments.over(canvas)


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


func _ask(client: StreamPeerTCP, request: Dictionary) -> Dictionary:
    return _runner.ask(client, request)


## The lines of *lines* that hold *text*.
static func _holding(lines: Variant, text: String) -> Array:
    var out: Array = []
    for line: Variant in lines if lines is Array else []:
        if String(line).contains(text):
            out.append(String(line))
    return out


## A window embedded in the root over the press point, which is what a docker
## is to the stroke step's cover check.
func _docker_over(at: Vector2i) -> Window:
    var docker := Window.new()
    docker.title = DOCKER
    docker.position = at - Vector2i(40, 40)
    docker.size = Vector2i(120, 120)
    _host.add_child(docker)
    return docker


func test_a_stroke_under_a_docker_answers_one_verdict_and_its_error() -> void:
    assert_true(_door.open_port(scratch_port_file), "The TCP way in opens")
    var client := _runner.connect_client()
    var docker := _docker_over(Vector2i(100, 100))
    var path := [{"at": [100, 100]}, {"at": [110, 104]}]
    var answer := _ask(client, {"id": 1, "stroke": {"points": path}})
    var failed := _holding(answer.get("verdicts"), "failed: no dab reached the GPU")
    assert_eq(failed.size(), 1, "The failure is one verdict line: %s" % str(answer.get("verdicts")))
    if failed.size() == 1:
        assert_true(failed[0].contains("'%s'" % DOCKER), "naming the docker that took the press: %s" % failed[0])
    var raised := _holding(answer.get("errors"), "failed: no dab reached the GPU")
    assert_eq(raised.size(), 1, "and the same failure is under errors: %s" % str(answer.get("errors")))
    docker.queue_free()
    client.disconnect_from_host()


func test_a_document_step_answers_one_verdict() -> void:
    assert_true(_door.open_port(scratch_port_file), "The TCP way in opens")
    var client := _runner.connect_client()
    var answer := _ask(client, {"id": 1, "document": "srgb"})
    var said := _holding(answer.get("verdicts"), "SaCapture: document srgb")
    assert_eq(said.size(), 1, "The document step says what it made: %s" % str(answer.get("verdicts")))
    if said.size() == 1:
        assert_true(said[0].contains("640x480"), "the canvas it reset: %s" % said[0])
    assert_eq(answer.get("errors"), [], "and raised nothing: %s" % str(answer.get("errors")))
    client.disconnect_from_host()


## `sara.init()` opens the lesson's document at the size File >
## New offers, whatever canvas the painter had open, so the step takes a size.
func test_a_document_step_with_a_size_opens_the_canvas_at_it() -> void:
    assert_true(_door.open_port(scratch_port_file), "The TCP way in opens")
    var client := _runner.connect_client()
    var answer := _ask(client, {"id": 1, "document": "srgb", "size": "default"})
    var said := _holding(answer.get("verdicts"), "SaCapture: document srgb")
    assert_eq(said.size(), 1, "The step says what it made: %s" % str(answer.get("verdicts")))
    if said.size() == 1:
        assert_true(said[0].contains("1920x1080"), "the size File > New offers, not the 640x480 it replaced: %s" % said[0])
    var canvas: SaCanvas = SaCanvas.live_canvases()[0]
    assert_eq(canvas.canvas_size, NewDocumentDialog.DEFAULT_SIZE, "and the canvas is that size")
    assert_eq(canvas.document.canvas_size, NewDocumentDialog.DEFAULT_SIZE, "as is the document it holds")
    answer = _ask(client, {"id": 2, "document": "srgb", "size": [320, 200]})
    said = _holding(answer.get("verdicts"), "SaCapture: document srgb")
    var pair_said := str(answer.get("verdicts"))
    assert_true(said.size() == 1 and said[0].contains("320x200"), "a pair is a width and a height: %s" % pair_said)
    client.disconnect_from_host()


func test_a_size_that_says_nothing_leaves_the_size_to_the_canvas() -> void:
    var elsewhere := Vector2i(7, 7)
    assert_eq(SaScenarioDocument.size_of(null), Vector2i.ZERO, "no size is zero, which keeps the canvas's own")
    assert_eq(SaScenarioDocument.size_of("big"), Vector2i.ZERO, "a word that is not default is zero")
    assert_eq(SaScenarioDocument.size_of([1, 2, 3]), Vector2i.ZERO, "so is a list that is not a pair")
    assert_eq(SaScenarioDocument.size_of([elsewhere.x, elsewhere.y]), elsewhere, "a pair is itself")
    assert_eq(SaScenarioDocument.size_of("default"), NewDocumentDialog.DEFAULT_SIZE, "and default is the dialog's")
