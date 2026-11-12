## A closed brush editor and how a step reopens it.
##
## The `pending_` method here is a defect measured on the running app. A
## `pending_` method is not run: the framework calls what begins with `test_`,
## so the fixer renames one method and the suite starts asserting the thing that
## was wrong.
##
## The `test_` methods are the two readings the sweep can hold without a GPU, and
## both pass. Neither of them opens a window: adding one in a headless run hangs
## (a window in a headless run hangs), so the source and the committed
## scenario files are what is asked.
extends "res://tests/test_framework.gd"

const F89_SCENARIO := "res://scenarios/shared-curve-eats-the-sensor-curve.json"
const W8_SCENARIO := "res://scenarios/editor-reopen-loses-the-curve.json"


func _steps(path: String) -> Array:
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    return parsed if parsed is Array else []


## A `brush_editor` page step reopens an editor a `close` step hid.
##
## `{"close": true}` is `window.hide()`, so the window stays in the tree.
## `capture_editor` finds it with `live_window`, which asks nothing about
## visibility, so the branch that would show it again never runs and the page is
## switched on a window nobody can see. `CurveOptionCapture.live_control` does
## ask, so the `curve_option` step that follows finds nothing and edits a bare
## throwaway option in the host instead, silently.
##
## Renamed to `test_` by `a-page-step-does-not-reopen-the-editor`, which
## made it pass. The running-app half is
## `scenarios/editor-reopen-loses-the-curve.json`, whose second dump read the
## identity and whose third, one `"open": true` later, read the curve the painter
## drew. Both read the drawn curve now, which is the fix.
func test_a_page_step_reopens_an_editor_that_was_closed() -> void:
    var source := FileAccess.get_file_as_string("res://harness/captures/brush_editor_capture.gd")
    assert_true(
        source.contains('if window == null or not window.visible or bool(spec.get("open", false)):'),
        "capture_editor asks whether the window is visible, not only whether it exists"
    )


## The two lookups that disagree, which is the defect stated where
## a reader of either function will meet it.
##
## This passes today and is the assertion that would have stopped a proof
## being committed with the wrong spelling: `live_window` and `live_control` answer different questions
## about the same window, and only one of them asks about visibility.
func test_the_two_editor_lookups_disagree_about_what_being_there_means() -> void:
    # The window lookup is the door's and the control lookup the capture's.
    # One asks whether the window exists, the other whether a control is on
    # screen, and the capture has to ask the second itself.
    var door := FileAccess.get_file_as_string("res://ui/brush_editor/brush_editor_door.gd")
    var capture := FileAccess.get_file_as_string("res://harness/captures/brush_editor_capture.gd")
    assert_true(door.contains("static func live_window("), "the door looks its window up by name")
    # The body of `live_window` and not the paragraph over it, because the
    # paragraph over either lookup names the other's question by name. What is
    # asserted is what the function runs.
    var window_body := door.split("static func live_window(")[1].split("\n\n\n")[0]
    assert_false(window_body.contains("is_visible_in_tree"), "and asks nothing about whether it is on screen")
    assert_true(capture.contains("is_visible_in_tree()"), "while the control lookup requires exactly that")
    assert_true(
        capture.contains("SaCurveOptionHost.open(tree, curve_spec(tree, page), null, page)"),
        "and opens the bare host on a throwaway when it finds none, which is what a shut editor gives it"
    )


## The committed proof scenario reopens with a page step alone, and the editor
## reopen scenario holds the pair that shows why.
##
## Asserted against the scenario files rather than by running them, because the
## contract is a file a script can run and this is the claim about those files: one of them is wrong today and
## the other says what right looks
## like.
func test_the_two_scenarios_spell_the_reopen_the_two_ways() -> void:
    var f89 := _steps(F89_SCENARIO)
    var w8 := _steps(W8_SCENARIO)
    assert_false(f89.is_empty(), "the shared curve scenario parses")
    assert_false(w8.is_empty(), "and so does the reopen scenario")

    var f89_closes := 0
    var f89_reopens_explicitly := 0
    for step: Variant in f89:
        var spec: Variant = (step as Dictionary).get("brush_editor")
        if spec == null:
            continue
        if bool((spec as Dictionary).get("close", false)):
            f89_closes += 1
        elif bool((spec as Dictionary).get("open", false)):
            f89_reopens_explicitly += 1
    assert_true(f89_closes > 0, "the shared curve scenario closes the editor")
    assert_eq(f89_reopens_explicitly, 0, "and never reopens it with `open`, which is the defect")

    var w8_explicit := 0
    for step: Variant in w8:
        var spec: Variant = (step as Dictionary).get("brush_editor")
        if spec != null and bool((spec as Dictionary).get("open", false)):
            w8_explicit += 1
    assert_eq(w8_explicit, 1, "the reopen scenario reopens once the way that works, beside the way that does not")
