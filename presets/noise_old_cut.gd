## The cut a noise preset was stored under while Strength was the cut, carried
## to the shift Strength is now that the pressure is the cut, and read back.
## The settings' `migrate`, `carry_cut` and `old_cut` answer through it.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **The old cut and the new one, and what carries.** Under the old cut the
## texel the tip covers painted where its field value v stood at or above the
## Strength row S times the Strength curve f at the pressure p, and under the
## new one it paints where the new value plus the shift s stands at or below
## p. The new value is one less the old for a Bristle's streak and an
## inverted picture, so the two paint the same texels at every pressure when s(p) is p - 1 + S f(p). A grain is read
## the same way round as before, so it carries how much of the stroke paints
## at each pressure, its values spread evenly about a half, while the specks
## that paint are the ones that did not. Under the old default, S at one and f
## the falling line, s is nought, the new default exactly.
##
## **Strength and a curve, as near as a curve allows.** The shift is the
## Strength row times the curve option's answer, which is nought to one, so the
## row becomes the shift of largest size over the pressures and the curve the
## shift over it at [constant MIGRATED_CURVE_POINTS] pressures, cut at nought
## where the shift would change its sign, so the pressures on the other side of
## that point paint as the new cut does rather than as the old one did. Exact
## for every S under the falling line, the old default, and for any curve whose
## shift keeps one sign.
extends RefCounted

## How many points along the pressure a stored Strength curve is read at, the
## stamp's own number for a migrated curve.
const MIGRATED_CURVE_POINTS: int = 9
## How far past a bend where a carried curve turns flat it gains a point of
## its own, as a share of the pressure's range, [method _shift_curve]'s reason.
const BEND_REACH: float = 0.02


## A Strength row and its curve option, what an old cut carries to.
class Shift:
    var strength: float = 0.0
    var option: SaCurveOption = null


## The Strength row and curve option that paint the old cut *old_strength*
## times *old_option*.
static func carry(old_strength: float, old_option: SaCurveOption) -> Shift:
    var count := MIGRATED_CURVE_POINTS
    var falls := _pressure_factors(old_option, count)
    var shifts := PackedFloat32Array()
    var largest := 0.0
    for i in count:
        var pressure := float(i) / float(count - 1)
        var shift := pressure - 1.0 + old_strength * falls[i]
        shifts.append(shift)
        # A tie goes to the firmer pressure, where a mouse paints.
        if absf(shift) >= absf(largest):
            largest = shift
    var option := SaCurveOption.new()
    option.use_curve = true
    if old_option != null:
        option = old_option.duplicate(true)
    option.strength = 1.0
    option.strength_min = 0.0
    option.strength_max = 1.0
    option.sensors.erase(int(SaSensor.Id.PRESSURE))
    if absf(largest) > 0.0001:
        var curve := _shift_curve(shifts, largest)
        var pressure_sensor := SaSensor.create(SaSensor.Id.PRESSURE, true)
        pressure_sensor.curve = curve
        option.set_sensor(pressure_sensor)
        option.common_curve = curve.duplicate()
    option.enabled = not option.active_sensors().is_empty()
    var out := Shift.new()
    out.strength = clampf(largest, -1.0, 1.0)
    out.option = option
    return out


## The old cut that paints what *strength* and its curve *option* paint now,
## the inverse of [method carry]: an option on the pressure alone whose
## strength is the largest the cut 1 - p + s(p) reaches, held in nought to one,
## and whose curve is the cut over it.
static func read_back(strength: float, option: SaCurveOption) -> SaCurveOption:
    var count := MIGRATED_CURVE_POINTS
    var factors := _pressure_factors(option, count)
    var cuts := PackedFloat32Array()
    var largest := 0.0
    for i in count:
        var shift := clampf(strength * factors[i], -1.0, 1.0)
        var cut := clampf(1.0 - float(i) / float(count - 1) + shift, 0.0, 1.0)
        cuts.append(cut)
        largest = maxf(largest, cut)
    var out := SaCurveOption.new()
    out.use_curve = true
    out.strength = largest
    if largest > 0.0001:
        var curve := _shift_curve(cuts, largest)
        var pressure := SaSensor.create(SaSensor.Id.PRESSURE, true)
        pressure.curve = curve
        out.set_sensor(pressure)
        out.common_curve = curve.duplicate()
    out.enabled = true
    return out


## What *option* answers at *count* pressures from nought to one, the
## pressure's curve alone times the option's constant and in its bounds, the
## old cut's curve and the shift's alike. One at every pressure while the
## option is off or reads no pressure.
static func _pressure_factors(option: SaCurveOption, count: int) -> PackedFloat32Array:
    var out := PackedFloat32Array()
    out.resize(count)
    out.fill(1.0)
    if option == null or not option.enabled:
        return out
    var constant := clampf(option.strength, option.strength_min, option.strength_max)
    var pressure := option.sensor_for(SaSensor.Id.PRESSURE)
    if not option.use_curve or pressure == null or not pressure.active:
        out.fill(constant)
        return out
    var curve := option.common_curve if option.use_same_curve else pressure.curve
    var sampled := SaMonotoneCurve.sample(curve, count)
    for i in count:
        out[i] = clampf(option.strength * sampled[i], option.strength_min, option.strength_max)
    return out


## The curve the shift *shifts*, read at evenly spaced pressures, follows as a
## share of *largest*: nought to one, with a point where it crosses nought.
##
## **A line comes back as its two ends, and a flat bend gains a point beside
## it.** A point inside a straight run is dropped. Where the curve turns flat
## or back, the monotone cubic `SaSensor` reads it through lays its tangent
## flat, which bends the span beside it off the line by a seventh of its rise
## at most, the whole run from Canvas Scumble's bend to a full press. A point
## [constant BEND_REACH] past the bend on each side that rises holds that to
## one short span, a three hundredth of the share for that line.
static func _shift_curve(shifts: PackedFloat32Array, largest: float) -> PackedVector2Array:
    var last := shifts.size() - 1
    var points := PackedVector2Array()
    for i in shifts.size():
        var at := float(i) / float(last)
        var share := shifts[i] / largest
        if i > 0:
            var before := shifts[i - 1] / largest
            if (before < 0.0) != (share < 0.0):
                var crossing := (float(i - 1) + before / (before - share)) / float(last)
                if crossing - points[points.size() - 1].x > 0.000001 and at - crossing > 0.000001:
                    points.append(Vector2(crossing, 0.0))
        points.append(Vector2(at, clampf(share, 0.0, 1.0)))
    var kept := PackedVector2Array([points[0]])
    for i in range(1, points.size() - 1):
        var before := points[i - 1]
        var after := points[i + 1]
        var on_line := lerpf(before.y, after.y, (points[i].x - before.x) / (after.x - before.x))
        if absf(points[i].y - on_line) > 0.0001:
            kept.append(points[i])
    kept.append(points[points.size() - 1])
    var slopes := PackedFloat32Array()
    for i in kept.size() - 1:
        slopes.append((kept[i + 1].y - kept[i].y) / (kept[i + 1].x - kept[i].x))
    var out := PackedVector2Array([kept[0]])
    for i in range(1, kept.size()):
        var from := kept[i - 1]
        var to := kept[i]
        var rises := absf(slopes[i - 1]) > 0.0001
        var room := to.x - from.x > 2.0 * BEND_REACH
        if rises and room and i > 1 and slopes[i - 2] * slopes[i - 1] <= 0.0:
            out.append(from.lerp(to, BEND_REACH / (to.x - from.x)))
        if rises and room and i < kept.size() - 1 and slopes[i - 1] * slopes[i] <= 0.0:
            out.append(to.lerp(from, BEND_REACH / (to.x - from.x)))
        out.append(to)
    return out
