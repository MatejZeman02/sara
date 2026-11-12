## The ring's lead moves with the hand and not on its own.
##
## With both the system and Sara's cursor on, the brush circle must not jump or
## wiggle against the system's smooth one. That is two claims that need
## separate readings.
##
## **The wiggle is the velocity, not the drawing.** The pointer's position is
## written by the device and read by the frame loop, and 125 hertz into 60 does
## not divide: some frames see one device step and some see three, so the
## difference of the last two readings alternates by a third of itself while the
## hand is perfectly steady. What that puts on screen is a lead that breathes,
## against a system pointer the compositor draws on the truth. The readings are
## below, and they are what chose [constant SaCursorPrediction.WINDOW_SECONDS].
##
## **The jump is the threshold.** A lead that switched on at
## [constant SaCursorPrediction.REST_SPEED] rather than fading in would move the
## ring, for a hand drifting across that speed, by the whole lead that speed earns
## while the hand moved a fraction of it. Half a pixel at one refresh interval,
## which is small, and a pixel at the 32 milliseconds `cursor_prediction_ms`
## will take, which is not, and either way it is a step in the one place the
## ring is meant to be sitting still.
##
## The step is not the 64 pixel cap snapping off: the cap is 3840 pixels a
## second away at one refresh interval and no hand goes there.
extends "res://tests/test_framework.gd"

## The frame rate every reading here is taken at, in hertz.
const FPS: float = 60.0

## The device rate that beats worst against [constant FPS], in hertz. A common
## mouse, and the case the fit was chosen on.
const DEVICE_HZ: float = 125.0

## A stroke a hand actually makes, in logical pixels a second.
const STROKE_SPEED: float = 900.0

## What the lead may breathe by over a steady sweep, in logical pixels.
##
## The difference of the last two readings leaves 2.51 at
## [constant STROKE_SPEED], measured on the low pass this replaced. The fit
## leaves 1.54, so two pixels sits between them and fails either way round.
const RIPPLE_ALLOWED: float = 2.0

## What the lead may move by between two frames of a steady sweep, in logical
## pixels.
##
## The note's own word is "jumps", and this is the reading of it: not how far the
## lead wanders over a second but how far it moves in one frame, which is what
## the eye catches against a system pointer drawn on the truth. The low pass
## leaves 2.51 at [constant STROKE_SPEED], a window average would leave 1.20, and
## the fit leaves 0.77.
const JUMP_ALLOWED: float = 1.0

var _saved_ms: float = 0.0


func before_each() -> void:
    _saved_ms = SaSettings.cursor_prediction_ms


func after_each() -> void:
    SaSettings.cursor_prediction_ms = _saved_ms


## A predictor fed the readings a frame loop would take of a pointer crossing at
## *pixels_per_second*, with the position quantised to *device_hz* the way the
## real one is.
##
## This is the whole fixture: Wayland will not let a capture move the pointer,
## so the only place the beat between the two rates can be reproduced is here.
func _frame_loop(pixels_per_second: float, device_hz: float, frames: int) -> Array[Vector2]:
    var prediction := SaCursorPrediction.new()
    var seconds := SaCursorPrediction.latency_seconds()
    var leads: Array[Vector2] = []
    for i in frames:
        var at := float(i + 1) / FPS
        # The device wrote the position at its own last tick, not at this frame.
        var written := floorf(at * device_hz) / device_hz
        prediction.sample(Vector2(pixels_per_second * written, 400.0), int(at * 1_000_000.0))
        leads.append(prediction.lead(seconds))
    return leads


## The largest the lead moves between two frames of *leads*, ignoring the first
## ones while the window fills.
func _largest_jump(leads: Array[Vector2]) -> float:
    var worst := 0.0
    for i in range(21, leads.size()):
        worst = maxf(worst, absf(leads[i].length() - leads[i - 1].length()))
    return worst


## The spread of the lead's length over *leads*, ignoring the first ones while
## the window fills.
func _ripple(leads: Array[Vector2]) -> float:
    var low := INF
    var high := -INF
    for i in range(20, leads.size()):
        var length := leads[i].length()
        low = minf(low, length)
        high = maxf(high, length)
    return high - low


## A steady hand gets a steady lead.
func test_a_steady_sweep_does_not_breathe() -> void:
    SaSettings.cursor_prediction_ms = SaCursorPrediction.FOLLOW_DISPLAY
    var leads := _frame_loop(STROKE_SPEED, DEVICE_HZ, 90)

    var mean := 0.0
    for i in range(20, leads.size()):
        mean += leads[i].length()
    mean /= float(leads.size() - 20)
    var expected := STROKE_SPEED * SaCursorPrediction.latency_seconds()
    assert_almost_eq(mean, expected, 0.2, "The lead is the speed times the latency: %.2f" % mean)

    var ripple := _ripple(leads)
    assert_true(ripple <= RIPPLE_ALLOWED, "and a hand at one speed does not make it breathe: %.2f px of spread" % ripple)

    # A jump is measured per frame rather than per second.
    var jump := _largest_jump(leads)
    assert_true(jump <= JUMP_ALLOWED, "and it does not jump between two frames: %.2f px" % jump)


## A device that beats less badly against the frame rate breathes less, which is
## how the reading is known to be the beat rather than the arithmetic.
func test_a_faster_device_leaves_less_of_it() -> void:
    SaSettings.cursor_prediction_ms = SaCursorPrediction.FOLLOW_DISPLAY
    var slow := _ripple(_frame_loop(STROKE_SPEED, DEVICE_HZ, 90))
    var fast := _ripple(_frame_loop(STROKE_SPEED, 1000.0, 90))

    assert_true(fast < slow, "A thousand hertz beats less than 125: %.2f against %.2f" % [fast, slow])
    assert_true(fast < 0.2, "and what is left of it is nothing a painter sees: %.2f px" % fast)

    # The same at the speed a fast stroke reaches, where the beat is twice the
    # size and so is anything left of it.
    var quick := _largest_jump(_frame_loop(1800.0, DEVICE_HZ, 90))
    assert_true(quick <= 2.0 * JUMP_ALLOWED, "Twice the speed is at most twice the jump: %.2f px" % quick)


## `predicted` walked across the rest threshold never steps
## further than the hand steps in one frame.
##
## The hand's own step at a speed is that speed over the frame rate, so this is
## the strongest form of "the ring moves with the hand": whatever the speed, the
## ring's answer to a change in it is smaller than the hand's own motion.
func test_crossing_the_rest_threshold_never_steps_further_than_the_hand() -> void:
    for milliseconds: float in [8.0, 1000.0 / 60.0, 32.0]:
        SaSettings.cursor_prediction_ms = milliseconds
        var seconds := SaCursorPrediction.latency_seconds()
        var at := Vector2(700.0, 400.0)
        var previous := at
        var worst := 0.0
        var worst_speed := 0.0
        # A pixel a second at a time, from well under the threshold to well over
        # the speed the fade is finished at.
        for step in range(0, 200):
            var pixels_per_second := float(step)
            var prediction := _swept(pixels_per_second)
            var here := prediction.predicted(at, seconds)
            var moved := here.distance_to(previous)
            if step > 0 and moved > worst:
                worst = moved
                worst_speed = pixels_per_second
            previous = here
        var one_frame := worst_speed / FPS
        assert_true(
            worst <= one_frame + 0.001,
            (
                "At %.1f ms the worst step across the threshold is %.3f px at %.0f px/s, against %.3f px of hand"
                % [milliseconds, worst, worst_speed, one_frame]
            )
        )


## Below the rest speed the ring is on the pointer exactly, and the fade is over
## by the speed a hand has clearly decided to move at.
func test_the_fade_runs_from_rest_to_a_deliberate_move() -> void:
    assert_eq(SaCursorPrediction.lead_fraction(0.0), 0.0, "A still pointer leads by none of it")
    assert_eq(
        SaCursorPrediction.lead_fraction(SaCursorPrediction.REST_SPEED),
        0.0,
        "and the threshold itself is still none of it, which is what makes it continuous"
    )
    assert_eq(
        SaCursorPrediction.lead_fraction(SaCursorPrediction.GLIDE_SPEED),
        1.0,
        "Two pixels a frame is a hand that has decided, and leads by all of it"
    )
    assert_almost_eq(SaCursorPrediction.lead_fraction(75.0), 0.5, 0.001, "and the middle is half")

    var previous := -1.0
    for step in range(0, 200):
        var fraction := SaCursorPrediction.lead_fraction(float(step))
        assert_true(fraction >= previous, "The fade never falls back at %d px/s" % step)
        previous = fraction


## A hand crossing the threshold is not a hand that has stopped, and the ring
## still arrives exactly on a pointer that has.
func test_a_pointer_that_stops_ends_on_the_pointer() -> void:
    SaSettings.cursor_prediction_ms = SaCursorPrediction.FOLLOW_DISPLAY
    var prediction := SaCursorPrediction.new()
    var at := Vector2(500.0, 400.0)
    for i in 20:
        prediction.sample(at, i * 16_667)

    var seconds := SaCursorPrediction.latency_seconds()
    assert_eq(prediction.lead(seconds), Vector2.ZERO, "A pointer that has stopped leads by nothing")
    assert_eq(prediction.predicted(at, seconds), at, "so the ring is drawn on it exactly")


## A predictor holding a steady *pixels_per_second* along x, fed at the frame
## rate for long enough to fill the window.
func _swept(pixels_per_second: float) -> SaCursorPrediction:
    var prediction := SaCursorPrediction.new()
    for i in 20:
        var at := float(i) / FPS
        prediction.sample(Vector2(pixels_per_second * at, 400.0), int(at * 1_000_000.0))
    return prediction
