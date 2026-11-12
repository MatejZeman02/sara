## A chord a painter changes is still that chord in the next process.
##
## `SaShortcutStore.set_chords` writes the `InputMap` and nothing else, so a
## rebind made without pressing Save As was gone at the next launch, with the
## page saying only that the shipped map "cannot be changed in place" and
## nothing at all between the change and the loss. An edit under a shipped
## profile forks it now, the way editing a shipped docker layout forks that.
##
## The suite cannot restart, so it does what a restart does: put the `InputMap`
## back the way `project.godot` builds it, then call `apply_active`, which is
## the one call `main.gd` makes at startup.
##
## **It builds the app's own commands first, and could not stand up without
## them**. `project.godot` carries `edit_undo` and the tool keys and
## nothing else. `view_zoom_in`, which four of these methods rebind, is one of
## `ShortcutRouter`'s own commands and reaches the `InputMap` through
## `SaCommandRegistry`. So on `./run_tests.sh f34_rebind` it answered nothing at
## all: `chords_for` read `[]`, `_saved_events` held an empty array for it, and
## `after_each` restored an action with no chords, which made the first
## method's rebind the baseline every later method read. Three assertions failed
## alone and the same commit's full run was green, because some earlier suite
## had built the commands there. The suite builds them itself now, and the same
## call fills `SaShortcutStore.defaults()` on the way past, since
## `SaCommandRegistry` records a command's shipped chords as it creates its
## action.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

static var scratch_dir: String = SaDataRoot.path("test_f34_profiles")

## The events themselves, not the text they spell. `chord_text` cannot name
## every binding, so restoring through `set_chords` erases what it could not
## write and leaves an action answering nothing.
var _saved_events: Dictionary = {}
var _saved_profile: String = ""

## Whether the app's commands are in the `InputMap` yet. Once per run: the
## registry refuses a second registration of an id it already has, so this is a
## saving rather than a correctness guard, and the state it leaves behind is the
## state every other suite runs in.
var _commands_built: bool = false


## `main.gd`'s own startup, as far as the `InputMap` is concerned.
##
## The router is what registers its own list, `bind_commands` walks
## `_own_commands` and hands each to the registry, so a registry built without a
## router has the application's commands and none of the view ones. It is freed
## straight after: the actions belong to the `InputMap` and outlive it.
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
    _saved_profile = SaSettings.shortcuts_profile
    SaShortcutStore.dir_override = scratch_dir
    SaShortcutStore.capture_defaults()
    SaSettings.shortcuts_profile = SaShortcutStore.DEFAULT_PROFILE


func after_each() -> void:
    for action: StringName in _saved_events:
        InputMap.action_erase_events(action)
        for event: InputEvent in _saved_events[action]:
            InputMap.action_add_event(action, event)
    SaSettings.shortcuts_profile = _saved_profile
    var dir := DirAccess.open(scratch_dir)
    if dir != null:
        for file: String in dir.get_files():
            dir.remove(file)
    SaShortcutStore.dir_override = ""


## What a launch does to the map before `apply_active` lays a profile over it.
func _restart() -> void:
    for action: StringName in _saved_events:
        InputMap.action_erase_events(action)
        for event: InputEvent in _saved_events[action]:
            InputMap.action_add_event(action, event)
    SaShortcutStore.apply_active()


func test_a_rebind_on_the_shipped_map_forks_it() -> void:
    var page := SaShortcutsPage.new()
    page.rebind(&"view_zoom_in", "Ctrl+Alt+I")

    var forked := SaShortcutStore.DEFAULT_PROFILE + SaShortcutStore.FORK_SUFFIX
    assert_eq(SaSettings.shortcuts_profile, forked, "The edit lands in a fork of the shipped profile")
    assert_true(SaShortcutStore.list_profiles().has(forked), "which the dropdown offers")
    assert_eq(page.active_profile(), forked, "and the page is showing")

    var stored := SaShortcutStore.load_profile(forked)
    assert_eq(stored.get("view_zoom_in", []), ["Ctrl+Alt+I"] as Array[String], "The fork holds the chord that moved")
    assert_false(stored.has("edit_undo"), "and nothing that did not")
    page.free()


func test_the_chord_is_still_there_in_the_next_process() -> void:
    var page := SaShortcutsPage.new()
    page.rebind(&"view_zoom_in", "Ctrl+Alt+I")
    page.free()

    _restart()
    assert_eq(
        SaShortcutStore.chords_for(&"view_zoom_in"), ["Ctrl+Alt+I"] as Array[String], "The chord a painter set is the chord"
    )
    var after := SaShortcutsPage.new()
    assert_eq(after.chord_shown(&"view_zoom_in"), "Ctrl+Alt+I", "and the row reads it back")
    after.free()


## The shipped map is still there to go back to, which is the half of the layout
## store's answer that makes the fork safe.
func test_the_shipped_map_is_still_there_to_reset_to() -> void:
    var was := SaShortcutStore.chords_for(&"view_zoom_in")
    var page := SaShortcutsPage.new()
    page.rebind(&"view_zoom_in", "Ctrl+Alt+I")
    page.reset_action(&"view_zoom_in")
    assert_eq(SaShortcutStore.chords_for(&"view_zoom_in"), was, "Reset reads the profile the fork was made from")
    page.free()


## A painter's own profile is written in place. Forking one would leave a
## "Mine (custom)" beside "Mine" after every edit, which is a dropdown that
## grows a row per session.
func test_an_edit_under_a_saved_profile_writes_into_it() -> void:
    SaShortcutStore.set_chords(&"view_zoom_in", ["Ctrl+Alt+I"])
    SaShortcutStore.save_profile("Mine")
    SaSettings.shortcuts_profile = "Mine"

    var page := SaShortcutsPage.new()
    page.rebind(&"view_zoom_out", "Ctrl+Alt+O")
    assert_eq(SaSettings.shortcuts_profile, "Mine", "The profile a painter chose is the one that keeps the edit")
    assert_false(SaShortcutStore.list_profiles().has("Mine" + SaShortcutStore.FORK_SUFFIX), "and nothing forked beside it")

    var stored := SaShortcutStore.load_profile("Mine")
    assert_eq(stored.get("view_zoom_out", []), ["Ctrl+Alt+O"] as Array[String], "The new chord is in it")
    assert_eq(stored.get("view_zoom_in", []), ["Ctrl+Alt+I"] as Array[String], "beside the one that was already there")
    page.free()


## A reset of a row nobody moved must not name a profile after an edit that did
## not happen, or the dropdown fills with empty forks.
func test_a_reset_that_changes_nothing_forks_nothing() -> void:
    var page := SaShortcutsPage.new()
    page.reset_action(&"view_zoom_in")
    assert_eq(SaSettings.shortcuts_profile, SaShortcutStore.DEFAULT_PROFILE, "The shipped profile is still the active one")
    assert_false(
        SaShortcutStore.list_profiles().has(SaShortcutStore.DEFAULT_PROFILE + SaShortcutStore.FORK_SUFFIX),
        "and no empty fork was written"
    )
    page.free()


## The shipped map is still reachable from the dropdown, which is the other half
## of the layout store's answer: a fork is only safe if the thing it forked from
## is still there to go back to.
##
## True of every action the shipped map records, and this suite captures its
## defaults with the whole build loaded, so every action is in them here. The app
## captures at bootstrap and a command that registers later is not, which is the
## defect below and not this one.
func test_switching_back_to_the_shipped_profile_undoes_the_fork() -> void:
    var was := SaShortcutStore.chords_for(&"edit_undo")
    var page := SaShortcutsPage.new()
    page.rebind(&"edit_undo", "Ctrl+Alt+Z")
    assert_eq(SaShortcutStore.chords_for(&"edit_undo"), ["Ctrl+Alt+Z"] as Array[String], "The chord moved")

    page.select_profile(SaShortcutStore.DEFAULT_PROFILE)
    assert_eq(SaShortcutStore.chords_for(&"edit_undo"), was, "and choosing the shipped profile puts it back")
    assert_eq(page.chord_shown(&"edit_undo"), was[0], "with the row saying so")
    page.free()


## A command registered after `apply_active` has swept the InputMap is still put
## back by a profile switch.
##
## `capture_defaults` is a sweep at one instant and `apply_profile` walks what it
## recorded, so an action created after it was in no shipped map and a switch
## left it wherever the profile before it had put it. Found on the running app
## rather than here: `scenarios/rebind-lost-on-restart.json` rebinds
## `view_zoom_in` and a switch to Sara Default leaves it rebound, while the same
## sequence on `edit_undo` puts it back, the only difference between the two
## being whether the action existed when the sweep ran.
##
## The command goes through `SaCommandRegistry`, which is the door the
## application registers through and the one the record lives in. The pending
## form of this method built the action with a bare `InputMap.add_action`, which
## is not a door any command uses and which no fix in the registry could have
## satisfied.
func test_a_profile_switch_puts_back_an_action_the_capture_never_saw() -> void:
    SaShortcutStore.capture_defaults()
    var late := &"f56_late_action"
    var registries := SaRegistries.new()
    registries.build_context(func() -> Variant: return null, func() -> Array: return [])
    var command := SaCommandDescriptor.create(late, "Registered Late", func() -> void: pass)
    command.default_events = [SaShortcutStore.parse_chord("Ctrl+Alt+Y")]
    registries.context.for_module(&"f56-test").register_command(command)
    assert_true(InputMap.has_action(late), "The command created its action after the sweep")

    var page := SaShortcutsPage.new()
    SaShortcutStore.set_chords(late, ["Ctrl+Alt+U"])
    assert_eq(SaShortcutStore.chords_for(late), ["Ctrl+Alt+U"] as Array[String], "and the rebind takes")
    page.select_profile(SaShortcutStore.DEFAULT_PROFILE)
    assert_eq(SaShortcutStore.chords_for(late), ["Ctrl+Alt+Y"] as Array[String], "The shipped profile puts back what it shipped")
    page.free()
    InputMap.erase_action(late)


## The other face of the same gap, and the one a painter meets first: a fork
## written after one rebind holds one action rather than every action the sweep
## never saw.
func test_a_late_action_is_not_written_into_every_profile_as_an_override() -> void:
    SaShortcutStore.capture_defaults()
    var late := &"f56_late_override"
    var registries := SaRegistries.new()
    registries.build_context(func() -> Variant: return null, func() -> Array: return [])
    var command := SaCommandDescriptor.create(late, "Late And Ordinary", func() -> void: pass)
    command.default_events = [SaShortcutStore.parse_chord("Ctrl+Alt+J")]
    registries.context.for_module(&"f56-test").register_command(command)

    var overrides := SaShortcutStore.overrides_now()
    assert_false(
        overrides.has(String(late)),
        "An action at the chord its build ships is not an override, %s" % str(overrides.get(String(late)))
    )
    InputMap.erase_action(late)
