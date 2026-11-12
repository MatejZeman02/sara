## Quick settings' "I'm coming from" offers Krita and Photoshop only, and a
## second press goes back to Sara's own.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The row is built over a layout store of the suite's own on a scratch file,
## as the suite for the first program button builds one, so a press loads its layout into that store
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
    _root.name = "U533Host"
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


func test_the_row_shows_krita_and_photoshop() -> void:
    # Procreate follows the two, as a program, so no
    # button for Sara or for having no program is among them.
    assert_eq(_row.buttons.keys().slice(0, 2), ["krita", "photoshop"], "Krita's and Photoshop's first")
    assert_eq(_row.buttons.keys(), SaComingFromRow.PROGRAMS.keys(), "a button a program")
    assert_false(_row.buttons.has("sara") or _row.buttons.has("none"), "and none for Sara or for no program")
    assert_eq(_row.get_child_count(), _row.buttons.size(), "and nothing else in the row")
    assert_eq(_pressed(), [] as Array[String], "neither pressed on a fresh profile")
    assert_eq(SaComingFromRow.in_force(_store), "", "and no program in force")


func test_krita_then_krita_again() -> void:
    var fresh := _five()
    _row.press("krita")
    assert_eq(_five(), _wanted("krita"), "Krita's five values are in force")
    assert_eq(_five()["zoom"], "pixels", "Ctrl+0 among them at actual pixels")
    assert_eq(_pressed(), ["krita"] as Array[String], "with Krita pressed")
    _row.press("krita")
    var back := _five()
    assert_true(SaComingFromRow.SARA_SHORTCUTS.has(back["shortcuts"]), "Sara's own shortcut map")
    back.erase("shortcuts")
    fresh.erase("shortcuts")
    assert_eq(back, fresh, "and a fresh profile's other four values")
    assert_eq(_pressed(), [] as Array[String], "with no button pressed")


func test_photoshop_then_krita() -> void:
    _row.press("photoshop")
    assert_eq(_pressed(), ["photoshop"] as Array[String], "Photoshop pressed")
    _row.press("krita")
    assert_eq(_five(), _wanted("krita"), "Krita's five values, not a release")
    assert_eq(_pressed(), ["krita"] as Array[String], "with Krita pressed")


## A painter who sets Krita's five values by hand sees Krita pressed.
func test_krita_s_values_by_hand_press_krita() -> void:
    SaComingFromRow.apply("krita", _store)
    _row.refresh()
    assert_eq(_pressed(), ["krita"] as Array[String], "Krita reads pressed")


func test_the_hover_says_how_to_go_back_and_what_a_newcomer_does() -> void:
    for hover: String in [_row.tooltip_text, _row.buttons["krita"].tooltip_text]:
        assert_true(hover.contains("again for Sara's own settings"), "the hover says how to go back")
        assert_true(hover.contains("used no painting program"), "and speaks to a newcomer")


## A profile written before the row lost its Sara buttons loses the key.
func test_a_stored_answer_is_migrated_away() -> void:
    var config := ConfigFile.new()
    config.set_value("ui", "coming_from_pressed", "none")
    config.set_value("ui", "first_launch_done", true)
    SaSettingsMigrations.apply(config, 25)
    assert_false(config.has_section_key("ui", "coming_from_pressed"), "the key is gone")
    assert_true(config.get_value("ui", "first_launch_done"), "and its neighbour stays")
    assert_false(SaSettingsKeys.KEYS.has("coming_from_pressed"), "and no setting reads it")
    assert_false("coming_from_pressed" in SaSettings, "nor a property holds it")
