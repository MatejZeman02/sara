## A door session keeps no step it has run.
##
## The door runs every request through `SaCaptureRun.steps`, and a stroke
## splices a step a frame into it, so a session of 5,000 strokes held about
## 95,000 steps it had run, about 2 KB each, and `splice` copied all of them at
## every stroke. A big brush's hundreds slowed by 1 to 3 percent from about the
## 3,000th stroke. `SaCapture._process` now has the run let go of them as it
## hands a frame to the door. This suite holds the run's half, and
## `scripts/test_five_thousand_strokes_big_or_small_paint_through_one_door_session.py`
## holds the session's.
extends "res://tests/test_framework.gd"

const CaptureRun := preload("res://harness/sa_capture_run.gd")


func _run_at(steps: Array, index: int) -> CaptureRun:
    var run := CaptureRun.new(SaDataRoot.path("test_h1_steps"), steps)
    run.step_index = index
    return run


func test_a_run_that_has_run_out_holds_no_step() -> void:
    var run := _run_at([{"wait": 1}, {"stroke": {"tool_event": {"event": "press"}}}, {"wait": 2}], 3)
    run.forget_the_steps_run()
    assert_eq(run.steps, [], "every step was run, so none is kept")
    assert_eq(run.step_index, 0, "and the next one spliced is the first")


func test_the_steps_still_to_come_are_kept_in_their_order() -> void:
    var run := _run_at([{"wait": 1}, {"wait": 2}, {"wait": 3}, {"wait": 4}], 2)
    run.forget_the_steps_run()
    assert_eq(run.steps, [{"wait": 3}, {"wait": 4}], "the two not yet run")
    assert_eq(run.step_index, 0, "and the next to run is the first of them")


func test_a_run_that_has_run_nothing_is_left_as_it_is() -> void:
    var scenario: Array = [{"wait": 1}, {"wait": 2}]
    var run := _run_at(scenario, 0)
    run.forget_the_steps_run()
    assert_true(is_same(run.steps, scenario), "the scenario's own list, not a copy of it")
    assert_eq(run.step_index, 0, "and its index where it was")


func test_a_thousand_strokes_through_the_door_leave_only_the_last_ones_frames() -> void:
    var run := _run_at([], 0)
    var frames: Array = []
    for i in 18:
        frames.append({"stroke": {"tool_event": {"event": "motion", "at": [i, i]}}})
    for stroke in 1000:
        run.forget_the_steps_run()
        run.splice(frames)
        run.step_index = run.steps.size()
    assert_eq(run.steps.size(), frames.size(), "one stroke's frames, not a thousand's")
