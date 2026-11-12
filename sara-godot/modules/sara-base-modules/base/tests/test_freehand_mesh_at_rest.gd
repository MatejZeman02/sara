## A Freehand box draws the nine points its press grabs before any of them
## has moved.
##
## The box at rest must not draw only the eight handles every mode draws with
## `preview_shape` handing the overlay the mesh once a warp is in the air, while
## `_press` already lays the same grid over the box and grabs a point of it, or
## a painter who picked Freehand would see eight of the nine points, no grid and
## no centre, and find the ninth by pressing where it ought to be.
##
## `scenarios/the-freehand-box-shows-no-mesh-until-a-point-has-moved.json`
## is the same claim on the running app.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true
const Fixtures = preload("res://tests/fixtures.gd")
const StateTransformScript = preload("res://modules/sara-base-modules/base/transform/state_transform.gd")

const BOX := Rect2i(400, 384, 500, 400)


func _button(pressed: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    return event


func _tool() -> Array:
    var surface := Fixtures.make_surface(Vector2i(1024, 1024))
    var machine := Fixtures.make_bound_machine(surface)
    var document := surface.get_document()
    document.active_layer.get_or_create_chunk(Vector2i(1, 1))
    document.selection.select_rect(BOX)
    machine.set_active_tool(&"transform")
    return [surface, machine, machine.active_tool]


func test_a_resting_freehand_box_hands_the_overlay_its_nine_points() -> void:
    var parts := _tool()
    var tool: StateTransformScript = parts[2]
    tool.transform_mode = StateTransformScript.Mode.FREEHAND
    assert_false(tool.is_moving(), "Nothing is lifted by picking the mode")
    var shape: Dictionary = tool.preview_shape()
    assert_eq(shape.get("rect", Rect2()), Rect2(BOX), "The overlay is still handed the resting rectangle")
    assert_false(bool(shape.get("handles", true)), "without the eight handles")
    var mesh: PackedVector2Array = shape.get("knots", PackedVector2Array())
    assert_eq(mesh.size(), SaTransformMesh.POINTS, "and with the nine points in their place")
    if mesh.size() == SaTransformMesh.POINTS:
        assert_eq(mesh[0], Vector2(BOX.position), "The first is the box's top left")
        assert_eq(mesh[4], Vector2(BOX.get_center()), "the fifth its centre, the point the eight handles never showed")
        assert_eq(mesh[8], Vector2(BOX.end), "and the last its bottom right")
        assert_eq(SaTransformMesh.lines_of(mesh).size(), 6, "which the overlay draws as the grid's six lines")
    Fixtures.teardown(parts[0], parts[1])


func test_the_other_three_modes_still_draw_eight_handles() -> void:
    var parts := _tool()
    var tool: StateTransformScript = parts[2]
    var names := {
        StateTransformScript.Mode.NORMAL: "Normal",
        StateTransformScript.Mode.PERSPECTIVE: "Perspective",
        StateTransformScript.Mode.SHEAR: "Shear",
    }
    for mode: int in names:
        tool.transform_mode = mode
        var shape: Dictionary = tool.preview_shape()
        assert_true(bool(shape.get("handles", false)), "%s at rest draws the eight handles" % names[mode])
        assert_false(shape.has("knots"), "and no mesh")
    Fixtures.teardown(parts[0], parts[1])


## The top middle point is an edge handle in every other mode, so a press there
## is the one that says whether what is drawn is what the press takes.
func test_the_points_drawn_are_the_points_a_press_grabs() -> void:
    var parts := _tool()
    var surface: SaSurface = parts[0]
    var tool: StateTransformScript = parts[2]
    tool.transform_mode = StateTransformScript.Mode.FREEHAND
    var drawn: PackedVector2Array = (tool.preview_shape() as Dictionary).get("knots", PackedVector2Array())
    assert_eq(drawn.size(), SaTransformMesh.POINTS, "The nine points are drawn before the press")
    if drawn.size() != SaTransformMesh.POINTS:
        Fixtures.teardown(parts[0], parts[1])
        return
    surface.view.mouse_position = drawn[1]
    tool.handle_input(_button(true))
    surface.view.mouse_position = drawn[1] + Vector2(0.0, -40.0)
    tool.handle_input(InputEventMouseMotion.new())
    var bent: PackedVector2Array = tool.pending_mesh()
    assert_eq(bent.size(), SaTransformMesh.POINTS, "The press on the drawn point started a warp")
    if bent.size() == SaTransformMesh.POINTS:
        assert_almost_eq((bent[1] - (drawn[1] + Vector2(0.0, -40.0))).length(), 0.0, 1.0, "which moved that point")
        assert_almost_eq((bent[0] - drawn[0]).length(), 0.0, 1.0, "and left the corner beside it")
        assert_almost_eq((bent[2] - drawn[2]).length(), 0.0, 1.0, "and the other corner, so it was no edge scale")
    Fixtures.teardown(parts[0], parts[1])


## A box moved under Normal and then put under Freehand, since a press between
## the points takes nothing there, is grabbed by the same grid laid over where
## it now is.
func test_a_moved_box_in_freehand_draws_the_grid_over_where_it_landed() -> void:
    var parts := _tool()
    var surface: SaSurface = parts[0]
    var tool: StateTransformScript = parts[2]
    surface.view.mouse_position = Vector2(500, 464)
    tool.handle_input(_button(true))
    surface.view.mouse_position = Vector2(530, 484)
    tool.handle_input(InputEventMouseMotion.new())
    tool.handle_input(_button(false))
    tool.transform_mode = StateTransformScript.Mode.FREEHAND
    assert_true(tool.is_moving(), "Normal moved the box, and Freehand kept the move")
    assert_eq(tool.pending_mesh().size(), 0, "and warped nothing")
    var shape: Dictionary = tool.preview_shape()
    var mesh: PackedVector2Array = shape.get("knots", PackedVector2Array())
    assert_eq(mesh, SaTransformMesh.grid_over(tool.pending_quad()), "The grid is laid over the moved box")
    assert_false(bool(shape.get("handles", true)), "in place of the eight handles")
    assert_true(shape.has("ants"), "and the outline still follows the move")
    tool.transform_mode = StateTransformScript.Mode.NORMAL
    shape = tool.preview_shape()
    assert_true(bool(shape.get("handles", false)) and not shape.has("knots"), "Normal on the same move is eight handles again")
    Fixtures.teardown(parts[0], parts[1])


func test_the_dump_carries_the_grid_the_box_rests_under() -> void:
    var parts := _tool()
    var tool: StateTransformScript = parts[2]
    var report: Dictionary = tool.capture_report(&"transform", true)
    assert_eq((report["transform"]["mesh"] as Array).size(), 0, "Normal at rest dumps no mesh")
    tool.transform_mode = StateTransformScript.Mode.FREEHAND
    report = tool.capture_report(&"transform", true)
    assert_eq((report["transform"]["mesh"] as Array).size(), SaTransformMesh.POINTS, "Freehand at rest dumps the nine")
    assert_false(bool(report["transform"]["moving"]), "with nothing in the air")
    Fixtures.teardown(parts[0], parts[1])
