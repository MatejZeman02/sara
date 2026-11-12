## The Quick settings pane holds both interface sliders, the scale of
## everything and the scale of text.
##
## A painter whose text is too small or too large at a scale that suits the
## controls finds the Font size slider right under UI scale, built with the
## Workspace page's range and readout.
extends "res://tests/test_framework.gd"

const PANE_SOURCE: String = "res://ui/welcome/quick_settings/quick_settings_pane.gd"

var _pane: WelcomeQuickSettingsPane = null
var _saved_scale: float = 1.0
var _saved_font_scale: float = 0.75
var _saved_user_font_scale: float = 0.75


func before_each() -> void:
    _saved_scale = SaSettings.ui_scale
    _saved_font_scale = SaSettings.ui_font_scale
    _saved_user_font_scale = SaUI.user_font_scale
    SaSettings.ui_scale = 1.0
    SaSettings.ui_font_scale = SaSettingsValues.DEFAULT_FONT_SCALE
    SaUI.user_font_scale = SaSettingsValues.DEFAULT_FONT_SCALE
    _pane = WelcomeQuickSettingsPane.new()


func after_each() -> void:
    SaSettings.ui_scale = _saved_scale
    SaSettings.ui_font_scale = _saved_font_scale
    SaUI.user_font_scale = _saved_user_font_scale
    if _pane != null:
        _pane.free()
        _pane = null


## The pane builds a text size slider beside the scale slider with the Workspace
## page's range, step and readout.
func test_the_pane_declares_font_size_slider_with_workspace_range() -> void:
    assert_not_null(_pane.scale_slider, "the pane holds the scale slider")
    assert_not_null(_pane.font_slider, "the pane holds the font size slider")
    assert_eq(_pane.font_slider.name, "FontSizeSlider", "the name matches the Workspace page")
    var expected_min := ceilf(SaSettingsValues.MIN_TEXT_SIZE * 100.0) / 100.0
    var expected_max := floorf(SaSettingsValues.MAX_TEXT_SIZE * 100.0) / 100.0
    assert_almost_eq(_pane.font_slider.min_value, expected_min, 0.0001, "minimum matches the Workspace page")
    assert_almost_eq(_pane.font_slider.max_value, expected_max, 0.0001, "maximum matches the Workspace page")
    assert_almost_eq(_pane.font_slider.step, 0.01, 0.0001, "step is 1%")
    assert_not_null(_pane.font_readout, "the font size readout stands beside the slider")
    assert_eq(_pane.font_readout.text, SaWorkspacePage.percent(_pane.font_slider.value), "the readout shows percent")


## Moving the font size slider updates SaSettings.ui_font_scale and
## SaUI.user_font_scale, and leaves Window.content_scale_factor untouched.
func test_moving_font_size_slider_updates_settings_and_user_font_scale() -> void:
    var initial_scale := 1.0
    var win := _pane.get_window()
    if win != null:
        initial_scale = win.content_scale_factor
    _pane.font_slider.set_value_no_signal(1.2)
    _pane.font_slider.value_changed.emit(1.2)
    var expected_font_scale := 1.2 * SaSettingsValues.DEFAULT_FONT_SCALE
    assert_almost_eq(SaSettings.ui_text_size, 1.2, 0.0001, "the reading updates to 1.2")
    assert_almost_eq(SaSettings.ui_font_scale, expected_font_scale, 0.0001, "the stored multiplier updates")
    assert_almost_eq(SaUI.user_font_scale, expected_font_scale, 0.0001, "SaUI.user_font_scale receives the write")
    assert_eq(_pane.font_readout.text, "120%", "the readout follows the slider value")
    if win != null:
        assert_almost_eq(win.content_scale_factor, initial_scale, 0.0001, "Window scale remains untouched")


## A drag holds the setting back until the hand lets go of the grabber.
func test_a_drag_writes_the_text_size_once_when_it_ends() -> void:
    var initial_font_scale := SaSettings.ui_font_scale
    _pane.font_slider.drag_started.emit()
    _pane.font_slider.set_value_no_signal(1.3)
    _pane.font_slider.value_changed.emit(1.3)
    assert_almost_eq(SaSettings.ui_font_scale, initial_font_scale, 0.0001, "dragging leaves the setting alone")
    assert_eq(_pane.font_readout.text, "130%", "the readout moves with the grabber")
    _pane.font_slider.drag_ended.emit(true)
    var expected_font_scale := 1.3 * SaSettingsValues.DEFAULT_FONT_SCALE
    assert_almost_eq(SaSettings.ui_font_scale, expected_font_scale, 0.0001, "letting go writes the setting")
    assert_almost_eq(SaUI.user_font_scale, expected_font_scale, 0.0001, "and SaUI.user_font_scale follows")


## Setting SaSettings.ui_font_scale from outside updates the pane's slider and
## readout.
func test_setting_font_scale_from_outside_updates_the_slider_and_readout() -> void:
    var wanted_font_scale := 0.9
    SaSettings.ui_font_scale = wanted_font_scale
    var expected_text_size := wanted_font_scale / SaSettingsValues.DEFAULT_FONT_SCALE
    assert_almost_eq(_pane.font_slider.value, expected_text_size, 0.0001, "the slider follows the outside write")
    assert_eq(_pane.font_readout.text, "120%", "the readout reflects the outside write")

    SaSettings.ui_font_scale = SaSettingsValues.DEFAULT_FONT_SCALE
    assert_almost_eq(_pane.font_slider.value, 1.0, 0.0001, "the slider returns to 1.0")
    assert_eq(_pane.font_readout.text, "100%", "the readout returns to 100%")


## The pane writes SaSettings and never Window.content_scale_factor.
func test_the_pane_never_writes_the_content_scale_factor() -> void:
    var code: Array[String] = []
    for line in _read_pane_source().split("\n"):
        if not line.strip_edges().begins_with("#"):
            code.append(line)
    var assignment := RegEx.create_from_string("content_scale_factor\\s*=[^=]")
    assert_null(assignment.search("\n".join(code)), "the pane never writes Window.content_scale_factor")


## The pane answers slider_named and drive_sliders for font_size as well as
## ui_scale.
func test_slider_named_and_drive_sliders() -> void:
    assert_eq(_pane.slider_named("font_size"), _pane.font_slider, "font_size finds the font slider")
    assert_eq(_pane.slider_named("ui_font_scale"), _pane.font_slider, "ui_font_scale finds the font slider")
    assert_eq(_pane.slider_named("ui_scale"), _pane.scale_slider, "ui_scale finds the scale slider")
    var reply := _pane.drive_sliders({"slider": "font_size", "value": 1.15})
    assert_true(reply.contains("font_size"), "the reply confirms the font_size slider was driven")
    assert_almost_eq(_pane.font_slider.value, 1.15, 0.0001, "the slider takes the driven value")


func _read_pane_source() -> String:
    var file := FileAccess.open(ProjectSettings.globalize_path(PANE_SOURCE), FileAccess.READ)
    if file == null:
        return ""
    return file.get_as_text()
