## The five transform modes are a strip on the canvas beside the box.
##
## The modes are toggles on the canvas as well as a row on the Tool Options
## docker, because and a painter mid-transform is looking at the canvas.
##
## The geometry first, because it is the half that has to be one description
## rather than two: `SaTransformModeStrip` builds the cells and
## `StateTransform._press` answers a press on them, and a strip drawn in one
## place and hit-tested in another is a control that works at one zoom. Then the
## tool, through the same door a real press comes in by.
##
## It sits under the module's tests with the class it reads, because the strip
## is the transform tool's and not the skeleton's.
##
## `scenarios/the-warp-mode-has-a-toggle-on-the-canvas.json` is the same claim
## on the running app, where the strip is shot beside the box, the freehand cell
## is pressed, and the mesh that appears is shot after it.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true
const Fixtures = preload("res://tests/fixtures.gd")
const StateTransformScript = preload("res://modules/sara-base-modules/base/transform/state_transform.gd")

## A box wide enough that the strip does not reach past its right edge at zoom 1,
## which is five cells of 22 and four gaps of 3, so 122 pixels.
const BOX := Rect2i(400, 384, 500, 400)


func _quad() -> PackedVector2Array:
    return SaHomography.corners_of(BOX)


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


# --- The geometry ---------------------------------------------------------------


func test_the_strip_is_a_row_of_cells_above_the_box() -> void:
    var boxes := SaTransformModeStrip.boxes(_quad(), 1.0)
    assert_eq(boxes.size(), SaTransformModeStrip.MODE_COUNT, "One cell per mode")
    assert_eq(boxes[0].position.x, float(BOX.position.x), "The first sits on the box's left edge")
    for index in boxes.size():
        assert_eq(boxes[index].size, Vector2(SaTransformModeStrip.MODE_CELL, SaTransformModeStrip.MODE_CELL), "square")
        assert_eq(boxes[index].position.y, boxes[0].position.y, "and all of them on one line")
    assert_true(boxes[3].end.y <= float(BOX.position.y), "The strip clears the box's top edge")
    for index in range(1, boxes.size()):
        assert_true(boxes[index].position.x >= boxes[index - 1].end.x, "and no two cells overlap")


func test_the_strip_is_the_same_size_on_screen_at_every_zoom() -> void:
    var near := SaTransformModeStrip.boxes(_quad(), 1.0)
    var far := SaTransformModeStrip.boxes(_quad(), 4.0)
    assert_almost_eq(far[0].size.x, near[0].size.x * 4.0, 1e-4, "Zoomed out, a cell is four times as many texels")
    assert_almost_eq(far[0].size.x / 4.0, near[0].size.x, 1e-4, "which is the same number of screen pixels")
    assert_eq(far[0].position.x, near[0].position.x, "The strip stays anchored to the box's left edge")
    assert_true(far[0].position.y < near[0].position.y, "and lifts further in texels the further out the view is")


## A warped or sheared quad has no top edge a strip can sit parallel to, so the
## strip is anchored to the quad's bounding box and stays upright.
func test_the_strip_follows_a_quad_that_is_not_a_rectangle() -> void:
    var leaning := PackedVector2Array([Vector2(460, 300), Vector2(900, 384), Vector2(860, 800), Vector2(400, 700)])
    var boxes := SaTransformModeStrip.boxes(leaning, 1.0)
    assert_eq(boxes.size(), SaTransformModeStrip.MODE_COUNT, "Every cell over a leaning quad too")
    assert_eq(boxes[0].position.x, 400.0, "at the leftmost point of it")
    assert_true(boxes[0].end.y <= 300.0, "and above the topmost")
    for index in range(1, boxes.size()):
        assert_eq(boxes[index].position.y, boxes[0].position.y, "still upright rather than leaning with the quad")


func test_a_quad_that_is_not_one_gets_no_strip() -> void:
    assert_eq(SaTransformModeStrip.boxes(PackedVector2Array(), 1.0).size(), 0, "No points, no strip")
    assert_eq(SaTransformModeStrip.boxes(_quad(), 0.0).size(), 0, "and no zoom to draw it at, none either")
    assert_eq(SaTransformModeStrip.pick(PackedVector2Array(), 1.0, Vector2.ZERO), -1, "and nothing to press")


func test_a_press_picks_the_cell_it_landed_in() -> void:
    var boxes := SaTransformModeStrip.boxes(_quad(), 1.0)
    for index in boxes.size():
        var middle := boxes[index].get_center()
        assert_eq(SaTransformModeStrip.pick(_quad(), 1.0, middle), index, "The middle of cell %d" % index)


func test_a_press_beside_the_strip_picks_nothing() -> void:
    var boxes := SaTransformModeStrip.boxes(_quad(), 1.0)
    assert_eq(SaTransformModeStrip.pick(_quad(), 1.0, Vector2(BOX.get_center())), -1, "Inside the box")
    assert_eq(SaTransformModeStrip.pick(_quad(), 1.0, boxes[3].end + Vector2(20.0, 0.0)), -1, "past the last cell")
    assert_eq(SaTransformModeStrip.pick(_quad(), 1.0, boxes[0].position - Vector2(0.0, 40.0)), -1, "above the strip")
    var between := Vector2(boxes[0].end.x + SaTransformModeStrip.MODE_GAP * 0.5, boxes[0].get_center().y)
    assert_eq(SaTransformModeStrip.pick(_quad(), 1.0, between), -1, "and in the gap between two cells")


# --- The tool -------------------------------------------------------------------


## The overlay is handed boxes and a glyph and knows nothing of a mode, so the
## mode reaches the picture as which cell is the filled one.
func test_the_preview_hands_the_overlay_a_cell_per_mode_and_marks_the_picked_one() -> void:
    var parts := _tool()
    var tool: StateTransformScript = parts[2]
    var resting: Dictionary = tool.preview_shape()
    assert_true(resting.has("cells"), "A resting box hands the overlay its cells")
    var cells: Array = resting["cells"]
    assert_eq(cells.size(), SaTransformModeStrip.MODE_COUNT, "one per mode")
    for index in cells.size():
        var cell: Dictionary = cells[index]
        var wanted: bool = index == StateTransformScript.Mode.NORMAL
        assert_eq(bool(cell["on"]), wanted, "only Normal is marked picked to begin with, cell %d" % index)
        assert_true((cell["glyph"] as Array).size() >= 1, "and every cell has a shape to draw")
    assert_true(SaTransformModeStrip.MODE_COUNT == StateTransformScript.Mode.size(), "and one cell for each mode")
    tool.transform_mode = StateTransformScript.Mode.SHEAR
    var moved: Array = (tool.preview_shape() as Dictionary)["cells"]
    assert_true(bool(moved[StateTransformScript.Mode.SHEAR]["on"]), "picking Shear moves the fill to its cell")
    assert_false(bool(moved[StateTransformScript.Mode.NORMAL]["on"]), "and off Normal's")
    Fixtures.teardown(parts[0], parts[1])


## The warp's cell is a square with a grid over it, so its glyph is three
## polylines, Mirrored's is its outline and a diagonal, and every other cell's is
## the one outline.
func test_the_warp_cell_draws_the_grid_over_its_square() -> void:
    var boxes := SaTransformModeStrip.boxes(_quad(), 1.0)
    var cells := SaTransformModeStrip.cells(_quad(), StateTransformScript.Mode.FREEHAND, 1.0)
    assert_eq(cells.size(), boxes.size(), "One cell per box")
    for index in cells.size():
        var glyph: Array = cells[index]["glyph"]
        assert_eq(cells[index]["box"], boxes[index], "drawn where the pick looks, cell %d" % index)
        var wanted := 1
        if index == StateTransformScript.Mode.FREEHAND:
            wanted = 3
        elif index == StateTransformScript.Mode.MIRRORED:
            wanted = 2
        assert_eq(glyph.size(), wanted, "cell %d draws %d polyline(s)" % [index, wanted])


func test_pressing_the_freehand_cell_writes_the_same_property_the_row_writes() -> void:
    var parts := _tool()
    var surface: SaSurface = parts[0]
    var tool: StateTransformScript = parts[2]
    assert_eq(tool.transform_mode, StateTransformScript.Mode.NORMAL, "Normal to begin with")
    var boxes := SaTransformModeStrip.boxes(tool.pending_quad(), 1.0 / surface.view.get_zoom())
    surface.view.mouse_position = boxes[StateTransformScript.Mode.FREEHAND].get_center()
    tool.handle_input(_button(true))
    assert_eq(tool.transform_mode, StateTransformScript.Mode.FREEHAND, "and the strip's fourth cell writes Freehand")
    assert_false(tool.is_moving(), "The press that picked a mode lifted nothing")
    Fixtures.teardown(parts[0], parts[1])


func test_every_cell_of_the_strip_writes_its_own_mode() -> void:
    var parts := _tool()
    var surface: SaSurface = parts[0]
    var tool: StateTransformScript = parts[2]
    var wanted := [
        StateTransformScript.Mode.PERSPECTIVE,
        StateTransformScript.Mode.SHEAR,
        StateTransformScript.Mode.FREEHAND,
        StateTransformScript.Mode.NORMAL,
    ]
    for mode: int in wanted:
        var boxes := SaTransformModeStrip.boxes(tool.pending_quad(), 1.0 / surface.view.get_zoom())
        surface.view.mouse_position = boxes[mode].get_center()
        tool.handle_input(_button(true))
        tool.handle_input(_button(false))
        assert_eq(tool.transform_mode, mode, "Cell %d writes mode %d" % [mode, mode])
    Fixtures.teardown(parts[0], parts[1])


## The strip is checked before a gesture is chosen, so the cells must not eat a
## press meant for the box. The box is 500 by 400 and the strip is 97 by 22
## above its top edge, so nothing inside the box can reach one.
func test_a_press_on_the_box_still_lifts_it() -> void:
    var parts := _tool()
    var surface: SaSurface = parts[0]
    var tool: StateTransformScript = parts[2]
    surface.view.mouse_position = Vector2(BOX.get_center())
    tool.handle_input(_button(true))
    surface.view.mouse_position = Vector2(BOX.get_center()) + Vector2(30.0, 20.0)
    tool.handle_input(InputEventMouseMotion.new())
    assert_true(tool.is_moving(), "A press inside the box is still a move")
    assert_eq(tool.transform_mode, StateTransformScript.Mode.NORMAL, "and changed no mode on the way")
    Fixtures.teardown(parts[0], parts[1])


## The freehand cell is the one the audit row is about: picking it has to give
## the painter the mesh, not only the mode.
func test_the_freehand_cell_gives_the_mesh_the_next_drag_bends() -> void:
    var parts := _tool()
    var surface: SaSurface = parts[0]
    var tool: StateTransformScript = parts[2]
    var boxes := SaTransformModeStrip.boxes(tool.pending_quad(), 1.0 / surface.view.get_zoom())
    surface.view.mouse_position = boxes[StateTransformScript.Mode.FREEHAND].get_center()
    tool.handle_input(_button(true))
    tool.handle_input(_button(false))
    surface.view.mouse_position = Vector2(BOX.get_center())
    tool.handle_input(_button(true))
    surface.view.mouse_position = Vector2(BOX.get_center()) + Vector2(40.0, 30.0)
    tool.handle_input(InputEventMouseMotion.new())
    var mesh: PackedVector2Array = tool.pending_mesh()
    assert_eq(mesh.size(), 9, "The nine points are there after the strip picked the mode")
    var shape: Dictionary = tool.preview_shape()
    assert_eq((shape["knots"] as PackedVector2Array).size(), 9, "and the overlay is handed them as points")
    assert_eq((shape["lines"] as Array).size(), 6, "with the grid's six lines")
    assert_true(
        bool((shape["cells"] as Array)[StateTransformScript.Mode.FREEHAND]["on"]), "beside the cell the strip wrote the mode into"
    )
    Fixtures.teardown(parts[0], parts[1])
