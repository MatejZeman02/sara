## A rotation typed past -180 or 180 wraps rather than clamps.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A value typed outside -180 to 180 in the rotation field wraps, not clamps,
## so 360 does not land on 180, a half turn where the painter asked for none.
## The field is the bar's own slider, built by `SaTopBarRotation.attach` and handed a fake view, and the
## typing is what a painter does: open the field, type, press Return. The last
## case is the other half, that every other `FactorSlider` still
## clamps.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

var _host: HBoxContainer = null

## Held for the case, because the pair is `RefCounted` and the slider's
## `value_changed` goes nowhere once nothing holds the object it names.
var _pair: SaTopBarRotation = null


func before_each() -> void:
    _host = HBoxContainer.new()
    _host.name = "N7RotationHost"
    EventBus.add_child(_host)


func after_each() -> void:
    if _host != null:
        _host.free()
        _host = null
    _pair = null


func _rotation_slider(view: SaView) -> FactorSlider:
    _pair = SaTopBarRotation.new(view)
    _pair.attach(_host)
    _pair.follow()
    return _pair.slider


func _type(slider: FactorSlider, text: String) -> void:
    slider.start_editing()
    slider._line_edit.text = text
    slider._on_line_edit_submitted(text)


func test_a_whole_turn_typed_reads_nought() -> void:
    var view := Fixtures.FakeView.new()
    var slider := _rotation_slider(view)
    _type(slider, "45")
    _type(slider, "360")
    assert_almost_eq(slider.value, 0.0, 1e-6, "360 wraps to 0 rather than clamping to 180")
    assert_almost_eq(rad_to_deg(view.get_rotation()), 0.0, 0.01, "and the view is turned there too")


func test_minus_two_seventy_reads_ninety() -> void:
    var view := Fixtures.FakeView.new()
    var slider := _rotation_slider(view)
    _type(slider, "-270")
    assert_almost_eq(slider.value, 90.0, 1e-6, "-270 wraps to 90 rather than clamping to -180")
    assert_almost_eq(rad_to_deg(view.get_rotation()), 90.0, 0.01, "and the view is turned there too")


func test_an_angle_inside_the_range_is_kept_as_typed() -> void:
    var slider := _rotation_slider(Fixtures.FakeView.new())
    _type(slider, "180")
    assert_almost_eq(slider.value, 180.0, 1e-6, "180 is an end of the range and stays 180")
    _type(slider, "-30")
    assert_almost_eq(slider.value, -30.0, 1e-6, "an angle in range is untouched")


func test_every_other_slider_still_clamps() -> void:
    var slider := FactorSlider.new()
    _host.add_child(slider)
    slider.min_value = -180.0
    slider.max_value = 180.0
    slider.value = 0.0
    assert_false(slider.wraps, "wrapping is off unless a row asks for it")
    _type(slider, "360")
    assert_almost_eq(slider.value, 180.0, 1e-6, "a row that does not wrap clamps 360 to its top")
    _type(slider, "-270")
    assert_almost_eq(slider.value, -180.0, 1e-6, "and -270 to its bottom")
