## A stroke at a pen's own rate sends each frame every report due since the
## frame before.
##
## A frame-paced stroke sends one move a frame however long the frame took, so
## a slow frame never meets the heap of motions a pen leaves behind it, and the
## loop a painter's hand drives on a slow machine cannot be measured. These run
## the step's frames by hand, with a recording driver in place of the one that
## injects, and hold that every report goes out once and in order, that a long
## frame is followed by the reports of all of it, and that the stroke ends with
## its release and its verdict. The running app's half is the unit's scenario,
## `scenarios/a-small-brush-keeps-up-with-the-pen-on-windows.json`.
extends "res://tests/test_framework.gd"

const CaptureRun := preload("res://harness/sa_capture_run.gd")
const ScenarioStroke := preload("res://harness/scenario/sa_scenario_stroke.gd")


## The input driver with its burst written down rather than injected.
class RecordingInput:
    extends "res://harness/drivers/sa_input_driver.gd"

    var bursts: Array = []

    func motion_burst(raw: Variant) -> void:
        bursts.append((raw as Array).duplicate(true))


var _run: CaptureRun = null
var _input: RecordingInput = null
var _stroke: ScenarioStroke = null


func before_each() -> void:
    _run = CaptureRun.new()
    _input = RecordingInput.new(_run)
    _stroke = ScenarioStroke.new(_run, _input)


func after_each() -> void:
    _stroke = null
    _input = null
    _run = null


## The step's expansion: a move and a press, then the paced step itself in
## place of a move a frame, carrying every report and the verdict.
func test_a_rate_expands_into_one_paced_step() -> void:
    _stroke.stroke({"from": [100, 200], "to": [300, 200], "steps": 20, "rate": 1000})
    assert_eq(_run.steps.size(), 3, "A move, a press and one paced step")
    assert_true(_run.steps[0].has("move") and _run.steps[1].has("press"), "The press waits for the move to its point")
    var paced := (_run.steps[2]["stroke"] as Dictionary).get("paced", {}) as Dictionary
    assert_eq((paced["path"] as Array).size(), 21, "Twenty reports after the press point")
    assert_eq(paced["sent"], 1, "of which none is sent yet")
    assert_true(paced.has("verdict"), "and the verdict rides along to the end")


## Every report goes out once, in order, and a frame three times as long as the
## one before it is followed by three times the reports.
func test_each_frame_sends_every_report_due_and_none_twice() -> void:
    _stroke.stroke({"from": [100, 200], "to": [300, 200], "steps": 40, "rate": 1000})
    var paced := _next_paced(0)
    _stroke.stroke({"paced": paced})
    assert_eq(_input.bursts.size(), 0, "The first frame starts the clock and owes nothing")
    OS.delay_usec(5000)
    _stroke.stroke({"paced": _next_paced(0)})
    var short: int = (_input.bursts[0] as Array).size()
    assert_true(short >= 5, "Five milliseconds at a thousand reports a second owe five or more, sent %d" % short)
    OS.delay_usec(15000)
    _stroke.stroke({"paced": _next_paced(0)})
    var long: int = (_input.bursts[1] as Array).size()
    assert_true(long >= 15, "and fifteen owe fifteen or more, sent %d" % long)
    OS.delay_usec(30000)
    _stroke.stroke({"paced": _next_paced(0)})

    var sent: Array = []
    for burst: Array in _input.bursts:
        sent.append_array(burst)
    assert_eq(sent.size(), 40, "Every report after the press point went out")
    var last_x := 100.0
    for entry: Dictionary in sent:
        var x := float((entry["at"] as Array)[0])
        assert_true(x > last_x, "each one further along than the one before, %f after %f" % [x, last_x])
        last_x = x
    assert_eq(last_x, 300.0, "and the last is the stroke's end")


## Once the last report is out the step hands over to the release and the
## verdict, whose frame count is the frames the stroke took.
func test_the_last_frame_releases_and_reports_the_frames_it_took() -> void:
    _stroke.stroke({"from": [100, 200], "to": [300, 200], "steps": 4, "rate": 1000})
    _stroke.stroke({"paced": _next_paced(0)})
    OS.delay_usec(10000)
    _stroke.stroke({"paced": _next_paced(0)})
    var tail := _run.steps.slice(_run.step_index)
    assert_eq(tail.size(), 2, "The release and the verdict, and no paced step after them")
    assert_eq(tail[0].get("release", ""), "left", "The release first")
    var verdict := (tail[1]["stroke"] as Dictionary).get("report", {}) as Dictionary
    assert_eq(verdict.get("steps", -1), 2, "The verdict counts the two frames the paced step ran")


## A stroke at a rate with no driver to send it says so and splices nothing.
func test_a_rate_without_a_driver_sends_nothing() -> void:
    var alone := ScenarioStroke.new(_run)
    alone.stroke({"from": [100, 200], "to": [300, 200], "steps": 4, "rate": 1000})
    assert_eq(_run.steps.size(), 0, "No move and no press for a stroke that could not be paced")


## The paced step the run holds at or after *from*, taken out of the run as
## the runner would by stepping past it.
func _next_paced(from: int) -> Dictionary:
    for at: int in range(maxi(from, _run.step_index), _run.steps.size()):
        var step: Dictionary = _run.steps[at]
        if step.has("stroke") and (step["stroke"] as Dictionary).has("paced"):
            _run.step_index = at + 1
            return (step["stroke"] as Dictionary)["paced"]
    return {}
