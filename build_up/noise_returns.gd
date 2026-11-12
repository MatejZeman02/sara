## The path a noise stroke has laid so far, kept for the kernel's
## `noise_build_up`, which reads it to say where the pen came back over paint
## the same stroke laid, so a scrub builds up while a single pass stays a wash.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **A point every quarter of a radius.** Every line the stretch sends passes
## through [method send], and each of its points further along the path than
## the newest kept, and a quarter of its tip's radius past it, is kept with
## where it lies, its place and its tip's radius, the round disc of the tip at
## its widest. A quarter of a radius apart, the discs leave less than a
## hundredth of a radius of the swept band between them uncovered. The place
## is the length of path from the press, and not the along the field is read
## at, which a Drift row grows by a share of the path only, so a gap counted
## in along asks a drifting brush for several times the path.
##
## **Only what can reach the stretch is sent.** A texel looks at every point
## the buffer holds, so the buffer holds only the points that lie at least
## [constant GAP] radii of path behind the stretch's newest, the kernel's own
## gap, and whose disc reaches the stretch's box grown by a radius, which
## covers the front laid under the pen past it too. A straight stroke and a
## turn send none and run the wash they always did. Past [constant MOST] the
## rest are left out, and the texels they cover take the wash.
##
## **The front reads the body's points.** The front under the pen is laid
## through the same kernel from a buffer of its own, and binds this buffer
## too, so the end it shows under the pen builds up where the body will.
extends RefCounted

const NoiseStretchScript = preload("res://modules/sara-noise-brush-engine/dab_list/noise_stretch.gd")

## The kernel's `NOISE_RETURN_GAP`, the radii of path back a part of the
## stroke has to lie for paint it laid to build up, and how far apart the
## points are kept, in radii.
const GAP: float = 3.0
const SPACING: float = 0.25
## The floats a point takes in the buffer, the two the header takes before
## them, and the most points one buffer carries.
const FLOATS: int = 4
const HEADER: int = 2
const MOST: int = 1024

## The points kept, [constant FLOATS] floats a point, oldest first.
var _kept := PackedFloat32Array()
## The place of the newest point a line sent, which no later line's point
## repeats.
var _newest: float = -INF
var _buffer: SaCompute.Buffer = null
var _capacity: int = 0


## Forgets the stroke before, at a press and a lift.
func clear() -> void:
    _kept = PackedFloat32Array()
    _newest = -INF


## Keeps the points of *line*, at the stretch's slots, that are new to the
## stroke, and writes to the buffer the points kept that the line can come
## back over, behind the first of *line* that no line before sent.
func send(line: PackedFloat32Array) -> void:
    @warning_ignore("integer_division")
    var count := line.size() / NoiseStretchScript.FLOATS
    var fresh := count
    var box := Rect2()
    var radius := INF
    var newest := -INF
    for index in count:
        var at := index * NoiseStretchScript.FLOATS
        var here := Vector2(line[at + NoiseStretchScript.AT], line[at + NoiseStretchScript.AT + 1])
        var place := line[at + NoiseStretchScript.PLACE]
        var reach := maxf(line[at + NoiseStretchScript.HALF_EXTENT], line[at + NoiseStretchScript.HALF_EXTENT + 1])
        var tip := Rect2(here, Vector2.ZERO).grow(2.0 * reach)
        box = tip if index == 0 else box.merge(tip)
        radius = minf(radius, reach)
        newest = maxf(newest, place)
        if place > _newest:
            fresh = mini(fresh, index)
            _keep(here, place, reach)
    _newest = maxf(_newest, newest)
    _write(box, newest - GAP * radius, fresh)


## Binds the buffer to *compute*'s `returns`, an empty one before any line.
func bind(compute: SaCompute) -> void:
    if _buffer == null:
        _write(Rect2(), -INF, 0)
    compute.set_storage("returns", _buffer.rid)


func _keep(here: Vector2, place: float, reach: float) -> void:
    var last := _kept.size() - FLOATS
    if last >= 0 and place - _kept[last + 2] < SPACING * maxf(reach, _kept[last + 3]):
        return
    _kept.append_array([here.x, here.y, place, reach])


## Writes the header and every point kept behind *before* whose disc reaches
## *box*, with *fresh* the line's first new point.
func _write(box: Rect2, before: float, fresh: int) -> void:
    var out := PackedFloat32Array([0.0, float(fresh)])
    @warning_ignore("integer_division")
    for index in _kept.size() / FLOATS:
        var at := index * FLOATS
        if _kept[at + 2] >= before or out.size() >= HEADER + MOST * FLOATS:
            continue
        if box.grow(_kept[at + 3]).has_point(Vector2(_kept[at], _kept[at + 1])):
            out.append_array(_kept.slice(at, at + FLOATS))
    @warning_ignore("integer_division")
    out[0] = float((out.size() - HEADER) / FLOATS)
    if _buffer == null or out.size() > _capacity:
        _capacity = maxi(HEADER + 64 * FLOATS, nearest_po2(out.size()))
        var room := PackedFloat32Array()
        room.resize(_capacity)
        _buffer = SaCompute.Buffer.new(room.to_byte_array())
    _buffer.update(out.to_byte_array())
