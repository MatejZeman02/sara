## A shift-drag that resizes the brush tells the options rows once a frame,
## however many motions the frame brought.
##
## Every motion told them, and each telling had the options bar and the docker
## read every row again, 7.8 ms a motion on Linux. A pen under Windows sends
## four or more motions a frame, so a resize cost 30 ms a frame and the ring
## and the slider fell behind the hand, which a painter reported as "changing the size
## also still lags". A suite cannot wait for a frame, so each test ends its
## frame by calling what the frame's end calls.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true

## The motions a pen under Windows sends in one frame at 60 Hz.
const MOTIONS_A_FRAME := 4

var _told: int = 0


func _count_told() -> void:
    _told += 1


func _press(at: Vector2) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = true
    event.shift_pressed = true
    event.position = at
    event.global_position = at
    return event


func _release(at: Vector2) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = false
    event.position = at
    event.global_position = at
    return event


func _motion(at: Vector2) -> InputEventMouseMotion:
    var event := InputEventMouseMotion.new()
    event.position = at
    event.global_position = at
    event.pressure = 0.8
    return event


func before_each() -> void:
    _told = 0
    EventBus.tool_options_moved.connect(_count_told)


func after_each() -> void:
    if EventBus.tool_options_moved.is_connected(_count_told):
        EventBus.tool_options_moved.disconnect(_count_told)


## Four motions, one telling, and the radius the rows read is the last
## motion's rather than the first's.
func test_a_frame_of_four_motions_is_told_once() -> void:
    var surface := Fixtures.make_surface()
    var machine := Fixtures.make_bound_machine(surface)
    machine.set_active_tool(&"brush")
    var settings: Resource = machine.get_tool(&"brush").get("settings")

    machine.handle_input(_press(Vector2(100.0, 100.0)))
    var radii: Array[float] = []
    for step in range(1, MOTIONS_A_FRAME + 1):
        machine.handle_input(_motion(Vector2(100.0 + 10.0 * step, 100.0)))
        radii.append(float(settings.radius))
    assert_eq(_told, 0, "Nothing is told while the frame's motions arrive")
    assert_true(radii[0] < radii[MOTIONS_A_FRAME - 1], "and every motion still moves the radius, %s" % [radii])

    machine.tell_moved_size()
    assert_eq(_told, 1, "The frame's end tells the rows once for its four motions")
    assert_almost_eq(float(settings.radius), radii[MOTIONS_A_FRAME - 1], 1e-9, "and what they read is the last motion's radius")

    machine.tell_moved_size()
    assert_eq(_told, 1, "A frame with nothing moved tells nothing")

    machine.handle_input(_motion(Vector2(160.0, 100.0)))
    machine.handle_input(_motion(Vector2(170.0, 100.0)))
    machine.handle_input(_release(Vector2(170.0, 100.0)))
    machine.tell_moved_size()
    assert_eq(_told, 2, "The next frame's motions are told once more, the release keeping what they moved untold until then")
    Fixtures.teardown(surface, machine)


## A drag that moved nothing, pushed against the smallest size, tells nothing:
## the rows would read what they already show.
func test_a_drag_that_moves_no_size_tells_nothing() -> void:
    var surface := Fixtures.make_surface()
    var machine := Fixtures.make_bound_machine(surface)
    machine.set_active_tool(&"brush")
    var settings: Resource = machine.get_tool(&"brush").get("settings")

    machine.handle_input(_press(Vector2(100.0, 100.0)))
    machine.handle_input(_motion(Vector2(-100000.0, 100.0)))
    machine.tell_moved_size()
    _told = 0
    var smallest := float(settings.radius)
    for step in range(MOTIONS_A_FRAME):
        machine.handle_input(_motion(Vector2(-100010.0 - step, 100.0)))
    machine.tell_moved_size()
    assert_almost_eq(float(settings.radius), smallest, 1e-9, "The radius stays at its floor")
    assert_eq(_told, 0, "and the frame tells nothing")
    machine.handle_input(_release(Vector2(-100013.0, 100.0)))
    Fixtures.teardown(surface, machine)
