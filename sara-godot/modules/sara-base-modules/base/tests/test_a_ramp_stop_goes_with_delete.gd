## A colour ramp stop goes with Delete, and the remove control says so.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The testers of 2026-10-06 asked for right-click and Delete beside the button
## and found the button, a bare minus sign, hard to find. Right-click was
## already there. The control is fed the events a window would give it,
## detached.
extends "res://tests/test_framework.gd"


func _control(stops: int = 3) -> SaColorRampControl:
    var control := SaColorRampControl.new()
    var ramp := SaColorRamp.from_pair(Color.RED, Color.BLUE)
    if stops > 2:
        ramp.add_stop(0.5)
    control.bind_ramp(ramp)
    return control


func test_delete_removes_the_selected_stop() -> void:
    var control := _control()
    control.select_stop(1)

    (control.find_child("Bar", true, false) as Control).gui_input.emit(_key())

    assert_eq(control.ramp.size(), 2, "the middle stop is gone")
    control.free()


func test_delete_on_the_stop_row_does_the_same() -> void:
    var control := _control()
    control.select_stop(1)

    (control.find_child("RemoveStop", true, false) as Control).gui_input.emit(_key())

    assert_eq(control.ramp.size(), 2, "from the remove control's own focus")
    control.free()


func test_at_the_fewest_stops_delete_changes_nothing() -> void:
    var control := _control(2)
    var before := control.ramp.size()
    assert_eq(before, SaColorRamp.MIN_STOPS, "a fresh pair is the fewest")

    (control.find_child("Bar", true, false) as Control).gui_input.emit(_key())

    assert_eq(control.ramp.size(), SaColorRamp.MIN_STOPS, "no stop goes")
    var button := control.find_child("RemoveStop", true, false) as Button
    assert_true(button.disabled, "and the remove control is disabled, which dims it")
    control.free()


func test_the_remove_control_is_a_word_and_enabled_above_the_fewest() -> void:
    var control := _control()

    var button := control.find_child("RemoveStop", true, false) as Button

    assert_eq(button.text, "Remove", "it says what it does")
    assert_false(button.disabled, "and is live with three stops")
    assert_true(button.tooltip_text.contains("Delete"), "its tooltip names the key")
    control.free()


func _key() -> InputEventKey:
    var event := InputEventKey.new()
    event.keycode = KEY_DELETE
    event.pressed = true
    return event
