## The ring is never drawn under a docker the pen is over, whatever window the
## docker is and whatever the display server says the pointer is.
##
## A painter with a pen in hand and embedded subwindows off said: "the
## cursor was not drawing properly on top of it once it became its own window."
## Under Windows Ink the display server reports the mouse and not the pen, and
## the main window asked the display server whenever the pen had last been seen
## in another window. So with the pen over a let-out docker the main window
## found its pointer over the canvas where the mouse was left, drew the ring
## there under the docker and hid the system pointer.
##
## A suite cannot map a window of its own, for the reason
## `render/cursor/tests/test_a_window_of_its_own.gd` gives, so the docker here is embedded
## and the let-out half is the scenario of the same name. What the two share is
## the arithmetic: the pen's place carried from the docker into the main window,
## and the rectangle `rect_in` measures the docker by, which is the one the
## window-of-its-own ruler asks. Every pen place is one the display server has
## never heard of, because the events are fed to the policy and the pointer is
## not moved.
extends "res://tests/test_framework.gd"

## A canvas builds an easel, which needs a RenderingDevice.
const REQUIRES_GPU := true

const DOCKER_AT := Vector2i(400, 300)
const DOCKER_SIZE := Vector2i(240, 200)
const RING := 12.0
## A point on the canvas clear of the docker and of the top left corner, where
## the windows other suites leave in the root stand.
const CANVAS_POINT := Vector2(1000.0, 700.0)

var _host: Node = null
var _previous_mode: String = "auto"


func before_each() -> void:
    _previous_mode = SaSettings.software_cursor
    SaSettings.software_cursor = "always"
    SaCursorPolicy.forget_pointer_device()
    _host = Node.new()
    _host.name = "R12CursorOverADockerTestHost"
    EventBus.add_child(_host)


func after_each() -> void:
    SaCursorPolicy.forget_pointer_device()
    SaSettings.software_cursor = _previous_mode
    if _host != null:
        _host.free()
        _host = null


## The main window is the root, with a canvas over all of it that wants a ring.
## A window embedded in another embedded window is left out, because
## `get_screen_transform` of the inner one skips the outer one's place, and no
## window of Sara's is nested that way.
func _main_window() -> Window:
    var window := (Engine.get_main_loop() as SceneTree).root
    var canvas := SaCanvas.new()
    canvas.canvas_size = Vector2i(256, 256)
    _host.add_child(canvas)
    canvas.position = Vector2.ZERO
    canvas.size = window.get_visible_rect().size
    canvas.cursor_ring_radius = RING
    return window


## The docker, with no overlay of its own, the way the policy meets one it has
## nothing drawn in.
func _docker() -> Window:
    var docker := Window.new()
    docker.borderless = true
    docker.position = DOCKER_AT
    docker.size = DOCKER_SIZE
    _host.add_child(docker)
    docker.show()
    return docker


## A pen motion, known for a pen by its tilt, fed the way `CursorOverlay._input`
## feeds it: in the window it arrived in.
func _pen_at(window: Window, at: Vector2) -> void:
    var motion := InputEventMouseMotion.new()
    motion.tilt = Vector2(0.2, -0.1)
    motion.position = at
    SaCursorPolicy.note_pointer_device(motion, window)


func test_the_pen_over_the_docker_is_over_the_docker_in_the_main_window() -> void:
    if DisplayServer.get_name() == "headless":
        return
    var window := _main_window()
    var docker := _docker()

    _pen_at(docker, Vector2(50.0, 60.0))
    var pointer := SaCursorPolicy.pointer_in_window(window)
    assert_true(
        pointer.is_equal_approx(Vector2(450.0, 360.0)), "The main window reads the pen carried from the docker, got %s" % pointer
    )
    assert_true(
        SaCursorPolicy.rect_in(window, docker).has_point(pointer), "which falls inside the rectangle the docker is measured by"
    )
    assert_true(
        SaCursorPolicy.pointer_is_over_ui(window, pointer), "so the main window knows something stands over its canvas there"
    )
    assert_eq(SaCursorPolicy.cursor_ring_radius_at(window, pointer), -1.0, "claims no ring under the docker")
    assert_eq(SaCursorPolicy.drawn_at(window, pointer), &"system", "and leaves the system pointer to the painter")
    assert_false(SaCursorPolicy.pointer_is_over_a_canvas(window, pointer), "The tool picture comes down there too")


func test_the_pen_over_the_canvas_draws_the_ring() -> void:
    if DisplayServer.get_name() == "headless":
        return
    var window := _main_window()
    var docker := _docker()

    _pen_at(docker, Vector2(50.0, 60.0))
    _pen_at(window, CANVAS_POINT)
    var pointer := SaCursorPolicy.pointer_in_window(window)
    assert_eq(pointer, CANVAS_POINT, "Back over the canvas the pen's own place is the main window's")
    assert_eq(SaCursorPolicy.cursor_ring_radius_at(window, pointer), RING, "the canvas claims its ring")
    assert_eq(SaCursorPolicy.drawn_at(window, pointer), &"ring", "and the ring is what is drawn")
    var in_docker := SaCursorPolicy.pointer_in_window(docker)
    assert_true(
        in_docker.is_equal_approx(Vector2(600.0, 400.0)), "The docker reads the same pen outside itself, got %s" % in_docker
    )


func test_a_mouse_keeps_the_display_servers_answer() -> void:
    if DisplayServer.get_name() == "headless":
        return
    var window := _main_window()
    var to_desktop := Transform2D(0.0, Vector2(window.position)) * window.get_screen_transform()
    var expected := to_desktop.affine_inverse() * Vector2(DisplayServer.mouse_get_position())

    assert_true(SaCursorPolicy.pointer_in_window(window).is_equal_approx(expected), "No pen seen, the display server's place")
    _pen_at(window, Vector2(100.0, 100.0))
    SaCursorPolicy.forget_pointer_device()
    assert_true(
        SaCursorPolicy.pointer_in_window(window).is_equal_approx(expected), "and a pen forgotten leaves nothing of its place"
    )
