## A Perspective corner drag moves its neighbour the mirror way, and Shift
## moves the one corner.
##
## Stretching the upper part left and right at the same time takes one drag, not
## one per top corner. Shift and a corner drag takes only the one point, and the
## default is both. That is Photoshop's Perspective, where a corner drag moves
## the other end of the edge it is dragged along by the mirror of the drag across
## that edge's middle.
##
## The pictures are taken by the scenario
## `a-perspective-corner-drag-moves-its-neighbour-the-mirror-way-and-shift-moves-the-one-corner`.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true
const Fixtures = preload("res://tests/fixtures.gd")
const BaseModule = preload("res://modules/sara-base-modules/base/module.gd")
const StateTransformScript = preload("res://modules/sara-base-modules/base/transform/state_transform.gd")

## The selection every drag is made over: corners (400, 384), (900, 384),
## (900, 784) and (400, 784), clockwise from the top left as `pending_quad`
## lists them.
const BOX := Rect2i(400, 384, 500, 400)
const CORNERS: Array[Vector2] = [Vector2(400, 384), Vector2(900, 384), Vector2(900, 784), Vector2(400, 784)]

## How far every drag here goes, fifty pixels.
const BY := 50.0

## How far a corner may stand from where the suite says, in document pixels.
const NEAR := 0.01


## A tool that answers one tooltip wherever the pointer is, for the machine's
## half of the road.
class SaysTool:
    extends ToolState

    func tooltip() -> String:
        return "A corner moves its neighbour."


func _button(pressed: bool, shift: bool = false) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    event.shift_pressed = shift
    return event


func _tool() -> Array:
    var surface := Fixtures.make_surface(Vector2i(1280, 1280))
    var machine := Fixtures.make_bound_machine(surface)
    var document := surface.get_document()
    document.active_layer.get_or_create_chunk(Vector2i(1, 1))
    document.selection.select_rect(BOX)
    machine.set_active_tool(&"transform")
    var tool: StateTransformScript = machine.active_tool
    tool.transform_mode = StateTransformScript.Mode.PERSPECTIVE
    return [surface, machine, tool]


## A press at *from*, Shift on it when *shift*, and a motion to *to*, left held
## so the quad read after it is the drag's own.
func _drag(parts: Array, from: Vector2, to: Vector2, shift: bool = false) -> PackedVector2Array:
    var surface: SaSurface = parts[0]
    var tool: StateTransformScript = parts[2]
    surface.view.mouse_position = from
    tool.handle_input(_button(true, shift))
    surface.view.mouse_position = to
    tool.handle_input(InputEventMouseMotion.new())
    return tool.pending_quad()


func _release(parts: Array) -> void:
    (parts[2] as StateTransformScript).handle_input(_button(false))


## Each corner of *got* against *wanted*, by index, to [constant NEAR].
func _assert_quad(got: PackedVector2Array, wanted: Array, what: String) -> void:
    assert_eq(got.size(), 4, "%s: a quad" % what)
    if got.size() != 4:
        return
    for index in 4:
        assert_almost_eq(
            (got[index] - (wanted[index] as Vector2)).length(), 0.0, NEAR, "%s: corner %d at %s" % [what, index, got[index]]
        )


# --- The two drags -------------------------------------------------------------


## The top left corner dragged 50 left takes the top right 50 right, so the top
## widens on both sides at once, and the bottom corners stay.
func test_the_top_left_dragged_left_widens_the_top_both_ways() -> void:
    var parts := _tool()
    var quad := _drag(parts, CORNERS[0], CORNERS[0] + Vector2(-BY, 0))
    _assert_quad(quad, [Vector2(350, 384), Vector2(950, 384), CORNERS[2], CORNERS[3]], "Left")
    assert_false((parts[2] as StateTransformScript).preview_shape().has("ants"), "and the map is a homography")
    Fixtures.teardown(parts[0], parts[1])


## The top left corner dragged 50 up takes the bottom left 50 down, so the left
## side stretches both ways, and the right corners stay.
func test_the_top_left_dragged_up_stretches_the_left_side_both_ways() -> void:
    var parts := _tool()
    var quad := _drag(parts, CORNERS[0], CORNERS[0] + Vector2(0, -BY))
    _assert_quad(quad, [Vector2(400, 334), CORNERS[1], CORNERS[2], Vector2(400, 834)], "Up")
    Fixtures.teardown(parts[0], parts[1])


## Shift held on the press moves the one corner, both ways, which is how a
## Perspective corner moved before the mirror way.
func test_shift_moves_the_one_corner() -> void:
    for by: Vector2 in [Vector2(-BY, 0), Vector2(0, -BY)]:
        var parts := _tool()
        var quad := _drag(parts, CORNERS[0], CORNERS[0] + by, true)
        _assert_quad(quad, [CORNERS[0] + by, CORNERS[1], CORNERS[2], CORNERS[3]], "Shift %s" % by)
        Fixtures.teardown(parts[0], parts[1])


# --- Every corner, every axis -----------------------------------------------------------


## Each of the four corners dragged 50 along each axis, outwards and inwards:
## the corner is on the pointer, the neighbour along the drag's axis moves by
## the drag turned round, and the other two stay. Sixteen drags.
func test_every_corner_takes_the_neighbour_along_its_drag() -> void:
    for index in 4:
        # Clockwise, so the top left's and the bottom right's horizontal
        # neighbour is the next corner and the other two's is the one before.
        var horizontal := (index + 1) % 4 if index % 2 == 0 else (index + 3) % 4
        var vertical := (index + 3) % 4 if index % 2 == 0 else (index + 1) % 4
        for by: Vector2 in [Vector2(BY, 0), Vector2(-BY, 0), Vector2(0, BY), Vector2(0, -BY)]:
            var partner := horizontal if by.y == 0.0 else vertical
            var wanted: Array = CORNERS.duplicate()
            wanted[index] = CORNERS[index] + by
            wanted[partner] = CORNERS[partner] + (Vector2(-by.x, 0) if by.y == 0.0 else Vector2(0, -by.y))
            var parts := _tool()
            _assert_quad(_drag(parts, CORNERS[index], CORNERS[index] + by), wanted, "Corner %d by %s" % [index, by])
            Fixtures.teardown(parts[0], parts[1])


## A drag that slants keeps its part across the edge and turns its part along
## the edge round: the top left by (-50, -10) takes the top right by (50, -10),
## so the top's middle moves straight up and the top stays level.
func test_a_slanting_drag_mirrors_along_the_edge_and_keeps_across_it() -> void:
    var parts := _tool()
    var quad := _drag(parts, CORNERS[0], CORNERS[0] + Vector2(-BY, -10))
    _assert_quad(quad, [Vector2(350, 374), Vector2(950, 374), CORNERS[2], CORNERS[3]], "Slant")
    if quad.size() == 4:
        assert_almost_eq(((quad[0] + quad[1]) * 0.5 - Vector2(650, 374)).length(), 0.0, NEAR, "The top's middle went up")
    # Steeper than the diagonal, so the left side is the edge it runs along.
    var steep := _tool()
    _assert_quad(
        _drag(steep, CORNERS[0], CORNERS[0] + Vector2(-10, -BY)),
        [Vector2(390, 334), CORNERS[1], CORNERS[2], Vector2(390, 834)],
        "Steep"
    )
    Fixtures.teardown(parts[0], parts[1])
    Fixtures.teardown(steep[0], steep[1])


## A drag that crosses its own diagonal swaps the neighbour, since every motion
## is read from the press: the far end of the first edge goes back.
func test_the_neighbour_is_read_again_on_every_motion() -> void:
    var parts := _tool()
    var surface: SaSurface = parts[0]
    var tool: StateTransformScript = parts[2]
    _drag(parts, CORNERS[0], CORNERS[0] + Vector2(-BY, 0))
    surface.view.mouse_position = CORNERS[0] + Vector2(0, -BY)
    tool.handle_input(InputEventMouseMotion.new())
    _assert_quad(tool.pending_quad(), [Vector2(400, 334), CORNERS[1], CORNERS[2], Vector2(400, 834)], "Turned up")
    Fixtures.teardown(parts[0], parts[1])


## The axis is the box's own, read off the quad as it stood at the press. With
## the box turned a quarter, its top edge runs down the screen, and the top
## left dragged up the screen, out along that edge, takes the top right down.
func test_the_edge_is_the_quads_own_in_a_turned_box() -> void:
    var parts := _tool()
    var tool: StateTransformScript = parts[2]
    tool.transform_mode = StateTransformScript.Mode.NORMAL
    tool.angle_degrees = 90.0
    tool.transform_mode = StateTransformScript.Mode.PERSPECTIVE
    var turned: PackedVector2Array = tool.pending_quad()
    _assert_quad(turned, [Vector2(850, 334), Vector2(850, 834), Vector2(450, 834), Vector2(450, 334)], "Turned")
    var quad := _drag(parts, turned[0], turned[0] + Vector2(0, -BY))
    _assert_quad(quad, [Vector2(850, 284), Vector2(850, 884), turned[2], turned[3]], "Along the turned top")
    Fixtures.teardown(parts[0], parts[1])


## Corners a Shift drag placed stay placed: the next corner drag moves from
## where the four stand, and its neighbour is mirrored along the edge as it
## stands, which is no longer level.
func test_a_placed_quad_mirrors_along_its_edge_as_it_stands() -> void:
    var parts := _tool()
    _drag(parts, CORNERS[1], CORNERS[1] + Vector2(0, -BY), true)
    _release(parts)
    var placed: PackedVector2Array = (parts[2] as StateTransformScript).pending_quad()
    _assert_quad(placed, [CORNERS[0], Vector2(900, 334), CORNERS[2], CORNERS[3]], "Placed")
    var edge := (placed[1] - placed[0]).normalized()
    var quad := _drag(parts, placed[0], placed[0] - edge * BY)
    _assert_quad(quad, [placed[0] - edge * BY, placed[1] + edge * BY, CORNERS[2], CORNERS[3]], "Along the leaning top")
    Fixtures.teardown(parts[0], parts[1])


# --- What is left as it was ----------------------------------------------------------------


## An edge handle under Perspective moves its edge and nothing else, with or
## without Shift.
func test_an_edge_handle_still_moves_its_edge() -> void:
    for shift: bool in [false, true]:
        var parts := _tool()
        var quad := _drag(parts, Vector2(650, 384), Vector2(650, 334), shift)
        _assert_quad(quad, [Vector2(400, 334), Vector2(900, 334), CORNERS[2], CORNERS[3]], "Top edge, Shift %s" % shift)
        Fixtures.teardown(parts[0], parts[1])


## Mirrored moves the corner across the centre, with or without Shift, since
## the mirror way is Perspective's alone.
func test_mirrored_still_moves_the_opposite_corner() -> void:
    for shift: bool in [false, true]:
        var parts := _tool()
        (parts[2] as StateTransformScript).transform_mode = StateTransformScript.Mode.MIRRORED
        var quad := _drag(parts, CORNERS[0], CORNERS[0] + Vector2(-BY, 0), shift)
        _assert_quad(quad, [Vector2(350, 384), CORNERS[1], Vector2(950, 784), CORNERS[3]], "Mirrored, Shift %s" % shift)
        Fixtures.teardown(parts[0], parts[1])


## Normal still scales from a corner, Shift or not, so the pair is Perspective's.
func test_normal_still_scales_from_a_corner() -> void:
    var parts := _tool()
    (parts[2] as StateTransformScript).transform_mode = StateTransformScript.Mode.NORMAL
    var quad := _drag(parts, CORNERS[0], CORNERS[0] + Vector2(-BY, 0))
    _assert_quad(quad, [Vector2(350, 384), Vector2(900, 384), CORNERS[2], Vector2(350, 784)], "Normal")
    Fixtures.teardown(parts[0], parts[1])


# --- What the strip and the row say ----------------------------------------------------------


## The strip's Perspective cell says, under the pointer, that a corner moves its
## neighbour and Shift moves the one corner. Every cell says something of its
## own, the space beside the strip says nothing, and neither does a drag.
func test_the_strips_perspective_cell_says_what_a_corner_does() -> void:
    var parts := _tool()
    var surface: SaSurface = parts[0]
    var tool: StateTransformScript = parts[2]
    var cells := SaTransformModeStrip.boxes(tool.pending_quad(), 1.0)
    assert_eq(cells.size(), StateTransformScript.Mode.size(), "One cell per mode")
    var said := {}
    for index in cells.size():
        surface.view.mouse_position = cells[index].get_center()
        var tip: String = tool.tooltip()
        assert_false(tip.is_empty(), "Cell %d says something" % index)
        said[tip] = true
    assert_eq(said.size(), cells.size(), "and no two cells say the same")
    surface.view.mouse_position = cells[StateTransformScript.Mode.PERSPECTIVE].get_center()
    var perspective: String = tool.tooltip()
    assert_true(perspective.begins_with("Perspective."), "The second cell is Perspective's: %s" % perspective)
    assert_true(perspective.contains("A corner moves its neighbour too"), "and says a corner moves its neighbour")
    assert_true(perspective.contains("Shift and a corner moves the one corner"), "and that Shift moves one corner")
    surface.view.mouse_position = cells[cells.size() - 1].end + Vector2(40, 0)
    assert_eq(tool.tooltip(), "", "Beside the strip there is nothing to say")
    _drag(parts, CORNERS[0], CORNERS[0] + Vector2(-BY, 0))
    surface.view.mouse_position = cells[StateTransformScript.Mode.PERSPECTIVE].get_center()
    assert_eq(tool.tooltip(), "", "and nothing while a drag is under way")
    Fixtures.teardown(parts[0], parts[1])


## The Mode row's tooltip says the same two things, and no longer says Shift
## shears from an edge in any mode, which was never true of Perspective.
func test_the_mode_rows_tooltip_says_what_a_corner_does() -> void:
    var tip := ""
    for spec: SaOptionSpec in BaseModule.transform_options():
        if spec.key == &"transform_mode":
            tip = spec.tooltip
    assert_true(tip.contains("Perspective moves a corner and its neighbour the mirror way"), "The row says the pair: %s" % tip)
    assert_true(tip.contains("Shift and a corner moving the one corner"), "and that Shift moves the one")
    assert_false(tip.contains("in any mode"), "and Shift's shear is not promised everywhere")


## The machine writes what the active tool says onto the canvas, where the
## engine shows a tooltip from, and writes nothing while a holder owns the
## pointer.
func test_the_machine_writes_the_tools_tooltip_on_the_canvas() -> void:
    var surface := Fixtures.make_surface(Vector2i(256, 256))
    var machine := Fixtures.make_bound_machine(surface)
    var fake: SaView = surface.view
    var canvas := SaCanvas.new()
    surface.view = canvas.view()
    var tool := SaysTool.new()
    var was: ToolState = machine.active_tool
    machine.active_tool = tool
    machine._show_tooltip()
    assert_eq(canvas.tooltip_text, tool.tooltip(), "The canvas carries the tool's tooltip")
    machine.pointer_holder = &"suite"
    machine._show_tooltip()
    assert_eq(canvas.tooltip_text, "", "and none while a holder owns the pointer")
    machine.pointer_holder = &""
    machine.active_tool = was
    surface.view = fake
    canvas.free()
    Fixtures.teardown(surface, machine)
