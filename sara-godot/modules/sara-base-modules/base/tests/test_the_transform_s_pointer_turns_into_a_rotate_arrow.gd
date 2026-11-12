## The Transform's pointer turns into a rotate arrow where a press would rotate.
##
## The descriptor's move shape does not stand everywhere, inside the box, on a
## handle and in the rotation's reach just
## outside a corner. The tool asks for a picture of its own by position,
## the curved arrow, wherever a press would turn the box and all through a turn
## being dragged, and the move shape is back as soon as the pointer leaves.
##
## The OS pointer is drawn by the compositor and no capture holds it, so every
## claim here is what the tool asks for, what the machine publishes and what the
## cursor policy puts in the slot. The scenario named after this suite,
## `the-transform-s-pointer-turns-into-a-rotate-arrow-where-a-press-would-rotate`,
## reads the same slot off the running app's state dump.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true
const Fixtures = preload("res://tests/fixtures.gd")
const StateTransformScript = preload("res://modules/sara-base-modules/base/transform/state_transform.gd")

## The selection the box stands on, so a drag lifts it.
const BOX := Rect2i(400, 384, 320, 256)

## The box's bottom right and top left corners, in document pixels.
const CORNER := Vector2(720, 640)
const TOP_LEFT := Vector2(400, 384)

var _surface: SaSurface = null
var _machine: ToolMachine = null
var _tool: StateTransformScript = null


func before_each() -> void:
    _surface = Fixtures.make_surface(Vector2i(1024, 1024))
    _machine = Fixtures.make_bound_machine(_surface)
    var document := _surface.get_document()
    document.active_layer.get_or_create_chunk(Vector2i(1, 1))
    document.selection.select_rect(BOX)
    _machine.set_active_tool(&"transform")
    _tool = _machine.active_tool as StateTransformScript


func after_each() -> void:
    # Or a run leaves the desktop's own pointer replaced, which outlives Godot.
    SaCursorPolicy.clear_tool_cursor()
    Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null
    _tool = null


static func _button(pressed: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    return event


## The pointer taken to *at*, a motion handed to the tool, and a frame of the
## machine, which is where it publishes what the tool asks for.
func _hover(at: Vector2) -> void:
    _surface.view.mouse_position = at
    _tool.handle_input(InputEventMouseMotion.new())
    _machine._process(0.0)


## The name of the picture the machine published last, empty for none.
func _published() -> String:
    var shown: SaCursorPicture = _machine._cursor_picture_shown
    return String(shown.name) if shown != null else ""


## The note's walk: inside the box, just outside a corner, further out. The
## move shape, the arrow, the move shape, with the shape under the arrow kept
## as the move shape so the slot it stands in is the descriptor's own.
func test_the_arrow_stands_by_a_corner_and_nowhere_else() -> void:
    _hover(Vector2(BOX.get_center()))
    assert_null(_tool.cursor_picture(), "Inside the box a press moves, so the tool asks for no picture")
    assert_eq(_published(), "", "and the machine publishes none")
    assert_eq(_machine._cursor_shape_shown, Control.CURSOR_MOVE, "leaving the descriptor's move shape")

    _hover(CORNER + Vector2(14.0, 14.0))
    var picture := _tool.cursor_picture()
    assert_not_null(picture, "Just outside a corner a press turns the box, so the tool asks for its picture")
    assert_eq(String(picture.name), "rotate", "the rotate arrow")
    assert_not_null(picture.texture, "drawn from the theme's icons")
    assert_eq(picture.hotspot, Vector2(0.5, 0.5), "with its point at its centre, since a turn has no tip")
    assert_false(picture.held, "and standing over the canvas alone, since nothing is held yet")
    assert_eq(_published(), "rotate", "The machine publishes the arrow with no tool switch")
    assert_eq(_machine._cursor_shape_shown, Control.CURSOR_MOVE, "standing in the move shape's slot")

    _hover(CORNER + Vector2(40.0, 40.0))
    assert_null(_tool.cursor_picture(), "Beyond the reach a press does nothing, and the arrow goes")
    assert_eq(_published(), "", "the move shape back as soon as the pointer leaves")


## Every place a press grabs rather than turns keeps the move shape, though it
## is within the rotation's reach: a corner handle, the mode strip above the
## top left corner, and the box's own inside. Just left of that corner, clear of
## the strip and the handle, is the arrow again.
func test_a_handle_and_the_mode_strip_keep_the_move_shape() -> void:
    _hover(CORNER + Vector2(4.0, 4.0))
    assert_null(_tool.cursor_picture(), "On the corner handle a press scales, so no arrow")
    var on_strip := TOP_LEFT + Vector2(5.0, -19.0)
    _hover(on_strip)
    assert_true(TOP_LEFT.distance_to(on_strip) < StateTransformScript.ROTATE_REACH, "This point is in the reach")
    assert_null(_tool.cursor_picture(), "and on the strip's first cell, where a press picks a mode, so no arrow")
    _hover(CORNER - Vector2(14.0, 14.0))
    assert_null(_tool.cursor_picture(), "Inside the corner a press moves, so no arrow")
    _hover(TOP_LEFT + Vector2(-12.0, -4.0))
    assert_eq(_published(), "rotate", "Just left of the top left corner, clear of the strip, the arrow")


## The reach is in screen pixels, the press's own measure, so at twice the zoom
## the arrow's ground is half as many document pixels wide.
func test_the_reach_follows_the_zoom() -> void:
    _surface.view.set_zoom(2.0)
    _hover(CORNER + Vector2(14.0, 14.0))
    assert_null(_tool.cursor_picture(), "At 200% a point 20 document pixels off the corner is 40 screen pixels off it")
    _hover(CORNER + Vector2(7.0, 7.0))
    assert_not_null(_tool.cursor_picture(), "and one 10 document pixels off it is in the reach again")


## With a rotation held the arrow stays wherever the pointer goes, over the
## box, over a handle and far outside, and the release hands the question back
## to where the pointer is.
func test_a_held_rotation_keeps_the_arrow_all_the_way() -> void:
    _hover(CORNER + Vector2(14.0, 14.0))
    _tool.handle_input(_button(true))
    assert_eq(_tool._gesture, StateTransformScript.Gesture.ROTATE, "The press there turns the box")
    for at: Vector2 in [Vector2(BOX.get_center()), CORNER, Vector2(900.0, 900.0), TOP_LEFT + Vector2(5.0, -19.0)]:
        _hover(at)
        assert_eq(_published(), "rotate", "Held, the arrow stays at %s" % at)
        assert_true(_machine._cursor_picture_shown.held, "as the held turn's, which stays over a docker too")
    assert_true(_tool.is_moving(), "and the drag did turn the picture")
    _hover(Vector2(900.0, 900.0))
    _tool.handle_input(_button(false))
    _machine._process(0.0)
    assert_eq(_published(), "", "Let go far outside, the move shape is back")


## A held move is not a turn, so the arrow does not come up when its drag
## crosses the rotation's reach.
func test_a_held_move_never_shows_the_arrow() -> void:
    _hover(Vector2(BOX.get_center()))
    _tool.handle_input(_button(true))
    _hover(Vector2(BOX.get_center()) + Vector2(4.0, 4.0))
    _hover(CORNER + Vector2(14.0, 14.0))
    assert_eq(_published(), "", "A move dragged into a corner's reach keeps the move shape")
    _tool.handle_input(_button(false))


## The reading and the press cannot drift apart: across the ground round two
## corners, in every mode, the arrow stands at exactly the points a press
## there turns the box.
func test_the_arrow_stands_exactly_where_a_press_turns() -> void:
    for mode in StateTransformScript.Mode.size():
        var disagreed: Array[Vector2] = []
        var turned := 0
        for corner: Vector2 in [CORNER, TOP_LEFT]:
            for dx in range(-40, 41, 4):
                for dy in range(-40, 41, 4):
                    _tool.transform_mode = mode
                    var at := corner + Vector2(dx, dy)
                    _surface.view.mouse_position = at
                    var arrow := _tool.cursor_picture() != null
                    _tool.handle_input(_button(true))
                    var turns: bool = _tool._gesture == StateTransformScript.Gesture.ROTATE
                    _tool.handle_input(_button(false))
                    turned += 1 if turns else 0
                    if arrow != turns:
                        disagreed.append(at)
        # Cage turns nothing: its presses place, close and grab the cage.
        var caged := mode == StateTransformScript.Mode.CAGE
        assert_true(turned > 0 or caged, "Mode %d has ground a press turns from" % mode)
        assert_true(disagreed.is_empty(), "and in mode %d the arrow and the press agree everywhere: %s" % [mode, disagreed])


## The policy puts the tool's picture in the slot of the shape the tool asked
## for, under the tool's name with the picture named beside it, which is what
## the canvas block of a state dump reads, and gives the slot back when the
## pointer leaves the reach.
func test_the_policy_holds_the_arrow_in_the_move_slot() -> void:
    var descriptor := _machine.get_descriptor(&"transform")
    _surface.view.mouse_position = CORNER + Vector2(14.0, 14.0)
    SaCursorPolicy.apply_tool_cursor(null, descriptor, Control.CURSOR_MOVE, _tool.cursor_picture())
    var held := SaCursorPolicy.tool_cursor_state()
    assert_true(held["custom"], "The arrow takes a slot")
    assert_eq(held["tool"], "transform", "under the Transform's name")
    assert_eq(held["picture"], "rotate", "naming the arrow")
    assert_eq(held["shape"], Control.CURSOR_MOVE, "in the move shape's slot")

    _surface.view.mouse_position = Vector2(BOX.get_center())
    SaCursorPolicy.apply_tool_cursor(null, descriptor, Control.CURSOR_MOVE, _tool.cursor_picture())
    var freed := SaCursorPolicy.tool_cursor_state()
    assert_false(freed["custom"], "Inside the box the slot is given back")
    assert_eq(freed["picture"], "", "and no picture is named")
    assert_eq(freed["shape"], -1, "so the stock move shape shows")
