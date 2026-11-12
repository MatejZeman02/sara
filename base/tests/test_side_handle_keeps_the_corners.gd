## A side handle respects the map already in the air: under a perspective quad
## it moves that edge's two corners, under a freehand warp that edge's three
## control points, and neither throws away what a hand has placed.
##
## The indices first, because "which points is this edge" is a lookup two files
## answer and a picture cannot tell a right answer from a nearly right one.
## Then the gestures through a bound machine, a corner press followed by a side
## press in each of the three modes, where a side drag must not revert the corner action and snap the
## picture back
## to a scale.
##
## The pictures are `scenarios/the-side-handle-keeps-the-corners.json`.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true
const Fixtures = preload("res://tests/fixtures.gd")
const StateTransformScript = preload("res://modules/sara-base-modules/base/transform/state_transform.gd")

## The selection every gesture below is made over, so a reader can work the
## handle positions out by hand: the corners are (400, 384) and (900, 784), the
## middle of the top edge is (650, 384) and of the right edge (900, 584).
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


## One press at *from*, one motion to *to*, one release, which is the whole of
## a gesture as far as the tool is concerned.
func _drag(parts: Array, from: Vector2, to: Vector2) -> void:
    var surface: SaSurface = parts[0]
    var tool: StateTransformScript = parts[2]
    surface.view.mouse_position = from
    tool.handle_input(_button(true))
    surface.view.mouse_position = to
    tool.handle_input(InputEventMouseMotion.new())
    tool.handle_input(_button(false))


## Whether *quad* still has its sides square and parallel, which every affine
## gesture over an unturned box leaves true and a placed corner does not.
static func _is_a_rectangle(quad: PackedVector2Array) -> bool:
    if quad.size() != 4:
        return false
    return (
        absf(quad[0].y - quad[1].y) < 1.0
        and absf(quad[3].y - quad[2].y) < 1.0
        and absf(quad[0].x - quad[3].x) < 1.0
        and absf(quad[1].x - quad[2].x) < 1.0
    )


# --- Which points an edge is ------------------------------------------------------


## The four edges name two corners each, in the quad's own clockwise order, and
## a corner handle names none: an edge gesture asked for a corner would be the
## perspective drag it already has.
func test_an_edge_names_its_two_corners_and_a_corner_names_none() -> void:
    assert_eq(SaTransformHandles.edge_corners(Vector2i(0, -1)), PackedInt32Array([0, 1]), "The top edge is the first two")
    assert_eq(SaTransformHandles.edge_corners(Vector2i(1, 0)), PackedInt32Array([1, 2]), "the right edge the second two")
    assert_eq(SaTransformHandles.edge_corners(Vector2i(0, 1)), PackedInt32Array([2, 3]), "the bottom edge the last two")
    assert_eq(SaTransformHandles.edge_corners(Vector2i(-1, 0)), PackedInt32Array([0, 3]), "and the left edge wraps")
    for corner: Vector2i in SaTransformHandles.QUAD_CORNERS:
        assert_true(SaTransformHandles.edge_corners(corner).is_empty(), "%s is a corner and names no edge" % corner)
    assert_true(SaTransformHandles.edge_corners(Vector2i.ZERO).is_empty(), "and the centre is not a handle at all")


## The same four edges name three control points each, which are the rows and
## columns `lines_of` draws.
func test_an_edge_names_three_control_points_of_the_mesh() -> void:
    assert_eq(SaTransformMesh.edge_points(Vector2i(0, -1)), PackedInt32Array([0, 1, 2]), "The top row")
    assert_eq(SaTransformMesh.edge_points(Vector2i(0, 1)), PackedInt32Array([6, 7, 8]), "the bottom row")
    assert_eq(SaTransformMesh.edge_points(Vector2i(-1, 0)), PackedInt32Array([0, 3, 6]), "the left column")
    assert_eq(SaTransformMesh.edge_points(Vector2i(1, 0)), PackedInt32Array([2, 5, 8]), "and the right column")
    for corner: Vector2i in SaTransformHandles.QUAD_CORNERS:
        assert_true(SaTransformMesh.edge_points(corner).is_empty(), "%s is a corner and names no edge" % corner)


# --- Perspective ------------------------------------------------------------------


## A sequence: a corner placed, then the middle of a side dragged.
## The corner keeps what it was given and the edge's two corners travel with the
## pointer, which a side handle must not undo.
func test_a_side_drag_in_perspective_keeps_the_placed_corner() -> void:
    var parts := _tool()
    var tool: StateTransformScript = parts[2]
    tool.transform_mode = StateTransformScript.Mode.PERSPECTIVE
    _drag(parts, Vector2(400, 384), Vector2(460, 420))
    var placed: PackedVector2Array = tool.pending_quad()
    assert_almost_eq((placed[0] - Vector2(460, 420)).length(), 0.0, 1.0, "The top left corner is where it was put")
    assert_false(_is_a_rectangle(placed), "and the quad is no longer a rectangle")

    # The middle of the top edge is the midpoint of the two corners it joins,
    # which the corner drag has moved.
    var handle: Vector2 = placed[0].lerp(placed[1], 0.5)
    _drag(parts, handle, handle + Vector2(0.0, 60.0))

    var after: PackedVector2Array = tool.pending_quad()
    assert_eq(after.size(), 4, "Still a quad")
    assert_almost_eq(
        (after[0] - (placed[0] + Vector2(0, 60))).length(), 0.0, 1.5, "The placed corner kept its place and moved with the edge"
    )
    assert_almost_eq((after[1] - (placed[1] + Vector2(0, 60))).length(), 0.0, 1.5, "the other corner of that edge came with it")
    assert_almost_eq((after[2] - placed[2]).length(), 0.0, 1.5, "the far side's corners stayed")
    assert_almost_eq((after[3] - placed[3]).length(), 0.0, 1.5, "both of them")
    assert_false(_is_a_rectangle(after), "and the map is still the homography rather than a scale")
    assert_false(tool.preview_shape().has("ants"), "which the overlay is told by being handed no affine")
    Fixtures.teardown(parts[0], parts[1])


## Moving the body of the box carries the placed corners rather than flattening
## them, which is the same reversion by the other road.
func test_moving_the_box_in_perspective_carries_the_placed_corner() -> void:
    var parts := _tool()
    var tool: StateTransformScript = parts[2]
    tool.transform_mode = StateTransformScript.Mode.PERSPECTIVE
    _drag(parts, Vector2(400, 384), Vector2(460, 420))
    var placed: PackedVector2Array = tool.pending_quad()

    _drag(parts, Vector2(650, 584), Vector2(700, 614))

    var after: PackedVector2Array = tool.pending_quad()
    for index in 4:
        var wanted: Vector2 = placed[index] + Vector2(50, 30)
        assert_almost_eq((after[index] - wanted).length(), 0.0, 1.5, "Corner %d came along, %s" % [index, after[index]])
    assert_false(_is_a_rectangle(after), "and the quad kept its shape")
    Fixtures.teardown(parts[0], parts[1])


# --- Freehand ---------------------------------------------------------------------


## The same in Freehand, by the longer route: the mid-edge
## control point and the edge handle sit on the same pixel until a corner point
## is dragged, and only then can the handle be grabbed on its own.
func test_a_side_drag_in_freehand_keeps_the_placed_control_point() -> void:
    var parts := _tool()
    var tool: StateTransformScript = parts[2]
    tool.transform_mode = StateTransformScript.Mode.FREEHAND
    _drag(parts, Vector2(400, 384), Vector2(400, 484))
    var placed: PackedVector2Array = tool.pending_mesh()
    assert_eq(placed.size(), 9, "A warp is in the air")
    assert_almost_eq((placed[0] - Vector2(400, 484)).length(), 0.0, 1.0, "with its top left point where it was put")

    # The top edge handle, which is now 50 pixels off the mid-top control point
    # and so can be grabbed without the mesh winning the press.
    var handle: Vector2 = Vector2(400, 484).lerp(Vector2(900, 384), 0.5)
    _drag(parts, handle, handle + Vector2(0.0, 60.0))

    var after: PackedVector2Array = tool.pending_mesh()
    assert_eq(after.size(), 9, "The warp is still in the air")
    for index: int in [0, 1, 2]:
        var wanted: Vector2 = placed[index] + Vector2(0, 60)
        assert_almost_eq((after[index] - wanted).length(), 0.0, 1.0, "Point %d moved with the edge, %s" % [index, after[index]])
    for index: int in [3, 4, 5, 6, 7, 8]:
        assert_almost_eq((after[index] - placed[index]).length(), 0.0, 1.0, "and point %d stayed" % index)
    Fixtures.teardown(parts[0], parts[1])


## A control point dragged and then the box turned from outside a corner,
## which is the carry the perspective test makes over four corners made over
## nine points. It was a drag inside the box, which under Freehand now takes
## nothing between the points.
func test_turning_the_box_in_freehand_carries_the_control_points() -> void:
    var parts := _tool()
    var tool: StateTransformScript = parts[2]
    tool.transform_mode = StateTransformScript.Mode.FREEHAND
    _drag(parts, Vector2(650, 584), Vector2(700, 620))
    var placed: PackedVector2Array = tool.pending_mesh()
    assert_almost_eq((placed[4] - Vector2(700, 620)).length(), 0.0, 1.0, "The centre point is where it was put")

    # Outside the top left corner, past a point's reach and inside the turn's,
    # and turned ten degrees about the box's centre.
    var centre := Vector2(BOX.get_center())
    var from := Vector2(386, 370)
    var turn := deg_to_rad(10.0)
    _drag(parts, from, centre + (from - centre).rotated(turn))

    var after: PackedVector2Array = tool.pending_mesh()
    assert_eq(after.size(), 9, "The warp survived the turn")
    for index in mini(after.size(), 9):
        var wanted: Vector2 = centre + (placed[index] - centre).rotated(turn)
        assert_almost_eq((after[index] - wanted).length(), 0.0, 1.0, "Point %d came along, %s" % [index, after[index]])
    Fixtures.teardown(parts[0], parts[1])


# --- Normal, which was already right ----------------------------------------------


## The mode that was right costs nothing: in Normal a corner drag still scales
## and a side drag after it still scales, both holding the far side still, and
## the box stays a box.
func test_normal_mode_still_scales_from_a_corner_and_from_a_side() -> void:
    var parts := _tool()
    var tool: StateTransformScript = parts[2]
    var before: PackedVector2Array = tool.pending_quad()
    _drag(parts, Vector2(400, 384), Vector2(460, 420))
    var pulled: PackedVector2Array = tool.pending_quad()
    assert_true(_is_a_rectangle(pulled), "A corner scale leaves a rectangle")
    assert_almost_eq((pulled[2] - before[2]).length(), 0.0, 1.0, "with the far corner held still")
    assert_true((pulled[1] - before[1]).length() > 1.0, "and the two beside it moved, which a placed corner does not")

    var handle: Vector2 = pulled[0].lerp(pulled[1], 0.5)
    _drag(parts, handle, handle + Vector2(0.0, 60.0))

    var after: PackedVector2Array = tool.pending_quad()
    assert_true(_is_a_rectangle(after), "A side scale leaves a rectangle too")
    assert_almost_eq(after[2].y, pulled[2].y, 1.0, "the far edge is held")
    assert_almost_eq(after[0].y, pulled[0].y + 60.0, 1.5, "and the grabbed edge followed the pointer")
    assert_true(tool.preview_shape().has("ants"), "which is an affine map, so the outline is drawn through it")
    Fixtures.teardown(parts[0], parts[1])
