## Tab into or out of focus mode ends Ctrl+0's toggle.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Tab into focus mode turns off the zoomed toggle (Ctrl+0). Ctrl+0 remembers
## the view it left so a second press goes back there, and only a move of the
## view forgets it. Tab hides or shows the dockers, which changes the free
## rectangle a reset fits into without moving the view, so the press after a Tab
## must fit the reset into the new room and not go back to the close-in view.
##
## The route is the whole one: a real `MainCanvas` in a viewport the size of
## the window, docker stand-ins embedded there as side covers, `SaFocusMode`
## hiding and showing them as Tab does, and Ctrl+0 struck as a keyboard sends
## it through the commands the shortcut table registers.
extends "res://tests/test_framework.gd"

## A real canvas builds an easel, which needs a RenderingDevice.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const MainCanvasScript = preload("res://render/main_canvas.gd")

const WINDOW := Vector2i(1920, 1080)

## The two docker columns of the default layout, the left one ending at 380 and
## the right one starting at 1600.
const LEFT := Rect2(0.0, 79.0, 380.0, 900.0)
const RIGHT := Rect2(1600.0, 79.0, 320.0, 900.0)

## Where the painter stood before the first press: close in, on a corner. The
## view stands straight on, because a reset keeps the painter's turn and the
## checks below read the picture's middle against the room's.
const ZOOM := 3.0
const PAN := Vector2(-1234.5, -678.25)

var _host: Node = null
var _main: Node = null
var _focus: SaFocusMode = null
var _table: Array = []
var _registries: SaRegistries = null
var _commands: SaShortcutCommands = null
var _saved_events: Dictionary = {}
var _saved_reset: String = ""


func before_each() -> void:
    SaFocusMode.active = false
    _saved_events.clear()
    for action: StringName in InputMap.get_actions():
        _saved_events[action] = InputMap.action_get_events(action).duplicate()
    _saved_reset = SaSettings.reset_zoom
    SaSettings.reset_zoom = SaView.RESET_WHOLE
    SaShortcutStore.apply_profile(SaShortcutStore.DEFAULT_PROFILE)
    _host = Node.new()
    _host.name = "U585TestHost"
    EventBus.add_child(_host)
    var viewport := SubViewport.new()
    viewport.size = WINDOW
    viewport.gui_embed_subwindows = true
    _host.add_child(viewport)
    _main = MainCanvasScript.new()
    viewport.add_child(_main)
    _main.bind_tools(Fixtures.make_tool_registry())
    _focus = SaFocusMode.new()
    _host.add_child(_focus)
    _table = [_docker(viewport, "LeftDocker", LEFT), _docker(viewport, "RightDocker", RIGHT)]
    var machine: ToolMachine = _main.tool_machine
    _registries = Fixtures.make_registries(machine.surface)
    _commands = SaShortcutCommands.new(func() -> ToolMachine: return machine, Callable(), Callable(), null)
    _commands.register_into(_registries.commands)


func after_each() -> void:
    SaFocusMode.active = false
    _commands = null
    _registries = null
    _table = []
    if _host != null and is_instance_valid(_host):
        _host.free()
    _host = null
    _main = null
    _focus = null
    SaSettings.reset_zoom = _saved_reset
    SaShortcutStore.apply_profile(SaShortcutStore.DEFAULT_PROFILE)
    for action: StringName in InputMap.get_actions():
        if not _saved_events.has(action):
            InputMap.erase_action(action)
    for action: StringName in _saved_events:
        if not InputMap.has_action(action):
            continue
        InputMap.action_erase_events(action)
        for event: InputEvent in _saved_events[action]:
            InputMap.action_add_event(action, event)


func test_ctrl_0_after_tab_into_focus_mode_resets_into_the_whole_window() -> void:
    var view := _stand_close_in()
    assert_true(_ctrl_0(), "Ctrl+0 is taken by the command")
    var between := view.get_zoom()
    var room_starts := view.get_free_rect().position.x
    assert_almost_eq(room_starts, LEFT.end.x, 1e-3, "With the dockers shown the room starts after the left column")
    _tab()
    assert_true(SaFocusMode.active, "Tab enters focus mode")
    assert_eq(view.get_zoom(), between, "The Tab press itself does not move the view")
    assert_eq(view.get_free_rect(), view.get_visible_rect(), "and the room is now the whole visible rectangle")
    _ctrl_0()
    assert_true(not is_equal_approx(view.get_zoom(), ZOOM), "Ctrl+0 after the Tab does not go back to the close-in view")
    _assert_reset_into(view, "Ctrl+0 after Tab into focus mode")


func test_ctrl_0_after_tab_out_of_focus_mode_resets_between_the_columns() -> void:
    _tab()
    var view := _stand_close_in()
    _ctrl_0()
    var between := view.get_zoom()
    _tab()
    assert_false(SaFocusMode.active, "Tab leaves focus mode")
    assert_eq(view.get_zoom(), between, "The Tab press itself does not move the view")
    assert_almost_eq(view.get_free_rect().position.x, LEFT.end.x, 1e-3, "and the room is between the columns again")
    _ctrl_0()
    assert_true(not is_equal_approx(view.get_zoom(), ZOOM), "Ctrl+0 after the Tab does not go back to the close-in view")
    _assert_reset_into(view, "Ctrl+0 after Tab out of focus mode")


func test_ctrl_0_twice_with_no_tab_between_still_goes_back() -> void:
    var view := _stand_close_in()
    _ctrl_0()
    _assert_reset_into(view, "The first press")
    _ctrl_0()
    assert_eq(view.get_zoom(), ZOOM, "The second press puts the zoom back exactly")
    assert_eq(view.get_pan(), PAN, "and the pan")


## Tab into focus mode and back out again before the second press leaves the
## room as it was, so the press still goes back: what is forgotten is a press
## whose room changed, not one a Tab happened near.
func test_tab_twice_between_the_presses_leaves_the_room_and_the_toggle_as_they_were() -> void:
    var view := _stand_close_in()
    _ctrl_0()
    _tab()
    _tab()
    _ctrl_0()
    assert_eq(view.get_zoom(), ZOOM, "The same room, so the second press goes back to the zoom")
    assert_eq(view.get_pan(), PAN, "and the pan")


# --- Helpers --------------------------------------------------------------------


## The free rectangle as it stands, holding the whole picture at its Size and
## centred in it. The picture is the one the surface opens with, the size the
## command itself asks the view to reset.
func _assert_reset_into(view: SaView, what: String) -> void:
    var free := view.get_free_rect()
    var document := (_main.tool_machine as ToolMachine).surface.get_canvas_size()
    var size := float(SaSettings.reset_zoom_size)
    assert_almost_eq(view.zoom_per_cent(document), size, 1e-3, "%s shows the whole picture at its Size" % what)
    var middle := view.document_to_screen(Vector2(document) * 0.5)
    assert_almost_eq(middle.x, free.get_center().x, 1e-2, "%s centres it across the room as it now stands" % what)
    assert_almost_eq(middle.y, free.get_center().y, 1e-2, "%s and down it" % what)


## The painter's own view, set the way a wheel and a drag would leave it.
func _stand_close_in() -> SaView:
    var view: SaView = (_main.tool_machine as ToolMachine).surface.view
    view.set_zoom(ZOOM)
    view.set_pan(PAN)
    return view


## Ctrl+0 as a keyboard sends it, struck through the commands.
func _ctrl_0() -> bool:
    var event := InputEventKey.new()
    event.keycode = KEY_0
    event.physical_keycode = KEY_0
    event.ctrl_pressed = true
    event.pressed = true
    return _registries.commands.try_handle_input(event)


## Tab, the way `main_dockers.gd` hands it to the focus mode.
func _tab() -> void:
    _focus.toggle(_table)


## A docker's stand-in, embedded in *viewport* and in the side cover group, the
## way `instantiate_registered_dockers` leaves a docker.
func _docker(viewport: SubViewport, docker_name: String, rect: Rect2) -> Dictionary:
    var side := Window.new()
    side.name = docker_name
    side.borderless = true
    side.position = Vector2i(rect.position)
    side.size = Vector2i(rect.size)
    side.add_to_group(SaCanvasView.SIDE_COVER_GROUP)
    viewport.add_child(side)
    assert_true(side.is_embedded(), "The stand-in must embed, or this suite measures nothing")
    return {"id": docker_name, "node": side}
