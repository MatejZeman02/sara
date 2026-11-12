## The reports one frame delivers read the pen that made them.
##
## Godot's events carry no time, and a pen reporting 240 times a second into
## frames slowed to 38 ms hands the brush nine or ten reports at once. Read as
## they arrived, microseconds apart, a pen at 1.5 px/ms read anywhere from 0.18
## to 11.3 px/ms in
## `scenarios/a-burst-of-pen-reports-reads-the-speed-the-pen-moved-at.json`.
## The clock reads one frame's reports as one moment, and the speed smoother
## takes one moment's reports as one sample, measured once it is whole.
extends "res://tests/test_framework.gd"

## The pen's speed in px/ms, and its reports' interval in ms.
const PEN: float = 1.5
const REPORT_MS: float = 1000.0 / 240.0

## Frames as a loaded machine lays them, in ms, uneven, taken in turn.
const FRAMES_MS: Array[float] = [38.4, 52.0, 55.0, 41.0, 47.5, 60.0, 39.0]

var _was_pinned: bool = false


func before_each() -> void:
    _was_pinned = SaPenClock.is_pinned()
    SaPenClock.unpin()


func after_each() -> void:
    SaPenClock.unpin()
    if _was_pinned:
        SaPenClock.pin_to_frames()


## On the engine's clock every report of one frame reads the time the first
## read, however long the brush took over the ones between.
func test_on_the_engines_clock_one_frames_reports_read_one_moment() -> void:
    var first := SaPenClock.report_ms()
    OS.delay_usec(3000)
    assert_eq(SaPenClock.report_ms(), first, "Three milliseconds later in the same frame a report reads the frame's moment")
    assert_true(SaPenClock.now_ms() - first >= 3.0, "while the clock itself has moved on")


## A report that brings its own time, held, reads that time.
func test_a_held_report_reads_its_own_time() -> void:
    var read := {}
    SaPenClock.held(5_000_000, func() -> void: read["ms"] = SaPenClock.report_ms())
    assert_almost_eq(float(read["ms"]), 5000.0, 1e-6, "A report held at five seconds reads five seconds")


## Nine to fourteen reports a frame in frames of uneven length, each frame's at
## the frame's moment, read the pen within a twentieth at every report from the
## second frame on, including the reports that open a frame with only a part of
## its way in. Held as one sample a frame, four frames counted at their mean,
## they read 1.33 to 1.51 under the scenario's load.
func test_a_frames_reports_at_one_moment_read_the_pen() -> void:
    var info := SaStrokeInfo.new()
    info.begin(Vector2.ZERO)
    info.feed_report(Vector2.ZERO, 0.0)
    var speeds: Array[float] = []
    var report := 1
    var moment := 0.0
    for frame in range(1, 30):
        moment += FRAMES_MS[frame % FRAMES_MS.size()]
        while float(report) * REPORT_MS <= moment:
            info.feed_report(Vector2(float(report) * REPORT_MS * PEN, 0.0), moment)
            if frame > 1:
                speeds.append(info._last_speed)
            report += 1
    assert_true(speeds.size() > 200, "The pen sent its reports, %d" % speeds.size())
    var reads := "From the second frame the reports read %.3f to %.3f px/ms" % [speeds.min(), speeds.max()]
    assert_almost_eq(speeds.min(), PEN, PEN * 0.05, reads)
    assert_almost_eq(speeds.max(), PEN, PEN * 0.05, reads)


## Reports at the press's own moment have no sample to join, and their way is
## the next moment's, measured from the press, so a frame that holds the press
## and the first reports reads the pen as well.
func test_reports_at_the_presss_moment_count_from_the_press() -> void:
    var info := SaStrokeInfo.new()
    info.begin(Vector2.ZERO)
    info.feed_report(Vector2.ZERO, 0.0)
    info.feed_report(Vector2(10.0, 0.0), 0.0)
    info.feed_report(Vector2(20.0, 0.0), 0.0)
    info.feed_report(Vector2(40.0, 0.0), 20.0)
    assert_almost_eq(info._distances[0].x, 40.0, 1e-6, "The first sample is the whole way from the press")
    assert_almost_eq(info._last_speed, 2.0, 1e-6, "and reads 40 px over 20 ms")


## A report with a time of its own is a sample as the port has it, measured the
## moment it comes, so a pen whose reports are timed reads its speed at the
## first of them.
func test_a_timed_report_is_measured_as_it_comes() -> void:
    var info := SaStrokeInfo.new()
    info.begin(Vector2.ZERO)
    info.feed_report(Vector2.ZERO, 0.0)
    info.feed_report(Vector2(REPORT_MS * PEN, 0.0), REPORT_MS)
    assert_almost_eq(info._last_speed, PEN, 1e-4, "The first timed report reads the pen")
    for report in range(2, 40):
        info.feed_report(Vector2(float(report) * REPORT_MS * PEN, 0.0), float(report) * REPORT_MS)
    assert_almost_eq(info._last_speed, PEN, 1e-4, "and so does the fortieth")
