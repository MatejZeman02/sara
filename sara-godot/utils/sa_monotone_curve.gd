## The monotone cubic a curve editor draws, sampled evenly into the lookup
## whatever reads the curve walks.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **Out of `SaCurveEditor` and into `utils`**, because a
## sensor's response is the same curve and the sensor moved into the door,
## `core/api/dynamics`. `core` never names a class under `ui`, so the maths the
## widget and the sensor share lives below both of them, and the widget's
## `sample_curve` hands its call on here, so no caller of it changed. The
## functions moved as they were, comments and all.
##
## The curve is a monotone cubic through the points (Fritsch and Carlson), not
## a Catmull-Rom. A Catmull-Rom overshoots between two points that are close in
## x and far apart in y, which on a tone curve means a shadow that gets darker
## as the painter drags the point up, and a lookup that is not a function of
## input any more.
class_name SaMonotoneCurve
extends RefCounted


## The monotone cubic through *control*, sampled evenly. Static so the maths
## can be checked without a control in a tree.
static func sample(control: PackedVector2Array, count: int) -> PackedFloat32Array:
    var out := PackedFloat32Array()
    out.resize(maxi(count, 2))
    var n := control.size()
    if n < 2:
        for i in range(out.size()):
            out[i] = float(i) / float(out.size() - 1)
        return out

    var tangents := _tangents(control)
    var segment := 0
    for i in range(out.size()):
        var x := float(i) / float(out.size() - 1)
        while segment < n - 2 and x > control[segment + 1].x:
            segment += 1
        out[i] = clampf(_hermite(control, tangents, segment, x), 0.0, 1.0)
    return out


## The slope at each point, limited so the curve cannot rise between two
## points that both fall. This is the Fritsch-Carlson step, and it is the whole
## reason this is not a Catmull-Rom.
static func _tangents(control: PackedVector2Array) -> PackedFloat32Array:
    var n := control.size()
    var slopes := PackedFloat32Array()
    slopes.resize(maxi(n - 1, 1))
    for i in range(n - 1):
        var run := control[i + 1].x - control[i].x
        slopes[i] = (control[i + 1].y - control[i].y) / run if run > 1e-6 else 0.0

    var tangents := PackedFloat32Array()
    tangents.resize(n)
    tangents[0] = slopes[0]
    tangents[n - 1] = slopes[n - 2]
    for i in range(1, n - 1):
        tangents[i] = 0.0 if slopes[i - 1] * slopes[i] <= 0.0 else (slopes[i - 1] + slopes[i]) * 0.5

    for i in range(n - 1):
        if is_zero_approx(slopes[i]):
            tangents[i] = 0.0
            tangents[i + 1] = 0.0
            continue
        var a := tangents[i] / slopes[i]
        var b := tangents[i + 1] / slopes[i]
        var length := sqrt(a * a + b * b)
        if length > 3.0:
            tangents[i] = 3.0 / length * a * slopes[i]
            tangents[i + 1] = 3.0 / length * b * slopes[i]
    return tangents


static func _hermite(control: PackedVector2Array, tangents: PackedFloat32Array, segment: int, x: float) -> float:
    var left := control[segment]
    var right := control[segment + 1]
    var run := right.x - left.x
    if run <= 1e-6:
        return right.y
    var t := clampf((x - left.x) / run, 0.0, 1.0)
    var t2 := t * t
    var t3 := t2 * t
    return (
        (2.0 * t3 - 3.0 * t2 + 1.0) * left.y
        + (t3 - 2.0 * t2 + t) * run * tangents[segment]
        + (-2.0 * t3 + 3.0 * t2) * right.y
        + (t3 - t2) * run * tangents[segment + 1]
    )
