## The slider over a ramp keeps what it inherits from `FactorSlider`: a range
## that crosses zero reaches both ends, and Backspace puts it back where it
## was built.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The two cases sit beside `SaGradientSlider`, which lives with the filters
## that build it, because a suite follows the class it builds.
extends "res://tests/test_framework.gd"

const WIDTH := 200.0


func _backspace() -> InputEventKey:
    var key := InputEventKey.new()
    key.keycode = KEY_BACKSPACE
    key.pressed = true
    return key


## Hue, minus one hundred and eighty to one hundred and eighty, on the class
## the adjustments build. The mapping is driven through `_update_from_mouse_x`,
## the handler `_gui_input` calls, because an injected motion never reaches
## `_gui_input`.
func test_hue_on_a_gradient_slider_reaches_both_ends() -> void:
    var slider := SaGradientSlider.new()
    slider.min_value = -180.0
    slider.max_value = 180.0
    slider.step = 1.0
    slider.value = 0.0
    slider._ready()
    slider.size = Vector2(WIDTH, 18.0)
    slider._update_from_mouse_x(WIDTH)
    assert_almost_eq(slider.value, 180.0, 0.5, "Hue's right end is a hundred and eighty")
    slider._update_from_mouse_x(WIDTH * 0.5)
    assert_almost_eq(slider.value, 0.0, 0.5, "and its middle is nought")
    slider._update_from_mouse_x(0.0)
    assert_almost_eq(slider.value, -180.0, 0.5, "and its left end is minus a hundred and eighty")
    slider.free()


## SaGradientSlider overrides only `_draw`, so the reset it inherits answers
## the claim for the gradient sliders without a line of its own.
func test_a_gradient_slider_inherits_the_same_reset() -> void:
    var slider := SaGradientSlider.new()
    slider.value = 0.3
    slider._ready()
    slider.value = 0.9
    slider._on_mouse_entered()

    slider._unhandled_key_input(_backspace())

    assert_eq(slider.value, 0.3, "the gradient slider answers Backspace the same as its parent")
    slider.free()
