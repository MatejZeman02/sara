## A shortcut profile switch leaves the keyboard where it was.
##
## The Keyboard Shortcuts page is in two parts, the search and the profile
## built once and the rows rebuilt on a switch, so the search field
## keeps the keyboard because `refresh()` never rebuilds the page it sits on.
## Its scenario read no focused control in either state, so this suite gives
## the field the keyboard, switches the profile through the page's own door,
## and reads the same field still holding it.
extends "res://tests/test_framework.gd"

static var scratch_dir: String = SaDataRoot.path("test_keyboard_kept_profiles")

var _saved_events: Dictionary = {}
var _saved_profile := ""


func before_each() -> void:
    _saved_events.clear()
    for action: StringName in InputMap.get_actions():
        _saved_events[action] = InputMap.action_get_events(action).duplicate()
    SaShortcutStore.dir_override = scratch_dir
    _saved_profile = SaSettings.shortcuts_profile


func after_each() -> void:
    for action: StringName in _saved_events:
        InputMap.action_erase_events(action)
        for event: InputEvent in _saved_events[action]:
            InputMap.action_add_event(action, event)
    SaShortcutStore.dir_override = ""
    SaSettings.shortcuts_profile = _saved_profile


func test_the_search_field_keeps_the_keyboard_through_a_profile_switch() -> void:
    var page := SaShortcutsPage.new()
    EventBus.add_child(page)
    page.filter("fill")
    var field := page.search
    field.grab_focus()
    assert_true(field.has_focus(), "the search field has the keyboard before the switch")
    for profile: String in ["Krita", SaShortcutStore.DEFAULT_PROFILE]:
        page.select_profile(profile)
        assert_eq(SaSettings.shortcuts_profile, profile, "the page switched to %s" % profile)
        assert_eq(page.search, field, "the field is the same control after the switch to %s" % profile)
        assert_true(is_instance_valid(field) and field.is_inside_tree(), "and it is still on the page")
        assert_true(field.has_focus(), "and it still has the keyboard")
        assert_eq(field.get_viewport().gui_get_focus_owner(), field, "which the window reads as its focus owner")
    page.free()
