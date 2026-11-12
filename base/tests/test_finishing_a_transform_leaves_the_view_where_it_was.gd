## Finishing a transform leaves the view where it was.
##
## The transform tool must not jump the view when done. Enter, Escape and an
## undo never move the view, and neither does the release of a drag that
## carried a handle out of the room between the dockers, because the reach runs
## as the tool opens only. So every way a transform ends leaves the view's pan,
## zoom and rotation as the painter set them.
##
## The pictures are `scenarios/finishing-a-transform-leaves-the-view-where-it-was.json`.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true
const Fixtures = preload("res://tests/fixtures.gd")
const StateTransformScript = preload("res://modules/sara-base-modules/base/transform/state_transform.gd")

const CANVAS := Vector2i(1024, 1024)
const STROKE := Rect2i(300, 300, 100, 50)
## The view off its fit, as a painter leaves it: zoomed, turned, and panned so
## the stroke's middle stands at the middle of the window.
const ZOOM := 1.5
const TURN := 0.3

## The pan `_rig` set, which every assertion reads the view's against.
var _pan := Vector2.ZERO


func _button(pressed: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    return event


func _key(keycode: Key) -> InputEventKey:
    var event := InputEventKey.new()
    event.keycode = keycode
    event.physical_keycode = keycode
    event.pressed = true
    return event


## A surface with a painted stroke, the transform tool on it, and the view set
## off its fit. The tool's first tick is the open's own reach, which the box
## inside the room leaves alone.
func _rig() -> Array:
    var surface := Fixtures.make_surface(CANVAS)
    var machine := Fixtures.make_bound_machine(surface)
    machine.set_active_tool(&"brush")
    machine.set_active_tool(&"transform")
    var view := surface.view as Fixtures.FakeView
    view.viewport_size = Vector2(800, 600)
    view.set_zoom(ZOOM)
    view.set_rotation(TURN)
    view.set_pan(view.get_pan() + view.viewport_size * 0.5 - view.document_to_screen(Vector2(STROKE.get_center())))
    _pan = view.get_pan()
    _paint(surface.get_document(), STROKE)
    var tool: StateTransformScript = machine.active_tool
    tool.tick(0.0)
    return [surface, machine, tool, view]


## A frame of the running app after a key, which ticks whatever tool the
## machine holds then: Enter hands the brush back, and the transform's own tick
## no longer runs.
static func _frame(machine: ToolMachine) -> void:
    machine.active_tool.tick(0.0)


## *rect*, in document pixels, painted on the active layer chunk by chunk.
static func _paint(document: SaDocument, rect: Rect2i) -> void:
    var layer := document.active_layer
    var device := GlobalShaderCompiler.get_rd()
    for grid_pos: Vector2i in SaChunkWalk.positions_in(rect):
        var chunk := layer.get_or_create_chunk(grid_pos)
        var texture := chunk.albedo()
        var edge := chunk.pixel_size()
        var half := texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
        var format := Image.FORMAT_RGBAH if half else Image.FORMAT_RGBAF
        var image := Image.create_from_data(edge, edge, false, format, device.texture_get_data(texture.rid, 0))
        image.fill_rect(SaChunkWalk.local_rect(grid_pos, rect, edge), Color(0.8, 0.3, 0.1, 1.0))
        device.texture_update(texture.rid, 0, image.get_data())
        layer.mark_unresolved(grid_pos)
    document.invalidate_chunks(layer.chunks.keys())


## A drag of the left button from *from* to *to*, in document pixels, with a
## tick on each frame as the running app gives one, and the tick after the
## release, where a reach would run.
func _drag(tool: StateTransformScript, view: Fixtures.FakeView, from: Vector2, to: Vector2) -> void:
    view.mouse_position = from
    tool.handle_input(_button(true))
    for i in range(1, 9):
        view.mouse_position = from.lerp(to, float(i) / 8.0)
        tool.handle_input(InputEventMouseMotion.new())
        tool.tick(0.0)
    tool.handle_input(_button(false))
    tool.tick(0.0)


## A turn from just outside the box's bottom right corner, a reach the corner's
## own handle does not take, round the box's middle by a quarter.
func _turn(tool: StateTransformScript, view: Fixtures.FakeView) -> void:
    var quad := tool.pending_quad()
    var corner: Vector2 = quad[2]
    var middle := (quad[0] + quad[2]) * 0.5
    var outside := corner + (corner - middle).normalized() * (18.0 / ZOOM)
    var turned := middle + (outside - middle).rotated(PI * 0.25)
    _drag(tool, view, outside, turned)


func _assert_view_kept(view: Fixtures.FakeView, what: String) -> void:
    assert_eq(view.get_pan(), _pan, "%s leaves the pan" % what)
    assert_eq(view.get_zoom(), ZOOM, "and the zoom")
    assert_eq(view.get_rotation(), TURN, "and the rotation")


func test_the_view_opens_where_the_painter_left_it() -> void:
    var parts := _rig()
    _assert_view_kept(parts[3], "Opening on a box inside the room")
    Fixtures.teardown(parts[0], parts[1])


func test_enter_after_a_move_and_a_turn_inside_the_canvas_leaves_the_view() -> void:
    var parts := _rig()
    var tool: StateTransformScript = parts[2]
    var view: Fixtures.FakeView = parts[3]
    _drag(tool, view, Vector2(350, 325), Vector2(420, 380))
    _turn(tool, view)
    assert_true(tool.is_moving(), "The picture is in the air")
    assert_true(absf(tool.matrix.get_rotation()) > 0.1, "and turned, by %s" % tool.matrix.get_rotation())
    _assert_view_kept(view, "The move and the turn")
    tool.handle_input(_key(KEY_ENTER))
    _frame(parts[1])
    assert_false(tool.is_moving(), "Enter landed it")
    _assert_view_kept(view, "Enter")
    Fixtures.teardown(parts[0], parts[1])


## A move and a turn that carry the picture past the canvas's right edge and
## past the window's, where a reach on the release would pan the view. The
## canvas keeps its size, because a transform lands what is past the page in
## chunks beyond it rather than growing the page.
func test_enter_after_a_move_past_the_canvas_edge_leaves_the_view() -> void:
    var parts := _rig()
    var surface: SaSurface = parts[0]
    var tool: StateTransformScript = parts[2]
    var view: Fixtures.FakeView = parts[3]
    _drag(tool, view, Vector2(350, 325), Vector2(1100, 400))
    _turn(tool, view)
    assert_true(tool.pending_quad()[1].x > float(CANVAS.x), "The box stands past the canvas's right edge")
    assert_false(
        view.get_visible_rect().has_point(view.document_to_screen(tool.pending_quad()[1])), "and its corner past the window's"
    )
    _assert_view_kept(view, "The release past the edge")
    tool.handle_input(_key(KEY_ENTER))
    _frame(parts[1])
    _assert_view_kept(view, "Enter")
    assert_eq(surface.get_document().canvas_size, CANVAS, "and the canvas kept its size")
    Fixtures.teardown(parts[0], parts[1])


func test_escape_after_a_move_past_the_edge_leaves_the_view() -> void:
    var parts := _rig()
    var tool: StateTransformScript = parts[2]
    var view: Fixtures.FakeView = parts[3]
    _drag(tool, view, Vector2(350, 325), Vector2(1100, 400))
    tool.handle_input(_key(KEY_ESCAPE))
    _frame(parts[1])
    assert_false(tool.is_moving(), "Escape put it back")
    _assert_view_kept(view, "Escape")
    Fixtures.teardown(parts[0], parts[1])


## An undo over a move in the air commits it first, `close_session`, and then
## takes it back, the commit by undo the row names.
func test_an_undo_over_a_move_past_the_edge_leaves_the_view() -> void:
    var parts := _rig()
    var surface: SaSurface = parts[0]
    var tool: StateTransformScript = parts[2]
    var view: Fixtures.FakeView = parts[3]
    _drag(tool, view, Vector2(350, 325), Vector2(1100, 400))
    assert_true(tool.close_session(), "The undo's commit wrote the move")
    assert_true(surface.get_document().undo(), "and the undo took it back")
    tool.tick(0.0)
    _assert_view_kept(view, "The undo")
    Fixtures.teardown(parts[0], parts[1])


func test_enter_after_moving_a_selection_past_the_edge_leaves_the_view() -> void:
    var parts := _rig()
    var surface: SaSurface = parts[0]
    var tool: StateTransformScript = parts[2]
    var view: Fixtures.FakeView = parts[3]
    surface.get_document().selection.select_rect(Rect2i(320, 310, 40, 30))
    tool.reset()
    tool.tick(0.0)
    _assert_view_kept(view, "Opening on the selection")
    _drag(tool, view, Vector2(340, 325), Vector2(1100, 400))
    assert_true(tool.is_moving(), "The selection's pixels are in the air")
    tool.handle_input(_key(KEY_ENTER))
    _frame(parts[1])
    _assert_view_kept(view, "Enter on the selection")
    Fixtures.teardown(parts[0], parts[1])
