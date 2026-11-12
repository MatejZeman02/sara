## The door answers a step in its verdict lines, and with the dump only when
## asked.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## An answer that is the whole state dump runs a hundred and fifty thousand
## characters and up, which is past a small model's context before its first
## stroke. These open the door in this process over TCP, as
## `test_door_attach.gd` does, and run real steps through a real step table
## on a canvas of the suite's own: the steps a stroke splices are run between
## polls the way `SaCapture._process` runs them. What comes back is read for
## its verdict lines, its view line and its errors, and measured.
extends "res://tests/test_framework.gd"

const AgentDoor := preload("res://harness/door/sa_agent_door.gd")
const DoorLog := preload("res://harness/door/sa_door_log.gd")
const StepTable := preload("res://harness/sa_step_table.gd")
const CaptureRun := preload("res://harness/sa_capture_run.gd")
const Fixtures := preload("res://tests/fixtures.gd")
const DoorRunner := preload("res://tests/fixtures/door_runner.gd")

static var scratch_known: String = SaDataRoot.path("q1-door/door.json")
static var scratch_port_file: String = SaDataRoot.path("q1-door/door.port")
static var scratch_run_folder: String = SaDataRoot.path("q1-door-run")

## Rounds of polling before a case gives up on an answer, a few milliseconds
## each, enough for a stroke's frames and the settle after them.
const ROUNDS: int = 600

## What one stroke's answer may cost a client.
const BUDGET: int = 2000

## A stroke in the window's space, across the canvas.
const STROKE := {"stroke": {"from": [200, 300], "to": [600, 300], "steps": 6}}

var _host: Node = null
var _canvas: SaCanvas = null
## The canvas of the suite, held as the document in front, which is where the
## door's view line and its steps look.
var _front: Fixtures.FrontDocuments = null
var _door: AgentDoor = null
var _run: CaptureRun = null
var _runner: DoorRunner = null
var _table: StepTable = null


## Parented to an autoload, because the runner calls this from its own `_ready`
## and a parent mid-`_ready` rejects `add_child`.
func before_each() -> void:
    _host = Node.new()
    _host.name = "Q1DoorTestHost"
    EventBus.add_child(_host)
    _canvas = SaCanvas.new()
    _canvas.canvas_size = Vector2i(1920, 1080)
    _host.add_child(_canvas)
    _canvas.size = Vector2(1920, 1080)
    _front = Fixtures.FrontDocuments.over(_canvas)
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
    if _front != null:
        _front.put_back()
        _front = null
    if _host != null:
        _host.free()
        _host = null
        _canvas = null


## The answer to *request*, parsed, with the characters of its body under
## `"chars"`, the figure a client pays for it.
func _ask(client: StreamPeerTCP, request: Dictionary) -> Dictionary:
    return _runner.ask(client, request)


## The first verdict line of *answer* that holds *text*, or "".
static func _verdict(answer: Dictionary, text: String) -> String:
    for line: Variant in answer.get("verdicts", []):
        if String(line).contains(text):
            return String(line)
    return ""


func test_a_stroke_answers_in_its_verdict_the_view_and_the_errors() -> void:
    assert_true(_door.open_port(scratch_port_file), "The TCP way in opens")
    var client := _runner.connect_client()
    var request := STROKE.duplicate(true)
    request["id"] = 1
    var answer := _ask(client, request)
    assert_eq(answer.get("id"), 1.0, "The stroke is answered: %s" % answer)
    assert_true(bool(answer.get("ok", false)), "as done")
    var verdict := _verdict(answer, "SaCapture: stroke (200, 300) -> (600, 300)")
    assert_false(verdict.is_empty(), "with the stroke's own verdict line: %s" % answer.get("verdicts"))
    assert_true(String(answer.get("view", "")).begins_with("view: document 1920x1080, its (0, 0) at"), "a view line")
    assert_true(answer.get("errors") is Array and answer.get("warnings") is Array, "and the errors and warnings it raised")
    assert_false(answer.has("state"), "and no dump")
    assert_true(int(answer["chars"]) < BUDGET, "in %d characters, under %d" % [int(answer["chars"]), BUDGET])
    print("Figure: one stroke's answer is %d characters" % int(answer["chars"]))
    client.disconnect_from_host()


func test_the_same_request_with_dump_carries_the_state_report() -> void:
    assert_true(_door.open_port(scratch_port_file), "The TCP way in opens")
    var client := _runner.connect_client()
    var request := STROKE.duplicate(true)
    request["id"] = 2
    request["dump"] = true
    var answer := _ask(client, request)
    assert_true(answer.get("state") is Dictionary, "A request that sets dump gets the state report")
    var state: Dictionary = answer.get("state", {})
    assert_true(state.has("canvases") and state.has("vram_bytes"), "whole, %d keys" % state.size())
    var step: Dictionary = answer.get("step", {})
    assert_eq(step.keys(), ["stroke"], "and the rest of today's answer, the step without the door's keys")
    assert_true(answer.has("printed") and answer.has("frames"), "the log's lines and the frames settled")
    assert_false(_verdict(answer, "SaCapture: stroke (200, 300)").is_empty(), "beside the verdict lines")
    print("Figure: the same stroke's answer with dump is %d characters" % int(answer["chars"]))
    client.disconnect_from_host()


## The case the ask names: a client with no pipe to the process got a step's
## own `print` from the buffered run log late or never, and now has it in the
## answer to that step.
func test_an_attached_client_gets_the_verdict_its_step_printed() -> void:
    assert_true(_door.open_port(scratch_port_file), "The TCP way in opens")
    var client := _runner.connect_client()
    assert_true(bool(_ask(client, {"id": 1, "attach": true}).get("attached", false)), "The client attaches")
    var answer := _ask(client, {"id": 2, "comment": "the verdict of a comment"})
    assert_eq(answer.get("verdicts"), ["SaCapture: the verdict of a comment"], "It gets the line the step printed")
    client.disconnect_from_host()


## A line printed between two requests is nobody's verdict, and the door's
## own lines are never one.
func test_only_the_steps_own_lines_are_its_verdicts() -> void:
    assert_true(_door.open_port(scratch_port_file), "The TCP way in opens")
    var client := _runner.connect_client()
    assert_eq(_ask(client, {"id": 1}).get("verdicts"), [], "A request with no step has no verdict")
    print("SaCapture: printed while no step ran")
    var answer := _ask(client, {"id": 2, "comment": "mine"})
    assert_eq(answer.get("verdicts"), ["SaCapture: mine"], "and a step's answer holds its own line alone")
    client.disconnect_from_host()


## The painter's two and a half hour session left a 31 MB log, because each
## `layers` answer of the 540-layer mirrors file is one line of over a hundred
## thousand characters and the log took it whole. The client reads it whole
## from the answer, where it was always read, and the log keeps a line saying
## what it was and how long.
func test_a_long_verdict_is_cut_in_the_log_and_whole_in_the_answer() -> void:
    assert_true(_door.open_port(scratch_port_file), "The TCP way in opens")
    var heard := SaErrorCatcher.new()
    OS.add_logger(heard)
    var whole := "%slayers %s" % [SaDoorVerdicts.PREFIX, "x".repeat(SaDoorVerdicts.LOG_CHARS)]
    SaDoorVerdicts.say(whole)
    SaDoorVerdicts.say("%sa short one" % SaDoorVerdicts.PREFIX)
    OS.remove_logger(heard)

    var kept := _door._verdicts.take()
    assert_eq(Array(kept), [whole, "%sa short one" % SaDoorVerdicts.PREFIX], "The answer carries both lines as they were said")
    var longest := 0
    var said := ""
    for line: String in heard.printed():
        longest = maxi(longest, line.length())
        if line.contains("cut from"):
            said = line
    assert_true(longest <= SaDoorVerdicts.LOG_CHARS, "and the longest line the log got is %d characters" % longest)
    assert_true(said.begins_with("SaAgentDoor: layers xxx"), "one line in place of the long one, naming it: %s" % said.left(40))
    var size := "cut from %d characters, the answer holds it whole" % whole.length()
    assert_true(said.ends_with(size), "and its size: %s" % said.right(60))


func test_the_logger_goes_with_the_door() -> void:
    assert_true(_door.open_port(scratch_port_file), "The TCP way in opens")
    assert_true(_door._verdicts != null, "Listening installs the verdict logger")
    _door.close()
    assert_true(_door._verdicts == null, "and closing takes it out")


func test_the_view_line_says_where_the_document_sits() -> void:
    _canvas.position = Vector2(120, 80)
    _canvas.scale = Vector2(0.5, 0.5)
    _canvas.rotation = 0.0
    assert_eq(
        SaDoorGlance.view_line(),
        "view: document 1920x1080, its (0, 0) at (120.0, 80.0) in the window, zoom 0.5, turned 0.0 degrees",
        "the origin and the zoom of the view"
    )
    _canvas.scale = Vector2(-2, 2)
    _canvas.rotation = deg_to_rad(90.0)
    var line := SaDoorGlance.view_line()
    assert_true(line.contains("zoom 2.0,") and line.ends_with(", mirrored"), "a mirrored view says so: %s" % line)
    _front.put_back()
    _front = null
    assert_eq(SaDoorGlance.view_line(), "view: no canvas in front", "and no document in front says so")


## The lines come from the door's logger rather than the run log, and
## a flood is capped. A failed stroke's error stays under
## `errors` though its text is a verdict line as well.
func test_the_errors_and_warnings_keep_a_failed_steps_error() -> void:
    var failed := "ERROR: SaCapture: stroke (1, 1) -> (2, 2) failed at: _stroke (res://x.gd:9)"
    var script_error := "SCRIPT ERROR: Invalid call at: _ready (res://x.gd:3)"
    var taken := {"errors": [failed, script_error], "warnings": ["WARNING: a warning at: _w (res://x.gd:4)"]}
    var raised := DoorLog.raised_in(taken)
    var wanted: Array = [failed, script_error]
    assert_eq(raised["errors"], wanted, "each error with its origin, the failed stroke's among them")
    assert_eq(raised["warnings"], ["WARNING: a warning at: _w (res://x.gd:4)"], "and the warning")
    var many: Array = []
    for i in DoorLog.RAISED_CAP + 5:
        many.append("ERROR: number %d" % i)
    var capped: Array = DoorLog.raised_in({"errors": many})["errors"]
    assert_eq(capped.size(), DoorLog.RAISED_CAP + 1, "a flood stops at the cap")
    assert_eq(capped.back(), "and 5 more", "and says how many more")


## A long path in the message must not take the origin with it: the file and
## line are what the client acts on, and the cut once fell from the end.
func test_a_long_line_keeps_its_origin() -> void:
    var path := "/a-deep-settings-folder/" + "x".repeat(400)
    var long := "ERROR: Error loading image: '%s'. at: read_with_engine (res://harness/x.gd:42)" % path
    var kept: String = DoorLog.raised_in({"errors": [long]})["errors"][0]
    assert_true(kept.length() <= DoorLog.RAISED_CHARS + 3 + DoorLog.ORIGIN_CHARS, "the line is cut, %d" % kept.length())
    assert_true(kept.length() < long.length(), "shorter than it was")
    assert_true(kept.ends_with("at: read_with_engine (res://harness/x.gd:42)"), "and still ends in its origin: %s" % kept)
    assert_true(kept.begins_with("ERROR: Error loading image"), "and still begins with its message")
    var short := "ERROR: short at: f (res://y.gd:1)"
    assert_eq(DoorLog.cut(short), short, "a short line is as it was")
    var bare := "ERROR: " + "y".repeat(400)
    assert_eq(DoorLog.cut(bare).length(), DoorLog.RAISED_CHARS, "a long line with no origin is cut at the cap")
