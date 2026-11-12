## Sara's paint information: one input sample, plus what the stroke has been
## doing.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The speed it answers is measured by the class it extends, [SaSpeedSmoother]
## in the `speed` folder beside this file, a port whose copyright line is in
## [`PROVENANCE.md`](PROVENANCE.md). Everything this file adds, the running
## totals, the angle and its fallback, the lock and the normalisation, is
## written below from what it does.
##
## **It extends the smoother rather than holding one**, because the sample is
## what the smoother is fed and what answers the speed, and the suites and the
## speed trace capture read `_last_speed` and `_distances` on the sample. Held
## as a member, every one of those reads would have to go through it.
##
## **Pressure arrives through `SaTablet.normalize` with a gamma of 1.0.** The
## maximum and the sweep correction stay, because they are the hardware and the
## hand. A gamma would be taste, and taste is a response curve a painter draws.
class_name SaStrokeInfo
extends SaSpeedSmoother

## Pixels per millisecond that read as full speed. Thirty is a hand moving fast
## across a screen-sized canvas, and it is what a speed curve drawn in another
## program assumes, so a preset that ramps at the middle of the graph ramps at
## the same hand speed here.
const SPEED_MAX: float = 30.0

var position: Vector2 = Vector2.ZERO
## 0 to 1, already through `SaTablet.normalize`.
var pressure: float = 0.0
## Degrees, each -60 to 60, which is the range every sensor divides by.
var tilt_x: float = 0.0
var tilt_y: float = 0.0
## Barrel rotation in degrees, -180 to 180.
var barrel_rotation: float = 0.0

## Whether the pen is over the canvas without touching it. Six sensors answer a
## fixed value here rather than their own, because a hover has no stroke behind
## it: there is no distance travelled, no elapsed time and no dab count to read,
## and a random draw per dab has no dab. What the fixed value shows is the brush
## at rest, which is what an outline under a hovering pen should be.
var hovering: bool = true

## Total length of the stroke so far, in document pixels.
var total_length: float = 0.0
## Which dab this is, counting from zero at the press.
var dab_index: int = 0
## Milliseconds since the press.
var elapsed_ms: float = 0.0
## How much ink the stroke has laid down, which is what the depletion sensor
## spends. Pressure-weighted document pixels: each dab adds the pressure it was
## laid at times the step it took to get there.
##
## **A fourth running total rather than a reservoir.** A reservoir would need a
## capacity, and the capacity is the painter's number on the sensor, not the
## stroke's. Counted the way `total_length` is counted, the stroke says how much
## was spent and the sensor says how much the pen held, which is also what lets
## two options deplete at two different rates from one stroke.
var total_ink: float = 0.0

var last_position: Vector2 = Vector2.ZERO
## The last angle the stroke had, in radians, which is what a sample that did not
## move falls back to.
var last_angle: float = 0.0
## The angle the stroke was set to at its first painted dab, and never
## overwritten, so a whole stroke can use the angle it started at.
var locked_angle: float = 0.0
var has_locked_angle: bool = false
## An angle pushed in from outside, which answers before either of the above.
## The fan corners use it.
var angle_override: float = 0.0
var has_angle_override: bool = false

## The highest pressure this stroke has reached, which is what the pressure in
## sensor answers.
var max_pressure: float = 0.0

## The brush's texture at this dab's centre, 0 to 1, which the texture sensor
## answers. The field's second channel where it has one and its
## lightness where it has one channel.
##
## **The engine writes it, before the dynamics read the sample**, because the
## texture is the engine's and this sample knows nothing of it. An engine that
## reads it on the CPU keeps the canvas in VRAM, which is hard rule 1. One with
## no texture to read leaves it at `SaSensor.NEUTRAL_TEXTURE`, a middle grey,
## which a colour offset reads as no shift, and every press puts it back there.
var texture: float = 0.5
## The brush's diameter at full pressure in document pixels, which the
## along-the-stroke roll measures its features in. Written by the engine after
## the press, like the texture, and nought where it writes none, which the
## sensor reads as `SaSensor.ALONG_FALLBACK_DIAMETER`.
var tip_diameter: float = 0.0
## The pen source the airbrush's finger wheel is read from, the one
## `SaContext.pens` asks, taken at the press by [method begin] so a dab reads
## the wheel without a walk to the registry. Null where none is registered, and
## then the wheel reads nought, its resting value.
var pen: SaPenSource = null

## Reseeded per dab, so two dabs of one stroke differ.
var random: RandomNumberGenerator = RandomNumberGenerator.new()
## Seeded once per stroke, so every dab of one stroke agrees. Keyed by the option
## that asks, which is why it is a dictionary rather than one number: two options
## with a fuzzy per stroke sensor must not move together.
var _stroke_random: Dictionary[String, float] = {}
var stroke_seed: int = 0


## Starts a stroke: every running total back to nothing and both random streams
## reseeded. The per-stroke seed is drawn once here, which is what makes a fuzzy
## per stroke sensor a constant for the whole of it.
func begin(at: Vector2, seed_value: int = 0) -> void:
    position = at
    last_position = at
    total_length = 0.0
    dab_index = 0
    elapsed_ms = 0.0
    # The refill rule, and the whole of it: lifting the pen and putting it down
    # again is what a painter does with a marker that has stopped marking.
    total_ink = 0.0
    max_pressure = 0.0
    texture = SaSensor.NEUTRAL_TEXTURE
    tip_diameter = 0.0
    pen = SaPenSource.registered()
    hovering = false
    last_angle = 0.0
    locked_angle = 0.0
    has_locked_angle = false
    has_angle_override = false
    _begin_speed(at)
    _stroke_random.clear()
    stroke_seed = seed_value if seed_value != 0 else SaPenClock.now_usec()
    random.seed = stroke_seed


## *seed_value* folded to the 24 bits a float holds exactly, the stroke's seed as
## a kernel's rounding of a store into a half texture draws from it. The three
## 24-bit pieces of the 64 are folded together rather than
## the low bits kept, so a clock's seed and a suite's small one both reach it.
static func folded_seed(seed_value: int) -> int:
    return (seed_value ^ (seed_value >> 24) ^ (seed_value >> 48)) & 0xffffff


## One sample, which feeds the speed smoother as well: [method feed_dab] and
## [method feed_report] at one place and one time. Right for a brush whose
## samples carry times of their own, as the noise brush's do, spread between
## the two reports either side of them.
func feed(
    at: Vector2,
    raw_pressure: float,
    tilt: Vector2,
    rotation_degrees: float,
    time_ms: float,
    table: PackedFloat32Array = SaTablet.correction
) -> void:
    feed_dab(at, raw_pressure, tilt, rotation_degrees, time_ms, table)
    _feed_speed(at, time_ms)


## One dab's sample with the speed smoother left alone, for a brush that feeds
## the smoother its pen's reports through [method feed_report].
## *raw_pressure* is the tablet's own number and is normalised here, so no
## caller has to remember the calibration.
##
## *table* is the correction the pressure is read through. The stamp brush
## passes its preset's, the table the preset was made under, so a painter's own
## curve does not reach a preset made under another. A caller
## that names none reads the painter's, which is what an engine whose presets
## carry no table wants.
##
## The running totals move before the angle is read, because the drawing angle is
## between the last position and this one and a sample that has already moved the
## position has lost the pair.
func feed_dab(
    at: Vector2,
    raw_pressure: float,
    tilt: Vector2,
    rotation_degrees: float,
    time_ms: float,
    table: PackedFloat32Array = SaTablet.correction
) -> void:
    var moved := at - position
    var distance := moved.length()
    if distance > 0.0:
        last_angle = atan2(moved.y, moved.x)
    last_position = position
    position = at
    total_length += distance
    elapsed_ms = time_ms
    tilt_x = tilt.x
    tilt_y = tilt.y
    barrel_rotation = rotation_degrees
    pressure = SaTablet.normalize(raw_pressure, SaSettings.tablet_max_pressure, 1.0, table)
    max_pressure = maxf(max_pressure, pressure)


## Counts one dab and reseeds the per-dab stream, so the fuzzy per dab sensor
## answers a new number for each. The lock is taken here rather than at the press
## because it is the first *painted* dab that sets it: a stroke that begins with
## the pen hovering across the canvas would otherwise lock on the direction of
## the approach rather than of the mark.
##
## The ink goes here rather than in `feed` for the same reason the dab count
## does: a hover feeds samples and paints nothing, and a pen carried across the
## canvas without touching it must not come down dry.
func next_dab() -> void:
    if not has_locked_angle:
        locked_angle = drawing_angle(false)
        has_locked_angle = true
    dab_index += 1
    total_ink += dab_ink()
    random.seed = stroke_seed + dab_index * 2654435761


## What one dab costs the pen, in pressure-weighted document pixels.
##
## **The coverage of a dab, measured from what the stroke alone knows.** The
## dynamics half decides how wide the dab is and the stroke never sees that
## number, but it does see the step the walk just took, and the walk steps by the
## dab's own size: `SaStrokeDistance.effective_spacing` is the tip's width and
## height times the spacing fraction. So a wide tip lays a long step and a
## hairline lays a short one, and the distance between two dabs *is* the dab's
## width up to a factor the painter set on purpose. Pressure is the other half of
## the area, the nib pushed harder wetting more of the paper.
##
## The first dab of a stroke costs nothing, because `begin` puts the position and
## the last position on the same point, and a marker put down and not yet moved
## has not marked anything.
func dab_ink() -> float:
    return pressure * position.distance_to(last_position)


## The angle to draw at, in radians.
##
## An override answers first, then the locked angle when the caller asked for it,
## then the angle between the last position and this one, falling back to the
## last angle when the two coincide. That fallback is the whole of why
## `last_angle` is kept: a sample that did not move has no angle of its own and a
## brush that snapped to zero there would flick on every held pen.
func drawing_angle(consider_locked: bool) -> float:
    if has_angle_override:
        return angle_override
    if consider_locked and has_locked_angle:
        return locked_angle
    var moved := position - last_position
    if is_zero_approx(moved.length_squared()):
        return last_angle
    return atan2(moved.y, moved.x)


## The airbrush's finger wheel, 0 to 1, as [member pen] reads it now, which the
## tangential pressure sensor answers. Nought with no source, and nought from a
## source that reads no wheel.
func wheel() -> float:
    return pen.wheel() if pen != null else 0.0


## A number in 0 to 1 that is the same for the whole stroke and different per
## *key*, which is the option's own name. Two options with a fuzzy per stroke
## sensor must not move together, and one option must not move between its dabs.
func stroke_random(key: String) -> float:
    if not _stroke_random.has(key):
        var generator := RandomNumberGenerator.new()
        generator.seed = stroke_seed ^ int(hash(key))
        _stroke_random[key] = generator.randf()
    return float(_stroke_random[key])


## Speed in 0 to 1: the smoother's pixels per millisecond against the speed that
## reads as full, and anything faster reads as full rather than as more.
##
## Zero for the first sample of a stroke, which has no pair to measure between.
func drawing_speed() -> float:
    return minf(1.0, _last_speed / SPEED_MAX)


## What the stroke reports about itself, for a state dump. The four running
## totals are the point: a picture of a stroke cannot say which dab it is on, and
## a picture of one that faded cannot say whether the ink ran out or the pressure
## did.
func report() -> Dictionary[String, Variant]:
    return {
        "position": [position.x, position.y],
        "pressure": pressure,
        "max_pressure": max_pressure,
        "tilt": [tilt_x, tilt_y],
        "barrel_rotation": barrel_rotation,
        "hovering": hovering,
        "total_length": total_length,
        "dab_index": dab_index,
        "elapsed_ms": elapsed_ms,
        "total_ink": total_ink,
        "drawing_angle": drawing_angle(false),
        "locked_angle": locked_angle if has_locked_angle else 0.0,
        "has_locked_angle": has_locked_angle,
        "drawing_speed": drawing_speed(),
        "texture": texture,
    }
