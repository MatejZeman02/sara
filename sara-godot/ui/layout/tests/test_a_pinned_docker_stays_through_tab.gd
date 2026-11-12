## The dockers the painter pins stay shown when Tab hides the rest.
##
## Tab is a much pressed chord, and a painter goes out of focus mode and back
## for each colour. The pin is a button
## on the docker's own bar, and the pinned ids are kept in the profile.
##
## Every test points `SaSettings` at a scratch file and puts the run's own
## profile back afterwards, by path and by a fresh load, the way
## `test_a_module_keeps_its_own_preferences.gd` does, because the pins are a
## preference and the suites after this one read the autoload.
##
## The windows are detached, as `test_focus_mode.gd`'s are and for its reason:
## a `Window` added to the tree of a headless run hangs it, and nothing here
## needs one in the tree to carry a `visible` flag and a name.
extends "res://tests/test_framework.gd"

## Where each docker stood when Tab was pressed, in the host window's space, and
## a click inside each.
const STOOD_COLOUR := Rect2(Vector2(900.0, 60.0), Vector2(300.0, 320.0))
const STOOD_LAYERS := Rect2(Vector2(900.0, 400.0), Vector2(300.0, 300.0))
const STOOD_TOOLBOX := Rect2(Vector2(0.0, 60.0), Vector2(60.0, 400.0))
const IN_COLOUR := Vector2(1000.0, 200.0)
const IN_LAYERS := Vector2(1000.0, 500.0)
const IN_TOOLBOX := Vector2(30.0, 200.0)

static var scratch_path: String = SaDataRoot.path("test_n4_docker_pins.cfg")

var _saved_path: String


func before_each() -> void:
    SaFocusMode.active = false
    _saved_path = SaSettings.settings_path
    DirAccess.remove_absolute(_scratch())
    var file := FileAccess.open(_scratch(), FileAccess.WRITE)
    file.store_string("[meta]\nversion=%d\n" % SaSettings.SETTINGS_VERSION)
    file.close()
    SaSettings.config = ConfigFile.new()
    SaSettings.settings_path = _scratch()
    SaSettings.load_settings()


func after_each() -> void:
    SaFocusMode.active = false
    SaSettings.settings_path = _saved_path
    SaSettings.config = ConfigFile.new()
    SaSettings.load_settings()
    DirAccess.remove_absolute(_scratch())
    DirAccess.remove_absolute(_scratch() + SaSettings.BACKUP_SUFFIX)


func _scratch() -> String:
    return ProjectSettings.globalize_path(scratch_path)


## A second launch against the file the first one left.
func _relaunch() -> void:
    SaSettings.config = ConfigFile.new()
    SaSettings.load_settings()


## The docker table `MainDockers` hands focus mode, of windows named for their
## docker ids as `MainDockers` names them, each with a bar row holding a title
## and the pin, the way `DockerWindow._build_hide_button` builds it.
func _table(states: Dictionary) -> Array:
    var out: Array = []
    for docker_id: String in states:
        var window := Window.new()
        window.name = docker_id
        window.visible = states[docker_id]
        var row := HBoxContainer.new()
        row.name = "DragBarRow"
        window.add_child(row)
        var title := Label.new()
        title.text = docker_id
        row.add_child(title)
        SaDockerPin.build_button(row, window)
        out.append({"id": docker_id, "node": window})
    return out


func _free_table(table: Array) -> void:
    for config: Dictionary in table:
        (config["node"] as Window).free()


func _node(table: Array, docker_id: String) -> Window:
    for config: Dictionary in table:
        if config["id"] == docker_id:
            return config["node"] as Window
    return null


func _pin_button(table: Array, docker_id: String) -> Button:
    return _node(table, docker_id).find_child(SaDockerPin.BUTTON_NAME, true, false) as Button


func _visible(table: Array) -> Dictionary:
    var out: Dictionary = {}
    for config: Dictionary in table:
        out[config["id"]] = (config["node"] as Window).visible
    return out


func _stood() -> Dictionary:
    return {"ColorDocker": STOOD_COLOUR, "LayersDocker": STOOD_LAYERS, "ToolBoxDocker": STOOD_TOOLBOX}


## What `MainDockers.toggle_all_dockers` does on a Tab: the table, where the
## open dockers stood, and the pins read off the profile at that moment.
func _tab(focus: SaFocusMode, table: Array) -> Array:
    return focus.toggle(table, _stood() if not SaFocusMode.active else {}, SaDockerPin.pinned_ids())


func _click(focus: SaFocusMode, at: Vector2) -> bool:
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    press.position = at
    var taken := focus.swallows(press)
    var release := press.duplicate() as InputEventMouseButton
    release.pressed = false
    focus.swallows(release)
    return taken


## The case that matters: the Colour Picker pinned from its bar, Tab, and it stays shown
## with every other open docker hidden and outlined. Tab again and the
## arrangement is the one the painter had.
func test_tab_leaves_the_pinned_colour_picker_and_hides_and_outlines_the_rest() -> void:
    var focus := SaFocusMode.new()
    var table := _table({"ToolBoxDocker": true, "ColorDocker": true, "LayersDocker": true, "InfoDocker": false})
    var before := _visible(table)

    _pin_button(table, "ColorDocker").pressed.emit()
    assert_eq(SaDockerPin.pinned_ids(), ["ColorDocker"], "A press on the Colour Picker's pin pins it")

    var changed := _tab(focus, table)
    assert_true(SaFocusMode.active, "Tab enters focus mode")
    var after := _visible(table)
    assert_true(after["ColorDocker"], "The pinned Colour Picker stays shown")
    assert_false(after["ToolBoxDocker"], "the toolbox is hidden")
    assert_false(after["LayersDocker"], "and so are the layers")
    assert_false(after["InfoDocker"], "and the docker that was closed stays closed")
    assert_eq(changed.size(), 2, "Tab reports the two it hid and not the pinned one")
    assert_false(changed.has("ColorDocker"), "so the Window menu's tick for the Colour Picker is left alone")

    assert_eq(focus._outlines.size(), 2, "Each hidden docker is outlined, and the pinned one is not")
    assert_true(_click(focus, IN_LAYERS), "A press where the layers stood is swallowed")
    assert_true(_click(focus, IN_TOOLBOX), "and so is one where the toolbox stood")
    assert_false(_click(focus, IN_COLOUR), "while the Colour Picker still stands where it was and takes its own press")

    var back := _tab(focus, table)
    assert_false(SaFocusMode.active, "Tab again leaves focus mode")
    assert_eq(back.size(), 2, "and shows the two it hid")
    assert_eq(_visible(table), before, "The arrangement is the one the painter had before the first Tab")

    focus.free()
    _free_table(table)


## The pin is in the profile, so it outlives the run that set it.
func test_the_pin_holds_across_a_reload_of_the_settings() -> void:
    var table := _table({"ColorDocker": true})
    SaDockerPin.set_pinned(_node(table, "ColorDocker"), true)
    _relaunch()

    assert_eq(SaDockerPin.pinned_ids(), ["ColorDocker"], "The pin comes back after the settings are read from disk again")
    assert_true(SaDockerPin.is_pinned(_node(table, "ColorDocker")), "and the docker reads as pinned")
    var written := ConfigFile.new()
    assert_eq(written.load(_scratch()), OK, "The profile was saved")
    assert_eq(
        written.get_value(SaSettingsFile.module_section(SaDockerPin.MODULE_ID), String(SaDockerPin.PINS_KEY), []),
        ["ColorDocker"],
        "under the skeleton's own section",
    )
    _free_table(table)


## Nothing is pinned in a fresh profile, so Tab hides every open docker as it
## did before the pin existed.
func test_a_fresh_profile_pins_nothing_and_tab_hides_every_docker() -> void:
    assert_true(SaDockerPin.pinned_ids().is_empty(), "A fresh profile has no pins")
    var focus := SaFocusMode.new()
    var table := _table({"ToolBoxDocker": true, "ColorDocker": true})
    _tab(focus, table)
    for shown: bool in _visible(table).values():
        assert_false(shown, "Every open docker is hidden")
    assert_eq(focus._outlines.size(), 2, "and every one is outlined")
    focus.free()
    _free_table(table)


## A pin changed while focus mode is on counts from the next Tab: unpinning the
## docker that stayed leaves it where it is, the way back changes nothing for
## it, and the Tab after that hides it with the rest.
func test_a_pin_changed_in_focus_mode_counts_from_the_next_tab() -> void:
    var focus := SaFocusMode.new()
    var table := _table({"ToolBoxDocker": true, "ColorDocker": true})
    SaDockerPin.set_pinned(_node(table, "ColorDocker"), true)
    _tab(focus, table)

    _pin_button(table, "ColorDocker").pressed.emit()
    assert_false(SaDockerPin.is_pinned(_node(table, "ColorDocker")), "The press unpins it")
    assert_true(_node(table, "ColorDocker").visible, "and the docker stays shown, since the mode is already on")

    var back := _tab(focus, table)
    assert_eq(back, ["ToolBoxDocker"], "The way back shows what the first Tab hid and nothing else")
    assert_true(_node(table, "ColorDocker").visible, "so the Colour Picker is untouched")

    _tab(focus, table)
    assert_false(_node(table, "ColorDocker").visible, "The next Tab hides it with the rest")

    focus.free()
    _free_table(table)


## Every open docker pinned leaves Tab nothing to hide, and a mode with nothing
## to come back to is not entered.
func test_every_open_docker_pinned_does_not_enter_the_mode() -> void:
    var focus := SaFocusMode.new()
    var table := _table({"ColorDocker": true, "LayersDocker": false})
    SaDockerPin.set_pinned(_node(table, "ColorDocker"), true)
    assert_true(_tab(focus, table).is_empty(), "Nothing changed")
    assert_false(SaFocusMode.active, "and the mode was not entered")
    focus.free()
    _free_table(table)


## The button says what it does in focus mode, and draws the pin's state, set
## by a press or by the profile.
func test_the_button_says_what_the_pin_does_in_focus_mode() -> void:
    var table := _table({"ColorDocker": true})
    var button := _pin_button(table, "ColorDocker")
    assert_not_null(button, "Every docker's bar carries the pin")
    assert_false(button.button_pressed, "It starts out")
    assert_eq(button.tooltip_text, SaDockerPin.PIN_TOOLTIP, "and says a pin keeps the docker shown in focus mode")

    button.pressed.emit()
    assert_true(button.button_pressed, "A press draws it in")
    assert_eq(button.tooltip_text, SaDockerPin.UNPIN_TOOLTIP, "and it says focus mode keeps the docker and how to undo it")
    assert_true(SaDockerPin.PIN_TOOLTIP.contains("focus mode"), "Both tooltips name focus mode")
    assert_true(SaDockerPin.UNPIN_TOOLTIP.contains("focus mode"), "which is where a pin does anything")
    _free_table(table)


## A reset of the preferences forgets the pins with the rest of the skeleton's
## section, and the button drawn from the profile reads out again.
func test_a_reset_of_the_preferences_forgets_the_pins() -> void:
    var table := _table({"ColorDocker": true})
    SaDockerPin.set_pinned(_node(table, "ColorDocker"), true)
    SaSettings.reset_to_defaults()
    assert_true(SaDockerPin.pinned_ids().is_empty(), "The reset forgets the pin")
    SaDockerPin.redraw(_node(table, "ColorDocker"))
    assert_false(_pin_button(table, "ColorDocker").button_pressed, "and the redrawn button reads out")
    _free_table(table)


## Unpinning the last docker forgets the key, so a profile that pinned and
## unpinned is the profile that never pinned.
func test_unpinning_the_last_docker_forgets_the_key() -> void:
    var table := _table({"ColorDocker": true})
    SaDockerPin.set_pinned(_node(table, "ColorDocker"), true)
    SaDockerPin.set_pinned(_node(table, "ColorDocker"), false)
    var section := SaSettingsFile.module_section(SaDockerPin.MODULE_ID)
    assert_false(SaSettings.config.has_section_key(section, String(SaDockerPin.PINS_KEY)), "No key is left behind")
    _free_table(table)
