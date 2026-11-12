## A right press or Escape during a slider's drag puts the value back.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A right click while dragging the bar's rotation slider cancels it and reverts
## to the original value. The drag ends, the value is the one it had
## at the press, `value_changed` says so once, and the release that follows does
## nothing.
##
## The events go through `_gui_input` the way a held button's do, and the Escape
## through the router's own entry, since a slider holds no focus for a key to
## find it by. The dialog half is `test_escape_in_a_dialog_leaves_the_window.gd`.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

const WIDTH := 200.0

var _host: Node = null


func before_each() -> void:
    _host = Node.new()
    _host.name = "SliderDragCancelHost"
    EventBus.add_child(_host)


func after_each() -> void:
    _host.free()
    _host = null


## A slider from 0 to 100 at 40, in the tree and 200 wide, so a pixel is half a
## unit and a press at x puts it at x / 2.
func _slider() -> FactorSlider:
    var slider := FactorSlider.new()
    _host.add_child(slider)
    slider.min_value = 0.0
    slider.max_value = 100.0
    slider.step = 1.0
    slider.value = 40.0
    slider.size = Vector2(WIDTH, 18.0)
    return slider


static func _button(index: MouseButton, pressed: bool, x: float = 0.0) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = index
    event.pressed = pressed
    event.position = Vector2(x, 9.0)
    return event


## A motion with the left button held, which is what a drag's motion carries.
static func _motion(x: float) -> InputEventMouseMotion:
    var event := InputEventMouseMotion.new()
    event.position = Vector2(x, 9.0)
    event.button_mask = MOUSE_BUTTON_MASK_LEFT
    return event


static func _escape() -> InputEventKey:
    var key := InputEventKey.new()
    key.keycode = KEY_ESCAPE
    key.physical_keycode = KEY_ESCAPE
    key.pressed = true
    return key


## What a slider says through `value_changed`, in order.
func _heard(slider: FactorSlider) -> Array[float]:
    var heard: Array[float] = []
    slider.value_changed.connect(func(new_value: float) -> void: heard.append(new_value))
    return heard


## Presses at 60 (the value jumps to 30) and drags to 150 (to 75), the way a
## painter's hand does before changing their mind.
func _drag_away(slider: FactorSlider) -> void:
    slider._gui_input(_button(MOUSE_BUTTON_LEFT, true, 60.0))
    slider._gui_input(_motion(150.0))


func test_a_right_press_puts_the_value_back_to_what_it_was_at_the_press() -> void:
    var slider := _slider()
    var heard := _heard(slider)
    _drag_away(slider)
    assert_almost_eq(slider.value, 75.0, 0.01, "The drag moved the value away")

    slider._gui_input(_button(MOUSE_BUTTON_RIGHT, true, 150.0))
    assert_almost_eq(slider.value, 40.0, 0.01, "A right press puts back what the value was before the press jumped it")
    assert_eq(heard.back(), 40.0, "and value_changed fired with it last")
    var told := heard.size()

    slider._gui_input(_button(MOUSE_BUTTON_LEFT, false, 150.0))
    slider._gui_input(_motion(20.0))
    assert_eq(heard.size(), told, "The release and a motion with the button still down say nothing more")
    assert_almost_eq(slider.value, 40.0, 0.01, "and the value stays")


func test_escape_through_the_router_does_the_same() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    var router := ShortcutRouter.new()
    _host.add_child(router)
    var slider := _slider()
    var heard := _heard(slider)
    _drag_away(slider)

    router.handle_viewport_input(_escape(), tree.root)
    assert_almost_eq(slider.value, 40.0, 0.01, "Escape puts the start value back")
    assert_eq(heard.back(), 40.0, "and value_changed fired with it last")
    var told := heard.size()

    slider._gui_input(_button(MOUSE_BUTTON_LEFT, false, 150.0))
    assert_eq(heard.size(), told, "The release that follows does nothing")


func test_a_drag_that_never_left_the_start_has_nothing_to_put_back() -> void:
    var slider := _slider()
    var heard := _heard(slider)
    slider._gui_input(_button(MOUSE_BUTTON_LEFT, true, 80.0))
    assert_almost_eq(slider.value, 40.0, 0.01, "A press on the value moves nothing")

    slider._gui_input(_button(MOUSE_BUTTON_RIGHT, true, 80.0))
    assert_true(heard.is_empty(), "so the cancel says nothing either")


func test_neither_key_does_anything_without_a_drag() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    var slider := _slider()
    var heard := _heard(slider)
    slider._gui_input(_button(MOUSE_BUTTON_RIGHT, true, 150.0))
    assert_false(SaSliderDrag.cancel_live(_escape(), tree.root), "No slider is in a drag to cancel")
    assert_almost_eq(slider.value, 40.0, 0.01, "A right press on a slider at rest leaves it")
    assert_true(heard.is_empty(), "and says nothing")

    slider._gui_input(_button(MOUSE_BUTTON_LEFT, true, 60.0))
    slider._gui_input(_button(MOUSE_BUTTON_LEFT, false, 60.0))
    assert_false(SaSliderDrag.cancel_live(_escape(), tree.root), "A released drag is no longer one to cancel")
    assert_almost_eq(slider.value, 30.0, 0.01, "and what it set stays")


func test_a_cancelled_drag_is_a_fresh_start_for_the_next() -> void:
    var slider := _slider()
    _drag_away(slider)
    slider._gui_input(_button(MOUSE_BUTTON_RIGHT, true, 150.0))
    slider._gui_input(_button(MOUSE_BUTTON_LEFT, false, 150.0))

    slider._gui_input(_button(MOUSE_BUTTON_LEFT, true, 100.0))
    slider._gui_input(_motion(120.0))
    assert_almost_eq(slider.value, 60.0, 0.01, "The next drag follows the pointer again")
    slider._gui_input(_button(MOUSE_BUTTON_RIGHT, true, 120.0))
    assert_almost_eq(slider.value, 40.0, 0.01, "and its cancel puts back the value it began at")


## The bar's own case, on the slider that turns the view live: the cancel is a
## `value_changed` like any other, so the view turns back with it.
func test_the_bars_rotation_slider_turns_the_view_back() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    var view := Fixtures.FakeView.new()
    var pair := SaTopBarRotation.new(view)
    pair.attach(_host)
    pair.follow()
    var slider := pair.slider
    slider.size = Vector2(WIDTH, 18.0)

    slider._gui_input(_button(MOUSE_BUTTON_LEFT, true, 150.0))
    slider._gui_input(_motion(180.0))
    assert_almost_eq(rad_to_deg(view.get_rotation()), 144.0, 0.5, "The drag turned the view")

    slider._gui_input(_button(MOUSE_BUTTON_RIGHT, true, 180.0))
    assert_almost_eq(slider.value, 0.0, 0.01, "A right press puts the slider back at the angle it began at")
    assert_almost_eq(rad_to_deg(view.get_rotation()), 0.0, 0.01, "and the view turns back with it")
    slider._gui_input(_button(MOUSE_BUTTON_LEFT, false, 180.0))

    slider._gui_input(_button(MOUSE_BUTTON_LEFT, true, 150.0))
    assert_almost_eq(rad_to_deg(view.get_rotation()), 90.0, 0.5, "A second drag turns the view from its own angle")
    var router := ShortcutRouter.new()
    _host.add_child(router)
    router.handle_viewport_input(_escape(), tree.root)
    assert_almost_eq(rad_to_deg(view.get_rotation()), 0.0, 0.01, "and Escape turns the view back as well")
    slider._gui_input(_button(MOUSE_BUTTON_LEFT, false, 150.0))
