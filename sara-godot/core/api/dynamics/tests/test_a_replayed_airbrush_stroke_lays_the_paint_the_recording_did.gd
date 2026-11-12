## A replayed airbrush stroke lays the paint the recorded one did.
##
## The airbrush lays its paint by the clock, so a lesson's replay at another
## pace, or on a busier machine, laid more or less of it than the recording had.
## `SaPenClock.frame_elapsed_ms` is the interval the airbrush now asks for: the
## engine's frame while nothing follows a recording, and the recording's own
## frame while a replay does. This suite holds the live half to today's feel,
## and `scripts/test_...py` holds the replay to the recorded picture.
extends "res://tests/test_framework.gd"

const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")

## `StateBrush._init` loads the dab kernel, so it needs a rendering device even
## though nothing here dispatches one.
const REQUIRES_GPU := true


## A brush with the pen down and the airbrush on at *rate*.
func _held(rate: float) -> RefCounted:
    var brush := StateBrushScript.new()
    brush.settings.airbrush_enabled = true
    brush.settings.airbrush_rate = rate
    brush.is_drawing = true
    return brush


## The dabs a pen held still over *deltas* lays, timed the way `tick` times it
## when *clocked*, and by the bare delta, the airbrush, when not.
func _dabs(rate: float, deltas: PackedFloat64Array, clocked: bool) -> int:
    var brush := _held(rate)
    var dabs := 0
    for delta: float in deltas:
        var seconds := SaPenClock.frame_elapsed_ms(delta) / 1000.0 if clocked else delta
        dabs += brush.airbrush_dabs_for_frame(seconds)
    return dabs


## One second of frames: even at 60 a second, and the uneven ones a loaded
## machine makes, which add up to the same second.
func _seconds() -> Array[PackedFloat64Array]:
    var even := PackedFloat64Array()
    for _frame in 60:
        even.append(1.0 / 60.0)
    var uneven := PackedFloat64Array()
    var left := 1.0
    var at := 0
    while left > 1e-9:
        var delta := minf(left, [0.004, 0.031, 0.017, 0.052, 0.009][at % 5])
        uneven.append(delta)
        left -= delta
        at += 1
    return [even, uneven]


func test_a_live_airbrush_held_still_for_a_second_lays_as_much_paint_as_today() -> void:
    assert_false(SaPenClock.is_followed(), "Nothing follows a recording outside a replay")
    for rate: float in [10.0, 40.0, 50.0]:
        for deltas: PackedFloat64Array in _seconds():
            var today := _dabs(rate, deltas, false)
            var now := _dabs(rate, deltas, true)
            # A second the frames add up to a hair under lays one dab fewer.
            assert_almost_eq(float(today), rate, 1.0, "Today's airbrush lays rate %d over a second" % int(rate))
            assert_almost_eq(
                float(now),
                float(today),
                0.01 * today,
                "A live second at rate %d over %d frames lays today's dabs within a per cent" % [int(rate), deltas.size()]
            )


func test_a_live_frame_is_the_engines_delta() -> void:
    for delta: float in [0.0, 1.0 / 144.0, 1.0 / 60.0, 0.25]:
        assert_almost_eq(SaPenClock.frame_elapsed_ms(delta), delta * 1000.0, 1e-9, "Live, the interval is the delta")


## A replay's frame is the one it handed, whatever the engine's delta was, and
## a frame of a slowed replay it handed nothing to lays nothing.
func test_a_followed_clock_answers_the_recordings_frame_and_not_the_engines() -> void:
    # Let go before the asserts, so a failing one leaves no clock followed
    # for the suites after it.
    SaPenClock.follow(3883333)
    SaPenClock.hand_frame(16.666667)
    var read := [SaPenClock.is_followed(), SaPenClock.now_usec(), SaPenClock.report_usec(), SaPenClock.frame_elapsed_ms(0.5)]
    SaPenClock.let_go()
    assert_true(read[0], "A replay follows the recording")
    assert_eq(read[1], 3883333, "A followed clock reads the recording's time")
    assert_eq(read[2], 3883333, "And a report, which the stroke's seed is drawn from")
    assert_eq(read[3], 0.0, "This frame was handed nothing, the next is")
    assert_false(SaPenClock.is_followed())
    assert_almost_eq(SaPenClock.frame_elapsed_ms(0.5), 500.0, 1e-9, "Let go, the engine's delta again")


## The tick a recording keeps beside a point: this frame's before its airbrush
## asked, the next one's after.
func test_a_point_made_after_the_tick_belongs_to_the_next_frame() -> void:
    var frame := Engine.get_process_frames()
    SaPenClock.frame_elapsed_ms(0.0)
    assert_eq(SaPenClock.tick_frame(), frame + 1)


## A replay hands its stroke the seed the recording drew, once, and a stroke
## after it draws its own off the clock again.
func test_a_handed_seed_is_drawn_by_the_next_stroke_only() -> void:
    var drawn := SaPenClock.seeds_drawn
    SaPenClock.seed_next(3850000)
    var seeds := [SaPenClock.stroke_seed(), SaPenClock.last_seed]
    OS.delay_usec(10)
    seeds.append(SaPenClock.stroke_seed())
    assert_eq(seeds[0], 3850000, "The next stroke draws the handed seed")
    assert_eq(seeds[1], 3850000, "which a recording reads back")
    assert_true(seeds[2] != 3850000, "and the one after draws its own")
    assert_eq(SaPenClock.seeds_drawn, drawn + 2, "Each stroke's draw is counted")
