## A touch on a docker's title raises no script error.
##
## Every log of a tablet session held `Invalid access to property or
## key 'alt_pressed' on a base object of type 'InputEventScreenTouch'` from the
## handle's `_input`, because the ALT gesture read a modifier off a touch, which
## carries none. The handle now reads the modifier only from an event that has
## one, and a touch on the title moves the docker as a left press does.
##
## The touch goes in through both doors the running app uses, `handle_input`
## first as `_input` does and then the title bar's own `gui_input`, with the
## pointer given through `capture_pointer` because the handle reads the live one.
## The app's layout listeners are set aside, so the drag saves nothing.
@tool
extends "res://tests/test_framework.gd"

var _listeners: Array = []


func _ignore() -> void:
    pass


func before_each() -> void:
    _listeners = EventBus.docker_layout_changed.get_connections()
    for listener: Dictionary in _listeners:
        EventBus.docker_layout_changed.disconnect(listener["callable"])
    EventBus.docker_layout_changed.connect(_ignore)


func after_each() -> void:
    DockerDragHandle.capture_pointer = null
    EventBus.docker_layout_changed.disconnect(_ignore)
    for listener: Dictionary in _listeners:
        EventBus.docker_layout_changed.connect(listener["callable"], listener["flags"])


func _touch(pressed: bool, at: Vector2) -> InputEventScreenTouch:
    var event := InputEventScreenTouch.new()
    event.pressed = pressed
    event.position = at
    return event


func _drag(at: Vector2, relative: Vector2) -> InputEventScreenDrag:
    var event := InputEventScreenDrag.new()
    event.position = at
    event.relative = relative
    return event


## One event as the running app delivers it: to `_input` first, and to the
## title bar only when `_input` did not take it.
func _deliver(handle: DockerDragHandle, title_bar: Control, event: InputEvent) -> bool:
    var taken := handle.handle_input(event)
    if not taken:
        title_bar.gui_input.emit(event)
    return taken


func test_a_touch_drag_on_a_title_moves_the_docker_with_no_error() -> void:
    var window := Window.new()
    window.position = Vector2i(300, 200)
    window.size = Vector2i(200, 150)
    var title_bar := Control.new()
    window.add_child(title_bar)
    var handle := DockerDragHandle.new()
    handle.bind(window, title_bar)

    var errors := SaErrorCatcher.new()
    OS.add_logger(errors)
    var taken: Array[bool] = []
    DockerDragHandle.capture_pointer = Vector2(340, 210)
    taken.append(_deliver(handle, title_bar, _touch(true, Vector2(40, 10))))
    DockerDragHandle.capture_pointer = Vector2(400, 260)
    taken.append(_deliver(handle, title_bar, _drag(Vector2(100, 60), Vector2(60, 50))))
    taken.append(_deliver(handle, title_bar, _touch(false, Vector2(100, 60))))
    DockerDragHandle.capture_pointer = null
    OS.remove_logger(errors)

    var caught := errors.described([SaErrorCatcher.ERROR, SaErrorCatcher.SCRIPT])
    assert_eq(caught, PackedStringArray(), "No script error reads a modifier off the touch")
    assert_eq(taken, [false, false, false] as Array[bool], "The ALT gesture takes none of a touch")
    assert_eq(window.position, Vector2i(360, 250), "The touch drag moves the docker as a left press drag does")
    window.free()
    handle.free()


func test_a_mouse_alt_drag_still_moves_the_docker() -> void:
    var window := Window.new()
    window.position = Vector2i(300, 200)
    window.size = Vector2i(200, 150)
    var title_bar := Control.new()
    window.add_child(title_bar)
    var handle := DockerDragHandle.new()
    handle.bind(window, title_bar)

    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    press.alt_pressed = true
    var release := press.duplicate() as InputEventMouseButton
    release.pressed = false
    DockerDragHandle.capture_pointer = Vector2(340, 210)
    var took_press := handle.handle_input(press)
    DockerDragHandle.capture_pointer = Vector2(380, 230)
    handle.handle_input(DockerDragHandle.held_motion(MOUSE_BUTTON_MASK_LEFT))
    var took_release := handle.handle_input(release)
    DockerDragHandle.capture_pointer = null

    assert_true(took_press and took_release, "The ALT gesture still takes a mouse press and its release")
    assert_eq(window.position, Vector2i(340, 220), "and moves the docker by what the pointer moved")
    window.free()
    handle.free()
