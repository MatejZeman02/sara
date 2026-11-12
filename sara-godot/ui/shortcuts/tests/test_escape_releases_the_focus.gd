## Escape lets go of whatever holds the keyboard, and closes nothing.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Escape closes no dialog or docker, because a selected dropdown would then
## open on Space instead of panning.
##
## So the key has three meanings and this is the order they are read in: a
## tool with a gesture in the air keeps it, then a focused text box lets go, then
## anything else focused lets go. A window is never touched, which
## `ui/shortcuts/tests/test_escape_closes_docker.gd` reads from the docker side and
## `ui/dialogs/tests/test_escape_cancels_the_edit.gd` from the dialog side.
##
## A `SubViewport` stands in for a window, for the reason
## `ui/shortcuts/tests/test_text_box_keyboard.gd` records: a `Window` added to the tree in
## a headless run hangs the suite, and a `SubViewport` is a `Viewport` with a
## focus owner of its own, which is every gate the router asks. The real
## Preferences window is driven by
## `scenarios/escape-cancels-never-closes.json`.
extends "res://tests/test_framework.gd"


## A tool with a pending gesture, which is what the router asks `preview_shape`
## about.
class GestureTool:
    extends ToolState

    var shape: Dictionary = {}

    func preview_shape() -> Dictionary:
        return shape


func _escape() -> InputEventKey:
    var event := InputEventKey.new()
    event.keycode = KEY_ESCAPE
    event.physical_keycode = KEY_ESCAPE
    event.pressed = true
    return event


## A viewport in the tree with a dropdown, a plain button and a text box in it,
## which is the three kinds of focus owner. `EventBus` is
## the host every other suite parks one under.
func _bench() -> Dictionary:
    var host := Node.new()
    host.name = "N3EscapeTestHost"
    EventBus.add_child(host)
    var viewport := SubViewport.new()
    host.add_child(viewport)
    var dropdown := OptionButton.new()
    dropdown.name = "N3Dropdown"
    dropdown.add_item("Normal")
    dropdown.add_item("Multiply")
    viewport.add_child(dropdown)
    var button := Button.new()
    button.name = "N3Button"
    viewport.add_child(button)
    var field := LineEdit.new()
    field.name = "N3Field"
    viewport.add_child(field)
    var router := ShortcutRouter.new()
    router.canvas_provider = func() -> SaCanvas: return null
    router.tool_machine_provider = func() -> ToolMachine: return null
    return {"host": host, "viewport": viewport, "dropdown": dropdown, "button": button, "field": field, "router": router}


func _teardown(bench: Dictionary) -> void:
    (bench["router"] as ShortcutRouter).free()
    (bench["host"] as Node).free()


## **The motivating case.** An `OptionButton` keeps the focus after it has
## been picked from, and `ui_accept` is Space, so the pan quick key reopened the
## list. Escape hands the keyboard back and the next Space is the tool's again.
func test_escape_releases_a_focused_dropdown() -> void:
    var bench := _bench()
    var router := bench["router"] as ShortcutRouter
    var viewport := bench["viewport"] as SubViewport
    var dropdown := bench["dropdown"] as OptionButton
    dropdown.grab_focus()
    assert_eq(viewport.gui_get_focus_owner(), dropdown, "the dropdown really holds the keyboard")

    router.handle_viewport_input(_escape(), viewport)

    assert_eq(viewport.gui_get_focus_owner(), null, "and Escape hands it back")
    _teardown(bench)


## Any focused control, not the dropdown alone. A button that took the focus off
## a click swallows Space the same way, and the rule is about the focus rather
## than about one class.
func test_escape_releases_a_focused_button() -> void:
    var bench := _bench()
    var router := bench["router"] as ShortcutRouter
    var viewport := bench["viewport"] as SubViewport
    var button := bench["button"] as Button
    button.grab_focus()

    router.handle_viewport_input(_escape(), viewport)

    assert_eq(viewport.gui_get_focus_owner(), null, "a plain button lets go too")
    _teardown(bench)


## A text box is the same outcome by the earlier branch. Asserted here so the two branches cannot drift apart.
func test_escape_releases_a_focused_text_box() -> void:
    var bench := _bench()
    var router := bench["router"] as ShortcutRouter
    var viewport := bench["viewport"] as SubViewport
    var field := bench["field"] as LineEdit
    field.grab_focus()

    router.handle_viewport_input(_escape(), viewport)

    assert_eq(viewport.gui_get_focus_owner(), null, "the box lets the keyboard go")
    _teardown(bench)


## With nothing focused there is nothing to release, and nothing to go wrong
## either: the branch has to answer false rather than reach into a null owner.
func test_escape_with_nothing_focused_does_nothing() -> void:
    var bench := _bench()
    var router := bench["router"] as ShortcutRouter
    var viewport := bench["viewport"] as SubViewport

    router.handle_viewport_input(_escape(), viewport)

    assert_eq(viewport.gui_get_focus_owner(), null, "nothing focused before, nothing after")
    _teardown(bench)


## A tool with a gesture in the air is first in the order, so the focus is not
## released under it: one Escape abandons the gesture, the next frees the focus.
func test_a_live_gesture_keeps_the_key_and_the_focus_stays() -> void:
    var bench := _bench()
    var router := bench["router"] as ShortcutRouter
    var viewport := bench["viewport"] as SubViewport
    var dropdown := bench["dropdown"] as OptionButton
    var machine := ToolMachine.new()
    var tool := GestureTool.new()
    tool.shape = {"rect": Rect2(0, 0, 10, 10), "handles": true}
    machine.active_tool = tool
    router.tool_machine_provider = func() -> ToolMachine: return machine
    dropdown.grab_focus()

    router.handle_viewport_input(_escape(), viewport)

    assert_eq(viewport.gui_get_focus_owner(), dropdown, "the gesture took the key, so the focus is untouched")
    machine.active_tool = null
    machine.free()
    _teardown(bench)
