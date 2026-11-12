## Sara full screen on Android leaves the swipe from the top
## or bottom edge to the system, and keeps no button that leaves full screen.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Android draws its bars over a full-screen app for a moment when a finger
## swipes in from an edge, and the app hears the same swipe. So the canvas
## must not follow a finger that lands on the window's top or bottom edge, or a
## finger's pan would move the view under the bars. One finger's drag pans the
## canvas, so the same swipe that pans from the middle of the window moves
## nothing when it lands on the top or bottom edge. Every event
## goes the engine's way, the root window's `window_input` first and then
## `push_input`, with the mouse Godot emulates from a finger beside it, to a
## real `MainCanvas` that fills the window as Sara's canvas does with no bar
## below it. The window buttons are read in
## `ui/top_bar/tests/test_on_android_the_bar_keeps_close_alone.gd`. @tool
extends "res://tests/test_framework.gd"

## A real canvas with a brush, which needs a RenderingDevice.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const MainCanvasScript = preload("res://render/main_canvas.gd")

var _host: Control = null
var _canvas: Node = null


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    SaCursorPolicy.forget_pointer_device()
    _host = Control.new()
    _host.name = "U375Host"
    _host.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _host.size = Vector2(tree.root.size)
    EventBus.add_child(_host)
    _canvas = MainCanvasScript.new()
    _host.add_child(_canvas)
    _canvas.size = _host.size
    _canvas.bind_tools(Fixtures.make_tool_registry())
    _canvas.notification(Container.NOTIFICATION_SORT_CHILDREN)


func after_each() -> void:
    SaPointerDevice.suite_pointer = null
    if _host != null:
        _host.free()
    _host = null
    _canvas = null


func test_the_band_is_the_top_and_bottom_edge_alone() -> void:
    assert_true(MainCanvasScript.at_system_edge(0.0, 800.0), "A landing on the top row is the system's")
    assert_true(MainCanvasScript.at_system_edge(799.0, 800.0), "and one on the bottom row")
    assert_true(MainCanvasScript.at_system_edge(785.0, 800.0), "and one 15 pixels above the bottom")
    assert_false(MainCanvasScript.at_system_edge(400.0, 800.0), "and the middle is the canvas's")
    assert_false(MainCanvasScript.at_system_edge(30.0, 800.0), "as is a point 30 pixels down")


func test_the_canvas_reaches_both_edges_here() -> void:
    var rect: Rect2 = _canvas.control_node.get_global_rect()
    assert_true(rect.has_point(Vector2(_middle_x(), 2.0)), "The canvas's control reaches the top edge, %s" % rect)
    var bottom := Vector2(_middle_x(), _height() - 2.0)
    assert_true(rect.has_point(bottom), "and the bottom edge, so only the band keeps a finger off it")


func test_one_finger_inside_the_window_pans() -> void:
    var moved := _swipe_from(_height() * 0.5 + 60.0)
    assert_true(moved.length() > 10.0, "One finger's drag landing inside the window moved the view, by %s" % moved)


func test_a_swipe_up_from_the_bottom_edge_moves_nothing_and_paints_nothing() -> void:
    var steps := _steps()
    var moved := _swipe_from(_height() - 2.0)
    assert_true(
        moved.is_zero_approx(), "A finger landing on the bottom edge is not the canvas's, the view stayed, moved by %s" % moved
    )
    assert_eq(_steps(), steps, "and the swipe left no undo step, so it painted nothing")
    assert_false(_drawing(), "and no stroke is under way")


func test_a_swipe_down_from_the_top_edge_moves_nothing_and_paints_nothing() -> void:
    var steps := _steps()
    var moved := _swipe_from(1.0)
    assert_true(moved.is_zero_approx(), "A finger landing on the top edge moved nothing, %s" % moved)
    assert_eq(_steps(), steps, "and painted nothing")


# --- Helpers --------------------------------------------------------------------


func _height() -> float:
    return _host.size.y


func _middle_x() -> float:
    return _host.size.x * 0.5


## One finger lands at *y* and swipes up to the middle, the way a painter
## calls the bars back from the bottom, or down for the top. Returns how far
## the view moved.
func _swipe_from(y: float) -> Vector2:
    var view: SaView = _canvas.tool_machine.surface.view
    var pan := view.get_pan()
    var x := _middle_x()
    var middle := _height() * 0.5
    var toward := middle - 120.0 if y > middle else middle + 120.0
    _touch(0, Vector2(x, y), true)
    for i in range(1, 11):
        _drag(0, Vector2(x + 4.0 * i, lerpf(y, toward, i / 10.0)))
    _touch(0, Vector2(x + 40.0, toward), false)
    return view.get_pan() - pan


func _touch(index: int, at: Vector2, pressed: bool) -> void:
    var event := InputEventScreenTouch.new()
    event.index = index
    event.pressed = pressed
    _hand(event, at)
    if index == 0:
        var button := InputEventMouseButton.new()
        button.device = InputEvent.DEVICE_ID_EMULATION
        button.button_index = MOUSE_BUTTON_LEFT
        button.pressed = pressed
        button.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
        _hand(button, at)


func _drag(index: int, at: Vector2) -> void:
    var event := InputEventScreenDrag.new()
    event.index = index
    _hand(event, at)
    if index == 0:
        var motion := InputEventMouseMotion.new()
        motion.device = InputEvent.DEVICE_ID_EMULATION
        motion.button_mask = MOUSE_BUTTON_MASK_LEFT
        motion.pressure = 1.0
        _hand(motion, at)


func _drawing() -> bool:
    var tool_machine: ToolMachine = _canvas.tool_machine
    return tool_machine.active_tool != null and bool(tool_machine.active_tool.get("is_drawing"))


func _steps() -> int:
    var history: Object = _canvas.canvas.document.history
    return history.step_count() if history != null else -1


## *event* at *at*, in the main window's logical space, handed to the root the
## way `Window` hands an event the display server delivered: its input signal
## first, in the window's own space, then into the viewport.
func _hand(event: InputEvent, at: Vector2) -> void:
    var root := (Engine.get_main_loop() as SceneTree).root
    var raw := root.get_final_transform() * at
    var mouse := event as InputEventMouse
    if mouse != null:
        SaPointerDevice.suite_pointer = SaPointerDevice.desktop_transform(root) * at
        mouse.position = raw
        mouse.global_position = raw
    elif event is InputEventScreenTouch:
        (event as InputEventScreenTouch).position = raw
    else:
        (event as InputEventScreenDrag).position = raw
    root.window_input.emit(event)
    root.push_input(event)
