## A command that registers after a profile switch answers to the chord it ships.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The order the chord suites failed in. `test_a_profile_switch_keeps_the_keyboard`
## switches to Krita and back to Sara Default before the app's commands are
## built, and seven chord suites run after it found forty-three actions
## answering to nothing. Krita's table had created those actions, Sara Default
## took their chords off because nothing had recorded what they ship, and the
## commands then registered onto actions that already existed.
## `SaCommandRegistry._ensure_action` recorded the shipped chords of such an
## action and left it unbound, so `test_shortcut_editor` read forty-three
## differences where it had made one.
##
## A whole run never showed it, because a suite earlier in the alphabet builds
## the commands first. The cases here make the order themselves, on actions of
## their own that nothing else registers, so they hold it whatever ran before.
extends "res://tests/test_framework.gd"

static var scratch_dir: String = SaDataRoot.path("test_late_command_profiles")

## The saved profile that makes the actions before their commands register.
const PROFILE: String = "Late command"

var _saved_events: Dictionary = {}
var _saved_actions: Array[StringName] = []
var _saved_profile: String = ""


func before_each() -> void:
    _saved_events.clear()
    for action: StringName in InputMap.get_actions():
        _saved_events[action] = InputMap.action_get_events(action).duplicate()
    _saved_actions.assign(InputMap.get_actions())
    _saved_profile = SaSettings.shortcuts_profile
    SaShortcutStore.dir_override = scratch_dir
    SaShortcutStore.capture_defaults()


func after_each() -> void:
    for action: StringName in _saved_events:
        InputMap.action_erase_events(action)
        for event: InputEvent in _saved_events[action]:
            InputMap.action_add_event(action, event)
    for action: StringName in InputMap.get_actions():
        if not _saved_actions.has(action):
            InputMap.erase_action(action)
    SaSettings.shortcuts_profile = _saved_profile
    SaShortcutStore.dir_override = ""
    var dir := DirAccess.open(scratch_dir)
    if dir != null:
        for file: String in dir.get_files():
            dir.remove(file)


## The Shortcuts page's switch: the setting first, then the map.
func _switch_to(profile: String) -> void:
    SaSettings.shortcuts_profile = profile
    SaShortcutStore.apply_profile(profile)


## The profile, naming *action* with a chord of its own.
func _save(action: StringName) -> void:
    var overrides: Dictionary[String, Array] = {String(action): ["Ctrl+Alt+E"]}
    assert_true(SaShortcutStore.save_overrides(PROFILE, overrides), "The profile is saved")


## A command shipping *shipped*, registered through the door a module uses.
func _register(action: StringName, shipped: String) -> void:
    var registries := SaRegistries.new()
    registries.build_context(func() -> Variant: return null, func() -> Array: return [])
    var command := SaCommandDescriptor.create(action, "Late %s" % action, func() -> void: pass)
    command.default_events = [SaShortcutStore.parse_chord(shipped)]
    registries.context.for_module(&"late-command-test").register_command(command)


func test_a_command_registered_after_a_switch_away_answers_to_the_chord_it_ships() -> void:
    var late := &"late_command_after_a_switch"
    _save(late)
    _switch_to(PROFILE)
    assert_eq(SaShortcutStore.chords_for(late), ["Ctrl+Alt+E"] as Array[String], "The profile made the action")
    _switch_to(SaShortcutStore.DEFAULT_PROFILE)
    assert_eq(
        SaShortcutStore.chords_for(late), [] as Array[String], "Sara Default took the chord off, nothing having recorded it"
    )

    _register(late, "Ctrl+Alt+Y")
    assert_eq(SaShortcutStore.defaults()[String(late)], ["Ctrl+Alt+Y"], "The registration records what the command ships")
    assert_eq(SaShortcutStore.chords_for(late), ["Ctrl+Alt+Y"] as Array[String], "and puts it on the action")
    assert_true(InputMap.event_is_action(SaShortcutStore.parse_chord("Ctrl+Alt+Y"), late), "so the key reaches it")
    assert_false(SaShortcutStore.overrides_now().has(String(late)), "and nothing reads it as a painter's change")


func test_a_command_registered_under_the_profile_that_made_its_action_keeps_the_profile_s_chord() -> void:
    var late := &"late_command_under_its_profile"
    _save(late)
    _switch_to(PROFILE)

    _register(late, "Ctrl+Alt+Y")
    assert_eq(SaShortcutStore.defaults()[String(late)], ["Ctrl+Alt+Y"], "The registration records what the command ships")
    assert_eq(SaShortcutStore.chords_for(late), ["Ctrl+Alt+E"] as Array[String], "and the profile's chord stays on")
    _switch_to(SaShortcutStore.DEFAULT_PROFILE)
    assert_eq(SaShortcutStore.chords_for(late), ["Ctrl+Alt+Y"] as Array[String], "until Sara Default gives back the shipped one")
