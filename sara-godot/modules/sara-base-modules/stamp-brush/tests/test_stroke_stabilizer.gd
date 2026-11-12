## The stabilizer's arithmetic: the average damps a shake, the rope follows
## without overshooting, a reset forgets the last stroke, and the finish ends
## a stroke on the pen.
extends "res://tests/test_framework.gd"

const StabilizerScript = preload("res://modules/sara-base-modules/stamp-brush/walk/stroke_stabilizer.gd")


func _stabilizer(mode: int, amount: float) -> RefCounted:
    var stabilizer := StabilizerScript.new()
    stabilizer.mode = mode
    stabilizer.amount = amount
    return stabilizer


## A zigzag along a line: the raw samples swing four pixels either side, and
## the averaged ones swing less.
func test_the_average_damps_a_shake() -> void:
    var stabilizer := _stabilizer(StabilizerScript.Mode.AVERAGE, 0.5)
    var worst := 0.0
    for i in 40:
        var raw := Vector2(float(i) * 3.0, 4.0 if i % 2 == 0 else -4.0)
        var smoothed: Vector2 = stabilizer.feed(raw)
        if i > 8:
            worst = maxf(worst, absf(smoothed.y))
    assert_true(worst < 2.0, "The swing of four either side comes out under two: %.2f" % worst)
    assert_eq(stabilizer.window(), 13, "Half amount is a window of thirteen samples")


func test_the_average_weights_the_newest_most() -> void:
    var stabilizer := _stabilizer(StabilizerScript.Mode.AVERAGE, 0.0)
    assert_eq(stabilizer.window(), 2, "The lightest setting keeps two samples")
    stabilizer.feed(Vector2(0, 0))
    var out: Vector2 = stabilizer.feed(Vector2(30, 0))
    assert_almost_eq(out.x, 20.0, 0.01, "Weights one and two: the newer sample counts twice")


func test_off_passes_the_pointer_through() -> void:
    var stabilizer := _stabilizer(StabilizerScript.Mode.OFF, 1.0)
    assert_eq(stabilizer.feed(Vector2(7, 9)), Vector2(7, 9), "Nothing moves")


## The rope: the brush stays put until the pointer is a rope's length away,
## then follows so that it is exactly a rope's length behind, and never past.
func test_the_rope_follows_a_rope_length_behind_and_never_overshoots() -> void:
    var stabilizer := _stabilizer(StabilizerScript.Mode.ROPE, 0.0)
    var length: float = stabilizer.rope_length()
    assert_almost_eq(length, 4.0, 0.01, "The shortest rope is four pixels")
    assert_eq(stabilizer.feed(Vector2.ZERO), Vector2.ZERO, "The first sample anchors the rope")
    assert_eq(stabilizer.feed(Vector2(3, 0)), Vector2.ZERO, "Within the rope, the brush does not move")
    var out: Vector2 = stabilizer.feed(Vector2(10, 0))
    assert_almost_eq(out.x, 6.0, 0.01, "Past it, the brush ends a rope's length behind the pointer")
    out = stabilizer.feed(Vector2(0, 0))
    assert_almost_eq(out.x, 4.0, 0.01, "and pulled back the same way, never overshooting the pointer")

    # A shaky hand on a slow curve: the brush moves less than the pointer.
    var long_rope := _stabilizer(StabilizerScript.Mode.ROPE, 1.0)
    long_rope.feed(Vector2.ZERO)
    var travelled := 0.0
    var last := Vector2.ZERO
    for i in 30:
        var raw := Vector2(float(i) * 2.0, 6.0 if i % 2 == 0 else -6.0)
        var smoothed: Vector2 = long_rope.feed(raw)
        travelled += smoothed.distance_to(last)
        last = smoothed
    assert_true(travelled < 30.0, "Sixty pixels of wobble become under thirty of travel: %.1f" % travelled)


## The buffer must be cleared in the reset, or the next stroke starts pulled
## towards the end of the last one.
func test_reset_forgets_the_last_stroke() -> void:
    var stabilizer := _stabilizer(StabilizerScript.Mode.AVERAGE, 1.0)
    for i in 10:
        stabilizer.feed(Vector2(1000, 1000))
    stabilizer.reset()
    assert_eq(stabilizer.feed(Vector2(5, 5)), Vector2(5, 5), "The first sample of a new stroke is where the pen is")

    var rope := _stabilizer(StabilizerScript.Mode.ROPE, 1.0)
    rope.feed(Vector2(1000, 1000))
    rope.reset()
    assert_eq(rope.feed(Vector2(5, 5)), Vector2(5, 5), "and a rope re-anchors there")


## The brush reads the settings on every press and clears the buffer, and a
## preset carries both fields.
func test_the_brush_settings_carry_the_stabilizer() -> void:
    var settings := preload("res://modules/sara-base-modules/stamp-brush/tools/brush_settings.gd").new()
    assert_eq(settings.stabilizer_mode, 0, "Off by default")
    assert_almost_eq(settings.stabilizer_amount, 0.5, 0.001, "at half strength when switched on")


## A fast run of samples along a line, fed as a stroke's motions are.
func _fast_run(stabilizer: RefCounted) -> Vector2:
    var last := Vector2.ZERO
    for i in 60:
        last = stabilizer.feed(Vector2(560.0 + 10.0 * float(i + 1), 300.0))
    return last


## The average lags the pen by its window, and the finish eases the rest of
## the way and ends exactly on the last raw sample, at either end of the
## amount, every point past the last smoothed one and none behind it.
func test_the_averages_finish_ends_on_the_last_raw_sample() -> void:
    for amount: float in [0.0, 1.0]:
        var stabilizer := _stabilizer(StabilizerScript.Mode.AVERAGE, amount)
        var smoothed := _fast_run(stabilizer)
        assert_true(smoothed.x < 1160.0, "At %.0f the brush trails the pen: %.2f" % [amount, smoothed.x])
        var tail: Array[Vector2] = stabilizer.finish()
        assert_true(tail.size() > 0, "At %.0f the finish owes points" % amount)
        assert_eq(tail[-1], Vector2(1160, 300), "At %.0f the finish ends exactly on the pen" % amount)
        var behind := smoothed.x
        var forward := true
        for point in tail:
            forward = forward and point.x > behind
            behind = point.x
        assert_true(forward, "At %.0f every point of the tail moves on towards the pen" % amount)
        assert_eq(stabilizer.finish().size(), 0, "At %.0f a second finish owes nothing" % amount)


## The rope loses up to its length and finishes with the straight run to the
## pen, one point, so the two modes end alike.
func test_the_ropes_finish_is_the_run_to_the_pen() -> void:
    for amount: float in [0.0, 1.0]:
        var stabilizer := _stabilizer(StabilizerScript.Mode.ROPE, amount)
        var smoothed := _fast_run(stabilizer)
        assert_almost_eq(smoothed.x, 1160.0 - stabilizer.rope_length(), 0.01, "At %.0f the brush is a rope behind" % amount)
        var tail: Array[Vector2] = stabilizer.finish()
        assert_eq(tail, [Vector2(1160, 300)] as Array[Vector2], "At %.0f the tail is the pen itself" % amount)


## Off, or on a tap that never moved the brush off the pen, there is nothing
## to finish, so a stroke with no stabiliser lays what it always laid.
func test_no_finish_with_the_stabilizer_off() -> void:
    var off := _stabilizer(StabilizerScript.Mode.OFF, 1.0)
    _fast_run(off)
    assert_eq(off.finish().size(), 0, "Off, the finish answers nothing")
    var tap := _stabilizer(StabilizerScript.Mode.AVERAGE, 1.0)
    tap.feed(Vector2(40, 40))
    assert_eq(tap.finish().size(), 0, "A tap stands on the pen already")
    var unfed := _stabilizer(StabilizerScript.Mode.ROPE, 1.0)
    assert_eq(unfed.finish().size(), 0, "and a stabiliser never fed owes nothing")
