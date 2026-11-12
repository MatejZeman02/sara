## The Polygonal Lasso closes on a click near its first point measured in
## screen pixels, so zoomed in it does not close early on points placed near the
## start and zoomed out it closes on a click on the first point as the painter
## sees it.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

const FIRST := Vector2(100, 100)
const SECOND := Vector2(300, 100)
const THIRD := Vector2(300, 300)

var _surface: SaSurface = null
var _machine: ToolMachine = null


func before_each() -> void:
    _surface = Fixtures.make_surface(Vector2i(512, 512))
    _machine = Fixtures.make_bound_machine(_surface)


func after_each() -> void:
    Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null


func test_a_click_a_few_screen_pixels_from_the_first_point_closes_at_twenty_five_and_eight_hundred_per_cent() -> void:
    var doc := _surface.get_document()
    _machine.set_active_tool(&"polygonal_lasso")
    var tool := _machine.active_tool

    # At 25 %, 12 document pixels is 3 screen pixels.
    _surface.view.set_zoom(0.25)
    _click(tool, FIRST)
    _click(tool, SECOND)
    _click(tool, THIRD)
    _click(tool, FIRST + Vector2(12, 0))
    assert_true(doc.selection.active, "the selection is made at 25 % zoom")
    assert_true(tool.preview_shape().is_empty(), "the points are spent at 25 % zoom")

    doc.selection.drop()
    tool.reset()

    # At 800 %, 0.5 document pixels is 4 screen pixels.
    _surface.view.set_zoom(8.0)
    _click(tool, FIRST)
    _click(tool, SECOND)
    _click(tool, THIRD)
    _click(tool, FIRST + Vector2(0.5, 0))
    assert_true(doc.selection.active, "the selection is made at 800 % zoom")
    assert_true(tool.preview_shape().is_empty(), "the points are spent at 800 % zoom")


func test_a_click_beyond_screen_reach_within_eight_document_pixels_stays_open_at_eight_hundred_per_cent() -> void:
    var doc := _surface.get_document()
    _machine.set_active_tool(&"polygonal_lasso")
    var tool := _machine.active_tool

    # At 800 %, 5 document pixels is 40 screen pixels, well beyond the 8 screen pixel reach
    # but within the old 8 document pixel threshold.
    _surface.view.set_zoom(8.0)
    _click(tool, FIRST)
    _click(tool, SECOND)
    _click(tool, THIRD)
    _click(tool, FIRST + Vector2(5, 0))
    assert_false(doc.selection.active, "the selection is not closed prematurely")
    var points: PackedVector2Array = tool.preview_shape().get("points", PackedVector2Array())
    assert_eq(points.size(), 4, "and the polygon is still open with four points")


func _click(tool: ToolState, at: Vector2) -> void:
    _surface.view.mouse_position = at
    tool.handle_input(_button(true))
    tool.handle_input(_button(false))


func _button(pressed: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    return event
