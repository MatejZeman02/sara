## The transform tool's Cage mode, a polygon clicked round the subject
## whose points bend the picture inside by Green coordinates.
##
## The weights first, as arithmetic, because a cage whose weights do not give
## the grid back unmoved bends every picture it closes on and no shot says by
## how much. Then the pass through the warp kernel's storage buffer, and the
## tool through its presses.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true
const Fixtures = preload("res://tests/fixtures.gd")
const StateTransformScript = preload("res://modules/sara-base-modules/base/transform/state_transform.gd")

## The box the lift takes, and a six-point cage wholly round it, so every
## point of the grid is inside, clicked clockwise on the screen so the close
## has a winding to turn.
const BOX := Rect2i(100, 100, 200, 120)
const CAGE: Array[Vector2] = [
    Vector2(80, 80), Vector2(200, 60), Vector2(330, 80), Vector2(340, 240), Vector2(200, 260), Vector2(70, 240)
]


func _cage() -> SaTransformCage:
    var cage := SaTransformCage.new(PackedVector2Array(CAGE))
    assert_true(cage.close(BOX), "The six points close a cage over the box")
    return cage


func _rest() -> PackedVector2Array:
    return SaTransformMesh.grid_over(SaHomography.corners_of(BOX), SaTransformCage.SIDE)


func _button(pressed: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    return event


# --- The weights, as arithmetic ---------------------------------------------------


func test_a_closed_cage_with_no_point_moved_maps_every_mesh_point_to_itself() -> void:
    var cage := _cage()
    var rest := _rest()
    var mesh := cage.mesh_for(cage.points())
    assert_eq(mesh.size(), rest.size(), "The mesh is the grid, %d points" % rest.size())
    var worst := 0.0
    for index in mini(mesh.size(), rest.size()):
        worst = maxf(worst, mesh[index].distance_to(rest[index]))
    assert_true(worst <= 0.001, "every point within a thousandth of a texel of itself, the worst %f" % worst)


func test_a_cage_moved_whole_by_an_offset_moves_every_mesh_point_by_it() -> void:
    var cage := _cage()
    var rest := _rest()
    var by := Vector2(37.0, -21.5)
    var moved := PackedVector2Array()
    for point: Vector2 in cage.points():
        moved.append(point + by)
    var mesh := cage.mesh_for(moved)
    assert_eq(mesh.size(), rest.size(), "The mesh is the grid")
    var worst := 0.0
    for index in mini(mesh.size(), rest.size()):
        worst = maxf(worst, mesh[index].distance_to(rest[index] + by))
    assert_true(worst <= 0.001, "every point moved by the offset within a thousandth of a texel, the worst %f" % worst)


func test_the_weights_reproduce_the_point_they_were_worked_out_for() -> void:
    # Green coordinates reproduce the identity, the points by their weights and
    # the edges' outward normals by theirs, which is the whole of what makes a
    # moved cage's differences the map. Asked here of the bare weights, since
    # `mesh_for` writes the grid as rest plus differences and an unmoved cage
    # gives nothing to sum.
    var cage := _cage()
    var points := cage.points()
    var count := points.size()
    for at: Vector2 in [Vector2(200, 160), Vector2(110, 105), Vector2(295, 215)]:
        var weights := SaTransformCage.Green.weights(points, at)
        var sum := Vector2.ZERO
        var share := 0.0
        for i in count:
            sum += points[i] * weights[i]
            share += weights[i]
        for j in count:
            var normal := SaTransformCage.Green._normal(points[j], points[(j + 1) % count], 1.0)
            sum += Vector2(normal[0], normal[1]) * weights[count + j]
        assert_almost_eq(share, 1.0, 1e-6, "the point weights at %s add to one" % at)
        assert_true(sum.distance_to(at) <= 0.001, "and give %s back, not %s" % [at, sum])


func test_a_point_outside_the_cage_stays_and_one_dragged_point_bends_toward_itself() -> void:
    var small := SaTransformCage.new(PackedVector2Array([Vector2(150, 120), Vector2(250, 120), Vector2(200, 200)]))
    assert_true(small.close(BOX), "A triangle inside the box closes")
    var rest := _rest()
    var moved := small.points()
    var pulled := 0
    for index in moved.size():
        if moved[index].distance_to(Vector2(200, 200)) < 0.5:
            pulled = index
    moved[pulled] += Vector2(0, 40)
    var mesh := small.mesh_for(moved)
    assert_eq(mesh[0], rest[0], "the box's top left, outside the cage, stays")
    assert_eq(mesh[mesh.size() - 1], rest[rest.size() - 1], "and so does its bottom right")
    var nearest := 0
    for index in rest.size():
        if rest[index].distance_to(Vector2(200, 180)) < rest[nearest].distance_to(Vector2(200, 180)):
            nearest = index
    assert_true(mesh[nearest].y > rest[nearest].y + 5.0, "a point inside near the dragged one follows it down")


func test_a_cage_that_crosses_itself_or_has_two_points_does_not_close() -> void:
    var bow := SaTransformCage.new(PackedVector2Array([Vector2(0, 0), Vector2(100, 100), Vector2(100, 0), Vector2(0, 100)]))
    assert_false(bow.close(BOX), "A bow tie has no inside to weigh")
    var two := SaTransformCage.new(PackedVector2Array([Vector2(0, 0), Vector2(100, 100)]))
    assert_false(two.close(BOX), "and two points are no polygon")


# --- The pass, through the kernel's storage buffer -----------------------------------


func _alpha_at(document: SaDocument, at: Vector2i) -> float:
    var grid_pos := Vector2i(floori(float(at.x) / SaChunk.SIZE), floori(float(at.y) / SaChunk.SIZE))
    var chunk: SaChunk = document.stroke_layer.chunks.get(grid_pos, null)
    if chunk == null:
        return 0.0
    var data: PackedByteArray = GlobalShaderCompiler.get_rd().texture_get_data(chunk.albedo().rid, 0)
    var local := at - grid_pos * SaChunk.SIZE
    return data.decode_float((local.y * SaChunk.SIZE + local.x) * 16 + 12)


func test_the_kernel_draws_the_picture_through_the_cage_s_dense_mesh() -> void:
    var easel := SaEasel.create_default(Vector2i(512, 512))
    var document := easel.document
    document.active_layer.fill(Color(1.0, 0.0, 0.0, 1.0))
    document.selection.select_rect(BOX)
    var moving := SaTransform.new(document)
    assert_true(moving.lift(document.active_layer, BOX), "There is something to lift")
    var cage := _cage()
    var moved := cage.points()
    # The right hand point pulled further right, so the right edge bulges.
    var right := 0
    for index in moved.size():
        if moved[index].x > moved[right].x:
            right = index
    moved[right] += Vector2(60, 0)
    moving.preview_mesh(cage.mesh_for(moved))
    assert_true(moving.is_warped(), "The pass is under the cage's mesh")
    assert_eq(moving.mesh().size(), SaTransformCage.SIDE * SaTransformCage.SIDE, "all of its points")
    moving.tick()
    assert_true(_alpha_at(document, Vector2i(310, 170)) > 0.99, "a texel past the box's right edge is picture now")
    assert_true(_alpha_at(document, Vector2i(200, 160)) > 0.99, "and the middle still is")
    assert_true(_alpha_at(document, Vector2i(400, 160)) < 0.01, "and far past the pulled point is not")
    assert_true(moving.commit(), "Enter commits the bend")
    moving = null
    easel.free()


# --- The tool -----------------------------------------------------------------------


func _tool() -> Array:
    var surface := Fixtures.make_surface(Vector2i(1024, 1024))
    var machine := Fixtures.make_bound_machine(surface)
    var document := surface.get_document()
    document.active_layer.get_or_create_chunk(Vector2i(1, 1))
    document.selection.select_rect(Rect2i(400, 384, 300, 200))
    machine.set_active_tool(&"transform")
    return [surface, machine, machine.active_tool]


func _click(surface: SaSurface, tool: StateTransformScript, at: Vector2) -> void:
    surface.view.mouse_position = at
    tool.handle_input(_button(true))
    tool.handle_input(_button(false))


func test_clicks_close_a_cage_a_drag_bends_and_enter_and_undo_are_one_step() -> void:
    var parts := _tool()
    var surface: SaSurface = parts[0]
    var tool: StateTransformScript = parts[2]
    var document := surface.get_document()
    var steps_before: int = document.history.step_count()
    tool.transform_mode = StateTransformScript.Mode.CAGE
    var outline: Array[Vector2] = [
        Vector2(380, 370), Vector2(550, 350), Vector2(720, 370), Vector2(730, 600), Vector2(550, 620), Vector2(370, 600)
    ]
    for point: Vector2 in outline:
        _click(surface, tool, point)
    var report: Dictionary = tool.capture_report(&"transform", true)
    assert_eq((report["transform"]["cage"] as Array).size(), 6, "Six clicks place six points")
    assert_false(bool(report["transform"]["cage_closed"]), "and the cage is still open")
    assert_false(tool.is_moving(), "with nothing lifted")
    _click(surface, tool, outline[0] + Vector2(2, 1))
    report = tool.capture_report(&"transform", true)
    assert_true(bool(report["transform"]["cage_closed"]), "A click on the first point closes it")
    var knots := tool.preview_shape().get("knots", PackedVector2Array()) as PackedVector2Array
    assert_eq(knots.size(), 6, "and the overlay is handed its six points")
    surface.view.mouse_position = Vector2(730, 600)
    tool.handle_input(_button(true))
    surface.view.mouse_position = Vector2(800, 650)
    tool.handle_input(InputEventMouseMotion.new())
    tool.handle_input(_button(false))
    assert_true(tool.is_moving(), "A drag of a point lifts the picture")
    assert_eq(tool.pending_mesh().size(), SaTransformCage.SIDE * SaTransformCage.SIDE, "under the cage's mesh")
    assert_true(tool.commit_move(), "Enter commits the bend")
    assert_eq(document.history.step_count(), steps_before + 1, "as one step")
    assert_eq((tool.capture_report(&"transform", true)["transform"]["cage"] as Array).size(), 0, "and the cage is gone")
    assert_true(document.undo(), "which undo takes back")
    Fixtures.teardown(parts[0], parts[1])


func test_escape_clears_an_open_cage_and_leaving_the_mode_drops_it() -> void:
    var parts := _tool()
    var surface: SaSurface = parts[0]
    var tool: StateTransformScript = parts[2]
    tool.transform_mode = StateTransformScript.Mode.CAGE
    _click(surface, tool, Vector2(380, 370))
    _click(surface, tool, Vector2(720, 370))
    var escape := InputEventKey.new()
    escape.keycode = KEY_ESCAPE
    escape.pressed = true
    tool.handle_input(escape)
    assert_eq((tool.capture_report(&"transform", true)["transform"]["cage"] as Array).size(), 0, "Escape clears it")
    assert_false(tool.pending_box().size == Vector2i.ZERO, "and leaves the box up")
    _click(surface, tool, Vector2(380, 370))
    tool.transform_mode = StateTransformScript.Mode.CAGE
    var kept := tool.capture_report(&"transform", true)["transform"]["cage"] as Array
    assert_eq(kept.size(), 1, "The mode written again keeps the cage")
    tool.transform_mode = StateTransformScript.Mode.NORMAL
    assert_eq((tool.capture_report(&"transform", true)["transform"]["cage"] as Array).size(), 0, "and another mode drops it")
    Fixtures.teardown(parts[0], parts[1])
