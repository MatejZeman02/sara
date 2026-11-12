## The ring leaves the canvas when the pen leaves the main window for a docker,
## under Windows Ink as under WinTab.
##
## Under Windows Ink with subwindows off the ring could stay on the canvas
## when the pen crossed onto a docker. Godot 4.7
## parses a pen's hover under Ink only in the window that has the focus, so the
## docker the pen crossed onto heard nothing, and the main window, which had the
## focus, heard nothing more either, since the pen had left it. The one thing
## the engine does send is the window event that says the pointer left the main
## window, before the focus test that drops the motion. That reaches every node
## of the window as `NOTIFICATION_WM_MOUSE_EXIT`, and the overlay is the node
## every window has.
##
## A suite cannot map a window of its own, for the reason
## `render/cursor/tests/test_a_window_of_its_own.gd` gives, so the docker here is
## embedded and the notification is handed to the main window's overlay the way
## the engine hands it to each node. The docker's own motions, where they come,
## are the focused docker's under Ink and the rerouted ones of WinTab, fed the
## way `CursorOverlay._input` feeds them.
extends "res://tests/test_framework.gd"

## A canvas builds an easel, which needs a RenderingDevice.
const REQUIRES_GPU := true

const DOCKER_AT := Vector2i(400, 300)
const DOCKER_SIZE := Vector2i(240, 200)
const RING := 12.0
## The pen's last place on the canvas before it crosses onto the docker, just
## right of the docker's right edge, as a shot of it shows.
const BESIDE_THE_DOCKER := Vector2(660.0, 400.0)
## A point on the canvas clear of the docker and of the top left corner, where
## the windows other suites leave in the root stand.
const CANVAS_POINT := Vector2(1000.0, 700.0)

var _host: Node = null
var _previous_mode: String = "auto"
var _previous_mouse_mode: int = Input.MOUSE_MODE_VISIBLE


func before_each() -> void:
    _previous_mode = SaSettings.software_cursor
    _previous_mouse_mode = Input.get_mouse_mode()
    SaSettings.software_cursor = "always"
    SaCursorPolicy.forget_pointer_device()
    _host = Node.new()
    _host.name = "D20RingOntoADockerTestHost"
    EventBus.add_child(_host)


func after_each() -> void:
    SaCursorPolicy.forget_pointer_device()
    SaSettings.software_cursor = _previous_mode
    if _host != null:
        _host.free()
        _host = null
    # Process-wide, so a pointer an overlay here hid would stay hidden for the
    # suites after it.
    if Input.get_mouse_mode() != _previous_mouse_mode:
        Input.set_mouse_mode(_previous_mouse_mode as Input.MouseMode)


## Whether this run has no display that maps a window, saying so once so the
## closing notice counts the cases that returned instead of drawing.
func _no_window_maps() -> bool:
    if DisplayServer.get_name() != "headless":
        return false
    skip("a headless display maps no window, so no case followed the pen's ring onto a docker")
    return true


## The main window is the root, with a canvas over all of it that wants a ring.
func _main_window() -> Window:
    var window := (Engine.get_main_loop() as SceneTree).root
    var canvas := SaCanvas.new()
    canvas.canvas_size = Vector2i(256, 256)
    _host.add_child(canvas)
    canvas.position = Vector2.ZERO
    canvas.size = window.get_visible_rect().size
    canvas.cursor_ring_radius = RING
    return window


## An overlay in the main window, under the host rather than on the root,
## because the suites run inside the root's own setting up and it takes no
## child then. Its window is the root all the same, which is what the
## notification is asked about.
func _main_overlay(_window: Window) -> CursorOverlay:
    var overlay := CursorOverlay.new()
    _host.add_child(overlay)
    return overlay


## A docker with an overlay of its own, as every docker has.
func _docker() -> Window:
    var docker := Window.new()
    docker.borderless = true
    docker.position = DOCKER_AT
    docker.size = DOCKER_SIZE
    _host.add_child(docker)
    docker.show()
    CursorOverlay.attach_to(docker)
    return docker


## A pen motion, known for a pen by its tilt, in the window it arrived in.
func _pen_at(window: Window, at: Vector2, pressure: float = 0.0) -> void:
    var motion := InputEventMouseMotion.new()
    motion.tilt = Vector2(0.2, -0.1)
    motion.pressure = pressure
    motion.position = at
    SaCursorPolicy.note_pointer_device(motion, window)


## What the overlay of *window* draws for the pointer the ring's reader gives
## it, asked the way `CursorOverlay._draw_body` asks.
func _drawn_in(window: Window) -> StringName:
    var at := SaCursorPolicy.pointer_in_window(window)
    return (
        CursorOverlay
        . resolve_cursor(
            SaCursorPolicy.cursor_ring_radius_at(window, at),
            SaCursorPolicy.pointer_is_tablet,
            SaCursorPolicy.wants_software_pointer(window, at),
        )
    )


## The pen hovers over the canvas, crosses onto the docker, and the
## only word of it is the main window's exit.
func test_the_ring_leaves_the_canvas_when_the_pen_leaves_the_main_window() -> void:
    if _no_window_maps():
        return
    var window := _main_window()
    var overlay := _main_overlay(window)
    var docker := _docker()

    _pen_at(window, BESIDE_THE_DOCKER)
    assert_eq(_drawn_in(window), &"ring", "Over the canvas beside the docker, the ring is drawn")

    overlay.notification(Node.NOTIFICATION_WM_MOUSE_EXIT)
    var at := SaCursorPolicy.pointer_in_window(window)
    assert_false(
        Rect2(Vector2.ZERO, window.get_visible_rect().size).has_point(at),
        "The pen that left the main window is in none of it, got %s" % at
    )
    assert_eq(SaCursorPolicy.cursor_ring_radius_at(window, at), -1.0, "the canvas claims no ring for it")
    assert_eq(_drawn_in(window), &"system", "and the main window's overlay draws nothing")
    assert_false(SaCursorPolicy.pointer_is_over_a_canvas(window, at), "The tool's picture comes down with it")
    assert_eq(_drawn_in(docker), &"system", "The docker cannot place the pen either, so it draws nothing stale")


## A focused docker under Ink, and every docker under WinTab, hears the pen, and
## the arrow is drawn in it where the pen is while the canvas stays clear.
func test_a_motion_in_the_docker_puts_the_pen_there() -> void:
    if _no_window_maps():
        return
    var window := _main_window()
    var overlay := _main_overlay(window)
    var docker := _docker()

    _pen_at(window, BESIDE_THE_DOCKER)
    overlay.notification(Node.NOTIFICATION_WM_MOUSE_EXIT)
    _pen_at(docker, Vector2(50.0, 60.0))
    assert_eq(SaCursorPolicy.pointer_in_window(docker), Vector2(50.0, 60.0), "The docker reads the pen at its own place")
    assert_eq(_drawn_in(docker), &"pointer", "and draws the pen's arrow there")
    var in_main := SaCursorPolicy.pointer_in_window(window)
    assert_eq(SaCursorPolicy.cursor_ring_radius_at(window, in_main), -1.0, "while the main window draws no ring under the docker")


func test_the_pen_back_on_the_canvas_brings_the_ring_back() -> void:
    if _no_window_maps():
        return
    var window := _main_window()
    var overlay := _main_overlay(window)
    _docker()

    _pen_at(window, BESIDE_THE_DOCKER)
    overlay.notification(Node.NOTIFICATION_WM_MOUSE_EXIT)
    _pen_at(window, CANVAS_POINT)
    assert_eq(SaCursorPolicy.pointer_in_window(window), CANVAS_POINT, "A hover back on the canvas is the pen's place again")
    assert_eq(_drawn_in(window), &"ring", "and the ring is drawn there")


## Under Ink a window without the focus hears a pen's tip come down though not
## its hover, so a press is where the pen is before any motion says so.
func test_a_press_after_the_pen_left_puts_the_ring_where_it_landed() -> void:
    if _no_window_maps():
        return
    var window := _main_window()
    var overlay := _main_overlay(window)
    _docker()

    _pen_at(window, BESIDE_THE_DOCKER)
    overlay.notification(Node.NOTIFICATION_WM_MOUSE_EXIT)
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    press.position = CANVAS_POINT
    SaCursorPolicy.note_pointer_device(press, window)
    assert_eq(SaCursorPolicy.pointer_in_window(window), CANVAS_POINT, "The press is where the pen is")
    assert_eq(_drawn_in(window), &"ring", "and the ring is drawn where it landed")


## A stroke's motions keep coming to the window it began in, so an exit while
## the pen is down, which the engine sends under WinTab as the pointer crosses a
## docker, leaves the stroke's place alone.
func test_an_exit_during_a_stroke_leaves_the_pen_where_it_is() -> void:
    if _no_window_maps():
        return
    var window := _main_window()
    var overlay := _main_overlay(window)
    _docker()

    _pen_at(window, BESIDE_THE_DOCKER, 0.5)
    overlay.notification(Node.NOTIFICATION_WM_MOUSE_EXIT)
    assert_eq(SaCursorPolicy.pointer_in_window(window), BESIDE_THE_DOCKER, "A pressed pen keeps its place through the exit")


## Only the window the pen's place was kept in speaks for it, so a docker the
## pen was never seen in saying the pointer left it changes nothing.
func test_an_exit_from_another_window_leaves_the_pen_where_it_is() -> void:
    if _no_window_maps():
        return
    var window := _main_window()
    var docker := _docker()

    _pen_at(window, CANVAS_POINT)
    (docker.get_node("CursorOverlay") as CursorOverlay).notification(Node.NOTIFICATION_WM_MOUSE_EXIT)
    assert_eq(SaCursorPolicy.pointer_in_window(window), CANVAS_POINT, "The main window keeps the pen's place")
    assert_eq(_drawn_in(window), &"ring", "and its ring")


## A mouse is the display server's to place, which an exit does not change.
func test_a_mouse_keeps_the_display_servers_answer_through_an_exit() -> void:
    if _no_window_maps():
        return
    var window := _main_window()
    var overlay := _main_overlay(window)
    var to_desktop := Transform2D(0.0, Vector2(window.position)) * window.get_screen_transform()
    var expected := to_desktop.affine_inverse() * Vector2(DisplayServer.mouse_get_position())

    overlay.notification(Node.NOTIFICATION_WM_MOUSE_EXIT)
    assert_true(SaCursorPolicy.pointer_in_window(window).is_equal_approx(expected), "No pen seen, the display server's place")
