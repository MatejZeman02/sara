## Quick settings' Krita button sets Ctrl+0 to actual pixels.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Krita's first hour, finding 13: in Krita Ctrl+0 is Reset Zoom to 100 per
## cent, and the Krita button now gives it that meaning through the setting the
## Display page already holds, `SaSettings.reset_zoom`, while Sara's default
## stays the whole picture. Every setting the row writes starts at a fresh
## folder's value and is put back after each test, the shortcut map applied
## again with it, which is how the Quick settings suites put the input map
## back. A copy of the input map put back by hand leaves
## `test_command_chords` finding commands with no chord whenever this suite runs
## after the suite for choosing a program. The row is built with no layout store and out of the
## tree, so a press applies at once and leaves the layout alone. Ctrl+0 is
## struck as a keyboard sends it, through the commands the shortcut table
## registers, on a real easel, the way the shortcut suites strike it.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## A real easel needs a RenderingDevice.
const REQUIRES_GPU := true

const CANVAS := Vector2i(2000, 1000)
const KEYS: Array[String] = ["shortcuts_profile", "theme_name", "color_picker_shape", "reset_zoom"]

var _surface: SaSurface = null
var _machine: ToolMachine = null
var _registries: SaRegistries = null
var _table: SaShortcutCommands = null
var _row: SaComingFromRow = null
var _saved: Dictionary = {}


func before_each() -> void:
    for key: String in KEYS:
        _saved[key] = SaSettings.get(key)
        SaSettings.set(key, _fresh(key))
    SaShortcutStore.apply_profile(SaSettings.shortcuts_profile)
    _surface = Fixtures.make_surface(CANVAS)
    _machine = Fixtures.make_bound_machine(_surface)
    _registries = Fixtures.make_registries(_surface)
    _table = SaShortcutCommands.new(func() -> ToolMachine: return _machine, Callable(), Callable(), null)
    _table.register_into(_registries.commands)
    _row = SaComingFromRow.new()


func after_each() -> void:
    _row.free()
    _table = null
    _registries = null
    Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null
    for key: String in _saved:
        SaSettings.set(key, _saved[key])
    SaShortcutStore.apply_profile(SaSettings.shortcuts_profile)
    EventBus.shortcuts_changed.emit()


## A fresh settings folder's value, read off a values object nothing has
## loaded into. `Script.get_property_default_value` answers null for every
## setting here, so a suite that sets the settings to it changes none of them.
static func _fresh(key: String) -> Variant:
    var fresh := SaSettingsValues.new()
    var value: Variant = fresh.get(key)
    fresh.free()
    return value


## Ctrl+0 as a keyboard sends it, struck through the commands.
func _ctrl_0() -> bool:
    var event := InputEventKey.new()
    event.keycode = KEY_0
    event.physical_keycode = KEY_0
    event.ctrl_pressed = true
    event.pressed = true
    return _registries.commands.try_handle_input(event)


func test_krita_then_ctrl_0_shows_actual_pixels() -> void:
    assert_eq(SaSettings.reset_zoom, SaView.RESET_WHOLE, "a fresh folder's Ctrl+0 shows the whole picture")
    _row.press("krita")
    assert_eq(SaSettings.shortcuts_profile, "Krita", "the Krita button put Krita's shortcuts in force")
    assert_eq(SaSettings.reset_zoom, SaView.RESET_PIXELS, "and Ctrl+0's answer is actual pixels")
    var view := _surface.view
    view.set_zoom(3.0)
    assert_true(_ctrl_0(), "Ctrl+0 is taken by the command under Krita's shortcuts")
    var reading := view.get_zoom() * view.get_content_scale()
    assert_almost_eq(reading, 1.0, 1e-6, "the zoom reads 1.0, one texel on one device pixel")
    assert_eq(SaComingFromRow.in_force(null), "krita", "and Krita is the program in force")


func test_krita_again_puts_back_a_fresh_folders_answer() -> void:
    _row.press("krita")
    _row.press("krita")
    assert_eq(SaSettings.reset_zoom, _fresh("reset_zoom"), "Krita pressed again gives back a fresh folder's Ctrl+0")
    assert_true(SaComingFromRow.holds(SaComingFromRow.OWN_VALUES, null), "and Sara's own values are in force")
    assert_eq(SaComingFromRow.in_force(null), "", "with no program")


## A painter who chose actual pixels on the Display page with Sara's other
## values is in no program until they press one, as the row reads the picker.
func test_actual_pixels_chosen_by_hand_presses_no_program() -> void:
    SaSettings.reset_zoom = SaView.RESET_PIXELS
    assert_eq(SaComingFromRow.in_force(null), "", "Sara's values with actual pixels are no program")
    var pressed: Array[String] = []
    for program: String in _row.buttons:
        if _row.buttons[program].button_pressed:
            pressed.append(program)
    assert_eq(pressed, [] as Array[String], "and no button shows pressed")
