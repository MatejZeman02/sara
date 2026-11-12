## A painting client sees what the painter changed before it paints.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A client sharing one running Sara with a painter through the door can paint
## from what it remembered: spellings of a renamed layer, strokes in the old
## place after a group moved, a layer hidden again after the painter showed it. These open the door
## over TCP on a main canvas of the suite's own with the real Layers docker
## beside it, change the document the way a painter does, through the docker's
## opacity slider and its Rename Layer dialog, and read the next answer saying
## so. `glance` is read naming the layer, the tool and the preset in hand, and
## the part of the document the window shows shrinking when a docker opens over
## the canvas.
extends "res://tests/test_framework.gd"

## The main canvas builds an easel, which needs a RenderingDevice.
const REQUIRES_GPU := true

const AgentDoor := preload("res://harness/door/sa_agent_door.gd")
const StepTable := preload("res://harness/sa_step_table.gd")
const CaptureRun := preload("res://harness/sa_capture_run.gd")
const Fixtures := preload("res://tests/fixtures.gd")
const MainCanvasScript := preload("res://render/main_canvas.gd")
const LayersDockerScript := preload("res://ui/dockers/layers/layers_docker.gd")
const DoorRunner := preload("res://tests/fixtures/door_runner.gd")

static var scratch_known: String = SaDataRoot.path("door/door.json")
static var scratch_port_file: String = SaDataRoot.path("door/door.port")
static var scratch_run_folder: String = SaDataRoot.path("door-run")

## Rounds of polling before a case gives up on an answer.
const ROUNDS: int = 600

## The preset the suite puts in the hand.
const PRESET := "Inker"

var _host: Node = null
var _main: Node = null
var _docker: LayersDocker = null
var _bar: ToolOptionsBar = null
var _door: AgentDoor = null
var _run: CaptureRun = null
var _runner: DoorRunner = null
var _table: StepTable = null
var _client: StreamPeerTCP = null

## The suite's canvas, held as the document in front, which is where a
## harness step and a door line look.
var _front: Fixtures.FrontDocuments = null


## Parented to an autoload, because the runner calls this from its own `_ready`
## and a parent mid-`_ready` rejects `add_child`.
func before_each() -> void:
    SaCursorPolicy.forget_pointer_device()
    _host = Node.new()
    _host.name = "U56DoorTestHost"
    EventBus.add_child(_host)
    _main = MainCanvasScript.new()
    _host.add_child(_main)
    _main.bind_tools(Fixtures.make_tool_registry())
    _main.notification(Container.NOTIFICATION_SORT_CHILDREN)
    _front = Fixtures.FrontDocuments.over(_main.canvas as SaCanvas)
    var doc: SaDocument = _main.canvas.document
    SaLayerOps.new(doc).add().name = "Sky"
    SaLayerOps.new(doc).add().name = "Ink"
    _docker = LayersDockerScript.new()
    _docker.name = "LayersDocker"
    _docker.visible = false
    _docker.target_canvas = _main.canvas
    _host.add_child(_docker)
    _docker.sync_layer_list()
    _bar = ToolOptionsBar.new()
    _bar.target_tool_machine = _main.canvas.tool_machine()
    _host.add_child(_bar)
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
    if _host != null:
        _host.free()
        _host = null
    _main = null
    _docker = null
    _bar = null
    SaCursorPolicy.forget_pointer_device()


func _ask(request: Dictionary) -> Dictionary:
    return _runner.ask(_client, request)


## The JSON after *prefix* on the first verdict line of *answer* opening with
## it, or {} when there is none.
static func _verdict_json(answer: Dictionary, prefix: String) -> Variant:
    for line: Variant in answer.get("verdicts", []):
        if String(line).begins_with(prefix):
            return JSON.parse_string(String(line).trim_prefix(prefix))
    return {}


func _glance() -> Dictionary:
    var answer := _ask({"id": 7, "glance": true, "settle": 0})
    var glance: Variant = _verdict_json(answer, "SaCapture: glance ")
    assert_true(glance is Dictionary and not (glance as Dictionary).is_empty(), "glance answers its line: %s" % answer)
    return glance if glance is Dictionary else {}


func test_the_next_answer_says_the_painter_changed_the_document_and_a_further_one_says_not() -> void:
    var first := _ask({"id": 1, "layer": {"opacity": 0.5}})
    assert_true(first.has("changed"), "Every answer says whether the document changed: %s" % first)
    var at := int(first.get("changes", -1))
    var quiet := _ask({"id": 2})
    assert_false(bool(quiet.get("changed", true)), "The door's own opacity step is not the painter's change: %s" % quiet)
    assert_eq(int(quiet.get("changes", -1)), at, "and does not move the counter")

    var doc: SaDocument = _main.canvas.document
    var ink := doc.get_node("Ink") as SaLayer
    var sky := doc.get_node("Sky") as SaLayer
    doc.set_active_layer(ink)
    _docker.opacity_slider.step_by_units(-30.0)
    assert_almost_eq(ink.opacity, 0.2, 0.0001, "The painter's slider moved Ink's opacity")
    doc.set_active_layer(sky)
    assert_true(_docker.open_rename_dialog(), "Rename Layer opens on Sky")
    # Read, never written: the docker keeps the dialog it opened, and the docker
    # is a Window with fields of its own, so a search from it finds its own.
    var dialog: Window = _docker._rename_dialog
    (dialog.find_child("NameEdit", true, false) as LineEdit).text = "Clouds"
    (dialog.find_child("OKButton", true, false) as Button).pressed.emit()
    assert_eq(str(sky.name), "Clouds", "and its OK renamed the layer")

    var after := _ask({"id": 3})
    assert_true(bool(after.get("changed", false)), "The next answer says the painter changed the document: %s" % after)
    assert_true(int(after.get("changes", -1)) >= at + 2, "the counter moved by the slider and the rename at least")
    var further := _ask({"id": 4, "layers": true})
    assert_false(bool(further.get("changed", true)), "and a further step's answer says it did not: %s" % further)
    assert_eq(int(further.get("changes", -1)), int(after.get("changes", -2)), "with the counter where it was")


func test_an_undo_by_hand_is_a_change() -> void:
    _ask({"id": 1, "layer": {"opacity": 0.5}})
    _main.canvas.document.undo()
    assert_true(bool(_ask({"id": 2}).get("changed", false)), "An undo the painter made is a change")


func test_glance_names_the_active_layer_the_tool_and_the_preset() -> void:
    _bar.preset_box.selected_preset = PRESET
    var answer := _ask({"id": 5, "glance": true, "settle": 0})
    var layers: Variant = _verdict_json(answer, "SaCapture: layers ")
    var active := ""
    for entry: Variant in layers if layers is Array else []:
        if bool((entry as Dictionary).get("active", false)):
            active = String((entry as Dictionary).get("name", ""))
    assert_eq(active, "Ink", "glance carries the layers line, naming the active layer: %s" % answer)
    var glance := _glance()
    assert_eq(String(glance.get("tool", "")), _run.active_tool_name(), "the tool in hand")
    assert_false(String(glance.get("tool", "<none>")) == "<none>", "which is one")
    assert_eq(String(glance.get("preset", "")), PRESET, "and the preset in hand")
    assert_eq(String(glance.get("colour", "")), "#" + SaColors.foreground.to_html(false), "with the colour")
    assert_true(glance.has("size") and glance.has("opacity") and glance.has("selection"), "size, opacity and selection")
    assert_eq(glance.get("selection"), null, "and no selection")
    var chars := JSON.stringify(answer).length()
    assert_true(chars < 3000, "and the whole answer fits on a screen: %d characters" % chars)


func test_glance_shows_less_of_the_document_when_a_docker_opens_over_the_canvas() -> void:
    var canvas: SaCanvas = _main.canvas
    var before: Variant = _glance().get("shows")
    assert_true(
        before is Array and (before as Array).size() == 4, "glance names the part of the document shown: %s" % str(before)
    )
    var root := (Engine.get_main_loop() as SceneTree).root
    var free := canvas.view().get_free_rect()
    var docker := Window.new()
    docker.name = "U56Docker"
    docker.borderless = true
    docker.position = Vector2i(int(free.end.x) - 400, int(free.position.y))
    docker.size = Vector2i(400, int(free.size.y))
    docker.add_to_group(SaCanvasView.SIDE_COVER_GROUP)
    _host.add_child(docker)
    assert_true(docker.is_embedded() and root.gui_embed_subwindows, "The stand-in docker embeds over the canvas")
    var after: Variant = _glance().get("shows")
    assert_true(after is Array and (after as Array).size() == 4, "and still names a part once it opens: %s" % str(after))
    if before is Array and after is Array:
        assert_true(float(after[2]) < float(before[2]), "a narrower one, %s against %s" % [str(after), str(before)])
    docker.free()
