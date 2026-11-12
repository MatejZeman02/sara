## A real drag of a picked set onto the lower half of Background lands the set
## under it as one step.
##
## The picked-set suite drives the drop through the list's own calls. The running app's
## half, a real click, a real Ctrl+click, a real press, four moves and a real
## release over the lower half of Background, then one Ctrl+Z, is the scenario
## read here. Its states showed C, Layer 1, Background, B, A after the drop with
## B and A still picked and one step more in the history, and the stack as before
## after the Ctrl+Z. This suite keeps the scenario's names, steps and aim in the
## gate, so a later edit that stops aiming at Background fails here.
extends "res://tests/test_framework.gd"

const SCENARIO := (
    "res://scenarios/a-real-drag-of-a-picked-set-onto-the-lower-half-of-background" + "-lands-the-set-under-it-as-one-step.json"
)

## The Layers docker's origin on screen, and the rows' tops and height inside
## it, as the first run's state `01-a-b-and-c-filled` reported them.
const DOCKER_TOP := 120.0
const ROW_H := 29.0
const ROW_B_TOP := 150.0
const ROW_A_TOP := 181.0
const ROW_BACKGROUND_TOP := 243.0

const NAMES := [
    "01-a-b-and-c-filled",
    "02-b-and-a-picked",
    "03-the-pointer-over-the-lower-half-of-background",
    "04-the-drop-lands-b-and-a-under-background",
    "05-one-ctrl-z-puts-the-stack-back",
]


func _steps() -> Array:
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SCENARIO))
    return parsed if parsed is Array else []


func _first(steps: Array, kind: String) -> Dictionary:
    for step: Variant in steps:
        if step is Dictionary and (step as Dictionary).has(kind):
            return step
    return {}


func _within(y: float, top: float, from: float, to: float) -> bool:
    var screen_top := DOCKER_TOP + top
    return y >= screen_top + ROW_H * from and y <= screen_top + ROW_H * to


func test_the_scenario_has_its_steps() -> void:
    assert_eq(_steps().size(), 41, "the scenario keeps its 41 steps")


func test_every_state_and_shot_is_named() -> void:
    var states: Array = []
    var shots: Array = []
    for step: Variant in _steps():
        if step is Dictionary and (step as Dictionary).has("state"):
            states.append(step["state"])
        if step is Dictionary and (step as Dictionary).has("shot"):
            shots.append(step["shot"])
    assert_eq(states, NAMES, "a state at every point the claim reads")
    assert_eq(shots, [NAMES[0], NAMES[1], NAMES[3], NAMES[4]], "a shot of each but the mid-drag one")


func test_b_and_a_are_picked_by_a_click_and_a_ctrl_click() -> void:
    var clicks: Array = []
    for step: Variant in _steps():
        if step is Dictionary and (step as Dictionary).has("click"):
            clicks.append(step["click"])
    assert_eq(clicks.size(), 2, "two clicks pick the set")
    assert_true(_within(float(clicks[0]["at"][1]), ROW_B_TOP, 0.0, 1.0), "the plain click lands on B")
    assert_false(clicks[0].get("ctrl", false), "the first click is plain")
    assert_true(_within(float(clicks[1]["at"][1]), ROW_A_TOP, 0.0, 1.0), "the Ctrl+click lands on A")
    assert_true(clicks[1].get("ctrl", false), "the second click holds Ctrl")


func test_the_press_is_on_a_picked_row_and_the_release_on_the_lower_half_of_background() -> void:
    var steps := _steps()
    var press: Dictionary = _first(steps, "press")["press"]
    var release: Dictionary = _first(steps, "release")["release"]
    assert_true(_within(float(press["at"][1]), ROW_A_TOP, 0.0, 1.0), "the press is on A, a picked row")
    assert_true(_within(float(release["at"][1]), ROW_BACKGROUND_TOP, 0.5, 1.0), "the release is on the lower half of Background")
    var moves := 0
    for step: Variant in steps:
        if step is Dictionary and (step as Dictionary).has("move"):
            moves += 1
    assert_true(moves >= 3, "the pointer moves in steps, as a hand drags")


func test_one_ctrl_z_follows_the_drop() -> void:
    var steps := _steps()
    var release_at := -1
    var undo_at := -1
    for i in steps.size():
        var step: Variant = steps[i]
        if step is Dictionary and (step as Dictionary).has("release"):
            release_at = i
        if step is Dictionary and (step as Dictionary).has("key"):
            assert_eq(undo_at, -1, "a single key, the one Ctrl+Z")
            undo_at = i
            assert_eq(step["key"], {"key": "z", "ctrl": true}, "the key is Ctrl+Z")
    assert_true(release_at > 0 and undo_at > release_at, "the Ctrl+Z comes after the drop")
