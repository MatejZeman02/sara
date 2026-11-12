## Switching the shortcut profile answers within a second.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A switch to Krita once held a frame for half
## a minute, and the switch back for a minute, nearly all of it the page's rows. The suite builds the
## page over the app's commands, switches it three times, and
## reads each switch done within a second.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

static var scratch_dir: String = SaDataRoot.path("test_profile_switch_timing")

## The budget of one switch, the row's "under a second".
const BUDGET_MS := 1000

var _commands_built: bool = false
var _saved_events: Dictionary = {}
var _saved_profile: String = ""
var _registries: SaRegistries = null


func _build_app_commands() -> void:
    if _commands_built:
        return
    _commands_built = true
    var registries := Fixtures.make_registries()
    SaAppCommands.register_all(registries, func(_docker_id: StringName) -> void: pass)
    var router := ShortcutRouter.new()
    router.bind_commands(registries.commands)
    router.free()


func before_each() -> void:
    _build_app_commands()
    _saved_events.clear()
    for action: StringName in InputMap.get_actions():
        _saved_events[action] = InputMap.action_get_events(action).duplicate()
    SaShortcutStore.dir_override = scratch_dir
    SaShortcutStore.capture_defaults()
    _saved_profile = SaSettings.shortcuts_profile
    SaSettings.shortcuts_profile = SaShortcutStore.DEFAULT_PROFILE
    SaShortcutStore.apply_profile(SaShortcutStore.DEFAULT_PROFILE)


func after_each() -> void:
    for action: StringName in InputMap.get_actions():
        if not _saved_events.has(action):
            InputMap.erase_action(action)
    for action: StringName in _saved_events:
        InputMap.action_erase_events(action)
        for event: InputEvent in _saved_events[action]:
            InputMap.action_add_event(action, event)
    SaShortcutStore.dir_override = ""
    SaSettings.shortcuts_profile = _saved_profile
    _registries = null


func _page() -> SaShortcutsPage:
    _registries = Fixtures.make_menu_registries()
    var page := SaShortcutsPage.new()
    page.bind_tools(_registries.tools, _registries.filters, _registries.commands)
    return page


## Milliseconds the page takes to switch to *profile*, the dropdown's path.
func _switch_ms(page: SaShortcutsPage, profile: String) -> int:
    var began := Time.get_ticks_usec()
    page.select_profile(profile)
    return int((Time.get_ticks_usec() - began) / 1000.0)


func test_three_switches_each_take_under_a_second() -> void:
    var page := _page()
    for profile: String in ["Krita", SaShortcutStore.DEFAULT_PROFILE, "Krita"]:
        var took := _switch_ms(page, profile)
        print("A switch to %s took %d ms" % [profile, took])
        assert_true(took < BUDGET_MS, "The switch to %s took %d ms, under a second" % [profile, took])
        assert_eq(page.active_profile(), profile, "and the page reads %s" % profile)
    page.free()


func test_every_shipped_profile_switches_under_a_second() -> void:
    var page := _page()
    for profile: String in SaShortcutStore.SHIPPED_PROFILES:
        var took := _switch_ms(page, profile)
        assert_true(took < BUDGET_MS, "The switch to %s took %d ms, under a second" % [profile, took])
    _switch_ms(page, SaShortcutStore.DEFAULT_PROFILE)
    page.free()
