## The transform tool's box, as arithmetic.
##
## No pixel moves here, so everything provable about the tool is the rectangle
## it would act on and when that rectangle is there at all. The four claims:
## the box is round the layer's paint when nothing is selected, the selection's
## bounds when something is, an unpainted layer offers no box, and Escape drops
## the box without changing what a transform would take. The chunks here are
## painted whole, because the box has been round the paint and not round the
## chunks, and another suite holds the tight box.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true
const Fixtures = preload("res://tests/fixtures.gd")
const OPAQUE := Color(0.5, 0.4, 0.3, 1.0)


func test_the_box_is_the_painted_chunks_when_nothing_is_selected() -> void:
    var surface := Fixtures.make_surface(Vector2i(1024, 1024))
    var machine := Fixtures.make_bound_machine(surface)
    machine.set_active_tool(&"transform")
    var tool := machine.active_tool

    var layer := surface.get_document().active_layer
    layer.get_or_create_chunk(Vector2i(1, 1)).clear(OPAQUE)
    layer.get_or_create_chunk(Vector2i(2, 1)).clear(OPAQUE)

    assert_eq(tool.pending_box(), Rect2i(256, 256, 512, 256), "Two chunks painted whole side by side give the box their union")
    Fixtures.teardown(surface, machine)


func test_a_selection_wins_over_the_layer() -> void:
    var surface := Fixtures.make_surface(Vector2i(1024, 1024))
    var machine := Fixtures.make_bound_machine(surface)
    machine.set_active_tool(&"transform")
    var tool := machine.active_tool

    var document := surface.get_document()
    document.active_layer.get_or_create_chunk(Vector2i(3, 3)).clear(OPAQUE)
    document.selection.select_rect(Rect2i(100, 120, 200, 40))

    assert_eq(tool.pending_box(), Rect2i(100, 120, 200, 40), "The selection's own bounds, not the chunks it happens to touch")
    document.selection.deselect()
    assert_eq(tool.pending_box(), Rect2i(768, 768, 256, 256), "and dropping the selection hands the box back to the layer")
    Fixtures.teardown(surface, machine)


func test_an_unpainted_layer_offers_no_box() -> void:
    var surface := Fixtures.make_surface(Vector2i(512, 512))
    var machine := Fixtures.make_bound_machine(surface)
    machine.set_active_tool(&"transform")
    var tool := machine.active_tool

    assert_eq(tool.pending_box(), Rect2i(), "Nothing painted is nothing to transform")
    assert_true(tool.preview_shape().is_empty(), "so the overlay is asked to draw nothing")
    Fixtures.teardown(surface, machine)


func test_escape_drops_the_box_and_leaving_the_tool_brings_it_back() -> void:
    var surface := Fixtures.make_surface(Vector2i(1024, 1024))
    var machine := Fixtures.make_bound_machine(surface)
    machine.set_active_tool(&"transform")
    var tool := machine.active_tool
    surface.get_document().active_layer.get_or_create_chunk(Vector2i(0, 0)).clear(OPAQUE)

    var shape: Dictionary = tool.preview_shape()
    assert_eq(shape.get("rect", Rect2()), Rect2(0, 0, 256, 256), "The overlay is handed the box")
    assert_true(bool(shape.get("handles", false)), "with the crop's own handles flag")
    assert_false(shape.has("dim"), "and without the crop's dim, which would say the outside is going away")

    var escape := InputEventKey.new()
    escape.keycode = KEY_ESCAPE
    escape.pressed = true
    tool.handle_input(escape)

    assert_eq(tool.pending_box(), Rect2i(), "Escape drops the box")
    assert_eq(tool.target_box(), Rect2i(0, 0, 256, 256), "without changing what a transform would take")
    tool.reset()
    assert_eq(tool.pending_box(), Rect2i(0, 0, 256, 256), "and leaving the tool puts the box back")
    Fixtures.teardown(surface, machine)


## Enter after a move commits it and hands the machine back to the tool the
## painter came from Ctrl+T from the brush, a drag, Enter,
## and the brush is back with the move written down as one step. Enter with
## nothing lifted commits nothing and stays, so a stray Enter does not throw
## the painter out of a tool they only just picked.
func test_enter_after_a_move_commits_and_hands_back() -> void:
    var surface := Fixtures.make_surface(Vector2i(1024, 1024))
    var machine := Fixtures.make_bound_machine(surface)
    machine.set_active_tool(&"brush")
    machine.set_active_tool(&"transform")
    var tool := machine.active_tool
    var document := surface.get_document()
    document.active_layer.get_or_create_chunk(Vector2i(0, 0)).clear(OPAQUE)
    var enter := InputEventKey.new()
    enter.keycode = KEY_ENTER
    enter.pressed = true

    tool.handle_input(enter)
    assert_eq(machine.active_tool_name, &"transform", "Enter with nothing lifted stays")

    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    surface.view.mouse_position = surface.view.document_to_screen(Vector2(100.0, 100.0))
    tool.handle_input(press)
    surface.view.mouse_position = surface.view.document_to_screen(Vector2(200.0, 100.0))
    tool.handle_input(InputEventMouseMotion.new())
    assert_true(tool.is_moving(), "the drag lifted the box")
    var steps := document.history.step_count()

    tool.handle_input(enter)
    assert_eq(document.history.step_count(), steps + 1, "Enter wrote the move down as one step")
    assert_false(tool.is_moving(), "and nothing is in the air")
    assert_eq(machine.active_tool_name, &"brush", "and the brush is back")
    Fixtures.teardown(surface, machine)
