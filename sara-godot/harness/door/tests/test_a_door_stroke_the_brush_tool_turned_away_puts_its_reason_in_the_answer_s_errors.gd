## A door stroke the brush tool turned away puts its reason in
## the answer's errors.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A rehearsal of 192 strokes on hidden
## layers laid nothing, and every answer had empty `errors`, so a script that
## reads `errors` painted nothing. These open the door in this
## process over TCP, as the door's other suites do, with the brush in hand on a
## real main canvas, and send a stroke on a hidden layer, on a locked one and on
## a visible one. The first two answer their refusal in `errors` and the verdict
## line as it was, the third answers with `errors` empty.
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

## Rounds of polling before a case gives up on an answer, a few milliseconds
## each.
const ROUNDS: int = 600

## the shape a painting client's strokes have.
## the shape a long painting session's strokes have.
const STROKE := {"route": "tool", "space": "document", "from": [300, 450], "to": [900, 450], "steps": 12}

var _host: Node = null
var _door: AgentDoor = null
var _run: CaptureRun = null
var _runner: DoorRunner = null
var _table: StepTable = null
var _front: Fixtures.FrontDocuments = null
var _layer: SaLayer = null


## Parented to an autoload, because the runner calls this from its own `_ready`
## and a parent mid-`_ready` rejects `add_child`.
func before_each() -> void:
    _host = Node.new()
    _host.name = "U593DoorHost"
    EventBus.add_child(_host)
    var main: Node = MainCanvasScript.new()
    _host.add_child(main)
    main.bind_tools(Fixtures.make_tool_registry())
    main.notification(Container.NOTIFICATION_SORT_CHILDREN)
    _front = Fixtures.FrontDocuments.over(main.canvas as SaCanvas)
    var doc: SaDocument = (main.canvas as SaCanvas).document
    _layer = SaLayer.new()
    _layer.name = "rim-dusk-winter"
    doc.add_child(_layer)
    doc.set_active_layer(_layer)
    _door = AgentDoor.new(scratch_known)
    _run = CaptureRun.new(scratch_run_folder)
    _table = StepTable.new(_run)
    _runner = DoorRunner.new(_door, _table, _run, ROUNDS, scratch_known, Callable(), Input.flush_buffered_events)


func after_each() -> void:
    if _front != null:
        _front.put_back()
        _front = null
    _door.close()
    _door = null
    _table = null
    _runner = null
    _run = null
    _layer = null
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


## The answer to one door stroke on the suite's layer.
func _stroke() -> Dictionary:
    assert_true(_door.open_port(scratch_port_file), "The TCP way in opens")
    var client := _runner.connect_client()
    return _ask(client, {"id": 1, "stroke": STROKE.duplicate(true)})


## The refusal of *answer* is one error, the same line as its verdict, which
## names *why*.
func _refused_in_errors(answer: Dictionary, why: String) -> void:
    assert_eq(answer.get("ok"), true, "ok keeps its meaning, the door called the step: %s" % str(answer))
    var said := _holding(answer.get("verdicts"), "refused by the")
    assert_eq(said.size(), 1, "The verdict says the refusal as before: %s" % str(answer.get("verdicts")))
    var raised := _holding(answer.get("errors"), "refused by the")
    assert_eq(raised.size(), 1, "and the refusal is one error: %s" % str(answer.get("errors")))
    if raised.size() == 1:
        assert_true(String(raised[0]).contains(why), "which says why: %s" % raised[0])
    assert_true(_layer.chunks.is_empty(), "The layer was left empty")


func test_a_stroke_on_a_hidden_layer_answers_its_refusal_in_errors() -> void:
    _layer.visible = false
    _refused_in_errors(_stroke(), "'rim-dusk-winter' is hidden")


func test_a_stroke_on_a_locked_layer_answers_its_refusal_in_errors() -> void:
    _layer.is_locked = true
    _refused_in_errors(_stroke(), "This layer is locked")


func test_a_stroke_on_a_visible_layer_answers_no_error() -> void:
    var answer := _stroke()
    assert_eq(answer.get("errors"), [], "The stroke raises nothing: %s" % str(answer))
    assert_eq(_holding(answer.get("verdicts"), "refused by the"), [], "and no verdict says refused")
    assert_false(_layer.chunks.is_empty(), "and the brush laid paint on the layer")
