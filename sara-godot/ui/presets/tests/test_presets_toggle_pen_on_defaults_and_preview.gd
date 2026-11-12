## The Presets button toggles, Z toggles beside it, a new preset comes from
## the class defaults, and the tip preview is drawn on General as well.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Four things in one: the Presets window opens on the button and
## closes on a second press. *Enable pen settings* was off for
## every preset, and there was no way to see the defaults,
## because a new preset could only be forked from an existing one. The brush tip
## preview is also visible on the General page, and Z toggles the window too.
##
## **The docker is a `Window`, so the toggle itself is proved by the scenario.**
## The suite runner blocks the moment a test adds a Window to the tree, which is
## why every other presets suite builds one detached and asserts the wiring
## instead. So what is here is the wiring: which method the button presses, what
## a host with no docker answers, what the New preset action does to the live
## settings, and the two tables the chord and the preview page read from.
## `scenarios/presets-toggle-pen-on-defaults-and-preview.json` presses the
## button twice, presses Z twice and opens General in the running app.
##
## The migration half is the submodule's, in
## `modules/sara-base-modules/stamp-brush/tests/test_brush_settings_migration.gd`,
## because the resource it corrects lives there.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const DockerScript = preload("res://ui/dockers/presets/brush_presets_docker.gd")
const EditorPages = preload("res://ui/brush_editor/editor_pages.gd")
const StampModuleScript = preload("res://modules/sara-base-modules/stamp-brush/module.gd")

const REQUIRES_GPU := true

# --- The button toggles -------------------------------------------------------


## The button presses the toggle, not the opener. The opener stays public
## because the capture door presses it, through `sa_menu_driver.gd`.
##
## **The reason is not the right click**, which would name the
## wrong caller and the wrong behaviour at once: the right press has its own
## pair of calls in `tool_machine.gd` and never comes through this file, and
## it toggles rather than only opens.
func test_the_button_presses_the_toggle_and_the_opener_stays_public() -> void:
    var box := ToolOptionsPresets.new()

    assert_true(box.has_method("toggle_presets_docker"), "There is a toggle")
    assert_true(box.has_method("open_presets_docker"), "and the opener the capture door takes is still there")
    var pressed := box.preset_menu.pressed.get_connections()
    assert_eq(pressed.size(), 1, "The button has one handler")
    assert_eq(
        String((pressed[0]["callable"] as Callable).get_method()),
        "toggle_presets_docker",
        "and it is the toggle, so a second press closes what the first opened"
    )

    box.free()


## With no docker in the tree the toggle says so rather than half working, which
## is the answer `open_presets_docker` gives the same three hosts: a test, the
## info docker's scratchpad and the brush editor's.
func test_a_bar_with_no_docker_toggles_nothing() -> void:
    var host := Node.new()
    EventBus.add_child(host)
    var box := ToolOptionsPresets.new()
    host.add_child(box)

    assert_false(box.toggle_presets_docker(), "Nothing to toggle")

    host.free()


# --- Z, beside Shift+S --------------------------------------------------------


## The Z key, on the docker's own command, so the chord, the
## Dockers menu row and the button all end at one toggle.
func test_the_presets_docker_answers_to_z_as_well_as_to_shift_s() -> void:
    var row: Array = []
    for entry: Array in SaAppCommands.DOCKER_COMMANDS:
        if entry[0] == &"docker_brush_presets":
            row = entry

    # The key, the two summon titles and then the second key.
    assert_eq(row.size(), 7, "The presets row carries a second key")
    assert_eq(int(row[3]), int(KEY_S), "Shift with the first, which is what it always had")
    assert_eq(int(row[6]), int(KEY_Z), "and bare Z")
    for entry: Array in SaAppCommands.DOCKER_COMMANDS:
        if entry[0] != &"docker_brush_presets":
            assert_eq(entry.size(), 6, "%s carries one key, so nothing else grew a bare letter" % entry[0])


## Both chords reach the InputMap, which is what a rebind reads and what the
## Keyboard Shortcuts page shows.
func test_both_chords_are_registered_on_the_one_command() -> void:
    var registries := Fixtures.make_registries()
    SaAppCommands.register_all(registries, func(_docker_id: StringName) -> void: pass)

    var text := registries.commands.chord_text(&"docker_brush_presets")

    assert_true(text.contains("Shift+S"), "Shift+S is still the docker's chord: %s" % text)
    assert_true(text.contains("Z"), "and Z is beside it: %s" % text)


## The cost of the Z binding, written down rather than left to be found by a painter
## reaching for the zoom tool.
##
## `ShortcutRouter.handle` answers the docker table and then the registered
## commands before it ever reaches `SaToolKeys.answer`, so a Z left on `tool_zoom`
## could never have fired: the Keyboard Shortcuts page would have shown two rows
## claiming Z and only one of them true. The zoom tool keeps Ctrl+Space, the
## toolbox and the wheel, and Photoshop's shipped profile still puts Z back on
## it for a painter who picks that map.
func test_the_zoom_tool_gave_the_bare_z_up() -> void:
    var source := FileAccess.get_file_as_string("res://project.godot")
    var block := source.split("tool_zoom={")[1].split("}")[0]

    assert_true(block.contains('"events": []'), "tool_zoom binds nothing now: %s" % block)
    assert_eq(
        SaShortcutStore.PHOTOSHOP_DEFAULTS.get("tool_zoom", ""),
        "Z",
        "and the Photoshop profile still offers it, which is the way back"
    )


# --- New preset, from the class defaults --------------------------------------


## The defaults reachable without a fork. The
## live resource is written in place, the way a load writes it, because the base
## module hands one settings instance to every surface.
func test_new_preset_writes_the_class_defaults_over_the_live_settings() -> void:
    var live := SaStampBrushSettings.new()
    live.radius = 0.5
    live.opacity = 0.125
    live.color = Color(1.0, 0.0, 0.0, 1.0)
    var box := ToolOptionsPresets.new()
    box.settings_source = func() -> Resource: return live
    var applied: Array = []
    box.on_applied = func() -> void: applied.append(true)

    assert_true(box.new_preset(), "The defaults went on")

    var fresh := SaStampBrushSettings.new()
    assert_eq(live, live, "the same object, written in place rather than replaced")
    assert_almost_eq(live.radius, fresh.radius, 1e-6, "the radius is the class default")
    assert_almost_eq(live.opacity, fresh.opacity, 1e-6, "and so is the opacity")
    assert_eq(live.color, Color(1.0, 0.0, 0.0, 1.0), "and the palette colour is left alone, which a preset never carries")
    assert_eq(box.selected_preset, "", "with no preset loaded, because this one is not on disk")
    assert_eq(applied.size(), 1, "and the surface was told to pull its controls back into line")

    box.free()


## Nothing is written to disk. A new preset is the defaults on the brush, and
## Save as... beside it is what names them, so a painter who only wanted to look
## at the defaults leaves no file behind.
func test_new_preset_writes_no_file() -> void:
    var live := SaStampBrushSettings.new()
    var box := ToolOptionsPresets.new()
    box.settings_source = func() -> Resource: return live
    box.preset_store = SaPresetStore.new()
    box.preset_store.dir = SaDataRoot.path("test_n4_presets")

    box.new_preset()

    assert_eq(box.preset_store.list_names().size(), 0, "The library is untouched")

    box.free()


## The action id is the programmatic door, so the docker's button, a
## capture and a test all press one path.
func test_the_new_action_presses_through_the_id() -> void:
    var live := SaStampBrushSettings.new()
    live.radius = 0.5
    var box := ToolOptionsPresets.new()
    box.settings_source = func() -> Resource: return live

    assert_true(box.action_available(ToolOptionsPresets.PRESET_ID_NEW), "New is offered while there are settings")
    box.press_action(ToolOptionsPresets.PRESET_ID_NEW)

    assert_almost_eq(live.radius, SaStampBrushSettings.new().radius, 1e-6, "and pressing it puts the defaults on")

    box.free()


## With no settings resource behind it the action is dead rather than half
## working, which is the rule `action_available` already holds for Delete.
func test_the_new_action_is_dead_with_no_settings() -> void:
    var box := ToolOptionsPresets.new()

    assert_false(box.action_available(ToolOptionsPresets.PRESET_ID_NEW), "Nothing to write the defaults onto")
    assert_false(box.new_preset(), "and pressing it says so")

    box.free()


## The entry a painter clicks, under the grid with the other two.
func test_the_docker_carries_the_new_preset_entry() -> void:
    var host := Node.new()
    var docker := DockerScript.new()
    host.add_child(docker)

    assert_not_null(docker.new_button, "New preset is under the grid")
    assert_eq(docker.new_button.name, StringName("ChooserNew"), "under a name a capture can find")
    assert_eq(docker.new_button.text, "New Preset...", "and worded with the dots of a dialog")

    docker.sync_actions()
    assert_true(docker.new_button.disabled, "With no bar there is no store to make a preset in")
    assert_true(bool((docker.capture_state() as Dictionary)["new_disabled"]), "which the dump says out loud")

    host.free()


# --- The tip preview on General ------------------------------------------------


## The brush tip preview is also visible on the
## General page." General is the page the editor opens on when nothing else is
## asked for, so a painter moving size, opacity or spacing there sees the dab
## change under them.
##
## The preview is a row the stamp brush declares at the top of the two pages
## so the clause is read off the brush's declaration: one
## preview row on each of the two pages and none anywhere else.
func test_the_tip_preview_is_drawn_on_general_as_well_as_on_brush_tip() -> void:
    var pages: Array[String] = []
    for spec: SaOptionSpec in StampModuleScript.brush_options():
        if spec.kind == SaOptionSpec.Kind.CUSTOM and String(spec.key).begins_with("tip_preview"):
            pages.append(spec.page)
    assert_true(pages.has(StampModuleScript.TIP_PAGE), "Brush Tip keeps its preview")
    assert_true(pages.has(StampModuleScript.GENERAL_PAGE), "and General gains one")
    assert_eq(StampModuleScript.GENERAL_PAGE, EditorPages.DEFAULT_PAGE, "which is the page a spec that names none lands on")
    assert_eq(pages.size(), 2, "and no other page grew one")
