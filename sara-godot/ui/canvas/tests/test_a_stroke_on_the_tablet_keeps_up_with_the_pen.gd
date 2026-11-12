## A stroke on the tablet keeps up with the pen.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The tablet's ring trailed its pen by about 124 ms where Krita's trailed by
## 67. Three of the four causes are rules a suite can hold on
## any machine: the painting cap follows an Android panel whose rate moves under
## the hand, the ring leads on Android, where nothing but Sara draws the pen,
## and a frame's events handled before its tick are its work rather than a
## wait. The fourth, Android's batching of pen events, is a request to the
## window that only an Android build can make, and here it says it made none.
extends "res://tests/test_framework.gd"


func before_each() -> void:
    SaStrokeLedger.reset()


func after_each() -> void:
    SaStrokeLedger.reset()


## A pacer whose painting cap is *rate*, stepped by hand as `test_frame_pacer`
## steps its own, with the engine's cap and the setting put back by `_drop`.
func _pacer(rate: String) -> SaFramePacer:
    var pacer := SaFramePacer.new()
    pacer.set_meta("previous_fps", Engine.max_fps)
    pacer.set_meta("previous_low", OS.low_processor_usage_mode)
    pacer.set_meta("previous_rate", SaSettings.painting_frame_rate)
    SaSettings.painting_frame_rate = rate
    pacer._ready()
    return pacer


func _drop(pacer: SaFramePacer) -> void:
    Engine.max_fps = int(pacer.get_meta("previous_fps"))
    OS.low_processor_usage_mode = bool(pacer.get_meta("previous_low"))
    SaSettings.painting_frame_rate = String(pacer.get_meta("previous_rate"))
    pacer.free()


## The tablet's panel rested at 60 Hz and ran at 120 a moment after a touch, so
## a cap read as the hand started could be the resting rate. On Android the cap
## is read again while the hand moves and follows the panel, and elsewhere it
## stays what the stroke's start read.
func test_on_android_the_painting_cap_follows_the_panel_while_the_hand_moves() -> void:
    var pacer := _pacer(SaSettingsPerformance.THIRTY)
    pacer.note_motion()
    Engine.max_fps = 60
    assert_false(pacer.follow_the_panel("Wayland"), "A desktop's cap stays what the stroke's start read")
    assert_eq(Engine.max_fps, 60, "so it is not touched there")
    assert_true(pacer.follow_the_panel("Android"), "On Android a cap that no longer matches is put in again")
    assert_eq(Engine.max_fps, SaFramePacer.painting_max_fps(), "at what the display says now")
    assert_false(pacer.follow_the_panel("Android"), "and a cap that matches is left alone")
    pacer.rest()
    Engine.max_fps = 60
    assert_false(pacer.follow_the_panel("Android"), "A hand at rest keeps the resting cap")
    assert_eq(Engine.max_fps, 60, "untouched")
    _drop(pacer)


## Unbatched pen events are asked of an Android window alone, and the dump says
## whether they were.
func test_unbatched_pen_events_are_asked_on_android_alone() -> void:
    assert_false(SaFramePacer.request_unbuffered_pen(), "A run that is not Android asks nothing")
    var pacer := _pacer(SaSettingsPerformance.THIRTY)
    assert_false(pacer.unbuffered_pen, "and its pacer says so")
    _drop(pacer)


## Auto leads the ring where a pen moves a pointer Sara alone draws. On Android
## that is so under every mode but Never, because the system draws nothing for
## a pen over Godot's window, while Sara's own arrow over the dockers stays the
## desktop's question.
func test_the_ring_leads_on_android() -> void:
    var previous: String = SaSettings.software_cursor
    SaSettings.software_cursor = "auto"
    assert_true(SaCursorPolicy.sara_draws_the_pen("Android"), "On Android Sara alone draws where the pen is")
    assert_eq(
        SaCursorPolicy.sara_draws_the_pen("X11"),
        SaCursorPolicy.software_pointer_mode_active(),
        "and elsewhere the answer is the pointer mode's",
    )
    assert_true(
        SaCursorPrediction.auto_lead_on(true, SaCursorPolicy.sara_draws_the_pen("Android")), "so a pen's ring leads there"
    )
    SaSettings.software_cursor = "never"
    assert_false(SaCursorPolicy.sara_draws_the_pen("Android"), "Never is the painter's word, on Android too")
    SaSettings.software_cursor = previous


## Events handled before the tick are the frame's own work. On Android every
## pen event is handled between two iterations, so a wait measured from the
## tick alone counted them, and a frame whose input took 1.26 s read a wait of
## 1.26 s.
func test_events_handled_before_the_tick_are_work_and_not_a_wait() -> void:
    assert_eq(SaStrokeLedger.busy_from(10_000, 4_000, 2_000), 4_000, "A first event before the tick opens the frame's work")
    assert_eq(SaStrokeLedger.busy_from(10_000, 12_000, 2_000), 10_000, "one after it leaves the tick")
    assert_eq(SaStrokeLedger.busy_from(10_000, 1_000, 2_000), 10_000, "and one the frame before drew is not this frame's")
    assert_eq(SaStrokeLedger.busy_from(10_000, 0, 2_000), 10_000, "and a frame with no event starts at its tick")


## The stroke's line adds every frame's wait up beside its input and its
## drawing, so a stroke's wait is one figure a before and an after compare.
func test_the_line_adds_the_wait_up() -> void:
    SaStrokeLedger.left_button(_button(true), 4)
    SaStrokeLedger.event_arrived(true, 4)
    SaStrokeLedger.dab_dispatched(1, 4)
    SaStrokeLedger.fold_frame(17_000, 1_000, 8_000, 4_200, 3_800)
    SaStrokeLedger.left_button(_button(false), 5)
    SaStrokeLedger.fold_frame(33_000, 1_500, 9_000, 6_500, 16_000)
    var stroke := SaStrokeLedger.last_stroke
    assert_eq(stroke["wait_usec"], 19_800, "The two frames' waits, added")
    var line := SaStrokeLedger.line_of(stroke)
    assert_true(line.contains("Input 2.5 ms, drawing 17.0 ms and waiting 19.8 ms in all."), "and the line says it: %s" % line)


func _button(pressed: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    return event
