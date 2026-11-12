## A let-out docker dragged by its title bar with the pen follows the pen, with
## the motion Windows Ink makes of a window moved under the system pointer
## arriving after every one of the pen's.
##
## On a Windows tablet Layers went back
## and forth between the pen and one fixed place near where the drag began, 372
## times in 897 changes of place. Each motion here is fed to the cursor policy
## first, as `CursorOverlay._input` sees it before the GUI does, and then to the
## title bar's own `gui_input`, the door a press on it arrives through.
## Why the plain motion is not the pen is
## `render/cursor/tests/test_a_plain_motion_does_not_move_a_pressed_pens_place.gd`.
##
## The pen's motions arrive in the root window, which stands in for the docker
## because a suite cannot map a window of its own, and the docker is a window
## outside the tree, so its drag reads the pen's place on the desktop as a
## let-out docker's does.
extends "res://tests/test_framework.gd"

## Where the system pointer stays while the pen drags, and where the drag
## begins, in the root window.
const STILL := Vector2(240.0, 160.0)
const PRESSED := Vector2(250.0, 165.0)
## How far each pen motion moves on from the last, and how many there are.
const STEP := Vector2(18.0, 7.0)
const STEPS := 12

var _host: Node = null
var _previous_trail: bool = false
var _previous_system_pointer: Callable


func before_each() -> void:
    SaCursorPolicy.forget_pointer_device()
    DockerDragHandle.capture_pointer = null
    _previous_trail = DockerDragHandle.trail
    # Windows Ink's case, where a move follows the pen's place.
    _previous_system_pointer = DockerDragHandle.system_pointer
    DockerDragHandle.system_pointer = func() -> Variant: return null
    _host = Node.new()
    _host.name = "D17PenDragTestHost"
    EventBus.add_child(_host)


func after_each() -> void:
    SaCursorPolicy.forget_pointer_device()
    DockerDragHandle.trail = _previous_trail
    DockerDragHandle.system_pointer = _previous_system_pointer
    if _host != null:
        _host.free()
        _host = null


static func _root() -> Window:
    return (Engine.get_main_loop() as SceneTree).root


## *at* in the root window on the desktop, the transform the cursor policy
## carries a window of its own's places by.
static func _on_the_desktop(at: Vector2) -> Vector2:
    var root := _root()
    return Transform2D(0.0, Vector2(root.position)) * root.get_screen_transform() * at


static func _pen(at: Vector2, pressure_of_1024: int) -> InputEventMouseMotion:
    var motion := InputEventMouseMotion.new()
    motion.position = at
    motion.global_position = at
    motion.pressure = float(pressure_of_1024) / 1024.0
    motion.tilt = Vector2(14.0, -9.0) / 90.0
    return motion


static func _plain(at: Vector2) -> InputEventMouseMotion:
    var motion := InputEventMouseMotion.new()
    motion.position = at
    motion.global_position = at
    return motion


static func _tip(at: Vector2, down: bool) -> InputEventMouseButton:
    var button := InputEventMouseButton.new()
    button.button_index = MOUSE_BUTTON_LEFT
    button.pressed = down
    button.position = at
    button.global_position = at
    return button


func test_a_let_out_docker_dragged_with_the_pen_never_goes_back() -> void:
    _drag_with_the_pen(STEPS)


## The same drag with the trail on, one pen motion and one plain one long, so
## a drag runs every branch of the trail's lines and prints only four of them.
func test_the_drags_trail_prints_from_a_drag() -> void:
    DockerDragHandle.trail = true
    _drag_with_the_pen(1)


## Hovers the pen to the press, presses the title bar, drags *steps* pen
## motions each with a plain one after it, lets go, and holds that the docker
## never went back and went as far as the pen did.
func _drag_with_the_pen(steps: int) -> void:
    var window := _root()
    var docker := Window.new()
    docker.title = "Probe Layers"
    docker.position = Vector2i(_on_the_desktop(PRESSED) - Vector2(30.0, 12.0))
    var title_bar := Control.new()
    # Not part of a layout, so the release does not save the run's layout.
    var handle := DockerDragHandle.new(false)
    _host.add_child(handle)
    handle.bind(docker, title_bar)

    SaCursorPolicy.note_pointer_device(_pen(PRESSED, 0), window)
    SaCursorPolicy.note_pointer_device(_tip(PRESSED, true), window)
    title_bar.gui_input.emit(_tip(PRESSED, true))
    var began := docker.position
    var pen := PRESSED
    var went_back := 0
    var last := docker.position
    for i in steps:
        pen += STEP
        for motion: InputEventMouseMotion in [_pen(pen, 300 + 20 * i), _plain(STILL)]:
            SaCursorPolicy.note_pointer_device(motion, window)
            title_bar.gui_input.emit(motion)
            if Vector2(docker.position - last).dot(STEP) < 0.0:
                went_back += 1
            last = docker.position
    SaCursorPolicy.note_pointer_device(_tip(pen, false), window)
    title_bar.gui_input.emit(_tip(pen, false))

    assert_eq(went_back, 0, "The docker never went back towards where the drag began")
    var travelled := Vector2(docker.position - began)
    var wanted := _on_the_desktop(pen) - _on_the_desktop(PRESSED)
    assert_true(travelled.distance_to(wanted) <= 1.5, "and went as far as the pen did, %s for %s" % [travelled, wanted])
    title_bar.free()
    docker.free()
