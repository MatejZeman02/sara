## A stroke the door sends never hides a layer.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A painting made through the door can find layers hidden
## though its steps never wrote a visibility. The strokes ran down the
## canvas's right edge, which sat under the Layers docker, and with the docker
## let out as a window of its own the input driver addressed each press to it.
## A press on a row's eye is a click and a press that runs down the eye column
## is a sweep, so a stroke toggled layers it never named. These stand the real
## Layers docker as a window of its own over the canvas's right edge with three
## layers, send strokes whose presses land on the eyes, and read every layer
## still visible. `force_native` stands in for the preference the way
## `test_a_stroke_under_a_let_out_docker_names_the_docker_and_the_way_round.gd`
## has it.
extends "res://tests/test_framework.gd"

## The brush needs a RenderingDevice, and the window a display.
const REQUIRES_GPU := true

const AgentDoor := preload("res://harness/door/sa_agent_door.gd")
const StepTable := preload("res://harness/sa_step_table.gd")
const CaptureRun := preload("res://harness/sa_capture_run.gd")
const Fixtures := preload("res://tests/fixtures.gd")
const MainCanvasScript := preload("res://render/main_canvas.gd")
const LayersDockerScript := preload("res://ui/dockers/layers/layers_docker.gd")
const DoorRunner := preload("res://tests/fixtures/door_runner.gd")

static var scratch_known: String = SaDataRoot.path("c2-door/door.json")
static var scratch_port_file: String = SaDataRoot.path("c2-door/door.port")
static var scratch_run_folder: String = SaDataRoot.path("c2-door-run")

## Rounds of polling before a case gives up on an answer, a few milliseconds
## each.
const ROUNDS: int = 600

## Where the docker is let out and how big, in root units. A compositor that
## places windows itself, as the gate's nested one does, puts it where it
## pleases, so every point below is read back from `rect_in`.
const DOCKER_AT := Vector2i(300, 100)
const DOCKER_SIZE := Vector2i(360, 520)

var _host: Node = null
var _main: Node = null
var _docker: LayersDocker = null
var _door: AgentDoor = null
var _run: CaptureRun = null
var _runner: DoorRunner = null
var _table: StepTable = null


## Parented to an autoload, because the runner calls this from its own `_ready`
## and a parent mid-`_ready` rejects `add_child`.
func before_each() -> void:
    SaCursorPolicy.forget_pointer_device()
    _host = Node.new()
    _host.name = "C2DoorTestHost"
    EventBus.add_child(_host)
    _main = MainCanvasScript.new()
    _host.add_child(_main)
    _main.bind_tools(Fixtures.make_tool_registry())
    _main.notification(Container.NOTIFICATION_SORT_CHILDREN)
    var doc: SaDocument = _main.canvas.document
    SaLayerOps.new(doc).add()
    SaLayerOps.new(doc).add()
    _docker = LayersDockerScript.new()
    _docker.name = "LayersDocker"
    _docker.visible = false
    _docker.force_native = true
    _docker.position = DOCKER_AT
    _docker.size = DOCKER_SIZE
    _docker.target_canvas = _main.canvas
    _host.add_child(_docker)
    _docker.show()
    _docker.sync_layer_list()
    # Sorted as the engine would a frame on, so an eye has the rectangle a press
    # can land on.
    for container: Node in _docker.find_children("*", "Container", true, false):
        (container as Container).notification(Container.NOTIFICATION_SORT_CHILDREN)
    _door = AgentDoor.new(scratch_known)
    _run = CaptureRun.new(scratch_run_folder)
    _table = StepTable.new(_run)
    _runner = DoorRunner.new(_door, _table, _run, ROUNDS, scratch_known)


func after_each() -> void:
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


func _ask(client: StreamPeerTCP, request: Dictionary) -> Dictionary:
    return _runner.ask(client, request)


## The lines of *lines* that hold *text*.
static func _holding(lines: Variant, text: String) -> Array:
    var out: Array = []
    for line: Variant in lines if lines is Array else []:
        if String(line).contains(text):
            out.append(String(line))
    return out


## The centre of row *index*'s eye in root units, which is where a hand would
## press to hide the layer.
func _eye(index: int) -> Vector2:
    var root := (Engine.get_main_loop() as SceneTree).root
    var inside: Rect2 = _docker.item_list.rows[index].eye_btn.get_global_rect()
    return SaCursorPolicy.rect_in(root, _docker).position + inside.get_center()


## How many of the document's layers are not visible.
func _hidden() -> Array:
    var out: Array = []
    for layer: SaLayer in SaLayerOps.new(_main.canvas.document).layers():
        if not layer.visible:
            out.append(str(layer.name))
    return out


## Sends *from* to *to* as a stroke the door carries and answers what came back.
func _send(from: Vector2, to: Vector2) -> Dictionary:
    assert_true(_door.open_port(scratch_port_file), "The TCP way in opens")
    var client := _runner.connect_client()
    var spec := {"from": [from.x, from.y], "to": [to.x, to.y], "steps": 12, "pressure": 0.8}
    var answer := _ask(client, {"id": 1, "stroke": spec})
    client.disconnect_from_host()
    return answer


func test_the_docker_has_three_rows_and_their_eyes_are_inside_it() -> void:
    assert_false(_docker.is_embedded(), "The docker is a window of its own")
    assert_eq(_docker.item_list.rows.size(), 4, "over three layers and the Background")
    var root := (Engine.get_main_loop() as SceneTree).root
    var rect := SaCursorPolicy.rect_in(root, _docker)
    for i in 3:
        assert_true(rect.has_point(_eye(i)), "and row %d's eye at %s is inside %s" % [i, _eye(i), rect])
    assert_eq(_hidden(), [], "with every layer visible to begin with")


func test_a_short_stroke_pressed_on_an_eye_hides_no_layer() -> void:
    for i in 3:
        var answer := _send(_eye(i), _eye(i) + Vector2(4, 0))
        assert_eq(_hidden(), [], "after a stroke pressed on row %d's eye: %s" % [i, str(answer.get("verdicts"))])


func test_a_stroke_down_the_eye_column_hides_no_layer() -> void:
    var answer := _send(_eye(0), _eye(2))
    assert_eq(_hidden(), [], "after a stroke down the eyes: %s" % str(answer.get("verdicts")))
    var failed := _holding(answer.get("errors"), "failed: no dab reached the GPU")
    assert_eq(failed.size(), 1, "and the stroke is one error: %s" % str(answer.get("errors")))
    if failed.size() == 1:
        assert_true(failed[0].contains("press was not sent"), "saying the press was not sent: %s" % failed[0])
        assert_true(failed[0].contains('"route": "tool"'), "and the way round: %s" % failed[0])
