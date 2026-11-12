## A Perspective side handle dragged along its side skews the opposite side the
## other way, and dragged across moves its side alone.
##
## The perspective transform's middle handles move the selected side freely. In
## the case of the top side, sideways skews the sides (the bottom in the
## opposite direction) and upward moves the side alone, not the opposite one.
## The drag is read along the side, as its two corners stood at the press, and
## across it: the side moves by the whole drag and the opposite side by the
## part along, turned round.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true
const Fixtures = preload("res://tests/fixtures.gd")
const StateTransformScript = preload("res://modules/sara-base-modules/base/transform/state_transform.gd")

## The box, 200 by 100: corners (400, 384), (600, 384), (600, 484) and
## (400, 484), clockwise from the top left as `pending_quad` lists them.
const BOX := Rect2i(400, 384, 200, 100)
const CORNERS: Array[Vector2] = [Vector2(400, 384), Vector2(600, 384), Vector2(600, 484), Vector2(400, 484)]

## The four side handles by the box's own direction, with the middle each sits
## at and the corners of its side and of the opposite one, in quad order.
const SIDES: Array[Dictionary] = [
    {"name": "top", "at": Vector2(500, 384), "own": [0, 1], "far": [2, 3]},
    {"name": "right", "at": Vector2(600, 434), "own": [1, 2], "far": [3, 0]},
    {"name": "bottom", "at": Vector2(500, 484), "own": [2, 3], "far": [0, 1]},
    {"name": "left", "at": Vector2(400, 434), "own": [3, 0], "far": [1, 2]},
]

## How far a corner may stand from where the suite says, in document pixels.
const NEAR := 0.01


func _button(pressed: bool, shift: bool = false) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    event.shift_pressed = shift
    return event


func _tool(which: int = StateTransformScript.Mode.PERSPECTIVE) -> Array:
    var surface := Fixtures.make_surface(Vector2i(1280, 1280))
    var machine := Fixtures.make_bound_machine(surface)
    var document := surface.get_document()
    document.active_layer.get_or_create_chunk(Vector2i(1, 1))
    document.selection.select_rect(BOX)
    machine.set_active_tool(&"transform")
    var tool: StateTransformScript = machine.active_tool
    tool.transform_mode = which
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


## *from* with the corners of *own* moved by *by* and those of *far* by
## *back*, the quad a side drag is read against.
func _moved(from: Array, own: Array, by: Vector2, far: Array, back: Vector2) -> Array:
    var wanted: Array = from.duplicate()
    for index: int in own:
        wanted[index] = (from[index] as Vector2) + by
    for index: int in far:
        wanted[index] = (from[index] as Vector2) + back
    return wanted


## The box tilted by a corner drag and let go: the top right corner dragged 40
## up, which under Perspective takes the bottom right 40 down and under
## Mirrored the bottom left. The top runs up to the right after either.
func _tilted(parts: Array) -> PackedVector2Array:
    _drag(parts, CORNERS[1], CORNERS[1] + Vector2(0, -40))
    _release(parts)
    return (parts[2] as StateTransformScript).pending_quad()


# --- The drags on the top handle ------------------------------------------------


## The top handle dragged 40 right takes the top 40 right and the bottom 40
## left, a skew about the box's middle, and no corner moves up or down.
func test_the_top_dragged_sideways_skews_the_bottom_the_other_way() -> void:
    var parts := _tool()
    var quad := _drag(parts, SIDES[0].at, SIDES[0].at + Vector2(40, 0))
    _assert_quad(quad, [Vector2(440, 384), Vector2(640, 384), Vector2(560, 484), Vector2(360, 484)], "Sideways")
    assert_false((parts[2] as StateTransformScript).preview_shape().has("ants"), "and the map is a homography")
    Fixtures.teardown(parts[0], parts[1])


## The top handle dragged 30 up takes the top 30 up and leaves the bottom.
func test_the_top_dragged_up_moves_the_top_alone() -> void:
    var parts := _tool()
    var quad := _drag(parts, SIDES[0].at, SIDES[0].at + Vector2(0, -30))
    _assert_quad(quad, [Vector2(400, 354), Vector2(600, 354), CORNERS[2], CORNERS[3]], "Up")
    Fixtures.teardown(parts[0], parts[1])


## A diagonal drag is both at once: the top goes by the whole drag and the
## bottom by its sideways part turned round, and not up.
func test_a_diagonal_drag_is_both_parts_at_once() -> void:
    var parts := _tool()
    var quad := _drag(parts, SIDES[0].at, SIDES[0].at + Vector2(40, -30))
    _assert_quad(quad, [Vector2(440, 354), Vector2(640, 354), Vector2(560, 484), Vector2(360, 484)], "Diagonal")
    Fixtures.teardown(parts[0], parts[1])


## The left handle dragged 30 down takes the right side 30 up.
func test_the_left_dragged_down_takes_the_right_up() -> void:
    var parts := _tool()
    var quad := _drag(parts, SIDES[3].at, SIDES[3].at + Vector2(0, 30))
    _assert_quad(quad, [Vector2(400, 414), Vector2(600, 354), Vector2(600, 454), Vector2(400, 514)], "Left down")
    Fixtures.teardown(parts[0], parts[1])


## Every side, along and across, both ways: the side is on the drag, the
## opposite side goes the other way along and stays across. Sixteen drags.
func test_every_side_skews_along_and_moves_alone_across() -> void:
    for side: Dictionary in SIDES:
        var horizontal: bool = (side.at as Vector2).y == CORNERS[0].y or (side.at as Vector2).y == CORNERS[2].y
        for by: Vector2 in [Vector2(30, 0), Vector2(-30, 0), Vector2(0, 30), Vector2(0, -30)]:
            var along: bool = (by.y == 0.0) == horizontal
            var wanted := _moved(CORNERS, side.own, by, side.far, -by if along else Vector2.ZERO)
            var parts := _tool()
            _assert_quad(_drag(parts, side.at, side.at + by), wanted, "The %s by %s" % [side.name, by])
            Fixtures.teardown(parts[0], parts[1])


# --- A tilted box ----------------------------------------------------------------------


## Along is the side as its corners stood at the press. With the top tilted by
## a corner drag, the top handle dragged along the tilted top takes the bottom
## the other way along that same direction, though the bottom leans the other
## way, and dragged across it the bottom stays.
func test_a_tilted_side_skews_along_its_own_direction() -> void:
    var parts := _tool()
    var placed := _tilted(parts)
    var placed_corners: Array = [placed[0], placed[1], placed[2], placed[3]]
    _assert_quad(placed, [CORNERS[0], Vector2(600, 344), Vector2(600, 524), CORNERS[3]], "Tilted")
    var handle: Vector2 = placed[0].lerp(placed[1], 0.5)
    var along: Vector2 = (placed[1] - placed[0]).normalized() * 30.0
    var quad := _drag(parts, handle, handle + along)
    _assert_quad(quad, _moved(placed_corners, [0, 1], along, [2, 3], -along), "Along the tilted top")
    _release(parts)
    var across := along.orthogonal()
    var lifted: PackedVector2Array = (parts[2] as StateTransformScript).pending_quad()
    var lifted_corners: Array = [lifted[0], lifted[1], lifted[2], lifted[3]]
    handle = lifted[0].lerp(lifted[1], 0.5)
    _assert_quad(_drag(parts, handle, handle + across), _moved(lifted_corners, [0, 1], across, [], Vector2.ZERO), "Across")
    Fixtures.teardown(parts[0], parts[1])


## Shift on a side handle moves its side alone, on the tilted box as on the
## level one, as Shift on a corner moves the one corner.
func test_shift_moves_the_one_side() -> void:
    var level := _tool()
    _assert_quad(
        _drag(level, SIDES[0].at, SIDES[0].at + Vector2(40, -30), true),
        [Vector2(440, 354), Vector2(640, 354), CORNERS[2], CORNERS[3]],
        "Shift on the level top"
    )
    var parts := _tool()
    var placed := _tilted(parts)
    var placed_corners: Array = [placed[0], placed[1], placed[2], placed[3]]
    var handle: Vector2 = placed[0].lerp(placed[1], 0.5)
    var along: Vector2 = (placed[1] - placed[0]).normalized() * 30.0
    _assert_quad(
        _drag(parts, handle, handle + along, true),
        _moved(placed_corners, [0, 1], along, [], Vector2.ZERO),
        "Shift on the tilted top"
    )
    Fixtures.teardown(level[0], level[1])
    Fixtures.teardown(parts[0], parts[1])


# --- What is left as it was ------------------------------------------------------------


## Mirrored keeps its rule, Shift or not and tilted or not: the opposite side
## goes the other way by the whole drag, across as well as along.
func test_mirrored_still_moves_the_opposite_side_by_the_whole_drag() -> void:
    var by := Vector2(20, -30)
    for shift: bool in [false, true]:
        var level := _tool(StateTransformScript.Mode.MIRRORED)
        _assert_quad(
            _drag(level, SIDES[0].at, SIDES[0].at + by, shift),
            _moved(CORNERS, [0, 1], by, [2, 3], -by),
            "Mirrored on the level top, Shift %s" % shift
        )
        Fixtures.teardown(level[0], level[1])
        var parts := _tool(StateTransformScript.Mode.MIRRORED)
        var placed := _tilted(parts)
        var placed_corners: Array = [placed[0], placed[1], placed[2], placed[3]]
        _assert_quad(placed, [CORNERS[0], Vector2(600, 344), CORNERS[2], Vector2(400, 524)], "Mirrored tilt")
        var handle: Vector2 = placed[0].lerp(placed[1], 0.5)
        _assert_quad(
            _drag(parts, handle, handle + by, shift),
            _moved(placed_corners, [0, 1], by, [2, 3], -by),
            "Mirrored on the tilted top, Shift %s" % shift
        )
        Fixtures.teardown(parts[0], parts[1])


# --- What the strip says --------------------------------------------------------------


## The strip's Perspective cell says what a side handle does along and across,
## and what Shift does with one, beside what it says of a corner.
func test_the_strips_perspective_cell_says_what_a_side_does() -> void:
    var parts := _tool()
    var surface: SaSurface = parts[0]
    var tool: StateTransformScript = parts[2]
    var cells := SaTransformModeStrip.boxes(tool.pending_quad(), 1.0)
    surface.view.mouse_position = cells[StateTransformScript.Mode.PERSPECTIVE].get_center()
    var tip: String = tool.tooltip()
    assert_true(tip.begins_with("Perspective."), "The second cell is Perspective's: %s" % tip)
    assert_true(
        tip.contains("A side handle dragged along its side moves the opposite side the other way"), "and says what along does"
    )
    assert_true(tip.contains("dragged across moves its side alone"), "and what across does")
    assert_true(tip.contains("Shift and a side handle moves the one side"), "and what Shift does")
    assert_true(tip.contains("Shift and a corner moves the one corner"), "and still what a corner does")
    assert_false(tip.contains("an edge handle moves its edge"), "and no longer that a side moves alone")
    Fixtures.teardown(parts[0], parts[1])
