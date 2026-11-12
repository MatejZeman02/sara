## Dragging inside a selection moves its outline.
##
## The note, the `sel` sweep's F7: with the Marquee or the Ellipse a painter
## drags a shape, presses inside it and drags, and a new shape replaced the old
## one, the bounds going from 320 by 193 to 161 by 81. The only way to move a
## selection was the Transform tool, which moves the pixels with it. A press
## inside the bounds with neither Shift nor Alt, in Replace mode, now carries
## the outline alone, and every other press starts a shape as it did.
##
## Every mask is read back from VRAM, because a carry through the wrong map
## hands back a plausible bounds over a mask that never moved.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const MarqueeScript = preload("res://modules/sara-base-modules/base/tools/state_marquee.gd")

const ORANGE := Color(1.0, 0.5, 0.0, 1.0)

## The note's first shape, 320 by 193.
const NOTE_RECT := Rect2i(60, 50, 320, 193)

var _surface: SaSurface = null
var _machine: ToolMachine = null
var _doc: SaDocument = null
var _feather_was: float = 0.0


## Four by four chunks, so a move can cross a seam and leave a chunk behind.
func before_each() -> void:
    _surface = Fixtures.make_surface(Vector2i(1024, 1024))
    _machine = Fixtures.make_bound_machine(_surface)
    _doc = _surface.get_document()
    _feather_was = SaSettings.selection_feather
    SaSettings.selection_feather = 0.0


func after_each() -> void:
    SaSettings.selection_feather = _feather_was
    Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null
    _doc = null


func _steps() -> int:
    return _doc.undo_redo.get_history_count()


static func _button(pressed: bool, shift: bool = false, alt: bool = false) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    event.shift_pressed = shift
    event.alt_pressed = alt
    return event


## *tool* made active and pressed at *from*, with Shift or Alt as given.
func _press(tool: StringName, from: Vector2, shift: bool = false, alt: bool = false) -> ToolState:
    _machine.set_active_tool(tool)
    var state := _machine.active_tool
    _surface.view.mouse_position = from
    state.handle_input(_button(true, shift, alt))
    return state


## The pointer taken to *to* with the button still down.
func _move(state: ToolState, to: Vector2) -> void:
    _surface.view.mouse_position = to
    state.handle_input(InputEventMouseMotion.new())


## A drag of *tool* from *from* to *to*, with Shift or Alt on the press.
func _drag(tool: StringName, from: Vector2, to: Vector2, shift: bool = false, alt: bool = false) -> void:
    var state := _press(tool, from, shift, alt)
    _move(state, to)
    state.handle_input(_button(false))


## The note's marquee, NOTE_RECT.
func _note_marquee() -> void:
    _drag(&"marquee", Vector2(NOTE_RECT.position), Vector2(NOTE_RECT.end))


func _coverage(x: int, y: int) -> float:
    var grid := Vector2i((Vector2(x, y) / SaChunk.SIZE).floor())
    var chunk: SaChunk = _doc.selection.chunks.get(grid, null)
    if chunk == null:
        return 0.0
    var texture := chunk.field(SaSelection.FIELD)
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var local := Vector2i(x, y) - grid * SaChunk.SIZE
    return bytes.decode_float((local.y * texture.size.x + local.x) * 4)


## Every chunk of the mask as its bytes, read back, so two masks compare whole.
func _mask() -> Dictionary:
    var out := {}
    for grid_pos: Vector2i in _doc.selection.chunks:
        var texture := (_doc.selection.chunks[grid_pos] as SaChunk).field(SaSelection.FIELD)
        out[grid_pos] = GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return out


## Every chunk of the active layer's colour, read back.
func _layer() -> Dictionary:
    var out := {}
    var layer := _doc.active_layer
    for grid_pos: Vector2i in layer.chunks:
        var texture := (layer.chunks[grid_pos] as SaChunk).albedo()
        out[grid_pos] = GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return out


## The Done when: a marquee, a press inside it and a drag 40 right and 20 down.
## The ants move by that much, the pixels do not, and Ctrl+Z puts the outline
## back.
func test_a_drag_inside_a_marquee_moves_its_outline_and_not_the_pixels() -> void:
    _doc.active_layer.get_or_create_chunk(Vector2i(0, 0)).clear(ORANGE)
    _doc.active_layer.get_or_create_chunk(Vector2i(1, 0)).clear(ORANGE)
    _note_marquee()
    assert_eq(_doc.selection.bounds, NOTE_RECT, "The note's marquee, 320 by 193")
    var mask := _mask()
    var pixels := _layer()
    var steps := _steps()

    _drag(&"marquee", Vector2(200.5, 150.5), Vector2(240.5, 170.5))

    var moved := Rect2i(NOTE_RECT.position + Vector2i(40, 20), NOTE_RECT.size)
    assert_eq(_doc.selection.bounds, moved, "The outline moved 40 right and 20 down, its size kept")
    assert_almost_eq(_coverage(100, 70), 1.0, 0.001, "The mask's new top left corner is selected")
    assert_almost_eq(_coverage(99, 70), 0.0, 0.001, "and the pixel left of it is not")
    assert_almost_eq(_coverage(419, 262), 1.0, 0.001, "The new bottom right corner is selected")
    assert_almost_eq(_coverage(420, 262), 0.0, 0.001, "and the pixel right of it is not")
    assert_almost_eq(_coverage(80, 60), 0.0, 0.001, "A pixel only the old shape held is out")
    assert_eq(_layer(), pixels, "The pixels did not move")
    assert_eq(_steps(), steps + 1, "The move is one step")
    assert_eq(_doc.undo_redo.get_current_action_name(), MarqueeScript.MOVE_TITLE, "named Move Selection")

    assert_true(_doc.undo(), "Ctrl+Z")
    assert_eq(_doc.selection.bounds, NOTE_RECT, "puts the outline back")
    assert_eq(_mask(), mask, "to the last bit")
    assert_eq(_layer(), pixels, "and the pixels are as they were")
    assert_true(_doc.redo(), "Ctrl+Shift+Z")
    assert_eq(_doc.selection.bounds, moved, "moves it again")


## While the button is down the overlay draws the ants through the offset and
## the mask waits for the release, so a drag writes nothing until it ends.
func test_the_ants_follow_the_pointer_in_whole_pixels_and_the_mask_waits() -> void:
    _note_marquee()
    var mask := _mask()
    var state := _press(&"marquee", Vector2(200.5, 150.5))
    assert_eq(state.call("preview_shape"), {"ants": Transform2D.IDENTITY}, "The press alone moves nothing")
    _move(state, Vector2(240.8, 170.3))
    assert_eq(state.call("preview_shape"), {"ants": Transform2D(0.0, Vector2(40, 20))}, "The ants follow in whole pixels")
    assert_eq(_doc.selection.bounds, NOTE_RECT, "and the selection has not moved yet")
    assert_eq(_mask(), mask, "nor has its mask")
    assert_eq(state.cursor_shape(), Control.CURSOR_MOVE, "The pointer is the move shape while it is held")
    state.handle_input(_button(false))
    assert_eq(state.call("preview_shape"), {}, "and the release leaves nothing in the air")


func test_a_press_outside_the_selection_draws_a_new_shape() -> void:
    _note_marquee()
    var steps := _steps()
    _drag(&"marquee", Vector2(500, 400), Vector2(661, 481))
    assert_eq(_doc.selection.bounds, Rect2i(500, 400, 161, 81), "A press outside draws the new shape")
    assert_almost_eq(_coverage(200, 150), 0.0, 0.001, "in place of the old one")
    assert_eq(_doc.undo_redo.get_current_action_name(), SaSelection.RECT_TITLE, "as a Rectangular Select step")
    assert_eq(_steps(), steps + 1, "and one step")


## Shift and Alt keep their chord inside the selection, and so does the bar's
## mode when it is not Replace. These are the ways the hint names for starting a
## shape from inside an old one.
func test_a_modifier_or_another_mode_starts_a_shape_inside_the_selection() -> void:
    _note_marquee()
    _drag(&"marquee", Vector2(300, 200), Vector2(450, 300), true)
    assert_eq(_doc.selection.bounds, Rect2i(60, 50, 390, 250), "Shift inside adds a shape")
    assert_eq(_doc.undo_redo.get_current_action_name(), SaSelection.RECT_TITLE, "and is the tool's step")
    _doc.undo()
    _drag(&"marquee", Vector2(100, 100), Vector2(200, 150), false, true)
    assert_almost_eq(_coverage(150, 120), 0.0, 0.001, "Alt inside subtracts a shape")
    assert_eq(_doc.selection.bounds.position, NOTE_RECT.position, "and the outline stays where it was")
    _doc.undo()
    _machine.set_active_tool(&"marquee")
    _machine.active_tool.set("mode", SaSelection.Mode.ADD)
    _drag(&"marquee", Vector2(300, 200), Vector2(450, 300))
    _machine.active_tool.set("mode", SaSelection.Mode.REPLACE)
    assert_eq(_doc.selection.bounds, Rect2i(60, 50, 390, 250), "The bar's Add inside adds a shape too")


## A press and a release inside the selection with no drag between is a click,
## and drops the selection as a click outside does, one step that Ctrl+Z takes
## back.
func test_a_click_inside_the_selection_drops_it() -> void:
    _note_marquee()
    var mask := _mask()
    _drag(&"marquee", Vector2(200.5, 150.5), Vector2(200.7, 150.2))
    assert_false(_doc.selection.active, "A click inside deselects")
    assert_eq(_doc.undo_redo.get_current_action_name(), SaSelection.DROP_TITLE, "as a Deselect step")
    _doc.undo()
    assert_eq(_mask(), mask, "which Ctrl+Z gives back")


## The Ellipse is the marquee with its shape fixed, so it moves too, and a
## feathered edge arrives as it left: a whole-pixel offset through the nearest
## filter puts every texel exactly on another.
func test_a_feathered_ellipse_moves_by_whole_pixels_unchanged() -> void:
    SaSettings.selection_feather = 0.01
    _drag(&"ellipse_select", Vector2(100, 100), Vector2(400, 300))
    var before := _doc.selection.bounds
    var samples: Array[Vector2i] = []
    for y in range(before.position.y, before.end.y, 17):
        for x in range(before.position.x, before.end.x, 13):
            samples.append(Vector2i(x, y))
    var was: Array[float] = []
    for at: Vector2i in samples:
        was.append(_coverage(at.x, at.y))
    var soft := was.filter(func(value: float) -> bool: return value > 0.01 and value < 0.99)
    assert_true(soft.size() > 4, "The samples cross the soft edge")

    _drag(&"ellipse_select", Vector2(250.5, 200.5), Vector2(287.5, 211.5))

    assert_eq(_doc.selection.bounds, Rect2i(before.position + Vector2i(37, 11), before.size), "The ellipse moved")
    var same := 0
    for i in samples.size():
        if _coverage(samples[i].x + 37, samples[i].y + 11) == was[i]:
            same += 1
    assert_eq(same, samples.size(), "and every sampled texel, the soft edge's too, is where the offset put it")
    assert_eq(_doc.undo_redo.get_current_action_name(), MarqueeScript.MOVE_TITLE, "as a Move Selection step")


## Only the chunks the moved bounds reach are made, and the old ones stay with
## the history step rather than being written into.
func test_a_move_writes_only_the_chunks_it_lands_on() -> void:
    _drag(&"marquee", Vector2(20, 20), Vector2(120, 120))
    var old_chunk: SaChunk = _doc.selection.chunks[Vector2i(0, 0)]
    var mask := _mask()
    _drag(&"marquee", Vector2(70, 70), Vector2(370, 370))
    assert_eq(_doc.selection.chunks.keys(), [Vector2i(1, 1)], "A move inside one chunk lands in one")
    assert_eq(_doc.selection.bounds, Rect2i(320, 320, 100, 100), "where the offset put it")
    _doc.undo()
    assert_eq(_doc.selection.chunks[Vector2i(0, 0)], old_chunk, "The undo hands back the very chunk the move left")
    assert_eq(_mask(), mask, "unwritten")
    _drag(&"marquee", Vector2(70, 70), Vector2(270, 70))
    var keys := _doc.selection.chunks.keys()
    keys.sort()
    assert_eq(keys, [Vector2i(0, 0), Vector2i(1, 0)], "A move across a seam lands on the two chunks it reaches")


## The Lasso and the Wand keep their clicks: a lasso drawn inside a selection
## replaces it rather than moving it.
func test_the_lasso_inside_a_selection_draws_a_new_one() -> void:
    _note_marquee()
    _machine.set_active_tool(&"lasso")
    var lasso := _machine.active_tool
    var path := [Vector2(150, 100), Vector2(250, 100), Vector2(250, 200), Vector2(150, 200)]
    _surface.view.mouse_position = path[0]
    lasso.handle_input(_button(true))
    for i in range(1, path.size()):
        _move(lasso, path[i])
    lasso.handle_input(_button(false))
    assert_eq(_doc.selection.bounds, Rect2i(150, 100, 100, 100), "The lasso's outline replaces the marquee")
    assert_eq(_doc.undo_redo.get_current_action_name(), SaSelection.FREEHAND_TITLE, "as its own step")


## The pointer says what a press would do: the move shape over a selection a
## press would move, and the tool's cross elsewhere and in another mode. The
## machine publishes the tool's answer as it changes, with no tool switch.
func test_the_cursor_is_the_move_shape_over_the_selection() -> void:
    _note_marquee()
    var state := _machine.active_tool
    _surface.view.mouse_position = Vector2(200, 150)
    assert_eq(state.cursor_shape(), Control.CURSOR_MOVE, "Over the selection the tool asks for the move shape")
    _machine._process(0.0)
    assert_eq(_machine._cursor_shape_shown, Control.CURSOR_MOVE, "and the machine publishes it")
    _surface.view.mouse_position = Vector2(600, 600)
    assert_eq(state.cursor_shape(), -1, "Outside it the tool leaves the shape to its descriptor")
    _machine._process(0.0)
    assert_eq(_machine._cursor_shape_shown, Control.CURSOR_CROSS, "which is the cross")
    _surface.view.mouse_position = Vector2(200, 150)
    state.set("mode", SaSelection.Mode.ADD)
    assert_eq(state.cursor_shape(), -1, "In Add a press inside draws, so the cross stays")
    state.set("mode", SaSelection.Mode.REPLACE)
    _doc.selection.drop()
    assert_eq(state.cursor_shape(), -1, "and with nothing selected there is nothing to move")
