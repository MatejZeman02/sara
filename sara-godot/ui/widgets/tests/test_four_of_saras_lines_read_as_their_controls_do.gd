## Four of Sara's lines read as the controls beside them do.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Four lines that a painter reads
## as slips. Gaussian Blur's slider read "Radius: 10.00  px" with two spaces
## before the unit, because the module hands " px" with a space of its own and
## the label puts one in as well. Colour Range's "Pick from canvas" is a switch
## and its sentence still opened "While ticked". The filter browser's empty pane
## titled itself "Pick a filter" over a sentence that opens with the same words
## (the pane's own suite holds that title). The UI scale's hint wrote "100%"
## beside a readout that said "100 %". Both write "100%",
## the conventions' way, and they still agree.
##
## The slider is built the way `test_a_signed_slider_reaches_both_ends.gd`
## builds one. The running app is
## `scenarios/four-of-saras-lines-read-as-their-controls-do.json`.
extends "res://tests/test_framework.gd"

var _kept_ui_scale: float = 1.0
var _host: Node = null


func before_each() -> void:
    _kept_ui_scale = SaSettings.ui_scale
    _host = Node.new()
    _host.name = "D105Host"
    EventBus.add_child(_host)


func after_each() -> void:
    if _host != null:
        _host.free()
        _host = null
    SaSettings.ui_scale = _kept_ui_scale


## A slider of radius 10 with *suffix*, the way a filter dialog builds its rows.
func _radius(suffix: String) -> FactorSlider:
    var slider := FactorSlider.new()
    slider.min_value = 1.0
    slider.max_value = 50.0
    slider.step = 1.0
    slider.prefix = "Radius: "
    slider.value_format = "%.2f"
    slider.suffix = suffix
    slider.value = 10.0
    slider._ready()
    return slider


func test_a_unit_with_a_space_of_its_own_reads_with_one_space() -> void:
    var slider := _radius(" px")
    assert_eq(slider._label.text, "Radius: 10.00 px", "Gaussian Blur hands ' px' and it reads one space, not two")
    slider.free()


func test_a_unit_without_a_space_reads_with_one_space() -> void:
    var slider := _radius("px")
    assert_eq(slider._label.text, "Radius: 10.00 px", "a module that hands 'px' gets the same line")
    slider.free()


func test_a_unit_with_several_spaces_reads_with_one_space() -> void:
    var slider := _radius("   px")
    assert_eq(slider._label.text, "Radius: 10.00 px", "however many spaces came with it")
    slider.free()


func test_a_slider_with_no_unit_reads_as_the_number() -> void:
    for suffix: String in ["", " "]:
        var slider := _radius(suffix)
        assert_eq(slider._label.text, "Radius: 10.00", "a suffix of '%s' leaves no trailing space" % suffix)
        slider.free()


func test_the_width_the_slider_reserves_is_of_the_one_spaced_text() -> void:
    var spaced := _radius(" px")
    var bare := _radius("px")
    assert_eq(spaced.text_width(), bare.text_width(), "the box fits the line both ways of writing the unit draw")
    spaced.free()
    bare.free()


func test_colour_ranges_switch_is_not_said_to_be_ticked() -> void:
    var dialog := SaColorRangeDialog.new()
    _host.add_child(dialog)
    dialog.for_selection = true
    dialog.build_page(Color.RED, 40.0, true, 0)
    var sentence: String = dialog._pick_row.explanation
    assert_false(sentence.contains("ticked"), "a switch is on or off, got '%s'" % sentence)
    assert_true(sentence.begins_with("While on,"), "the sentence says when it holds, as a switch's does")
    assert_true(sentence.contains("picks the colour"), "and still says what the switch does")


func test_the_scale_hint_writes_its_percentages_as_the_readout_does() -> void:
    var page := SaWorkspacePage.new()
    _host.add_child(page)
    var hint := page._scale_hint(1.0)
    var system_pct := int(round(SaUI.scale() / maxf(0.01, SaUI.user_scale) * 100.0))
    assert_true(hint.contains("system's %d%%," % system_pct), "the system's share is written as the readout is, '%s'" % hint)
    assert_true(hint.contains("drawn at %d%%." % system_pct), "so is the drawn size, '%s'" % hint)
    assert_eq(SaWorkspacePage.percent(1.0), "100%", "which writes no space before the sign")
    assert_false(hint.contains("%%"), "and none is written the old way")
    assert_false(hint.contains(" %"), "and no percent sign stands apart from its number")
