## A shipped shortcut profile hands a chord to an action that never gets it.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Driving a painting session under each shipped profile finds the exact
## thing to avoid: the Keyboard Shortcuts page
## showing two rows that claim one chord, only one of which is true.
##
## `SaShortcutStore.PHOTOSHOP_DEFAULTS` gives `tool_zoom` the bare Z, and
## `SaAppCommands.DOCKER_COMMANDS` gives `docker_brush_presets` the bare Z beside
## its S. `apply_profile` restores the shipped map and lays the profile's
## overrides on top, and it removes nothing, so both actions hold Z. Since
## `ShortcutRouter.handle` asks the docker table before the tools, the docker
## wins and the zoom tool is unreachable from the keyboard for a painter who
## picked the Photoshop map.
##
## Proved on the running app by
## `scenarios/the-z-key-under-a-profile.json`: under Photoshop, one Z leaves
## `canvases[0].motion.tool` at `brush` and flips the Brush Presets docker from
## hidden to shown.
##
## **Fixed by f8**, which is why these are `test_` now. `apply_profile` takes an
## overridden chord off whatever else still answered to it, so the tables may go
## on overlapping and the map that comes out of a switch does not.
##
## Applying a profile rebinds the live InputMap, so every case here puts it back
## the way `core/registry/tests/test_shortcut_profiles.gd` does, the actions a
## profile wrote into being erased with the rest. Restoring the events alone left
## Photoshop's `edit_preferences` on Ctrl+K whenever this suite ran before the
## app's commands were built, and `test_rebind_survives`, `test_shortcut_editor`
## and `test_text_box_keyboard` then read it as a painter's override.
extends "res://tests/test_framework.gd"

## Every action's events as they were before a case ran.
var _saved_events: Dictionary = {}

## The actions there were before a case ran, so the ones it made can go.
var _saved_actions: Array[StringName] = []


func before_each() -> void:
    _saved_events.clear()
    for action: StringName in InputMap.get_actions():
        _saved_events[action] = InputMap.action_get_events(action).duplicate()
    _saved_actions.assign(InputMap.get_actions())


func after_each() -> void:
    for action: StringName in _saved_events:
        InputMap.action_erase_events(action)
        for event: InputEvent in _saved_events[action]:
            InputMap.action_add_event(action, event)
    for action: StringName in InputMap.get_actions():
        if not _saved_actions.has(action):
            InputMap.erase_action(action)


## The action that stands in for the Brush Presets docker's row.
const PROBE: StringName = &"t1_probe_docker"


## Gives `PROBE` *chords* and records them as the ones it shipped with, which is
## the door a command already uses as it registers. The action is erased
## again in `after_each`, and the record it leaves behind names an action the
## InputMap no longer has, which `apply_profile` skips for that very reason.
func _probe(chords: Array) -> void:
    if not InputMap.has_action(PROBE):
        InputMap.add_action(PROBE)
    SaShortcutStore.set_chords(PROBE, chords)
    SaShortcutStore.remember_shipped(PROBE)


## Every chord a `DOCKER_COMMANDS` row claims, as the text a profile table would
## spell it with, mapped to the row's action id.
##
## The rows are `[id, docker_id, title, key, ...]`, so everything from index 3 on
## is a keycode. `OS.get_keycode_string` is what turns one into the spelling
## `SaShortcutStore`'s tables use, rather than a second table to keep in step.
func _docker_chords() -> Dictionary:
    var out: Dictionary = {}
    for row: Array in SaAppCommands.DOCKER_COMMANDS:
        # The key is the fourth element and a second key the seventh, after
        # the two summon titles.
        for i: int in [3, 6]:
            if i < row.size():
                out[OS.get_keycode_string(int(row[i]))] = String(row[0])
    return out


## The docker rows really do claim the chords this test reads, so a change that
## empties the table cannot make the case below pass by accident.
func test_the_docker_rows_claim_the_chords_this_reads() -> void:
    var chords := _docker_chords()

    assert_false(chords.is_empty(), "the docker command table claims at least one chord")
    assert_eq(chords.get("Z", ""), "docker_brush_presets", "and Z is the presets docker's, which it is given")


## Applying a shipped profile leaves nobody else holding a chord it claimed.
##
## The tables still overlap, deliberately: Photoshop's map says Z is the zoom
## tool and Sara's own says Z is the presets docker, and a profile is the place
## a painter settles that. What changed for f8 is that the settling happens,
## rather than both rows standing and `ShortcutRouter.handle` picking by the
## order it asks its groups in.
##
## The docker is stood in for by an action of this suite's own. `apply_profile`
## puts the shipped map back before it lays a profile over it, so a chord added
## to a real action by hand is undone before the release can see it, and the
## only way to exercise the release is an action whose *shipped* chords are the
## ones that clash. `docker_brush_presets` is exactly that in the app and does
## not exist in a headless run at all, which is what `_probe` is for.
func test_a_shipped_profile_takes_the_chord_off_whatever_held_it() -> void:
    assert_eq(_docker_chords().get("Z", ""), "docker_brush_presets", "Z is the presets docker's on the build map")
    _probe(["S", "Z"])

    SaShortcutStore.apply_profile("Photoshop")

    assert_eq(SaShortcutStore.chords_for(&"tool_zoom"), ["Z"], "the profile's own row keeps the key it asked for")
    assert_eq(SaShortcutStore.chords_for(PROBE), ["S"], "and the other gives Z up while keeping its S")
    assert_eq(SaShortcutStore.conflicts("Z", &"tool_zoom"), [] as Array[String], "so nothing else answers to Z here")


## Switching back gives the key to whoever the shipped map had it on, which is
## what makes the release a profile's doing rather than a loss.
func test_leaving_the_profile_gives_the_chord_back() -> void:
    _probe(["S", "Z"])

    SaShortcutStore.apply_profile("Photoshop")
    SaShortcutStore.apply_profile(SaShortcutStore.DEFAULT_PROFILE)

    assert_eq(SaShortcutStore.chords_for(PROBE), ["S", "Z"], "the shipped chord is back")


## The release reads the rest of the map and not the profile's own rows, so a
## map that hands out several chords still holds every one of them afterwards.
func test_the_release_leaves_the_profiles_own_rows_alone() -> void:
    _probe(["S", "Z"])

    SaShortcutStore.apply_profile("Photoshop")

    var table: Dictionary = SaShortcutStore.SHIPPED_PROFILES["Photoshop"]
    var missing: Array[String] = []
    for action: String in table:
        # An empty entry is a row the profile *clears*, `layer_alpha_lock` under
        # Krita and `docker_maximise` under both, so there is no chord for it to
        # still answer to and the claim below is not about it.
        if String(table[action]).is_empty():
            continue
        if (
            InputMap.has_action(StringName(action))
            and not SaShortcutStore.chords_for(StringName(action)).has(String(table[action]))
        ):
            missing.append(action)
    assert_eq(missing, [] as Array[String], "every row Photoshop names still answers to the chord it named")


## f20, fixed. The Dockers menu kept the chord it was built with.
##
## `MainDockers.setup_dockers_menu` snapshots the InputMap into a `Shortcut`
## resource per docker row, and a `PopupMenu` shortcut is dispatched by Godot
## itself before any of Sara's own doors see the key. Nothing rebuilds the menu
## when the map changes: `EventBus.shortcuts_changed` reaches `main.gd`, which
## re-emits the command registry's `changed`, and the Dockers menu is not built
## from that registry.
##
## So f8's release did its half and the menu undid it. Under the Photoshop
## profile `docker_brush_presets` holds Shift+S alone and `tool_zoom` holds Z,
## and a bare Z still toggled the Brush Presets docker, off the menu row's
## frozen copy: `scenarios/a-profile-chord-the-router-never-delivers.json`,
## dumps 5 and 6, with Shift+S closing the same docker in between. The same
## scenario now reads `zoom` there, and
## `scenarios/the-dockers-menu-follows-the-map.json` drives the rebind door
## beside the profile one.
##
## Read off the source rather than driven, for the reason
## `ui/shortcuts/tests/test_escape_closes_docker.gd` records: a `Window` added to the tree
## in a headless run hangs the suite, and a `PopupMenu` needs its MenuBar.
func test_f20_the_dockers_menu_is_rebuilt_when_the_map_changes() -> void:
    var text := FileAccess.get_file_as_string("res://ui/main/main_dockers.gd")
    assert_false(text.is_empty(), "the file is readable")
    assert_true(
        text.contains("EventBus.shortcuts_changed.connect(setup_dockers_menu)"),
        "the Dockers menu rebuilds its shortcuts when the map changes"
    )
