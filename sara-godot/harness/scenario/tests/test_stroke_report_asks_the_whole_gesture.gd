## The stroke report may not say "nothing covers" on the strength of one
## point, and a docker the gesture dragged has to be named.
##
## The defect was a scan done at the wrong moment. `_report_stroke` asked which
## window covered the press point *after* the release, and a press that lands on
## a docker's title bar drags that docker, so the window had already left. In
## `scenarios/stamp-engine-dynamics.json` the Brush Presets docker stood at (2, 340), the
## stroke from (200, 340) to (1160, 340) picked it up and carried it to
## (962, 340), and the run said "nothing covers (200, 340), so the brush tool
## drew nothing". Reading the dump the stroke had written suggested the docker sat at
## (962, 340) and a drag running into it voided the stroke, which was wrong.
##
## The walk itself needs a scene tree and real embedded windows, so the running
## app proves it in `scenarios/docker-under-a-drag-voids-the-stroke.json`.
## What is assertable without one is the reading of the walk: which entry counts
## as the press, and what the quiet line is allowed to claim.
extends "res://tests/test_framework.gd"

const ScenarioStroke = preload("res://harness/scenario/sa_scenario_stroke.gd")


## One entry the way `_covers_along` builds one.
func _cover(title: String, first: int, points: int, at: Vector2) -> Dictionary:
    return {"title": title, "first": first, "at": [at.x, at.y], "points": points, "was": [0.0, 0.0]}


## Frame 0 is the press point, and only frame 0 is.
func test_only_a_window_over_frame_zero_took_the_press() -> void:
    var press := _cover("Brush Presets", 0, 5, Vector2(200, 340))
    assert_eq(String(ScenarioStroke.press_cover([press])["title"]), "Brush Presets", "A window over frame 0 took the press")

    var midway := _cover("Brush Presets", 13, 4, Vector2(980, 340))
    assert_true(ScenarioStroke.press_cover([midway]).is_empty(), "and one the drag only reaches later did not")
    assert_true(ScenarioStroke.press_cover([]).is_empty(), "and a clear gesture has no press cover at all")

    assert_eq(
        String(ScenarioStroke.press_cover([midway, press])["title"]),
        "Brush Presets",
        "The press entry is found wherever in the list it sits, the walk having no order a reader can rely on"
    )


## The clause that replaced "nothing covers (x, y)". Its whole job is to say how
## much of the gesture was looked at, which the old line never did.
func test_the_quiet_clause_counts_the_points_it_checked() -> void:
    assert_eq(
        ScenarioStroke.cover_clause([], 16),
        "nothing covers any of the 17 points of the gesture",
        "A clear gesture says how many points were clear, not which one"
    )
    assert_eq(
        ScenarioStroke.cover_clause([], 1),
        "nothing covers any of the 2 points of the gesture",
        "and the shortest gesture is still two points, the press and the release"
    )
    assert_eq(
        ScenarioStroke.cover_clause([], 0),
        "nothing covers any of the 2 points of the gesture",
        "and a report with no step count is read as the shortest, never as one point"
    )


## A docker under the middle of a drag is named, with where along the drag it is.
func test_a_docker_the_drag_reaches_is_named_with_its_frame() -> void:
    assert_eq(
        ScenarioStroke.cover_clause([_cover("Brush Presets", 13, 4, Vector2(980, 340))], 16),
        "'Brush Presets' covers 4 of its 17 points, from frame 13 at (980, 340)",
        "The clause names the docker, how much of the gesture it holds and where the drag first meets it"
    )
    assert_eq(
        ScenarioStroke.cover_clause(
            [_cover("Info", 0, 17, Vector2(200, 340)), _cover("Tool Options", 9, 2, Vector2(740, 340))], 16
        ),
        (
            "'Info' covers 17 of its 17 points, from frame 0 at (200, 340), "
            + "'Tool Options' covers 2 of its 17 points, from frame 9 at (740, 340)"
        ),
        "and two windows over one gesture are both named rather than the first one winning"
    )
