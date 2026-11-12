## The Local Server's dialog goes away on a press outside it, as
## the Welcome window does, and the server stays open.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## An opened dialog acts as the welcome window does and is closed when clicking
## off. The Welcome window and the top menus have the rule, and a press on the
## canvas that puts one away paints nothing. This holds the dialog to the same.
##
## **The whole route, the way the engine hands a press over**, as the Welcome window's suite
## does it: each event is emitted on the root window's `window_input` and then
## pushed into it. A real `MainCanvas` with the base modules' brush in hand and
## the dialog stand in the real root with embedding forced. The dialog is the
## one `SaCapture.connect_an_agent` makes for a real door on a known file of the
## suite's own, so the server is open and the row's tick is true or false as it
## is for a painter. Everything is asked in one frame, since a test that awaits
## drops every assertion after the await. The running app's proof is
## `scenarios/the-local-server-s-dialog-goes-away-on-a-press-outside-it.json`.
@tool
extends "res://tests/test_framework.gd"

## Real windows go in the tree, and the brush needs a RenderingDevice.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const MainCanvasScript = preload("res://render/main_canvas.gd")
const LocalServerDialog := preload("res://ui/dialogs/sa_local_server_dialog.gd")

static var scratch_known: String = SaDataRoot.path("d18-door/door.json")


## A docker over the canvas, a bare `DockerWindow` because the dialog goes away
## on a press on a docker, with the presses that reach the panel filling it.
class Docker:
    extends DockerWindow

    var pressed: int = 0

    func _init() -> void:
        name = "D18Docker"
        borderless = true
        size = Vector2i(120, 80)
        var panel := Control.new()
        panel.set_anchors_preset(Control.PRESET_FULL_RECT)
        panel.gui_input.connect(_count_press)
        add_child(panel)

    func _count_press(event: InputEvent) -> void:
        if SaPutAway.is_press(event):
            pressed += 1


var _host: Control = null
var _was_embedding: bool = false
var _canvas: Node = null
var _dialog: LocalServerDialog = null
var _copies: PackedStringArray = []


func before_each() -> void:
    if FileAccess.file_exists(scratch_known):
        DirAccess.remove_absolute(scratch_known)
    var tree := Engine.get_main_loop() as SceneTree
    _was_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    SaCursorPolicy.forget_pointer_device()
    _copies = PackedStringArray()
    LocalServerDialog.clipboard = _copy
    # Parented to an autoload, because the runner calls this from its own
    # `_ready` and a parent mid-`_ready` rejects `add_child`.
    _host = Control.new()
    _host.name = "D18Host"
    _host.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _host.size = Vector2(tree.root.size)
    EventBus.add_child(_host)
    _canvas = MainCanvasScript.new()
    _host.add_child(_canvas)
    _canvas.bind_tools(Fixtures.make_tool_registry())
    _canvas.notification(Container.NOTIFICATION_SORT_CHILDREN)
    _dialog = SaCapture.connect_an_agent(_host, scratch_known)
    _lay_out_the_dialog()


func after_each() -> void:
    SaPointerDevice.suite_pointer = null
    LocalServerDialog.clipboard = DisplayServer.clipboard_set
    if _host != null:
        _host.free()
    _host = null
    _canvas = null
    _dialog = null
    if FileAccess.file_exists(scratch_known):
        DirAccess.remove_absolute(scratch_known)
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = _was_embedding


func _copy(text: String) -> void:
    _copies.append(text)


func test_the_server_is_open_and_the_dialog_is_up_and_listens_for_a_press() -> void:
    assert_not_null(_dialog, "The dialog is made for a door that opened")
    if _dialog == null:
        return
    assert_true(_dialog.visible, "and shown")
    assert_true(_listening(), "The server listens, which is the Modules row's tick")
    assert_true(_dialog.is_in_group(SaPutAway.GROUP), "and the dialog is in the group a press puts away")
    assert_true(_dialog._put_away._heard.size() > 0, "and hears the windows a press lands on")


func test_a_press_on_the_canvas_hides_the_dialog_and_paints_nothing() -> void:
    var descriptor: Variant = _canvas.tool_machine.get_descriptor(_canvas.tool_machine.active_tool_name)
    assert_true(descriptor != null and descriptor.is_painting, "The tool in hand paints")
    var at := _on_the_canvas()
    assert_false(_dialog_rect().has_point(at), "The press lands outside the dialog, on the canvas")
    var steps := _steps()
    var version := _version()

    _press(at)
    assert_false(_dialog.visible, "The press hides the dialog")
    assert_false(_canvas._capturing_stroke, "and takes no pointer for a stroke")
    assert_false(_drawing(), "and the brush began none")
    _release(at)

    assert_eq(_steps(), steps, "The release closes no stroke, so no undo step was added")
    assert_eq(_version(), version, "and the history did not move")
    assert_eq(_canvas._held_buttons, 0, "The release let go of the press it followed")
    assert_true(_listening(), "The server is still open, its Modules row still ticked")
    assert_true(FileAccess.file_exists(scratch_known), "with its known file still written")
    assert_true(_dialog.get_parent() == _host, "and the dialog is still there, hidden and not freed")
    assert_eq(_dialog._put_away._heard.size(), 0, "A hidden dialog hears no more presses")
    _click(at)
    assert_eq(_steps(), steps + 1, "The next press paints, since nothing is open")


## A drag of the press that put the dialog away reaches the tool as a hover.
func test_a_drag_after_the_press_paints_nothing_and_its_release_is_kept_too() -> void:
    var steps := _steps()
    var at := _on_the_canvas()
    _press(at)
    for step: int in 4:
        _drag(at - Vector2(30.0 * (step + 1), 20.0 * (step + 1)))
    _release(at - Vector2(120.0, 80.0))
    assert_false(_dialog.visible, "The press hid the dialog")
    assert_false(_drawing(), "No stroke began under the drag")
    assert_eq(_steps(), steps, "and none was closed")


func test_a_right_press_on_the_canvas_hides_the_dialog_and_reaches_no_tool() -> void:
    var at := _on_the_canvas()
    _send(at, MOUSE_BUTTON_RIGHT, true)
    assert_false(_dialog.visible, "The right press hides the dialog, as it closes a menu")
    assert_eq(_canvas._held_buttons, int(MOUSE_BUTTON_MASK_RIGHT), "and the canvas keeps it from the tool")
    _send(at, MOUSE_BUTTON_RIGHT, false)
    assert_eq(_canvas._held_buttons, 0, "with its release")
    assert_true(_listening(), "The server is open still")


## The wheel scrolls and a motion hovers, so neither puts the dialog away.
func test_a_wheel_turn_or_a_motion_over_the_canvas_leaves_the_dialog_up() -> void:
    var at := _on_the_canvas()
    _send(at, MOUSE_BUTTON_WHEEL_UP, true)
    _send(at, MOUSE_BUTTON_WHEEL_UP, false)
    var motion := InputEventMouseMotion.new()
    _hand(motion, at)
    assert_true(_dialog.visible, "The dialog is up after a wheel turn and a motion")


## A press on the dialog is the dialog's, whichever way the window around it is
## asked, and a press on its copy button is that button's.
func test_a_press_on_the_dialog_leaves_it_up_and_paints_nothing() -> void:
    var steps := _steps()
    var on_it := _dialog_rect().get_center()
    assert_true(_dialog_rect().size.x > 0.0, "The dialog has a size: %s" % [_dialog_rect()])
    _click(on_it)
    assert_true(_dialog.visible, "A press on the dialog leaves it up")
    assert_eq(_steps(), steps, "and paints nothing under it")
    assert_eq(_canvas._held_buttons, 0, "with the canvas holding no button")
    assert_true(_listening(), "and the server open")


func test_a_press_on_the_copy_button_leaves_it_up_and_copies() -> void:
    var button := _copy_button_at()
    assert_true(_dialog_rect().has_point(button), "The copy button is inside the dialog: %s in %s" % [button, _dialog_rect()])
    var steps := _steps()
    _click(button)
    assert_true(_dialog.visible, "A press on the copy button leaves the dialog up")
    assert_eq(_copies.size(), 1, "and the button copied the paragraph, once")
    assert_eq(_steps(), steps, "and nothing was painted")
    assert_true(_listening(), "The server is open")


## The dialog hides and is shown again, as a painter finds it after pressing
## Modules › Local Server on a server that is open, and it goes away again.
func test_shown_again_it_keeps_a_press_on_its_copy_button_and_goes_on_a_press_outside() -> void:
    var at := _on_the_canvas()
    _click(at)
    assert_false(_dialog.visible, "The first press hid it")
    _dialog.popup_centered()
    _lay_out_the_dialog()
    assert_true(_dialog.visible, "It is shown again")
    assert_true(_dialog._put_away._heard.size() > 0, "and hears the presses again")
    var steps := _steps()

    _click(_copy_button_at())
    assert_true(_dialog.visible, "A press on its copy button leaves it up")
    assert_eq(_copies.size(), 1, "and copies")

    _click(at)
    assert_false(_dialog.visible, "A press outside it hides it again")
    assert_eq(_steps(), steps, "and paints nothing")
    assert_true(_listening(), "The server is open throughout")


## A press on a docker goes on to the docker as well, and the canvas under the
## docker never holds it.
func test_a_press_on_a_docker_hides_the_dialog_and_reaches_the_docker() -> void:
    var at := _on_the_canvas()
    var docker := Docker.new()
    docker.position = Vector2i(at) - Vector2i(60, 40)
    _host.add_child(docker)
    _dialog.hide()
    _dialog.popup_centered()
    assert_false(_dialog_rect().has_point(at), "The docker's middle is outside the dialog")
    var steps := _steps()

    _press(at)
    assert_false(_dialog.visible, "The press on the docker hides the dialog")
    assert_eq(docker.pressed, 1, "and goes on to the docker")
    assert_eq(_canvas._held_buttons, 0, "which the canvas under it does not hold")
    _release(at)
    assert_eq(_steps(), steps, "and nothing is painted")


## The canvas hears a press at the root in the order it connected, the dialog
## after it, and the other way round, and both orders paint nothing.
func test_the_press_is_kept_when_the_canvas_hears_it_after_the_dialog_went() -> void:
    var root := (Engine.get_main_loop() as SceneTree).root
    root.window_input.disconnect(_canvas._on_window_input)
    root.window_input.connect(_canvas._on_window_input)
    var steps := _steps()
    _click(_on_the_canvas())
    assert_false(_dialog.visible, "The dialog went first")
    assert_eq(_steps(), steps, "and the canvas still painted nothing")


## Closing the server frees the dialog, and a dialog freed while it listened
## leaves nothing connected to the main window.
func test_closing_the_server_frees_the_dialog_and_leaves_nothing_connected() -> void:
    var root := (Engine.get_main_loop() as SceneTree).root
    var before := root.window_input.get_connections().size()
    assert_true(SaCapture.close_the_local_server(_host), "The server closes")
    _dialog.free()
    _dialog = null
    assert_eq(root.window_input.get_connections().size(), before - 1, "and the root hears one listener fewer")
    assert_false(_listening(), "The row reads unticked")


# --- Helpers --------------------------------------------------------------------


func _listening() -> bool:
    return LocalServerDialog.listening(Engine.get_main_loop() as SceneTree)


## The dialog's containers sorted inside it, as the engine would a frame on, so
## a button has the rectangle a press can land on.
func _lay_out_the_dialog() -> void:
    for container: Node in _dialog.find_children("*", "Container", true, false):
        (container as Container).notification(Container.NOTIFICATION_SORT_CHILDREN)


func _dialog_rect() -> Rect2:
    return Rect2(Vector2(_dialog.position), Vector2(_dialog.size))


## The middle of the copy button in the main window's space. A dialog of Sara's
## is borderless, so its content starts at its position.
func _copy_button_at() -> Vector2:
    return Vector2(_dialog.position) + _dialog.copy_button.get_global_rect().get_center()


## A point of the document, near its lower right corner and inside the canvas's
## control, where no dialog and no docker stands.
func _on_the_canvas() -> Vector2:
    var shown: Rect2 = _canvas.canvas.get_global_rect().intersection(_canvas.control_node.get_global_rect())
    return shown.end - Vector2(40.0, 40.0)


func _drawing() -> bool:
    var tool_machine: ToolMachine = _canvas.tool_machine
    return tool_machine.active_tool != null and bool(tool_machine.active_tool.get("is_drawing"))


func _steps() -> int:
    var history: Object = _canvas.canvas.document.history
    return history.step_count() if history != null else -1


func _version() -> int:
    return int(_canvas.canvas.document.undo_redo.get_version())


func _click(at: Vector2) -> void:
    _press(at)
    _release(at)


func _press(at: Vector2) -> void:
    _send(at, MOUSE_BUTTON_LEFT, true)


func _release(at: Vector2) -> void:
    _send(at, MOUSE_BUTTON_LEFT, false)


## A motion with the left button held, to *at*.
func _drag(at: Vector2) -> void:
    var motion := InputEventMouseMotion.new()
    motion.button_mask = MOUSE_BUTTON_MASK_LEFT
    motion.pressure = 1.0
    _hand(motion, at)


func _send(at: Vector2, which: MouseButton, pressed: bool) -> void:
    var event := InputEventMouseButton.new()
    event.button_index = which
    event.pressed = pressed
    var mask := MOUSE_BUTTON_MASK_LEFT if which == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT
    event.button_mask = mask if pressed else 0
    _hand(event, at)


## *event* at *at*, in the main window's logical space, handed to the root the
## way `Window` hands an event the display server delivered: its input signal
## first, in the window's own space, then into the viewport.
func _hand(event: InputEventMouse, at: Vector2) -> void:
    var root := (Engine.get_main_loop() as SceneTree).root
    var to_desktop: Transform2D = SaPointerDevice.desktop_transform(root)
    SaPointerDevice.suite_pointer = to_desktop * at
    event.position = root.get_final_transform() * at
    event.global_position = event.position
    root.window_input.emit(event)
    root.push_input(event)
