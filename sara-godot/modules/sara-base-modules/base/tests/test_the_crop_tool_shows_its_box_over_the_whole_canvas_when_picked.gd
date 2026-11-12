## The crop tool shows its box over the whole canvas when
## picked, as Photoshop does.
##
## Picked on a 400 by 300 document the box stands on the canvas with handles,
## Enter on it writes no step, a pull of its right handle and Enter crop the
## canvas and leave the box on the new canvas, and a click that does not
## travel on a tool with no box drawn leaves the canvas's box.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true
const Fixtures = preload("res://tests/fixtures.gd")

const SIZE := Vector2i(400, 300)


func test_the_box_starts_on_the_canvas_and_comes_back_after_a_crop() -> void:
    var surface := Fixtures.make_surface(SIZE)
    var machine := Fixtures.make_bound_machine(surface)
    var doc := surface.get_document()
    var view := surface.view
    machine.set_active_tool(&"crop")
    var tool := machine.active_tool
    # The skeleton's engines, which a bare machine does not hand a tool.
    tool.roles = Fixtures.make_registries().roles

    assert_eq(tool.call(&"pending_rect"), Rect2i(0, 0, 400, 300), "Picked, the box is the canvas")
    var shape: Dictionary = tool.preview_shape()
    assert_eq(shape.get("rect"), Rect2(0, 0, 400, 300), "and the overlay is told it")
    assert_true(shape.get("handles", false), "with its handles")

    var steps := doc.history.step_count()
    tool.handle_input(_key(KEY_ENTER))
    assert_eq(doc.history.step_count(), steps, "Enter on the whole canvas writes no step")
    assert_eq(doc.canvas_size, SIZE, "and crops nothing")

    view.mouse_position = Vector2(400, 150)
    tool.handle_input(_button(true))
    view.mouse_position = Vector2(300, 150)
    tool.handle_input(InputEventMouseMotion.new())
    tool.handle_input(_button(false))
    assert_eq(tool.call(&"pending_rect"), Rect2i(0, 0, 300, 300), "The right handle pulls the side in")
    tool.handle_input(_key(KEY_ENTER))
    assert_eq(doc.canvas_size, Vector2i(300, 300), "Enter crops the canvas")
    assert_eq(doc.history.step_count(), steps + 1, "as one step")
    assert_eq(tool.call(&"pending_rect"), Rect2i(0, 0, 300, 300), "and the box stands on the new canvas")
    Fixtures.teardown(surface, machine)


func test_a_click_that_does_not_travel_leaves_the_canvas_box() -> void:
    var surface := Fixtures.make_surface(SIZE)
    var machine := Fixtures.make_bound_machine(surface)
    var view := surface.view
    machine.set_active_tool(&"crop")
    var tool := machine.active_tool

    view.mouse_position = Vector2(150, 120)
    tool.handle_input(_button(true))
    tool.handle_input(_button(false))
    assert_eq(tool.call(&"pending_rect"), Rect2i(0, 0, 400, 300), "A click puts the box on the canvas")

    view.mouse_position = Vector2(100, 100)
    tool.handle_input(_button(true))
    view.mouse_position = Vector2(200, 180)
    tool.handle_input(InputEventMouseMotion.new())
    tool.handle_input(_button(false))
    assert_eq(tool.call(&"pending_rect"), Rect2i(100, 100, 100, 80), "A drag inside still draws a fresh box")

    tool.handle_input(_key(KEY_ESCAPE))
    assert_eq(tool.call(&"pending_rect"), Rect2i(0, 0, 400, 300), "and Escape puts it back on the canvas")
    Fixtures.teardown(surface, machine)


func test_a_ratio_lock_fits_the_canvas_box_inside_the_canvas_centred() -> void:
    var surface := Fixtures.make_surface(SIZE)
    var machine := Fixtures.make_bound_machine(surface)
    machine.set_active_tool(&"crop")
    var tool := machine.active_tool
    tool.set(&"ratio", 1)
    assert_eq(tool.call(&"pending_rect"), Rect2i(0, 0, 400, 300), "The document's own shape is the whole canvas")
    tool.set(&"ratio", 2)
    assert_eq(tool.call(&"pending_rect"), Rect2i(50, 0, 300, 300), "and a square stands in its middle")
    Fixtures.teardown(surface, machine)


static func _button(pressed: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    return event


static func _key(keycode: Key) -> InputEventKey:
    var event := InputEventKey.new()
    event.keycode = keycode
    event.pressed = true
    return event
