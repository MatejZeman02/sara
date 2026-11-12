## A stroke the door sends under a docker let out of the main window says the
## docker took it, and names the way round.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## With `embed_subwindows` off every docker is a window of its own, and the
## input driver addresses a press to the window under the point, so the docker
## takes it. A verdict that scanned the embedded windows only would take a
## let-out docker for no cover and come out quiet, "nothing covers any
## of the points", with no error. These stand a docker as a window of its own
## over the press point, send the stroke through a real door over TCP, and read
## the answer's verdicts and errors. `force_native` stands in for the preference
## the way `test_every_answer_names_the_dialog_over_the_canvas.gd` has it, since
## the root refuses to stop embedding while an embedded window is shown.
extends "res://tests/test_framework.gd"

## The brush needs a RenderingDevice, and the window a display.
const REQUIRES_GPU := true

const AgentDoor := preload("res://harness/door/sa_agent_door.gd")
const StepTable := preload("res://harness/sa_step_table.gd")
const CaptureRun := preload("res://harness/sa_capture_run.gd")
const Fixtures := preload("res://tests/fixtures.gd")
const MainCanvasScript := preload("res://render/main_canvas.gd")
const PixelDriver := preload("res://harness/scenario/sa_scenario_pixels.gd")
const DoorRunner := preload("res://tests/fixtures/door_runner.gd")

static var scratch_known: String = SaDataRoot.path("c1-door/door.json")
static var scratch_port_file: String = SaDataRoot.path("c1-door/door.port")
static var scratch_run_folder: String = SaDataRoot.path("c1-door-run")

## Rounds of polling before a case gives up on an answer, a few milliseconds
## each.
const ROUNDS: int = 600

## The title of the docker let out over the stroke's press point.
const DOCKER := "Let-out Docker"

## The docker's size, and where the stroke starts and runs from its corner in
## root units: the press under the docker, the middle under it still and the
## release clear of it. Its corner is read back from `rect_in`, because a
## compositor that places windows itself, as the gate's nested one does, puts
## it where it pleases.
const DOCKER_AT := Vector2i(300, 300)
const DOCKER_SIZE := Vector2i(400, 300)
const PRESS_FROM_CORNER := Vector2(40, 100)
const RUN := Vector2(480, 0)

var _host: Node = null
var _main: Node = null
var _docker: Window = null
var _door: AgentDoor = null
var _run: CaptureRun = null
var _runner: DoorRunner = null
var _table: StepTable = null
var _folder: String = ""
var _press: Vector2 = Vector2.ZERO

## The suite's canvas, held as the document in front, which is where a
## harness step and a door line look.
var _front: Fixtures.FrontDocuments = null


## Parented to an autoload, because the runner calls this from its own `_ready`
## and a parent mid-`_ready` rejects `add_child`.
func before_each() -> void:
    SaCursorPolicy.forget_pointer_device()
    _host = Node.new()
    _host.name = "C1DoorTestHost"
    EventBus.add_child(_host)
    _main = MainCanvasScript.new()
    _host.add_child(_main)
    _main.bind_tools(Fixtures.make_tool_registry())
    _main.notification(Container.NOTIFICATION_SORT_CHILDREN)
    _front = Fixtures.FrontDocuments.over(_main.canvas as SaCanvas)
    _docker = Window.new()
    _docker.title = DOCKER
    _docker.visible = false
    _docker.force_native = true
    _docker.position = DOCKER_AT
    _docker.size = DOCKER_SIZE
    _host.add_child(_docker)
    _docker.show()
    var root := (Engine.get_main_loop() as SceneTree).root
    _press = SaCursorPolicy.rect_in(root, _docker).position + PRESS_FROM_CORNER
    _door = AgentDoor.new(scratch_known)
    _run = CaptureRun.new(scratch_run_folder)
    _table = StepTable.new(_run)
    _runner = DoorRunner.new(_door, _table, _run, ROUNDS, scratch_known)
    _folder = OS.get_temp_dir().path_join("sara-c1-door-%d" % OS.get_process_id())
    DirAccess.make_dir_recursive_absolute(_folder)


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
    _main = null
    _docker = null
    SaCursorPolicy.forget_pointer_device()
    for name in DirAccess.get_files_at(_folder):
        DirAccess.remove_absolute(_folder.path_join(name))
    DirAccess.remove_absolute(_folder)


func _ask(client: StreamPeerTCP, request: Dictionary) -> Dictionary:
    return _runner.ask(client, request)


## The lines of *lines* that hold *text*.
static func _holding(lines: Variant, text: String) -> Array:
    var out: Array = []
    for line: Variant in lines if lines is Array else []:
        if String(line).contains(text):
            out.append(String(line))
    return out


## The stroke across the docker, on *route* when one is named.
func _stroke(route: String) -> Dictionary:
    var release := _press + RUN
    var spec := {"from": [_press.x, _press.y], "to": [release.x, release.y], "steps": 12, "pressure": 0.8}
    if route != "":
        spec["route"] = route
    return {"stroke": spec}


## The active layer's alpha at window point *at*, through the `read_pixels`
## step's own read, found by mapping the point into the document.
func _alpha_at(at: Vector2) -> float:
    var canvas: SaCanvas = _main.canvas
    var doc: SaDocument = canvas.document
    var texel := canvas.get_global_transform_with_canvas().affine_inverse() * at
    var index := SaLayerOps.new(doc).layers().find(doc.active_layer)
    var rect := [int(texel.x), int(texel.y), 1, 1]
    var answer := PixelDriver.read_into(doc, {"layer": index, "rect": rect, "file": "texel.npy"}, _folder)
    var body := FileAccess.get_file_as_bytes(String(answer["path"]))
    return snappedf(body.decode_float(body.size() - 4), 0.001)


func test_a_docker_let_out_is_a_window_of_its_own_over_the_press() -> void:
    assert_false(_docker.is_embedded(), "The docker is a window of its own")
    var root := (Engine.get_main_loop() as SceneTree).root
    var rect := SaCursorPolicy.rect_in(root, _docker)
    assert_true(rect.has_point(_press), "and its rectangle in root units holds the press point: %s" % rect)


func test_a_stroke_under_a_let_out_docker_answers_one_error_naming_it_and_the_way_round() -> void:
    assert_true(_door.open_port(scratch_port_file), "The TCP way in opens")
    var client := _runner.connect_client()
    var answer := _ask(client, _stroke("").merged({"id": 1}))
    var failed := _holding(answer.get("verdicts"), "failed: no dab reached the GPU")
    assert_eq(failed.size(), 1, "The failure is one verdict line: %s" % str(answer.get("verdicts")))
    if failed.size() == 1:
        assert_true(failed[0].contains("'%s' covers" % DOCKER), "naming the docker that took the press: %s" % failed[0])
        assert_true(failed[0].contains('"route": "tool"'), "and the way round: %s" % failed[0])
    var raised := _holding(answer.get("errors"), "failed: no dab reached the GPU")
    assert_eq(raised.size(), 1, "and the same failure is the one error: %s" % str(answer.get("errors")))
    if raised.size() == 1:
        assert_true(raised[0].contains(DOCKER) and raised[0].contains('"route": "tool"'), "naming both: %s" % raised[0])
    client.disconnect_from_host()


func test_the_same_stroke_by_the_tool_route_paints_under_the_docker() -> void:
    assert_true(_door.open_port(scratch_port_file), "The TCP way in opens")
    var client := _runner.connect_client()
    var answer := _ask(client, _stroke("tool").merged({"id": 1}))
    assert_eq(answer.get("errors"), [], "The route raises nothing: %s" % str(answer.get("errors")))
    var said := _holding(answer.get("verdicts"), "SaCapture: stroke by the tool route")
    assert_eq(said.size(), 1, "and prints one line: %s" % str(answer.get("verdicts")))
    if said.size() == 1:
        assert_true(said[0].contains("under '%s'" % DOCKER), "naming the docker it went under: %s" % said[0])
    assert_true(_alpha_at(_press + RUN / 2.0) > 0.5, "and there is paint at the stroke's middle, under the docker")
    client.disconnect_from_host()
