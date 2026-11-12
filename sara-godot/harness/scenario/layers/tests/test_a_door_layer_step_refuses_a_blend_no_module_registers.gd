## The door's layer step refuses a blend no module registers, so a misspelt
## blend never draws as Normal in silence.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A layer added with `"blend": "colour"`, the British
## spelling of the id `color`, was taken by the step, the layer drew as Normal, and
## the first word came at the next load. These open the door in this process
## over TCP, as the door's other suites do, on a real main canvas, and send the
## layer step and the brush step a misspelt mode and a registered one.
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

var _host: Node = null
var _door: AgentDoor = null
var _run: CaptureRun = null
var _runner: DoorRunner = null
var _table: StepTable = null
var _front: Fixtures.FrontDocuments = null
var _machine: ToolMachine = null
var _document: SaDocument = null


## Parented to an autoload, because the runner calls this from its own `_ready`
## and a parent mid-`_ready` rejects `add_child`.
func before_each() -> void:
    _host = Node.new()
    _host.name = "U882DoorHost"
    EventBus.add_child(_host)
    var main: Node = MainCanvasScript.new()
    _host.add_child(main)
    main.bind_tools(Fixtures.make_tool_registry())
    main.notification(Container.NOTIFICATION_SORT_CHILDREN)
    var canvas := main.canvas as SaCanvas
    _machine = canvas.get_node_or_null("ToolMachine") as ToolMachine
    _front = Fixtures.FrontDocuments.over(canvas)
    _document = canvas.document
    if canvas.document.compositor.registry == null:
        canvas.document.compositor.set_registry(Fixtures.make_registries().blend_modes)
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
    _machine = null
    _document = null
    if _host != null:
        _host.free()
        _host = null


## The answers to *requests*, sent in order on one connection.
func _ask(requests: Array) -> Array:
    assert_true(_door.open_port(scratch_port_file), "The TCP way in opens")
    var client := _runner.connect_client()
    var out: Array = []
    for request: Variant in requests:
        out.append(_runner.ask(client, request as Dictionary))
    return out


## The lines of *lines* that hold *text*.
static func _holding(lines: Variant, text: String) -> Array:
    var out: Array = []
    for line: Variant in lines if lines is Array else []:
        if String(line).contains(text):
            out.append(String(line))
    return out


func _layer(named: String) -> SaLayer:
    return SaScenarioPixels.named_target(_document, named)


func test_a_layer_given_colour_keeps_its_mode_and_the_errors_name_color() -> void:
    var answers := _ask(
        [
            {"id": 1, "layer": {"add": "red-streak-night-autumn"}},
            {"id": 2, "layer": {"of": "red-streak-night-autumn", "blend": "colour", "opacity": 0.5}},
        ]
    )
    var layer := _layer("red-streak-night-autumn")
    assert_not_null(layer, "The layer was added: %s" % str(answers[0]))
    if layer == null:
        return
    assert_eq(layer.blend_mode, SaLayer.BLEND_MODE.NORMAL, "The layer's mode is left as it was")
    var raised := _holding(answers[1].get("errors"), "'colour'")
    assert_eq(raised.size(), 1, "The refusal is one error: %s" % str(answers[1]))
    if raised.size() == 1:
        assert_true(String(raised[0]).contains("'color'"), "naming the registered id nearest: %s" % raised[0])
    assert_almost_eq(layer.opacity, 0.5, 0.0001, "and the step went on with its other keys")


func test_a_layer_given_multiply_takes_it_with_no_error() -> void:
    var answers := _ask(
        [
            {"id": 1, "layer": {"add": "shade"}},
            {"id": 2, "layer": {"of": "shade", "blend": "multiply"}},
        ]
    )
    var layer := _layer("shade")
    assert_not_null(layer, "The layer was added: %s" % str(answers[0]))
    if layer == null:
        return
    assert_eq(layer.blend_mode, &"multiply", "The mode is set: %s" % str(answers[1]))
    assert_eq(answers[1].get("errors"), [], "and nothing is raised")


func test_the_brush_given_colour_keeps_its_blend_and_the_errors_name_color() -> void:
    var answers := _ask([{"id": 1, "brush": {"blend_mode": "colour"}}])
    var settings: Resource = _machine.get_tool("brush").settings
    assert_eq(settings.get("blend_mode"), SaLayer.BLEND_MODE.NORMAL, "The brush's blend is left as it was")
    var raised := _holding(answers[0].get("errors"), "'colour'")
    assert_eq(raised.size(), 1, "The refusal is one error: %s" % str(answers[0]))
    if raised.size() == 1:
        assert_true(String(raised[0]).contains("'color'"), "naming the registered id nearest: %s" % raised[0])
