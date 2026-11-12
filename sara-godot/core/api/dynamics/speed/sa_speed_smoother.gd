## The speed smoother: how fast the hand is moving, from the pen's reports.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A port, and the one this folder keeps: `_feed_speed`, `_add_time_diff` and
## `_filtered_mean` are a specific piece of engineering rather than an idea, and
## **their copyright line is in [`PROVENANCE.md`](../PROVENANCE.md)**, the
## dynamics package's page, one folder up. What Sara added around the port,
## the moments a frame's reports are held in and spread over, is written below
## from what it does.
##
## **The distances are real and the times are estimated**, which is the whole
## trick of the smoother and the reason it is worth a port at all. A tablet's
## event timestamps are not a clock: they arrive late, in bursts, and sometimes
## stalled behind a busy frame, so a speed computed from them jumps where the
## hand did not. What is reliable is that the device samples at a roughly steady
## rate, so the time between two samples is better estimated from the recent
## history of intervals than read off the events, and the rate that comes out is
## steady enough for a curve to be drawn against.
##
## A folder of its own rather than the bottom of the stroke's sample, the class
## that extends it, so that `core/api/dynamics` stays under the line budget a
## folder read whole is held to.
class_name SaSpeedSmoother
extends RefCounted

## The smoother's five numbers. How many per-sample distances it keeps, the two
## conditions its backwards walk has to pass before it stops, and the rolling
## mean's window with the fraction of it that survives the trim.
const SPEED_HISTORY: int = 512
const SPEED_SAMPLES: int = 3
const SPEED_MIN_DISTANCE: float = 5.0
const MEAN_WINDOW: int = 200
const MEAN_KEPT: float = 0.8

## The smoother's own state. `_distances` holds a (distance, time) pair per
## sample, newest last, and `_last_point` is where the last sample it was fed
## lay, which is not the dab's last position once it is fed by report.
var _distances: Array[Vector2] = []
var _time_diffs: Array[float] = []
var _time_sum: float = 0.0
var _last_time: float = 0.0
var _last_speed: float = 0.0
var _last_point: Vector2 = Vector2.ZERO
var _has_last_point: bool = false

## The way each report of the newest moment came, first to last, which the
## smoother holds as one sample until the next moment begins, see
## [method _feed_speed], the moment's interval, and whether it was measured as
## it opened, before a moment of several reports was seen.
var _moment: PackedFloat32Array = PackedFloat32Array()
var _moment_span: float = 0.0
var _measured_open: bool = false


## One pen report into the speed smoother, at the time the report was made.
##
## **Once a report, not once a dab.** The smoother estimates the interval
## between two samples from the device's steady rate, and the dabs a brush walks
## between two reports are no device's samples: a stamp brush that fed it at
## each dab read one time for every dab of a frame, its trimmed mean dropped the
## frame's one long interval, and a pen at 1.5 px/ms in a burst of reports read
## 10.7, `scenarios/what-rate-bursts-do-to-the-speed-sensors-is-measured.json`
## under a load. Fed here once a report, the same burst reads the pen.
func feed_report(at: Vector2, time_ms: float) -> void:
    _feed_speed(at, time_ms)


## Every sample forgotten, for a stroke pressed at *at*.
func _begin_speed(at: Vector2) -> void:
    _distances.clear()
    _time_diffs.clear()
    _time_sum = 0.0
    _last_time = 0.0
    _last_speed = 0.0
    _last_point = at
    _has_last_point = false
    _moment.clear()
    _moment_span = 0.0
    _measured_open = false


## The speed smoother, formula for formula. **The port this file keeps.**
##
## The walk is backwards over the samples and stops once it has passed both
## `SPEED_SAMPLES` samples and `SPEED_MIN_DISTANCE` pixels, so a slow hand
## measures over a longer window than a fast one and neither reads as noise. The
## time it accumulates is the rolling mean of the intervals rather than the
## intervals themselves, for the reason in this file's header.
##
## Why it stays a port: the shape above is not the only answer to "how fast is
## the hand moving", it is one tuned answer, and the five constants are tuned
## with it. Any rewrite that reads as a derivation would land on different
## numbers, and every brush whose size or opacity follows speed would move with
## them.
##
## **The reports of one moment are spread over it once it is whole.** The app's
## reports carry no time, and the several a frame delivers reach the brush
## microseconds apart, so the trimmed mean kept the frame's one long interval or
## none of it, and read as they arrived a pen at 1.5 px/ms under a load read
## anywhere from 0.18 to 11.3 px/ms,
## `scenarios/a-burst-of-pen-reports-reads-the-speed-the-pen-moved-at.json`.
## [method SaPenClock.report_ms] reads them all at the frame's time, and here
## they are held as one sample, the frame's way over the frame's interval, until
## the next moment begins. Then each becomes a sample of its own at an even
## share of the interval, as a pen's steady rate made them, so the mean is the
## pen's interval however unevenly the frames fell. Held as one, the four
## samples the walk takes were four frames counted at their mean, and the pen
## read 1.33 to 1.51. The first report of a moment holds only part of its way,
## so after a moment of several reports the next is left out of the walk until
## it too is whole, a frame late. The first such moment, measured as it opened,
## is measured again as each report joins it. A report with a time of its own
## is a sample as the port has it.
func _feed_speed(at: Vector2, time_ms: float) -> void:
    if not _has_last_point:
        _has_last_point = true
        _last_point = at
        _last_time = time_ms
        _last_speed = 0.0
        return
    if time_ms == _last_time:
        _join_moment(at)
        return

    var distance := at.distance_to(_last_point)
    _last_point = at
    var whole := _moment.size() > 1
    if whole:
        _spread_moment()
    _moment = PackedFloat32Array([distance])
    _moment_span = time_ms - _last_time
    _add_time_diff(_moment_span)
    var average := _filtered_mean()
    _last_time = time_ms

    _distances.append(Vector2(distance, time_ms))
    if _distances.size() > SPEED_HISTORY:
        _distances.remove_at(0)
    _measured_open = not whole
    if _measured_open:
        _measure_speed(average)


## A report at the moment of the one before it: its way joins that moment's
## sample. One at the press's moment, before any sample, leaves its way to the
## next moment's, which is measured from the press.
func _join_moment(at: Vector2) -> void:
    if _moment.is_empty():
        return
    var way := at.distance_to(_last_point)
    _last_point = at
    _moment.append(way)
    var newest := _distances[_distances.size() - 1]
    newest.x += way
    _distances[_distances.size() - 1] = newest
    if _measured_open:
        _measure_speed(_filtered_mean())


## Puts a whole moment's reports in place of the one sample it was held as,
## each at an even share of its interval, and measures them.
func _spread_moment() -> void:
    _distances.remove_at(_distances.size() - 1)
    if not _time_diffs.is_empty():
        _time_sum -= _time_diffs[_time_diffs.size() - 1]
        _time_diffs.remove_at(_time_diffs.size() - 1)
    var share := _moment_span / float(_moment.size())
    for i in _moment.size():
        _add_time_diff(share)
        _distances.append(Vector2(_moment[i], _last_time - _moment_span + share * float(i + 1)))
    while _distances.size() > SPEED_HISTORY:
        _distances.remove_at(0)
    _measure_speed(_filtered_mean())


## The port's walk over the samples as they stand, each counted at *average*,
## the trimmed mean of their intervals.
func _measure_speed(average: float) -> void:
    var total_distance := 0.0
    var total_time := 0.0
    var searched := 0
    for i in range(_distances.size() - 1, -1, -1):
        searched += 1
        total_distance += _distances[i].x
        total_time += average
        if searched > SPEED_SAMPLES and total_distance > SPEED_MIN_DISTANCE:
            break

    if total_time > 0.0 and total_distance > SPEED_MIN_DISTANCE:
        _last_speed = total_distance / total_time


func _add_time_diff(value: float) -> void:
    _time_diffs.append(value)
    _time_sum += value
    if _time_diffs.size() > MEAN_WINDOW:
        _time_sum -= _time_diffs[0]
        _time_diffs.remove_at(0)


## The window's mean with the extremes at both ends dropped, half the discard
## taken off each end. The trimming is what stops one stalled event from
## halving the measured rate.
func _filtered_mean() -> float:
    var count := _time_diffs.size()
    if count == 0:
        return 0.0
    var useful := maxi(1, roundi(MEAN_KEPT * float(count)))
    var cut_total := count - useful
    if cut_total <= 0:
        return _time_sum / float(count)
    var sorted := _time_diffs.duplicate()
    sorted.sort()
    var cut_min := roundi(0.5 * float(cut_total))
    var cut_max := cut_total - cut_min
    var sum := _time_sum
    for i in range(cut_min):
        sum -= sorted[i]
    for i in range(cut_max):
        sum -= sorted[count - 1 - i]
    return sum / float(useful)
