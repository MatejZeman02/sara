## A batch of steps is undone by the name it was marked with.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Without a name, a client redoes a window by deleting its
## layer and sending every stroke again, because `undo` takes a count it would
## have to keep. These open the door over TCP on a main canvas of the
## suite's own, mark, paint strokes through it, and rewind: once to read the
## layer as it was before the mark and an answer of five steps, and once after
## the painter moved Ink's opacity on the real Layers docker, to read a refusal
## with nothing undone and then a forced rewind that goes through.
extends "res://tests/test_framework.gd"

## The brush needs a RenderingDevice, and the window a display.
const REQUIRES_GPU := true

const AgentDoor := preload("res://harness/door/sa_agent_door.gd")
const StepTable := preload("res://harness/sa_step_table.gd")
const CaptureRun := preload("res://harness/sa_capture_run.gd")
const Fixtures := preload("res://tests/fixtures.gd")
const MainCanvasScript := preload("res://render/main_canvas.gd")
const LayersDockerScript := preload("res://ui/dockers/layers/layers_docker.gd")
const PixelDriver := preload("res://harness/scenario/sa_scenario_pixels.gd")
const DoorRunner := preload("res://tests/fixtures/door_runner.gd")

static var scratch_known: String = SaDataRoot.path("door/door.json")
static var scratch_port_file: String = SaDataRoot.path("door/door.port")
static var scratch_run_folder: String = SaDataRoot.path("door-run")

## Rounds of polling before a case gives up on an answer.
const ROUNDS: int = 900

## Where the first stroke starts from the canvas's corner in root units, how
## far each runs, and how far apart they lie.
const FROM_CORNER := Vector2(60, 60)
const RUN := Vector2(240, 0)
const GAP := Vector2(0, 40)

var _host: Node = null
var _main: Node = null
var _docker: LayersDocker = null
var _door: AgentDoor = null
var _run: CaptureRun = null
var _runner: DoorRunner = null
var _table: StepTable = null
var _client: StreamPeerTCP = null
var _folder: String = ""

## The suite's canvas, held as the document in front, which is where a
## harness step and a door line look.
var _front: Fixtures.FrontDocuments = null


## Parented to an autoload, because the runner calls this from its own `_ready`
## and a parent mid-`_ready` rejects `add_child`.
func before_each() -> void:
    SaCursorPolicy.forget_pointer_device()
    _host = Node.new()
    _host.name = "U68DoorTestHost"
    EventBus.add_child(_host)
    _main = MainCanvasScript.new()
    _host.add_child(_main)
    _main.bind_tools(Fixtures.make_tool_registry())
    _main.notification(Container.NOTIFICATION_SORT_CHILDREN)
    _front = Fixtures.FrontDocuments.over(_main.canvas as SaCanvas)
    var doc: SaDocument = _main.canvas.document
    SaLayerOps.new(doc).add().name = "Ink"
    doc.undo_redo.clear_history()
    _docker = LayersDockerScript.new()
    _docker.name = "LayersDocker"
    _docker.visible = false
    _docker.target_canvas = _main.canvas
    _host.add_child(_docker)
    _docker.sync_layer_list()
    _door = AgentDoor.new(scratch_known)
    _run = CaptureRun.new(scratch_run_folder)
    _table = StepTable.new(_run)
    _runner = DoorRunner.new(_door, _table, _run, ROUNDS, scratch_known)
    _folder = OS.get_temp_dir().path_join("sara-door-%d" % OS.get_process_id())
    DirAccess.make_dir_recursive_absolute(_folder)
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
    if _host != null:
        _host.free()
        _host = null
    _main = null
    _docker = null
    SaCursorPolicy.forget_pointer_device()
    for name in DirAccess.get_files_at(_folder):
        DirAccess.remove_absolute(_folder.path_join(name))
    DirAccess.remove_absolute(_folder)


func _ask(request: Dictionary) -> Dictionary:
    return _runner.ask(_client, request)


## The first verdict line of *answer* holding *text*, or "" when none does.
static func _verdict(answer: Dictionary, text: String) -> String:
    for line: Variant in answer.get("verdicts", []):
        if String(line).contains(text):
            return String(line)
    return ""


## Stroke *i* through the door, in root units off the canvas's corner.
func _stroke(i: int) -> Dictionary:
    var from := (_main.canvas as SaCanvas).get_global_rect().position + FROM_CORNER + GAP * i
    var to := from + RUN
    var answer := _ask({"id": 100 + i, "stroke": {"from": [from.x, from.y], "to": [to.x, to.y], "steps": 12}})
    assert_eq(answer.get("errors"), [], "Stroke %d raises nothing: %s" % [i, answer])
    return answer


## The bytes of Ink over the box every stroke of a case lies in.
func _ink() -> PackedByteArray:
    var canvas: SaCanvas = _main.canvas
    var doc: SaDocument = canvas.document
    var back := canvas.get_global_transform_with_canvas().affine_inverse()
    var corner := back * (canvas.get_global_rect().position + FROM_CORNER - Vector2(20, 20))
    var span := back.basis_xform(RUN + GAP * 7 + Vector2(40, 40))
    var rect := [int(corner.x), int(corner.y), int(absf(span.x)), int(absf(span.y))]
    var index := SaLayerOps.new(doc).layers().find(doc.get_node("Ink"))
    var answer := PixelDriver.read_into(doc, {"layer": index, "rect": rect, "file": "ink.npy"}, _folder)
    return FileAccess.get_file_as_bytes(String(answer.get("path", "")))


func test_a_rewind_takes_five_strokes_back_to_the_layer_as_it_was_at_the_mark() -> void:
    _stroke(0)
    var before := _ink()
    var marked := _ask({"id": 1, "mark": "window"})
    assert_true(_verdict(marked, "SaCapture: mark window").length() > 0, "The mark is answered: %s" % marked)
    for i in range(1, 6):
        _stroke(i)
    assert_true(_ink() != before, "Five strokes changed Ink")
    var rewound := _ask({"id": 2, "rewind": "window"})
    var line := _verdict(rewound, "rewind window")
    assert_eq(line, "SaCapture: rewind window, 5 step(s) undone", "The rewind answers five steps: %s" % rewound)
    assert_eq(_ink(), before, "and Ink is as it was at the mark, the first stroke on it")
    var again := _ask({"id": 3, "rewind": "window"})
    assert_eq(_verdict(again, "rewind window"), "SaCapture: rewind window, 0 step(s) undone", "A second rewind undoes nothing")


func test_a_rewind_past_the_painters_change_is_refused_with_nothing_undone() -> void:
    _ask({"id": 1, "mark": "figure"})
    for i in 3:
        _stroke(i)
    var doc: SaDocument = _main.canvas.document
    var ink := doc.get_node("Ink") as SaLayer
    doc.set_active_layer(ink)
    _docker.opacity_slider.step_by_units(-30.0)
    assert_almost_eq(ink.opacity, 0.7, 0.0001, "The painter's slider moved Ink's opacity")
    var painted := _ink()
    var at := doc.undo_redo.get_current_action()
    var refused := _ask({"id": 2, "rewind": "figure"})
    var line := _verdict(refused, "rewind figure")
    assert_true(line.begins_with("SaCapture: refused rewind figure, the painter changed"), "The rewind is refused: %s" % refused)
    assert_true(line.contains('"force": true'), "and says how to ask anyway: %s" % line)
    assert_eq(doc.undo_redo.get_current_action(), at, "with nothing undone")
    assert_almost_eq(ink.opacity, 0.7, 0.0001, "the painter's opacity standing")
    assert_eq(_ink(), painted, "and the strokes on Ink")
    var forced := _ask({"id": 3, "rewind": "figure", "force": true})
    assert_eq(_verdict(forced, "rewind figure"), "SaCapture: rewind figure, 4 step(s) undone", "Forced, it goes: %s" % forced)
    assert_almost_eq(ink.opacity, 1.0, 0.0001, "the painter's opacity with it")


func test_a_mark_the_history_no_longer_holds_or_never_made_is_refused() -> void:
    _stroke(0)
    _ask({"id": 1, "mark": "sky"})
    var doc: SaDocument = _main.canvas.document
    doc.undo_redo.clear_history()
    var gone := _ask({"id": 2, "rewind": "sky", "force": true})
    assert_true(_verdict(gone, "rewind sky").contains("no longer holds the mark"), "A dropped mark is refused: %s" % gone)
    var never := _ask({"id": 3, "rewind": "cloud"})
    assert_true(_verdict(never, "rewind cloud").contains("no mark has that name"), "and a name never marked: %s" % never)
