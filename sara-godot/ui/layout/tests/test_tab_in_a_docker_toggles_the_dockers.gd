## Tab in a docker hides the dockers whatever control holds the focus there, a
## text field bar, and a dialog keeps its own Tab.
##
## Clicking the Advanced check in Tool Options and pressing Tab must hide the
## dockers, not move the focus ring to the next button and leave six open while
## the same Tab after a click on nothing hides them all. The router must not
## give a focused control its Tab wherever the key arrives, or a docker's own
## viewport walks its ring with it. The three cases are a
## check box in a docker, a text field in a docker, and a button in a dialog.
##
## The windows are real, embedded in the root the way the app embeds a docker,
## because the fault was in which viewport held the focus and a stand-in
## viewport would have answered for whichever the test handed the router.
@tool
extends "res://tests/test_framework.gd"

var _host: Node = null
var _embedding: bool = false


## The smallest dialog Sara builds: a shell with a `content` to put a control in.
class ADialog:
    extends SaDialogWindow

    func _init() -> void:
        _init_dialog("TabTestDialog", "A dialog", Vector2i(240, 140), Vector2i(120, 80))


func _tab() -> InputEventKey:
    var key := InputEventKey.new()
    key.keycode = KEY_TAB
    key.physical_keycode = KEY_TAB
    key.pressed = true
    return key


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "TabInADockerTestHost"
    EventBus.add_child(_host)


func after_each() -> void:
    _host.free()
    (Engine.get_main_loop() as SceneTree).root.gui_embed_subwindows = _embedding


## A router that counts the toggles it is asked for, and is never in the tree,
## so it is freed by hand or the run ends with leaked objects.
func _router(toggles: Array) -> ShortcutRouter:
    var router := ShortcutRouter.new()
    router.toggle_all_dockers = func() -> void: toggles[0] += 1
    return router


## A docker window holding *control*, in the tree. The caller gives the focus,
## because a spin box has none of its own and its field is what takes it.
func _window_with(window: Window, control: Control) -> Window:
    window.size = Vector2i(200, 120)
    control.position = Vector2(10.0, 10.0)
    control.size = Vector2(120.0, 30.0)
    window.add_child(control)
    _host.add_child(window)
    return window


func test_a_focused_check_box_in_a_docker_toggles_on_tab_and_leaves_nothing_focused() -> void:
    var toggles := [0]
    var router := _router(toggles)
    var check := CheckBox.new()
    var docker := _window_with(Window.new(), check)
    check.grab_focus()
    assert_eq(docker.gui_get_focus_owner(), check, "The check box really holds the focus in the docker")

    router.handle_docker_input(_tab(), docker)

    assert_eq(toggles[0], 1, "Tab toggles the dockers with a check box focused")
    assert_null(docker.gui_get_focus_owner(), "and leaves nothing focused in the docker, so the next Tab toggles too")
    assert_true(docker.is_input_handled(), "The docker's own interface never sees the key, or its ring would walk")

    router.handle_docker_input(_tab(), docker)
    assert_eq(toggles[0], 2, "The next Tab is a toggle again")
    router.free()


func test_a_focused_text_field_keeps_its_tab() -> void:
    var toggles := [0]
    var router := _router(toggles)
    var line := LineEdit.new()
    var docker := _window_with(Window.new(), line)
    line.grab_focus()

    router.handle_docker_input(_tab(), docker)
    assert_eq(toggles[0], 0, "A line edit in a docker keeps Tab")
    assert_eq(docker.gui_get_focus_owner(), line, "and keeps the focus")
    router.free()

    toggles[0] = 0
    router = _router(toggles)
    var spin := SpinBox.new()
    var second := _window_with(Window.new(), spin)
    var field := spin.get_line_edit()
    field.grab_focus()
    assert_eq(second.gui_get_focus_owner(), field, "The field inside a spin box holds the focus")
    router.handle_docker_input(_tab(), second)
    assert_eq(toggles[0], 0, "and keeps Tab as well")
    router.free()

    toggles[0] = 0
    router = _router(toggles)
    var text := TextEdit.new()
    var third := _window_with(Window.new(), text)
    text.grab_focus()
    router.handle_docker_input(_tab(), third)
    assert_eq(toggles[0], 0, "and so does a text edit")
    router.free()


func test_a_dialogs_focused_button_keeps_its_tab() -> void:
    var toggles := [0]
    var router := _router(toggles)
    var button := Button.new()
    var dialog := ADialog.new()
    dialog.content.add_child(button)
    _host.add_child(dialog)
    button.grab_focus()
    assert_eq(dialog.gui_get_focus_owner(), button, "The button really holds the focus in the dialog")

    router.handle_docker_input(_tab(), dialog)

    assert_eq(toggles[0], 0, "A dialog is not a docker, so its Tab does not toggle them")
    assert_eq(dialog.gui_get_focus_owner(), button, "and its button keeps the focus")
    assert_false(dialog.is_input_handled(), "The key stays the dialog's own")
    router.free()


## The main window keeps today's rule: a focused button has the Tab, and nothing
## focused means the mode.
func test_the_main_window_keeps_a_focused_buttons_tab() -> void:
    var toggles := [0]
    var router := _router(toggles)
    var viewport := SubViewport.new()
    _host.add_child(viewport)
    var button := Button.new()
    viewport.add_child(button)
    button.grab_focus()

    router.handle_viewport_input(_tab(), viewport)
    assert_eq(toggles[0], 0, "A button focused in the main window keeps Tab")

    viewport.gui_release_focus()
    router.handle_viewport_input(_tab(), viewport)
    assert_eq(toggles[0], 1, "and nothing focused is the mode")
    router.free()
