## Ctrl and the wheel over a closed dropdown step through its options.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Ctrl and scroll over a dropdown button quickly try the options without
## clicking. A notch is a row, in the
## order the list shows, past a disabled row, held at the ends, and announced
## with the signal a press in the list sends.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const REQUIRES_GPU := true


func _notch(down: bool, ctrl: bool = true, factor: float = 1.0) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_WHEEL_DOWN if down else MOUSE_BUTTON_WHEEL_UP
    event.pressed = true
    event.ctrl_pressed = ctrl
    event.factor = factor
    return event


func _five() -> SaChoiceButton:
    var button := SaChoiceButton.new()
    (
        button
        . set_choices(
            [
                {"id": &"a", "label": "A"},
                {"id": &"b", "label": "B"},
                {"id": &"c", "label": "C", "disabled": true},
                {"id": &"d", "label": "D"},
                {"id": &"e", "label": "E"},
            ]
        )
    )
    return button


func test_a_notch_down_steps_past_the_disabled_row_and_holds_at_the_last() -> void:
    var button := _five()
    var picked: Array = []
    button.choice_picked.connect(func(value: Variant) -> void: picked.append(value))
    assert_eq(button.selected_value(), &"a", "The list starts on its first row")

    button._gui_input(_notch(true))
    assert_eq(button.selected_value(), &"b", "One notch down is the row below")
    button._gui_input(_notch(true))
    assert_eq(button.selected_value(), &"d", "and the next passes over the disabled row")
    assert_eq(button.text, "D", "with the button reading the row it landed on")
    button._gui_input(_notch(true))
    button._gui_input(_notch(true))
    button._gui_input(_notch(true))
    assert_eq(button.selected_value(), &"e", "The last row holds against more notches, with no wrap to the first")
    assert_eq(picked, [&"b", &"d", &"e"], "and each step that moved is announced once, the held ones not at all")
    assert_false(button.popup.visible, "The list stays closed throughout")
    button.free()


func test_a_notch_up_holds_at_the_first() -> void:
    var button := _five()
    button.select_value(&"e")
    var picked: Array = []
    button.choice_picked.connect(func(value: Variant) -> void: picked.append(value))
    for _notch_index in 6:
        button._gui_input(_notch(false))
    assert_eq(button.selected_value(), &"a", "Up runs to the first row and holds there")
    assert_eq(picked, [&"d", &"b", &"a"], "past the disabled row, once a step")
    button.free()


func test_the_wheel_without_ctrl_leaves_the_value_alone() -> void:
    var button := _five()
    var picked: Array = []
    button.choice_picked.connect(func(value: Variant) -> void: picked.append(value))
    button._gui_input(_notch(true, false))
    button._gui_input(_notch(false, false))
    assert_eq(button.selected_value(), &"a", "A plain wheel is the docker's scroll, not a step")
    assert_eq(picked, [], "and announces nothing")
    button.free()


func test_a_touchpad_swipe_adds_up_to_a_notch() -> void:
    var button := _five()
    for _part in 3:
        button._gui_input(_notch(true, true, 0.3))
    assert_eq(button.selected_value(), &"a", "Nine tenths of a notch is not yet a step")
    button._gui_input(_notch(true, true, 0.3))
    assert_eq(button.selected_value(), &"b", "and the part that makes it whole is one")
    var pan := InputEventPanGesture.new()
    pan.ctrl_pressed = true
    pan.delta = Vector2(0.0, SaStep.PAN_PER_NOTCH * 0.6)
    button._gui_input(pan)
    assert_eq(button.selected_value(), &"b", "A Wayland pan of six tenths of a notch is not a step either")
    button._gui_input(pan)
    assert_eq(button.selected_value(), &"d", "and a second makes one, past the disabled row")
    button.free()


func test_a_run_of_steps_says_it_continues_until_the_pointer_leaves() -> void:
    var button := _five()
    var runs: Array = []
    button.choice_picked.connect(func(_value: Variant) -> void: runs.append(button.continues_a_run()))
    button._gui_input(_notch(true))
    button._gui_input(_notch(true))
    button.mouse_exited.emit()
    button._gui_input(_notch(true))
    assert_eq(runs, [false, true, false], "The first step starts a run, the second folds into it, and leaving ends it")
    button.toggle_list()
    button.popup.press_row(SaChoiceButton.row_id_of(&"a"))
    assert_eq(runs, [false, true, false, false], "A press in the list is never part of a run")
    assert_false(button.continues_a_run(), "and outside a pick nothing is")
    button.free()


func test_a_blend_button_visits_each_mode_once_with_a_favourite_on_top() -> void:
    var was: Array = SaSettings.blend_favorites
    SaSettings.blend_favorites = ["multiply"]
    var button := BlendModeButton.new()
    button.registry = Fixtures.make_registries().blend_modes
    button.include_hidden_in_layers = false
    button.refresh()
    var order := button.stepped_order()
    assert_eq(order[0], &"multiply", "The favourite comes first, as the list shows it")
    assert_eq(order.count(&"multiply"), 1, "and is not visited again in its own section")

    button.select_mode(order[0])
    var picked: Array[StringName] = []
    button.mode_selected.connect(func(mode_id: StringName) -> void: picked.append(mode_id))
    for _notch_index in order.size() + 2:
        button._gui_input(_notch(true))
    var expected: Array[StringName] = order.slice(1)
    assert_eq(picked, expected, "A notch at a time walks every other mode once, in order, and holds at the last")
    assert_eq(button.current, order[-1], "The button ends on the last mode")

    button.select_mode(&"normal")
    picked.clear()
    for _notch_index in 3:
        button._gui_input(_notch(true))
    var normal_at := order.find(&"normal")
    assert_eq(picked, order.slice(normal_at + 1, normal_at + 4), "Three notches from Normal are the three modes after it")

    SaSettings.blend_favorites = was
    button.free()
