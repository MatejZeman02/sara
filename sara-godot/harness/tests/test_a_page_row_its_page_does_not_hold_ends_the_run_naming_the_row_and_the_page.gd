## A `page_row` step asked for a row its page does not hold ends the run with an
## error naming the row and the page.
##
## `the-docker-summoned` asked the Workspace page for `popup_palette`, which
## had moved to the Brushes page, and the step printed one line and carried
## on, so four steps shot a palette nobody had switched on. The step now pushes
## the miss as an error and moves the run past its last step.
##
## The page hangs under `EventBus`, for the reason `ui/page/tests/
## test_page_row_step.gd` gives: `SaPageDrive` walks a visible `Window`, and a
## suite may not add a `Window` of its own.
extends "res://tests/test_framework.gd"

const StepTable := preload("res://harness/sa_step_table.gd")
const CaptureRun := preload("res://harness/sa_capture_run.gd")

var _host: VBoxContainer = null
var _page: SaPage = null
var _knobs: SaPageDemo.Knobs = null


func _declare(ui: SaPage) -> void:
    ui.section("Kinds").toggle("Rolloff", _knobs, ^"rolloff")


func before_each() -> void:
    _knobs = SaPageDemo.Knobs.new()
    _host = VBoxContainer.new()
    _host.name = "U246Workspace"
    _page = SaPage.new(_declare)
    _page.declare_rows()
    _page.realize(_host)
    EventBus.add_child(_host)


func after_each() -> void:
    if _host != null:
        EventBus.remove_child(_host)
        _host.free()
    _host = null
    _page = null
    _knobs = null


## A scenario of four steps whose first is *page_row*, run up to that step.
func _run_first(page_row: Dictionary) -> CaptureRun:
    var steps: Array = [{"page_row": page_row}, {"wait": 5}, {"state": "after"}, {"shot": "after"}]
    var run := CaptureRun.new(SaDataRoot.path("test_steps"), steps)
    var table := StepTable.new(run)
    run.step_index = 1
    table.run(steps[0] as Dictionary)
    return run


func test_a_row_no_open_page_holds_ends_the_run_and_names_the_row_and_the_page() -> void:
    var run := _run_first({"row": "popup_palette", "value": true})
    assert_eq(run.step_index, run.steps.size(), "the steps after the miss are never run")
    var said := SaPageDrive.capture(Engine.get_main_loop() as SceneTree, {"row": "popup_palette"})
    assert_true(said.begins_with(SaPageDrive.MISS), "the answer is a miss: %s" % said)
    assert_true(said.contains("'popup_palette'"), "it names the row: %s" % said)
    assert_true(said.contains("'U246Workspace'"), "and the page it looked on: %s" % said)


func test_a_row_the_named_page_does_not_hold_names_both() -> void:
    var run := _run_first({"row": "popup_palette", "value": true, "page": "U246Workspace"})
    assert_eq(run.step_index, run.steps.size(), "the run ends there")
    var said := SaPageDrive.capture(Engine.get_main_loop() as SceneTree, {"row": "popup_palette", "page": "U246Workspace"})
    assert_true(said.contains("'popup_palette'") and said.contains("'U246Workspace'"), "row and page: %s" % said)


func test_a_row_the_page_holds_moves_and_the_run_goes_on() -> void:
    var run := _run_first({"row": "rolloff", "value": false})
    assert_eq(run.step_index, 1, "the next step is the wait after it")
    assert_false(_knobs.rolloff, "and the row moved")
