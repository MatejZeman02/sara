## A `kernel` step whose `params` name a field the kernel does
## not declare is refused by Sara before it dispatches, naming each unknown word
## and the parameters the kernel declares.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A notebook refuses a misspelt word on a cell's line in the client,
## but a script calling `doc.kernel` itself, or any client that is not the
## notebook, would run the kernel at the field's default and say nothing. These open
## the door in this process over TCP, as `test_the_door_answers_a_failed_stroke_and_a_document_once.gd`
## does, and send the step through a real step table, which is the way every
## client's step arrives.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const AgentDoor := preload("res://harness/door/sa_agent_door.gd")
const StepTable := preload("res://harness/sa_step_table.gd")
const CaptureRun := preload("res://harness/sa_capture_run.gd")
const Fixtures := preload("res://tests/fixtures.gd")
const DoorRunner := preload("res://tests/fixtures/door_runner.gd")

static var scratch_known: String = SaDataRoot.path("u7-door/door.json")
static var scratch_port_file: String = SaDataRoot.path("u7-door/door.port")
static var scratch_run_folder: String = SaDataRoot.path("u7-door-run")

## Rounds of polling before a case gives up on an answer, a few milliseconds
## each.
const ROUNDS: int = 600

## What the step's verdict line opens with.
const VERDICT := "SaCapture: kernel "

## A kernel declaring `amount`, which a run writes into a layer named after it.
const INVERT := """kernel u7_invert

image src: readonly
image dst

params:
    float amount

def u7_invert():
    vec4 c = image_load(src, pixel)
    image_store(dst, pixel, vec4(mix(c.rgb, vec3(1.0) - c.rgb, amount), 1.0))
"""

## A kernel declaring no parameter at all.
const FLAT := """kernel u7_flat

image src: readonly
image dst

def u7_flat():
    image_store(dst, pixel, vec4(0.25, 0.5, 0.75, 1.0))
"""

## One workgroup's corner, so a dispatch that should not have happened would
## still have written one chunk to find.
const RECT := [0, 0, 16, 16]

var _host: Node = null
var _canvas: SaCanvas = null
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
    _host.name = "U7DoorTestHost"
    EventBus.add_child(_host)
    _canvas = SaCanvas.new()
    _canvas.canvas_size = Vector2i(640, 480)
    _host.add_child(_canvas)
    _canvas.size = Vector2(640, 480)
    _door = AgentDoor.new(scratch_known)
    _run = CaptureRun.new(scratch_run_folder)
    _table = StepTable.new(_run)
    _runner = DoorRunner.new(_door, _table, _run, ROUNDS, scratch_known)
    _front = Fixtures.FrontDocuments.over(_canvas)


func after_each() -> void:
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


## The `kernel` step's verdict for *kernel* sent through the door, or `{}` when
## the answer holds no verdict line of it.
func _kernel(client: StreamPeerTCP, kernel: Dictionary) -> Dictionary:
    var answer := _runner.ask(client, {"id": 1, "kernel": kernel})
    var lines: Variant = answer.get("verdicts")
    for line: Variant in lines if lines is Array else []:
        var at := String(line).find(VERDICT)
        if at >= 0:
            var parsed: Variant = JSON.parse_string(String(line).substr(at + VERDICT.length()))
            return parsed as Dictionary if parsed is Dictionary else {}
    return {}


## The names of the canvas document's layers, bottom first.
func _layer_names() -> Array:
    return SaLayerOps.new(_canvas.document).layers().map(func(layer: SaLayer) -> String: return String(layer.name))


func test_a_misspelt_parameter_is_refused_naming_both_and_nothing_runs() -> void:
    assert_true(_door.open_port(scratch_port_file), "The TCP way in opens")
    var client := _runner.connect_client()
    var before := _layer_names()
    var verdict := _kernel(client, {"source": INVERT, "name": "u7_invert", "rect": RECT, "params": {"amout": 1.0}})
    assert_false(verdict.is_empty(), "The step answers its verdict line")
    assert_false(bool(verdict.get("ok", true)), "and refuses the misspelt word: %s" % [verdict])
    var said := String(verdict.get("error", ""))
    assert_true(said.contains("amout"), "naming the word the kernel lacks: %s" % said)
    assert_true(said.contains("amount"), "and the parameter it declares: %s" % said)
    assert_eq(said, "kernel u7_invert has no parameter called amout, its parameters are amount.", "in Sara's own sentence")
    assert_false(verdict.has("gpu_ms"), "No dispatch was timed: %s" % [verdict])
    assert_false(verdict.has("chunks"), "and no chunk was written")
    assert_eq(_layer_names(), before, "and no layer was added for the result")
    client.disconnect_from_host()


## The control: the same step spelt right dispatches, so the refusal above is
## the check's and not a kernel that could never have run.
func test_the_same_step_spelt_right_dispatches() -> void:
    assert_true(_door.open_port(scratch_port_file), "The TCP way in opens")
    var client := _runner.connect_client()
    var verdict := _kernel(client, {"source": INVERT, "name": "u7_invert", "rect": RECT, "params": {"amount": 1.0}})
    assert_true(bool(verdict.get("ok", false)), "The declared word runs: %s" % [verdict])
    assert_eq(int(verdict.get("chunks", 0)), 1, "and writes the chunk its rectangle reaches")
    assert_true(_layer_names().has("u7_invert"), "into a layer named after the kernel: %s" % [_layer_names()])
    client.disconnect_from_host()


func test_every_unknown_word_is_named_and_a_kernel_with_none_says_so() -> void:
    assert_true(_door.open_port(scratch_port_file), "The TCP way in opens")
    var client := _runner.connect_client()
    var two := _kernel(
        client, {"source": INVERT, "name": "u7_invert", "rect": RECT, "params": {"amount": 1.0, "amout": 1.0, "gian": 2.0}}
    )
    var said := String(two.get("error", ""))
    assert_false(bool(two.get("ok", true)), "One right word does not let the wrong ones through: %s" % [two])
    assert_eq(said, "kernel u7_invert has no parameter called amout or gian, its parameters are amount.", "both are named")
    var none := _kernel(client, {"source": FLAT, "name": "u7_flat", "rect": RECT, "params": {"amount": 1.0}})
    var flat_said := String(none.get("error", ""))
    assert_eq(flat_said, "kernel u7_flat has no parameter called amount, it declares none.", "a kernel with none says so")
    assert_false(_layer_names().has("u7_flat"), "and wrote nothing: %s" % [_layer_names()])
    client.disconnect_from_host()
