## A capture times its pen by frames, and the app by the wall clock.
##
## A scenario lays one move a frame, and read off the engine's clock the speed
## sensor saw how busy the machine was on that run: the noise strokes of
## `scenarios/the-sitting-after-the-board-h-grounds.json` came out a texel or
## two apart between runs of one tree. Pinned, the clock reads the frames since
## the pin, so the same frames read the same time in every run.
extends "res://tests/test_framework.gd"

const StateNoiseBrushScript = preload("res://modules/sara-noise-brush-engine/state_noise_brush.gd")

var _was_pinned: bool = false


func before_each() -> void:
    _was_pinned = SaPenClock.is_pinned()
    SaPenClock.unpin()


func after_each() -> void:
    SaPenClock.unpin()
    if _was_pinned:
        # A suite has no frames of its own, so the pin taken here counts from
        # this frame, which is the one the run it interrupted was in.
        SaPenClock.pin_to_frames()


## Unpinned, the clock is the engine's.
func test_the_app_reads_the_wall_clock() -> void:
    var before := Time.get_ticks_usec()
    var now := SaPenClock.now_usec()
    assert_false(SaPenClock.is_pinned(), "The app's clock is not pinned")
    assert_true(now >= before and now <= Time.get_ticks_usec(), "and reads the engine's microseconds")


## Pinned, the clock stands still inside a frame whatever the wall does, and
## starts at its origin rather than at nought, which a seed would read as
## "draw one from the clock".
func test_a_pinned_clock_reads_the_frame_not_the_wall() -> void:
    SaPenClock.pin_to_frames()
    var first := SaPenClock.now_usec()
    OS.delay_usec(3000)
    assert_eq(SaPenClock.now_usec(), first, "Three wall milliseconds later in the same frame, a pinned clock has not moved")
    assert_eq(first, SaPenClock.PINNED_ORIGIN_USEC, "and it reads its origin on the frame it was pinned in")
    assert_almost_eq(SaPenClock.now_ms(), float(SaPenClock.PINNED_ORIGIN_USEC) / 1000.0, 0.0001, "the same in milliseconds")


## A noise brush with Randomness above nought draws its seed from the pen's
## clock, so a pinned run lays the same field in every run.
func test_a_clock_drawn_seed_is_the_pinned_clocks() -> void:
    var brush := StateNoiseBrushScript.new()
    brush.settings.randomness = 0.5
    SaPenClock.pin_to_frames()
    assert_eq(brush.seed_for_stroke(), SaPenClock.PINNED_ORIGIN_USEC, "A seed drawn from a pinned clock is the pin's own reading")
