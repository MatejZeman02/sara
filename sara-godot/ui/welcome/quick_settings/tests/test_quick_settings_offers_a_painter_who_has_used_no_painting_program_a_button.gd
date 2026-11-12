## Quick settings offers a painter who has used no painting program a button
## that sets Sara's own shortcuts and says so.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The row is built over a layout store of the suite's own on a scratch file,
## as the suite for the program buttons builds one, so a press loads its layout into that store
## and never into the running window. Every value a press writes is put back
## after each test.
extends "res://tests/test_framework.gd"

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
    _root.name = "U489Host"
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


## A fresh profile shows no button pressed, and the row's hover tells a
## painter who has used no painting program to leave it as it is, in place of a
## beginner's button.
func test_a_fresh_profile_presses_no_button_and_the_hover_answers_the_newcomer() -> void:
    assert_false(_row.buttons.has("none"), "no button for no program")
    assert_true(_row.tooltip_text.contains("used no painting program"), "the hover speaks to a newcomer")
    assert_true(_row.tooltip_text.contains("leave this row as it is"), "and says to leave the row")
    assert_eq(_pressed(), [] as Array[String], "no button pressed on Sara's own values")


## Photoshop and then Photoshop again gives back every default, with no button
## pressed.
func test_photoshop_then_photoshop_again_gives_back_sara_s_own() -> void:
    var layout_fresh := _store.current_preset()
    _row.press("photoshop")
    assert_eq(_pressed(), ["photoshop"] as Array[String], "Photoshop pressed")
    _row.press("photoshop")
    assert_true(SaComingFromRow.SARA_SHORTCUTS.has(SaSettings.shortcuts_profile), "Sara's own shortcut profile")
    assert_eq(SaSettings.theme_name, "default", "the default theme")
    assert_eq(SaTheme.palette_id, "default", "drawn in the default palette")
    assert_eq(_store.current_preset(), "default", "the default layout")
    assert_true(layout_fresh != "photoshop", "the store did not start on Photoshop's layout")
    assert_eq(SaSettings.color_picker_shape, "wheel", "the default picker")
    assert_eq(_pressed(), [] as Array[String], "no button pressed")


## A Preferences page that changes one of Krita's values shows no button
## pressed, and putting it back shows Krita's again.
func test_a_changed_setting_presses_none() -> void:
    _row.press("krita")
    SaSettings.color_picker_shape = "okhsl"
    assert_eq(_pressed(), [] as Array[String], "a picker none uses presses no button")
    SaSettings.color_picker_shape = "hsv_triangle"
    assert_eq(_pressed(), ["krita"] as Array[String], "putting it back presses Krita's again")
    # Sara's values put back without a press, as four Preferences pages would.
    SaComingFromRow.apply(SaComingFromRow.OWN, _store)
    _row.refresh()
    assert_eq(_pressed(), [] as Array[String], "Sara's own values press no button")
