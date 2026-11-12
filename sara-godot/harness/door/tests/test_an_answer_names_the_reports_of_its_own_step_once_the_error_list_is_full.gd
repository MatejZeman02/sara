## An answer names the reports of its own step once the door's list of the
## session's errors is full, and carries no line that names no error.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## After about 200 strokes that laid
## nothing in one Sara, every further one answered `"errors": ["and 1 more
## reports past the 200 kept"]` with ok true, where the first 200 carried no
## error, so a script that reads `errors` saw one event as fine and then as
## failed. Each of those strokes warns that it laid nothing, with its
## coordinates in the message, so each is a distinct report and the 200 filled
## the list. These open the door in this process over TCP with the brush in
## hand on a real main canvas, as the door's other stroke suites do, fill the
## logger past `CAP` and read the answers that follow.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const AgentDoor := preload("res://harness/door/sa_agent_door.gd")
const DoorErrors := preload("res://harness/report/sa_door_errors.gd")
const StepTable := preload("res://harness/sa_step_table.gd")
const CaptureRun := preload("res://harness/sa_capture_run.gd")
const Fixtures := preload("res://tests/fixtures.gd")
const MainCanvasScript := preload("res://render/main_canvas.gd")
const DoorRunner := preload("res://tests/fixtures/door_runner.gd")

static var scratch_known: String = SaDataRoot.path("error-cap-door/door.json")
static var scratch_port_file: String = SaDataRoot.path("error-cap-door/door.port")
static var scratch_run_folder: String = SaDataRoot.path("error-cap-door-run")

## Rounds of polling before a case gives up on an answer, a few milliseconds
## each.
const ROUNDS: int = 600

## A stroke at no pressure, which runs the brush and lays nothing, so its
## answer warns that it laid nothing, as the painter's did.
const BARE := {
    "route": "tool",
    "space": "document",
    "points": [{"at": [300, 300], "pressure": 0.0}, {"at": [301, 301], "pressure": 0.0}],
}

## The words every answer of the painter's carried once the list was full.
const PAST := "past the"

var _host: Node = null
var _door: AgentDoor = null
var _run: CaptureRun = null
var _runner: DoorRunner = null
var _table: StepTable = null
var _front: Fixtures.FrontDocuments = null
var _layer: SaLayer = null
## What the next frame raises, `ERROR` or `WARNING`, or "" for nothing. Raised
## once, in the frames the step's answer is waited for.
var _raise_next: String = ""


## Parented to an autoload, because the runner calls this from its own `_ready`
## and a parent mid-`_ready` rejects `add_child`.
func before_each() -> void:
    _host = Node.new()
    _host.name = "ErrorCapDoorHost"
    EventBus.add_child(_host)
    var main: Node = MainCanvasScript.new()
    _host.add_child(main)
    main.bind_tools(Fixtures.make_tool_registry())
    main.notification(Container.NOTIFICATION_SORT_CHILDREN)
    _front = Fixtures.FrontDocuments.over(main.canvas as SaCanvas)
    var doc: SaDocument = (main.canvas as SaCanvas).document
    _layer = SaLayer.new()
    _layer.name = "crowns"
    doc.add_child(_layer)
    doc.set_active_layer(_layer)
    _door = AgentDoor.new(scratch_known)
    _run = CaptureRun.new(scratch_run_folder)
    _table = StepTable.new(_run)
    _runner = DoorRunner.new(_door, _table, _run, ROUNDS, scratch_known, _raise_when_asked, Input.flush_buffered_events)
    _raise_next = ""


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
    if _host != null:
        _host.free()
        _host = null


## The suite's part of each frame, one report while a case asks for one.
func _raise_when_asked() -> void:
    if _raise_next == "ERROR":
        push_error("error cap: raised during the step")
    elif _raise_next == "WARNING":
        push_warning("error cap: warned during the step")
    _raise_next = ""


## Opens the door and connects a client to it, trusted by a first answer,
## since the door drops what was raised before it trusts a client.
func _open() -> StreamPeerTCP:
    assert_true(_door.open_port(scratch_port_file), "The TCP way in opens")
    var client := _runner.connect_client()
    _runner.ask(client, {"id": 0, "comment": "attached"})
    return client


## Fills the door's logger past its cap with distinct reports, each its own
## origin and message as a stroke's coordinates make its warning, and takes
## them as the answers of the steps that raised them would.
func _fill() -> void:
    for i in DoorErrors.CAP + 7:
        _door._errors._keep("WARNING", {"function": "_warn_if_bare", "file": "stroke.gd", "line": 710}, "laid nothing at %d" % i)
    _door._errors.take()
    assert_eq(DoorErrors.session_entries("all").back().get("count"), 7, "The list is full and counts what it left out")


## The lines of *lines* that hold *text*.
static func _holding(lines: Variant, text: String) -> Array:
    return (lines if lines is Array else []).filter(func(line: Variant) -> bool: return String(line).contains(text))


func test_a_step_that_raised_nothing_answers_no_error_once_the_list_is_full() -> void:
    var client := _open()
    _fill()
    var answer := _runner.ask(client, {"id": 1, "comment": "quiet"})
    assert_eq(answer.get("ok"), true, "The step ran: %s" % str(answer))
    assert_eq(answer.get("errors"), [], "and its answer has no error: %s" % str(answer))
    assert_eq(answer.get("warnings"), [], "and no warning")
    client.disconnect_from_host()


func test_a_report_raised_in_a_step_with_the_list_full_is_named_with_its_level_and_origin() -> void:
    var client := _open()
    _fill()
    var own: String = (get_script() as Script).resource_path
    _raise_next = "ERROR"
    var answer := _runner.ask(client, {"id": 1, "comment": "raises an error"})
    var errors: Array = answer.get("errors", [])
    assert_eq(errors.size(), 1, "The step's one error is in its answer: %s" % str(errors))
    if errors.size() == 1:
        var line := String(errors[0])
        assert_true(line.begins_with("ERROR: error cap: raised during the step"), "at its level: %s" % line)
        assert_true(line.contains(" at: _raise_when_asked (%s:" % own), "from where it was raised: %s" % line)
    assert_eq(_holding(errors, PAST), [], "and nothing says past the kept")
    _raise_next = "WARNING"
    var warned := _runner.ask(client, {"id": 2, "comment": "raises a warning"})
    assert_eq(warned.get("errors"), [], "A warning raised with the list full is no error: %s" % str(warned))
    var warnings: Array = warned.get("warnings", [])
    assert_eq(warnings.size(), 1, "it is the step's one warning: %s" % str(warnings))
    if warnings.size() == 1:
        assert_true(
            String(warnings[0]).begins_with("WARNING: error cap: warned during the step"), "at its level: %s" % warnings[0]
        )
        assert_true(String(warnings[0]).contains(" at: _raise_when_asked (%s:" % own), "from where it was raised")
    var listed := _runner.ask(client, {"id": 3, "errors": {"level": "all"}})
    assert_eq(_holding(listed.get("errors"), PAST), [], "The errors step's own answer carries no such line in errors")
    assert_eq(
        _holding(listed.get("verdicts"), "reports past the %d kept x9" % DoorErrors.CAP).size(),
        1,
        "and its verdicts count every report left out: %s" % str(listed.get("verdicts"))
    )
    client.disconnect_from_host()


## The same stroke, answered with the list empty and with it full, the second
## on a door opened afresh so the stroke's own warning is no entry yet.
func test_a_stroke_that_laid_nothing_answers_alike_before_and_after_the_list_fills() -> void:
    var client := _open()
    var before := _runner.ask(client, {"id": 1, "stroke": BARE.duplicate(true)})
    client.disconnect_from_host()
    _door.close()
    client = _open()
    _fill()
    var after := _runner.ask(client, {"id": 2, "stroke": BARE.duplicate(true)})
    assert_eq(
        _holding(before.get("verdicts"), "laid nothing on the layer").size() > 0,
        true,
        "The stroke laid nothing: %s" % str(before)
    )
    assert_eq(_holding(after.get("verdicts"), "laid nothing on the layer").size() > 0, true, "both times: %s" % str(after))
    assert_eq(
        after.get("errors"),
        before.get("errors"),
        "Its errors read alike: %s and %s" % [before.get("errors"), after.get("errors")]
    )
    assert_eq(after.get("warnings"), before.get("warnings"), "and so do its warnings: %s" % str(after.get("warnings")))
    assert_eq(
        _holding(before.get("warnings"), "laid nothing on the layer").size(),
        1,
        "which say it laid nothing: %s" % str(before.get("warnings"))
    )
    print(
        (
            "Error cap figure: a bare stroke answers errors %s and warnings %s before the list fills and after"
            % [before.get("errors"), before.get("warnings")]
        )
    )
    client.disconnect_from_host()
