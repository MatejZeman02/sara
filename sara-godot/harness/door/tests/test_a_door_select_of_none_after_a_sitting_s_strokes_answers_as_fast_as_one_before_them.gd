## A door select of none after a run of strokes answers as
## fast as one before them.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A select none read as taking 8.26 s after 292 strokes. The steps log stamps every step
## of a request with the whole request's time, and that select was the last of
## a request of 28 steps, 14 of them strokes, so the 8.26 s was the strokes'.
## These hold the door to that case: a rectangle is
## selected, 250 short strokes, two points a pixel or
## two apart on the tool route, go through the door in requests of 50 inside
## it, and then a select none is sent alone and timed, with one more after it
## and one before the strokes to compare. Each answers inside half a second.
## The document is the main canvas's own, 1920 by 1080.
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

## Rounds of polling before a request gives up on an answer, a few
## milliseconds each. A request of 50 strokes takes many.
const ROUNDS: int = 20000

## The strokes of the run, and how many go in one request.
const STROKES: int = 250
const PER_REQUEST: int = 50

## The longest a lone select none may take to answer, in milliseconds.
const BOUND_MSEC: int = 500

## The rectangle the strokes paint inside.
const AREA := Rect2i(400, 300, 900, 400)

var _host: Node = null
var _door: AgentDoor = null
var _run: CaptureRun = null
var _runner: DoorRunner = null
var _table: StepTable = null
var _front: Fixtures.FrontDocuments = null
var _document: SaDocument = null
var _layer: SaLayer = null


## Parented to an autoload, because the runner calls this from its own `_ready`
## and a parent mid-`_ready` rejects `add_child`.
func before_each() -> void:
    _host = Node.new()
    _host.name = "RunDoorHost"
    EventBus.add_child(_host)
    var main: Node = MainCanvasScript.new()
    _host.add_child(main)
    main.bind_tools(Fixtures.make_tool_registry())
    main.notification(Container.NOTIFICATION_SORT_CHILDREN)
    _front = Fixtures.FrontDocuments.over(main.canvas as SaCanvas)
    _document = (main.canvas as SaCanvas).document
    # The document's own layer, in the document's own format, which a layer made
    # here with `SaLayer.new()` is not.
    _layer = _document.active_layer
    DirAccess.make_dir_recursive_absolute(scratch_run_folder)
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
    _document = null
    if _host != null:
        _host.free()
        _host = null


## The *index*th stroke of the run, two points a pixel or two apart inside
## `AREA`, spread over it the same way every run.
static func _stroke(index: int) -> Dictionary:
    var x := AREA.position.x + (index * 37) % AREA.size.x
    var y := AREA.position.y + (index * 53) % AREA.size.y
    var points := [{"at": [x, y], "pressure": 1.0}, {"at": [x + 1.5, y + 1.0], "pressure": 0.75}]
    return {"stroke": {"points": points, "space": "document", "route": "tool", "smoothing": false}}


## The answer to a lone select none on *client*, and how long it took.
func _timed_select_none(client: StreamPeerTCP, id: int) -> Array:
    var began := Time.get_ticks_msec()
    var answer := _runner.ask(client, {"id": id, "select": "none"})
    return [answer, Time.get_ticks_msec() - began]


func test_a_lone_select_none_after_250_strokes_answers_inside_half_a_second() -> void:
    assert_true(_door.open_port(scratch_port_file), "The TCP way in opens")
    var client := _runner.connect_client()
    var rect := [AREA.position.x, AREA.position.y, AREA.size.x, AREA.size.y]
    _runner.ask(client, {"id": 1, "select": rect})
    var before := _timed_select_none(client, 2)
    print("a lone select none before the strokes took %d ms" % int(before[1]))
    assert_true(int(before[1]) < BOUND_MSEC, "A select none before the strokes answers at once: %s" % str(before[0]))

    _runner.ask(client, {"id": 3, "select": rect})
    var sent := 0
    var painted_ms := 0
    while sent < STROKES:
        var batch: Array = []
        for index in range(sent, mini(sent + PER_REQUEST, STROKES)):
            batch.append(_stroke(index))
        var began := Time.get_ticks_msec()
        var answers: Variant = _runner.ask(client, batch)
        painted_ms += Time.get_ticks_msec() - began
        assert_false(str(answers).contains("refused by the"), "No stroke of the run is refused")
        sent += batch.size()
    print("%d strokes in requests of %d took %d ms" % [STROKES, PER_REQUEST, painted_ms])
    assert_false(_layer.chunks.is_empty(), "The run laid paint on the layer")
    assert_true(_document.selection.active, "and the rectangle still stands before the select")

    var dropped := _timed_select_none(client, 4)
    print("the lone select none after them took %d ms" % int(dropped[1]))
    assert_eq((dropped[0] as Dictionary).get("errors"), [], "The select raises nothing: %s" % str(dropped[0]))
    assert_false(_document.selection.active, "and drops the rectangle")
    assert_true(int(dropped[1]) < BOUND_MSEC, "A lone select none after 250 strokes answers inside half a second")

    var again := _timed_select_none(client, 5)
    print("a second select none took %d ms" % int(again[1]))
    assert_true(int(again[1]) < BOUND_MSEC, "and so does one after it, with nothing left to drop")
