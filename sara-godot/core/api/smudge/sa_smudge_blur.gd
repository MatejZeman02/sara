## The smudge stage's blur: the paint under each dab of a blurring stroke,
## softened on a small lattice the dab reads texel by texel.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **Why a third rate.** Dulling lays the mean of the paint under each dab, one
## colour over the whole tip, so a stroke along an edge between two greys lays a
## band of their mean with an edge of its own on each side, three values where
## the painter wanted a gradient. A blur
## lays, at each texel, the paint around that texel, so the same stroke leaves a
## ramp across the edge that meets the paint on either side without a step.
##
## **A lattice of whole pixels on the document's own grid.** `smudge_blur.gmacs`
## averages the stroke's snapshot into cells [member Plan.cell] pixels across,
## blurs the cells by a Gaussian in two passes, and leaves the lattice in the
## carry's rows from 1 down, where the dab reads it bilinearly. The cells sit at
## multiples of their side in document pixels, so every dab of a stroke finds
## the same number in a cell it shares with the dab before it, and the dabs
## move a texel towards one blur rather than towards twenty a few codes apart.
##
## **The work is the lattice's, never the canvas's.** The lattice is at most
## [constant SIDE] cells across the dab's box, whatever its radius, because the
## cell grows with the dab, and the Gaussian reads at most [constant TAPS]
## cells on each side. A dab's blur is three small dispatches recorded into the
## queue its reservoir sends, between its pickup and its dab, so nothing waits
## on the CPU and nothing is read back (hard rules 1 and 2).
##
## **Its own class, held by the reservoir.** [SaSmudgeReservoir] makes one on the
## first dab of a stroke at [constant SaSmudgePage.BLURRING], and drops it with
## the stroke, so its two scratch textures go with it (hard rule 4).
class_name SaSmudgeBlur
extends RefCounted

## The kernel's name, one file and three stages.
const KERNEL: String = "smudge_blur"

## The most cells the lattice the dab reads has along either axis.
const SIDE: int = 64

## The most cells the Gaussian reads on each side of the one it blurs: three
## deviations at the widest deviation [constant SPREAD_CELLS] allows.
const TAPS: int = 12

## The Gaussian's deviation as a share of the pickup's reach, which is the dab's
## own radius times the brush's Smudge Radius. Half of it puts the ramp's foot,
## three deviations out, half a radius past the dab's rim, where the dab lays
## nothing, so the ramp meets the paint beside it within a code or two.
const SPREAD: float = 0.5

## The widest the Gaussian is, in cells. The cell is the deviation over this,
## so the blur spans the same few cells at any radius.
const SPREAD_CELLS: float = 4.0

## The most snapshot texels a cell's average reads along each axis. A cell of
## eight pixels or fewer is averaged whole, and a larger one at eight evenly
## spaced, which the Gaussian over it smooths past seeing.
const SAMPLES: int = 8

## The carry a blurring stroke holds: the reservoir's two texels and the
## lattice's place in row 0, and the lattice in the rows below it.
const CARRY := Vector2i(SIDE, SIDE + 1)

## The texture group's side, the eight by eight every kernel runs at.
const GROUP: int = 8

var _cells: SaTexture = null
var _rows: SaTexture = null
var _compute: SaCompute = null
## The snapshot's format, which [method bind] was last handed.
var _format: int = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT


## The two scratch textures and the kernel, or nothing when the device is
## missing.
func _init() -> void:
    if GlobalShaderCompiler.get_rd() == null:
        return
    _cells = SaTexture.new(Vector2i(SIDE + 2 * TAPS, SIDE + 2 * TAPS))
    _rows = SaTexture.new(Vector2i(SIDE, SIDE + 2 * TAPS))
    _compute = SaCompute.new(KERNEL)


## Compiles the kernel at *format*, beside the pickup's, for the reason
## [method SaSmudgeReservoir.warm] gives.
static func warm(format: int) -> void:
    if GlobalShaderCompiler.get_rd() == null:
        return
    SaCompute.new(KERNEL).use_storage_format(format)


## The lattice one dab reads, laid out over *region*, the dab's box in document
## pixels, for a dab centred on *centre* whose pickup reaches *reach* pixels.
static func plan(region: Rect2i, centre: Vector2, reach: float) -> Plan:
    # Two pixels past the box, because the box the brush hands the pickup is the
    # tip's own cut to whole pixels, and the dab's last texels lie in the cut.
    var box := region.grow(2)
    var spread := maxf(SPREAD * reach, 0.0)
    var widest := maxf(float(box.size.x), float(box.size.y))
    var cell := maxi(1, maxi(ceili(spread / SPREAD_CELLS), ceili(widest / float(SIDE - 4))))
    var first := Vector2i(floori(box.position.x / float(cell)) - 1, floori(box.position.y / float(cell)) - 1)
    var last := Vector2i(floori(box.end.x / float(cell)) + 1, floori(box.end.y / float(cell)) + 1)
    var deviation := maxf(spread / float(cell), 0.01)
    return Plan.new(first, last - first + Vector2i.ONE, cell, deviation, clampi(ceili(3.0 * deviation), 1, TAPS), centre)


## Binds *source*, the snapshot, and *carry* for the stages the next records
## dispatch.
func bind(source: SaTexture, carry: SaTexture) -> void:
    if _compute == null:
        return
    _format = source.format
    _compute.use_storage_format(_format)
    _compute.set_texture(0, source.rid)
    _compute.set_texture(1, _cells.rid)
    _compute.set_texture(2, _rows.rid)
    _compute.set_texture(3, carry.rid)


## The three stages of *planned*, each waiting for what came before it, over a
## snapshot whose texel (0, 0) is document pixel *origin* and which holds
## *scale* texels to a pixel.
func record(planned: Plan, origin: Vector2i, scale: float) -> Array[SaCompute.Recorded]:
    var out: Array[SaCompute.Recorded] = []
    if _compute == null or _cells == null:
        return out
    var extent := planned.count + Vector2i(2 * planned.taps, 2 * planned.taps)
    var groups: Array[Vector2i] = [extent, Vector2i(planned.count.x, extent.y), planned.count]
    for stage in range(3):
        _compute.set_push_constant_float_array(planned.params(origin, scale, float(stage)))
        var size: Vector2i = groups[stage]
        var one := _compute.record(KERNEL, _format, ceili(size.x / float(GROUP)), ceili(size.y / float(GROUP)), 1, true)
        if one != null:
            out.append(one)
    return out


## One dab's lattice, in document pixels, and the push constant each stage
## takes from it once the snapshot it reads is known.
class Plan:
    extends RefCounted

    ## The lattice's first cell, in cells from the document's corner.
    var first: Vector2i
    ## How many cells the dab reads, along x and y.
    var count: Vector2i
    ## A cell's side, in whole document pixels.
    var cell: int
    ## The Gaussian's deviation, in cells.
    var deviation: float
    ## How many cells the Gaussian reads on each side.
    var taps: int
    ## The dab's centre, in document pixels.
    var centre: Vector2

    func _init(at: Vector2i, cells: Vector2i, side: int, spread: float, reach: int, middle: Vector2) -> void:
        first = at
        count = cells
        cell = side
        deviation = spread
        taps = reach
        centre = middle

    ## The document rectangle the stages read: the lattice and the Gaussian's
    ## reach past it on every side, which the snapshot has to hold.
    func wanted() -> Rect2i:
        return Rect2i((first - Vector2i(taps, taps)) * cell, (count + Vector2i(2 * taps, 2 * taps)) * cell)

    ## The push constant of *stage* over a snapshot whose texel (0, 0) is
    ## document pixel *origin*, at *scale* texels a pixel.
    ##
    ## A cell's centre is the middle of its pixels, half a pixel less than half
    ## its side past its corner, in the sense the dab's own coordinates give a
    ## pixel, which is its index.
    func params(origin: Vector2i, scale: float, stage: float) -> PackedFloat32Array:
        var corner := Vector2((first - Vector2i(taps, taps)) * cell - origin) * scale
        var middle := (centre - Vector2.ONE * (float(cell) - 1.0) * 0.5) / float(cell) - Vector2(first)
        var side := float(cell) * scale
        return PackedFloat32Array(
            [
                corner.x,
                corner.y,
                side,
                float(mini(ceili(side), SAMPLES)),
                deviation,
                float(taps),
                float(count.x),
                float(count.y),
                middle.x,
                middle.y,
                1.0 / float(cell),
                stage,
            ]
        )
