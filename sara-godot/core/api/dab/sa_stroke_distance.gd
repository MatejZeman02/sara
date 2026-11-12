## How far along a stroke the next dab goes, and how much of the walk is left
## over.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **An accumulator rather than one step size per segment.** Dividing the
## travelled distance by one step size and painting that many dabs is right
## while the step never changes and wrong the moment it does, which is every
## stroke with size by pressure on: the whole segment would be walked at the
## step the *end* of it asks for, so a stroke that thickens under pressure drops
## dabs at its thin end and a stroke that thins bunches them. The accumulator
## carries the remainder, offers one dab at a time and is
## told the spacing that produced each, so the step can change between any two
## dabs of one segment.
##
## **The remainder is a `Vector2` and not a length.** A flat tip owes a longer
## step along its length than across it, and a walk that carries one scalar has
## thrown away which of the two the leftover belongs to: it bunches the dabs
## along one axis and gaps them along the other. Carrying both components, in
## the tip's own frame, is what makes the two spacings mean anything.
class_name SaStrokeDistance
extends RefCounted

## The floor on a distance spacing, in pixels. Half a pixel is the point at
## which a stroke asks for more than two dabs per texel it crosses, and every
## one of them costs a dispatch, so below this the brush is a hang rather than a
## stroke and the painter sees the same solid line either way.
const MIN_DISTANCE_SPACING: float = 0.5

## The bounds on a timed interval, in milliseconds. The floor matches
## [constant MIN_DISTANCE_SPACING]'s reasoning in the other unit: two thousand
## dabs a second is a hang. The ceiling is an hour, which is not a slow airbrush
## but an airbrush that is off, and naming it as a bound rather than as a
## special case keeps the clock arithmetic free of a zero-rate branch.
const MIN_TIMED_INTERVAL: float = 0.5
const MAX_TIMED_INTERVAL: float = 60.0 * 60.0 * 1000.0

## Below this the spacing ellipse is treated as axis-aligned and the segment is
## not rotated into its frame. Two thousandths of a radian is a ninth of a
## degree, at which a segment the length of the longest sensible step moves by
## well under a thousandth of a pixel, so the rotation buys nothing and the two
## trigonometric calls it costs are per dab.
const ROTATION_EPSILON: float = 2e-3

## The floor on a fan's step, in degrees. A right-angled corner at this step
## already asks for eighty-nine extra dabs at one point, each of them a
## dispatch, which is [constant MIN_DISTANCE_SPACING]'s reasoning in the other
## unit: below it the brush is a hang rather than a fan, and a painter cannot
## see the difference between eighty-nine dabs and nine hundred.
const MIN_FAN_STEP_DEGREES: float = 1.0

## The ceiling on how many dabs one corner may fan. A turn cannot exceed half a
## revolution, because [method fan_angles] takes the short way round, so at the
## floor above the largest honest answer is 179 and this bounds a step that
## arrived as a fraction of a degree from a file rather than from the editor.
const MAX_FAN_DABS: int = 180

## How far over a whole number of steps a turn may measure and still be counted
## as that whole number.
##
## The division has to be rounded up, or a turn of a step and a half would fan
## nothing, and rounding up is what makes an exact multiple fragile: a right
## angle at a step of thirty is three divisions when the ratio comes out at
## 3.0 and four when it comes out at 3.0000000000000004. Both happen. The angles
## a real stroke turns are `atan2` of positions a walk interpolated, so a leg
## that ran due east arrives as a hair off it and the ratio lands on whichever
## side of the integer that hair points. One part in a million of a step is far
## below the tenth of a degree the floor allows and far above the noise, so this
## decides the exact multiples and nothing else.
const FAN_RATIO_TOLERANCE: float = 1e-6


## One dab's spacing: how far to step on each axis, in what frame, and whether
## that frame is mirrored.
##
## Inner rather than a `class_name` of its own so no rescan of the class cache
## stands between a fresh checkout and a green gate, which is the reason
## `SaCompute.Buffer` is inner too. `SaStrokeDistance.Spacing`.
class Spacing:
    extends RefCounted

    ## Pixels between dabs on each axis of the tip's own frame.
    var distance: Vector2 = Vector2(1.0, 1.0)

    ## The tip's rotation, so the ellipse the walk solves against is the tip's
    ## rather than the document's.
    var rotation: float = 0.0

    ## Whether that frame is mirrored, which turns the rotation into its
    ## explement: a reflection reverses the sense of an angle, so the ellipse a
    ## mirrored tip walks against leans the other way.
    var flipped: bool = false

    ## False turns the distance walk off entirely, which is what an airbrush
    ## ignoring spacing asks for.
    var enabled: bool = true

    ## The small-dab mode's walk rather than the ellipse. A dab under
    ## [constant SaDabGeometry.PIXEL_MODE_DIAMETER] paints whole texels, so the
    ## step that lays one texel per texel crossed is not a distance at all: it is
    ## the first of the two axes to advance a whole texel, which is a square in
    ## the document's own frame and not an ellipse in the tip's.
    var pixel_grid: bool = false

    func _init(
        step: Vector2 = Vector2.ONE,
        at: float = 0.0,
        is_flipped: bool = false,
        is_enabled: bool = true,
        on_pixel_grid: bool = false
    ) -> void:
        distance = step
        rotation = at
        flipped = is_flipped
        enabled = is_enabled
        pixel_grid = on_pixel_grid

    ## Both axes equal, which is the case the cheap walk handles.
    func is_isotropic() -> bool:
        return is_equal_approx(distance.x, distance.y)


## The offset accumulated since the last dab, in the tip's frame, and a vector
## for the reason the class comment gives.
var _accumulated: Vector2 = Vector2.ZERO

## Milliseconds since the last dab, for the timed walk.
var _accumulated_time: float = 0.0

## The spacing the last dab was painted with, which is what the next
## interpolation walks against. [method register_dab] replaces it, and that
## replacement is what lets the step change inside one segment.
var spacing: Spacing = Spacing.new()

## Milliseconds between dabs when the timed walk is on, and -1.0 when it is off.
var timed_interval: float = -1.0

## Where the last dab landed, and the direction the stroke was going. Read by
## the sensors rather than by the walk.
var last_position: Vector2 = Vector2.ZERO
var last_angle: float = 0.0
var has_last_position: bool = false

## How many dabs this stroke has painted, which is the seed the kernel's density
## and randomness hash against.
var dab_sequence: int = 0

## The distance the stroke has travelled and the hardest it was ever pressed,
## both of which are sensors rather than inputs to the walk.
var total_distance: float = 0.0
var last_max_pressure: float = 0.0

## What the stroke before this one came to, kept across [method reset].
##
## The live counters are per stroke, which is what a sensor wants, and they are
## zero by the time anything outside the stroke can read them: the tool resets
## on the pen lift. A capture dump is exactly that reader, and "how many dabs did
## that stroke paint" is the number that says the walk works, so the two survive
## the reset that clears the rest.
var previous_dabs: int = 0
var previous_distance: float = 0.0

## Milliseconds the timed walk has been handed this stroke, and what the stroke
## before came to, kept across [method reset] beside the two above.
##
## The airbrush is the one walk whose correctness is a rate, and a rate cannot be
## read off a dab count alone. A drive counted 8 dabs at rate 10 and 48 at rate
## 50 over "the same 60 frames" and read the two as 80 and 96 per cent of what
## the rate asked for. A frame is not a sixtieth of a second in an offscreen
## capture, and both numbers are what a run at 75 and then 62 frames a second
## deposits at exactly the right rate. So the walk counts the time it walked, and
## a reader with the pair can divide rather than assume.
##
## **Written by the caller, once a frame**, and this is the one field here that
## is. The calls of one frame are `(0, E)`, then `(t1, E)`, then `(t2, E)`, all
## sub-segments of the same frame, so a walk that added what each call was handed
## counted a measured second as 1333 milliseconds. Only the caller knows where
## one frame ends, and `SaDabCadence.dabs_for_frame` is the only caller
## that passes times at all: the drag path calls
## [method next_point_position] with the default zeros, so its timed walk never
## runs.
##
## A distance-only stroke leaves it at zero, which is honest: no clock ran.
var timed_elapsed: float = 0.0
var previous_timed_elapsed: float = 0.0


## The step Auto Spacing asks for at a dab of *size* pixels: it grows with the
## square root of the size above a pixel and linearly below it.
##
## The square root is the whole of the idea. What the eye reads along a stroke
## is the gap between two dab outlines, not the gap as a fraction of the
## diameter, so a spacing that is a fixed fraction steps in visible lumps the
## moment the brush is large. Taking the root makes the gap grow far slower than
## the size, which closes it on a large brush without a small one asking for a
## hundred dabs a pixel.
##
## Below one pixel the root would run the other way, `sqrt(0.25)` being twice
## its argument, so the curve is linear there: the two halves meet at one, where
## a number and its own root are equal, and the join is continuous for that
## reason rather than by a fitted constant. *coeff* scales the whole curve and
## is the Auto Spacing slider.
static func auto_step(size: float, coeff: float) -> float:
    return coeff * (size if size < 1.0 else sqrt(size))


## A dab's size becomes the spacing the walk steps by.
##
## *isotropic* takes the larger of the two dimensions on both axes and throws the
## rotation away, which is what a painter means by "spacing" when the tip is
## round: one number, and no frame for it to be measured in. Anisotropic keeps
## the two apart, so a flat tip steps further along its length than across it,
## and it keeps the tip's rotation because the two steps are only meaningful in
## the frame the tip's own axes define.
##
## *on_pixel_grid* is the small-dab mode's step instead of any of the above, and
## it is a flag the caller sets rather than a test on *dab_width* here. The first
## shape of it was that test, and it rewrote an answer three suites pin by
## driving this function directly with sizes of a quarter of a pixel: Krita's own
## sub-pixel branch in [method auto_step] is one of them, and a mode a caller
## walked into by handing over a small number would have taken it away from them.
## `SaDabCadence.spacing_for` is the one place a real dab asks this, and it is
## where the size is tested.
static func effective_spacing(
    dab_width: float,
    dab_height: float,
    spacing_value: float,
    extra_scale: float = 1.0,
    isotropic: bool = false,
    rotation: float = 0.0,
    axes_flipped: bool = false,
    auto_spacing: bool = false,
    auto_coeff: float = 1.0,
    distance_enabled: bool = true,
    on_pixel_grid: bool = false
) -> Spacing:
    # The small-dab mode, before any of the settings below are read. Under
    # `SaDabGeometry.PIXEL_MODE_DIAMETER` the dab is a texel, so the step that
    # lays one texel per texel crossed is the whole of the answer and Spacing,
    # Auto Spacing and the tip's rotation have nothing left to say: a fraction of
    # a one-texel dab is a step the walk floors at half a pixel anyway, and it
    # would stamp the same texel two and three times over.
    #
    # `distance_enabled` still comes through, because Ignore Spacing is the
    # airbrush's switch and not a spacing number: a held pen under an airbrush
    # deposits on its clock in this mode exactly as it does in every other.
    if on_pixel_grid:
        return Spacing.new(Vector2.ONE, 0.0, false, distance_enabled, true)
    var step := Vector2.ZERO
    var at := rotation
    var flipped := axes_flipped
    if not isotropic:
        if auto_spacing:
            step = Vector2(auto_step(dab_width, auto_coeff), auto_step(dab_height, auto_coeff))
        else:
            step = Vector2(dab_width, dab_height) * spacing_value
    else:
        var significant := maxf(dab_width, dab_height)
        significant = auto_step(significant, auto_coeff) if auto_spacing else significant * spacing_value
        step = Vector2(significant, significant)
        at = 0.0
        flipped = false
    return Spacing.new(step * extra_scale, at, flipped, distance_enabled)


## Everything a fresh stroke starts from, keeping what the last one came to.
func reset() -> void:
    if dab_sequence > 0:
        previous_dabs = dab_sequence
        previous_distance = total_distance
        previous_timed_elapsed = timed_elapsed
    timed_elapsed = 0.0
    _accumulated = Vector2.ZERO
    _accumulated_time = 0.0
    last_position = Vector2.ZERO
    last_angle = 0.0
    has_last_position = false
    dab_sequence = 0
    total_distance = 0.0
    last_max_pressure = 0.0


## The segment parameter of the next dab, or -1.0 when the segment is too short
## to hold one.
##
## Called in a loop: each answer that is not negative is a dab, and the caller
## comes back with the same segment until the answer is negative. The times are
## milliseconds and only matter when [member timed_interval] is positive.
##
## When both walks are on the smaller factor wins, because each is a deadline
## and a dab is due at the first of them: taking the later would let a fast drag
## outrun its own spacing while the clock was still counting, and taking the
## distance alone would leave a still pen painting nothing under an airbrush.
##
## **The caller advances *start_time* to each dab's own time**, the way it
## advances *start* to each dab's position, or the second question of a frame
## sees the whole frame's elapsed time again and the airbrush fires once per
## call rather than once per interval.
##
## A counter of how long ago the spacing was last recomputed does not belong
## here and was tried: Sara recomputes the spacing for every dab anyway, so the
## counter answered a question nobody asks, and adding to it on this path
## corrupted the timed accumulator beside it. Measured at 59 dabs a second where
## the rate asked for 20.
func next_point_position(start: Vector2, end: Vector2, start_time: float = 0.0, end_time: float = 0.0) -> float:
    var distance_factor := -1.0
    if spacing.enabled:
        if spacing.pixel_grid:
            distance_factor = _next_point_pixel(start, end)
        else:
            distance_factor = (
                _next_point_isotropic(start, end) if spacing.is_isotropic() else _next_point_anisotropic(start, end)
            )

    var time_factor := -1.0
    if timed_interval > 0.0:
        time_factor = _next_point_timed(start_time, end_time)

    var t := -1.0
    if distance_factor < 0.0:
        t = time_factor
    elif time_factor < 0.0:
        t = distance_factor
    else:
        t = minf(distance_factor, time_factor)

    return t


## Records the dab the caller just painted and the spacing that produced it, so
## the next walk uses that spacing rather than the one before it.
##
## This is the half that lets the step change inside a segment, and leaving it
## out is the bug the class comment describes rather than a missed statistic.
##
## *painted* is false for a sample the caller decided not to dispatch, which is
## a dab under `StateBrush.MIN_DAB_DIAMETER`. The walk still has to be told, or
## the accumulator offers the same point for ever, and everything about where
## the stroke has got to is updated. What is not is `dab_sequence`, which is the
## count of dabs the canvas received: it seeds the kernel's per-dab randomness
## and it is what a state dump reports, and a run that answers 1979 for a stroke
## with no lit texel in it is a dump that lies about the picture.
func register_dab(
    position: Vector2, painted_with: Spacing, pressure: float = 0.0, interval: float = -1.0, painted: bool = true
) -> void:
    if has_last_position:
        total_distance += last_position.distance_to(position)
        var travel := position - last_position
        if not travel.is_zero_approx():
            last_angle = travel.angle()
    last_position = position
    has_last_position = true
    spacing = painted_with
    timed_interval = interval
    if painted:
        dab_sequence += 1
    last_max_pressure = maxf(last_max_pressure, pressure)


## The round-tip walk: one length against one step.
##
## Both axes carry the same step here, so only one component of the accumulator
## is used and the ellipse of the other walk is a circle the arithmetic need
## never form.
##
## The negative branch is not defensive. The spacing is replaced by
## [method register_dab] between interpolation attempts, so a step that shrank
## under a pressure change leaves the accumulator already past it, and the dab
## belongs at the start of the segment rather than nowhere.
func _next_point_isotropic(start: Vector2, end: Vector2) -> float:
    if start.is_equal_approx(end):
        return -1.0
    var step := maxf(MIN_DISTANCE_SPACING, spacing.distance.x)
    var segment := start.distance_to(end)
    var remaining := step - _accumulated.x

    if remaining <= 0.0:
        _reset_accumulators()
        return 0.0
    if remaining <= segment:
        _reset_accumulators()
        return remaining / segment
    _accumulated.x += segment
    return -1.0


## The flat-tip walk: where the accumulated offset crosses the spacing ellipse.
##
## **The derivation, because the four terms below are unreadable without it.**
## A flat tip owes a step of `sx` along one axis and `sy` along the other, so
## "one dab further" is not a distance but a point on the ellipse
## `(x/sx)^2 + (y/sy)^2 = 1` in the tip's own frame. The walk holds the offset
## `(x, y)` accumulated since the last dab, and the current segment adds
## `(dx, dy)` as its parameter *t* runs from zero to one. Substituting
## `(x + t*dx, y + t*dy)` into the ellipse and collecting powers of *t* gives
##
##     travel * t^2 + 2 * along * t + start_excess = 0
##
## with `travel` the segment's own squared ellipse norm, `along` the offset and
## the segment paired through the same metric, and `start_excess` the offset's
## squared norm less one, which is negative exactly while the offset is still
## inside the ellipse. The dab is at the smaller non-negative root, which is the
## `+` one because `travel` is positive and the product of the roots,
## `start_excess / travel`, is negative: one root is behind the segment's start
## and the other is the crossing ahead of it.
##
## The offsets and the segment are taken absolute first. The ellipse is
## symmetrical in both axes, so folding everything into one quadrant costs
## nothing and spares the walk a sign convention, which is also why the sign of
## the rotation never matters.
func _next_point_anisotropic(start: Vector2, end: Vector2) -> float:
    if start.is_equal_approx(end):
        return -1.0

    # The two steps as reciprocals, because every use below divides by them.
    var per_x := 1.0 / maxf(MIN_DISTANCE_SPACING, spacing.distance.x)
    var per_y := 1.0 / maxf(MIN_DISTANCE_SPACING, spacing.distance.y)
    var x := _accumulated.x
    var y := _accumulated.y

    var start_excess := pow(x * per_x, 2.0) + pow(y * per_y, 2.0) - 1.0
    # Already on or outside the ellipse, for the same reason the isotropic walk
    # has a negative branch: the spacing moved under the accumulator.
    if start_excess >= 0.0:
        _reset_accumulators()
        return 0.0

    var current_rotation := spacing.rotation
    if spacing.flipped:
        current_rotation = TAU - current_rotation

    var diff := end - start
    if current_rotation > ROTATION_EPSILON:
        diff = diff.rotated(current_rotation)

    var dx := absf(diff.x)
    var dy := absf(diff.y)
    var travel := pow(dx * per_x, 2.0) + pow(dy * per_y, 2.0)
    var along := x * dx * per_x * per_x + y * dy * per_y * per_y
    var discriminant := pow(along, 2.0) - travel * start_excess

    # `start_excess` is negative on this branch and `travel` is not, so the
    # discriminant is a square plus a positive number and a real root always
    # exists. The guard is for a zero-length segment the equality test above let
    # through, and there is nothing to warn about.
    if discriminant < 0.0 or travel <= 0.0:
        return -1.0

    var t := (-along + sqrt(discriminant)) / travel
    if t >= 0.0 and t <= 1.0:
        _reset_accumulators()
        return t
    # The crossing is past the end of this segment, so the whole of it is
    # leftover and the caller comes back with the next one.
    _accumulated += Vector2(dx, dy)
    return -1.0


## The small-dab walk: one dab per texel the stroke crosses.
##
## **Not an ellipse, and that is the whole of it.** The two walks above ask when
## the travelled offset crosses a circle or an ellipse, which is a Euclidean
## question, and the answer on a diagonal is a step of the same length as on an
## axis. Round that to the grid and a diagonal one-texel stroke stamps the same
## texel twice and then skips one, because a step of one pixel along a 45 degree
## line is 0.707 of a texel on each axis. What a pixel editor draws instead is
## the line every drawing program has drawn since Bresenham: advance one whole
## texel along the axis the line runs fastest on, and let the other axis
## staircase under it. That is the infinity norm, a square rather than an
## ellipse, and it is one texel per texel crossed at every angle.
##
## In the document's own frame, not the tip's: the grid is the document's, and a
## dab this small has no visible axis for a rotated frame to mean anything about.
##
## **Anchored on the grid, not on an accumulator, and that is the whole of the
## rest of it.** The first shape of this walk carried the travelled offset in
## `_accumulated` the way the two above do, and it doubled texels: the offset
## measures from where the last dab fell, the grid measures from where that dab
## was rounded to, and the two drift apart by up to half a texel over a segment
## the caller hands in in pieces. Measured on a forty five degree line fed in
## chunks of one and a half pixels, it stamped nine texels twice in twenty. So
## the question this asks is against `start.round()`, which is the texel the last
## dab actually painted, since a dab under the threshold is snapped the whole
## way: solve for the point where the dominant axis is a whole texel off that,
## and the drift has nowhere to accumulate.
##
## The accumulator is cleared on a dab so a stroke whose size ramps back up out
## of the mode starts the ellipse walk from nothing rather than from a leftover
## this branch never wrote.
##
## **The last dab's texel, not the segment's start, at the first step of a
## segment**. `start` is the last dab only inside a segment.
## A new segment starts at the previous sample, which lies up to a texel past
## the last dab, and rounding that forward anchored the walk one texel ahead of
## the painted one, so the next dab skipped a texel. Pencil at 30 events over
## 520 pixels left ten one-texel holes, one wherever the sample's leftover was
## half a texel or more, and the same share at 120. The registered dab is used
## only while it is within a texel of *start* on both axes, which is that case
## and no other: a scattered dab lands away from the path and is no anchor.
func _next_point_pixel(start: Vector2, end: Vector2) -> float:
    if start.is_equal_approx(end):
        return -1.0
    var diff := end - start
    var anchor := start.round()
    if has_last_position:
        var behind := start - last_position
        if absf(behind.x) < 1.0 and absf(behind.y) < 1.0:
            anchor = last_position.round()
    # The dominant axis, which is what makes this the infinity norm. A vertical
    # segment has no horizontal travel at all, so the tie goes to x only when
    # both are zero and that case returned above.
    var t := 0.0
    if absf(diff.x) >= absf(diff.y):
        t = (anchor.x + signf(diff.x) - start.x) / diff.x
    else:
        t = (anchor.y + signf(diff.y) - start.y) / diff.y
    if t > 1.0:
        return -1.0
    _reset_accumulators()
    return t


## The airbrush walk: one interval against the time the segment took, which
## paints on a pen that is not moving at all.
func _next_point_timed(start_time: float, end_time: float) -> float:
    if not (start_time < end_time):
        return -1.0
    var interval := clampf(timed_interval, MIN_TIMED_INTERVAL, MAX_TIMED_INTERVAL)
    var remaining := interval - _accumulated_time
    var elapsed := end_time - start_time

    if remaining <= 0.0:
        _reset_accumulators()
        return 0.0
    if remaining <= elapsed:
        _reset_accumulators()
        return remaining / elapsed
    _accumulated_time += elapsed
    return -1.0


## The angles a fan around a corner is drawn at, from *from_angle* to
## *to_angle* in steps of *step_degrees*, or an empty array when no fan is
## due.
##
## **What a fan is for.** A round tip turning a corner looks the same either
## way, and a flat one does not: the walk lays a dab pointing along the way in
## and the next one pointing along the way out, and the outside of the corner is
## cut off between them. The fan fills that wedge with dabs at the same point
## and stepped angles, so the tip sweeps round the corner rather than jumping
## across it.
##
## **Both ends are excluded**, which is the whole of why this answers an array
## rather than a count. *from_angle* is the angle the last dab was already drawn
## at and *to_angle* is the angle the next one is about to be drawn at, so a fan
## that emitted either would stamp the same dab twice at the same point. What is
## left is the strictly intermediate angles, `steps - 1` of them for `steps`
## equal divisions of the turn.
##
## **The short way round.** `angle_difference` answers the signed turn in -PI to
## PI, so a corner of ten degrees fans through ten and never through three
## hundred and fifty, and the sign carries the direction the stroke actually
## turned. A stroke that reverses exactly, an angle of PI, is the one case with
## no short way, and it fans in whichever direction the engine's sign convention
## picks rather than being a case of its own: a pen that reverses on the spot has
## no outside of the corner to cut.
static func fan_angles(from_angle: float, to_angle: float, step_degrees: float) -> PackedFloat32Array:
    var angles := PackedFloat32Array()
    if step_degrees < MIN_FAN_STEP_DEGREES:
        return angles
    var step := deg_to_rad(step_degrees)
    var turn := angle_difference(from_angle, to_angle)
    var count := mini(ceili(absf(turn) / step - FAN_RATIO_TOLERANCE), MAX_FAN_DABS)
    # One division is the turn the two ends already cover, and nothing at all is
    # left in between, so both no-fan cases answer here rather than in a guard of
    # their own.
    if count < 2:
        return angles
    var each := turn / float(count)
    for i in count - 1:
        angles.append(from_angle + float(i + 1) * each)
    return angles


func _reset_accumulators() -> void:
    _accumulated = Vector2.ZERO
    _accumulated_time = 0.0
