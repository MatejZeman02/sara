## Preferences, General's Advanced options box follows the Tool Options
## docker's check while the page is open.
##
## The box read the setting when the page was built and never again. Ticked in
## the docker behind an open page, it went on showing off, and a press on it
## then wrote the value that was already set.
##
## The write is the one `SaSettingsApply` makes the bus say, emitted here
## because the apply node is not in a suite's tree.
extends "res://tests/test_framework.gd"

var _saved: bool = false


func before_each() -> void:
    _saved = SaSettings.advanced_options


func after_each() -> void:
    SaSettings.advanced_options = _saved


func test_the_box_follows_a_write_made_behind_the_page() -> void:
    SaSettings.advanced_options = false
    var listeners := EventBus.advanced_options_changed.get_connections().size()
    var page := SaGeneralPage.new()
    var box := page.find_child("AdvancedOptionsCheck", true, false) as CheckButton
    assert_false(box.button_pressed, "Built off")
    SaSettings.advanced_options = true
    EventBus.advanced_options_changed.emit(true)
    assert_true(box.button_pressed, "and on once the docker turned the setting on")
    page.free()
    var left := EventBus.advanced_options_changed.get_connections().size()
    assert_eq(left, listeners, "and a freed page leaves no listener on the bus")
