## A stroke whose press the canvas never heard says where the
## press stood, rather than "nothing covers any of the 3 points".
##
## A stroke along document y 1080 of a canvas 1080 rows high at
## Fit, which put the press at root y 1048 of a window 1048 high, and since
## the status line puts it on the line's top edge. A `Rect2` holds its origin
## and not its far edge, the engine's hit test asks one, and the canvas never
## heard the press, while the line blamed nothing and the reader went looking
## in the brush. The running app proves the loud line in a scenario, and this suite holds the clauses the step measures.
extends "res://tests/test_framework.gd"

const ScenarioStroke = preload("res://harness/scenario/sa_scenario_stroke.gd")

## The window the stroke met, 1920 by 1048.
const WINDOW := [0.0, 0.0, 1920.0, 1048.0]
## The canvas's view in it, between the top bar and the status line.
const VIEW := [0.0, 35.0, 1920.0, 989.0]


## The press on the window's far edge is past it, and half a row inside is not.
func test_a_press_on_the_windows_far_edge_is_outside_it() -> void:
    assert_eq(
        ScenarioStroke.off_window_clause(Vector2(903, 1048), WINDOW),
        (
            "the press at (903, 1048) is outside the window, which spans (0, 0) to (1920, 1048)"
            + " without its far edges, so no control took it"
        ),
        "The press sent is named with the window it missed"
    )
    assert_eq(ScenarioStroke.off_window_clause(Vector2(903, 1047.5), WINDOW), "", "and one half a row inside is the window's")
    assert_true(not ScenarioStroke.off_window_clause(Vector2(1920, 400), WINDOW).is_empty(), "The right edge is a far edge too")
    assert_eq(ScenarioStroke.off_window_clause(Vector2(0, 0), WINDOW), "", "and the origin is the window's own")
    assert_eq(ScenarioStroke.off_window_clause(Vector2(903, 1048), []), "", "A verdict with no window measured claims nothing")


## A press on a bar is inside the window and outside the canvas's view.
func test_a_press_on_a_bar_is_outside_the_view() -> void:
    assert_eq(
        ScenarioStroke.off_view_clause(Vector2(900, 20), VIEW),
        "the press at (900, 20) is outside the canvas's view, which spans (0, 35) to (1920, 1024)",
        "A press on the top bar names the view it missed"
    )
    assert_true(
        not ScenarioStroke.off_view_clause(Vector2(905, 1024), VIEW).is_empty(),
        "and so does one on the status line's top edge, the view's far edge"
    )
    assert_eq(ScenarioStroke.off_view_clause(Vector2(900, 35), VIEW), "", "The view's top row is its own")
    assert_eq(ScenarioStroke.off_view_clause(Vector2(900, 20), []), "", "and a window with no canvas claims nothing")


## What makes the line loud: a press past the window whatever the stroke was
## written in, and one off the view when the writer named a texel.
func test_a_texel_the_view_put_off_the_canvas_fails_loudly() -> void:
    var document := {"window": WINDOW, "view": VIEW, "document": [[900, 1080], [1020, 1080]]}
    var missed := ScenarioStroke.missed_press_clause(Vector2(905, 1024), document)
    assert_true(
        missed.begins_with("the press at (905, 1024) is outside the canvas's view"),
        "The stroke under the status line names the view it missed, and read '%s'" % missed
    )
    assert_true(missed.ends_with("so zoom out first"), "and tells the writer what to do")

    var window := {"window": WINDOW, "view": VIEW}
    assert_eq(ScenarioStroke.missed_press_clause(Vector2(900, 20), window), "", "A window-unit press on the bar stays quiet")
    assert_eq(
        ScenarioStroke.missed_press_clause(Vector2(903, 1048), window),
        ScenarioStroke.off_window_clause(Vector2(903, 1048), WINDOW),
        "and one past the window is loud without the hint, which is about a texel"
    )
    assert_eq(ScenarioStroke.missed_press_clause(Vector2(960, 500), document), "", "A texel inside the view misses nothing")
