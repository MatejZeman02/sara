## A press beside a selection's shape starts a new shape and does not move it.
##
## With an ellipse selected from (100, 100) to (300, 300), a press at (108, 108),
## in the corner of its box and outside the ellipse, must not move the outline.
## The marquee asks the shape the selection keeps beside its mask, on the CPU,
## and the bounds only where no shape stands. Every mask the suite reads is read back from VRAM.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const MarqueeScript = preload("res://modules/sara-base-modules/base/tools/state_marquee.gd")

## The probe's ellipse, and the press in the corner of its box.
const ELLIPSE_FROM := Vector2(100, 100)
const ELLIPSE_TO := Vector2(300, 300)
const CORNER := Vector2(108, 108)
const MIDDLE := Vector2(200, 200)

## A lasso shaped like a U: the notch runs down from the top between x 180 and
## 220 to y 160.
const U_SHAPE: Array[Vector2] = [
    Vector2(100, 300),
    Vector2(100, 100),
    Vector2(180, 100),
    Vector2(180, 220),
    Vector2(220, 220),
    Vector2(220, 100),
    Vector2(300, 100),
    Vector2(300, 300),
]
const NOTCH := Vector2(200, 150)
const ARM := Vector2(140, 200)

var _surface: SaSurface = null
var _machine: ToolMachine = null
var _doc: SaDocument = null
var _feather_was: float = 0.0


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


static func _button(pressed: bool, shift: bool = false) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    event.shift_pressed = shift
    return event


func _move(state: ToolState, to: Vector2) -> void:
    _surface.view.mouse_position = to
    state.handle_input(InputEventMouseMotion.new())


## A drag of *tool* through *path*, pressed at its first point and let go at
## its last, with Shift on the press when *shift* asks.
func _drag(tool: StringName, path: Array, shift: bool = false) -> void:
    _machine.set_active_tool(tool)
    var state := _machine.active_tool
    _surface.view.mouse_position = path[0]
    state.handle_input(_button(true, shift))
    for i in range(1, path.size()):
        _move(state, path[i])
    state.handle_input(_button(false))


## The marquee's answer for a plain press at *point*, the Ellipse Select's
## being the same code.
func _moves(point: Vector2) -> bool:
    _machine.set_active_tool(&"marquee")
    return _machine.active_tool.call("moves_from", point, false, false)


## The cursor the tool answers with the pointer at *point*, and the one the
## machine publishes from that answer.
func _cursor_at(point: Vector2) -> Array:
    _surface.view.mouse_position = point
    var answer: int = _machine.active_tool.cursor_shape()
    _machine._process(0.0)
    return [answer, _machine._cursor_shape_shown]


func _coverage(x: int, y: int) -> float:
    var grid := Vector2i((Vector2(x, y) / SaChunk.SIZE).floor())
    var chunk: SaChunk = _doc.selection.chunks.get(grid, null)
    if chunk == null:
        return 0.0
    var texture := chunk.field(SaSelection.FIELD)
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var local := Vector2i(x, y) - grid * SaChunk.SIZE
    return bytes.decode_float((local.y * texture.size.x + local.x) * 4)


func test_a_press_in_the_corner_of_an_ellipse_s_box_does_not_move_it() -> void:
    _drag(&"ellipse_select", [ELLIPSE_FROM, ELLIPSE_TO])
    assert_eq(_doc.selection.bounds, Rect2i(100, 100, 200, 200), "The probe's ellipse")
    assert_true(Rect2(_doc.selection.bounds).has_point(CORNER), "The corner press is inside the bounds")
    assert_false(_moves(CORNER), "and a press there does not move the outline")
    assert_true(_moves(MIDDLE), "A press at the ellipse's middle still does")
    _machine.set_active_tool(&"ellipse_select")
    assert_eq(_cursor_at(CORNER), [-1, Control.CURSOR_CROSS], "The corner shows the cross")
    assert_eq(_cursor_at(MIDDLE), [Control.CURSOR_MOVE, Control.CURSOR_MOVE], "and the middle the move cursor")


func test_a_press_in_a_lasso_s_notch_does_not_move_it() -> void:
    var path: Array = U_SHAPE.duplicate()
    path.append(U_SHAPE[0])
    _drag(&"lasso", path)
    assert_eq(_doc.selection.bounds, Rect2i(100, 100, 200, 200), "The U's box")
    assert_almost_eq(_coverage(int(NOTCH.x), int(NOTCH.y)), 0.0, 0.001, "The notch is not selected")
    assert_false(_moves(NOTCH), "and a press in it does not move the outline")
    assert_true(_moves(ARM), "A press in the U's arm does")


## A shape added to the selection makes a mask no one shape describes, so the
## marquee asks the bounds as it always did.
func test_a_selection_added_to_falls_back_to_the_bounds() -> void:
    var path: Array = U_SHAPE.duplicate()
    _drag(&"lasso", path)
    _drag(&"marquee", [Vector2(400, 400), Vector2(450, 450)], true)
    assert_eq(_doc.selection.bounds, Rect2i(100, 100, 350, 350), "The square joined the U")
    assert_null(_doc.selection.shape, "No shape is kept for an added selection")
    assert_true(_moves(NOTCH), "so a press in the notch moves it, as before")
    assert_true(_moves(Vector2(350, 350)), "and so does one between the two shapes")


func test_a_drag_from_the_corner_selects_a_second_ellipse_in_its_place() -> void:
    _drag(&"ellipse_select", [ELLIPSE_FROM, ELLIPSE_TO])
    _drag(&"ellipse_select", [CORNER, Vector2(160, 160)])
    assert_eq(_doc.selection.bounds, Rect2i(108, 108, 52, 52), "The new ellipse's box")
    assert_eq(_doc.undo_redo.get_current_action_name(), SaSelection.ELLIPSE_TITLE, "as an Ellipse Select step")
    assert_almost_eq(_coverage(134, 134), 1.0, 0.001, "The new ellipse's middle is selected")
    assert_almost_eq(_coverage(250, 250), 0.0, 0.001, "and the old one's, which it does not cover, is not")


## The shape travels with the selection's held state, so an undo puts back the
## ellipse that knows its corner, and a move of the outline carries it along.
func test_the_shape_follows_undo_and_a_move() -> void:
    _drag(&"ellipse_select", [ELLIPSE_FROM, ELLIPSE_TO])
    _drag(&"marquee", [Vector2(500, 500), Vector2(600, 600)])
    assert_true(_moves(Vector2(502, 502)), "A rectangle moves from its own corner")
    _doc.undo()
    assert_eq(_doc.selection.bounds, Rect2i(100, 100, 200, 200), "Ctrl+Z gives the ellipse back")
    assert_false(_moves(CORNER), "and its corner still starts a new shape")
    _doc.redo()
    _doc.undo()
    assert_false(_moves(CORNER), "after a redo and an undo too")
    _drag(&"ellipse_select", [MIDDLE, MIDDLE + Vector2(20, 0)])
    assert_eq(_doc.undo_redo.get_current_action_name(), MarqueeScript.MOVE_TITLE, "The middle press moved it")
    assert_false(_moves(Vector2(128, 108)), "and the moved ellipse's corner still starts a new shape")
    assert_true(_moves(MIDDLE + Vector2(20, 0)), "while its new middle moves it")
    _doc.undo()
    assert_false(_moves(CORNER), "Ctrl+Z puts the ellipse and its shape back where they were")
    _drag(&"lasso", U_SHAPE.duplicate())
    _drag(&"marquee", [ARM, ARM + Vector2(0, 30)])
    assert_eq(_doc.selection.bounds, Rect2i(100, 130, 200, 200), "The U moved 30 down")
    assert_false(_moves(NOTCH + Vector2(0, 30)), "and its notch moved with it")


func test_a_feathered_ellipse_keeps_its_shape() -> void:
    SaSettings.selection_feather = 0.01
    _drag(&"ellipse_select", [ELLIPSE_FROM, ELLIPSE_TO])
    assert_false(_moves(CORNER), "The feathered ellipse's corner starts a new shape")
    assert_true(_moves(MIDDLE), "and its middle moves it")
