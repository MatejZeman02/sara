## The ring leads the pointer by its velocity times the presentation latency.
##
## The input queue is one frame deep and no motion events are dropped.
## What is left is the frame the compositor holds, which no amount of pacing
## removes, and prediction is what pays for it.
##
## The arithmetic is the point, so it is asserted here rather than
## photographed: `scenarios/predict-the-last-frame.json` runs the same claim
## on the app through the `ring_predict` step, because Wayland will not let a
## capture move the pointer and a lead is a difference between two points a
## screenshot cannot tell apart.
extends "res://tests/test_framework.gd"

## A tenth of a pixel a second, which is finer than anything here turns on.
const SPEED_EPSILON: float = 0.1

var _saved_ms: float = 0.0


func before_each() -> void:
    _saved_ms = SaSettings.cursor_prediction_ms


func after_each() -> void:
    SaSettings.cursor_prediction_ms = _saved_ms


## A predictor fed *samples* readings along the line from *from* to *to* over
## *seconds*, which is a pointer travelling at a known speed.
func _swept(from: Vector2, to: Vector2, seconds: float, samples: int = 24) -> SaCursorPrediction:
    var prediction := SaCursorPrediction.new()
    var step_usec := int(seconds / float(samples - 1) * 1_000_000.0)
    for i in samples:
        prediction.sample(from.lerp(to, float(i) / float(samples - 1)), step_usec * i)
    return prediction


## The speed a straight sweep reports is the speed it was swept at. The fit over
## a window reads a straight line back exactly, so the tolerance here is slack
## the file does not use.
func test_a_straight_sweep_reads_back_the_speed_it_was_swept_at() -> void:
    var prediction := _swept(Vector2(100, 300), Vector2(1300, 300), 1.0)

    assert_almost_eq(prediction.speed(), 1200.0, 1.0, "1200 pixels in a second reads as 1200 a second")
    assert_almost_eq(prediction.velocity.y, 0.0, SPEED_EPSILON, "and a horizontal sweep has no vertical velocity")
    assert_true(prediction.is_moving(), "which is moving")


## The claim itself: the lead is the speed times the latency, along the
## direction of travel.
func test_the_lead_is_the_speed_times_the_latency() -> void:
    var prediction := _swept(Vector2(100, 300), Vector2(700, 300), 1.0)
    assert_almost_eq(prediction.speed(), 600.0, 1.0, "600 pixels a second")

    var lead := prediction.lead(0.016)
    assert_almost_eq(lead.x, 600.0 * 0.016, 0.05, "leads by speed times latency")
    assert_almost_eq(lead.y, 0.0, 0.001, "along the way it is going and no other way")

    var at := Vector2(700, 300)
    assert_almost_eq(prediction.predicted(at, 0.016).x, at.x + lead.x, 0.001, "and the drawn point is the pointer plus it")

    # Twice the latency, twice the lead, which is what makes the number in the
    # settings file mean anything.
    assert_almost_eq(prediction.lead(0.032).x, lead.x * 2.0, 0.05, "Twice the latency leads twice as far")


## A still pointer draws the ring on the pointer exactly, which is the half of
## the claim a jittering ring would fail.
func test_a_still_pointer_leads_by_nothing() -> void:
    var prediction := SaCursorPrediction.new()
    for i in 20:
        prediction.sample(Vector2(400, 400), i * 16_000)

    assert_almost_eq(prediction.speed(), 0.0, SPEED_EPSILON, "A pointer that has not moved has no speed")
    assert_false(prediction.is_moving(), "so it is not moving")
    assert_eq(prediction.lead(0.016), Vector2.ZERO, "and the lead is nothing")
    assert_eq(prediction.predicted(Vector2(400, 400), 0.016), Vector2(400, 400), "so the ring is on the pointer exactly")


## A hand resting on a tablet produces samples a pixel apart, and multiplying
## that noise by a latency puts the ring where the pointer is not, on a still
## screen where it shows most. Below the rest speed the lead is exactly nothing,
## and the fade in above it is what makes the edge of that continuous.
func test_a_hand_at_rest_is_below_the_threshold() -> void:
    var prediction := SaCursorPrediction.new()
    var jitter := [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0), Vector2(0, -1)]
    for i in 40:
        prediction.sample(Vector2(400, 400) + jitter[i % jitter.size()], i * 16_000)

    assert_true(prediction.speed() < SaCursorPrediction.REST_SPEED, "A pixel a frame is rest, not travel")
    assert_eq(prediction.lead(0.016), Vector2.ZERO, "so nothing leads")


## A warp, a window move or a scenario stepping the pointer across the canvas
## is not a hand. The lead is capped, so the worst case is a ring a few tens of
## pixels ahead rather than one off the screen.
func test_a_teleport_is_capped_rather_than_followed() -> void:
    var prediction := SaCursorPrediction.new()
    prediction.sample(Vector2(0, 0), 0)
    prediction.sample(Vector2(4000, 0), 1_000)

    var lead := prediction.lead(0.016)
    assert_almost_eq(lead.length(), SaCursorPrediction.MAX_LEAD, 0.001, "The lead stops at the cap")
    assert_true(lead.x > 0.0, "in the direction it was going")


## A pointer that left the window and came back has no velocity worth carrying
## across the gap, or it leads towards where it was going when it left.
func test_a_gap_starts_a_new_gesture() -> void:
    var prediction := _swept(Vector2(100, 300), Vector2(700, 300), 0.2)
    assert_true(prediction.is_moving(), "It was moving")

    prediction.sample(Vector2(700, 300), 10_000_000)

    assert_almost_eq(prediction.speed(), 0.0, SPEED_EPSILON, "and a long gap drops the velocity rather than decaying it")
    assert_eq(prediction.lead(0.016), Vector2.ZERO, "so nothing leads out of the gap")


## Two samples in one tick divide by nothing, which is a pointer read twice in
## a frame.
func test_two_samples_in_one_tick_are_ignored() -> void:
    var prediction := SaCursorPrediction.new()
    prediction.sample(Vector2(0, 0), 1_000)
    prediction.sample(Vector2(50, 0), 1_000)

    assert_eq(prediction.velocity, Vector2.ZERO, "No interval, no velocity")


## The latency is the settings file's when it holds a number, one refresh
## interval when it holds `FOLLOW_DISPLAY`, and nothing at zero.
func test_the_latency_comes_from_the_settings_and_falls_back_to_the_display() -> void:
    SaSettings.cursor_prediction_ms = 8.0
    assert_almost_eq(SaCursorPrediction.latency_seconds(), 0.008, 1e-6, "A written number is milliseconds")

    SaSettings.cursor_prediction_ms = 0.0
    assert_almost_eq(SaCursorPrediction.latency_seconds(), 0.0, 1e-6, "Zero turns prediction off")

    SaSettings.cursor_prediction_ms = SaCursorPrediction.FOLLOW_DISPLAY
    var hz := SaCursorPrediction.refresh_hz()
    assert_true(hz > 1.0, "The refresh rate is a rate, headless or not: %s" % hz)
    assert_almost_eq(SaCursorPrediction.latency_seconds(), 1.0 / hz, 1e-6, "and the default is one refresh interval")


## Turning it off draws the ring on the pointer, whatever the hand is doing,
## which is what the settings key is for.
func test_zero_milliseconds_draws_on_the_pointer() -> void:
    var prediction := _swept(Vector2(100, 300), Vector2(1300, 300), 1.0)
    assert_true(prediction.is_moving(), "A fast sweep is moving")

    assert_eq(prediction.lead(0.0), Vector2.ZERO, "and no latency is no lead")
