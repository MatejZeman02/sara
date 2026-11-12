## A pen tap on a docker that was not focused presses what is
## under the pen.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Under Windows Ink Godot reads the pen's hovers in the focused window only, so
## a docker the pen came to unfocused had found no control under it, and the
## first tap pressed nothing. [SaPointerDevice] holds
## such a press, and the release behind it, until a motion shows the window has
## the control, or until a short wait is over. What these hold is that bookkeeping:
## the press and its release are kept in order, a motion over nothing sends
## nothing, a hold is sent once, an old wait sends no newer hold, and what was sent
## passes when it comes back. The tap itself is driven with a synthetic pen on a
## real desktop, because a suite's pen would move the real pointer of whoever
## runs it.
extends "res://tests/test_framework.gd"

const AWAY := Vector2(-4000.0, -4000.0)

var _host: Node = null
## What the hold sent again, caught instead of parsed.
var _sent: Array[InputEventMouseButton] = []


func before_each() -> void:
    SaCursorPolicy.forget_pointer_device()
    _sent.clear()
    SaPointerDevice.send_again = func(button: InputEventMouseButton) -> void: _sent.append(button)
    _host = Node.new()
    _host.name = "PenTapHoldTestHost"
    EventBus.add_child(_host)


func after_each() -> void:
    SaCursorPolicy.forget_pointer_device()
    SaPointerDevice.send_again = Input.parse_input_event
    if _host != null:
        _host.free()
        _host = null


## A window with nothing in it, so nothing is ever under the pen there.
func _empty_window() -> Window:
    var window := Window.new()
    window.borderless = true
    window.size = Vector2i(320, 240)
    _host.add_child(window)
    return window


func _button(pressed: bool) -> InputEventMouseButton:
    var button := InputEventMouseButton.new()
    button.button_index = MOUSE_BUTTON_LEFT
    button.pressed = pressed
    button.position = AWAY
    return button


func test_a_press_over_nothing_is_held_with_the_release_behind_it() -> void:
    var window := _empty_window()
    SaPointerDevice._hold_unhovered_press(_button(true), window)
    assert_eq(SaPointerDevice._held.size(), 1, "The press with nothing under it is held")
    assert_eq(SaPointerDevice._held_window, window, "for its window")
    assert_true(SaPointerDevice._held_back(_button(false), window), "The release behind it is taken")
    assert_eq(SaPointerDevice._held.size(), 2, "and held as well")
    assert_true(SaPointerDevice._held[0].pressed and not SaPointerDevice._held[1].pressed, "press first, release second")
    assert_false(SaPointerDevice._held_back(InputEventMouseMotion.new(), window), "A motion over nothing passes")
    assert_eq(SaPointerDevice._held.size(), 2, "and sends nothing")


func test_a_button_in_another_window_is_left_alone() -> void:
    var window := _empty_window()
    var other := _empty_window()
    SaPointerDevice._hold_unhovered_press(_button(true), window)
    assert_false(SaPointerDevice._held_back(_button(false), other), "A release in another window is not taken")
    assert_eq(SaPointerDevice._held.size(), 1, "and the hold is as it was")


func test_the_wait_sends_the_hold_once_and_what_it_sent_passes() -> void:
    var window := _empty_window()
    SaPointerDevice._hold_unhovered_press(_button(true), window)
    SaPointerDevice._held_back(_button(false), window)
    var serial := SaPointerDevice._hold_serial
    SaPointerDevice._send_held(serial)
    assert_true(SaPointerDevice._held.is_empty(), "The end of the wait sends the hold")
    assert_eq(SaPointerDevice._held_window, null, "and lets the window go")
    assert_eq(SaPointerDevice._resending, 2, "with two buttons on their way back")
    assert_eq(_sent.size(), 2, "sent again")
    assert_true(_sent[0].pressed and not _sent[1].pressed, "press first, release second")
    SaPointerDevice._send_held(serial)
    assert_eq(_sent.size(), 2, "A second end of the same wait sends nothing")
    assert_true(SaPointerDevice._held_back(_button(true), window), "The press coming back passes")
    assert_true(SaPointerDevice._held_back(_button(false), window), "and so does its release")
    assert_false(SaPointerDevice._held_back(_button(true), window), "and a new press is a new press")


func test_an_old_wait_sends_no_newer_hold() -> void:
    var window := _empty_window()
    SaPointerDevice._hold_unhovered_press(_button(true), window)
    var old := SaPointerDevice._hold_serial
    SaPointerDevice._send_held(old)
    SaCursorPolicy.forget_pointer_device()
    SaPointerDevice._hold_unhovered_press(_button(true), window)
    SaPointerDevice._send_held(old)
    assert_eq(SaPointerDevice._held.size(), 1, "The first tap's wait leaves the second tap's press held")


func test_a_release_alone_is_never_held() -> void:
    var window := _empty_window()
    SaPointerDevice._hold_unhovered_press(_button(false), window)
    assert_true(SaPointerDevice._held.is_empty(), "A release with no held press goes straight on")
    SaPointerDevice._hold_unhovered_press(InputEventMouseMotion.new(), window)
    assert_true(SaPointerDevice._held.is_empty(), "and so does a motion")
