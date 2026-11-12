## The rotate arrow shows wherever a press would turn the box.
##
## The tool asks for the arrow and the policy puts it in the OS
## cursor's slot. The pen is the case at risk: under
## Wayland the driver gives a pen no cursor, so Sara hides the OS one and draws
## an arrow of its own, over the canvas as well, and that drawn arrow never
## asked what the tool wanted. The slot held `rotate` under a hidden cursor.
##
## The first half holds the ground: on a turned box on a zoomed view the arrow
## stands at exactly the points around every corner where a press starts a
## rotation. The second holds the drawing: the pen's drawn pointer wears the
## picture the slot holds, there and nowhere else. The scenario named after
## this suite shows the drawn arrow in a shot of the running app.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true
const Fixtures = preload("res://tests/fixtures.gd")
const StateTransformScript = preload("res://modules/sara-base-modules/base/transform/state_transform.gd")

## The selection the box stands on, so a drag lifts it.
const BOX := Rect2i(400, 384, 320, 256)
## The box's bottom right corner, in document pixels, where the turn is made.
const CORNER := Vector2(720, 640)
## The zoom the ground is read at, so a reach in screen pixels is half as many
## document pixels as at 100%.
const ZOOM := 2.0
## A point over the live canvas of the second half, in its window's pixels.
const ON_CANVAS := Vector2(100, 60)

var _surface: SaSurface = null
var _machine: ToolMachine = null
var _tool: StateTransformScript = null
var _host: Node = null


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
    SaPointerDevice.suite_pointer = null
    SaCursorPolicy.clear_tool_cursor()
    if _host != null:
        _host.free()
        _host = null
    Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null
    _tool = null


static func _button(pressed: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    return event


func _hover(at: Vector2) -> void:
    _surface.view.mouse_position = at
    _tool.handle_input(InputEventMouseMotion.new())
    _machine._process(0.0)


## The box turned by a drag from just outside its bottom right corner, the
## way a hand turns it, and left pending.
func _turn_the_box() -> void:
    _hover(CORNER + Vector2(14.0, 14.0))
    _tool.handle_input(_button(true))
    _hover(CORNER + Vector2(-30.0, 60.0))
    _tool.handle_input(_button(false))
    _machine._process(0.0)


func test_the_box_is_turned_before_the_ground_is_read() -> void:
    _turn_the_box()
    var quad := _tool.pending_quad()
    assert_eq(quad.size(), 4, "The box has four corners")
    var edge := quad[1] - quad[0]
    assert_true(absf(edge.angle()) > 0.1, "and its top edge leans after the turn, %.3f radians" % edge.angle())


## Every corner, on the turned box at 200%, on a grid of points round it in
## every mode: the arrow and the press agree at each one.
func test_the_arrow_stands_exactly_where_a_press_turns_on_a_turned_zoomed_box() -> void:
    _turn_the_box()
    _surface.view.set_zoom(ZOOM)
    var quad := _tool.pending_quad()
    for mode in StateTransformScript.Mode.size():
        _tool.transform_mode = mode
        var disagreed: Array[Vector2] = []
        var turned := 0
        var arrows := 0
        for corner: Vector2 in quad:
            for dx in range(-24, 25, 2):
                for dy in range(-24, 25, 2):
                    var at := corner + Vector2(dx, dy)
                    _surface.view.mouse_position = at
                    # A press on the mode strip picks a mode, and the sixth
                    # cell, Cage, reaches this corner's ground and would end
                    # the session, so the strip is no ground of the box's.
                    if _tool.tooltip() != "":
                        continue
                    var arrow := _tool.cursor_picture() != null
                    _tool.handle_input(_button(true))
                    var turns: bool = _tool._gesture == StateTransformScript.Gesture.ROTATE
                    _tool.handle_input(_button(false))
                    turned += 1 if turns else 0
                    arrows += 1 if arrow else 0
                    if arrow != turns:
                        disagreed.append(at)
        # Cage has no rotation, its presses place and drag the cage's points.
        if mode != StateTransformScript.Mode.CAGE:
            assert_true(turned > 0, "Mode %d has ground a press turns from" % mode)
        else:
            assert_eq(turned, 0, "Cage has no ground a press turns from")
        assert_eq(arrows, turned, "and in mode %d as many arrows as turns" % mode)
        assert_true(disagreed.is_empty(), "and in mode %d they stand at the same points: %s" % [mode, disagreed])


## The reach is the press's at this zoom: 28 screen pixels is 14 document ones.
func test_the_reach_on_the_zoomed_view_is_in_screen_pixels() -> void:
    _turn_the_box()
    _surface.view.set_zoom(ZOOM)
    var corner := _tool.pending_quad()[2]
    var outward := (corner - _centre(_tool.pending_quad())).normalized()
    _hover(corner + outward * 12.0)
    assert_eq(_published(), "rotate", "12 document pixels out, 24 screen pixels, the arrow")
    _hover(corner + outward * 16.0)
    assert_eq(_published(), "", "16 out, 32 screen pixels, past the reach, none")


## The pen's drawn pointer wears the picture the slot holds where the Transform
## asks for it, and is the plain arrow again where it asks for none. Without that the pen's
## pointer would always be the plain arrow.
func test_the_drawn_pen_pointer_wears_the_rotate_arrow() -> void:
    var window := _live_window()
    var descriptor := _machine.get_descriptor(&"transform")
    _hover(CORNER + Vector2(14.0, 14.0))
    var picture := _tool.cursor_picture()
    assert_not_null(picture, "Just outside the corner the tool asks for the arrow")
    SaCursorPolicy.apply_tool_cursor(_canvas_in(window), descriptor, Control.CURSOR_MOVE, picture)
    var worn := SaCursorPolicy.pen_picture_at(window, ON_CANVAS)
    assert_not_null(worn, "and the pen's drawn pointer wears a picture over the canvas")
    assert_eq(String(worn.name), "rotate", "the rotate arrow")
    assert_not_null(worn.texture, "drawn from a texture")
    assert_eq(worn.texture.get_width(), SaCursorPolicy.tool_cursor_edge, "at the edge every tool picture is drawn at")
    assert_eq(worn.hotspot, Vector2(0.5, 0.5), "centred on the pointer")

    _hover(Vector2(BOX.get_center()))
    SaCursorPolicy.apply_tool_cursor(_canvas_in(window), descriptor, Control.CURSOR_MOVE, _tool.cursor_picture())
    assert_null(SaCursorPolicy.pen_picture_at(window, ON_CANVAS), "Inside the box the drawn pointer is the plain arrow")


## Under Never Sara draws no pointer, so there is no drawn arrow to wear it.
func test_never_draws_no_picture() -> void:
    var window := _live_window()
    var previous := SaSettings.software_cursor
    _hover(CORNER + Vector2(14.0, 14.0))
    var descriptor := _machine.get_descriptor(&"transform")
    SaCursorPolicy.apply_tool_cursor(_canvas_in(window), descriptor, Control.CURSOR_MOVE, _tool.cursor_picture())
    SaSettings.software_cursor = "never"
    var worn := SaCursorPolicy.pen_picture_at(window, ON_CANVAS)
    SaSettings.software_cursor = previous
    assert_null(worn, "Never wears nothing")


func _published() -> String:
    var shown: SaCursorPicture = _machine._cursor_picture_shown
    return String(shown.name) if shown != null else ""


static func _centre(quad: PackedVector2Array) -> Vector2:
    return (quad[0] + quad[1] + quad[2] + quad[3]) * 0.25


func _live_window() -> Window:
    _host = Node.new()
    _host.name = "U54TestHost"
    EventBus.add_child(_host)
    var window := Window.new()
    window.borderless = true
    window.size = Vector2i(1920, 1080)
    _host.add_child(window)
    window.show()
    return window


## A live canvas over the whole of *window*, the pointer put over it.
func _canvas_in(window: Window) -> SaCanvas:
    var canvas := window.get_node_or_null("U54Canvas") as SaCanvas
    if canvas == null:
        canvas = SaCanvas.new()
        canvas.name = "U54Canvas"
        canvas.canvas_size = Vector2i(256, 256)
        window.add_child(canvas)
        canvas.position = Vector2.ZERO
        canvas.size = Vector2(1920, 1080)
    SaPointerDevice.suite_pointer = SaPointerDevice.desktop_transform(window) * ON_CANVAS
    return canvas
