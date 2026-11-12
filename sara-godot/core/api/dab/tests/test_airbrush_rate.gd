## The airbrush deposits the rate it is set to, measured against time.
##
## A drive held the pointer for "the same 60 frames" at rate 10 and at rate 50 and
## counted 8 dabs and 48, read those as 80 and 96 per cent of what the rate
## asked for, and filed the shortfall because no single fraction explains both.
## **A frame is not a sixtieth of a second in an offscreen capture**, and that is
## the whole of it: 8 dabs in 60 frames at rate 10 is a run at 75 frames a
## second, 48 in 60 at rate 50 is a run at 62.5, and both are exactly the rate
## asked for over the time those frames took. A capture that paints more each
## time slows down between one hold and the next, which is the order the drive's
## scenario runs them in.
##
## So this suite measures the clock rather than counting frames.
## `StateBrush.airbrush_dabs_for_frame` is the decision without the dispatch, and
## the deltas below are the interval, added up by the test itself.
extends "res://tests/test_framework.gd"

const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")
const DabCadence = preload("res://core/api/dab/sa_dab_cadence.gd")

## `StateBrush._init` loads the dab kernel, so it needs a rendering device even
## though nothing here dispatches one.
const REQUIRES_GPU := true

## The frame rate an offscreen capture is assumed to run at and does not.
const NOMINAL_FPS: float = 60.0


## A brush with the pen down, the airbrush on at *rate*, and nothing else set.
func _held(rate: float) -> RefCounted:
    var brush := StateBrushScript.new()
    brush.settings.airbrush_enabled = true
    brush.settings.airbrush_rate = rate
    brush.is_drawing = true
    return brush


## The dabs *deltas* deposit, and the seconds they took, so the caller divides
## one by the other rather than assuming what a frame is worth.
func _walk(rate: float, deltas: PackedFloat64Array) -> Array:
    var brush := _held(rate)
    var dabs := 0
    var seconds := 0.0
    for delta: float in deltas:
        dabs += brush.airbrush_dabs_for_frame(delta)
        seconds += delta
    return [dabs, seconds, brush]


func _even(fps: float, frames: int) -> PackedFloat64Array:
    var deltas := PackedFloat64Array()
    for _frame in frames:
        deltas.append(1.0 / fps)
    return deltas


## The clause the filing asks for: the count the rate asks for, over an interval
## the test measured rather than counted.
func test_a_held_pen_deposits_its_rate_over_a_measured_second() -> void:
    for rate: float in [10.0, 50.0]:
        var walked := _walk(rate, _even(NOMINAL_FPS, int(NOMINAL_FPS)))
        var dabs: int = walked[0]
        var seconds: float = walked[1]
        assert_almost_eq(seconds, 1.0, 1e-5, "The interval is measured, not assumed")
        assert_eq(dabs, int(rate), "Rate %d deposits %d dabs in a measured second" % [int(rate), int(rate)])


## And the same over two seconds and a third of one, because a rate that is only
## right at the length the test happens to pick is not a rate.
func test_the_count_follows_the_interval_rather_than_the_frame_count() -> void:
    for seconds: float in [0.5, 2.0]:
        var frames := int(NOMINAL_FPS * seconds)
        var walked := _walk(20.0, _even(NOMINAL_FPS, frames))
        assert_eq(int(walked[0]), int(20.0 * seconds), "Rate 20 over %.1f measured seconds" % seconds)


## The drive's own two numbers, reproduced from the frame rates that produce them.
##
## This is the assertion that turns the filing from a defect into an arithmetic
## error, and it fails the moment the walk really does lose dabs. Two corrections
## to the drive's reading, both measured on the running app in
## `scenarios/airbrush-rate-short.json`.
##
## **The press deposits a dab of its own**, which the control hold with the
## airbrush off reads as `previous_dabs` 1. So the drive's 8 and 48 are 7 and 47
## airbrush dabs, and the counts here are the airbrush's alone.
##
## **The two holds did not run at one frame rate**, which is why no single
## fraction explained both and is the observation the filing stopped one step
## short of. Seven airbrush dabs at rate 10 is a run between 75 and 85 frames a
## second, forty-seven at rate 50 is a run between 62.5 and 64, and the rate 10
## hold is the earlier of the two in `scenarios/airbrush-tips.json` and the
## faster of the two here. That is what a capture with more paint on it before
## each later hold does, and this unit's own run measured 88 frames a second for
## the first hold and 97 for the second.
func test_s7s_eight_and_forty_eight_are_the_right_count_for_the_time_they_took() -> void:
    assert_eq(int(_walk(10.0, _even(75.0, 60))[0]), 7, "60 frames at 75 a second is 0.8 s, and rate 10 owes 7")
    assert_eq(int(_walk(50.0, _even(63.0, 60))[0]), 47, "60 frames at 63 a second is 0.952 s, and rate 50 owes 47")
    # The bracket either side, so the pair above is a measurement of the frame
    # rate rather than a number that happens to come out.
    assert_eq(int(_walk(10.0, _even(66.0, 60))[0]), 9, "A slower run at rate 10 owes nine")
    assert_eq(int(_walk(10.0, _even(90.0, 60))[0]), 6, "and a faster one owes six")


## A clock that stutters deposits what an even one does, or the accumulator is
## losing the remainder of every frame it does not fire on.
func test_a_jittery_clock_deposits_what_an_even_one_does() -> void:
    var rng := RandomNumberGenerator.new()
    rng.seed = 0xF76
    var deltas := PackedFloat64Array()
    var seconds := 0.0
    while seconds < 1.0:
        var delta: float = rng.randf_range(0.004, 0.05)
        delta = minf(delta, 1.0 - seconds)
        deltas.append(delta)
        seconds += delta
    var walked := _walk(50.0, deltas)
    assert_almost_eq(float(walked[1]), 1.0, 1e-4, "A measured second of uneven frames")
    assert_eq(int(walked[0]), 50, "deposits the fifty the rate asks for")


## The walk counts the time it walked, which is the number a dump needs beside
## the dab count for anybody to divide one by the other.
func test_the_walk_records_the_interval_it_was_handed() -> void:
    var walked := _walk(50.0, _even(NOMINAL_FPS, 60))
    var brush: RefCounted = walked[2]
    assert_almost_eq(brush.stroke_distance.timed_elapsed, 1000.0, 0.5, "A measured second in milliseconds")
    brush.stroke_distance.dab_sequence = 1
    brush.stroke_distance.reset()
    assert_almost_eq(brush.stroke_distance.previous_timed_elapsed, 1000.0, 0.5, "and it survives the reset the pen lift makes")
    assert_almost_eq(brush.stroke_distance.timed_elapsed, 0.0, 1e-6, "while the live one starts over")


## A distance-only stroke leaves the clock at zero rather than at a plausible
## number, or a reader dividing by it gets an answer to a question nobody asked.
func test_a_stroke_with_no_airbrush_walks_no_clock() -> void:
    var brush := StateBrushScript.new()
    brush.is_drawing = true
    for _frame in 60:
        assert_eq(brush.airbrush_dabs_for_frame(1.0 / NOMINAL_FPS), 0, "Nothing without the airbrush")
    assert_almost_eq(brush.stroke_distance.timed_elapsed, 0.0, 1e-6, "and no clock ran")


## A pen that is up deposits nothing however long it is held, which is the
## control the four assertions above need.
func test_a_pen_that_is_up_deposits_nothing() -> void:
    var brush := StateBrushScript.new()
    brush.settings.airbrush_enabled = true
    brush.settings.airbrush_rate = 50.0
    for _frame in 60:
        assert_eq(brush.airbrush_dabs_for_frame(1.0 / NOMINAL_FPS), 0, "Nothing while the pen is up")


## The frame is a ceiling and not a cap of one, which is what the Rate row's own
## tooltip said until this unit read it. At sixty frames a second a rate of 100,
## which is the top of the slider, deposits a hundred and not sixty.
func test_a_rate_above_the_frame_rate_is_honoured_up_to_the_ceiling() -> void:
    var walked := _walk(100.0, _even(NOMINAL_FPS, 60))
    assert_eq(int(walked[0]), 100, "The top of the slider deposits its hundred")
    var over := _walk(600.0, _even(NOMINAL_FPS, 60))
    assert_eq(
        int(over[0]),
        60 * DabCadence.MAX_DABS_PER_FRAME,
        "and a rate past the ceiling deposits the ceiling, which no slider can ask for"
    )


## The law the four holds on the running app obey, asserted over a grid rather
## than at the four points that happened to be measured.
##
## `scenarios/airbrush-rate-short.json` read 6, 12, 31 and 61 airbrush dabs
## over 678.7, 1223.3, 620.0 and 1230.1 milliseconds at rates 10, 10, 50 and 50,
## and every one is exactly `floor(rate * seconds)`. Its frame rates were 88 and
## 97 a second, neither of them sixty, which is the whole reason the count has to
## be read against the clock beside it.
##
## **The law is asserted as "never a whole dab out" rather than as the floor**,
## because an interval that lands exactly on a boundary is one either way and
## which one depends on the last bit of the sum. Sixty frames of a sixtieth of a
## second add up to a hair under two seconds, so the floor says 19 where the walk
## fires 20 and the walk is the one that is right. A drift, which is what a
## broken rate is, is a whole dab and then two and then ten.
func test_the_count_is_the_floor_of_the_rate_times_the_measured_seconds() -> void:
    for rate: float in [10.0, 20.0, 50.0, 100.0]:
        for fps: float in [58.0, 60.0, 88.0, 97.0]:
            for frames: int in [37, 60, 120]:
                var walked := _walk(rate, _even(fps, frames))
                var seconds: float = walked[1]
                var owed := rate * seconds
                assert_true(
                    absf(float(walked[0]) - owed) < 1.0,
                    "Rate %d over %.4f s at %.0f fps owes %.3f and deposited %d" % [int(rate), seconds, fps, owed, int(walked[0])]
                )
