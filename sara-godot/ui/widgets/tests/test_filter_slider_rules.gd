## A filter's slider can be dragged after a rule pass, and carries its caption
## inside the box.
##
## The Box blur slider could not be adjusted, and the word Radius should live
## inside it. The cause was
## `SaPage.set_live` writing STOP on every descendant of a live row, which
## turned the click-through `Label` a `FactorSlider` lays over its box into the
## control that ate every press. The scenario of the same name is the other
## half, a real drag through the dialog's own window.
extends "res://tests/test_framework.gd"

var _on: bool = true
var _host: VBoxContainer = null
var _page: SaPage = null


func _declare(ui: SaPage) -> void:
    var section := ui.section("Filter")
    section.toggle("Enabled", self, ^"_on").dims(&"radius")
    section.rows.append(SaSlider.make("Radius", 1, 20, 3, {"hard_max": 200}))


func _build() -> void:
    _on = true
    _host = VBoxContainer.new()
    _page = SaPage.new(_declare)
    _page.declare_rows()
    _page.realize(_host)


func _tear_down() -> void:
    _host.free()
    _host = null
    _page = null


func _slider() -> FactorSlider:
    return _page.row(&"radius").control as FactorSlider


func _label(slider: FactorSlider) -> Label:
    return slider.find_child("Label", false, false) as Label


func test_the_label_over_the_box_stays_click_through_after_a_rule_pass() -> void:
    _build()
    var slider := _slider()
    assert_true(slider != null, "the row draws a FactorSlider")
    _page.apply_rules()
    assert_eq(_label(slider).mouse_filter, Control.MOUSE_FILTER_IGNORE, "the Label lets a press through to the slider")
    assert_eq(slider.mouse_filter, Control.MOUSE_FILTER_STOP, "and the slider itself takes it")
    assert_eq(_label(slider).focus_mode, Control.FOCUS_NONE, "a label asks for no focus and keeps asking")
    _tear_down()


func test_a_dimmed_slider_refuses_the_hand_and_a_live_one_takes_it_back() -> void:
    _build()
    var slider := _slider()
    _page.row(&"enabled").drive(false)
    assert_false(SaOptionSpec.row_reads_enabled(_page.row(&"radius").line), "off dims Radius")
    assert_eq(slider.mouse_filter, Control.MOUSE_FILTER_IGNORE, "and the box refuses the press")
    _page.row(&"enabled").drive(true)
    assert_eq(slider.mouse_filter, Control.MOUSE_FILTER_STOP, "on gives the box the press back")
    assert_eq(_label(slider).mouse_filter, Control.MOUSE_FILTER_IGNORE, "and the Label its own filter, not STOP")
    _tear_down()


func test_the_caption_lives_inside_the_box_and_the_label_column_is_empty() -> void:
    _build()
    var slider := _slider()
    assert_eq(slider.prefix, "Radius: ", "the caption is the box's prefix")
    assert_eq(_label(slider).text, "Radius: 3", "and reads with the value")
    assert_eq(String(slider.name), "Radius", "the slider is found by its caption")
    var line := _page.row(&"radius").line
    assert_eq(String(line.get_meta(SaSettingsRows.TITLE_META)), "", "the row's own label column carries nothing")
    var title := line.get_child(0).get_child(0) as Label
    assert_eq(title.text, "", "and the label it draws there is empty")
    _tear_down()
