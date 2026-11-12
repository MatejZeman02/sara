## Turning three hand sweeps into one pressure correction.
##
## The painter scratches three coated blocks, each in one sweep from the dot at
## one end to the far end, pressing what feels to their hand like an even ramp
## from nothing to full. The dialog records the pen's raw pressure against
## **where the pen is along the block**, from 0 at the dot to 1 at the far end,
## and never against time, so a quick hand and a slow one are read alike.
##
## The correction is the x the hand meant. If a sweep meant to be even came
## out as `raw = x * x`, the hand reported a quarter halfway along, so the brush
## must read a quarter as half: the table is `sqrt`. [method correction_of]
## does that for the dialog and adds what a bare inverse lacks, a cut of the
## lift, room above the sweep's peak and a floor under its first reading.
## [method fit] is the bare inverse, which the harness pen reads widths through.
##
## A sibling of `sa_tablet.gd` rather than part of it, so the maths can be read
## and tested without the recorder and the clamps around it.
class_name SaTabletSweep
extends RefCounted

## Entries in a correction table, matching the curve editor's lookup so the
## Tablet page can hand one to the other.
const SAMPLES: int = 256

## How many sweeps the dialog asks for. Three, because one is a fluke and two
## cannot outvote each other.
const SWEEP_COUNT: int = 3

## The shortest run along its own x a shape worth a bare [method fit] spans. A
## tap is not a ramp, and four readings over a sliver would make a correction
## out of noise.
const MIN_DURATION: float = 0.35

## The fewest readings a sweep must carry.
const MIN_READINGS: int = 8

## The fewest readings a scratched sweep must carry. Fewer than
## [constant MIN_READINGS], because a flick across a block in a tenth of a
## second is a dozen events on a pen that streams every 8 ms, and the dialog
## refuses such a sweep for what its readings say rather than for how few they
## are.
const MIN_SWEEP_READINGS: int = 5

## A reading within this share of the sweep's peak is still the peak. The last
## such reading is where the lift starts, and everything after it is the pen
## coming off the block rather than the hand pressing.
const LIFT_SHARE: float = 0.98

## The corrected pressure a sweep's peak is given. Under one, so a painter who
## sweeps lightly paints as they swept and can still press harder for more.
const SWEEP_PEAK: float = 0.8

## The corrected pressure the softest touch-down is given, rising to it from
## nought below the first reading a sweep made. Sweeps measured on a tablet landed at
## raw 0.044 to 0.217, and 0.05 is the lowest of those rounded, so the lightest
## landing any of them made paints about what it would have painted uncorrected.
const FLOOR: float = 0.05

## Where along the block a sweep may land at the latest and still count. Past
## the middle it began at the far end.
const LATEST_START: float = 0.5

## How much of the block a sweep must cover, from where it landed to the
## furthest it reached.
const LEAST_COVER: float = 0.9

## How far along the block the peak must come at the earliest. Measured quick
## sweeps peaked at 0.52 to 0.66 and lifted while still moving, and slow ones
## at 0.90 to 0.96.
const EARLIEST_PEAK: float = 0.8

## Why a scratched sweep is not counted, or [constant Refusal.NONE].
enum Refusal {
    ## It counts.
    NONE,
    ## Too few readings to say anything, which a tap is.
    TOO_FEW,
    ## It began at the far end of the block rather than at the dot.
    FAR_END,
    ## It covered less than [constant LEAST_COVER] of the block.
    SHORT,
    ## Its peak came before [constant EARLIEST_PEAK] of the block.
    EARLY_PEAK,
}


## Whether *sweep*, as `Vector2(x, raw pressure)` in reading order, is long
## enough and full enough for a bare [method fit].
static func is_usable(sweep: PackedVector2Array) -> bool:
    if sweep.size() < MIN_READINGS:
        return false
    if sweep[sweep.size() - 1].x - sweep[0].x < MIN_DURATION:
        return false
    return _peak_of(sweep) > 0.0


## Why the scratched *sweep*, as `Vector2(along the block, raw pressure)` in
## the order the pen reported them, is not counted, or [constant Refusal.NONE].
static func refusal_of(sweep: PackedVector2Array) -> Refusal:
    if sweep.size() < MIN_SWEEP_READINGS or _peak_of(sweep) <= 0.0:
        return Refusal.TOO_FEW
    var landed := sweep[0].x
    if landed > LATEST_START:
        return Refusal.FAR_END
    var furthest := landed
    var peak := 0.0
    var peak_at := landed
    for point in sweep:
        furthest = maxf(furthest, point.x)
        if point.y > peak:
            peak = point.y
            peak_at = point.x
    if furthest - landed < LEAST_COVER:
        return Refusal.SHORT
    if peak_at < EARLIEST_PEAK:
        return Refusal.EARLY_PEAK
    return Refusal.NONE


## The index of the last reading of *sweep* within [constant LIFT_SHARE] of its
## peak, which is where the lift begins.
static func lift_index(sweep: PackedVector2Array) -> int:
    var near := _peak_of(sweep) * LIFT_SHARE
    for i in range(sweep.size() - 1, -1, -1):
        if sweep[i].y >= near:
            return i
    return sweep.size() - 1


## *sweep* with the lift cut off and what is left stretched along the block to
## fill 0 to 1, from where the pen landed to the last reading of the peak.
##
## The first reading is kept, being where the pen lands. A pen that slips back
## a little along the block is held where it had got to, so the positions never
## fall, which is what lets [method resample] read them as an axis.
static func clean(sweep: PackedVector2Array) -> PackedVector2Array:
    var out := PackedVector2Array()
    if sweep.is_empty():
        return out
    var last := lift_index(sweep)
    var start := sweep[0].x
    var reached := start
    for i in range(last + 1):
        reached = maxf(reached, sweep[i].x)
    var span := reached - start
    var along := start
    for i in range(last + 1):
        along = maxf(along, sweep[i].x)
        var stretched := 0.0 if span <= 0.0 else (along - start) / span
        out.append(Vector2(stretched, maxf(sweep[i].y, 0.0)))
    return out


## The correction table for the scratched *sweeps*, indexed by raw pressure
## from 0 to 1, or an empty array when none of them counts.
##
## Each counted sweep is cleaned, made non-decreasing and inverted, so it says
## for each raw pressure the x along the block where the hand reported it, and
## the three x are averaged. That x runs from [constant FLOOR] at the softest
## first reading to [constant SWEEP_PEAK] at the hardest peak. Under the first
## reading the table rises evenly from nought to the floor, and over the peak
## it rises evenly to one at the peak over [constant SWEEP_PEAK], full past it.
static func correction_of(sweeps: Array, count: int = SAMPLES) -> PackedFloat32Array:
    var size := maxi(count, 2)
    var meant := PackedFloat32Array()
    meant.resize(size)
    var first := INF
    var peak := 0.0
    var used := 0
    for sweep: PackedVector2Array in sweeps:
        if refusal_of(sweep) != Refusal.NONE:
            continue
        var shape := monotone(resample(clean(sweep), SAMPLES))
        first = minf(first, shape[0])
        peak = maxf(peak, shape[shape.size() - 1])
        var inverse := invert(shape, size)
        for i in range(size):
            meant[i] += inverse[i]
        used += 1
    if used == 0 or peak <= 0.0:
        return PackedFloat32Array()
    var ceiling := peak / SWEEP_PEAK
    var table := PackedFloat32Array()
    table.resize(size)
    for i in range(size):
        var raw := float(i) / float(size - 1)
        if raw <= first:
            table[i] = 0.0 if first <= 0.0 else FLOOR * raw / first
        elif raw <= peak:
            table[i] = lerpf(FLOOR, SWEEP_PEAK, meant[i] / float(used))
        elif raw < ceiling:
            table[i] = lerpf(SWEEP_PEAK, 1.0, (raw - peak) / (ceiling - peak))
        else:
            table[i] = 1.0
    return table


## One sweep resampled onto *count* points evenly spaced over its own x, which
## is what lets three sweeps of different lengths be averaged. The x must not
## fall from one reading to the next.
static func resample(sweep: PackedVector2Array, count: int = SAMPLES) -> PackedFloat32Array:
    var out := PackedFloat32Array()
    out.resize(maxi(count, 2))
    if sweep.is_empty():
        return out
    var start := sweep[0].x
    var span := sweep[sweep.size() - 1].x - start
    if span <= 0.0:
        for i in range(out.size()):
            out[i] = sweep[sweep.size() - 1].y
        return out

    var reading := 0
    for i in range(out.size()):
        var at := start + span * float(i) / float(out.size() - 1)
        while reading < sweep.size() - 2 and sweep[reading + 1].x < at:
            reading += 1
        var left := sweep[reading]
        var right := sweep[reading + 1]
        var run := right.x - left.x
        out[i] = left.y if run <= 0.0 else lerpf(left.y, right.y, clampf((at - left.x) / run, 0.0, 1.0))
    return out


## The mean of the usable sweeps, each normalised to its own x first, so a long
## one and a short one count the same.
static func mean_of(sweeps: Array, count: int = SAMPLES) -> PackedFloat32Array:
    var total := PackedFloat32Array()
    total.resize(maxi(count, 2))
    var used := 0
    for sweep: PackedVector2Array in sweeps:
        if not is_usable(sweep):
            continue
        var resampled := resample(sweep, total.size())
        for i in range(total.size()):
            total[i] += resampled[i]
        used += 1
    if used == 0:
        return PackedFloat32Array()
    for i in range(total.size()):
        total[i] /= float(used)
    return total


## The bare inverse of *sweeps*, indexed by the reading from 0 to 1, or an
## empty array when no sweep was usable. No lift is cut and no room or floor is
## added, which is what the harness pen wants of its widths and the dialog does
## not, so the dialog reads [method correction_of].
##
## Empty rather than an identity, so a caller can tell "the painter has not
## calibrated" from "the painter calibrated and it came out flat".
static func fit(sweeps: Array, count: int = SAMPLES) -> PackedFloat32Array:
    var mean := mean_of(sweeps, count)
    if mean.is_empty():
        return PackedFloat32Array()
    return invert(monotone(mean), count)


## *shape* made non-decreasing by carrying its running maximum forward.
##
## A hand wobbles, and a sweep that dips is not a function that can be
## inverted: two efforts would map to one pressure and the table would fold
## back on itself. Carrying the maximum keeps the shape the hand made and
## flattens only the dips.
static func monotone(shape: PackedFloat32Array) -> PackedFloat32Array:
    var out := shape.duplicate()
    for i in range(1, out.size()):
        out[i] = maxf(out[i], out[i - 1])
    return out


## The inverse of *shape*, as a table of *count* entries indexed by the raw
## pressure the pen reports.
##
## Below the softest reading the hand ever made there is nothing to invert, so
## the table starts at zero, and above the hardest it is already full effort,
## so it ends at one. That is what makes a pen whose top third is never
## reached usable: everything above the top of the sweep is full pressure.
static func invert(shape: PackedFloat32Array, count: int = SAMPLES) -> PackedFloat32Array:
    var table := PackedFloat32Array()
    table.resize(maxi(count, 2))
    if shape.size() < 2:
        for i in range(table.size()):
            table[i] = float(i) / float(table.size() - 1)
        return table

    var reading := 0
    for i in range(table.size()):
        var wanted := float(i) / float(table.size() - 1)
        if wanted <= shape[0]:
            table[i] = 0.0
            continue
        if wanted >= shape[shape.size() - 1]:
            table[i] = 1.0
            continue
        while reading < shape.size() - 2 and shape[reading + 1] < wanted:
            reading += 1
        var run := shape[reading + 1] - shape[reading]
        var within := 0.0 if run <= 0.0 else clampf((wanted - shape[reading]) / run, 0.0, 1.0)
        table[i] = (float(reading) + within) / float(shape.size() - 1)
    return table


## The identity table, which is what an uncalibrated pen and a Reset both mean.
static func identity(count: int = SAMPLES) -> PackedFloat32Array:
    var table := PackedFloat32Array()
    table.resize(maxi(count, 2))
    for i in range(table.size()):
        table[i] = float(i) / float(table.size() - 1)
    return table


## Whether *table* is the identity within a thousandth, which is what says a
## stored curve is doing nothing and can be left out of the input path.
static func is_identity(table: PackedFloat32Array) -> bool:
    if table.size() < 2:
        return true
    for i in range(table.size()):
        if absf(table[i] - float(i) / float(table.size() - 1)) > 1e-3:
            return false
    return true


static func _peak_of(sweep: PackedVector2Array) -> float:
    var peak := 0.0
    for point in sweep:
        peak = maxf(peak, point.y)
    return peak
