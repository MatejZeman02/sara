## The welcome window's UI scale slider writes the setting when the hand lets
## go, the rule Preferences' Workspace page already keeps.
##
## It wrote `SaSettings.ui_scale` on every tick of a drag, so the whole
## interface rescaled under the held grabber and the drag chased its own
## handle, the fault `workspace_page.gd`'s `_wire_slider` was written for.
##
## Driven the way `test_quick_settings_pane.gd` drives the pane, out of the
## tree: the value set silently and then the signals a real drag delivers.
extends "res://tests/test_framework.gd"

var _pane: WelcomeQuickSettingsPane = null
var _saved_scale: float = 1.0


func before_each() -> void:
    _saved_scale = SaSettings.ui_scale
    SaSettings.ui_scale = 1.0
    _pane = WelcomeQuickSettingsPane.new()


func after_each() -> void:
    SaSettings.ui_scale = _saved_scale
    if _pane != null:
        _pane.free()
        _pane = null


func test_a_drag_writes_the_scale_once_when_it_ends() -> void:
    var slider := _pane.scale_slider
    slider.drag_started.emit()
    slider.set_value_no_signal(1.5)
    slider.value_changed.emit(1.5)
    assert_almost_eq(SaSettings.ui_scale, 1.0, 0.0001, "A tick under the held grabber leaves the scale alone")
    slider.drag_ended.emit(true)
    assert_almost_eq(SaSettings.ui_scale, 1.5, 0.0001, "and letting go writes it")


func test_a_change_with_no_drag_applies_at_once() -> void:
    var slider := _pane.scale_slider
    slider.set_value_no_signal(1.25)
    slider.value_changed.emit(1.25)
    assert_almost_eq(SaSettings.ui_scale, 1.25, 0.0001, "An arrow key or a click on the track writes the scale")
