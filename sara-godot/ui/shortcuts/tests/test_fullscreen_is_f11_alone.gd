## Fullscreen is F11 alone.
##
## Ctrl+Shift+F is dropped and F11 stays. What is tested is three things: the
## command answers to F11 and nothing else, Ctrl+Shift+F is free in the build's
## map, and a profile that wrote the old pair reads F11 while one that bound
## the command to a chord of its own keeps it.
extends "res://tests/test_framework.gd"

const PROFILE_DIR: String = "test_fullscreen_is_f11_alone"

## Applying a profile rebinds the live InputMap, so every test puts it back.
var _saved_events: Dictionary = {}


func before_each() -> void:
    _saved_events.clear()
    for action: StringName in InputMap.get_actions():
        _saved_events[action] = InputMap.action_get_events(action).duplicate()
    SaShortcutStore.dir_override = SaDataRoot.path(PROFILE_DIR)


func after_each() -> void:
    SaShortcutStore.delete_profile("old pair")
    SaShortcutStore.delete_profile("own chord")
    SaShortcutStore.dir_override = ""
    for action: StringName in _saved_events:
        InputMap.action_erase_events(action)
        for event: InputEvent in _saved_events[action]:
            InputMap.action_add_event(action, event)


func _register() -> SaCommandRegistry:
    var registries := SaRegistries.new()
    registries.build_context(Callable(), Callable())
    SaAppCommands.register_all(registries, Callable())
    return registries.commands


func test_the_command_answers_to_f11_alone() -> void:
    var commands := _register()
    assert_eq(commands.chord_text(&"window_fullscreen"), "F11", "The command lists F11 and nothing beside it")
    assert_eq(SaShortcutStore.chords_for(&"window_fullscreen"), ["F11"], "and the InputMap holds exactly that")


func test_ctrl_shift_f_is_free() -> void:
    _register()
    var chord := SaAppCommands.chord(KEY_F, true, true)
    assert_false(InputMap.event_is_action(chord, &"window_fullscreen"), "Ctrl+Shift+F no longer toggles fullscreen")
    assert_eq(SaShortcutStore.conflicts("Ctrl+Shift+F"), [], "and nothing else in the build's map holds it")


func test_a_profile_that_wrote_the_old_pair_reads_f11_alone() -> void:
    _register()
    SaShortcutStore.capture_defaults()
    assert_true(
        SaShortcutStore.save_overrides("old pair", {"window_fullscreen": ["Ctrl+Shift+F", "F11"]}),
        "A profile holding the pair as a painter wrote it before F11 stood alone"
    )
    assert_false(SaShortcutStore.load_profile("old pair").has("window_fullscreen"), "reads as no entry for the command")
    SaShortcutStore.apply_profile("old pair")
    assert_eq(SaShortcutStore.chords_for(&"window_fullscreen"), ["F11"], "so applying it leaves F11 alone")


func test_a_binding_of_the_painters_own_is_kept() -> void:
    _register()
    SaShortcutStore.capture_defaults()
    SaShortcutStore.save_overrides("own chord", {"window_fullscreen": ["Ctrl+Alt+F"]})
    var kept: Array = SaShortcutStore.load_profile("own chord").get("window_fullscreen", [])
    assert_eq(kept, ["Ctrl+Alt+F"], "The profile keeps its chord")
    SaShortcutStore.apply_profile("own chord")
    assert_eq(SaShortcutStore.chords_for(&"window_fullscreen"), ["Ctrl+Alt+F"], "and the live map answers to it")
