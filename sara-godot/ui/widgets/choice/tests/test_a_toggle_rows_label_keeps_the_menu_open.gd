## A press on a toggle row's label presses its box and leaves the menu open.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The rule "A toggle row keeps the menu open,
## because marking several is the gesture" must hold for the box and not for the
## label: `SaChoicePopup._on_row_pressed` hid the list on every label press, so a
## painter showing three dockers opened the Dockers menu three times unless they
## aimed at a box. A label press on a row with a box now presses the box, and
## every caller hears it on `marked`, the signal it already answers a box with.
##
## The blend list is the one list whose box is not the row's state: its label
## chooses a mode and its box keeps a favourite. It is built with `label_ticks`
## false and its label still chooses and closes, which the last test holds.
##
## Opened embedded under a host, the way `test_choice_popup.gd` opens one, so
## `visible` is the list a painter sees rather than a detached window's flag.
extends "res://tests/test_framework.gd"

var _host: Node = null
var _anchor: Control = null
var _was_embedding := false


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _was_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "D80ToggleHost"
    EventBus.add_child(_host)
    _anchor = Control.new()
    _anchor.size = Vector2(120.0, 24.0)
    _host.add_child(_anchor)


func after_each() -> void:
    _host.free()
    _host = null
    _anchor = null
    (Engine.get_main_loop() as SceneTree).root.gui_embed_subwindows = _was_embedding


## Two toggle rows and a plain one, the Dockers menu's shape: dockers ticked
## beside a layout that loads.
func _open(popup: SaChoicePopup, chosen: Array[StringName], marked: Array) -> SaChoicePopup:
    popup.clear()
    popup.add_row(&"toolbox", "ToolBox", true, true)
    popup.add_row(&"layers", "Layers", true, false)
    popup.add_gap()
    popup.add_row(&"layout", "Default")
    popup.chosen.connect(func(id: StringName) -> void: chosen.append(id))
    popup.marked.connect(func(id: StringName, on: bool) -> void: marked.append([id, on]))
    _host.add_child(popup)
    popup.open_under(_anchor)
    return popup


func test_a_press_on_a_toggle_rows_label_flips_it_and_leaves_the_list_open() -> void:
    var chosen: Array[StringName] = []
    var marked: Array = []
    var popup := _open(SaChoicePopup.new(), chosen, marked)
    assert_true(popup.visible, "The list is open")

    assert_true(popup.press_row(&"toolbox"), "The ToolBox row's label takes the press")

    assert_true(popup.visible, "and the list is still open")
    assert_false(popup.is_checked(&"toolbox"), "and the row flipped off")
    assert_eq(marked, [[&"toolbox", false]], "The caller hears it as the box, with the state the box now has")
    assert_true(chosen.is_empty(), "and never as a choice")

    popup.press_row(&"layers")
    assert_true(popup.visible, "A second toggle in the same visit leaves it open too")
    assert_true(popup.is_checked(&"layers"), "and flips its own row")

    popup.press_row(&"toolbox")
    assert_true(popup.is_checked(&"toolbox"), "Pressing the first label again flips it back on")
    assert_eq(marked.size(), 3, "one `marked` per press")


func test_the_box_and_the_label_are_one_act() -> void:
    var chosen: Array[StringName] = []
    var marked: Array = []
    var popup := _open(SaChoicePopup.new(), chosen, marked)

    popup.press_check(&"layers")
    popup.press_row(&"layers")

    assert_true(popup.visible, "A box then a label leaves the list open")
    assert_false(popup.is_checked(&"layers"), "and the two presses undo each other")
    assert_eq(marked, [[&"layers", true], [&"layers", false]], "which the caller hears as two marks alike")


func test_a_plain_rows_label_still_chooses_and_closes() -> void:
    var chosen: Array[StringName] = []
    var marked: Array = []
    var popup := _open(SaChoicePopup.new(), chosen, marked)

    popup.press_row(&"layout")

    assert_eq(chosen, [&"layout"] as Array[StringName], "A row with no box is a choice")
    assert_false(popup.visible, "and the list closes behind it")
    assert_true(marked.is_empty(), "with no mark")


func test_a_list_whose_box_is_a_favourite_still_chooses_from_the_label() -> void:
    var chosen: Array[StringName] = []
    var marked: Array = []
    var popup := _open(SaChoicePopup.new(false), chosen, marked)

    popup.press_row(&"layers")

    assert_eq(chosen, [&"layers"] as Array[StringName], "The label chooses")
    assert_false(popup.visible, "and closes the list")
    assert_false(popup.is_checked(&"layers"), "and leaves the favourite box as it was")
    assert_true(marked.is_empty(), "with no mark")


func test_the_blend_list_is_built_with_a_label_that_chooses() -> void:
    var button := BlendModeButton.new()
    assert_false(button.popup._label_ticks, "The blend list's label chooses, its box being a favourite")
    button.free()
