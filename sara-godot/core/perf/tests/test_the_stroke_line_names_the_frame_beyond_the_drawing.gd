## The frame a stroke's line names beyond its drawing: the card's time for it
## and the wait for the display, and the budget the line counts against, which
## is one refresh of the display the window is on.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A test function cannot wait for a frame, so the frames are fed whole through
## the ledger's own fold, the way its other suites hand its hooks the frame
## indices a stroke injected in one frame has. Every figure here is one this
## suite named, so the line's new parts are read against the frame they came
## from and not against whatever a loading machine happened to take.
extends "res://tests/test_framework.gd"

## The card's own time comes from the engine's render measure, which needs a
## RenderingDevice.
const REQUIRES_GPU := true


func before_each() -> void:
    SaStrokeLedger.reset()


func after_each() -> void:
    SaStrokeLedger.follow_display(-1.0)
    SaStrokeLedger.reset()


## A stroke of two known frames: the line names the card's time for the longest
## one and the wait for the display beside its input and its drawing, and the
## figures behind the line say the same.
func test_the_line_names_the_card_s_time_and_the_wait_of_the_longest_frame() -> void:
    SaStrokeLedger.left_button(_button(true), 4)
    SaStrokeLedger.event_arrived(true, 4)
    SaStrokeLedger.dab_dispatched(1, 4)
    SaStrokeLedger.fold_frame(17_000, 1_000, 8_000, 4_200, 3_800)
    SaStrokeLedger.left_button(_button(false), 5)
    SaStrokeLedger.fold_frame(33_000, 1_500, 9_000, 6_500, 16_000)

    var stroke := SaStrokeLedger.last_stroke
    assert_false(stroke.is_empty(), "The frame that shows the release ends the stroke")
    var longest: Dictionary = stroke["longest"]
    assert_eq(stroke["frames"]["max"], 33_000, "The longer frame is the one the line splits")
    assert_eq(longest["gpu"], 6_500, "with the card's time that came with it")
    assert_eq(longest["wait"], 16_000, "and the wait for the display")
    var line := SaStrokeLedger.line_of(stroke)
    assert_true(
        line.contains("(input 1.5 ms, drawing 9.0 ms, outside 22.5 ms (gpu 6.5 ms, wait 16.0 ms),"),
        "The line names them in one clause: %s" % line,
    )
    assert_false(line.contains(";"), "No semicolon in a line a painter reads")
    assert_false(line.contains("—"), "and no em dash")


## The budget follows the display: the same nineteen milliseconds is an early
## frame on a fifty hertz screen and a late one on a sixty hertz screen, and a
## driver that will not name a rate leaves the sixty hertz fallback.
func test_the_budget_follows_the_display() -> void:
    SaStrokeLedger.follow_display(50.0)
    SaStrokeLedger.reset()
    SaStrokeLedger.fold_frame(19_000, 0, 0, 0, 0)
    var fifty: Dictionary = SaStrokeLedger.block()["frame_usec"]
    assert_eq(fifty["budget"], 20_000, "One refresh of a fifty hertz display is twenty milliseconds")
    assert_eq(fifty["slow"], 0, "so a nineteen millisecond frame is within it")

    SaStrokeLedger.follow_display(60.0)
    SaStrokeLedger.reset()
    SaStrokeLedger.fold_frame(19_000, 0, 0, 0, 0)
    var sixty: Dictionary = SaStrokeLedger.block()["frame_usec"]
    assert_eq(sixty["budget"], 16_667, "One refresh of sixty hertz")
    assert_eq(sixty["slow"], 1, "so the same frame is over it")

    SaStrokeLedger.follow_display(-1.0)
    SaStrokeLedger.reset()
    SaStrokeLedger.fold_frame(19_000, 0, 0, 0, 0)
    var unknown: Dictionary = SaStrokeLedger.block()["frame_usec"]
    assert_eq(unknown["budget"], SaFrameTimes.BUDGET_USEC, "A driver that answers -1 falls back to sixty hertz")
    assert_eq(unknown["slow"], 1, "and counts the frame the same way")
    assert_eq(SaFrameTimes.budget_for_hz(144.0), 6_944, "and a rate the driver does name is one refresh of it")


## The line says which budget it judged against, so a painter reading "over
## 20.0 ms" knows it was their own panel and not a constant.
func test_the_line_names_the_display_s_own_budget() -> void:
    SaStrokeLedger.follow_display(50.0)
    SaStrokeLedger.left_button(_button(true), 6)
    SaStrokeLedger.event_arrived(true, 6)
    SaStrokeLedger.dab_dispatched(1, 6)
    SaStrokeLedger.fold_frame(19_000, 500, 4_000, 2_000, 12_000)
    SaStrokeLedger.left_button(_button(false), 7)
    SaStrokeLedger.fold_frame(19_000, 500, 4_000, 2_000, 12_000)

    var line := SaStrokeLedger.line_of(SaStrokeLedger.last_stroke)
    assert_true(line.contains("0 over 20.0 ms."), "The line counts against the display's refresh: %s" % line)


## The app's own path reads both figures itself, which is the path the post draw
## signal takes: the card's time from the engine's measure and the wait from the
## frame's period beyond its iteration. Neither can be named in advance on a
## loaded machine, so what is read here is that the frame carries both, and that
## a suite's own word for them replaces the reading.
func test_the_signal_s_path_reads_both_figures_itself() -> void:
    SaStrokeLedger.left_button(_button(true), 8)
    SaStrokeLedger.event_arrived(true, 8)
    SaStrokeLedger.dab_dispatched(1, 8)
    SaStrokeLedger.frame_ticked()
    SaStrokeLedger.frame_drawn(8)
    SaStrokeLedger.left_button(_button(false), 9)
    SaStrokeLedger.frame_drawn(9)
    var read: Dictionary = SaStrokeLedger.last_stroke["longest"]
    assert_true(read.has("gpu"), "The frame the signal folded carries the card's time")
    assert_true(read.has("wait"), "and the wait for the display")

    SaStrokeLedger.left_button(_button(true), 10)
    SaStrokeLedger.event_arrived(true, 10)
    SaStrokeLedger.dab_dispatched(1, 10)
    OS.delay_usec(6_000)
    SaStrokeLedger.frame_drawn(10, 1_234, 5_678)
    SaStrokeLedger.left_button(_button(false), 11)
    SaStrokeLedger.frame_drawn(11)
    var given: Dictionary = SaStrokeLedger.last_stroke["longest"]
    assert_eq(given["gpu"], 1_234, "A time a suite names is the one the frame folds")
    assert_eq(given["wait"], 5_678, "for the wait too")


## The measure the card's figure comes from is the engine's own, and asking for
## it on a run with no rendering device answers nought rather than failing, so a
## headless run's line still folds.
func test_the_engine_s_measure_is_read_without_a_viewport() -> void:
    assert_true(SaStrokeLedger.measured_gpu_usec() >= 0, "The engine's own measure answers a time")


func _button(pressed: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    return event
