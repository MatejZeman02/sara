## The polygonal lasso is a tool of its own beside the freehand Lasso.
##
## Four points clicked with the Polygonal Lasso close into one selection
## whichever of its three closes ends the outline, a double click on the last
## point, a click back on the first or Enter, and the Lasso dragged round the
## same four points selects as well. Every reading is a pixel of the mask, so
## a close that went through the wrong path cannot pass on a flag.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

## The four corners, a quadrilateral across the seam of four chunks so the
## outline is no rectangle a marquee would have made.
const CORNERS: Array[Vector2] = [Vector2(60, 80), Vector2(420, 50), Vector2(450, 400), Vector2(90, 430)]
## Pixels inside the outline, one in each chunk it crosses.
const INSIDE: Array[Vector2i] = [Vector2i(150, 150), Vector2i(350, 150), Vector2i(350, 350), Vector2i(150, 350)]
## Pixels outside it, beyond each edge.
const OUTSIDE: Array[Vector2i] = [Vector2i(240, 20), Vector2i(480, 240), Vector2i(240, 470), Vector2i(30, 240)]

var _surface: SaSurface = null
var _machine: ToolMachine = null


func before_each() -> void:
    _surface = Fixtures.make_surface(Vector2i(512, 512))
    _machine = Fixtures.make_bound_machine(_surface)


func after_each() -> void:
    Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null


func test_the_two_lassos_are_two_tools_and_neither_has_a_shape_row() -> void:
    var registry := _machine.registry
    for id: StringName in [&"lasso", &"polygonal_lasso"]:
        var descriptor := registry.get_descriptor(id)
        assert_not_null(descriptor, "%s is a registered tool" % id)
        for spec: SaOptionSpec in descriptor.options:
            assert_false(spec.key == &"lasso_shape", "%s declares no Freehand or Polygon row" % id)
    var polygonal := registry.get_descriptor(&"polygonal_lasso")
    assert_eq(polygonal.display_name, "Polygonal Lasso", "named as Krita and Photoshop name it")
    assert_eq(polygonal.icon_name, "polygonal_lasso", "with an icon of its own")
    assert_eq(polygonal.activate_action, &"tool_polygonal_lasso", "and an action of its own")
    assert_true(InputMap.has_action(&"tool_polygonal_lasso"), "which the input map holds")
    _machine.set_active_tool(&"lasso")
    assert_false(_machine.active_tool.polygon, "The Lasso is freehand alone")
    _machine.set_active_tool(&"polygonal_lasso")
    assert_true(_machine.active_tool.polygon, "and the Polygonal Lasso lays a point a click")


func test_a_double_click_a_click_on_the_first_point_and_enter_close_the_same_selection() -> void:
    var doc := _surface.get_document()
    _machine.set_active_tool(&"polygonal_lasso")
    var tool := _machine.active_tool

    _click_corners(tool)
    _surface.view.mouse_position = CORNERS[3]
    var double := _button(true)
    double.double_click = true
    tool.handle_input(double)
    tool.handle_input(_button(false))
    var by_double := _mask_reading(doc)
    var bounds := doc.selection.bounds
    _assert_the_outline(by_double, "A double click on the last point")
    doc.selection.drop()

    _click_corners(tool)
    _surface.view.mouse_position = CORNERS[0] + Vector2(3, -2)
    tool.handle_input(_button(true))
    tool.handle_input(_button(false))
    assert_eq(_mask_reading(doc), by_double, "A click back on the first point closes the same selection")
    assert_eq(doc.selection.bounds, bounds, "over the same bounds")
    doc.selection.drop()

    _click_corners(tool)
    tool.handle_input(_key(KEY_ENTER))
    assert_eq(_mask_reading(doc), by_double, "Enter closes the same selection")
    assert_eq(doc.selection.bounds, bounds, "over the same bounds")
    assert_true(tool.preview_shape().is_empty(), "and the points are spent")


func test_escape_throws_the_polygonal_lassos_points_away() -> void:
    var doc := _surface.get_document()
    _machine.set_active_tool(&"polygonal_lasso")
    var tool := _machine.active_tool
    _click_corners(tool)
    assert_eq((tool.preview_shape().get("points") as PackedVector2Array).size(), 4, "Four clicks are four points")
    tool.handle_input(_key(KEY_ESCAPE))
    assert_true(tool.preview_shape().is_empty(), "Escape throws them away")
    assert_false(doc.selection.active, "and selects nothing")


func test_the_lasso_dragged_round_the_four_points_selects_them() -> void:
    var doc := _surface.get_document()
    _machine.set_active_tool(&"lasso")
    var tool := _machine.active_tool
    _surface.view.mouse_position = CORNERS[0]
    tool.handle_input(_button(true))
    for at: Vector2 in CORNERS.slice(1):
        _surface.view.mouse_position = at
        tool.handle_input(InputEventMouseMotion.new())
    assert_true(tool.preview_shape().get("closed", false), "The Lasso's outline closes on release, a drag")
    tool.handle_input(_button(false))
    _assert_the_outline(_mask_reading(doc), "The Lasso dragged round the four points")

    _machine.set_active_tool(&"polygonal_lasso")
    var polygonal := _machine.active_tool
    _click_corners(polygonal)
    polygonal.handle_input(_key(KEY_ENTER))
    var clicked := _mask_reading(doc)
    _machine.set_active_tool(&"lasso")
    _surface.view.mouse_position = CORNERS[0]
    tool = _machine.active_tool
    tool.handle_input(_button(true))
    for at: Vector2 in CORNERS.slice(1):
        _surface.view.mouse_position = at
        tool.handle_input(InputEventMouseMotion.new())
    tool.handle_input(_button(false))
    assert_eq(_mask_reading(doc), clicked, "and selects what the Polygonal Lasso clicked round them")


func _click_corners(tool: ToolState) -> void:
    for at: Vector2 in CORNERS:
        _surface.view.mouse_position = at
        tool.handle_input(_button(true))
        tool.handle_input(_button(false))


func _assert_the_outline(reading: Array, said: String) -> void:
    for i: int in INSIDE.size():
        assert_almost_eq(float(reading[i]), 1.0, 0.001, "%s selects %s inside" % [said, INSIDE[i]])
    for i: int in OUTSIDE.size():
        assert_almost_eq(float(reading[INSIDE.size() + i]), 0.0, 0.001, "%s leaves %s outside" % [said, OUTSIDE[i]])


## The mask at every probe, the inside ones first, rounded to a thousandth so
## two closes compare as equal arrays.
func _mask_reading(doc: SaDocument) -> Array:
    var reading: Array = []
    for at: Vector2i in INSIDE + OUTSIDE:
        reading.append(snappedf(_coverage_of(doc, at.x, at.y), 0.001))
    return reading


func _coverage_of(doc: SaDocument, x: int, y: int) -> float:
    var side := SaChunk.SIZE
    @warning_ignore("integer_division")
    var chunk: SaChunk = doc.selection.chunks.get(Vector2i(x / side, y / side), null)
    if chunk == null:
        return 0.0
    var texture := chunk.field(SaSelection.FIELD)
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return bytes.decode_float(((y % side) * texture.size.x + x % side) * 4)


func _button(pressed: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    return event


func _key(code: Key) -> InputEventKey:
    var event := InputEventKey.new()
    event.keycode = code
    event.pressed = true
    return event
