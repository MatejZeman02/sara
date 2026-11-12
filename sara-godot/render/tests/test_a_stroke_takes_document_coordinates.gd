## A stroke written in document pixels lands on the same texels whatever the
## view.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A stroke in window space makes a client read the zoom off a `fit` and the
## frame off a screenshot and work out every point by hand, which goes wrong
## when the layout moves. A stroke
## that says `"space": "document"` is carried through the canvas's own
## transform when the step runs. These read the moves the step splices into
## the run, under the fitted view, two zooms, a pan and a turned and mirrored
## one, and carry each back through the transform the tool reads its pointer
## through. The running app's half, the same painted texels read with `texel`
## after each view, is
## `scenarios/a-stroke-takes-document-coordinates.json`.
extends "res://tests/test_framework.gd"

const CaptureRun := preload("res://harness/sa_capture_run.gd")
const ScenarioStroke := preload("res://harness/scenario/sa_scenario_stroke.gd")
const Fixtures = preload("res://tests/fixtures.gd")

## A document point is exact to this after a trip out to the root and back.
const CLOSE: float = 1e-3

## The stroke every view is asked to paint, in document pixels.
const FROM := Vector2(800, 540)
const TO := Vector2(1100, 540)

var _host: Node = null
var _canvas: SaCanvas = null
var _run: CaptureRun = null
var _stroke: ScenarioStroke = null

## The suite's canvas, held as the document in front, which is where a
## harness step and a door line look.
var _front: Fixtures.FrontDocuments = null


## Parented to an autoload, because the runner calls this from its own `_ready`
## and a parent mid-`_ready` rejects `add_child`.
func before_each() -> void:
    _host = Node.new()
    _host.name = "Q2StrokeTestHost"
    EventBus.add_child(_host)
    _canvas = SaCanvas.new()
    _canvas.canvas_size = Vector2i(1920, 1080)
    _host.add_child(_canvas)
    _canvas.size = Vector2(1920, 1080)
    _run = CaptureRun.new()
    _stroke = ScenarioStroke.new(_run)
    _front = Fixtures.FrontDocuments.over(_canvas)


func after_each() -> void:
    if _front != null:
        _front.put_back()
        _front = null
    _stroke = null
    _run = null
    if _host != null:
        _host.free()
        _host = null
        _canvas = null


## The views the scenario paints under, each as the canvas's position, scale
## and rotation, with a mirrored one the scenario cannot reach by a gesture.
func _views() -> Dictionary:
    return {
        "fitted": [Vector2(0, 33.75), Vector2(0.9375, 0.9375), 0.0],
        "zoomed in": [Vector2(-960, -540), Vector2(2, 2), 0.0],
        "zoomed out": [Vector2(480, 270), Vector2(0.5, 0.5), 0.0],
        "panned": [Vector2(120, 81), Vector2.ONE, 0.0],
        "turned and mirrored": [Vector2(900, -200), Vector2(-1.25, 1.25), 0.83],
    }


## The `move` steps the last `stroke` spliced into the run, as points.
func _moves() -> PackedVector2Array:
    var out := PackedVector2Array()
    for step: Dictionary in _run.steps:
        if not step.has("move"):
            continue
        var at := (step["move"] as Dictionary)["at"] as Array
        out.append(Vector2(float(at[0]), float(at[1])))
    return out


## The whole line under every view comes back to the line that was written,
## through the inverse the tool reads its pointer through
## (`SaCanvasView.get_document_mouse_position`, the canvas's local mouse).
func test_a_document_stroke_lands_on_the_same_pixels_under_every_view() -> void:
    assert_eq(SaCanvas.in_window(_host.get_window()), _canvas, "the step finds this suite's canvas")
    var views := _views()
    for view_name: String in views:
        var view: Array = views[view_name]
        _canvas.position = view[0]
        _canvas.scale = view[1]
        _canvas.rotation = view[2]
        _run.steps = []
        _run.step_index = 0
        _stroke.stroke({"space": "document", "from": [FROM.x, FROM.y], "to": [TO.x, TO.y], "steps": 10})
        var moves := _moves()
        assert_eq(moves.size(), 11, "%s: one move per waypoint" % view_name)
        var back := _canvas.get_global_transform_with_canvas().affine_inverse()
        var worst := 0.0
        for i in moves.size():
            var wanted := FROM.lerp(TO, float(i) / 10.0)
            worst = maxf(worst, (back * moves[i]).distance_to(wanted))
        assert_true(worst < CLOSE, "%s: every move lands on its document pixel, %s off at worst" % [view_name, worst])


## The moves differ from view to view, which is the point: a stroke that
## ignored the view would pass the test above only under the identity.
func test_the_root_points_follow_the_view() -> void:
    var firsts: Array[Vector2] = []
    var views := _views()
    for view_name: String in views:
        var view: Array = views[view_name]
        _canvas.position = view[0]
        _canvas.scale = view[1]
        _canvas.rotation = view[2]
        _run.steps = []
        _run.step_index = 0
        _stroke.stroke({"space": "document", "from": [FROM.x, FROM.y], "to": [TO.x, TO.y], "steps": 4})
        firsts.append(_moves()[0])
    for i in firsts.size():
        for k in range(i + 1, firsts.size()):
            assert_false(firsts[i].is_equal_approx(firsts[k]), "views %d and %d press at different root points" % [i, k])


## A point off the visible canvas is still sent, as a pen off the edge would be.
func test_a_point_off_the_canvas_is_still_sent() -> void:
    _canvas.position = Vector2(-960, -540)
    _canvas.scale = Vector2(2, 2)
    _stroke.stroke({"space": "document", "points": [{"at": [100, 100]}, {"at": [900, 500]}]})
    var moves := _moves()
    assert_eq(moves.size(), 2, "both waypoints are moves")
    assert_true(moves[0].is_equal_approx(Vector2(-760, -340)), "the first is off the window at %s" % moves[0])


## Window space stays the default, so every scenario in the tree replays as it
## did: the moves are the points as written, whatever the view.
func test_a_stroke_that_names_no_space_is_in_root_units() -> void:
    _canvas.position = Vector2(300, 40)
    _canvas.scale = Vector2(2, 2)
    _canvas.rotation = 0.4
    _stroke.stroke({"from": [100, 200], "to": [500, 200], "steps": 4})
    var moves := _moves()
    assert_eq(moves.size(), 5, "one move per waypoint")
    for i in moves.size():
        var wanted := Vector2(100, 200).lerp(Vector2(500, 200), float(i) / 4.0)
        assert_true(moves[i].is_equal_approx(wanted), "move %d is at %s as written" % [i, moves[i]])
    _run.steps = []
    _stroke.stroke({"space": "window", "from": [100, 200], "to": [500, 200], "steps": 4})
    assert_true(_moves()[4].is_equal_approx(Vector2(500, 200)), "and 'window' names the same frame")


## A space the step does not know splices nothing rather than guessing.
func test_an_unknown_space_paints_nothing() -> void:
    _stroke.stroke({"space": "screen", "from": [100, 200], "to": [500, 200]})
    assert_eq(_run.steps.size(), 0, "no step was spliced")


## The verdict line opens with the document points, and a window stroke's line
## is the one it always was.
func test_the_verdict_names_both_frames() -> void:
    assert_eq(
        ScenarioStroke.document_clause({"document": [[800, 540], [1100, 540]]}),
        "document (800, 540) -> (1100, 540), root ",
        "a document stroke says where it aimed"
    )
    assert_eq(ScenarioStroke.document_clause({}), "", "a window stroke says nothing new")
