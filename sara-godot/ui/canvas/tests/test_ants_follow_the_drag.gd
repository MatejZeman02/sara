## The marching ants follow the moved region.
##
## After Enter the selection is where the pixels are. During the drag the outline
## must follow them too, or a painter drags a piece out of a box that stays
## behind. `ui/canvas/selection_overlay.gd` drew the mask chunks at their stored
## positions and knew nothing of the pending transform.
##
## What is asserted here is the map the overlay is handed, because the drawing
## itself is a shader over a texture per chunk and the proof of it is the
## picture: `scenarios/transform.json` shot `04-moving`. The outline's own
## bounding box in that shot is (600, 484) to (1100, 884), the selection's
## original box (400, 384) to (900, 784) moved by the 200 by 100 the drag asked
## for.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true
const Fixtures = preload("res://tests/fixtures.gd")


func _button(pressed: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    return event


## A transform tool with a selection, lifted and dragged by 200 by 100, which is
## `scenarios/transform.json`'s own gesture.
func _dragged() -> Array:
    var surface := Fixtures.make_surface(Vector2i(1024, 1024))
    var machine := Fixtures.make_bound_machine(surface)
    var document := surface.get_document()
    document.active_layer.get_or_create_chunk(Vector2i(1, 1))
    document.selection.select_rect(Rect2i(400, 384, 500, 400))
    machine.set_active_tool(&"transform")
    var tool: Variant = machine.active_tool
    return [surface, machine, tool]


## Nothing in the air, nothing for the overlay to transform by. The absence is
## the signal: it is what tells the overlay to draw the mask where it is stored,
## which is right everywhere except during a drag.
func test_a_box_that_is_not_moving_hands_the_overlay_no_map() -> void:
    var parts := _dragged()
    var tool: Variant = parts[2]
    var shape: Dictionary = tool.preview_shape()
    assert_true(shape.has("rect"), "A box that is only sitting there is a rectangle")
    assert_false(shape.has("ants"), "and carries no map")
    Fixtures.teardown(parts[0], parts[1])


## The drag, and the map is the one the lifted picture is previewed through
## rather than a second reading of the same gesture.
func test_a_drag_hands_the_overlay_the_map_the_picture_moves_by() -> void:
    var parts := _dragged()
    var surface: SaSurface = parts[0]
    var tool: Variant = parts[2]
    surface.view.mouse_position = Vector2(650, 584)
    tool.handle_input(_button(true))
    surface.view.mouse_position = Vector2(850, 684)
    tool.handle_input(InputEventMouseMotion.new())

    var shape: Dictionary = tool.preview_shape()
    assert_true(shape.has("quad"), "A moving box is a quad")
    assert_true(shape.has("ants"), "and carries the map the outline is drawn through")
    var ants: Transform2D = shape["ants"]
    assert_eq(ants, tool.matrix, "which is the picture's own map and not a copy of it")
    assert_almost_eq(ants.origin.x, 200.0, 1.0, "The drag moved it 200 across, %.1f" % ants.origin.x)
    assert_almost_eq(ants.origin.y, 100.0, 1.0, "and 100 down, %.1f" % ants.origin.y)
    Fixtures.teardown(parts[0], parts[1])


## The map takes the outline exactly where it takes the quad, which is the
## clause: the outline and the preview agree at every frame.
func test_the_map_takes_the_outline_where_it_takes_the_box() -> void:
    var parts := _dragged()
    var surface: SaSurface = parts[0]
    var tool: Variant = parts[2]
    surface.view.mouse_position = Vector2(650, 584)
    tool.handle_input(_button(true))
    surface.view.mouse_position = Vector2(850, 684)
    tool.handle_input(InputEventMouseMotion.new())

    var shape: Dictionary = tool.preview_shape()
    var ants: Transform2D = shape["ants"]
    var quad: PackedVector2Array = shape["quad"]
    var corner := Vector2(400, 384)
    assert_almost_eq((ants * corner - quad[0]).length(), 0.0, 1.0, "The selection's own corner lands on the quad's")
    Fixtures.teardown(parts[0], parts[1])


## Escape puts the picture back and the map goes with it, so the outline returns
## to the mask rather than staying where the drag left it.
func test_escape_takes_the_map_away_again() -> void:
    var parts := _dragged()
    var surface: SaSurface = parts[0]
    var tool: Variant = parts[2]
    surface.view.mouse_position = Vector2(650, 584)
    tool.handle_input(_button(true))
    surface.view.mouse_position = Vector2(850, 684)
    tool.handle_input(InputEventMouseMotion.new())
    tool.handle_input(_button(false))
    assert_true(tool.preview_shape().has("ants"), "A released drag is still in the air")

    var escape := InputEventKey.new()
    escape.keycode = KEY_ESCAPE
    escape.pressed = true
    tool.handle_input(escape)

    assert_false(tool.preview_shape().has("ants"), "and Escape puts it down")
    Fixtures.teardown(parts[0], parts[1])
