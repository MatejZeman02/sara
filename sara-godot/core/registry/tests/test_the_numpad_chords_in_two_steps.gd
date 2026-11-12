## A shipped profile keeps the numpad chords and the other
## layout's keys.
##
## The ask, 2026-09-22: "CTRL + +|-|NumPad0 stopped working." The zoom was not
## broken. `KRITA_DEFAULTS` names one chord per action, `load_profile` turned
## each entry into a list of one, and `apply_profile` replaced the action's whole
## list with it, so choosing Krita took Ctrl+Plus and the numpad away, and on the
## author's Czech keyboard the digit row types letters without Shift, so the
## numpad was the only way left to the zoom.
##
## The suite builds the app's own commands first, the way
## `core/registry/tests/test_rebind_survives.gd` does and for the reason that suite's
## header gives: `view_zoom_in` and its neighbours are the router's commands and
## reach the `InputMap` through the registry.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

static var scratch_dir: String = SaDataRoot.path("test_the_numpad_chords_in_two_steps")

## The events themselves, not the text they spell: restoring through
## `set_chords` erases what `chord_text` could not write back, and the tool
## machine's quick-switches read the physical keycode.
var _saved_events: Dictionary = {}
var _saved_actions: Array[StringName] = []
var _saved_profile: String = ""

## Whether the app's commands are in the `InputMap` yet. Once per run: the
## actions outlive the registry and a second registration of an id is refused.
var _commands_built: bool = false


## `main.gd`'s startup as far as the `InputMap` is concerned.
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
    # Before the events are saved, or the restore puts back an InputMap that
    # never had these actions in it.
    _build_app_commands()
    _saved_events.clear()
    for action: StringName in InputMap.get_actions():
        _saved_events[action] = InputMap.action_get_events(action).duplicate()
    # The names as well as the events: a shipped table names actions the build
    # does not, and `set_chords` writes an action into being for one. Left
    # behind, they read to the next suite as four chords the build never
    # shipped, which is what `test_a_profile_stores_only_the_differences`
    # counted.
    _saved_actions.assign(InputMap.get_actions())
    _saved_profile = SaSettings.shortcuts_profile
    SaShortcutStore.dir_override = scratch_dir
    SaShortcutStore.capture_defaults()
    SaSettings.shortcuts_profile = SaShortcutStore.DEFAULT_PROFILE


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


## The Krita table names one key per zoom and the build ships the same gesture
## on the row beside it. Both stay, and the numpad's chord is the one already bound.
func test_the_krita_zoom_keeps_the_keys_the_table_does_not_name() -> void:
    SaShortcutStore.apply_profile("Krita")

    assert_eq(
        SaShortcutStore.chords_for(&"view_zoom_in"),
        ["Ctrl+=", "Ctrl++", "Ctrl+Numpad +"] as Array[String],
        "Zoom in answers Ctrl with Equal, Plus and the numpad's plus"
    )
    assert_eq(
        SaShortcutStore.chords_for(&"view_zoom_out"),
        ["Ctrl+-", "Ctrl+Numpad -"] as Array[String],
        "Zoom out answers Ctrl with Minus and the numpad's minus"
    )
    assert_eq(
        SaShortcutStore.chords_for(&"view_zoom_100"),
        ["Ctrl+0", "Ctrl+Numpad 0"] as Array[String],
        "and Reset zoom answers Ctrl with 0 and the numpad's 0"
    )


## A table entry that really moves an action leaves nothing of the old key: the
## alternatives kept are the same key on another row, not every key the action
## answers to.
func test_an_entry_that_moves_an_action_leaves_the_old_key_behind() -> void:
    SaShortcutStore.apply_profile("Photoshop")

    # Photoshop's Ctrl+1 would be the example, but the build has an
    # Actual Pixels on that very chord, so the table no longer moves anything
    # there. Its Ctrl+K for Preferences moves Sara's Ctrl+comma instead.
    assert_eq(
        SaShortcutStore.chords_for(&"edit_preferences"),
        ["Ctrl+K"] as Array[String],
        "Photoshop's Ctrl+K is the whole list, and Sara's Ctrl+comma is not beside it"
    )
    assert_eq(SaShortcutStore.chords_for(&"edit_undo"), ["Ctrl+Z"] as Array[String], "and the same of every other key")


## The maintainers' own reading: the chord they pressed was Ctrl, not Ctrl+Shift.
## A kept alternative with another modifier would be a key the profile invented.
func test_a_kept_chord_carries_the_modifiers_of_the_entry() -> void:
    SaShortcutStore.apply_profile("Krita")

    for action: StringName in [&"view_zoom_in", &"view_zoom_out", &"view_zoom_100"]:
        for chord: String in SaShortcutStore.chords_for(action):
            var event := SaShortcutStore.parse_chord(chord)
            assert_not_null(event, "%s reads back" % chord)
            assert_true(
                event.ctrl_pressed and not event.shift_pressed and not event.alt_pressed, "%s under Krita is Ctrl alone" % chord
            )


## Switching back gives every action the list the build shipped, which is what
## makes applying a shipped profile a thing that can be undone.
func test_switching_back_restores_the_defaults_exactly() -> void:
    var shipped := SaShortcutStore.defaults().duplicate(true)
    SaShortcutStore.apply_profile("Krita")
    SaShortcutStore.apply_profile(SaShortcutStore.DEFAULT_PROFILE)

    var off: Array[String] = []
    for action: String in shipped:
        if not InputMap.has_action(StringName(action)):
            continue
        if SaShortcutStore.chords_for(StringName(action)) != shipped[action]:
            off.append(action)
    assert_eq(off, [] as Array[String], "Every action answers the shipped map's list again")


## The list the record gives, held here so it can be checked rather than read:
## under Krita three zoom rows answer a second key the table does not name, and
## so do the ten brush slots, which sit on Ctrl+Alt digits,
## each with its numpad twin. Under Photoshop none does, because that table
## names no zoom row and its slots are cleared.
## Save's two chords under Krita are both the table's own.
func test_only_the_krita_zoom_rows_and_brush_slots_gain_a_chord() -> void:
    var krita: Array[String] = ["view_zoom_100", "view_zoom_in", "view_zoom_out"]
    for slot in range(1, SaSettingsValues.BRUSH_SLOT_COUNT + 1):
        krita.append("brush_slot_%d" % slot)
    krita.sort()
    for pair: Array in [["Krita", krita], ["Photoshop", []]]:
        var profile := String(pair[0])
        var gained: Array[String] = []
        var overrides := SaShortcutStore.load_profile(profile)
        var table: Dictionary = SaShortcutStore.SHIPPED_PROFILES[profile]
        for action: String in overrides:
            if (overrides[action] as Array).size() > maxi(1, SaShortcutStore.entry_chords(table.get(action, "")).size()):
                gained.append(action)
        gained.sort()
        assert_eq(gained, pair[1] as Array[String], "%s: only these rows answer more than the table's key" % profile)


## A profile a painter saved is their own list, so it is applied as it stands.
## The alternatives are what a shipped table gets beside it, not what a saved
## profile does.
func test_a_profile_a_painter_saved_is_applied_as_it_stands() -> void:
    SaShortcutStore.set_chords(&"view_zoom_in", ["Ctrl+Alt+I"])
    assert_true(SaShortcutStore.save_profile("Mine") > 0, "The profile is written from the map as the painter left it")

    SaShortcutStore.apply_profile(SaShortcutStore.DEFAULT_PROFILE)
    SaShortcutStore.apply_profile("Mine")

    assert_eq(
        SaShortcutStore.chords_for(&"view_zoom_in"),
        ["Ctrl+Alt+I"] as Array[String],
        "and applying it puts that one chord back with nothing added beside it"
    )
