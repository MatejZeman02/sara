## A docker's maximise button says Restore while the docker is maximised.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## "Maximize this docker" on hover whether the docker was
## maximised or not, "wrong exactly half the time a painter reads it", because
## the words were set once at build. The press and the Ctrl+Space chord both
## flip the state, so both have to flip the words.
##
## The chord goes through a real `ShortcutRouter` and a real key event, with the
## window embedded and given the focus the way `test_the_chord_over_an_open_list.gd`
## gives it: without embedding a Window added to the tree maps a real OS window
## and the run blocks until the watchdog fires.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

const MAXIMISE := "Maximize this docker."
const RESTORE := "Restore this docker."

var _was_embedding: bool = false
var _host: Node = null


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _was_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "N122Host"
    EventBus.add_child(_host)


func after_each() -> void:
    if _host != null:
        _host.free()
        _host = null
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = _was_embedding


## A window with the button in a row of its own, the shape a docker's drag bar
## gives it, so `toggle` finds the button by name the way it finds a docker's.
func _window_with_the_button(in_tree: bool) -> Window:
    var window := Window.new()
    window.title = "Scratch"
    window.position = Vector2i(200, 120)
    window.size = Vector2i(320, 240)
    if in_tree:
        _host.add_child(window)
    var row := SaMake.row(window, "DragBarRow", SaTheme.GAP_TIGHT)
    SaDockerMaximise.build_button(row, window)
    return window


func _button_of(window: Window) -> Button:
    return window.find_child(SaDockerMaximise.BUTTON_NAME, true, false) as Button


func _ctrl_space() -> InputEventKey:
    var event := InputEventKey.new()
    event.keycode = KEY_SPACE
    event.physical_keycode = KEY_SPACE
    event.ctrl_pressed = true
    event.pressed = true
    return event


func test_a_press_flips_the_words_both_ways() -> void:
    var window := _window_with_the_button(false)
    var button := _button_of(window)

    assert_eq(button.tooltip_text, MAXIMISE, "a docker in its place offers the maximise")
    button.pressed.emit()
    assert_true(SaDockerMaximise.is_maximised(window), "the press fills the host")
    assert_eq(button.tooltip_text, RESTORE, "and the button then offers the way back")
    button.pressed.emit()
    assert_false(SaDockerMaximise.is_maximised(window), "a second press puts it back")
    assert_eq(button.tooltip_text, MAXIMISE, "and the words go back with it")
    window.free()


## The half that was wrong: the chord never touched the button, so a
## docker maximised from the keyboard went on offering the maximise.
func test_the_chord_flips_the_words_both_ways() -> void:
    var window := _window_with_the_button(true)
    var button := _button_of(window)
    var router := ShortcutRouter.new()
    router.canvas_provider = func() -> SaCanvas: return null
    router.tool_machine_provider = func() -> ToolMachine: return null
    router.bind_commands(Fixtures.make_registries().commands)
    _host.add_child(router)
    window.grab_focus()
    var tree := Engine.get_main_loop() as SceneTree
    assert_eq(SaDockerMaximise.focused_window(tree), window, "the scratch window holds the keyboard")

    assert_true(router.handle(_ctrl_space()), "Ctrl+Space is taken")
    assert_true(SaDockerMaximise.is_maximised(window), "and fills the host with the focused window")
    assert_eq(button.tooltip_text, RESTORE, "so the button offers the way back without being pressed")
    assert_true(router.handle(_ctrl_space()), "the same chord again")
    assert_false(SaDockerMaximise.is_maximised(window), "puts the window back")
    assert_eq(button.tooltip_text, MAXIMISE, "and the button offers the maximise again")


## A button built while its window is already maximised starts on the words for
## the state it finds, because the build asks the same function the toggle does.
func test_a_button_built_on_a_maximised_window_starts_on_restore() -> void:
    var window := Window.new()
    window.size = Vector2i(200, 160)
    SaDockerMaximise.toggle(window)
    var row := SaMake.row(window, "DragBarRow", SaTheme.GAP_TIGHT)
    var button := SaDockerMaximise.build_button(row, window)
    assert_eq(button.tooltip_text, RESTORE, "the words follow the state, not the build")
    window.free()


## A dialog has the chord and no button, so the toggle finds nothing and says
## the sentence it always said.
func test_a_window_with_no_button_toggles_as_before() -> void:
    var window := Window.new()
    window.size = Vector2i(200, 160)
    assert_true(SaDockerMaximise.toggle(window).contains("fills"), "the maximise runs with no button to write")
    assert_true(SaDockerMaximise.toggle(window).contains("back at"), "and so does the restore")
    window.free()
