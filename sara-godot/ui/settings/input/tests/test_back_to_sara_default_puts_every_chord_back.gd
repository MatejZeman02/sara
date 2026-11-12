## Back to Sara Default puts every chord back.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The `shell` sweep's F3. A painter bound Export and Import a picture to one
## chord, picked Share, pressed Back to Sara Default and found Import still on
## the chord with a lit Reset. The cause is the order of a launch, which a
## single session never shows: the File menu's commands register when the
## router binds its commands, after the stored profile is laid over the map, so a
## profile that binds one of them creates its action first. The command then
## found the action there and recorded nothing, the shipped map never named it,
## and the restore walk in `apply_profile`, which goes through that map, passed
## it by. The suite holds the invariant the sweep broke: after Back to Sara
## Default every action answers to what the build ships it, and one the build
## never recorded counts as unbound.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

static var scratch_dir: String = SaDataRoot.path("test_back_to_default_profiles")

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
    ShortcutRouter.capture_in_progress = false
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
    var dir := DirAccess.open(scratch_dir)
    if dir != null:
        for file: String in dir.get_files():
            dir.remove(file)


func _page() -> SaShortcutsPage:
    _registries = Fixtures.make_menu_registries()
    var page := SaShortcutsPage.new()
    page.bind_tools(_registries.tools, _registries.filters, _registries.commands)
    return page


func _register(action: StringName, shipped: String = "") -> void:
    var registries := SaRegistries.new()
    registries.build_context(func() -> Variant: return null, func() -> Array: return [])
    var command := SaCommandDescriptor.create(action, "Chord %s" % action, func() -> void: pass)
    if not shipped.is_empty():
        command.default_events = [SaShortcutStore.parse_chord(shipped)]
    registries.context.for_module(&"chord-test").register_command(command)


## The first step, which says which of three suspects a run is: the
## two commands bound to one chord, the shipped profile applied, and what the
## shipped map and the InputMap then hold for each.
##
## In one session both commands are in the map, their events come off and no
## second place holds the chord, so the missing record and the pair or alias
## write are not what a session meets. The record is what a launch loses, which
## the two launch-order tests below hold.
func test_the_shipped_profile_applied_over_one_chord_on_both_commands() -> void:
    SaShortcutStore.set_chords(&"file_import", ["Ctrl+Alt+E"])
    SaShortcutStore.set_chords(&"file_export", ["Ctrl+Alt+E"])
    SaShortcutStore.apply_profile(SaShortcutStore.DEFAULT_PROFILE)
    for action: StringName in [&"file_import", &"file_export"]:
        assert_true(SaShortcutStore.defaults().has(String(action)), "%s is in the shipped map" % action)
        assert_eq(InputMap.action_get_events(action).size(), 0, "%s has no event left in the InputMap" % action)
    assert_eq(SaShortcutStore.paired_with(&"file_import"), [] as Array[StringName], "Import is no gesture's half")
    assert_eq(SaShortcutStore.aliases_of(&"file_import"), [] as Array[StringName], "and no alias of another action")


## The sweep's own steps, on the two real commands.
func test_start_again_after_a_shared_chord_leaves_no_row_lit() -> void:
    var page := _page()
    page.offer(&"file_export", "Ctrl+Alt+E")
    page.offer(&"file_import", "Ctrl+Alt+E")
    assert_not_null(page.question, "Import is asked about the chord Export holds")
    page.question.buttons[SaShortcutsPage.ANSWER_SHARE].pressed.emit()
    assert_eq(SaShortcutStore.chords_for(&"file_import"), ["Ctrl+Alt+E"] as Array[String], "Share leaves both on the chord")
    assert_eq(SaShortcutStore.chords_for(&"file_export"), ["Ctrl+Alt+E"] as Array[String], "and Export keeps it")

    page.start_again()
    assert_eq(page.active_profile(), SaShortcutStore.DEFAULT_PROFILE, "The profile reads Sara Default")
    for action: StringName in [&"file_import", &"file_export"]:
        assert_eq(SaShortcutStore.chords_for(action), [] as Array[String], "%s is unbound again" % action)
        assert_eq(page.chords_shown(action), [SaShortcutsPage.NO_CHORD_TEXT] as Array[String], "%s reads Set…" % action)
    assert_eq(_lit_rows(page), [] as Array[String], "and no row has a lit Reset")
    page.free()


## What no row's Reset may be, for every action and not only the two above.
func _lit_rows(page: SaShortcutsPage) -> Array[String]:
    var lit: Array[String] = []
    for action: String in SaShortcutStore.current_map():
        if not page.at_reset(StringName(action)):
            lit.append(action)
    return lit


## A few more edits of different kinds, then the one press.
func test_start_again_puts_back_every_edit_of_a_session() -> void:
    var page := _page()
    page.rebind(&"file_import", "Ctrl+Alt+E")
    page.rebind(&"edit_redo", "Ctrl+Alt+Y")
    page.rebind(&"view_zoom_in", "")
    page.rebind(&"layer_clear", "Ctrl+Alt+K", 0)
    assert_false(_lit_rows(page).is_empty(), "The edits light some Resets")
    page.start_again()
    assert_eq(_lit_rows(page), [] as Array[String], "Back to Sara Default leaves none lit")
    assert_true(
        SaShortcutStore.overrides_now().is_empty(),
        "and nothing differs from the shipped map: %s" % str(SaShortcutStore.overrides_now())
    )
    page.free()


## The launch order, which is the cause: a saved profile binds an action before
## its command registers.
func test_an_action_a_profile_created_before_its_command_is_recorded_unbound() -> void:
    var late := &"chord_profile_first"
    SaShortcutStore.capture_defaults()
    assert_false(InputMap.has_action(late), "The action does not exist yet")
    SaShortcutStore.set_chords(late, ["Ctrl+Alt+E"])
    _register(late)
    assert_true(
        SaShortcutStore.defaults().has(String(late)), "The command's registration records it although the action was there"
    )
    assert_eq(SaShortcutStore.defaults()[String(late)], [], "as shipping no chord")

    SaShortcutStore.apply_profile(SaShortcutStore.DEFAULT_PROFILE)
    assert_eq(SaShortcutStore.chords_for(late), [] as Array[String], "so Sara Default takes the chord off it")
    InputMap.erase_action(late)


## The same order for a command that ships a chord, which has to come back as
## that chord and not as nothing.
func test_an_action_a_profile_created_first_goes_back_to_the_chord_its_command_ships() -> void:
    var late := &"chord_profile_first_shipped"
    SaShortcutStore.capture_defaults()
    SaShortcutStore.set_chords(late, ["Ctrl+Alt+E"])
    _register(late, "Ctrl+Alt+Y")
    assert_eq(
        SaShortcutStore.defaults()[String(late)], ["Ctrl+Alt+Y"], "The record is what the command ships, not the painter's chord"
    )
    SaShortcutStore.apply_profile(SaShortcutStore.DEFAULT_PROFILE)
    assert_eq(SaShortcutStore.chords_for(late), ["Ctrl+Alt+Y"] as Array[String], "and Sara Default gives that back")
    InputMap.erase_action(late)


## A registration that finds the action already recorded keeps the record, or a
## rebind would be promoted to a default by registering twice.
func test_a_second_registration_does_not_promote_a_rebind() -> void:
    var action := &"chord_recorded_twice"
    SaShortcutStore.capture_defaults()
    _register(action, "Ctrl+Alt+Y")
    SaShortcutStore.set_chords(action, ["Ctrl+Alt+E"])
    SaShortcutStore.remember_shipped_events(action, [SaShortcutStore.parse_chord("Ctrl+Alt+E")])
    assert_eq(SaShortcutStore.defaults()[String(action)], ["Ctrl+Alt+Y"], "The first record stands")
    InputMap.erase_action(action)


## An action nothing recorded counts as unbound, which is how `overrides_now`
## already reads it.
func test_an_action_the_shipped_map_never_recorded_counts_as_unbound() -> void:
    var stray := &"chord_stray_action"
    InputMap.add_action(stray)
    InputMap.action_add_event(stray, SaShortcutStore.parse_chord("Ctrl+Alt+E"))
    assert_false(SaShortcutStore.defaults().has(String(stray)), "Nothing recorded it")
    assert_true(SaShortcutStore.overrides_now().has(String(stray)), "and the store already calls its chord an override")
    SaShortcutStore.apply_profile(SaShortcutStore.DEFAULT_PROFILE)
    assert_eq(SaShortcutStore.chords_for(stray), [] as Array[String], "so putting the shipped map back takes the chord off")
    InputMap.erase_action(stray)
