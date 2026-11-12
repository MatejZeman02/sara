## The fewest control points that draw a pressure curve `pow(x, exponent)`
## on the Brush Editor's graph, which is what a pen switch writes.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **A default curve carries as few handles as it can.** The power at nine even
## pressures draws nine handles on a gentle bend, and a painter who wants to
## change the bend has to drag seven of them out of the way first. One to three
## points draw the same curve closely enough to paint with.
##
## **Measured on the graph's own curve.** A candidate's points go through
## `SaMonotoneCurve.sample`, the monotone cubic the editor draws and the sensor
## reads, and the gap is read against the power at [constant SAMPLES] even
## pressures. A straight line between the points would grade a curve no painter
## ever sees.
##
## **Two points, then three, then the even nine.** Two are the diagonal, and
## they are kept when the line stays inside both bounds, which is the exponent
## one. Three are the two ends and one bend point, placed by a search over the
## graph where the largest gap across the range is smallest, among the bend
## points that keep the pressures in [constant GRADED] within
## [constant GRADED_GAP]. The two ends stay at x 0 and x 1, because the editor
## pins them there and a first point further in would be moved by the first
## drag. When no bend point meets the bounds the curve is the power at
## `fallback_count` even pressures.
##
## **Why the quarters are held apart.** With its ends pinned and its end slopes
## the graph's own, one bend point cannot follow `pow(x, 4.8)`, the Size
## switch's curve, everywhere at once. The bend that keeps the largest gap
## smallest misses the half press by nearly as much again, so the brush would
## paint visibly lighter or thinner at the one press a painter leans on. The
## quarter, the half and the three quarters are where a pressure curve is read,
## so those three are held to [constant GRADED_GAP] and the rest of the range is
## fitted as close as that leaves room for, worst near a press of 0.9 where the
## curve climbs fastest. Opacity's gentle `pow(x, 1.2)` fits everywhere.
class_name SaPressureCurveFit
extends RefCounted

## How many even pressures a candidate is read at, the ends included. A power of
## two plus one so the quarters fall on samples.
const SAMPLES: int = 65

## The pressures held to [constant GRADED_GAP], the three a curve is read at.
const GRADED: Array[float] = [0.25, 0.5, 0.75]

## How far the curve may stand from the power at [constant GRADED]. Two
## hundredths, where a difference in the dab starts to show, less a margin for
## the sensor's table, which reads the spline between neighbours of its own and
## not the spline itself.
const GRADED_GAP: float = 0.015

## The largest gap anywhere across the range a short curve may keep, a tenth of
## the graph. Past it the old even curve is written instead.
const LARGEST_GAP: float = 0.1

## How many cells the first pass lays across each axis of the graph.
const FIRST_GRID: int = 32

## How many times the search halves its step around the best bend so far.
const REFINEMENTS: int = 8

## Fits already made, by exponent, because a fit is about a thousand samples of
## the spline and the switch asks for the same two exponents over and over.
static var _made: Dictionary[float, PackedVector2Array] = {}


## The curve for `pow(x, exponent)`, the fewest points that draw it inside the
## bounds, or *fallback_count* even points when three cannot.
static func of_power(exponent: float, fallback_count: int) -> PackedVector2Array:
    if not _made.has(exponent):
        _made[exponent] = _fitted(exponent, fallback_count)
    return _made[exponent].duplicate()


## The largest gap between the graph's curve through *points* and the power,
## at [constant SAMPLES] even pressures. Public because the suite reads it.
static func largest_gap(points: PackedVector2Array, exponent: float) -> float:
    var drawn := SaMonotoneCurve.sample(points, SAMPLES)
    var worst := 0.0
    for i in range(SAMPLES):
        var x := float(i) / float(SAMPLES - 1)
        worst = maxf(worst, absf(drawn[i] - pow(x, exponent)))
    return worst


static func _fitted(exponent: float, fallback_count: int) -> PackedVector2Array:
    var line := PackedVector2Array([Vector2.ZERO, Vector2.ONE])
    if _score(line, exponent) <= LARGEST_GAP:
        return line
    var bend := _best_bend(exponent)
    var three := _through(bend)
    if _score(three, exponent) <= LARGEST_GAP:
        return three
    return _even(exponent, fallback_count)


## The bend point with the lowest [method _score], a grid over the graph first
## and then a shrinking neighbourhood around the best cell.
static func _best_bend(exponent: float) -> Vector2:
    var best := Vector2(0.5, 0.5)
    var best_score := INF
    for i in range(1, FIRST_GRID):
        for j in range(FIRST_GRID + 1):
            var at := Vector2(float(i), float(j)) / float(FIRST_GRID)
            var score := _score(_through(at), exponent)
            if score < best_score:
                best = at
                best_score = score
    var step := 1.0 / float(FIRST_GRID)
    var margin := 1.0 / 256.0
    for _round in range(REFINEMENTS):
        step *= 0.5
        var centre := best
        for di in range(-2, 3):
            for dj in range(-2, 3):
                var at := Vector2(clampf(centre.x + di * step, margin, 1.0 - margin), clampf(centre.y + dj * step, 0.0, 1.0))
                var score := _score(_through(at), exponent)
                if score < best_score:
                    best = at
                    best_score = score
    return best


## The largest gap across the range when the graded pressures are inside
## [constant GRADED_GAP], and one plus their gap when they are not, so a curve
## that misses the quarters always loses to one that holds them.
static func _score(points: PackedVector2Array, exponent: float) -> float:
    var drawn := SaMonotoneCurve.sample(points, SAMPLES)
    var graded := 0.0
    for pressure: float in GRADED:
        var i := roundi(pressure * float(SAMPLES - 1))
        graded = maxf(graded, absf(drawn[i] - pow(pressure, exponent)))
    if graded > GRADED_GAP:
        return 1.0 + graded
    var worst := 0.0
    for i in range(SAMPLES):
        var x := float(i) / float(SAMPLES - 1)
        worst = maxf(worst, absf(drawn[i] - pow(x, exponent)))
    return worst


static func _through(bend: Vector2) -> PackedVector2Array:
    return PackedVector2Array([Vector2.ZERO, bend, Vector2.ONE])


static func _even(exponent: float, count: int) -> PackedVector2Array:
    var points := PackedVector2Array()
    for i in range(count):
        var x := float(i) / float(count - 1)
        points.append(Vector2(x, pow(x, exponent)))
    return points
