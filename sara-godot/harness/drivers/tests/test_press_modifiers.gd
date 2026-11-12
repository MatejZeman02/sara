## A capture `press` carries all three modifiers, not only shift.
##
## `SaCaptureInput.mouse_button` read `shift` off the step and nothing else, so
## `StateMarquee`, `StateLasso` and `StateWand` could each be driven into their
## add branch and none of them into their subtract branch, while the selection
## mode option's own tooltip documented both. The `click` step had taken `alt`
## since it was written, so the gap was the pair rather than the harness.
##
## These assert the mapping from step to event. What the running app does with
## the event is `scenarios/capture-press-alt.json`, because an event and a
## tool reading it are two different claims.
extends "res://tests/test_framework.gd"

const InputDriver := preload("res://harness/drivers/sa_input_driver.gd")


func test_a_bare_press_carries_no_modifier() -> void:
    var event := InputDriver.button_event({}, "left", true)
    assert_eq(event.button_index, MOUSE_BUTTON_LEFT, "The default button is the left one")
    assert_true(event.pressed, "and a press is pressed")
    assert_false(event.shift_pressed, "with no shift")
    assert_false(event.alt_pressed, "no alt")
    assert_false(event.ctrl_pressed, "and no ctrl")


## The half that already worked, asserted so a later change cannot trade one
## modifier for another.
func test_shift_reaches_the_event() -> void:
    var event := InputDriver.button_event({"shift": true}, "left", true)
    assert_true(event.shift_pressed, "Shift is on the event")
    assert_false(event.alt_pressed, "and asking for shift asks for nothing else")


## The half that did not. The subtract branch of all three selection tools reads
## this flag and nothing could set it.
func test_alt_reaches_the_event() -> void:
    var event := InputDriver.button_event({"alt": true}, "left", true)
    assert_true(event.alt_pressed, "Alt is on the event")
    assert_false(event.shift_pressed, "and asking for alt asks for nothing else")


func test_ctrl_reaches_the_event() -> void:
    var event := InputDriver.button_event({"ctrl": true}, "left", true)
    assert_true(event.ctrl_pressed, "Ctrl is on the event")


## All three at once, because a chord is what a modifier is for.
func test_a_release_carries_the_modifiers_too() -> void:
    var event := InputDriver.button_event({"shift": true, "alt": true, "ctrl": true}, "right", false)
    assert_eq(event.button_index, MOUSE_BUTTON_RIGHT, "The named button is used")
    assert_false(event.pressed, "a release is not pressed")
    assert_true(event.shift_pressed and event.alt_pressed and event.ctrl_pressed, "and it carries all three")
