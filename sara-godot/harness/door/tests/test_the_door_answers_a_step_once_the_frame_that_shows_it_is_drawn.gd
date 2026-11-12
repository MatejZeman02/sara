## The door answers a step once the frame that
## shows it is drawn.
##
## The door is opened in this process on the TCP way in, as `test_door_on_tcp`
## does, and its table is one whose `stroke` bumps a composite count the way the
## easel does. The frames drawn, the clock and the redraw the door asks for are
## the suite's own, handed to the door's wait, so a draw can be given or held
## back at will. `scripts/test_the_door_answers_a_step_once_the_frame_that_shows_it_is_drawn.py`
## paints 50 strokes in a real Sara and finds the same numbers there.
extends "res://tests/test_framework.gd"

const AgentDoor := preload("res://harness/door/sa_agent_door.gd")
const StepTable := preload("res://harness/sa_step_table.gd")
const CaptureRun := preload("res://harness/sa_capture_run.gd")
const Fixtures := preload("res://tests/fixtures.gd")
const DoorRunner := preload("res://tests/fixtures/door_runner.gd")

static var scratch_port_file: String = SaDataRoot.path("h2-door.port")

const ROUNDS: int = 400
const STROKES: int = 50
## What the pretend clock moves on each time it is read.
const TICK_MSEC: int = 400


## The document and the screen as the suite plays them.
class World:
    extends RefCounted

    var composites: int = 0
    ## Which painting is in front, as the door's wait reads it: a number that
    ## moves when another one comes forward, and no composite with it.
    var front: int = 1
    var frames: int = 0
    var now_msec: int = 0
    var asked: int = 0
    ## Whether a frame is drawn in each round of polling.
    var drawing: bool = true

    func tick() -> int:
        now_msec += TICK_MSEC
        return now_msec

    func ask(_root: Window) -> void:
        asked += 1


## A table whose `stroke` composites, whose `front` brings another painting
## forward and composites nothing, and whose every other step changes nothing.
class StrokeTable:
    extends StepTable

    var world: World = null

    func _init(held: World) -> void:
        super(CaptureRun.new(SaDataRoot.path("h2-door-run")))
        world = held

    func run(step: Dictionary) -> void:
        if step.has("stroke"):
            world.composites += 1
        elif step.has("front"):
            world.front += 1

    func state() -> Dictionary:
        return {}


var _door: AgentDoor = null
var _world: World = null
var _table: StrokeTable = null
var _run: CaptureRun = null
var _runner: DoorRunner = null


func before_each() -> void:
    _world = World.new()
    _door = AgentDoor.new()
    _door.drawn_wait.composites = func() -> int: return _world.composites
    _door.drawn_wait.front = func() -> int: return _world.front
    _door.drawn_wait.frames = func() -> int: return _world.frames
    _door.drawn_wait.clock = _world.tick
    _door.drawn_wait.ask = _world.ask
    _table = StrokeTable.new(_world)
    _run = CaptureRun.new(SaDataRoot.path("h2-door-run"))
    _runner = DoorRunner.new(_door, _table, _run, ROUNDS, scratch_port_file, Callable(), _count_drawn)


func after_each() -> void:
    _door.close()
    _door = null
    _table = null
    _runner = null
    _run = null
    _world = null


## The suite's part of a round of the app: a frame is drawn if the screen draws.
func _count_drawn() -> void:
    if _world.drawing:
        _world.frames += 1


func _ask(client: StreamPeerTCP, step: Variant) -> Dictionary:
    return _runner.ask(client, step)


func test_every_one_of_fifty_strokes_is_answered_with_a_later_drawn_frame() -> void:
    assert_true(_door.open_port(scratch_port_file), "The TCP way in opens")
    var client := _runner.connect_client()
    var before := -1.0
    var later := 0
    for i in STROKES:
        var answer := _ask(client, {"id": i, "stroke": {"from": [0, 0], "to": [10, 10]}})
        assert_true(bool(answer.get("ok", false)), "Stroke %d is answered" % i)
        assert_true(answer.has("drawn"), "Stroke %d says the frame that drew it" % i)
        if float(answer.get("drawn", 0.0)) > before:
            later += 1
        before = float(answer.get("drawn", 0.0))
    assert_eq(later, STROKES, "Every answer carries a drawn frame larger than the one before")
    assert_eq(_world.asked, STROKES, "and the redraw was asked for once per stroke, before its answer")
    client.disconnect_from_host()


func test_a_step_that_changed_nothing_is_answered_as_it_was() -> void:
    assert_true(_door.open_port(scratch_port_file), "The TCP way in opens")
    var client := _runner.connect_client()
    _world.drawing = false
    var answer := _ask(client, {"id": 1, "zoom": 2.0})
    assert_true(bool(answer.get("ok", false)), "A step that composited nothing is answered with no frame drawn")
    assert_false(answer.has("drawn"), "and carries no drawn key")
    assert_eq(_world.asked, 0, "and asks for no redraw")
    client.disconnect_from_host()


## The `front` step composites nothing,
## and the window still shows another painting afterwards. Read by the count
## alone, two paintings standing at the same composite is a step answered
## before its frame, and two standing at different ones is a wait for a frame
## nobody asked for, which ran out five seconds later.
func test_a_step_that_brought_another_painting_forward_is_answered_with_its_frame() -> void:
    assert_true(_door.open_port(scratch_port_file), "The TCP way in opens")
    var client := _runner.connect_client()
    var composited := _world.composites
    var answer := _ask(client, {"id": 7, "front": "the other painting"})
    assert_true(bool(answer.get("ok", false)), "The step is answered")
    assert_eq(_world.composites, composited, "with nothing composited")
    assert_true(answer.has("drawn"), "and the frame that shows the painting now in front")
    assert_eq(_world.asked, 1, "which the wait asked for")
    client.disconnect_from_host()


func test_a_draw_held_back_is_an_error_inside_the_bound() -> void:
    assert_true(_door.open_port(scratch_port_file), "The TCP way in opens")
    var client := _runner.connect_client()
    _world.drawing = false
    var began := Time.get_ticks_msec()
    var answer := _ask(client, {"id": 5, "stroke": {"from": [0, 0], "to": [10, 10]}})
    var took := Time.get_ticks_msec() - began
    assert_false(bool(answer.get("ok", true)), "A stroke whose draw never comes is answered with an error")
    assert_eq(answer.get("id"), 5.0, "to the request that was sent")
    var why := String(answer.get("error", ""))
    assert_true(why.contains("stroke"), "which names the step: %s" % why)
    assert_true(why.contains(str(_door.drawn_wait.bound_msec)), "and the bound: %s" % why)
    assert_eq(int(answer.get("bound_ms", 0)), _door.drawn_wait.bound_msec, "The bound is a key of its own")
    assert_false(answer.has("timed_out"), "It is an answer and not the client's timeout")
    assert_true(took < 5000, "and it came in %d ms of real time, not the client's 120 s" % took)
    assert_true(_world.now_msec >= _door.drawn_wait.bound_msec, "after the bound had passed on the door's clock")
    _world.drawing = true
    var next := _ask(client, {"id": 6, "stroke": {"from": [0, 0], "to": [10, 10]}})
    assert_true(bool(next.get("ok", false)), "The next stroke is answered once the screen draws again")
    assert_true(next.has("drawn"), "with its frame")
    client.disconnect_from_host()
