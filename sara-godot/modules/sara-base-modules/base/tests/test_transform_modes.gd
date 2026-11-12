## The transform's three modes, and the homography under the perspective
## one.
##
## The arithmetic first, because a homography is eight numbers solved from eight
## equations and a picture cannot tell a right one from a nearly right one. Then
## the gestures through a bound machine, because what the note asks for is that
## the mode decide what a handle drag means.
##
## The pictures are taken by `scenarios/transform-modes.json`, one shot per mode.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true
const Fixtures = preload("res://tests/fixtures.gd")
const StateTransformScript = preload("res://modules/sara-base-modules/base/transform/state_transform.gd")

const BOX := Rect2i(100, 200, 400, 300)


func _button(pressed: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    return event


static func _quad(rect: Rect2i) -> PackedVector2Array:
    return SaHomography.corners_of(rect)


# --- The homography, as arithmetic ---------------------------------------------


## The identity case, which is the one a reader checks first: a box mapped onto
## its own corners is the map that moves nothing.
func test_a_box_onto_itself_is_the_identity() -> void:
    var h := SaHomography.corners_to_quad(BOX, _quad(BOX))
    assert_eq(h.size(), 9, "Eight unknowns and a fixed ninth")
    for at: Vector2 in [Vector2(100, 200), Vector2(500, 500), Vector2(300, 350)]:
        var out := SaHomography.through(h, at)
        assert_almost_eq((out - at).length(), 0.0, 1e-3, "%s is where it was, %s" % [at, out])


## An affine quad has to come out affine, because every gesture but perspective
## still goes through `preview_matrix` and the two have to agree about the same
## picture. A translated and scaled box is the case.
func test_an_affine_quad_gives_an_affine_map() -> void:
    var moved := Rect2i(BOX.position + Vector2i(60, -20), BOX.size * 2)
    var h := SaHomography.corners_to_quad(BOX, _quad(moved))
    assert_almost_eq(h[6], 0.0, 1e-6, "The bottom row's first coefficient is nought")
    assert_almost_eq(h[7], 0.0, 1e-6, "and so is its second")
    var centre := Vector2(BOX.get_center())
    var wanted := Vector2(moved.position) + (centre - Vector2(BOX.position)) * 2.0
    assert_almost_eq(
        (SaHomography.through(h, centre) - wanted).length(), 0.0, 1e-2, "and the centre goes where the affine would put it"
    )


## The four corners land exactly on the four asked for, which is the property
## the whole solve exists for and the one a painter sees.
func test_the_four_corners_land_where_they_were_put() -> void:
    var wanted := PackedVector2Array([Vector2(140, 210), Vector2(520, 260), Vector2(470, 470), Vector2(160, 520)])
    var h := SaHomography.corners_to_quad(BOX, wanted)
    assert_eq(h.size(), 9, "The quad is not degenerate")
    var source := _quad(BOX)
    for i in 4:
        var out := SaHomography.through(h, source[i])
        assert_almost_eq((out - wanted[i]).length(), 0.0, 1e-2, "Corner %d lands on %s, got %s" % [i, wanted[i], out])


## A quad the four points cannot describe is refused rather than answered with a
## matrix nothing can invert, which is what keeps a drag holding its last good
## map instead of showing a picture folded through a singularity.
func test_a_degenerate_quad_is_refused() -> void:
    var flat := PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(20, 0), Vector2(30, 0)])
    assert_true(SaHomography.corners_to_quad(BOX, flat).is_empty(), "Four points in a line have no homography")
    var same := PackedVector2Array([Vector2(5, 5), Vector2(5, 5), Vector2(5, 5), Vector2(5, 5)])
    assert_true(SaHomography.corners_to_quad(BOX, same).is_empty(), "and neither has one point four times")


## The inverse undoes it, which is what the kernel is handed and what decides
## whether a texel reads the right source.
func test_the_inverse_takes_a_mapped_point_back() -> void:
    var wanted := PackedVector2Array([Vector2(140, 210), Vector2(520, 260), Vector2(470, 470), Vector2(160, 520)])
    var h := SaHomography.corners_to_quad(BOX, wanted)
    var back := SaHomography.inverse_of(h)
    for at: Vector2 in [Vector2(120, 220), Vector2(400, 450), Vector2(300, 350)]:
        var there := SaHomography.through(h, at)
        var home := SaHomography.through(back, there)
        assert_almost_eq((home - at).length(), 0.0, 1e-2, "%s out and back is %s" % [at, home])


## The affine and the perspective cases answer the same four pieces for the same
## map, which is what lets one kernel writer serve Image > Scale, the mask carry
## and the transform preview alike.
func test_the_kernel_rows_agree_with_the_affine_inverse() -> void:
    var affine := Transform2D(0.4, Vector2(1.5, 0.8), 0.0, Vector2(40.0, -12.0))
    var lift := Vector2(BOX.position)
    var plain := SaHomography.kernel_rows(PackedFloat32Array(), affine, lift)
    assert_eq(plain[3] as Vector3, Vector3(0.0, 0.0, 1.0), "An affine map divides by one")

    var quad := PackedVector2Array()
    for corner: Vector2 in SaHomography.corners_of(BOX):
        quad.append(affine * corner)
    var through := SaHomography.kernel_rows(SaHomography.corners_to_quad(BOX, quad), affine, lift)
    # Read a document position back to a position in the lifted picture the way
    # the kernel does, and the two roads have to arrive together.
    for at: Vector2 in [Vector2(160.0, 240.0), Vector2(-30.0, 500.0)]:
        var w: float = (through[3] as Vector3).x * at.x + (through[3] as Vector3).y * at.y + (through[3] as Vector3).z
        var mapped := Vector2((plain[0] as Vector2).dot(at), (plain[1] as Vector2).dot(at)) + (plain[2] as Vector2)
        var homogeneous := (
            (Vector2((through[0] as Vector2).dot(at), (through[1] as Vector2).dot(at)) + (through[2] as Vector2)) / w
        )
        assert_almost_eq((mapped - homogeneous).length(), 0.0, 1e-2, "%s reads the same both ways" % at)


# --- The commit, which the affine part alone cannot decide ---------------------


## A perspective drag of the bottom right corner alone leaves the other three
## where they were, so the affine part through them is the identity. A commit
## that reads only that part calls the whole gesture "put down where it was" and
## throws the map away, which is the one thing a mode has to survive.
func test_a_perspective_commit_survives_an_identity_affine_part() -> void:
    var easel := SaEasel.create_default(Vector2i(512, 512))
    var document := easel.document
    document.active_layer.fill(Color(1.0, 0.0, 0.0, 1.0))
    var box := Rect2i(100, 100, 120, 120)
    document.selection.select_rect(box)
    var moving := SaTransform.new(document)
    assert_true(moving.lift(document.active_layer, box), "There is something to lift")

    var corners := SaHomography.corners_of(box)
    corners[2] = Vector2(300.0, 300.0)
    moving.preview_homography(SaHomography.corners_to_quad(box, corners))
    assert_true(moving.is_perspective(), "The pass is under a homography")
    assert_true(moving.matrix.is_equal_approx(Transform2D.IDENTITY), "and its affine part reads as the identity it is not")
    assert_true(moving.commit(), "Enter commits the map rather than cancelling it")

    var landed := document.active_layer.chunks.has(Vector2i(0, 0))
    assert_true(landed, "and the pixels are in the layer")
    moving = null
    easel.free()


# --- The modes, through the tool -----------------------------------------------


func _tool() -> Array:
    var surface := Fixtures.make_surface(Vector2i(1024, 1024))
    var machine := Fixtures.make_bound_machine(surface)
    var document := surface.get_document()
    document.active_layer.get_or_create_chunk(Vector2i(1, 1))
    document.selection.select_rect(Rect2i(400, 384, 500, 400))
    machine.set_active_tool(&"transform")
    return [surface, machine, machine.active_tool]


## The row is declared, defaults to Normal, and writing it writes the tool.
func test_the_mode_defaults_to_normal_and_is_written_by_its_row() -> void:
    var parts := _tool()
    var tool: StateTransformScript = parts[2]
    assert_eq(tool.transform_mode, StateTransformScript.Mode.NORMAL, "A fresh tool is in Normal")
    tool.transform_mode = StateTransformScript.Mode.PERSPECTIVE
    assert_eq(tool.mode, StateTransformScript.Mode.PERSPECTIVE, "and the row writes the mode the press reads")
    tool.transform_mode = 99
    assert_eq(tool.mode, StateTransformScript.Mode.CAGE, "A number past the end clamps rather than answering nothing")
    Fixtures.teardown(parts[0], parts[1])


## Shear mode is what Ctrl says on an edge under Normal. An edge handle leans the box
## over with nothing held.
func test_shear_mode_makes_an_edge_handle_lean_without_a_modifier() -> void:
    var parts := _tool()
    var surface: SaSurface = parts[0]
    var tool: StateTransformScript = parts[2]
    tool.transform_mode = StateTransformScript.Mode.SHEAR
    # The middle of the top edge, which is the (0, -1) handle.
    surface.view.mouse_position = Vector2(650, 384)
    tool.handle_input(_button(true))
    surface.view.mouse_position = Vector2(750, 384)
    tool.handle_input(InputEventMouseMotion.new())

    var leaned: float = tool.move_skew()
    assert_true(absf(leaned) > 0.01, "The box leaned over, %.4f" % leaned)
    Fixtures.teardown(parts[0], parts[1])

    # The same drag with Ctrl held in Normal mode, which is what the mode is
    # replacing. `move_scale().y` is not one either way: a sheared basis has a
    # y column longer than it was and `Transform2D.get_scale` reports that
    # length, so the number to compare is the lean and not the size.
    var plain := _tool()
    var plain_surface: SaSurface = plain[0]
    var plain_tool: StateTransformScript = plain[2]
    plain_surface.view.mouse_position = Vector2(650, 384)
    var with_ctrl: InputEventMouseButton = _button(true)
    with_ctrl.ctrl_pressed = true
    plain_tool.handle_input(with_ctrl)
    plain_surface.view.mouse_position = Vector2(750, 384)
    plain_tool.handle_input(InputEventMouseMotion.new())
    assert_almost_eq(plain_tool.move_skew(), leaned, 1e-4, "and leans exactly as far as Ctrl does")
    Fixtures.teardown(plain[0], plain[1])


## Perspective mode with Shift moves one corner and leaves the other three,
## which is what separates it from a scale. Without Shift the corner takes a
## neighbour along, which another suite reads.
func test_perspective_mode_moves_one_corner_and_leaves_the_rest() -> void:
    var parts := _tool()
    var surface: SaSurface = parts[0]
    var tool: StateTransformScript = parts[2]
    tool.transform_mode = StateTransformScript.Mode.PERSPECTIVE
    var before: PackedVector2Array = tool.pending_quad()
    surface.view.mouse_position = Vector2(400, 384)
    var shifted := _button(true)
    shifted.shift_pressed = true
    tool.handle_input(shifted)
    surface.view.mouse_position = Vector2(460, 420)
    tool.handle_input(InputEventMouseMotion.new())

    var after: PackedVector2Array = tool.pending_quad()
    assert_eq(after.size(), 4, "Still a quad")
    assert_almost_eq((after[0] - Vector2(460, 420)).length(), 0.0, 1.0, "The grabbed corner is where the pointer is")
    for i: int in [1, 2, 3]:
        assert_almost_eq((after[i] - before[i]).length(), 0.0, 1.0, "and corner %d has not moved" % i)
    Fixtures.teardown(parts[0], parts[1])


## The same drag in Normal mode scales, so the mode is what decided it rather
## than the handle.
func test_the_same_corner_drag_scales_in_normal_mode() -> void:
    var parts := _tool()
    var surface: SaSurface = parts[0]
    var tool: StateTransformScript = parts[2]
    var before: PackedVector2Array = tool.pending_quad()
    surface.view.mouse_position = Vector2(400, 384)
    tool.handle_input(_button(true))
    surface.view.mouse_position = Vector2(460, 420)
    tool.handle_input(InputEventMouseMotion.new())

    var after: PackedVector2Array = tool.pending_quad()
    assert_true((after[2] - before[2]).length() < 1.0, "The far corner is held still by a scale")
    assert_true((after[1] - before[1]).length() > 1.0, "and the two beside it move, which a corner drag does not")
    Fixtures.teardown(parts[0], parts[1])


## Leaving Perspective drops the corners rather than keeping a map the mode
## cannot express, and the picture keeps the affine part of where it was.
func test_leaving_perspective_drops_the_corners() -> void:
    var parts := _tool()
    var surface: SaSurface = parts[0]
    var tool: StateTransformScript = parts[2]
    tool.transform_mode = StateTransformScript.Mode.PERSPECTIVE
    surface.view.mouse_position = Vector2(400, 384)
    tool.handle_input(_button(true))
    surface.view.mouse_position = Vector2(460, 420)
    tool.handle_input(InputEventMouseMotion.new())
    assert_false(tool.preview_shape().has("ants"), "A perspective map hands the overlay no affine to draw through")

    tool.transform_mode = StateTransformScript.Mode.NORMAL

    assert_true(tool.preview_shape().has("ants"), "and Normal hands it one again")
    Fixtures.teardown(parts[0], parts[1])
