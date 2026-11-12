## One `brush` step sets the preset, the colour and the size in pixels.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A client wants one command that sets colour, size and brush type before
## drawing. It took three
## steps, each with a trap: `pick_preset` needs the Brush Presets docker open,
## `colour` printed rather than answered, and `{"brush": {"radius": 12}}` set a
## brush twelve times the canvas's shorter side. These open the door in this
## process over TCP, as `test_the_door_answers_in_verdict_lines.gd` does, and
## send the step through a real step table on a canvas of the suite's own, with
## the real bar in the tree and no Brush Presets docker anywhere, which is the
## docker closed.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
const AgentDoor := preload("res://harness/door/sa_agent_door.gd")
const StepTable := preload("res://harness/sa_step_table.gd")
const CaptureRun := preload("res://harness/sa_capture_run.gd")
const Fixtures := preload("res://tests/fixtures.gd")
const StampSettingsScript := preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")
const DoorRunner := preload("res://tests/fixtures/door_runner.gd")

## The canvas, the bar and the machine need a RenderingDevice.
const REQUIRES_GPU := true

static var scratch_known: String = SaDataRoot.path("d27-door/door.json")
static var scratch_port_file: String = SaDataRoot.path("d27-door/door.port")
static var scratch_run_folder: String = SaDataRoot.path("d27-door-run")
static var scratch_presets: String = SaDataRoot.path("test_d27_presets")

## Rounds of polling before a case gives up on an answer, a few milliseconds each.
const ROUNDS: int = 600

## A document wider than it is tall, so a radius turned against the longer side
## would read differently.
const DOCUMENT := Vector2i(640, 480)

## A preset of an opacity nothing starts at, so its load is seen once the size
## and the colour have been written over it.
const AIR_OPACITY := 0.37

## The modules whose tools the machine holds, kept registered for the case so
## the colour on the bus reaches the brush's settings as it does in the app.
const MODULES: Array[String] = [
    "res://modules/sara-base-modules/stamp-brush/module.gd",
    "res://modules/sara-base-modules/base/module.gd",
]

var _host: Node = null
var _canvas: SaCanvas = null
var _machine: ToolMachine = null
var _bar: ToolOptionsBar = null
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
    ScratchFolder.clear(scratch_presets)
    _foreground = SaColors.foreground
    _host = Node.new()
    _host.name = "D27BrushStepHost"
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
    _bar = ToolOptionsBar.new()
    _bar.name = "ToolOptionsBar"
    _host.add_child(_bar)
    _bar.target_tool_machine = _machine
    _bar.preset_store.dir = scratch_presets
    var air: Resource = StampSettingsScript.new()
    air.opacity = AIR_OPACITY
    air.radius = 0.31
    _bar.preset_store.save_preset("Airbrush", air)
    _bar.preset_store.save_preset("Second Ink", StampSettingsScript.new())
    _bar._ready()
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
    _bar = null
    ScratchFolder.clear(scratch_presets)


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


## The `brush` verdict the door answers *spec* with, or "" when none came.
func _brush(spec: Dictionary) -> String:
    var answer := _runner.ask(_client, {"brush": spec})
    for line: Variant in answer.get("verdicts", []):
        if String(line).begins_with("SaCapture: brush"):
            return String(line)
    return ""


func _settings() -> Resource:
    return _machine.get_tool(&"brush").get("settings") as Resource


func _loaded() -> String:
    return _bar.preset_box.selected_preset


func test_the_three_keys_set_the_brush_with_the_presets_docker_closed() -> void:
    assert_null(_host.get_tree().root.find_child(SaDockerIds.BRUSH_PRESETS, true, false), "No Brush Presets docker is open")
    var trap := SaPresetPick.capture_pick(_host.get_tree(), "Airbrush")
    assert_true(trap.contains("no Brush Presets docker"), "so `pick_preset` has no preset to pick: %s" % trap)
    var answer := _brush({"preset": "Airbrush", "colour": "#4080c0", "radius_px": 12})
    assert_eq(_loaded(), "Airbrush", "The preset named is the one loaded: %s" % answer)
    assert_almost_eq(float(_settings().get("opacity")), AIR_OPACITY, 1e-6, "with its opacity in the hand")
    var colour: Color = _settings().get("color")
    assert_true(colour.is_equal_approx(Color.html("#4080c0")), "the colour asked for is the brush's: %s" % colour)
    var shorter := float(mini(DOCUMENT.x, DOCUMENT.y))
    assert_almost_eq(float(_settings().get("radius")), 12.0 / shorter, 1e-6, "and the radius is 12 over the shorter side")
    assert_true(answer.contains("preset 'Airbrush'"), "The answer names the preset: %s" % answer)
    assert_true(answer.contains("radius 12.00 px, stored 0.025000"), "the radius in pixels and as stored: %s" % answer)
    assert_true(answer.contains("#4080c0"), "the colour: %s" % answer)
    assert_true(
        answer.contains("opacity 0.37") and answer.contains("tool in hand brush"), "the opacity and the tool: %s" % answer
    )


func test_an_unknown_preset_changes_nothing_and_names_the_presets_on_offer() -> void:
    _brush({"preset": "Airbrush"})
    var radius := float(_settings().get("radius"))
    var colour: Color = _settings().get("color")
    var answer := _brush({"preset": "Airbrush Deluxe", "colour": "#ff0000", "radius_px": 40})
    assert_eq(_loaded(), "Airbrush", "The loaded preset is the one it was: %s" % answer)
    assert_almost_eq(float(_settings().get("radius")), radius, 1e-9, "and so is the radius")
    assert_true(Color(_settings().get("color")).is_equal_approx(colour), "and the colour")
    assert_true(
        answer.contains("found no preset named 'Airbrush Deluxe' and changed nothing"),
        "The answer says the name missed: %s" % answer
    )
    assert_true(answer.contains('"Airbrush"') and answer.contains('"Second Ink"'), "and names the presets on offer: %s" % answer)


func test_a_channel_above_one_keeps_its_value() -> void:
    var answer := _brush({"colour": [3.0, 0.5, 0.2]})
    var colour: Color = _settings().get("color")
    assert_almost_eq(colour.r, 3.0, 1e-6, "A channel above 1.0 reaches the brush whole (hard rule 5): %s" % answer)
    assert_true(answer.contains("colour [3.0000, 0.5000, 0.2000, 1.0000]"), "and the answer reads it unclamped: %s" % answer)


func test_radius_is_still_the_stored_fraction() -> void:
    var answer := _brush({"radius": 0.05})
    assert_almost_eq(float(_settings().get("radius")), 0.05, 1e-9, "`radius` writes the fraction as it did: %s" % answer)
    var shorter := float(mini(DOCUMENT.x, DOCUMENT.y))
    assert_true(answer.contains("radius %.2f px, stored 0.050000" % (0.05 * shorter)), "and the answer gives both: %s" % answer)
