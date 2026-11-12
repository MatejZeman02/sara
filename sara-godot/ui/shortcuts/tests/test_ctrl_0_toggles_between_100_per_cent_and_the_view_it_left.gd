## Ctrl+0 toggles between 100 per cent and the view it left.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A toggle like Shift+Z in DaVinci Resolve: a look at the work from a distance
## and then quickly back to the same level of detail. Ctrl+0 is struck here as a keyboard sends
## it, through the commands the shortcut table registers, on a surface whose
## fake view moves the way the canvas does, signal and all. Both answers of the
## Display page's Ctrl+0 row are pressed: actual pixels, the 100 per cent, and
## the whole picture, the default.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## A real easel needs a RenderingDevice.
const REQUIRES_GPU := true

const CANVAS := Vector2i(2000, 1000)

## Where the painter stood before the press: a corner of the picture, close in,
## turned a little.
const ZOOM := 3.0
const PAN := Vector2(-1234.5, -678.25)
const ROTATION := 0.25

var _surface: SaSurface = null
var _machine: ToolMachine = null
var _registries: SaRegistries = null
var _table: SaShortcutCommands = null
var _saved_events: Dictionary = {}
var _saved_reset: String = ""


func before_each() -> void:
    _saved_events.clear()
    for action: StringName in InputMap.get_actions():
        _saved_events[action] = InputMap.action_get_events(action).duplicate()
    _saved_reset = SaSettings.reset_zoom
    SaShortcutStore.apply_profile(SaShortcutStore.DEFAULT_PROFILE)
    _surface = Fixtures.make_surface(CANVAS)
    _machine = Fixtures.make_bound_machine(_surface)
    _registries = Fixtures.make_registries(_surface)
    _table = SaShortcutCommands.new(func() -> ToolMachine: return _machine, Callable(), Callable(), null)
    _table.register_into(_registries.commands)


func after_each() -> void:
    _table = null
    _registries = null
    Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null
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


## Ctrl+0 as a keyboard sends it, struck through the commands.
func _ctrl_0() -> bool:
    var event := InputEventKey.new()
    event.keycode = KEY_0
    event.physical_keycode = KEY_0
    event.ctrl_pressed = true
    event.pressed = true
    return _registries.commands.try_handle_input(event)


## The painter's own view, set the way a wheel and a drag would leave it.
func _stand_close_in() -> SaView:
    var view := _surface.view
    view.set_rotation(ROTATION)
    view.set_zoom(ZOOM)
    view.set_pan(PAN)
    return view


func test_a_second_press_puts_back_the_zoom_the_pan_and_the_turn_exactly() -> void:
    SaSettings.reset_zoom = SaView.RESET_PIXELS
    var view := _stand_close_in()
    assert_true(_ctrl_0(), "Ctrl+0 is taken by the command")
    assert_almost_eq(view.get_zoom(), view.actual_pixel_zoom(), 1e-6, "The first press shows 100 per cent")
    assert_true(view.get_pan() != PAN, "and moves the picture to the middle")
    assert_true(_ctrl_0(), "Ctrl+0 again is taken too")
    assert_eq(view.get_zoom(), ZOOM, "The second press puts the zoom back exactly")
    assert_eq(view.get_pan(), PAN, "and the pan")
    assert_eq(view.get_rotation(), ROTATION, "and the turn")
    _ctrl_0()
    assert_almost_eq(view.get_zoom(), view.actual_pixel_zoom(), 1e-6, "A third press is 100 per cent again")


func test_the_default_whole_picture_toggles_the_same_way() -> void:
    SaSettings.reset_zoom = SaView.RESET_WHOLE
    var view := _stand_close_in()
    _ctrl_0()
    var whole := view.get_zoom()
    var size := float(SaSettings.reset_zoom_size)
    assert_almost_eq(view.zoom_per_cent(CANVAS), size, 1e-3, "The first press shows the whole picture at its Size")
    _ctrl_0()
    assert_eq(view.get_zoom(), ZOOM, "The second press puts the zoom back exactly")
    assert_eq(view.get_pan(), PAN, "and the pan")
    _ctrl_0()
    assert_eq(view.get_zoom(), whole, "and the third shows the whole picture again")


func test_a_wheel_step_in_between_forgets_the_view_left() -> void:
    SaSettings.reset_zoom = SaView.RESET_PIXELS
    var view := _stand_close_in()
    _ctrl_0()
    view.zoom_by(SaView.ZOOM_STEP, view.get_free_rect().get_center())
    _ctrl_0()
    assert_almost_eq(view.get_zoom(), view.actual_pixel_zoom(), 1e-6, "After a wheel step Ctrl+0 shows 100 per cent")
    assert_true(view.get_zoom() != ZOOM, "and not the old view")


func test_a_pan_or_a_fit_in_between_forgets_it_too() -> void:
    SaSettings.reset_zoom = SaView.RESET_PIXELS
    var view := _stand_close_in()
    _ctrl_0()
    view.set_pan(view.get_pan() + Vector2(40, 0))
    _ctrl_0()
    assert_almost_eq(view.get_zoom(), view.actual_pixel_zoom(), 1e-6, "After a drag of the pan Ctrl+0 stays at 100 per cent")
    assert_true(view.get_pan() != PAN, "and centred, not the old pan")
    _stand_close_in()
    _ctrl_0()
    assert_true(_registries.commands.execute(&"view_fit"), "Fit runs")
    _ctrl_0()
    assert_almost_eq(view.get_zoom(), view.actual_pixel_zoom(), 1e-6, "After a fit Ctrl+0 shows 100 per cent")


func test_a_view_already_at_100_per_cent_has_nothing_to_go_back_to() -> void:
    SaSettings.reset_zoom = SaView.RESET_PIXELS
    var view := _surface.view
    view.reset(CANVAS)
    var zoom := view.get_zoom()
    var pan := view.get_pan()
    _ctrl_0()
    _ctrl_0()
    assert_eq(view.get_zoom(), zoom, "Pressed where it already stands, the view stays at 100 per cent")
    assert_eq(view.get_pan(), pan, "and centred")


func test_the_view_menus_row_says_it_toggles() -> void:
    var sentence := _registries.commands.get_descriptor(&"view_zoom_100").sentence
    var says := sentence.begins_with("Toggle between your view and the picture")
    assert_true(says, "The row's sentence says it toggles: %s" % sentence)
