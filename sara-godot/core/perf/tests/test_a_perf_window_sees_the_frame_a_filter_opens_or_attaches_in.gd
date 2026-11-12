## A perf window sees the frame a filter opens or attaches in.
##
## A frame of 114 ms where a dialog opened must not be left out of the window's
## maximum of 37 ms left out. The maximum was `frames.process_usec_max`, the
## engine's `Performance.TIME_PROCESS`, which the engine sets once a second to
## the longest frame of the second before. So a window shorter than a second
## missed the frame its own open landed in and read the one before its `begin`.
## The ledger now clocks each iteration from its tick, and these two hold both
## halves: the long frame inside the window is read, the one before it is not.
##
## A test function cannot await a frame, so each iteration is the pair of hooks
## the main canvas connects, with a delay standing in for the open's work.
extends "res://tests/test_framework.gd"

## `end` draws the device's frame delay before it folds.
const REQUIRES_GPU := true

## What an open cost in the timers was 114 ms, and in this unit's run 191 ms.
const OPEN_USEC := 40000

## An iteration with nothing in it, the tick straight to its post draw. The
## forced draws of `end` may fold into the window as well when a main canvas of
## an earlier suite left the hooks connected, and they cost a few milliseconds.
const QUIET_USEC := 20000


func before_each() -> void:
    SaPerfWindow.forget()
    SaStrokeLedger.reset()


func after_each() -> void:
    SaPerfWindow.forget()
    SaStrokeLedger.reset()


func _frames_of(line: String) -> Dictionary:
    var parsed: Variant = JSON.parse_string(line.trim_prefix("SaCapture: measure perf "))
    assert_true(parsed is Dictionary, "the end answers a block: %s" % line.left(80))
    return (parsed as Dictionary).get("frames", {}) if parsed is Dictionary else {}


## The open's iteration, the first after `begin`, is the longest frame the
## window reads, however short the window is.
func test_the_frame_an_open_lands_in_is_the_windows_own() -> void:
    SaPerfWindow.capture(null, "begin")
    SaStrokeLedger.frame_ticked()
    OS.delay_usec(OPEN_USEC)
    SaStrokeLedger.frame_drawn()
    SaStrokeLedger.frame_ticked()
    SaStrokeLedger.frame_drawn()
    var frames := _frames_of(SaPerfWindow.capture(null, "end"))
    var longest := int(frames.get("process_usec_max", 0))
    assert_true(longest >= OPEN_USEC, "the open's %d us frame is in the window, which read %d us" % [OPEN_USEC, longest])
    assert_true(longest < OPEN_USEC + QUIET_USEC, "and nothing but it: %d us against the open's %d us" % [longest, OPEN_USEC])


## An attach's iteration that drew nothing is timed to the next tick, so work
## whose frame is drawn later is not lost either.
func test_an_iteration_that_draws_nothing_is_timed_to_the_next_tick() -> void:
    SaPerfWindow.capture(null, "begin")
    SaStrokeLedger.frame_ticked()
    OS.delay_usec(OPEN_USEC)
    SaStrokeLedger.frame_ticked()
    SaStrokeLedger.frame_drawn()
    var frames := _frames_of(SaPerfWindow.capture(null, "end"))
    var longest := int(frames.get("process_usec_max", 0))
    assert_true(longest >= OPEN_USEC, "the attach's %d us iteration is in the window, which read %d us" % [OPEN_USEC, longest])


## A long frame the harness spent before `begin`, a shot or a state dump, is
## not the window's. the attach window read the 197 ms of the dump and the
## shot taken after the window before it.
func test_a_frame_before_begin_is_not_the_windows() -> void:
    SaStrokeLedger.frame_ticked()
    OS.delay_usec(OPEN_USEC)
    SaStrokeLedger.frame_drawn()
    SaPerfWindow.capture(null, "begin")
    SaStrokeLedger.frame_ticked()
    SaStrokeLedger.frame_drawn()
    var frames := _frames_of(SaPerfWindow.capture(null, "end"))
    var longest := int(frames.get("process_usec_max", 0))
    assert_true(longest < QUIET_USEC, "the window held one quiet frame and read %d us" % longest)
