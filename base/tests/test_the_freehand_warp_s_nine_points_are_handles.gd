## The Freehand warp's nine points are handles a painter can see and grab.
##
## A painter, 2026-10-09, of the strip's fourth cell: "the fourth one does
## nothing". The warp worked where a press landed on one of its nine points,
## and a press anywhere else inside the box moved the whole picture, so a point
## missed by a few pixels slid the picture away and read as the mode doing
## nothing of its own. A press between the points now takes nothing, a press on
## each point moves that point alone, and the points are handed to the overlay
## at the side every mode's handles are drawn at, one size on screen.
##
## The picture is the scenario named after the unit,
## `the-freehand-warp-s-nine-points-are-handles-a-painter-can-see-and-grab`,
## whose shots of a photograph under Normal and under Freehand show the eight
## handles and the nine points at one size.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true
const Fixtures = preload("res://tests/fixtures.gd")
const StateTransformScript = preload("res://modules/sara-base-modules/base/transform/state_transform.gd")

## The selection the box stands on, so a drag lifts it. Its nine points are
## (400, 384), (650, 384) and (900, 384) across the top, the same three at 584
## and at 784.
const BOX := Rect2i(400, 384, 500, 400)

## How far every drag goes, in document pixels, at the surface's zoom of one.
const BY := Vector2(30.0, -20.0)

## Presses inside the box and away from every point: the middles of the four
## cells, a point between two of the nine on a grid line, and one 14 pixels off
## the centre point, past the 10 a press reaches.
const BETWEEN: Array[Vector2] = [
    Vector2(525, 484),
    Vector2(775, 484),
    Vector2(525, 684),
    Vector2(775, 684),
    Vector2(525, 584),
    Vector2(664, 584),
]


static func _button(pressed: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    return event


## A Transform under Freehand over the box on a surface of *size*, the box a
## selection, or with *whole* the paint of a layer filled edge to edge and
## nothing selected, which is the photograph the note found the move on.
func _tool(size: Vector2i = Vector2i(1024, 1024), whole: bool = false) -> Array:
    var surface := Fixtures.make_surface(size)
    var machine := Fixtures.make_bound_machine(surface)
    var document := surface.get_document()
    if whole:
        document.active_layer.fill(Color(0.8, 0.4, 0.2, 1.0))
    else:
        document.active_layer.get_or_create_chunk(Vector2i(1, 1))
        document.selection.select_rect(BOX)
    machine.set_active_tool(&"transform")
    var tool: StateTransformScript = machine.active_tool
    tool.transform_mode = StateTransformScript.Mode.FREEHAND
    return [surface, machine, tool]


## One press at *from*, two motions to *from* + *by*, and the release.
static func _drag(surface: SaSurface, tool: StateTransformScript, from: Vector2, by: Vector2) -> void:
    surface.view.mouse_position = from
    tool.handle_input(_button(true))
    surface.view.mouse_position = from + by * 0.5
    tool.handle_input(InputEventMouseMotion.new())
    surface.view.mouse_position = from + by
    tool.handle_input(InputEventMouseMotion.new())
    tool.handle_input(_button(false))


## The nine points the overlay is handed, which are the ones a press grabs.
static func _drawn(tool: StateTransformScript) -> PackedVector2Array:
    return (tool.preview_shape() as Dictionary).get("knots", PackedVector2Array())


func test_a_press_between_the_points_moves_nothing_and_lifts_nothing() -> void:
    var parts := _tool()
    var surface: SaSurface = parts[0]
    var tool: StateTransformScript = parts[2]
    var document := surface.get_document()
    var steps := document.history.step_count()
    var quad := tool.pending_quad()
    for at: Vector2 in BETWEEN:
        _drag(surface, tool, at, BY * 2.0)
        assert_false(tool.is_moving(), "A press at %s lifted nothing" % at)
        assert_eq(tool.pending_quad(), quad, "and moved no corner of the box")
        assert_eq(tool.move_offset(), Vector2i.ZERO, "and slid nothing")
        assert_eq(tool.pending_mesh().size(), 0, "and bent nothing")
    assert_eq(document.history.step_count(), steps, "No press between the points wrote a step")
    assert_false(tool.commit_move(), "and Enter has nothing to commit")
    Fixtures.teardown(parts[0], parts[1])


## The note's own case: a layer the size of the canvas with nothing selected,
## whose nine points stand 960 pixels apart, and a press off them that moved the
## whole picture 140 by 105 pixels.
func test_a_press_off_the_points_of_a_whole_layer_moves_nothing() -> void:
    var parts := _tool(Vector2i(1920, 1080), true)
    var surface: SaSurface = parts[0]
    var tool: StateTransformScript = parts[2]
    var quad := tool.pending_quad()
    assert_eq(quad, SaHomography.corners_of(Rect2i(0, 0, 1920, 1080)), "The box is the whole layer")
    _drag(surface, tool, Vector2(1300, 700), Vector2(140, 105))
    assert_false(tool.is_moving(), "A press off the points lifted nothing")
    assert_eq(tool.pending_quad(), quad, "and the picture stayed where it was")
    assert_null(SaLiveTransform.of(surface.get_document().active_layer), "and the layer took no transform")
    Fixtures.teardown(parts[0], parts[1])


## Each of the nine pressed and dragged in turn, from where the overlay drew it,
## moves that one point by the drag and leaves the other eight where they were.
func test_a_press_on_each_point_moves_that_point_alone() -> void:
    var parts := _tool()
    var surface: SaSurface = parts[0]
    var tool: StateTransformScript = parts[2]
    for index in SaTransformMesh.POINTS:
        var drawn := _drawn(tool)
        assert_eq(drawn.size(), SaTransformMesh.POINTS, "The nine are drawn before point %d is pressed" % index)
        if drawn.size() != SaTransformMesh.POINTS:
            break
        _drag(surface, tool, drawn[index], BY)
        var bent := tool.pending_mesh()
        assert_eq(bent.size(), SaTransformMesh.POINTS, "A warp is in the air after point %d" % index)
        if bent.size() != SaTransformMesh.POINTS:
            break
        assert_almost_eq((bent[index] - (drawn[index] + BY)).length(), 0.0, 0.01, "Point %d went where it was dragged" % index)
        for other in SaTransformMesh.POINTS:
            if other != index:
                assert_almost_eq((bent[other] - drawn[other]).length(), 0.0, 0.01, "and point %d stayed" % other)
    Fixtures.teardown(parts[0], parts[1])


## A press a few pixels off a point still takes it, which is the reach a hand
## needs, and one past the reach takes nothing.
func test_a_point_is_taken_within_its_reach_and_not_past_it() -> void:
    var parts := _tool()
    var surface: SaSurface = parts[0]
    var tool: StateTransformScript = parts[2]
    var centre := Vector2(BOX.get_center())
    _drag(surface, tool, centre + Vector2(StateTransformScript.HANDLE_REACH + 4.0, 0.0), BY)
    assert_false(tool.is_moving(), "Past the reach the press took nothing")
    _drag(surface, tool, centre + Vector2(6.0, -4.0), BY)
    var bent := tool.pending_mesh()
    assert_eq(bent.size(), SaTransformMesh.POINTS, "Within it the press took the centre point")
    if bent.size() == SaTransformMesh.POINTS:
        assert_almost_eq((bent[4] - (centre + Vector2(6.0, -4.0) + BY)).length(), 0.0, 0.01, "and moved it under the pointer")
    Fixtures.teardown(parts[0], parts[1])


## Once a point is bent a press between the points still takes nothing: the
## warp keeps its nine where the hand left them and the history does not move.
func test_a_press_between_the_points_of_a_bent_warp_leaves_it() -> void:
    var parts := _tool()
    var surface: SaSurface = parts[0]
    var tool: StateTransformScript = parts[2]
    var document := surface.get_document()
    _drag(surface, tool, Vector2(BOX.get_center()), Vector2(50, 36))
    var bent := tool.pending_mesh()
    assert_eq(bent.size(), SaTransformMesh.POINTS, "The centre point bent the picture")
    var steps := document.history.step_count()
    for at: Vector2 in [Vector2(470, 450), Vector2(840, 720), Vector2(470, 720)]:
        _drag(surface, tool, at, BY * 2.0)
        assert_eq(tool.pending_mesh(), bent, "A press at %s left the nine where they were" % at)
    assert_eq(document.history.step_count(), steps, "and wrote nothing")
    assert_true(tool.commit_move(), "Enter still commits the bend")
    Fixtures.teardown(parts[0], parts[1])


## A press just outside a corner still turns the box under Freehand, as in
## every mode, so the one gesture taken away is the move.
func test_the_turn_outside_a_corner_is_kept() -> void:
    var parts := _tool()
    var surface: SaSurface = parts[0]
    var tool: StateTransformScript = parts[2]
    _drag(surface, tool, Vector2(BOX.end) + Vector2(14, 14), Vector2(-40, 30))
    assert_true(tool.is_moving(), "The press outside the corner lifted the box")
    assert_true(absf(tool.move_angle()) > 0.05, "and turned it, %.3f radians" % tool.move_angle())
    Fixtures.teardown(parts[0], parts[1])


## The nine points and every mode's eight handles are handed over at one side,
## the tool's `HANDLE_SIDE` in screen pixels, at rest and in the air, so the
## overlay draws a point exactly as it draws a handle and at every zoom.
func test_the_points_and_the_handles_are_handed_over_at_one_side() -> void:
    var parts := _tool()
    var surface: SaSurface = parts[0]
    var tool: StateTransformScript = parts[2]
    for mode: int in StateTransformScript.Mode.values():
        tool.transform_mode = mode
        var resting: Dictionary = tool.preview_shape()
        assert_eq(
            float(resting.get("handle_side", 0.0)), StateTransformScript.HANDLE_SIDE, "Mode %d at rest names the side" % mode
        )
        var drawn: bool = bool(resting.get("handles", false)) or resting.has("knots")
        assert_true(drawn, "and draws its handles or its points at it")
    tool.transform_mode = StateTransformScript.Mode.FREEHAND
    assert_false(bool(tool.preview_shape().get("handles", true)), "Freehand draws the nine in place of the eight")
    _drag(surface, tool, Vector2(BOX.position), BY)
    var shape: Dictionary = tool.preview_shape()
    assert_eq(float(shape.get("handle_side", 0.0)), StateTransformScript.HANDLE_SIDE, "and a bent warp names the same side")
    assert_eq((shape.get("knots", PackedVector2Array()) as PackedVector2Array).size(), 9, "for its nine points")
    assert_true(
        StateTransformScript.HANDLE_SIDE * 0.5 < StateTransformScript.HANDLE_REACH, "A drawn square lies inside the reach"
    )
    assert_true(
        StateTransformScript.HANDLE_SIDE * 0.5 < SaTransformModeStrip.MODE_LIFT, "and the strip floats clear of the top handle"
    )
    Fixtures.teardown(parts[0], parts[1])
