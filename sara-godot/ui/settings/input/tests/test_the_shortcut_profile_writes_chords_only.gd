## A shortcut profile writes chords and nothing else.
##
## Only the workspace and layout change the Colour Picker, not a shortcut
## profile. The Keyboard Shortcuts page once put the picker on the HSV triangle under Krita's
## keys and on the square under Photoshop's, and nothing put it back, so a
## painter who only tried the Krita chords lost the wheel for good. The page no
## longer touches the picker, and this suite switches the profile there and back
## through the page's own door and reads the Colour Picker unchanged.
extends "res://tests/test_framework.gd"

static var scratch_dir: String = SaDataRoot.path("test_chords_only_profiles")

var _saved_events: Dictionary = {}
var _saved_profile := ""
var _saved_shape := ""


func before_each() -> void:
    _saved_events.clear()
    for action: StringName in InputMap.get_actions():
        _saved_events[action] = InputMap.action_get_events(action).duplicate()
    SaShortcutStore.dir_override = scratch_dir
    _saved_profile = SaSettings.shortcuts_profile
    _saved_shape = SaSettings.color_picker_shape


func after_each() -> void:
    for action: StringName in _saved_events:
        InputMap.action_erase_events(action)
        for event: InputEvent in _saved_events[action]:
            InputMap.action_add_event(action, event)
    SaShortcutStore.dir_override = ""
    SaSettings.shortcuts_profile = _saved_profile
    SaSettings.color_picker_shape = _saved_shape


## The picker keeps the shape the painter chose through every shipped profile,
## and the switch did happen, so a page that refused it cannot pass for one
## that left the picker alone.
func test_switching_the_profile_there_and_back_leaves_the_picker_shape() -> void:
    for shape: String in ["wheel", "okhsl", "hsl_square"]:
        SaSettings.color_picker_shape = shape
        var page := SaShortcutsPage.new()
        for profile: String in ["Krita", "Photoshop", SaShortcutStore.DEFAULT_PROFILE]:
            page.select_profile(profile)
            assert_eq(SaSettings.shortcuts_profile, profile, "The page switched to %s" % profile)
            assert_eq(SaSettings.color_picker_shape, shape, "and the picker is still on the %s under %s" % [shape, profile])
        page.free()


## Nothing the Colour Picker docker is built from moves on a switch: no
## `profile_changed` reaches it, which is the signal it rebuilds its shape,
## its rows and its geometry on, so its place, its size and what it shows stay
## as they were.
func test_a_switch_announces_nothing_the_colour_docker_rebuilds_on() -> void:
    var heard := [0]
    var count := func() -> void: heard[0] += 1
    SaSettings.profile_changed.connect(count)
    var page := SaShortcutsPage.new()
    page.select_profile("Krita")
    page.select_profile("Photoshop")
    page.select_profile(SaShortcutStore.DEFAULT_PROFILE)
    page.free()
    SaSettings.profile_changed.disconnect(count)
    assert_eq(heard[0], 0, "A shortcut profile switch tells no docker to rebuild")
