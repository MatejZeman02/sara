## A `brush_editor` page step reopens an editor a `close` step hid, and a
## `curve_option` step that misses the editor says so.
##
## The two halves of the fix for a closed editor. `{"close": true}` is
## `window.hide()`, so the window stays in the tree: `capture_editor` found
## it and never showed it again, and `CurveOptionCapture.live_control`, which
## asks about visibility, found nothing and fell through to a throwaway option
## in the bare host without a word, which made a committed proof read its own
## before-state at the fourth dump.
##
## No window is opened here. Adding one in a headless run hangs
## (a window in a headless run hangs), so the running-app half is
## `scenarios/a-page-step-does-not-reopen-the-editor.json` and what is asserted here
## is the source, the scenario files and the one function that answers without a
## window in the tree.
extends "res://tests/test_framework.gd"

const CurveOptionCapture = preload("res://harness/captures/brush_editor_capture.gd")
const F89_SCENARIO := "res://scenarios/shared-curve-eats-the-sensor-curve.json"
const OWN_SCENARIO := "res://scenarios/a-page-step-does-not-reopen-the-editor.json"


func _steps(path: String) -> Array:
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    return parsed if parsed is Array else []


## The branch that reopens, read off the source because the alternative is a
## window in a headless run.
func test_the_editor_step_asks_whether_the_window_is_on_screen() -> void:
    var source := FileAccess.get_file_as_string("res://harness/captures/brush_editor_capture.gd")
    assert_true(
        source.contains('if window == null or not window.visible or bool(spec.get("open", false)):'),
        "capture_editor reopens a window that exists and is not visible"
    )


## The complaint is silent for the bare host and loud for a missed editor.
##
## Only the silent half can be proved without a window, and it is the half that
## would break every scenario the bare host is the point of, so it is the one
## worth a test: a suite run has no `SaBrushEditorWindow` in its tree.
func test_no_editor_in_the_tree_earns_no_complaint() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    assert_not_null(tree, "the suite runs under a scene tree")
    assert_eq(
        CurveOptionCapture.shut_editor_complaint(tree),
        "",
        "a curve option step with no brush editor anywhere is the bare host, not a missed editor"
    )


## The line a missed step earns, in the shape of a clear complaint.
##
## `sara_shot.py` reads a `SaCapture:` line carrying `failed` as a problem worth
## putting in front of a reader, which is what makes the throwaway readable at
## all. The rest is what the step owes a reader: name what went wrong and
## what to write instead.
func test_the_complaint_names_the_problem_and_the_spelling_that_works() -> void:
    var line: String = CurveOptionCapture.SHUT_EDITOR_COMPLAINT % "hidden"
    assert_true(line.begins_with("SaCapture: curve_option failed,"), "the line is one sara_shot.py surfaces")
    assert_true(line.contains("hidden"), "it says which state the editor was in")
    assert_true(line.contains("throwaway"), "it says what the step edited instead")
    assert_true(line.contains('{"brush_editor": {"open": true'), "and it spells the step that would have worked")


## The shared curve scenario is left as committed, and the reopen scenario is the
## pair that says why.
##
## The fix could be the page step reopening or the scenario being corrected.
## Correcting the scenario would have deleted the only committed
## specimen of the spelling that has to keep working, and
## `test_a_closed_brush_editor_and_how_a_step_reopens_it.gd` pins that spelling,
## so the fix is the step alone and that file is untouched.
func test_f89_still_reopens_with_a_page_step_alone() -> void:
    var f89 := _steps(F89_SCENARIO)
    assert_false(f89.is_empty(), "the shared curve scenario parses")
    var closes := 0
    var explicit_opens := 0
    for step: Variant in f89:
        var spec: Variant = (step as Dictionary).get("brush_editor")
        if spec == null:
            continue
        if bool((spec as Dictionary).get("close", false)):
            closes += 1
        elif bool((spec as Dictionary).get("open", false)):
            explicit_opens += 1
    assert_true(closes > 0, "it still closes the editor")
    assert_eq(explicit_opens, 0, "and still reopens with a page step alone, which is now the working spelling")


## This unit's own scenario carries all three readings the fix has to produce.
func test_the_scenario_reopens_and_then_misses_on_purpose() -> void:
    var steps := _steps(OWN_SCENARIO)
    assert_false(steps.is_empty(), "the scenario parses")
    var closes := 0
    var page_reopens := 0
    var explicit_opens := 0
    var curve_dumps := 0
    for step: Variant in steps:
        var dict := step as Dictionary
        if dict.has("curve_option"):
            curve_dumps += 1
        var spec: Variant = dict.get("brush_editor")
        if spec == null:
            continue
        var editor := spec as Dictionary
        if bool(editor.get("close", false)):
            closes += 1
        elif bool(editor.get("open", false)):
            explicit_opens += 1
        elif editor.has("page"):
            page_reopens += 1
    assert_eq(closes, 2, "it closes twice, once to reopen and once to be missed")
    assert_true(page_reopens >= 2, "and reaches the editor with a page step alone both times")
    assert_eq(explicit_opens, 0, "never with `open`, or it would prove the spelling that already worked")
    assert_true(curve_dumps >= 3, "with a curve option reading either side of each close")
