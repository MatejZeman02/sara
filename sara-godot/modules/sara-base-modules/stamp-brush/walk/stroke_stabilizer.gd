## Smooths the pointer before the brush interpolates between its samples.
##
## Two ways to do it, offered as a choice rather than as two branches in the
## brush. A weighted moving average follows the pen's path over the last
## stretch of time and answers its mean, weighted towards the newest, so a
## shaky hand averages out and the stroke follows a little behind. A rope drags
## the brush behind the pointer on a string: the brush moves only when the
## pointer is farther than the rope's length, and then only enough to close the
## gap, which is what makes a slow curve come out clean.
##
## **The average is weighted by time, not by samples.** Counted in
## samples, one amount lagged twice as long on a pen of 88 reports a second as
## on one of 176, and 45 ms on a tablet measured at 88. The pen's path is
## drawn straight between its reports, and the mean is taken over the last
## [method window_ms] with a weight falling from one at the newest moment to
## nought at the window's far end, so a pen at a steady speed is followed
## [method window_ms] over three behind at any rate. The window is as long in
## time as the sample window was at 88 reports a second, so nothing lags more
## than it did there.
##
## **A pen that rests is caught up with.** A pen held still sends nothing, and
## an average that moves only when a sample arrives stood short of the pen
## until it moved again, which a painter saw as the paint stopping at a corner
## and then coming in one burst. So the brush asks [method follow] each frame,
## and once no report has come for [constant REST_GRACE_MS] the average's clock
## runs ahead until its whole window stands on the pen's last place, by
## [constant REST_MS] after the last report. The clock only ever runs forward,
## so the brush never steps back when the pen sets off again.
##
## **The reports a frame delivers are one moment** to [class SaPenClock], so a
## moment's reports are spread evenly over the time since the moment before.
##
## The buffer must be cleared between strokes, or the next stroke starts pulled
## towards the end of the last one.
##
## **A stroke ends where the pen lifted**, as in Krita. Both modes hold the
## brush back from the pointer, so at the release `finish` answers the points
## the brush still owes between the last smoothed point and the last raw
## sample, and the brush walks them before it closes the stroke.
extends RefCounted

enum Mode { OFF, AVERAGE, ROPE }

## Samples the average kept at full strength when it counted samples: two at
## the lightest setting, this many at the strongest. The time window is this
## many reports of a pen at [constant REFERENCE_HZ].
const MAX_WINDOW: int = 24
## The report rate the time window is measured against, the rate of the
## tablet the window was tuned on.
const REFERENCE_HZ: float = 88.0
## How long a pen may send nothing before it counts as resting, longer than
## the gap between two reports of any pen and two frames of a pinned clock.
const REST_GRACE_MS: float = 20.0
## By how long after the last report a resting pen's brush stands on it.
const REST_MS: float = 45.0
## Pixels of rope at the strongest setting, in document space.
const MAX_ROPE: float = 80.0

var mode: int = Mode.OFF
## Nought to one: how long a window, or how long a rope.
var amount: float = 0.5
## Where the brush stands, the last thing [method feed], [method follow] or
## [method finish] answered.
var answer: Vector2 = Vector2.ZERO

## The average's points of the pen's path and the times they stand at on its
## own clock, oldest first.
var _samples: Array[Vector2] = []
var _stamps: PackedFloat64Array = PackedFloat64Array()
## Where the newest moment's reports begin in [member _samples], the time the
## moment before it stands at, and the newest moment itself, on the pen's
## clock and on the average's.
var _moment_from: int = 0
var _before_moment: float = 0.0
var _moment_ms: float = 0.0
var _moment_stamp: float = 0.0
## How far the average's clock runs ahead of the pen's, from catching up
## with a resting pen.
var _ahead_ms: float = 0.0
## When the average was last taken, on its own clock.
var _taken_at: float = 0.0
var _rope_end: Vector2 = Vector2.ZERO
var _has_rope_end: bool = false
var _last_raw: Vector2 = Vector2.ZERO
var _has_raw: bool = false


## Forgets the last stroke.
func reset() -> void:
    _samples.clear()
    _stamps.clear()
    _ahead_ms = 0.0
    _has_rope_end = false
    _has_raw = false


## Forgets the last stroke and smooths the next by *with_mode* at *with_amount*,
## which the brush reads off its settings at every press.
func begin(with_mode: int, with_amount: float) -> void:
    reset()
    mode = with_mode
    amount = with_amount


## How many samples the average keeps at the current amount.
func window() -> int:
    return maxi(2, int(roundf(lerpf(2.0, float(MAX_WINDOW), clampf(amount, 0.0, 1.0)))))


## How far back the average reaches, in milliseconds: the span of
## [method window] reports at [constant REFERENCE_HZ], from the oldest to the
## newest, so a steady pen is followed by a third of it.
func window_ms() -> float:
    return float(window() - 1) * 1000.0 / REFERENCE_HZ


## The rope's length at the current amount.
func rope_length() -> float:
    return lerpf(4.0, MAX_ROPE, clampf(amount, 0.0, 1.0))


## Takes a raw pointer position reported at *at_ms* on [class SaPenClock] and
## answers where the brush should go. With no time, the report comes one
## report of [constant REFERENCE_HZ] after the last, as a suite feeds it.
func feed(raw: Vector2, at_ms: float = NAN) -> Vector2:
    if is_nan(at_ms):
        at_ms = _moment_ms + 1000.0 / REFERENCE_HZ if _has_raw else 0.0
    _last_raw = raw
    _has_raw = true
    match mode:
        Mode.AVERAGE:
            _add(raw, at_ms)
            answer = _mean_at(_moment_stamp)
        Mode.ROPE:
            answer = _rope(raw)
        _:
            answer = raw
    return answer


## One frame's look at a pen that sent nothing, at *now_ms* on
## [class SaPenClock], and whether the brush moved towards the pen's last place,
## to [member answer]. Only the average moves, once the pen has rested
## [constant REST_GRACE_MS], and it stands on the pen by [constant REST_MS].
func follow(now_ms: float) -> bool:
    if mode != Mode.AVERAGE or _samples.is_empty():
        return false
    var rest := now_ms - _moment_ms
    if rest <= REST_GRACE_MS:
        return false
    var span := window_ms()
    var at := _moment_stamp + rest
    if span > REST_GRACE_MS:
        var caught := REST_GRACE_MS + (rest - REST_GRACE_MS) * (span - REST_GRACE_MS) / (REST_MS - REST_GRACE_MS)
        var ahead := _moment_stamp + minf(caught, span)
        _ahead_ms += maxf(0.0, ahead - at)
        at = maxf(at, ahead)
    var was := answer
    answer = _samples[-1] if at >= _moment_stamp + span else _mean_at(at)
    return answer != was


## The points the brush still owes at the release, in order, the last of them
## exactly the last raw sample. Nothing with the stabiliser off, before any
## sample, or when the brush already stands on the pen.
##
## The average's clock is run on to where its window holds nothing but the
## last raw sample, in [method window] steps, so the line eases into the
## release point. The rope has nothing to ease, and its tail is the straight
## run from the rope's end to the pen.
func finish() -> Array[Vector2]:
    var tail: Array[Vector2] = []
    if mode == Mode.OFF or not _has_raw or answer == _last_raw:
        return tail
    if mode == Mode.AVERAGE:
        var from := _taken_at
        var to := _moment_stamp + window_ms()
        var steps := window()
        for step in range(1, steps):
            var eased := _mean_at(lerpf(from, to, float(step) / float(steps)))
            if tail.is_empty() or tail[-1] != eased:
                tail.append(eased)
    # The weighted mean of equal samples can miss them by a rounding, and the
    # stroke must end on the pen, so the last point is the raw one itself.
    if not tail.is_empty() and tail[-1].is_equal_approx(_last_raw):
        tail[-1] = _last_raw
    else:
        tail.append(_last_raw)
    _rope_end = _last_raw
    answer = _last_raw
    return tail


## Puts *raw* on the path at *at_ms*. A report of a later moment starts a
## moment of its own, and one of the moment in hand joins it, which spreads
## the moment's reports evenly over the time since the moment before.
func _add(raw: Vector2, at_ms: float) -> void:
    if _samples.is_empty() or at_ms > _moment_ms:
        _before_moment = _moment_stamp if not _samples.is_empty() else at_ms - 1000.0 / REFERENCE_HZ
        _moment_from = _samples.size()
        _moment_ms = at_ms
        _moment_stamp = at_ms + _ahead_ms
        _samples.append(raw)
        _stamps.append(_moment_stamp)
        return
    _samples.append(raw)
    _stamps.append(_moment_stamp)
    var count := _samples.size() - _moment_from
    for i in count:
        _stamps[_moment_from + i] = lerpf(_before_moment, _moment_stamp, float(i + 1) / float(count))


## The mean of the path over the window that ends at *at* on the average's
## clock, each moment weighted by how near it is to *at*: one at *at*, nought
## a window before. Before its first point the path stands on that point and
## after its last on the last. Every piece of it is a straight run times a
## straight weight, so Simpson's rule is exact on it.
func _mean_at(at: float) -> Vector2:
    var span := window_ms()
    var start := at - span
    # A point whose next one is already out of the window is never read again.
    while _samples.size() > 1 and _stamps[1] <= start and _moment_from > 0:
        _samples.remove_at(0)
        _stamps.remove_at(0)
        _moment_from -= 1
    _taken_at = at
    # One point is the whole path, and the integral would only round it.
    if _samples.size() == 1:
        return _samples[0]
    var total := Vector2.ZERO
    if start < _stamps[0]:
        total += _piece(_samples[0], _stamps[0], _samples[0], _stamps[0], start, minf(at, _stamps[0]), start, span)
    for i in _samples.size() - 1:
        total += _piece(
            _samples[i],
            _stamps[i],
            _samples[i + 1],
            _stamps[i + 1],
            maxf(start, _stamps[i]),
            minf(at, _stamps[i + 1]),
            start,
            span
        )
    if at > _stamps[-1]:
        total += _piece(_samples[-1], _stamps[-1], _samples[-1], _stamps[-1], maxf(start, _stamps[-1]), at, start, span)
    # The weights over the whole window add up to half its length.
    return total / (span * 0.5)


## The weighted integral of the straight run from *a* at *ta* to *b* at *tb*,
## from *lo* to *hi*, the weight rising from nought at *start* by one a *span*.
static func _piece(a: Vector2, ta: float, b: Vector2, tb: float, lo: float, hi: float, start: float, span: float) -> Vector2:
    if hi <= lo:
        return Vector2.ZERO
    var place := func(t: float) -> Vector2: return a if tb <= ta else a.lerp(b, clampf((t - ta) / (tb - ta), 0.0, 1.0))
    var mid := (lo + hi) * 0.5
    var sum: Vector2 = place.call(lo) * (lo - start) + 4.0 * place.call(mid) * (mid - start) + place.call(hi) * (hi - start)
    return sum * (hi - lo) / (6.0 * span)


## The brush follows only when the pointer pulls the rope taut, and then only
## as far as the rope allows, so it never overshoots and never oscillates.
func _rope(raw: Vector2) -> Vector2:
    if not _has_rope_end:
        _rope_end = raw
        _has_rope_end = true
        return raw
    var length := rope_length()
    var to_pointer := raw - _rope_end
    var distance := to_pointer.length()
    if distance > length:
        _rope_end += to_pointer.normalized() * (distance - length)
    return _rope_end
