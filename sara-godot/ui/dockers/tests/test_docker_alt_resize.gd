## ALT + right drag resizes a docker from anywhere in it.
##
## The corner grip is 24 logical units in one corner. It is the only way to
## resize a docker, and it is unreachable the moment the window sits against a
## screen edge or under another one, which is the case this exists for. ALT-move
## already works from anywhere, so resize matches it.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## Builds a real docker window, detached.
const REQUIRES_GPU := true


func _press(button: MouseButton, alt: bool = true) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = button
    event.pressed = true
    event.alt_pressed = alt
    return event


func _release(button: MouseButton) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = button
    event.pressed = false
    event.alt_pressed = true
    return event


# --- The arithmetic, without a window ------------------------------------------------


## Absolute rather than accumulated, for the same reason the move is: adding each
## delta and rounding throws the fraction away every event, and at 2x scale most
## deltas round to zero.
func test_the_size_follows_the_whole_drag_not_the_last_step() -> void:
    var minimum := Vector2i(80, 80)

    var grown := DockerDragHandle.resize_size(Vector2i(200, 150), Vector2(37.4, -12.6), minimum)

    assert_eq(grown, Vector2i(237, 137), "Start size plus the drag, rounded once")


## A docker smaller than its contents draws over itself, so the floor holds
## whatever the drag asks for.
func test_a_docker_cannot_be_dragged_below_its_minimum() -> void:
    var shrunk := DockerDragHandle.resize_size(Vector2i(200, 150), Vector2(-500, -500), Vector2i(80, 60))

    assert_eq(shrunk, Vector2i(80, 60), "The minimum wins over the pointer")


func test_each_axis_is_clamped_on_its_own() -> void:
    var mixed := DockerDragHandle.resize_size(Vector2i(200, 150), Vector2(120, -500), Vector2i(80, 60))

    assert_eq(mixed, Vector2i(320, 60), "Width grows while height stops at the floor")


# --- The state machine ---------------------------------------------------------------


func _handle() -> DockerDragHandle:
    var window := Window.new()
    window.size = Vector2i(200, 150)
    window.min_size = Vector2i(80, 60)
    var handle_control := Control.new()
    window.add_child(handle_control)
    var handle := DockerDragHandle.new()
    handle.bind(window, handle_control)
    return handle


func test_alt_right_starts_a_resize_and_consumes_the_press() -> void:
    var handle := _handle()

    assert_true(handle.handle_input(_press(MOUSE_BUTTON_RIGHT)), "ALT + right belongs to the resize")
    assert_true(handle._is_alt_resizing, "and starts one")
    assert_false(handle._is_alt_dragging, "without also moving the docker")

    handle._window.free()
    handle.free()


## An unconsumed right release opens a context menu over the docker that was
## just resized, which is the same class of bug as the left button firing on a
## release whose press it never saw.
func test_the_right_release_is_consumed_too() -> void:
    var handle := _handle()
    handle.handle_input(_press(MOUSE_BUTTON_RIGHT))

    assert_true(handle.handle_input(_release(MOUSE_BUTTON_RIGHT)), "The release is part of the gesture")
    assert_false(handle._is_alt_resizing, "and ends it")

    handle._window.free()
    handle.free()


func test_right_without_alt_passes_through() -> void:
    var handle := _handle()

    assert_false(handle.handle_input(_press(MOUSE_BUTTON_RIGHT, false)), "A plain right click is not ours")
    assert_false(handle._is_alt_resizing, "and starts nothing")

    handle._window.free()
    handle.free()


## Both gestures share one handler, so the wrong button must not drive the other
## one's state.
func test_moving_and_resizing_do_not_trigger_each_other() -> void:
    var handle := _handle()

    handle.handle_input(_press(MOUSE_BUTTON_LEFT))
    assert_true(handle._is_alt_dragging, "ALT + left moves")
    assert_false(handle._is_alt_resizing, "and does not resize")
    handle.handle_input(_release(MOUSE_BUTTON_LEFT))

    handle.handle_input(_press(MOUSE_BUTTON_RIGHT))
    assert_true(handle._is_alt_resizing, "ALT + right resizes")
    assert_false(handle._is_alt_dragging, "and does not move")

    handle._window.free()
    handle.free()


func test_motion_outside_either_gesture_is_left_alone() -> void:
    var handle := _handle()

    assert_false(handle.handle_input(InputEventMouseMotion.new()), "Bare motion is the docker's business")

    handle._window.free()
    handle.free()


# --- The whole gesture, corner by corner ---------------------------------------


## The drag grows away from whichever corner it started in, not only towards
## the top right. A press in the opposite corner, bottom left, pulled further
## into its own corner, grows just the same rather than shrinking.
func test_alt_right_drag_grows_away_from_whichever_corner_it_started_in() -> void:
    var handle := _handle()
    var window := handle._window
    window.position = Vector2i(100, 100)
    window.size = Vector2i(200, 150)

    var press := Vector2(window.position.x, window.position.y + window.size.y)
    DockerDragHandle.capture_pointer = press
    handle.handle_input(_press(MOUSE_BUTTON_RIGHT))
    DockerDragHandle.capture_pointer = press + Vector2(-40, 30)
    handle.handle_input(DockerDragHandle.held_motion(MOUSE_BUTTON_MASK_RIGHT))
    handle.handle_input(_release(MOUSE_BUTTON_RIGHT))
    DockerDragHandle.capture_pointer = null

    assert_true(window.size.x > 200, "Pulling further left from the bottom-left corner grows the width")
    assert_true(window.size.y > 150, "Pulling further down from the bottom-left corner grows the height")

    handle._window.free()
    handle.free()
