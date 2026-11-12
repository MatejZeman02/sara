## A stroke that leaves where it can paint and comes back walks the path the pen
## took.
##
## `StateBrush._dispatch_brush` returned as soon as the paint context came back
## empty and never told `SaStrokeDistance` where that dab fell. The walk's total
## distance, its last angle and its spacing stayed at the last dab that painted,
## the distance and fade sensors counted the chord back rather than the path,
## and the first dab back was spaced by the stale step. The fix registers such a
## dab with painted false, as the dab too small to paint already was.
##
## It reads as a dab off the canvas, but that was not
## the case that reached the return: `SaPaintContext` did not clip to the
## canvas, so a dab past the edge had targets like any other. What came back
## empty was a dab whose every chunk the selection leaves out, or one with no
## layer to paint. The context is clipped to the chunks the canvas
## reaches, so a dab wholly past the edge comes back empty too. The first
## method is the selection's case, and the second is the canvas edge's.
extends "res://tests/test_framework.gd"

## The stroke dispatches real dabs on the way out and back.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

const ROW := 128.0
const START_X := 100.0
## Far enough past the first chunk that no dab near its edge reaches back.
const TURN_X := 900.0
const STEP := 20.0


func _button(brush: Object, pressed: bool) -> void:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    brush.handle_input(event)


func _move(surface: Object, brush: Object, x: float) -> void:
    surface.view.mouse_position = Vector2(x, ROW)
    var event := InputEventMouseMotion.new()
    event.pressure = 1.0
    brush.handle_input(event)


## Out along one row to `TURN_X` and back to one report short of the start,
## so the chord from the last dab that painted to the first one back is short
## and the path is long. The walk trails the pen by one report, which is the one
## stretch it has not been told of before the release, and the answer is the
## walk's distance, the path it was told of, and that path's chord, read with
## the pen still down because the release resets the walk.
func _stroke_out_and_back(canvas: Vector2i, selection: Rect2i) -> Dictionary:
    var surface := Fixtures.make_surface(canvas)
    var machine := Fixtures.make_bound_machine(surface)
    if selection.has_area():
        surface.easel.document.selection.select_rect(selection)
    machine.set_active_tool(&"brush")
    var brush: Object = machine.active_tool
    brush.is_tablet = false
    brush.settings.stabilizer_amount = 0.0
    brush.settings.radius = 4.0 / canvas.y

    surface.view.mouse_position = Vector2(START_X, ROW)
    _button(brush, true)
    var reports: Array[float] = []
    var x := START_X
    while x < TURN_X:
        x += STEP
        reports.append(x)
    while x > START_X + STEP:
        x -= STEP
        reports.append(x)
    for report in reports:
        _move(surface, brush, report)

    var walk: SaStrokeDistance = brush.stroke_distance
    var told := 0.0
    var previous := START_X
    for i in reports.size() - 1:
        told += absf(reports[i] - previous)
        previous = reports[i]
    var answer := {
        "walked": walk.total_distance,
        "told": told,
        "chord": absf(previous - START_X),
        "slack": walk.spacing.distance.x + STEP,
        "painted": walk.dab_sequence,
    }
    _button(brush, false)
    Fixtures.teardown(surface, machine)
    return answer


func _assert_the_path(answer: Dictionary, reach: float) -> void:
    assert_true(
        absf(answer.walked - answer.told) <= answer.slack,
        (
            "The walk measured %.1f pixels of a %.1f pixel path, not the %.1f pixel chord"
            % [answer.walked, answer.told, answer.chord]
        )
    )
    assert_true(answer.walked > answer.chord + 2.0 * (TURN_X - reach), "and far more than any chord from where paint could land")


## The regression. The selection holds the first chunk only, so every dab past
## it has an empty paint context, and before the fix the walk measured about
## twice the stretch inside the selection rather than the whole path.
func test_a_stroke_out_of_the_selection_and_back_walks_the_path() -> void:
    var answer := _stroke_out_and_back(Vector2i(1024, 256), Rect2i(0, 0, 256, 256))
    _assert_the_path(answer, 256.0)
    assert_true(answer.painted > 0, "The dabs inside the selection still painted, %d of them" % answer.painted)


## The canvas edge's case: past the canvas's right edge and back. The paint
## context clips to the canvas, so the dabs past the first
## chunk come back empty and this holds that they still count.
func test_a_stroke_off_the_canvas_and_back_walks_the_path() -> void:
    _assert_the_path(_stroke_out_and_back(Vector2i(256, 256), Rect2i()), 256.0)
