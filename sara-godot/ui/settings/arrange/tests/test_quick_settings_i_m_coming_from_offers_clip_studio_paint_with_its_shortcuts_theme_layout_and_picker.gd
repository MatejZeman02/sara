## Quick settings' "I'm coming from" offers Clip Studio Paint, with its
## shortcuts, theme, layout and picker.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The row stands in the tree over a layout store of the suite's own on a
## scratch file, and a press is spread over frames, each one an emission of the
## tree's `process_frame` and a call of the row's `_process`, the way the suite for
## choosing a program drives it, so the frame rule is read for the new program as well. The
## commands are the app's, registered the way the menu suites register them,
## so a chord is read on the action a key would reach. Every setting the row
## writes is put back after each test with the map applied again.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

const HOST := Vector2i(1920, 1048)
const BOUND_USEC: int = 100000
const MOST_FRAMES: int = 2000
const KEYS: Array[String] = ["shortcuts_profile", "theme_name", "color_picker_shape", "reset_zoom"]
const PROGRAM := "clip_studio"
## Ten of Clip Studio Paint's chords, each on the command it reaches.
const SAMPLE: Dictionary[String, String] = {
    "edit_redo": "Ctrl+Y",
    "layer_new_paint": "Ctrl+Shift+N",
    "layer_merge_visible": "Ctrl+Shift+E",
    "layer_clip_to_below": "Ctrl+Alt+G",
    "layer_group": "Ctrl+G",
    "view_actual_pixels": "Ctrl+Alt+0",
    "view_rotate_left": "-",
    "tool_bucket_fill": "G",
    "tool_wand": "W",
    "tool_eyedropper": "I",
}

static var scratch_layout_path: String = SaDataRoot.path("test_clip_studio_layout.cfg")

var _registries: SaRegistries = null
var _root: Node = null
var _store: DockerLayoutStore = null
var _row: SaComingFromRow = null
var _saved_layout_state := ConfigFile.new()
var _saved := {}


func before_each() -> void:
    for key: String in KEYS:
        _saved[key] = SaSettings.get(key)
        SaSettings.set(key, (SaSettingsValues as Script).get_property_default_value(key))
    _registries = Fixtures.make_menu_registries()
    SaShortcutStore.capture_defaults()
    SaTheme.use_named(SaSettings.theme_name)
    SaShortcutStore.apply_profile(SaSettings.shortcuts_profile)
    _saved_layout_state = ConfigFile.new()
    _root = Node.new()
    _root.name = "TestHost"
    EventBus.add_child(_root)
    var viewport := SubViewport.new()
    viewport.size = HOST
    viewport.gui_embed_subwindows = true
    _root.add_child(viewport)
    var host := Control.new()
    host.set_anchors_preset(Control.PRESET_FULL_RECT)
    viewport.add_child(host)
    var docker := Window.new()
    docker.size = Vector2i(200, 150)
    host.add_child(docker)
    _store = DockerLayoutStore.new()
    _store.path = scratch_layout_path
    _store.dockers_provider = func() -> Array: return [{"id": "ProbeDocker", "name": "Probe", "node": docker}]
    _store.save_allowed = func() -> bool: return true
    _store.presets().capture(_saved_layout_state)
    _row = SaComingFromRow.new(_store)
    host.add_child(_row)


func after_each() -> void:
    _settle()
    _row.free()
    _store.presets().apply(_saved_layout_state)
    _store.free()
    _root.free()
    _registries = null
    for key: String in _saved:
        SaSettings.set(key, _saved[key])
    SaTheme.use_named(SaSettings.theme_name)
    SaShortcutStore.apply_profile(SaSettings.shortcuts_profile)
    EventBus.shortcuts_changed.emit()
    DirAccess.remove_absolute(scratch_layout_path)


## One harness frame, and how long it took in microseconds.
func _frame() -> int:
    var started := Time.get_ticks_usec()
    (Engine.get_main_loop() as SceneTree).process_frame.emit()
    _row._process(0.0)
    return Time.get_ticks_usec() - started


## Frames until no press and no palette slice is left, answering each frame's
## time.
func _settle() -> Array[int]:
    var times: Array[int] = []
    while (_row.pressing() or SaTheme.repainting()) and times.size() < MOST_FRAMES:
        times.append(_frame())
    return times


## Clip Studio Paint pressed, spread over the frames after it as the row does
## on screen, and every frame of it under a tenth of a second.
func _press_clip_studio() -> void:
    _row.press(PROGRAM)
    var times := _settle()
    assert_false(_row.pressing(), "the press ended within %d frames" % MOST_FRAMES)
    var longest := 0
    for time: int in times:
        longest = maxi(longest, time)
    assert_true(longest <= BOUND_USEC, "no frame of the press held Sara past a tenth of a second, the longest %d us" % longest)


func test_the_row_offers_clip_studio_paint_after_krita_photoshop_and_procreate() -> void:
    assert_eq(_row.buttons.keys(), ["krita", "photoshop", "procreate", "clip_studio"], "four buttons, Clip Studio Paint's last")
    assert_eq(_row.buttons[PROGRAM].text, "Clip Studio Paint", "the button is named after the program")


func test_clip_studio_puts_its_five_values_in_force() -> void:
    _press_clip_studio()
    assert_eq(SaSettings.shortcuts_profile, "Clip Studio Paint", "the shortcut profile is Clip Studio Paint's")
    assert_eq(SaSettings.theme_name, "clip_studio", "the palette is Clip Studio Dark")
    assert_eq(SaTheme.palette_id, "clip_studio", "and SaTheme draws with it")
    assert_eq(_store.current_preset(), "clip_studio", "the layout is Clip Studio Paint's")
    assert_eq(SaSettings.color_picker_shape, "hsv_square", "the picker is the HSV square in its hue ring")
    assert_eq(SaSettings.reset_zoom, SaView.RESET_WHOLE, "Ctrl+0 shows the whole picture, Fit to Navigator")
    assert_eq(SaComingFromRow.in_force(_store), PROGRAM, "Clip Studio Paint is the program in force")
    assert_true(_row.buttons[PROGRAM].button_pressed, "and its button shows pressed")
    assert_false(_row.buttons["photoshop"].button_pressed, "Photoshop's, which shares its picker and Ctrl+0, does not")


func test_ten_of_its_chords_reach_their_commands_and_none_reaches_two() -> void:
    _press_clip_studio()
    for action: String in SAMPLE:
        var chord := SAMPLE[action]
        assert_true(
            SaShortcutStore.chords_for(StringName(action)).has(chord),
            "%s answers %s, it holds %s" % [action, chord, SaShortcutStore.chords_for(StringName(action))]
        )
        assert_eq(
            SaShortcutStore.conflicts(chord, StringName(action)), [] as Array[String], "%s reaches %s alone" % [chord, action]
        )


func test_every_chord_of_the_table_reaches_one_command() -> void:
    _press_clip_studio()
    for action: String in SaShortcutClipStudioTable.CHORDS:
        var chord := SaShortcutClipStudioTable.CHORDS[action]
        if chord.is_empty():
            assert_eq(SaShortcutStore.chords_for(StringName(action)), [] as Array[String], "%s is left unbound" % action)
            continue
        var held := SaShortcutStore.chords_for(StringName(action))
        assert_true(held.has(chord), "%s answers %s, it holds %s" % [action, chord, held])
        assert_eq(
            SaShortcutStore.conflicts(chord, StringName(action)), [] as Array[String], "%s reaches %s alone" % [chord, action]
        )


func test_a_second_press_puts_sara_s_own_back() -> void:
    _press_clip_studio()
    _press_clip_studio()
    assert_true(SaComingFromRow.holds(SaComingFromRow.OWN_VALUES, _store), "Sara's own values are in force again")
    assert_eq(SaComingFromRow.in_force(_store), "", "with no program")
    assert_eq(SaShortcutStore.chords_for(&"edit_redo").has("Ctrl+Y"), false, "and Ctrl+Y is no longer redo")
    var redo := InputEventKey.new()
    redo.keycode = KEY_Y
    redo.ctrl_pressed = true
    redo.pressed = true
    assert_true(InputMap.event_is_action(redo, &"ui_redo", true), "but a text box still redoes on the engine's own Ctrl+Y")


## The palette and the layout are listed where the others are, so the
## Appearance page and the Layouts and dockers page offer them.
func test_the_palette_and_the_layout_are_listed_beside_the_others() -> void:
    assert_true(SaTheme.PALETTES.has("clip_studio"), "the palette is among the colour themes")
    var palette := load(SaTheme.PALETTES["clip_studio"]) as SaPalette
    assert_eq(palette.display_name, "Clip Studio Dark", "under its name")
    assert_true(SaDockerLayoutPresets.SHIPPED.has("clip_studio"), "the layout is among the shipped layouts")
    assert_eq(
        SaDockerLayoutPresets.SHIPPED_TITLES["clip_studio"], "Clip Studio", "in title case as the other shipped layouts read"
    )
    assert_true(SaShortcutStore.list_profiles().has("Clip Studio Paint"), "and the shortcut profile among the profiles")
