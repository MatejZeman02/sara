## A click on a title bar leaves the layout alone.
##
## One click on a docker's title bar with nothing moved emitted
## `docker_layout_changed`, which saves and forks the shipped preset, so the
## Workspace page read "default (custom)" and Window › Layouts grew a fifth row.
## A dialog's title bar did the same through the same handle. The handle now
## announces a release only when its window's rectangle changed since the press,
## and a dialog's handle never announces one.
##
## Every gesture goes in through the title bar's own `gui_input` or through
## `handle_input`, the two doors the running app uses, with the pointer given
## through `capture_pointer` because the handle reads the live one. The app's
## own listeners are set aside for each test and put back after it, so a drag
## here never saves the layout of the run.
@tool
extends "res://tests/test_framework.gd"


class StubDialog:
    extends SaDialogWindow

    func _init() -> void:
        _init_dialog("U4StubDialog", "Stub", Vector2i(320, 200), Vector2i(200, 120))


var _announced: Array[int] = [0]
var _listeners: Array = []
var _previous_embedding: bool = true
var _host: Node = null


func _count() -> void:
    _announced[0] += 1


func before_each() -> void:
    _announced[0] = 0
    _listeners = EventBus.docker_layout_changed.get_connections()
    for listener: Dictionary in _listeners:
        EventBus.docker_layout_changed.disconnect(listener["callable"])
    EventBus.docker_layout_changed.connect(_count)
    var tree := Engine.get_main_loop() as SceneTree
    _previous_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "U4DialogHost"
    EventBus.add_child(_host)


func after_each() -> void:
    DockerDragHandle.capture_pointer = null
    if _host != null:
        _host.free()
        _host = null
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = _previous_embedding
    EventBus.docker_layout_changed.disconnect(_count)
    for listener: Dictionary in _listeners:
        EventBus.docker_layout_changed.connect(listener["callable"], listener["flags"])


func _button(pressed: bool, alt: bool = false) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    event.alt_pressed = alt
    return event


## A press, one motion to *to* and a release on *title_bar*, which is the path a
## real click on a docker's title bar takes.
func _title_bar_gesture(title_bar: Control, from: Vector2, to: Vector2) -> void:
    DockerDragHandle.capture_pointer = from
    title_bar.gui_input.emit(_button(true))
    DockerDragHandle.capture_pointer = to
    title_bar.gui_input.emit(InputEventMouseMotion.new())
    title_bar.gui_input.emit(_button(false))
    DockerDragHandle.capture_pointer = null


## The same through the ALT gesture, which moves a docker from anywhere in it.
func _alt_gesture(handle: DockerDragHandle, from: Vector2, to: Vector2) -> void:
    DockerDragHandle.capture_pointer = from
    handle.handle_input(_button(true, true))
    DockerDragHandle.capture_pointer = to
    handle.handle_input(DockerDragHandle.held_motion(MOUSE_BUTTON_MASK_LEFT))
    handle.handle_input(_button(false, true))
    DockerDragHandle.capture_pointer = null


func test_a_click_on_a_dockers_title_bar_announces_nothing() -> void:
    var window := Window.new()
    window.position = Vector2i(300, 200)
    window.size = Vector2i(200, 150)
    var title_bar := Control.new()
    window.add_child(title_bar)
    var handle := DockerDragHandle.new()
    handle.bind(window, title_bar)

    _title_bar_gesture(title_bar, Vector2(340, 210), Vector2(340, 210))

    assert_eq(window.position, Vector2i(300, 200), "A click with nothing moved leaves the docker where it was")
    assert_eq(_announced[0], 0, "and does not tell the app the layout changed, which is what forked it")
    window.free()
    handle.free()


func test_a_drag_of_a_dockers_title_bar_announces_once() -> void:
    var window := Window.new()
    window.position = Vector2i(300, 200)
    window.size = Vector2i(200, 150)
    var title_bar := Control.new()
    window.add_child(title_bar)
    var handle := DockerDragHandle.new()
    handle.bind(window, title_bar)

    _title_bar_gesture(title_bar, Vector2(340, 210), Vector2(400, 260))

    assert_eq(window.position, Vector2i(360, 250), "The drag moves the docker by what the pointer moved")
    assert_eq(_announced[0], 1, "and the release announces the layout change exactly once")
    window.free()
    handle.free()


## A drag that comes back to where it began is a click as far as the layout is
## concerned: the rectangle is compared, not the path.
func test_a_drag_that_returns_home_announces_nothing() -> void:
    var window := Window.new()
    window.position = Vector2i(300, 200)
    window.size = Vector2i(200, 150)
    var title_bar := Control.new()
    window.add_child(title_bar)
    var handle := DockerDragHandle.new()
    handle.bind(window, title_bar)

    DockerDragHandle.capture_pointer = Vector2(340, 210)
    title_bar.gui_input.emit(_button(true))
    DockerDragHandle.capture_pointer = Vector2(420, 290)
    title_bar.gui_input.emit(InputEventMouseMotion.new())
    DockerDragHandle.capture_pointer = Vector2(340, 210)
    title_bar.gui_input.emit(InputEventMouseMotion.new())
    title_bar.gui_input.emit(_button(false))

    assert_eq(_announced[0], 0, "The docker ended where it started, so nothing changed")
    window.free()
    handle.free()


func test_an_alt_click_announces_nothing_and_an_alt_drag_once() -> void:
    var window := Window.new()
    window.position = Vector2i(300, 200)
    window.size = Vector2i(200, 150)
    var title_bar := Control.new()
    window.add_child(title_bar)
    var handle := DockerDragHandle.new()
    handle.bind(window, title_bar)

    _alt_gesture(handle, Vector2(380, 260), Vector2(380, 260))
    assert_eq(_announced[0], 0, "An ALT click with nothing moved is not a layout edit")

    _alt_gesture(handle, Vector2(380, 260), Vector2(300, 300))
    assert_eq(_announced[0], 1, "An ALT drag that moved the docker is one")
    window.free()
    handle.free()


func test_a_dialogs_title_bar_never_announces() -> void:
    var dialog := StubDialog.new()
    dialog.visible = false
    _host.add_child(dialog)
    var start := dialog.position
    var grab := Vector2(start) + Vector2(40, 10)

    _title_bar_gesture(dialog.drag_handle, grab, grab)
    assert_eq(_announced[0], 0, "A click on a dialog's title bar says nothing about the layout")

    _title_bar_gesture(dialog.drag_handle, grab, grab + Vector2(90, 70))
    assert_eq(dialog.position, start + Vector2i(90, 70), "The dialog still moves with its title bar")
    assert_eq(_announced[0], 0, "but a dialog is not part of the layout, so the drag announces nothing")
