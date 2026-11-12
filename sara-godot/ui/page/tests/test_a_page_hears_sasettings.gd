## SaSettings says which preference moved, and a page hears it.
##
## `SaSettings.changed(property)` is what `sa_page_watch.gd` needed and did
## not have: a `Resource`'s bare `changed()` is one case a target can say it
## changed in, and the autoload's signal carrying a `StringName` is the other.
## `_target_changed` takes both because the
## argument it reads off `SaSettingsValues.changed` is defaulted away.
extends "res://tests/test_framework.gd"

var _host: VBoxContainer = null
var _page: SaPage = null
var _advanced_before: bool = false
var _font_scale_before: float = 1.0


func _declare(ui: SaPage) -> void:
    var section := ui.section("SaSettings")
    section.toggle("Advanced", SaSettings, ^"advanced_options")
    section.slider("Font scale", SaUI.MIN_FONT_SCALE, SaUI.MAX_FONT_SCALE, SaSettings, ^"ui_font_scale").step(0.01).decimals(2)


func before_each() -> void:
    _advanced_before = SaSettings.advanced_options
    _font_scale_before = SaSettings.ui_font_scale
    _host = VBoxContainer.new()
    _page = SaPage.new(_declare)
    _page.declare_rows()
    _page.realize(_host)


func after_each() -> void:
    SaSettings.advanced_options = _advanced_before
    SaSettings.ui_font_scale = _font_scale_before
    if _host != null:
        _host.free()
    _host = null
    _page = null


func test_a_write_behind_the_page_reaches_the_check_with_no_extra_argument_error() -> void:
    var check := _page.row(&"advanced").control as CheckButton
    assert_eq(check.button_pressed, _advanced_before, "the check read the setting on realize")
    SaSettings.advanced_options = not _advanced_before
    assert_eq(check.button_pressed, not _advanced_before, "and follows a write made behind its back")


func test_the_slider_follows_too_and_a_hand_write_stays_where_it_landed() -> void:
    var slider := _page.row(&"font_scale").control as HSlider
    SaSettings.ui_font_scale = 1.3
    assert_almost_eq(slider.value, 1.3, 0.001, "a write behind the page reaches the slider")

    _page.row(&"font_scale").drive(0.9)
    assert_almost_eq(SaSettings.ui_font_scale, 0.9, 0.001, "the hand's write reached the setting")
    assert_almost_eq(slider.value, 0.9, 0.001, "and the refresh that write triggered left the slider where the hand put it")
