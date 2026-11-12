## Quick settings' "I'm coming from" offers Procreate, with its gestures,
## theme, layout and picker.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The row is built over a layout store of the suite's own on a scratch file,
## as the suite for Sara's own button builds one, so a press loads its layout into that store
## and never into the running window. Every value a press writes is put back
## after each test. The three-finger tap that redoes is read by
## `tools/fingers/tests/test_a_three_finger_tap_redoes.gd`.
extends "res://tests/test_framework.gd"

## A sample of Procreate's keyboard shortcuts, chord -> the command it is to
## run once Procreate is pressed.
const SAMPLE: Dictionary[String, String] = {
    "Ctrl+Z": "edit_undo",
    "Ctrl+Shift+Z": "edit_redo",
    "Ctrl+C": "edit_copy",
    "Ctrl+A": "select_all",
    "B": "tool_brush",
    "V": "tool_transform",
    "L": "docker_layers",
    "C": "docker_color_selector",
    "]": "brush_size_increase",
    "[": "brush_size_decrease",
    "Ctrl+Equal": "view_zoom_in",
}

const HOST := Vector2i(1920, 1048)
static var scratch_layout_path: String = SaDataRoot.path("test_layout.cfg")

var _root: Node = null
var _store: DockerLayoutStore = null
var _row: SaComingFromRow = null
var _saved_layout_state := ConfigFile.new()
var _saved := {}
var _saved_events: Dictionary = {}
var _saved_actions: Array = []


func before_each() -> void:
    _saved_events.clear()
    for action: StringName in InputMap.get_actions():
        _saved_events[action] = InputMap.action_get_events(action).duplicate()
    _saved_actions.assign(InputMap.get_actions())
    for key: String in ["shortcuts_profile", "theme_name", "color_picker_shape", "reset_zoom"]:
        _saved[key] = SaSettings.get(key)
        # A fresh settings folder's value, which is the property's default.
        SaSettings.set(key, (SaSettingsValues as Script).get_property_default_value(key))
    SaShortcutStore.apply_profile(SaSettings.shortcuts_profile)
    _root = Node.new()
    _root.name = "U535Host"
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
    _saved_layout_state = ConfigFile.new()
    _store.presets().capture(_saved_layout_state)
    _row = SaComingFromRow.new(_store)


func after_each() -> void:
    _row.free()
    _store.presets().apply(_saved_layout_state)
    _store.free()
    _root.free()
    for key: String in _saved:
        SaSettings.set(key, _saved[key])
    SaShortcutStore.apply_profile(SaSettings.shortcuts_profile)
    EventBus.shortcuts_changed.emit()
    for action: StringName in _saved_events:
        InputMap.action_erase_events(action)
        for event: InputEvent in _saved_events[action]:
            InputMap.action_add_event(action, event)
    for action: StringName in InputMap.get_actions():
        if not _saved_actions.has(action):
            InputMap.erase_action(action)
    DirAccess.remove_absolute(scratch_layout_path)


func _pressed() -> Array[String]:
    var out: Array[String] = []
    for program: String in _row.buttons:
        if _row.buttons[program].button_pressed:
            out.append(program)
    return out


## The five values Krita sets, read off the settings and the store.
func _five() -> Dictionary:
    return {
        "shortcuts": SaSettings.shortcuts_profile,
        "palette": SaSettings.theme_name,
        "layout": _store.current_preset(),
        "picker": SaSettings.color_picker_shape,
        "zoom": SaSettings.reset_zoom,
    }


func _wanted(answer: String) -> Dictionary:
    var values := SaComingFromRow.values_of(answer)
    return {
        "shortcuts": values["shortcuts"],
        "palette": values["palette"],
        "layout": values["layout"],
        "picker": values["picker"],
        "zoom": values["zoom"],
    }


func test_the_row_offers_procreate_after_krita_and_photoshop() -> void:
    assert_eq(_row.buttons.keys().slice(0, 2), ["krita", "photoshop"], "Krita's and Photoshop's first")
    assert_true(_row.buttons.has("procreate"), "and a Procreate button")
    assert_eq(_row.buttons["procreate"].text, "Procreate", "under its name")
    assert_eq(_pressed(), [] as Array[String], "not pressed on a fresh profile")


func test_procreate_s_five_values_are_in_force() -> void:
    _row.press("procreate")
    assert_eq(_five(), _wanted("procreate"), "Procreate's five values are in force")
    assert_eq(
        _five(),
        {"shortcuts": "Procreate", "palette": "procreate", "layout": "procreate", "picker": "hsv_square", "zoom": "whole"},
        "its profile, Procreate Dark, its layout, the HSV square and Ctrl+0 at the whole picture"
    )
    assert_eq(SaTheme.palette_id, "procreate", "the palette painted")
    assert_eq(SaTheme.palette.display_name, "Procreate Dark", "under its own name")
    assert_eq(_pressed(), ["procreate"] as Array[String], "with Procreate pressed")
    assert_eq(SaComingFromRow.in_force(_store), "procreate", "and read as the program in force")


func test_a_second_press_gives_sara_s_own_back() -> void:
    _row.press("procreate")
    _row.press("procreate")
    assert_true(SaComingFromRow.SARA_SHORTCUTS.has(SaSettings.shortcuts_profile), "Sara's own shortcut map")
    assert_eq(SaSettings.theme_name, "default", "Sara Green")
    assert_eq(_pressed(), [] as Array[String], "with no button pressed")


func test_a_sample_of_its_shortcuts_runs_their_commands() -> void:
    _row.press("procreate")
    for chord: String in SAMPLE:
        var action := SAMPLE[chord]
        var wanted := SaShortcutStore.chord_text(SaShortcutStore.parse_chord(chord))
        var held: Array[String] = []
        for event: InputEvent in InputMap.action_get_events(action):
            held.append(SaShortcutStore.chord_text(event))
        assert_true(held.has(wanted), "%s runs %s, which holds %s" % [chord, action, held])
        assert_eq(SaShortcutStore.conflicts(wanted, action), [] as Array[String], "and nothing else answers %s" % chord)


func test_the_letters_procreate_takes_leave_sara_s_own_commands() -> void:
    _row.press("procreate")
    for action: String in ["tool_lasso", "tool_crop"]:
        var held: Array[String] = []
        for event: InputEvent in InputMap.action_get_events(action):
            held.append(SaShortcutStore.chord_text(event))
        assert_false(held.has("L") or held.has("C"), "%s gives its letter to Procreate's panel, holding %s" % [action, held])


func test_the_profile_palette_and_layout_are_listed_with_the_others() -> void:
    assert_true(SaShortcutStore.list_profiles().has("Procreate"), "the Keyboard Shortcuts page lists Procreate")
    assert_true(SaShortcutStore.is_shipped("Procreate"), "as a shipped profile")
    var palettes: Array[String] = []
    for entry: Dictionary in SaTheme.builtin():
        palettes.append(String(entry["id"]))
    assert_true(palettes.has("procreate"), "the Appearance page lists Procreate Dark")
    assert_true(SaDockerLayoutPresets.SHIPPED.has("procreate"), "and the Layouts page the procreate layout")
    var layout := ConfigFile.new()
    assert_eq(layout.load("res://layouts/procreate.cfg"), OK, "which ships")
    var open: Array[String] = []
    for section: String in layout.get_sections():
        if layout.get_value(section, "visible", false):
            open.append(section)
    open.sort()
    assert_eq(
        open,
        ["BrushPresetsDocker", "ColorDocker", "LayersDocker", "ToolBoxDocker"] as Array[String],
        "with the fewest dockers open"
    )
    for docker: String in ["BrushPresetsDocker", "LayersDocker"]:
        var at: Vector2i = layout.get_value(docker, "position")
        assert_true(at.x >= 1600, "%s stands at the right, at %s" % [docker, at])
    assert_eq(layout.get_value("ColorDocker", "position"), Vector2i(1600, 79), "the colours head the column at the top right")
    var brushes_y: int = layout.get_value("BrushPresetsDocker", "position").y
    var layers_y: int = layout.get_value("LayersDocker", "position").y
    assert_true(brushes_y < layers_y, "the brushes stand above the layers, as Procreate's buttons run")
