## The noise brush's first points, kept until the stroke's samples say how fast
## the pen moved off the press, so they are laid at that speed and not at
## nought.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **Why the press waits for a speed.** A stroke's first sample has no pair to
## measure a speed between, so it reads nought, and every option a Speed sensor
## drives would answer the press as a pen at rest. Thick Impasto's Thickness
## falls from one at rest to a half at the brush's fast speed, so a press
## answered at nought lays more height than the body beside it, and the kernel,
## which draws the thickness as a slope between two points, lights the first
## segment as a flat dark rectangle one point step long. The first segment is
## drawn only once its second point exists, so the press is answered again then
## at the speed that point reads, which costs no latency.
##
## **The first speed the smoother measures, not the second sample's.** The
## smoother answers nought until its walk has passed five pixels, so at four
## pixels a sample the second sample reads nought as well and the press would
## keep its step, and under a tip a few pixels wide the points of those five
## pixels all read nought and the step would move to the point after them. So
## every point laid before the first speed measured takes it, the press and
## those points alike.
## The stretch holds them until the update that sends them, which a round tip's
## held path puts a radius on and a tip that is not round a second point on,
## and a point already sent keeps what it was sent with.
##
## **It replays the samples, it does not set a speed.** The speed is the
## smoother's own, in [SaStrokeInfo], and nothing outside it writes one. So this
## keeps every sample the stroke fed the smoother until it measured a speed,
## and the stroke info it replays them through is a fresh one fed those same
## samples and then each point in turn, which reads exactly the speed the
## stroke's own reads there and everything else the point read. A pen that
## rests on its press before it moves writes onto the press only when it
## presses harder, as the stretch does.
extends RefCounted

## Every point the stroke laid before the smoother measured a speed, oldest
## first: where, how hard, its tilt and twist in degrees, when in milliseconds
## from the press, and how far the drift had slid the field there. A point at
## rest on the press that pressed no harder than the press is kept as well,
## since it counted a dab, but not [member _laid], since it wrote nothing.
var _at := PackedVector2Array()
var _pressure := PackedFloat32Array()
var _tilt := PackedVector2Array()
var _twist := PackedFloat64Array()
var _time := PackedFloat64Array()
var _slide := PackedFloat64Array()
var _laid: Array[bool] = []
## The hardest the pen pressed while it rested on the press.
var _hardest: float = -1.0
## Whether the smoother has measured a speed, once a stroke.
var _measured: bool = false


## Hears one point the stroke laid through *info*, at *at* with *pressure*,
## *tilt*, *twist* and *time_ms*, the drift having slid the field *slide* there,
## and answers whether it is the first the smoother measured a speed at, the
## speed the points before it take now.
func heard(at: Vector2, pressure: float, tilt: Vector2, twist: float, time_ms: float, slide: float, info: SaStrokeInfo) -> bool:
    if _measured:
        return false
    _measured = info.drawing_speed() > 0.0
    _at.append(at)
    _time.append(time_ms)
    if _measured:
        return true
    var resting := info.total_length == 0.0
    _laid.append(not resting or pressure > _hardest)
    if resting:
        _hardest = maxf(_hardest, pressure)
    _pressure.append(pressure)
    _tilt.append(tilt)
    _twist.append(twist)
    _slide.append(slide)
    return false


## Answers every point laid before the speed again, oldest first, at the first
## speed the smoother measured, for a stroke drawn with *stroke_seed* through a tip
## *tip_diameter* wide: *each* is called with the stroke info a point reads,
## its dab counted as it was, and the drift's slide there, for every point that
## wrote anything. *slide* is how far the drift has slid the field at the point
## that measured the speed, and what it slid over the step to that point is the
## Drift row's share at that speed, so every step before it is slid by that
## share as well, the Drift option being one a Speed sensor drives. Answers the
## slide at the point that measured the speed, which a step of nought leaves as
## it was.
func replay(stroke_seed: int, tip_diameter: float, slide: float, each: Callable) -> float:
    var last := _laid.size() - 1
    var step := _at[last + 1].distance_to(_at[last])
    var share := 0.0 if step == 0.0 else (slide - _slide[last]) / step
    var info := SaStrokeInfo.new()
    info.begin(_at[0], stroke_seed)
    info.tip_diameter = tip_diameter
    for i in _at.size():
        info.feed_report(_at[i], _time[i])
    var slid := _slide[0]
    for i in _laid.size():
        if i > 0 and step > 0.0:
            slid += _at[i].distance_to(_at[i - 1]) * share
        info.feed_dab(_at[i], _pressure[i], _tilt[i], _twist[i], _time[i])
        info.next_dab()
        if _laid[i]:
            each.call(info, slid if step > 0.0 else _slide[i])
    return slid + step * share if step > 0.0 else slide
