## A let-out docker dragged under WinTab follows the system pointer, which the
## driver carries with the pen, and not a motion's place in its window.
##
## On 4 October the Alt drag of Brush Presets under WinTab "was jumping all over
## the place", 568 of 1282 moves over 40 px. A motion's place is measured
## against where its window was when Windows made it, and under WinTab the
## pen's packets and the mouse moves Windows makes from them interleave, one
## measured before the docker's last move and one after. Here every second
## motion is such a late one, placed as if the docker had not moved yet, and
## the system pointer is the suite's own, one step on with each pen motion.
extends "res://tests/test_framework.gd"

## Where the drag begins in the root window, and how far the pen moves a motion.
const PRESSED := Vector2(250.0, 165.0)
const STEP := Vector2(18.0, 7.0)
const STEPS := 12

var _host: Node = null
var _previous_system_pointer: Callable
## The system pointer on the desktop, a dictionary so the lambda shares it.
var _system: Dictionary = {}


func before_each() -> void:
    SaCursorPolicy.forget_pointer_device()
    DockerDragHandle.capture_pointer = null
    _previous_system_pointer = DockerDragHandle.system_pointer
    var system := _system
    DockerDragHandle.system_pointer = func() -> Variant: return system["at"]
    _host = Node.new()
    _host.name = "WinTabDragTestHost"
    EventBus.add_child(_host)


func after_each() -> void:
    SaCursorPolicy.forget_pointer_device()
    DockerDragHandle.system_pointer = _previous_system_pointer
    if _host != null:
        _host.free()
        _host = null


static func _root() -> Window:
    return (Engine.get_main_loop() as SceneTree).root


static func _motion(at: Vector2, pressure: float) -> InputEventMouseMotion:
    var motion := InputEventMouseMotion.new()
    motion.position = at
    motion.global_position = at
    motion.pressure = pressure
    return motion


static func _tip(at: Vector2, down: bool) -> InputEventMouseButton:
    var button := InputEventMouseButton.new()
    button.button_index = MOUSE_BUTTON_LEFT
    button.pressed = down
    button.position = at
    button.global_position = at
    return button


func test_late_motions_do_not_swing_the_docker_back() -> void:
    var docker := Window.new()
    docker.title = "WinTab Brush Presets"
    docker.position = Vector2i(400, 300)
    var title_bar := Control.new()
    # Not part of a layout, so the release does not save the run's layout.
    var handle := DockerDragHandle.new(false)
    _host.add_child(handle)
    handle.bind(docker, title_bar)

    var pointer := Vector2(docker.position) + PRESSED
    _system["at"] = pointer
    title_bar.gui_input.emit(_tip(PRESSED, true))
    var began := docker.position
    var went_back := 0
    var last := docker.position
    var place := PRESSED
    for i in STEPS:
        pointer += STEP
        _system["at"] = pointer
        # The packet's place, measured after the last move, then the mouse move
        # Windows made of it, measured against where the docker was before.
        var late := place + STEP + Vector2(docker.position - last)
        for motion: InputEventMouseMotion in [_motion(place, 0.7), _motion(late, 1.0)]:
            title_bar.gui_input.emit(motion)
            if Vector2(docker.position - last).dot(STEP) < 0.0:
                went_back += 1
            last = docker.position
    title_bar.gui_input.emit(_tip(place, false))

    assert_eq(went_back, 0, "The docker never went back towards where the drag began")
    var travelled := Vector2(docker.position - began)
    assert_true(travelled.distance_to(STEP * STEPS) <= 1.5, "and went as far as the pointer did, %s" % travelled)
    title_bar.free()
    docker.free()


## Windows Ink's answer is null, and the drag reads the pen's place there.
func test_the_shipped_reader_answers_only_under_wintab() -> void:
    var answer: Variant = _previous_system_pointer.call()
    if DisplayServer.tablet_get_current_driver() == "wintab":
        assert_true(answer is Vector2, "Under WinTab the drag reads the system pointer")
    else:
        assert_null(answer, "Under %s the drag reads the pen's place" % DisplayServer.tablet_get_current_driver())
