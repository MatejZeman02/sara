## Ctrl+Space and the maximise button.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Ctrl+Space toggles maximalisation of the currently selected docker or dialog
## window, as in Blender, and a maximise button sits next to the close button
## of every docker, optionally.
##
## The button on a real drag bar and the docker filling the window are
## `scenarios/ctrl-space-maximises-the-focused-docker.json`, because a
## DockerWindow in the tree maps a real OS window and hangs a headless run, which
## is the same reason `test_docker_hide_button.gd` gives. What is here is the
## half no capture can show: that the chord declines when nothing is focused, so
## the quick zoom tool keeps the key over the canvas, that the two shipped
## profiles clear it, and that the layout store never learns a maximised
## rectangle.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## What the profile held for the switch when the suite started, null when it
## held nothing, put back after each test so a run does not quietly change a
## preference the person set.
var _saved_switch: Variant


## A window off the tree, which is what the toggle is written against: it reads
## `position` and `size` and asks `DockerDragHandle` for the host, and none of
## the three needs a docker.
func _window(at: Vector2i, of_size: Vector2i) -> Window:
    var window := Window.new()
    window.title = "Scratch"
    window.position = at
    window.size = of_size
    return window


func before_each() -> void:
    var section := SaSettingsFile.module_section(SaDockerMaximise.MODULE_ID)
    var held := SaSettings.config.has_section_key(section, String(SaDockerMaximise.SWITCH_KEY))
    _saved_switch = SaSettings.module_preference(SaDockerMaximise.MODULE_ID, SaDockerMaximise.SWITCH_KEY) if held else null


func after_each() -> void:
    SaSettings.set_module_preference(SaDockerMaximise.MODULE_ID, SaDockerMaximise.SWITCH_KEY, _saved_switch)


# --- The toggle ----------------------------------------------------------------


func test_a_window_fills_its_host_and_comes_back_to_the_rectangle_it_left() -> void:
    var window := _window(Vector2i(120, 90), Vector2i(300, 200))
    var host := SaDockerMaximise.host_rect(window)

    SaDockerMaximise.toggle(window)

    assert_true(SaDockerMaximise.is_maximised(window), "the window says it is filling its host")
    assert_eq(window.position, host.position, "and sits at the host's corner")
    assert_eq(window.size, host.size, "at the host's size")

    SaDockerMaximise.toggle(window)

    assert_false(SaDockerMaximise.is_maximised(window), "the same call puts it back")
    assert_eq(window.position, Vector2i(120, 90), "at the position it left")
    assert_eq(window.size, Vector2i(300, 200), "and the size it left")
    window.free()


## The restore reads the rectangle from the window rather than from a member of
## this file, so a second window maximised in between cannot be given the first
## one's geometry back.
func test_two_windows_each_remember_their_own_rectangle() -> void:
    var first := _window(Vector2i(10, 20), Vector2i(200, 100))
    var second := _window(Vector2i(300, 400), Vector2i(150, 250))

    SaDockerMaximise.toggle(first)
    SaDockerMaximise.toggle(second)
    SaDockerMaximise.toggle(first)
    SaDockerMaximise.toggle(second)

    assert_eq(first.position, Vector2i(10, 20), "the first window is where it was")
    assert_eq(second.position, Vector2i(300, 400), "and so is the second")
    assert_eq(first.size, Vector2i(200, 100), "at its own size")
    assert_eq(second.size, Vector2i(150, 250), "and the other at its own")
    first.free()
    second.free()


## Nothing is left on a window that has been put back, so a dump and the layout
## store both read it as an ordinary docker again.
func test_the_kept_rectangle_leaves_the_window_when_it_is_restored() -> void:
    var window := _window(Vector2i(0, 0), Vector2i(120, 120))

    SaDockerMaximise.toggle(window)
    SaDockerMaximise.toggle(window)

    assert_false(window.has_meta(SaDockerMaximise.KEPT_META), "the metadata goes with the state")
    window.free()


func test_nothing_focused_is_said_rather_than_crashed() -> void:
    assert_true(SaDockerMaximise.toggle(null).contains("nothing is focused"), "a null window is a sentence, not a crash")


# --- The chord -----------------------------------------------------------------


func _router() -> ShortcutRouter:
    var router := ShortcutRouter.new()
    router.canvas_provider = func() -> SaCanvas: return null
    router.tool_machine_provider = func() -> ToolMachine: return null
    return router


func test_the_command_ships_on_ctrl_space_in_the_sara_map() -> void:
    var registries := Fixtures.make_registries()
    var router := _router()
    router.bind_commands(registries.commands)

    var command := registries.commands.get_descriptor(&"docker_maximise")

    assert_not_null(command, "the router registers the command")
    assert_eq(SaCommandRegistry.format_events(command.default_events), "Ctrl+Space", "on the chord the request asks for")
    assert_eq(String(command.category), "docker", "under the dockers on the Keyboard Shortcuts page")
    router.free()


## The whole of how F1 and the rule "the zoom tool keeps Ctrl+Space" both stand.
## A quick tool is a key leaned on over the canvas, where the main window has the
## keyboard and no subwindow does, so the command declines and the event travels
## on. A handler returning false is what `SaCommandRegistry.try_handle_input`
## reads as a decline.
func test_the_chord_declines_when_no_subwindow_holds_the_keyboard() -> void:
    var router := _router()

    var event := InputEventKey.new()
    event.keycode = KEY_SPACE
    event.physical_keycode = KEY_SPACE
    event.ctrl_pressed = true
    event.pressed = true

    assert_false(router.handle(event), "nothing focused means nothing to maximise")
    router.free()


func test_the_quick_zoom_tool_still_answers_the_same_chord() -> void:
    assert_true(InputMap.has_action(&"tool_zoom_quick"), "the held zoom is still an action")
    var chords := SaShortcutStore.chords_for(&"tool_zoom_quick")
    assert_true(chords.has("Ctrl+Space"), "and still on Ctrl+Space, which it keeps: %s" % ", ".join(chords))


## A dialog is not a docker, so `handle_docker_input` declines every chord that
## is not on this list, and the request asks for the dialog as well as the docker.
func test_a_dialog_answers_the_chord() -> void:
    assert_true(ShortcutRouter.WINDOW_CHORDS.has("docker_maximise"), "the chord is one a dialog still answers")


func test_both_shipped_profiles_clear_the_chord() -> void:
    for profile: String in ["Krita", "Photoshop"]:
        var table: Dictionary = SaShortcutStore.SHIPPED_PROFILES[profile]
        assert_true(table.has("docker_maximise"), "%s names the maximise" % profile)
        assert_eq(String(table["docker_maximise"]), "", "and clears it, because %s has no docker maximise" % profile)


# --- The button and its option -------------------------------------------------


func test_the_switch_is_off_until_something_turns_it_on() -> void:
    SaSettings.set_module_preference(SaDockerMaximise.MODULE_ID, SaDockerMaximise.SWITCH_KEY, null)
    assert_false(SaDockerMaximise.button_wanted(), "a profile that never set it has no maximise button")
    var switch := SaDockerMaximise.new()
    switch.button_on = true
    assert_true(SaDockerMaximise.button_wanted(), "and the one switch is what draws it")
    switch.button_on = false
    assert_false(SaDockerMaximise.button_wanted(), "and takes it away")


## A module's preference is announced as its id, a slash and its key, and a
## docker hears the switch by that name alone.
func test_the_switch_is_announced_under_its_own_name() -> void:
    var heard: Array[StringName] = []
    var listen := func(property: StringName) -> void: heard.append(property)
    SaSettings.changed.connect(listen)
    SaDockerMaximise.new().button_on = not SaDockerMaximise.button_wanted()
    SaSettings.changed.disconnect(listen)
    assert_eq(heard.size(), 1, "one announcement")
    assert_true(heard.size() == 1 and SaDockerMaximise.names_the_switch(heard[0]), "under the switch's own name")
    assert_false(SaDockerMaximise.names_the_switch(&"docker_hide_button"), "and the hide switch's is not it")


## One switch for every docker, on Layouts and dockers, and the row a scenario names by its key is the switch a hand
## presses.
func test_layouts_and_dockers_draws_the_switch_and_a_step_reaches_it() -> void:
    SaDockerMaximise.new().button_on = false
    var page := SaDockersPage.new()
    var row := page.page.row(&"maximise_button")

    assert_not_null(row, "the page carries the row, by the key a scenario names")
    assert_true(row.control is CheckButton, "as a switch, which is what an on or off is")
    assert_eq(row.label, "Maximize button", "under the title the drag bar's tooltip spells the same way")
    row.drive(true)
    assert_true(SaDockerMaximise.button_wanted(), "and driving it writes the switch every docker reads")
    page.free()


# --- What the layout store does not learn ---------------------------------------


## The requirement: "the current preset's file is byte for byte
## what it was before". A maximised docker is skipped outright, so the stored
## rectangle is the one the painter left and no restore is needed to get it back.
func test_the_store_steps_over_a_maximised_docker() -> void:
    var window := _window(Vector2i(40, 50), Vector2i(220, 180))
    var store := DockerLayoutStore.new()
    store.path = SaDataRoot.path("test_f1_layout.cfg")
    store.save_allowed = func() -> bool: return true
    # Both keys, because `section_for` reads `config["name"]` as the default
    # argument to `get`, which GDScript evaluates whether or not the id is there.
    store.dockers_provider = func() -> Array: return [{"id": "Scratch", "name": "Scratch", "node": window}]

    store.save(true)
    var before := FileAccess.get_file_as_bytes(store.path)
    SaDockerMaximise.toggle(window)
    store.save(true)
    var after := FileAccess.get_file_as_bytes(store.path)

    assert_eq(after, before, "the file a maximise left is the file the maximise found")
    SaDockerMaximise.toggle(window)
    DirAccess.remove_absolute(ProjectSettings.globalize_path(store.path))
    store.free()
    window.free()
