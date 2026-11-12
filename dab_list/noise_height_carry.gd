## What a noise stroke carries ahead of itself, a lane at a time across its
## width: two loads a lane, the tallest surface it crossed and the paint it
## crossed on the layer it paints, each as carried and as the stretch before
## found, and the sums of what the last stretch found, all on the GPU, which
## `noise_height_carry.gmacs` folds together once an update before the
## stretch that lays the loads down. The loads and their rules are
## `noise_push.gmacs`'s beside this file. The name says height, and the paint
## rides the same lanes.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **The old paint is pushed ahead of the stroke**, the way a loaded bristle
## pushes the wet paint it meets, its height and its colour. Before the mix,
## `noise_dab` takes what stands under each texel its tip covers into the
## lane's sums, raises the surface towards the lane's height load and mixes the
## paint load's colour into what it lays, and the fold hands the sums to the
## next stretch, which takes them up along its length. So the stroke picks the
## old paint up under one stretch and lays it down ahead of itself from the
## next, a lane at a time, so a ridge of the grain is pushed along its own line
## and a band of colour smears out along the streaks that crossed it. The
## tallest height rather than the mean, because what a stroke pushes is what
## stands up in its way, and a mean lies under the brush's own height and never
## shows. The mean colour, because a colour has no tallest.
##
## **How far a push reaches is the tip's radius**, [constant REACH] of it, the
## engine's weight: a load picked up full is laid out to nothing that far along
## the path, inside a stretch and over the stretches after it alike. So a push
## reaches as far at any pen speed, whether a stretch is two pixels or forty. A
## reach of one radius, with a height falling by 1/e every reach, reads as no
## push at all.
##
## **Made by the stroke's first stretch that lays height and dropped with the
## stroke**, by the dab list that lays both, since the loads are the stroke's
## own. Nothing is read back: the kernel folds what the last stretch found, and
## the CPU only says how far the path went, which the stretch measures.
extends RefCounted

## The kernel that folds the sums into the loads.
const KERNEL := "noise_height_carry"
## The lanes the stroke's width is cut into, the kernels' `NOISE_CARRY_LANES`.
const LANES: int = 32
## The floats a lane's loads take and the integers its sums take, the
## kernels' `NOISE_CARRY_FLOATS` and `NOISE_FOUND_INTS`.
const CARRY_FLOATS: int = 12
const FOUND_INTS: int = 8
## How far a full load is laid out to nothing, in the tip's radii, the
## engine's weight, set against how a stripe dragged across a band looks at
## 100 % zoom.
const REACH: float = 3.0

## The loads, [constant CARRY_FLOATS] a lane, and the sums,
## [constant FOUND_INTS] a lane, for [member images] images. Null without a
## device.
var carry: SaCompute.Buffer = null
var found: SaCompute.Buffer = null
## How many images' lanes the buffers hold, made for the first stretch's and
## made again, empty, when a stretch paints more.
var images: int = 0

var _compute: SaCompute = null
## The length of path the last stretch painted and the reach it was laid at,
## which the next fold weighs. Nought before the stroke's first stretch.
var _painted: float = 0.0
var _reach: float = 1.0
## One lane carrying nothing and its sums at nought, what a stroke that lays no
## height binds, since a uniform set covers every binding the kernel declares.
static var _carry_none: SaCompute.Buffer = null
static var _found_none: SaCompute.Buffer = null


## Holds lanes for *count* images, the carry empty if it held fewer.
func room_for(count: int) -> void:
    if count <= images or GlobalShaderCompiler.get_rd() == null:
        return
    images = count
    carry = SaCompute.Buffer.new(_zeros(images * LANES * CARRY_FLOATS))
    found = SaCompute.Buffer.new(_zeros(images * LANES * FOUND_INTS))
    _painted = 0.0


## The fold of the sums the last stretch found into the loads, recorded for
## the list that lays the next one, or null before any stretch was laid.
func fold() -> SaCompute.Recorded:
    if carry == null or _painted <= 0.0:
        return null
    if _compute == null:
        _compute = SaCompute.new(KERNEL)
    _compute.set_storage("push_carry", carry.rid)
    _compute.set_storage("push_found", found.rid)
    _compute.set_params({"lane_count": float(images * LANES), "painted": _painted, "reach": _reach})
    _painted = 0.0
    return _compute.record(KERNEL, RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT, ceili(images * LANES / 8.0), 1, 1, true)


## Notes a stretch laid: *painted* pixels of path, at a reach of *reach*.
func laid(painted: float, reach: float) -> void:
    _painted += painted
    _reach = reach


## How far a tip of major radius *radius* lays a full load out to nothing, in
## document pixels.
static func reach_for(radius: float) -> float:
    return maxf(radius * REACH, 0.5)


## Binds the two buffers on *compute*.
func bind(compute: SaCompute) -> void:
    if carry == null or found == null:
        bind_none(compute)
        return
    compute.set_storage("push_carry", carry.rid)
    compute.set_storage("push_found", found.rid)


## Makes the stand-ins, so the first stretch that lays no height does not.
static func warm() -> void:
    bind_none(SaCompute.new(KERNEL))


## Binds the stand-ins on *compute*, for a stretch that lays no height.
static func bind_none(compute: SaCompute) -> void:
    if _carry_none == null and GlobalShaderCompiler.get_rd() != null:
        _carry_none = SaCompute.Buffer.new(_zeros(CARRY_FLOATS))
        _found_none = SaCompute.Buffer.new(_zeros(FOUND_INTS))
    if _carry_none != null:
        compute.set_storage("push_carry", _carry_none.rid)
        compute.set_storage("push_found", _found_none.rid)


static func _zeros(count: int) -> PackedByteArray:
    var bytes := PackedByteArray()
    bytes.resize(count * 4)
    return bytes
