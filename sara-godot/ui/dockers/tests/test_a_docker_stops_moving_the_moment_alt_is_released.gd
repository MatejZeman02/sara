## A docker stops moving the moment ALT is released.
##
## An ALT drag ran until the button's release, so a release of ALT before the
## button, or a release the window never heard because the pointer was over
## another window or the focus left, kept the docker following the pointer.
## The gesture now ends where the docker stands when ALT goes up, when the focus
## leaves, and when a motion arrives with no button down.
##
## Every gesture goes in through `handle_input`, the door the running app's
## `_input` uses, with the pointer given through `capture_pointer`.
extends "res://tests/test_framework.gd"


func after_each() -> void:
    DockerDragHandle.capture_pointer = null


func _handle() -> DockerDragHandle:
    var window := Window.new()
    window.position = Vector2i(300, 200)
    window.size = Vector2i(200, 150)
    window.min_size = Vector2i(80, 60)
    var control := Control.new()
    window.add_child(control)
    var handle := DockerDragHandle.new(false)
    handle.bind(window, control)
    return handle


func _press(button: MouseButton) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = button
    event.pressed = true
    event.alt_pressed = true
    return event


## A motion with *mask* held, ALT down as *alt* says.
func _motion(mask: int, alt: bool = true) -> InputEventMouseMotion:
    var event := InputEventMouseMotion.new()
    event.button_mask = mask
    event.alt_pressed = alt
    return event


func _alt_up() -> InputEventKey:
    var event := InputEventKey.new()
    event.keycode = KEY_ALT
    event.pressed = false
    return event


## Presses at (340, 210) and follows one motion 40 units right, so the gesture is
## live and has moved, and answers the docker's rectangle there.
func _begin(handle: DockerDragHandle, button: MouseButton, mask: int) -> Rect2i:
    DockerDragHandle.capture_pointer = Vector2(340, 210)
    handle.handle_input(_press(button))
    DockerDragHandle.capture_pointer = Vector2(380, 230)
    handle.handle_input(_motion(mask))
    return Rect2i(handle._window.position, handle._window.size)


func _rect(handle: DockerDragHandle) -> Rect2i:
    return Rect2i(handle._window.position, handle._window.size)


func test_the_drag_follows_while_alt_and_the_button_are_held() -> void:
    var handle := _handle()

    var moved := _begin(handle, MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MASK_LEFT)

    assert_eq(moved.position, Vector2i(340, 220), "The held drag follows the pointer")
    handle._window.free()
    handle.free()


func test_alt_released_with_the_button_down_stops_the_drag() -> void:
    var handle := _handle()
    var at := _begin(handle, MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MASK_LEFT)

    assert_false(handle.handle_input(_alt_up()), "ALT's release is not consumed, the shortcuts read it too")
    DockerDragHandle.capture_pointer = Vector2(500, 400)
    handle.handle_input(_motion(MOUSE_BUTTON_MASK_LEFT, false))

    assert_false(handle._is_alt_dragging, "ALT's release ends the drag")
    assert_eq(_rect(handle), at, "and the docker stays where ALT left it")
    handle._window.free()
    handle.free()


func test_alt_released_with_the_button_down_stops_the_resize() -> void:
    var handle := _handle()
    var at := _begin(handle, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MASK_RIGHT)

    handle.handle_input(_alt_up())
    DockerDragHandle.capture_pointer = Vector2(500, 400)
    handle.handle_input(_motion(MOUSE_BUTTON_MASK_RIGHT, false))

    assert_false(handle._is_alt_resizing, "ALT's release ends the resize")
    assert_eq(_rect(handle), at, "and the docker keeps its size")
    handle._window.free()
    handle.free()


func test_a_focus_lost_stops_the_drag() -> void:
    var handle := _handle()
    var at := _begin(handle, MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MASK_LEFT)

    handle._window.focus_exited.emit()
    DockerDragHandle.capture_pointer = Vector2(500, 400)
    handle.handle_input(_motion(MOUSE_BUTTON_MASK_LEFT))

    assert_false(handle._is_alt_dragging, "The window's focus lost ends the drag")
    assert_eq(_rect(handle), at, "and the docker stays")
    handle._window.free()
    handle.free()


func test_the_application_losing_focus_stops_the_drag() -> void:
    var handle := _handle()
    var at := _begin(handle, MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MASK_LEFT)

    handle.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
    DockerDragHandle.capture_pointer = Vector2(500, 400)
    handle.handle_input(_motion(MOUSE_BUTTON_MASK_LEFT))

    assert_false(handle._is_alt_dragging, "Sara losing the focus ends the drag")
    assert_eq(_rect(handle), at, "and the docker stays")
    handle._window.free()
    handle.free()


func test_a_motion_with_no_button_down_stops_the_drag() -> void:
    var handle := _handle()
    var at := _begin(handle, MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MASK_LEFT)

    DockerDragHandle.capture_pointer = Vector2(500, 400)
    assert_false(handle.handle_input(_motion(0)), "The buttonless motion is the docker's business again")

    assert_false(handle._is_alt_dragging, "A motion with no button down ends the drag")
    assert_eq(_rect(handle), at, "and the docker does not follow it")
    DockerDragHandle.capture_pointer = Vector2(520, 420)
    handle.handle_input(_motion(0))
    assert_eq(_rect(handle), at, "nor any motion after it")
    handle._window.free()
    handle.free()


func test_a_motion_with_no_button_down_stops_the_resize() -> void:
    var handle := _handle()
    var at := _begin(handle, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MASK_RIGHT)

    DockerDragHandle.capture_pointer = Vector2(500, 400)
    handle.handle_input(_motion(0))

    assert_false(handle._is_alt_resizing, "A motion with no button down ends the resize")
    assert_eq(_rect(handle), at, "and the docker keeps its size")
    handle._window.free()
    handle.free()


## The button's release that follows ALT's is consumed as the gesture's own
## would have been, or a Button under the pointer fires. The next press is a
## gesture of its own.
func test_the_button_s_release_after_alt_s_is_still_consumed() -> void:
    var handle := _handle()
    _begin(handle, MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MASK_LEFT)
    handle.handle_input(_alt_up())

    var release := InputEventMouseButton.new()
    release.button_index = MOUSE_BUTTON_LEFT
    release.pressed = false

    assert_true(handle.handle_input(release), "The owed release is consumed")
    assert_false(handle.handle_input(release), "and only that one")
    handle._window.free()
    handle.free()


## A motion that carries no ALT means ALT's release went to another window.
func test_a_motion_without_alt_stops_the_drag() -> void:
    var handle := _handle()
    var at := _begin(handle, MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MASK_LEFT)

    DockerDragHandle.capture_pointer = Vector2(500, 400)
    handle.handle_input(_motion(MOUSE_BUTTON_MASK_LEFT, false))

    assert_false(handle._is_alt_dragging, "A motion without ALT ends the drag")
    assert_eq(_rect(handle), at, "and the docker stays")
    handle._window.free()
    handle.free()
