## Escape closes a list after one of its ticks showed a window.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Ticking Undo History in the Window menu, and the menu stayed open through
## two Escapes and closed only on a click on its title. The Window menu answers
## a tick by showing the docker, and an embedded window shown takes the
## subwindow focus as it is registered, so the Escape went to the docker and
## never reached the list. A probe of the running app read the same: after the
## tick the docker held the focus and the list did not. The list now takes the
## keyboard back after its caller has answered a tick.
##
## Embedded under a host, the way `test_a_toggle_rows_label_keeps_the_menu_open.gd`
## opens a list, because a window added to the tree without embedding maps a
## real OS window. The Escape is pushed into the root viewport, which hands it
## to whichever embedded window holds the focus, the path a key takes from the
## keyboard.
extends "res://tests/test_framework.gd"

var _host: Node = null
var _anchor: Control = null
var _shown: Window = null
var _was_embedding := false


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _was_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "N21EscapeHost"
    EventBus.add_child(_host)
    _anchor = Control.new()
    _anchor.size = Vector2(120.0, 24.0)
    _host.add_child(_anchor)
    # The docker a tick shows, hidden until the tick and placed clear of the list.
    _shown = Window.new()
    _shown.name = "N21Docker"
    _shown.position = Vector2i(600, 200)
    _shown.size = Vector2i(240, 340)
    _shown.visible = false
    _host.add_child(_shown)


func after_each() -> void:
    _host.free()
    _host = null
    _anchor = null
    _shown = null
    (Engine.get_main_loop() as SceneTree).root.gui_embed_subwindows = _was_embedding


## Two docker rows, the Window menu's shape, the second ticked as its docker
## is shown, and a caller that answers a tick by showing or hiding the docker
## the way `MainDockers.toggle_docker` does.
func _open() -> SaChoicePopup:
    var popup := SaChoicePopup.new()
    popup.clear()
    popup.add_row(&"docker_0", "Layers", true, true)
    popup.add_row(&"docker_9", "Undo History", true, _shown.visible)
    popup.marked.connect(func(_id: StringName, on: bool) -> void: _shown.visible = on)
    _host.add_child(popup)
    popup.open_under(_anchor)
    return popup


func _escape() -> void:
    var escape := InputEventKey.new()
    escape.keycode = KEY_ESCAPE
    escape.physical_keycode = KEY_ESCAPE
    escape.pressed = true
    var root := (Engine.get_main_loop() as SceneTree).root
    root.push_input(escape)
    var release := escape.duplicate() as InputEventKey
    release.pressed = false
    root.push_input(release)


func test_escape_closes_the_list_after_a_tick_that_showed_a_window() -> void:
    var popup := _open()
    assert_true(popup.visible, "The list is open")
    assert_true(popup.has_focus(), "and holds the keyboard")

    assert_true(popup.press_row(&"docker_9"), "The Undo History row takes the press")
    assert_true(_shown.visible, "The tick showed the docker")
    assert_true(popup.visible, "and the list stayed open, as a tick leaves it")
    assert_true(popup.has_focus(), "The list has the keyboard back from the window the tick showed")
    assert_false(_shown.has_focus(), "and the docker does not hold it")

    _escape()
    assert_false(popup.visible, "One Escape closes the list")
    assert_true(_shown.visible, "and the docker the tick showed stays shown")


## A tick that hid a window takes nothing from the list, and Escape closes it
## just the same.
func test_escape_closes_the_list_after_a_tick_that_hid_a_window() -> void:
    _shown.visible = true
    var popup := _open()
    popup.press_row(&"docker_9")
    assert_false(_shown.visible, "The tick hid the docker")
    assert_true(popup.has_focus(), "and the list kept the keyboard")
    _escape()
    assert_false(popup.visible, "One Escape closes the list")
