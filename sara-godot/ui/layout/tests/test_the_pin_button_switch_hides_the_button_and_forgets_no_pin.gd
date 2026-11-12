## One switch under Every docker on the Dockers page hides the
## pin on every docker's bar, and a pin already set still holds while it is
## hidden.
##
## The pin is a button and a list in the profile, and the switch is about the
## button alone. Every test points `SaSettings` at a scratch file and puts the
## run's own profile back afterwards, as `test_a_pinned_docker_stays_through_tab.gd`
## does, and the windows are detached for its reason.
extends "res://tests/test_framework.gd"

static var scratch_path: String = SaDataRoot.path("test_b21_docker_pin_switch.cfg")

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


## A window named for its docker id with a bar row holding the pin, as
## `DockerWindow` builds it, and the button shown as the switch says.
func _docker(docker_id: String) -> Window:
    var window := Window.new()
    window.name = docker_id
    var row := HBoxContainer.new()
    row.name = "DragBarRow"
    window.add_child(row)
    SaDockerPin.apply_button(SaDockerPin.build_button(row, window))
    return window


func _button(window: Window) -> Button:
    return window.find_child(SaDockerPin.BUTTON_NAME, true, false) as Button


## The switch is on for a fresh profile, as the button always was.
func test_the_switch_is_on_in_a_fresh_profile() -> void:
    var pin := SaDockerPin.new()
    assert_true(pin.button_on, "A fresh profile wants the pin button")
    var window := _docker("LayersDocker")
    assert_true(_button(window).visible, "and the Layers docker's bar shows it")
    window.free()


## The case that matters: a docker pinned, the switch off, and the docker is still on
## the list and still shown in focus mode, with its button gone.
func test_a_pin_holds_while_the_button_is_hidden() -> void:
    var layers := _docker("LayersDocker")
    var brushes := _docker("BrushesDocker")
    var colour := _docker("ColorDocker")
    for window: Window in [layers, brushes, colour]:
        window.visible = true
    _button(layers).pressed.emit()

    var pin := SaDockerPin.new()
    pin.button_on = false
    assert_false(SaDockerPin.button_wanted(), "The switch reads off")
    assert_true(SaDockerPin.names_the_switch(&"sara-skeleton/docker_pin_button"), "and `changed` names it by its key")
    for window: Window in [layers, brushes, colour]:
        SaDockerPin.apply_button(_button(window))
        assert_false(_button(window).visible, "%s's pin is hidden" % window.name)

    assert_eq(SaDockerPin.pinned_ids(), ["LayersDocker"], "The pin set before is still on the list")
    assert_true(SaDockerPin.is_pinned(layers), "and the docker reads as pinned")

    var focus := SaFocusMode.new()
    var table: Array = []
    for window: Window in [layers, brushes, colour]:
        table.append({"id": String(window.name), "node": window})
    focus.toggle(table, {}, SaDockerPin.pinned_ids())
    assert_true(layers.visible, "The pinned Layers docker is still shown in focus mode")
    assert_false(brushes.visible, "and an unpinned one is hidden")
    focus.toggle(table, {}, SaDockerPin.pinned_ids())

    pin.button_on = true
    for window: Window in [layers, brushes, colour]:
        SaDockerPin.apply_button(_button(window))
        assert_true(_button(window).visible, "%s's pin is back" % window.name)
    assert_true(_button(layers).button_pressed, "and the pinned docker's reads pressed")
    assert_eq(SaDockerPin.pinned_ids(), ["LayersDocker"], "Turning the switch off and on forgot no pin")

    focus.free()
    for window: Window in [layers, brushes, colour]:
        window.free()


## The switch is kept in the profile, under the skeleton's own section.
func test_the_switch_outlives_the_run() -> void:
    SaDockerPin.new().button_on = false
    SaSettings.config = ConfigFile.new()
    SaSettings.load_settings()
    assert_false(SaDockerPin.button_wanted(), "The switch reads off after the settings are read again")
    var written := ConfigFile.new()
    assert_eq(written.load(_scratch()), OK, "The profile was saved")
    assert_eq(
        written.get_value(SaSettingsFile.module_section(SaDockerPin.MODULE_ID), String(SaDockerPin.SWITCH_KEY), true),
        false,
        "under the skeleton's own section",
    )
