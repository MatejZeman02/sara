## A slider whose range crosses zero reaches both ends.
##
## On Brightness/Contrast a click only went below zero (jumping to -40) and
## could not reach the positive range. The mapping from the
## pointer to a value was right, `min + fraction * (top - min)`. What was wrong
## was `top`: `soft_max_value` defaults to zero, which its own comment says means
## no soft ceiling, and `drag_max` asked only whether it sat above the minimum.
## On a slider from nought up it never does. On minus a hundred to a hundred it
## does, so every drag stopped at nought and the middle of the bar was minus
## fifty.
##
## The mapping is driven through `_update_from_mouse_x`, the handler `_gui_input`
## calls, because an injected motion never reaches `_gui_input`. The scenario drives the same slider
## through its window's own dispatch.
extends "res://tests/test_framework.gd"

const WIDTH := 200.0


## A slider over *low* to *high*, built the way the Adjust dialog builds its rows:
## no soft ceiling set, so the field keeps its default of zero.
func _slider(low: float, high: float) -> FactorSlider:
    var slider := FactorSlider.new()
    slider.min_value = low
    slider.max_value = high
    slider.step = 1.0
    slider.value = 0.0
    slider._ready()
    slider.size = Vector2(WIDTH, 18.0)
    return slider


## The regression. A click at the middle of Brightness
## is nought, and not the minus fifty a ceiling at nought made of it.
func test_the_middle_of_a_symmetric_range_is_zero() -> void:
    var slider := _slider(-100.0, 100.0)
    slider.value = -70.0
    slider._update_from_mouse_x(WIDTH * 0.5)
    assert_almost_eq(slider.value, 0.0, 0.5, "The middle of minus a hundred to a hundred is nought")
    slider.free()


## "Cannot go to the positive range." The right end is the maximum, and three
## quarters is half of it, which is the click the scenario shoots.
func test_the_right_end_and_three_quarters_are_positive() -> void:
    var slider := _slider(-100.0, 100.0)
    slider._update_from_mouse_x(WIDTH)
    assert_almost_eq(slider.value, 100.0, 0.5, "The right end is the maximum")
    slider._update_from_mouse_x(WIDTH * 0.75)
    assert_almost_eq(slider.value, 50.0, 0.5, "and three quarters is fifty")
    slider.free()


## The left end is still the minimum, so the fix moved the top and nothing else.
func test_the_left_end_is_the_minimum() -> void:
    var slider := _slider(-100.0, 100.0)
    slider.value = 30.0
    slider._update_from_mouse_x(0.0)
    assert_almost_eq(slider.value, -100.0, 0.5, "The left end is the minimum")
    slider.free()


## The drag ceiling itself, which is the line that was wrong.
func test_an_unset_soft_ceiling_is_no_ceiling_on_a_signed_range() -> void:
    var slider := _slider(-100.0, 100.0)
    assert_almost_eq(slider.drag_max(), 100.0, 0.0001, "An unset soft ceiling leaves the hard one")
    slider.free()


## A soft ceiling that was set still works, on a signed range as on a positive
## one, so a real ceiling is not mistaken for the unset zero.
func test_a_set_soft_ceiling_still_stops_a_signed_drag() -> void:
    var slider := _slider(-100.0, 100.0)
    slider.soft_max_value = 40.0
    slider._update_from_mouse_x(WIDTH)
    assert_almost_eq(slider.drag_max(), 40.0, 0.0001, "A soft ceiling of forty is a ceiling")
    assert_almost_eq(slider.value, 40.0, 0.5, "and the drag stops there")
    slider.free()


## A soft ceiling below zero is allowed too, which is the case the zero test must
## not throw away: it is set, and it is not zero.
func test_a_negative_soft_ceiling_is_still_a_ceiling() -> void:
    var slider := _slider(-100.0, 100.0)
    slider.soft_max_value = -20.0
    assert_almost_eq(slider.drag_max(), -20.0, 0.0001, "A soft ceiling of minus twenty is a ceiling")
    slider.free()


## Every slider that starts at nought behaves as it did: the soft ceiling and
## its unset zero, the two cases `test_factor_slider.gd` already pins.
func test_a_range_from_zero_is_unchanged() -> void:
    var slider := _slider(0.0, 1.0)
    slider.step = 0.001
    assert_almost_eq(slider.drag_max(), 1.0, 0.0001, "No soft ceiling from nought up is the hard one")
    slider.soft_max_value = 0.5
    assert_almost_eq(slider.drag_max(), 0.5, 0.0001, "and a soft one at a half is still a half")
    slider.free()
