## The smudge stage's field: the picture under a smearing tip, carried on the
## GPU cell by cell, so a dab lays what stood under each of its texels rather
## than one mean colour over the whole tip.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **Why a mean is not enough.** `smudge_pickup.gmacs` reduces the paint under a
## dab to one colour, which is the carry a dab lays everywhere inside its tip. At
## a small radius that reads as a smudge, because a few texels of paint are one
## colour anyway. At Oil Smudge's two hundred pixels it is the mean of
## everything the tip covers, so a stroke across dots in four hues laid one grey
## and the hues were gone. The field keeps the same picture the mean was taken
## of, on a lattice of at most [constant SIDE] cells a side, and the dab reads
## its own texel off it through `sa_smudge_blurred`.
##
## **A lattice fixed to the tip, which is what drags.** Cell *k* is the same
## place under the tip on every dab of the stroke, so what a cell held on the
## last dab is what stood a step back along the stroke, and the paint travels
## with the tip. Each dab then mixes every cell towards the paint under it now
## at the pickup rate, as the mean was mixed, so a dot dragged off its place
## leaves a streak of its own colour that thins by the rate over the next few
## dabs and mixes with what it meets. The lattice of [SaSmudgeBlur] is anchored
## on the document instead, because a blur must not drag.
##
## **The carry's own layout, so no dab kernel changes.** The field writes the
## lattice into the carry's rows from 1 down and the frame into texels 2 and 3
## of row 0, which is where the blur writes them and where `dab_texel.gmacs`
## already reads them bilinearly. A cell holds its colour times its load and the
## load in alpha, so a cell over bare canvas pulls nothing towards black and the
## dab thins there, the carry's load made per cell.
##
## **The work is the lattice's, never the canvas's.** One dispatch a dab over at
## most [constant SIDE] by [constant SIDE] cells whatever the radius, each
## reading at most [constant SAMPLES] by [constant SAMPLES] texels of the
## stroke's snapshot, recorded into the queue the reservoir sends and never read
## back (hard rules 1 and 2).
##
## **Its own class, held by the reservoir.** [SaSmudgeReservoir] makes one on the
## first dab of a smearing stroke whose brush asked to carry a picture, and
## drops it with the stroke (hard rule 4).
class_name SaSmudgeField
extends RefCounted

## The kernel's name, one stage.
const KERNEL: String = "smudge_field"

## The most cells the lattice has along either axis. The carry is square at this
## side and the dab's box is square at the tip's widest, so a cell is never
## finer than the tip's width over this.
const SIDE: int = 64

## The most snapshot texels a cell's average reads along each axis, the number
## and the reason of [constant SaSmudgeBlur.SAMPLES]: a cell of eight pixels or
## fewer is averaged whole, and a larger one at eight evenly spaced.
const SAMPLES: int = 8

## The carry a stroke that carries a picture holds: the reservoir's own texels
## and the lattice's frame in row 0, and the lattice in the rows below it. The
## blur's carry is the same shape, because the dab reads both the same way.
const CARRY := Vector2i(SIDE, SIDE + 1)

## The texture group's side, the eight by eight every kernel runs at.
const GROUP: int = 8

## The lattice the last [method record] dispatched, for a dump that says how
## small the dispatch a dab pays for is. Null before the first dab.
var lattice: Plan = null

## The lattice's own memory, the cells as the kernel last left them, apart from
## the carry's rows the dab reads, because a brush in another blend mode has
## the meeting with its colour written over those. Null without a device.
var held: SaTexture = null

var _compute: SaCompute = null
## The snapshot's format, which [method bind] was last handed.
var _format: int = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT


## The kernel, or nothing when the device is missing.
func _init() -> void:
    if GlobalShaderCompiler.get_rd() == null:
        return
    _compute = SaCompute.new(KERNEL)
    held = SaTexture.new(Vector2i(SIDE, SIDE))
    held.clear(Color(0.0, 0.0, 0.0, 0.0))


## Compiles the kernel at *format*, beside the pickup's, for the reason
## [method SaSmudgeReservoir.warm] gives.
static func warm(format: int) -> void:
    if GlobalShaderCompiler.get_rd() == null:
        return
    SaCompute.new(KERNEL).use_storage_format(format)


## The lattice one dab carries, laid out over *region*, the dab's box in
## document pixels, for a dab centred on *centre* that takes *pickup* of the
## paint under each cell and keeps *keep* of what it held.
##
## Two pixels past the box, because the box the brush hands the pickup is the
## tip's own cut to whole pixels and the dab's last texels lie in the cut, which
## is the margin [method SaSmudgeBlur.plan] takes for the same reason.
static func plan(region: Rect2i, centre: Vector2, pickup: float, keep: float) -> Plan:
    var box := region.grow(2)
    var widest := maxf(float(box.size.x), float(box.size.y))
    var cell := maxi(1, ceili(widest / float(SIDE)))
    var count := Vector2i(
        clampi(ceili(float(box.size.x) / float(cell)), 1, SIDE), clampi(ceili(float(box.size.y) / float(cell)), 1, SIDE)
    )
    return Plan.new(box.position, count, cell, centre, pickup, keep)


## Binds *source*, the stroke's snapshot, and *carry* for the records that
## follow, and *mixed*'s two images where the kernel stages a mix in the
## brush's own blend mode, or the stand-in on both when *mixed* is null.
func bind(source: SaTexture, carry: SaTexture, mixed: SaSmudgeMix = null) -> void:
    if _compute == null:
        return
    _format = source.format
    _compute.use_storage_format(_format)
    _compute.set_texture(0, source.rid)
    _compute.set_texture(1, carry.rid)
    _compute.set_texture(2, held.rid)
    var spare := SaSmudgeReservoir.stand_in()
    _compute.set_texture(3, mixed.under.rid if mixed != null else spare.rid)
    _compute.set_texture(4, mixed.over.rid if mixed != null else spare.rid)


## One dab's pass over *planned*, waiting for the pickup that wrote the carry
## before it, over a snapshot whose texel (0, 0) is document pixel *origin* and
## which holds *scale* texels to a pixel. *first* is the stroke's first dab,
## which starts every cell from the paint under it. *mixing* stages the cells'
## mix for the brush's own blend mode, for [SaSmudgeMix] to composite.
func record(planned: Plan, origin: Vector2i, scale: float, first: bool, mixing: bool = false) -> SaCompute.Recorded:
    if _compute == null:
        return null
    lattice = planned
    var params := planned.params(origin, scale, first)
    params.append(1.0 if mixing else 0.0)
    _compute.set_push_constant_float_array(params)
    var groups := Vector2i(ceili(planned.count.x / float(GROUP)), ceili(planned.count.y / float(GROUP)))
    return _compute.record(KERNEL, _format, groups.x, groups.y, 1, true)


## One dab's lattice, in document pixels, and the push constant it becomes once
## the snapshot it reads is known.
class Plan:
    extends RefCounted

    ## The lattice's first pixel, the corner of its first cell.
    var corner: Vector2i
    ## How many cells the dab carries, along x and y.
    var count: Vector2i
    ## A cell's side, in whole document pixels.
    var cell: int
    ## The dab's centre, in document pixels.
    var centre: Vector2
    ## How much of the paint under a cell enters it on this dab.
    var pickup: float
    ## The smear length: how much of its load a cell keeps through a dab.
    var keep: float

    func _init(at: Vector2i, cells: Vector2i, side: int, middle: Vector2, taken: float, kept: float) -> void:
        corner = at
        count = cells
        cell = side
        centre = middle
        pickup = taken
        keep = kept

    ## The document rectangle the pass reads, which the snapshot has to hold.
    func wanted() -> Rect2i:
        return Rect2i(corner, count * cell)

    ## The push constant over a snapshot whose texel (0, 0) is document pixel
    ## *origin*, at *scale* texels a pixel, on the stroke's *first* dab or a
    ## later one.
    ##
    ## A cell's centre is the middle of its pixels, half a pixel less than half
    ## its side past its corner, in the sense the dab's own coordinates give a
    ## pixel, which is its index.
    func params(origin: Vector2i, scale: float, first: bool) -> PackedFloat32Array:
        var at := Vector2(corner - origin) * scale
        var middle := (centre - Vector2(corner) - Vector2.ONE * (float(cell) - 1.0) * 0.5) / float(cell)
        var side := float(cell) * scale
        return PackedFloat32Array(
            [
                at.x,
                at.y,
                side,
                float(mini(ceili(side), SAMPLES)),
                float(count.x),
                float(count.y),
                middle.x,
                middle.y,
                1.0 / float(cell),
                pickup,
                keep,
                1.0 if first else 0.0,
            ]
        )
