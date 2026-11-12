## The freehand warp: a mesh of nine points over the box, one dragged, the
## pixels following by a bilinear patch per cell, committed as one step and
## undone.
##
## The mesh arithmetic first, because a warp whose forward map disagrees with
## its kernel's inverse tears at every cell edge and no picture says which
## side is wrong. Then the pass through the kernel, read back the way the
## resample suite reads, and the tool through its handles.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true
const Fixtures = preload("res://tests/fixtures.gd")
const StateTransformScript = preload("res://modules/sara-base-modules/base/transform/state_transform.gd")

const BOX := Rect2i(100, 100, 200, 100)


func _button(pressed: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    return event


# --- The mesh, as arithmetic ------------------------------------------------------


func test_the_grid_over_a_box_is_its_corners_edges_and_centre() -> void:
    var mesh := SaTransformMesh.grid_over(SaHomography.corners_of(BOX))
    assert_eq(mesh.size(), 9, "Nine points")
    assert_eq(mesh[0], Vector2(100, 100), "the top left")
    assert_eq(mesh[2], Vector2(300, 100), "the top right")
    assert_eq(mesh[4], Vector2(200, 150), "the centre")
    assert_eq(mesh[8], Vector2(300, 200), "and the bottom right")
    assert_eq(SaTransformMesh.corners_of(mesh), SaHomography.corners_of(BOX), "and the corners read in the quad's order")


func test_the_forward_map_lands_a_dragged_centre_where_it_was_put() -> void:
    var mesh := SaTransformMesh.grid_over(SaHomography.corners_of(BOX))
    mesh[4] = Vector2(260, 190)
    var centre := SaTransformMesh.through(mesh, BOX, Vector2(BOX.get_center()))
    assert_almost_eq((centre - Vector2(260, 190)).length(), 0.0, 1e-3, "the centre of the picture is where the point went")
    var corner := SaTransformMesh.through(mesh, BOX, Vector2(BOX.position))
    assert_almost_eq((corner - Vector2(BOX.position)).length(), 0.0, 1e-3, "and a corner stays put")
    var quarter := SaTransformMesh.through(mesh, BOX, Vector2(150, 125))
    assert_almost_eq((quarter - Vector2(165, 135)).length(), 0.0, 1e-3, "and a point between blends the cell it is in")
    var reach := SaTransformMesh.bounds_of(mesh)
    assert_true(reach.encloses(Rect2i(BOX.position, BOX.size)), "the reach holds the box")
    assert_true(reach.has_point(Vector2i(260, 190)), "and the dragged point")


func test_the_nearest_point_is_found_within_reach_and_not_beyond() -> void:
    var mesh := SaTransformMesh.grid_over(SaHomography.corners_of(BOX))
    assert_eq(SaTransformMesh.nearest(mesh, Vector2(203, 148), 10.0), 4, "the centre from three pixels off")
    assert_eq(SaTransformMesh.nearest(mesh, Vector2(203, 148), 2.0), -1, "and nothing from further than the reach")
    assert_eq(SaTransformMesh.lines_of(mesh).size(), 6, "three lines across and three down")


# --- The pass, through the kernel ----------------------------------------------------


func _alpha_at(document: SaDocument, at: Vector2i) -> float:
    var grid_pos := Vector2i(floori(float(at.x) / SaChunk.SIZE), floori(float(at.y) / SaChunk.SIZE))
    var chunk: SaChunk = document.stroke_layer.chunks.get(grid_pos, null)
    if chunk == null:
        return 0.0
    var texture: SaTexture = chunk.albedo()
    var data: PackedByteArray = GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var local := at - grid_pos * SaChunk.SIZE
    return data.decode_float((local.y * SaChunk.SIZE + local.x) * 16 + 12)


func test_the_kernel_bends_the_picture_through_the_dragged_centre() -> void:
    var easel := SaEasel.create_default(Vector2i(512, 512))
    var document := easel.document
    document.active_layer.fill(Color(1.0, 0.0, 0.0, 1.0))
    var box := Rect2i(100, 100, 100, 100)
    document.selection.select_rect(box)
    var moving := SaTransform.new(document)
    assert_true(moving.lift(document.active_layer, box), "There is something to lift")
    var mesh := SaTransformMesh.grid_over(SaHomography.corners_of(box))
    mesh[4] = Vector2(240, 150)
    moving.preview_mesh(mesh)
    assert_true(moving.is_warped(), "The pass is under a mesh")
    assert_false(moving.is_perspective(), "and not a homography")
    assert_true(moving.landed_bounds().has_point(Vector2i(240, 150)), "and the reach holds the dragged point")
    moving.tick()
    assert_true(_alpha_at(document, Vector2i(225, 150)) > 0.99, "a texel past the box's right edge is picture now")
    assert_true(_alpha_at(document, Vector2i(150, 150)) > 0.99, "and the middle still is")
    assert_true(_alpha_at(document, Vector2i(150, 105)) > 0.99, "and the top edge, which the centre's drag does not reach")
    assert_true(_alpha_at(document, Vector2i(260, 150)) < 0.01, "and past the dragged point is not")
    assert_true(moving.commit(), "Enter commits the warp")
    moving = null
    easel.free()


# --- The tool -----------------------------------------------------------------------


func _tool() -> Array:
    var surface := Fixtures.make_surface(Vector2i(1024, 1024))
    var machine := Fixtures.make_bound_machine(surface)
    var document := surface.get_document()
    document.active_layer.get_or_create_chunk(Vector2i(1, 1))
    document.selection.select_rect(Rect2i(400, 384, 500, 400))
    machine.set_active_tool(&"transform")
    return [surface, machine, machine.active_tool]


func test_freehand_mode_drags_one_point_and_leaves_the_corners() -> void:
    var parts := _tool()
    var surface: SaSurface = parts[0]
    var tool: StateTransformScript = parts[2]
    tool.transform_mode = StateTransformScript.Mode.FREEHAND
    var before: PackedVector2Array = tool.pending_quad()
    surface.view.mouse_position = Vector2(650, 584)
    tool.handle_input(_button(true))
    surface.view.mouse_position = Vector2(700, 620)
    tool.handle_input(InputEventMouseMotion.new())
    var mesh: PackedVector2Array = tool.pending_mesh()
    assert_eq(mesh.size(), 9, "A warp is in the air with its nine points")
    if mesh.size() == 9:
        assert_almost_eq((mesh[4] - Vector2(700, 620)).length(), 0.0, 1.0, "the centre is where the pointer is")
        assert_almost_eq((mesh[0] - before[0]).length(), 0.0, 1.0, "and the top left corner has not moved")
    var shape: Dictionary = tool.preview_shape()
    assert_true(shape.has("knots"), "the overlay is handed the mesh")
    assert_false(bool(shape.get("handles", true)), "in place of the eight handles")
    var report: Dictionary = tool.capture_report(&"transform", true)
    assert_eq((report["transform"]["mesh"] as Array).size(), 9, "and the dump carries it")
    tool.transform_mode = StateTransformScript.Mode.NORMAL
    assert_eq(tool.pending_mesh().size(), 0, "Leaving Freehand drops the mesh")
    Fixtures.teardown(parts[0], parts[1])


func test_a_warp_commits_as_one_step_and_undo_restores() -> void:
    var parts := _tool()
    var surface: SaSurface = parts[0]
    var tool: StateTransformScript = parts[2]
    var document := surface.get_document()
    var steps_before: int = document.history.step_count()
    tool.transform_mode = StateTransformScript.Mode.FREEHAND
    surface.view.mouse_position = Vector2(650, 584)
    tool.handle_input(_button(true))
    surface.view.mouse_position = Vector2(700, 620)
    tool.handle_input(InputEventMouseMotion.new())
    tool.handle_input(_button(false))
    assert_true(tool.is_moving(), "The warp is in the air")
    assert_true(tool.commit_move(), "and Enter commits it")
    assert_false(tool.is_moving(), "leaving nothing in the air")
    assert_eq(document.history.step_count(), steps_before + 1, "as one step")
    assert_true(document.undo(), "which undo takes back")
    Fixtures.teardown(parts[0], parts[1])
