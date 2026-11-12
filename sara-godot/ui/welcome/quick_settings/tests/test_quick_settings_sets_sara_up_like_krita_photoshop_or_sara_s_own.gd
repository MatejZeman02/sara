## Quick settings sets Sara up like Krita, Photoshop or Sara's own with one
## press.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The row is pressed through its own door, `SaComingFromRow.press`, over a
## layout store of the suite's own on a scratch file, the way
## `test_docker_layout_presets.gd` builds one, so the layout a press loads is
## read back from a store and not from the running window. Every value a press
## writes is put back after each test, the shortcut map applied again with it,
## so the suites after this one read the profile the run started with.
extends "res://tests/test_framework.gd"

const HOST := Vector2i(1920, 1048)
const MINE_SHORTCUTS := "mine"
const MINE_LAYOUT := "probe mine"
static var scratch_layout_path: String = SaDataRoot.path("test_layout.cfg")
static var scratch_presets_dir: String = SaDataRoot.path("layouts")

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
        SaSettings.set(key, _fresh(key))
    SaShortcutStore.apply_profile(SaSettings.shortcuts_profile)
    _saved_layout_state = ConfigFile.new()
    _root = Node.new()
    _root.name = "U421Host"
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
    SaShortcutStore.delete_profile(MINE_SHORTCUTS)
    DirAccess.remove_absolute(scratch_presets_dir.path_join(MINE_LAYOUT + ".cfg"))
    DirAccess.remove_absolute(scratch_layout_path)


static func _fresh(key: String) -> Variant:
    return (SaSettingsValues as Script).get_property_default_value(key)


## Each value the Done clause names, read from where it is in force.
func _reading() -> Dictionary:
    return {
        "shortcuts": SaSettings.shortcuts_profile,
        "palette": SaSettings.theme_name,
        "theme": SaTheme.palette_id,
        "layout": _store.current_preset(),
        "picker": SaSettings.color_picker_shape,
    }


func _pressed() -> Array[String]:
    var out: Array[String] = []
    for program: String in _row.buttons:
        if _row.buttons[program].button_pressed:
            out.append(program)
    return out


func test_a_fresh_folder_shows_no_button_pressed() -> void:
    # Sara's own values have no button.
    assert_eq(SaComingFromRow.in_force(_store), "", "a fresh folder is Sara's own, no program's")
    assert_eq(_pressed(), [] as Array[String], "and no button is pressed")


func test_photoshop_then_krita_then_krita_again() -> void:
    var fresh := _reading()
    _row.press("photoshop")
    var read := _reading()
    assert_eq(read["shortcuts"], "Photoshop", "the shortcut profile is Photoshop")
    assert_eq(read["palette"], "photoshop", "the palette is photoshop")
    assert_eq(read["theme"], "photoshop", "and SaTheme draws with it")
    assert_eq(read["layout"], "photoshop", "the layout is photoshop")
    assert_eq(read["picker"], "hsv_square", "the picker is the HSV square")
    assert_eq(_pressed(), ["photoshop"] as Array[String], "Photoshop is the button pressed")
    var chords := SaShortcutStore.chords_for(&"tool_zoom")
    assert_true(chords.has("Z"), "the input map is Photoshop's, bare Z zooms (%s)" % [chords])

    _row.press("krita")
    read = _reading()
    assert_eq(read["shortcuts"], "Krita", "the shortcut profile is Krita")
    assert_eq(read["palette"], "krita", "the palette is krita")
    assert_eq(read["layout"], "krita", "the layout is krita")
    assert_eq(read["picker"], "hsv_triangle", "the picker is the HSV triangle")
    assert_eq(_pressed(), ["krita"] as Array[String], "Krita is the button pressed")

    _row.press("krita")
    assert_eq(_reading(), fresh, "every value is a fresh folder's again")
    assert_eq(_pressed(), [] as Array[String], "and no button is pressed")


func test_a_press_keeps_the_painters_own_profile_and_layout() -> void:
    assert_true(SaShortcutStore.save_profile(MINE_SHORTCUTS) >= 0, "a custom shortcut profile is saved")
    assert_true(_store.save_preset(MINE_LAYOUT), "and a custom layout")
    _row.press("photoshop")
    _row.press("photoshop")
    assert_true(SaShortcutStore.list_profiles().has(MINE_SHORTCUTS), "the custom profile is still listed")
    assert_true(_store.list_presets().has(MINE_LAYOUT), "and so is the custom layout")


func test_settings_that_match_none_press_no_button() -> void:
    _row.press("krita")
    SaSettings.color_picker_shape = "okhsl"
    assert_eq(SaComingFromRow.in_force(_store), "", "Krita's with another picker is none of the three")
    assert_eq(_pressed(), [] as Array[String], "and no button is pressed, read as the setting changed")
    SaSettings.color_picker_shape = "hsv_triangle"
    assert_eq(_pressed(), ["krita"] as Array[String], "putting it back by hand presses Krita again")


func test_a_press_leaves_the_ui_scale_alone() -> void:
    var scale := SaSettings.ui_scale
    _row.press("krita")
    _row.press("photoshop")
    assert_eq(SaSettings.ui_scale, scale, "no program touches the scale")


## The row heads the pane, above the seven, and reads the store-less pane's
## settings as Sara's on a fresh folder.
func test_the_row_heads_the_quick_settings_pane() -> void:
    var pane := WelcomeQuickSettingsPane.new()
    var titles: Array[String] = []
    for node in pane.find_children("*", "HBoxContainer", true, false):
        if node.has_meta(SaSettingsRows.ROW_META):
            titles.append(String(node.get_meta(SaSettingsRows.TITLE_META)))
    assert_eq(titles.size(), 9, "the row and the eight")
    assert_eq(titles[0], "I'm coming from", "the row first")
    assert_eq(SaComingFromRow.in_force(null), "", "with no button pressed on Sara's values")
    pane.coming_from.press("photoshop")
    assert_eq(pane.theme_opt.selected_value(), "photoshop", "the theme row shows the new palette at once")
    assert_eq(pane.picker_shape_opt.selected_value(), "hsv_square", "and the picker row the new shape")
    pane.free()


## The same row stands first on Preferences > Interface.
func test_the_row_heads_the_interface_page() -> void:
    var page := SaWorkspacePage.new()
    var rows := page.find_children("ComingFromRow", "SaComingFromRow", true, false)
    assert_eq(rows.size(), 1, "the Interface page holds the row")
    page.free()
