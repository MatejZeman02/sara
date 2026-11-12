## The time sensor counts from the press.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The stamp brush handed `SaStrokeInfo` the pen's clock as it read, so the time
## sensor counted from when Sara started and not from the press, and a brush
## whose size followed it stood at the end of its curve from the first dab of
## any stroke made after the session's first second. Here the size is the time
## sensor alone, swept once over a second, and two strokes are painted three
## seconds apart into a session five seconds old, every event at the time the
## pen's clock is held at. Each begins at the curve's start, and the two read
## the same times dab for dab. The running app's half is
## `scenarios/the-time-sensor-counts-from-the-press.json`.
##
## The speed smoother is fed the pen's reports at their own times and never the
## time a dab reads, so the measured speeds stand, which
## `harness/scenario/tests/test_what_rate_bursts_do_to_the_speed_sensors.gd`
## holds.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

## One sweep of the sensor, in milliseconds.
const SWEEP_MS: int = 1000
## How far into the session the first press is, and how long after it the
## second comes.
const FIRST_PRESS_USEC: int = 5_000_000
const APART_USEC: int = 3_000_000
## A frame of a sixtieth of a second, the time between two reports.
const FRAME_USEC: int = 16667
## The stroke, inside the first chunk, and its reports: seventy frames, longer
## than the sweep, so its last dabs stand at the curve's end.
const FROM := Vector2(24, 128)
const TO := Vector2(232, 128)
const REPORTS: int = 70
## An 8 px radius on the 256 px canvas.
const RADIUS: float = 8.0 / 256.0

var _surface: SaSurface = null
var _machine: ToolMachine = null
var _was_pinned: bool = false


## The brush's sample, with the time each dab read written down.
class TimeRecorder:
    extends SaStrokeInfo

    var times: Array[float] = []

    func next_dab() -> void:
        super()
        times.append(elapsed_ms)


func before_each() -> void:
    _was_pinned = SaPenClock.is_pinned()
    SaPenClock.unpin()
    _surface = Fixtures.make_surface(Vector2i(256, 256))
    _machine = Fixtures.make_bound_machine(_surface)
    _machine.set_active_tool(&"brush")
    var settings: Resource = _brush().settings
    settings.radius = RADIUS
    settings.stabilizer_mode = 0
    var size: SaCurveOption = settings.size_option
    size.enabled = true
    size.sensors.clear()
    var time := SaSensor.create(SaSensor.Id.TIME, true)
    time.length = SWEEP_MS
    time.periodic = false
    size.set_sensor(time)


func after_each() -> void:
    if _was_pinned:
        # A suite has no frames of its own, so the pin taken here counts from
        # this frame, which is the one the run it interrupted was in.
        SaPenClock.pin_to_frames()
    Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null


func _brush() -> Object:
    return _machine.active_tool


## Two strokes three seconds apart, five seconds into the session, each
## beginning at the curve's start and reaching its end once the sweep is past.
## Counted from Sara's start, both first dabs read 5,000 and 8,000 ms and stood
## at the end of the curve.
func test_two_strokes_a_known_time_apart_begin_at_the_curves_start() -> void:
    var first := _stroke(FIRST_PRESS_USEC)
    var second := _stroke(FIRST_PRESS_USEC + APART_USEC)
    var full := 2.0 * float(_brush()._base_radius())
    for named: String in ["first", "second"]:
        var stroke: Dictionary = first if named == "first" else second
        var times: Array[float] = stroke["times"]
        assert_true(times.size() > REPORTS, "The %s stroke laid its dabs, %d" % [named, times.size()])
        assert_almost_eq(times[0], 0.0, 1e-6, "Its first dab reads the press's time, %.1f ms" % times[0])
        assert_almost_eq(stroke["first"], 0.0, 1e-6, "and is at the curve's start, %.3f px" % stroke["first"])
        assert_true(times[-1] > float(SWEEP_MS), "Its last reads past the sweep, %.1f ms" % times[-1])
        assert_almost_eq(stroke["last"], full, 1e-4, "and is at the curve's end, %.3f px of %.3f" % [stroke["last"], full])
    var a: Array[float] = first["times"]
    var b: Array[float] = second["times"]
    var apart := 0.0
    for i in mini(a.size(), b.size()):
        apart = maxf(apart, absf(a[i] - b[i]))
    assert_eq(b.size(), a.size(), "The two strokes laid as many dabs")
    assert_almost_eq(apart, 0.0, 1e-6, "and read the same times dab for dab, %.9f ms apart at most" % apart)


## On the engine's clock, a painter's, a stroke made after the session's first
## second begins at the curve's start too.
func test_on_the_engines_clock_a_stroke_begins_at_the_curves_start() -> void:
    while Time.get_ticks_msec() <= 2 * SWEEP_MS:
        OS.delay_msec(50)
    var recorder := TimeRecorder.new()
    _brush().stroke_info = recorder
    _brush().is_tablet = false
    _surface.view.mouse_position = FROM
    _button(true)
    _motion(FROM.lerp(TO, 0.5))
    _button(false)
    var full := 2.0 * float(_brush()._base_radius())
    var first: float = _brush().sampled_dabs[0].size
    assert_true(recorder.times.size() > 1, "The stroke laid its dabs, %d" % recorder.times.size())
    assert_true(recorder.times[0] < 0.01 * float(SWEEP_MS), "Its first dab reads %.3f ms after the press" % recorder.times[0])
    assert_true(first < 0.01 * full, "and is at the curve's start, %.3f px of %.3f" % [first, full])


## One stroke from [constant FROM] to [constant TO], pressed at *press_usec*
## and a report every frame after, each event with the pen's clock held at its
## time. A mouse's press, which lays its dab at once rather than waiting for a
## motion's pressure. Answers the times its dabs read and the size of its first
## and last dab.
func _stroke(press_usec: int) -> Dictionary:
    var recorder := TimeRecorder.new()
    _brush().stroke_info = recorder
    _brush().is_tablet = false
    _surface.view.mouse_position = FROM
    SaPenClock.held(press_usec, _button.bind(true))
    for k in range(1, REPORTS + 1):
        var at := FROM.lerp(TO, float(k) / float(REPORTS))
        SaPenClock.held(press_usec + k * FRAME_USEC, _motion.bind(at))
    SaPenClock.held(press_usec + (REPORTS + 1) * FRAME_USEC, _button.bind(false))
    var first: float = _brush().sampled_dabs[0].size
    var last: float = _brush().last_dab.size
    return {"times": recorder.times, "first": first, "last": last}


func _button(pressed: bool) -> void:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    _brush().handle_input(event)


func _motion(at: Vector2) -> void:
    var motion := InputEventMouseMotion.new()
    _surface.view.mouse_position = at
    _brush().handle_input(motion)
