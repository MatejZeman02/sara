## The noise brush's field read on the CPU at stroke coordinates, the texture
## sensor's reading at each point of a stroke.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **Why a second reading of one field.** The texture sensor answers one number
## a point, and the door's dynamics read it on the CPU before the point is
## laid, so Hue and Saturation can follow it. Reading it back off the GPU would
## stall every update on a readback, which is the CPU-GPU ping-pong hard
## rule 1 forbids. The field is a few hashes at one point, so this file reads it again
## here, line for line from `noise_fields.gmacs`. The suite holds the two to one
## another through the probe kernel, texel for texel in stroke coordinates.
##
## **Exact where it can be.** The field's hash is integer arithmetic, so it is
## the same number here as on the GPU, and what is left between the two is the
## float rounding of a smoothstep and a mix, inside the hundredth its suite
## allows. The products wrap at 32 bits by hand, in halves, so no product leaves
## a 64-bit int.
##
## **The sensor reads the path itself.** A point's centre is on the path, where
## across is nought, so the sensor's reading is the field down the middle of
## the stroke at the point's along: the grain there, or the middle bristle.
extends RefCounted

const NoiseFieldsScript = preload("res://modules/sara-noise-brush-engine/noise_fields.gd")

## The second grain's lattice shift, `NOISE_SECOND_GRAIN` in the library.
const SECOND_GRAIN: Vector2 = Vector2(71.3, 19.7)
## A bristle's greatest reach and the step between two neighbours' places in
## the run of reaches, `NOISE_BRISTLE_REACH` and `NOISE_BRISTLE_STEP` there.
const BRISTLE_REACH: float = 0.75
const BRISTLE_STEP: float = 0.618034
## The pressure map where no streak is, a streak's skirt as a share of its
## core's height and how many half widths it reaches, and the run's noise a
## streak fades in over, `NOISE_BRISTLE_GAP`, `NOISE_BRISTLE_SKIRT_LEVEL`,
## `NOISE_BRISTLE_SKIRT_REACH` and `NOISE_BRISTLE_BREAK` there.
const BRISTLE_GAP: float = 0.95
const BRISTLE_SKIRT_LEVEL: float = 0.6
const BRISTLE_SKIRT_REACH: float = 2.2
const BRISTLE_BREAK: Vector2 = Vector2(0.1, 0.4)
## `NOISE_BRISTLE_OUTER` and `NOISE_BRISTLE_OUTER_RUN` there.
const BRISTLE_OUTER: float = 2.0
const BRISTLE_OUTER_RUN: Vector2 = Vector2(0.04, 0.15)
## A strand's half width, its swell and the share of its run it swells over,
## its edge's softness, a body strand's share of the period, and the strands
## read either side of a texel's own cell and how much less a neighbour must
## need to be taken, `NOISE_STRAND_WIDTH`, `NOISE_STRAND_SWELL`,
## `NOISE_STRAND_SWELL_RUN`, `NOISE_STRAND_SOFT`, `NOISE_STRAND_LENGTH`,
## `NOISE_STRAND_NEIGHBOURS` and `NOISE_STRAND_TIE` there, and
## `NOISE_STRAND_EDGE_SLACK` and `NOISE_STRAND_SAME_SIZE`, how far inside a
## whole cell the dab's edge may fall and still leave that cell's strand out,
## and the share of the Size row's width a dab's may differ by and still be it.
const STRAND_WIDTH: Vector2 = Vector2(0.12, 0.6)
const STRAND_EDGE_SLACK: float = 0.001
const STRAND_SAME_SIZE: float = 0.0001
const STRAND_SWELL: float = 0.3
const STRAND_SWELL_RUN: float = 0.25
const STRAND_SOFT: Vector2 = Vector2(0.1, 1.0)
const STRAND_LENGTH: Vector2 = Vector2(0.6, 1.0)
const STRAND_NEIGHBOURS: int = 2
const STRAND_TIE: float = 0.0001
## The lowest height a strand draws and the grain's octaves' reach either side
## of their middle, `NOISE_STRAND_HEIGHT_LOW` and `NOISE_GRAIN_TONE_HALF`.
const STRAND_HEIGHT_LOW: float = 0.35
const GRAIN_TONE_HALF: float = 0.28
## `NOISE_BRISTLE_CLUMP`, `NOISE_BRISTLE_CLUMP_MOST` and
## `NOISE_BRISTLE_CLUMP_CELLS`, the wander of the cells' width across the brush.
const BRISTLE_CLUMP: float = 0.75
const BRISTLE_CLUMP_MOST: float = 0.3
const BRISTLE_CLUMP_CELLS: float = 3.0


## Both readings of the field *values* describe at stroke coordinates *along*
## and *across*, where the tip reaches *half_width* pixels either side of the
## path, x the pressure map and y the lightness, as `noise_field` answers them.
## *mask* is the picture's grey mask, or null while the field is not a picture.
## *along* is the travelled length less the drift.
static func at(values: PackedFloat32Array, mask: Image, along: float, across: float, half_width: float) -> Vector2:
    if values.size() < NoiseFieldsScript.SLOT_COUNT:
        return Vector2(SaSensor.NEUTRAL_TEXTURE, SaSensor.NEUTRAL_TEXTURE)
    var point := Vector2(along, across * half_width) + Vector2(values[3], values[4])
    var slot := values[0]
    var two := values[1] > 1.5
    var reading := Vector2.ONE
    if slot > 1.5:
        var picture := _picture(values, mask, point)
        return Vector2(1.0 - picture if values[7] > 0.5 else picture, picture)
    if slot > 0.5:
        var bristle := _bristle(values, along, across, half_width)
        if not two:
            return Vector2(1.0 - bristle.x, bristle.x)
        reading = Vector2(1.0 - bristle.x, bristle.y)
    else:
        var grain := _grain(values, point, Vector2.ZERO)
        if not two:
            return Vector2(grain, grain)
        reading = Vector2(grain, _grain(values, point, SECOND_GRAIN))
    var relief := values[2]
    return Vector2(reading.x, clampf(0.5 + (reading.y - 0.5) * relief, 0.0, 1.0))


## How many times `noise_field_tone` spreads the lightness of a *field* about
## its middle, read with two channels when *two*, at its Contrast *contrast*
## and its Relief *relief*: the grain's octaves' reach
## [constant GRAIN_TONE_HALF] widened and narrowed to a half, a strand's
## heights from [constant STRAND_HEIGHT_LOW] up, a one channel streak's from
## the gap's up, and one for a picture or a module's field.
static func tone_stretch(field: String, two: bool, contrast: float, relief: float) -> float:
    var squeeze := relief if two else 1.0
    if field == NoiseFieldsScript.GRAIN:
        return 0.5 / maxf(minf(GRAIN_TONE_HALF * maxf(contrast, 0.0), 0.5) * squeeze, 0.001)
    if field == NoiseFieldsScript.BRISTLE:
        var low := 0.5 + (STRAND_HEIGHT_LOW - 0.5) * squeeze if two else 1.0 - BRISTLE_GAP
        var high := 0.5 + 0.5 * squeeze if two else 1.0
        return 1.0 / maxf(high - low, 0.001)
    return 1.0


## What the texture sensor reads at a point of the path *along* the stroke: the
## lightness down its middle, which is the second channel where the field has
## two and its one grey where it has one.
static func sensor_reading(values: PackedFloat32Array, mask: Image, along: float) -> float:
    return at(values, mask, along, 0.0, 1.0).y


## The 32 bits a GLSL `uint` keeps.
const MASK_32: int = 0xffffffff


## `noise_hash`, one lattice cell to a number in 0 to 1.
static func hash21(p: Vector2) -> float:
    var cell := p.floor()
    var h := (_times(int(cell.x) & MASK_32, 1597334677) + _times(int(cell.y) & MASK_32, 3812015801)) & MASK_32
    h = _times(h ^ (h >> 16), 2146121005)
    h = _times(h ^ (h >> 15), 2221713035)
    h = h ^ (h >> 16)
    return float(h >> 8) / 16777216.0


## *a* times *b*, both unsigned 32-bit, wrapped to 32 bits as a `uint` product
## wraps. Split in two halves of *b* so each product fits in 63 bits.
static func _times(a: int, b: int) -> int:
    var low := a * (b & 0xffff)
    var high := ((a * (b >> 16)) & 0xffff) << 16
    return (low + high) & MASK_32


## `noise_value`, the four corners of the cell mixed along a smoothstep.
static func value_noise(p: Vector2) -> float:
    var cell := p.floor()
    var f := p - cell
    var smoothed := f * f * (Vector2(3.0, 3.0) - 2.0 * f)
    var a := hash21(cell)
    var b := hash21(cell + Vector2(1.0, 0.0))
    var c := hash21(cell + Vector2(0.0, 1.0))
    var d := hash21(cell + Vector2(1.0, 1.0))
    return lerpf(lerpf(a, b, smoothed.x), lerpf(c, d, smoothed.x), smoothed.y)


## `noise_fbm`, three octaves, each twice as fine and half as loud.
static func value_fbm(p: Vector2) -> float:
    var total := 0.0
    var amplitude := 0.5
    var weight := 0.0
    var point := p
    for _octave in 3:
        total += amplitude * value_noise(point)
        weight += amplitude
        amplitude *= 0.5
        point *= 2.0
    return total / weight


## `noise_grain`, at a point already offset.
static func _grain(values: PackedFloat32Array, point: Vector2, lattice_shift: Vector2) -> float:
    var scale := maxf(values[5], 0.5)
    var grain := value_fbm(point / scale + lattice_shift)
    return clampf((grain - 0.5) * values[6] + 0.5, 0.0, 1.0)


## `noise_bristle` at stroke coordinates *along* and *across*, the tip
## *half_width* pixels either side of the path: the strand of the texel's own
## cell or of the [constant STRAND_NEIGHBOURS] either side that needs the least
## pressure there.
static func _bristle(values: PackedFloat32Array, along: float, across: float, half_width: float) -> Vector2:
    var width := maxf(values[8], 1.0)
    var count := maxf(values[5], 1.0)
    var spread := clampf(values[6], 0.0, 1.0)
    var period := maxf(values[7] * width, 1.0)
    var salt := values[3]
    var run_at := along + values[4]
    var reach := count * 2.0 * maxf(half_width, 1e-6) / width
    if absf(reach - count) <= STRAND_SAME_SIZE * count:
        reach = count
    var low := 0.5 * (count - reach)
    var cells := _place(low + (across * 0.5 + 0.5) * reach, count, spread, salt)
    var high := _place(0.5 * (count + reach), count, spread, salt)
    low = _place(low, count, spread, salt)
    var edges := Vector2(floorf(low + STRAND_EDGE_SLACK), ceilf(high - STRAND_EDGE_SLACK))
    var index := floorf(cells)
    var best := Vector2(1.0 - BRISTLE_GAP, STRAND_HEIGHT_LOW)
    var found := false
    for i in 2 * STRAND_NEIGHBOURS + 1:
        var side := 1.0 if i % 2 == 0 else -1.0
        var strand := index + side * floorf(0.5 * float(i + 1))
        if strand < edges.x or strand >= edges.y:
            continue
        var reading := _strand(values, strand, cells, run_at, period, edges, spread, salt)
        if not found or reading.x > best.x + STRAND_TIE:
            best = reading
            found = true
    return best


## `noise_bristle_place`, the place *cells* across the brush moves to under
## the cells' wander, for a brush of *count* cells at *spread*.
static func _place(cells: float, count: float, spread: float, salt: float) -> float:
    var steepest := minf(BRISTLE_CLUMP * spread, BRISTLE_CLUMP_MOST)
    if steepest <= 0.0:
        return cells
    var amount := steepest / (1.5 / BRISTLE_CLUMP_CELLS + 1.0 / count)
    var first := _wander(0.0, salt)
    var last := _wander(count, salt)
    return cells + amount * (_wander(cells, salt) - lerpf(first, last, cells / count))


## `noise_bristle_wander`, the wander at *cells*, from nought to one.
static func _wander(cells: float, salt: float) -> float:
    return value_noise(Vector2(cells / BRISTLE_CLUMP_CELLS, salt + 23.0))


## `noise_strand`'s first two readings, one less the pressure *strand* needs
## at *cells* across the comb, and its height, with the brush's strand rows
## read off *values*.
static func _strand(
    values: PackedFloat32Array,
    strand: float,
    cells: float,
    run_at: float,
    period: float,
    edges: Vector2,
    spread: float,
    salt: float
) -> Vector2:
    var middle := strand + 0.5 + (hash21(Vector2(strand, salt)) - 0.5) * spread
    var phase := 17.0 * hash21(Vector2(strand, salt + 2.0))
    var own := period * lerpf(STRAND_LENGTH.x, STRAND_LENGTH.y, hash21(Vector2(strand, salt + 6.0)))
    if strand < edges.x + BRISTLE_OUTER or strand >= edges.y - BRISTLE_OUTER:
        own = period * lerpf(BRISTLE_OUTER_RUN.x, BRISTLE_OUTER_RUN.y, hash21(Vector2(strand, salt + 5.0)))
    own = maxf(own, 1.0)
    var run := value_noise(Vector2(run_at / own + phase, 3.7 * strand + salt))
    var presence := smoothstep(BRISTLE_BREAK.x, BRISTLE_BREAK.y, run)
    var swell := value_noise(Vector2(run_at / (own * STRAND_SWELL_RUN) + phase, 5.3 * strand + salt + 11.0))
    var drawn := hash21(Vector2(strand, salt + 1.0))
    var half_width := lerpf(STRAND_WIDTH.x, STRAND_WIDTH.y, drawn * drawn) * values[NoiseFieldsScript.SLOT_STRAND_WIDTH]
    var taper := values[NoiseFieldsScript.SLOT_STRAND_TAPER]
    half_width *= (
        (1.0 + STRAND_SWELL * (2.0 * swell - 1.0)) * (presence if taper >= 1.0 else lerpf(1.0, presence, maxf(taper, 0.0)))
    )
    half_width = maxf(half_width, 0.001)
    var draw := minf(
        hash21(Vector2(strand, salt + 7.0)) * 2.0 * clampf(values[NoiseFieldsScript.SLOT_STRAND_SOFT], 0.0, 1.0), 1.0
    )
    var soft := lerpf(STRAND_SOFT.x, STRAND_SOFT.y, draw)
    var off_middle := absf(cells - middle)
    var core := 1.0 - smoothstep(0.5 * half_width * (1.0 - soft), half_width, off_middle)
    var skirt_from := half_width * (1.0 + (BRISTLE_SKIRT_REACH - 1.0) * (1.0 - soft))
    var skirt_to := BRISTLE_SKIRT_REACH * half_width + 0.001
    var skirt := BRISTLE_SKIRT_LEVEL * (1.0 - smoothstep(skirt_from, skirt_to, off_middle))
    var cover := maxf(core, skirt) * presence
    var height := STRAND_HEIGHT_LOW + (1.0 - STRAND_HEIGHT_LOW) * hash21(Vector2(strand, salt + 3.0))
    var reach := BRISTLE_REACH * fposmod(hash21(Vector2(0.0, salt + 4.0)) + strand * BRISTLE_STEP, 1.0)
    var needed := reach + (BRISTLE_GAP - reach) * (1.0 - cover)
    return Vector2(1.0 - needed, height)


## `noise_picture`, the mask turned, tiled and read between its four nearest
## texels, as the kernel's linear, repeating sampler reads it, and spread from
## the picture's tone range as the kernel spreads it. A middle grey
## with no mask, where the kernel would read its white stand-in and paint as if
## solid, because a grey is what the sensor answers for no texture.
static func _picture(values: PackedFloat32Array, mask: Image, point: Vector2) -> float:
    if mask == null or mask.is_empty():
        return SaSensor.NEUTRAL_TEXTURE
    var scale := maxf(values[5], 0.01)
    var angle := deg_to_rad(values[6])
    var c := cos(angle)
    var s := sin(angle)
    var turned := Vector2(point.x * c + point.y * s, -point.x * s + point.y * c)
    var size := Vector2(mask.get_size())
    var tile := size * scale
    var uv := turned / tile
    uv -= uv.floor()
    var texel := uv * size - Vector2(0.5, 0.5)
    var low := texel.floor()
    var t := texel - low
    var width := mask.get_width()
    var height := mask.get_height()
    var x0 := posmod(int(low.x), width)
    var y0 := posmod(int(low.y), height)
    var x1 := posmod(x0 + 1, width)
    var y1 := posmod(y0 + 1, height)
    var top := lerpf(mask.get_pixel(x0, y0).r, mask.get_pixel(x1, y0).r, t.x)
    var bottom := lerpf(mask.get_pixel(x0, y1).r, mask.get_pixel(x1, y1).r, t.x)
    var grey := lerpf(top, bottom, t.y)
    if values.size() <= NoiseFieldsScript.SLOT_TONE_HIGH:
        return clampf(grey, 0.0, 1.0)
    var tone_low := values[NoiseFieldsScript.SLOT_TONE_LOW]
    var span := maxf(values[NoiseFieldsScript.SLOT_TONE_HIGH] - tone_low, 0.001)
    return clampf((grey - tone_low) / span, 0.0, 1.0)
