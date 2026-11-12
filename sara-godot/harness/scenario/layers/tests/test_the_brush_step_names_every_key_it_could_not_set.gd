## The `brush` step names every key it could not set.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## `{"brush": {"preset": "Fill", "hardness": 0}}`
## answered `ok` and painted Fill as hard as before, because hardness is a
## resource holding its number under `value`, and `set_indexed` drops a number
## written over it without a word, as it dropped `ratio:value`. These open
## the door in this process over TCP, as
## `test_one_brush_step_sets_the_preset_the_colour_and_the_size.gd` does, and
## send the step through a real step table on a canvas of the suite's own, so
## what is checked is the answer a client reads.
extends "res://tests/test_framework.gd"

const AgentDoor := preload("res://harness/door/sa_agent_door.gd")
const StepTable := preload("res://harness/sa_step_table.gd")
const CaptureRun := preload("res://harness/sa_capture_run.gd")
const Fixtures := preload("res://tests/fixtures.gd")
const DoorRunner := preload("res://tests/fixtures/door_runner.gd")

## The canvas and the machine need a RenderingDevice.
const REQUIRES_GPU := true

static var scratch_known: String = SaDataRoot.path("r4-door/door.json")
static var scratch_port_file: String = SaDataRoot.path("r4-door/door.port")
static var scratch_run_folder: String = SaDataRoot.path("r4-door-run")

## Rounds of polling before a case gives up on an answer, a few milliseconds each.
const ROUNDS: int = 600

const DOCUMENT := Vector2i(320, 240)

## What the brush answers before its `unset`, so a line that lost it is told
## from a line that never came.
const VERDICT := "SaCapture: brush "

## Where the answer's object of keys that did not take begins.
const UNSET := ", unset "

## The modules whose tools the machine holds, kept registered for the case as
## they are in the app.
const MODULES: Array[String] = [
    "res://modules/sara-base-modules/stamp-brush/module.gd",
    "res://modules/sara-base-modules/base/module.gd",
]

var _host: Node = null
var _canvas: SaCanvas = null
var _machine: ToolMachine = null
var _ctx: SaContext = null
var _modules: Array[SaModule] = []
var _door: AgentDoor = null
var _run: CaptureRun = null
var _runner: DoorRunner = null
var _table: StepTable = null
var _client: StreamPeerTCP = null
var _foreground: Color = Color.BLACK

## The suite's canvas, held as the document in front, which is where a
## harness step and a door line look.
var _front: Fixtures.FrontDocuments = null


## Parented to an autoload, because the runner calls this from its own `_ready`
## and a parent mid-`_ready` rejects `add_child`.
func before_each() -> void:
    _foreground = SaColors.foreground
    _host = Node.new()
    _host.name = "R4BrushStepHost"
    EventBus.add_child(_host)
    _canvas = SaCanvas.new()
    _canvas.canvas_size = DOCUMENT
    _host.add_child(_canvas)
    _canvas.size = Vector2(DOCUMENT)
    _machine = ToolMachine.new()
    _machine.name = "ToolMachine"
    _canvas.add_child(_machine)
    _machine.bind(SaSurface.create(&"main", _canvas.easel, SaCanvasView.for_canvas(_canvas)), _registry())
    _machine.set_active_tool(&"brush")
    _front = Fixtures.FrontDocuments.over(_canvas)
    _door = AgentDoor.new(scratch_known)
    _run = CaptureRun.new(scratch_run_folder)
    _table = StepTable.new(_run)
    _runner = DoorRunner.new(_door, _table, _run, ROUNDS, scratch_known)
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
    SaColors.foreground = _foreground
    for module: SaModule in _modules:
        module.unregister(_ctx)
    _modules.clear()
    _ctx = null
    if _machine != null:
        _machine.registered_tools.clear()
        _machine.active_tool = null
        _machine.registry = null
    if _host != null:
        _host.free()
    _host = null
    _canvas = null
    _machine = null


## The built-in tools, as `Fixtures.make_tool_registry` builds them, with the
## modules left registered until the case ends.
func _registry() -> SaToolRegistry:
    var registry := SaToolRegistry.new()
    _ctx = SaContext.create(
        registry,
        SaBlendModeRegistry.new(),
        SaCommandRegistry.new(),
        SaLayerTypeRegistry.new(),
        SaUIRegistry.new(),
        null,
        Callable(),
        Callable(),
        null,
        SaRoleRegistry.new()
    )
    for path: String in MODULES:
        var module: SaModule = load(path).new()
        module.register(_ctx.for_module(module.get_id()))
        _modules.append(module)
    return registry


## The door's whole answer to `{"brush": spec}`.
func _ask(spec: Dictionary) -> Dictionary:
    return _runner.ask(_client, {"brush": spec})


## The `brush` verdict line in *answer*, or "" when none came.
static func _verdict(answer: Dictionary) -> String:
    for line: Variant in answer.get("verdicts", []):
        if String(line).begins_with(VERDICT):
            return String(line)
    return ""


## The keys *line* names under `unset`, or null when it names none at all.
static func _unset(line: String) -> Variant:
    var at := line.rfind(UNSET)
    if at < 0:
        return null
    return JSON.parse_string(line.substr(at + UNSET.length()))


func _settings() -> Resource:
    return _machine.get_tool(&"brush").get("settings") as Resource


func test_three_keys_that_set_nothing_are_named_two_with_the_path_that_reaches_them() -> void:
    var hardness := float(_settings().get_indexed("hardness:value"))
    var ratio := float(_settings().get_indexed("tip:ratio"))
    var answer := _ask({"hardness": 0.75, "ratio:value": 0.4, "hardnes": 0.3})
    var line := _verdict(answer)
    assert_true(bool(answer.get("ok", false)), "The step still answers ok, so a scenario keeps running: %s" % answer)
    var unset: Variant = _unset(line)
    assert_true(unset is Dictionary, "The answer names the keys it could not set under `unset`: %s" % line)
    if not unset is Dictionary:
        return
    var named: Dictionary = unset
    assert_eq(named.size(), 3, "All three keys are named and nothing else: %s" % line)
    assert_eq(named.get("hardness", ""), "hardness:value", "`hardness` with the path that reaches its value: %s" % line)
    assert_eq(named.get("ratio:value", ""), "tip:ratio", "`ratio:value` with the tip's ratio: %s" % line)
    assert_true(named.has("hardnes") and named["hardnes"] == null, "the misspelt key with no path: %s" % line)
    assert_almost_eq(float(_settings().get_indexed("hardness:value")), hardness, 1e-9, "and the hardness is as it was")
    assert_almost_eq(float(_settings().get_indexed("tip:ratio")), ratio, 1e-9, "and so is the tip's ratio")


func test_the_paths_it_names_set_their_fields_with_nothing_under_unset() -> void:
    var answer := _ask({"hardness:value": 0.25, "tip:ratio": 0.5})
    var line := _verdict(answer)
    assert_almost_eq(
        float(_settings().get_indexed("hardness:value")), 0.25, 1e-6, "`hardness:value` sets the hardness: %s" % line
    )
    assert_almost_eq(float(_settings().get_indexed("tip:ratio")), 0.5, 1e-6, "`tip:ratio` sets the tip's ratio: %s" % line)
    assert_eq(_unset(line), {}, "and nothing is under `unset`: %s" % line)


func test_a_key_written_with_the_value_it_holds_is_set() -> void:
    _ask({"stabilizer_mode": 2})
    var line := _verdict(_ask({"stabilizer_mode": 2}))
    assert_eq(int(_settings().get("stabilizer_mode")), 2, "The mode is the one asked: %s" % line)
    assert_eq(_unset(line), {}, "so a write that changed nothing because nothing needed changing is not unset: %s" % line)
