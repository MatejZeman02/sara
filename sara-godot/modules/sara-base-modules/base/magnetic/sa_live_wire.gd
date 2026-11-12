## The cheapest path from the trace's last anchor to any cell of the cost
## window, the search of Mortensen and Barrett's intelligent scissors.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Dijkstra's search out of the anchor over the links `SaMagneticCost` read
## back, a byte a link, so every distance is a whole number and the queue is
## Dial's: one bucket a distance, 256 of them round a ring, since no link costs
## more than 255. That is the paper's own active list, and it keeps a push and
## a pop as cheap as an append and a pop.
##
## **The search runs on the fly**, as the paper's section 3.3 has it: it
## settles cells out of the anchor only until the cell the pointer asks for is
## settled, and keeps its queue for the next ask. A pointer moving about near
## the anchor asks for cells already settled, which costs a walk back along
## the path, and one moving out settles the ring it crossed and no more. A
## *budget* caps what one ask settles, so a frame never waits on the whole
## window, and a cell reached but not yet settled answers the path it has so
## far, which the next ask makes good.
##
## The window's outer ring of cells is settled before the search starts, so
## no step out of a cell ever looks past the window and the loop needs no
## bounds test.
extends RefCounted

## What a cell's distance reads before any path reaches it.
const UNREACHED: int = 0x3fffffff
## Distances apart that two buckets of the ring stand, one more than the
## costliest link.
const RING: int = 256

## Cells along a side of the window, and the cell the search starts from.
var side: int = 0
var start: int = -1
## How many cells the searches since [method begin] have settled, which the
## suite reads to see the search stop where it was asked to.
var settled: int = 0

var _bytes: PackedByteArray = PackedByteArray()
var _distance: PackedInt32Array = PackedInt32Array()
## The step that reached each cell, 0 to 7 in the kernel's order, and 255 for
## the start and for a cell no path has reached.
var _from: PackedByteArray = PackedByteArray()
var _done: PackedByteArray = PackedByteArray()
var _buckets: Array[Array] = []
## The distance whose bucket the search empties next, and how many cells sit
## in the buckets, stale ones included.
var _at: int = 0
var _queued: int = 0
## The step to each of the eight neighbours, in cells of the flat array.
var _steps: PackedInt32Array = PackedInt32Array()


## Starts a search over *bytes*, `SaMagneticCost`'s twelve a cell for a window
## *cells* across, from the cell *from*.
func begin(bytes: PackedByteArray, cells: int, from: Vector2i) -> void:
    _bytes = bytes
    side = cells
    var count := cells * cells
    _distance = PackedInt32Array()
    _distance.resize(count)
    _distance.fill(UNREACHED)
    _from = PackedByteArray()
    _from.resize(count)
    _from.fill(255)
    _done = PackedByteArray()
    _done.resize(count)
    for i in cells:
        _done[i] = 1
        _done[count - cells + i] = 1
        _done[i * cells] = 1
        _done[i * cells + cells - 1] = 1
    _steps = PackedInt32Array([1, cells + 1, cells, cells - 1, -1, -cells - 1, -cells, -cells + 1])
    _buckets = []
    for _i in RING:
        _buckets.append([])
    _at = 0
    _queued = 0
    settled = 0
    var clamped := clamp_cell(from)
    start = clamped.y * cells + clamped.x
    _done[start] = 0
    _distance[start] = 0
    _buckets[0].append(start)
    _queued = 1


## *at* moved inside the window's searched part, a cell in from its outer ring.
func clamp_cell(at: Vector2i) -> Vector2i:
    return Vector2i(clampi(at.x, 1, side - 2), clampi(at.y, 1, side - 2))


## Settles cells until *target* is settled, the queue is empty or *budget*
## cells have been settled. True when *target* is settled.
func reach(target: Vector2i, budget: int) -> bool:
    if start < 0:
        return false
    var goal := target.y * side + target.x
    if _done[goal] != 0 and _distance[goal] < UNREACHED:
        return true
    var left := budget
    var empty_run := 0
    var bytes := _bytes
    var distance := _distance
    var from := _from
    var done := _done
    var steps := _steps
    while _queued > 0 and left > 0:
        var bucket: Array = _buckets[_at & 255]
        if bucket.is_empty():
            _at += 1
            empty_run += 1
            if empty_run > RING:
                break
            continue
        empty_run = 0
        var here: int = bucket.pop_back()
        _queued -= 1
        if done[here] != 0:
            continue
        done[here] = 1
        settled += 1
        left -= 1
        var base := here * 12
        var far := _at
        for k in 8:
            var next := here + steps[k]
            if done[next] != 0:
                continue
            var through := far + bytes[base + k]
            if through < distance[next]:
                distance[next] = through
                from[next] = k
                (_buckets[through & 255] as Array).append(next)
                _queued += 1
        if here == goal:
            break
    # Packed arrays are values in GDScript, so the locals the loop wrote are
    # handed back to the fields they were copied from.
    _distance = distance
    _from = from
    _done = done
    return done[goal] != 0 and distance[goal] < UNREACHED


## Whether *target* is settled, so its path is the cheapest there is.
func settles(target: Vector2i) -> bool:
    var at := target.y * side + target.x
    return _done[at] != 0 and _distance[at] < UNREACHED


## Whether a path reaches *target* yet, settled or not.
func reached(target: Vector2i) -> bool:
    return _distance[target.y * side + target.x] < UNREACHED


## The cells from the start to *target*, the start first, along the cheapest
## path found so far. Empty when no path reaches *target*.
func path(target: Vector2i) -> PackedInt32Array:
    var cells := PackedInt32Array()
    var at := target.y * side + target.x
    if start < 0 or _distance[at] >= UNREACHED:
        return cells
    var guard := side * side
    while at != start and guard > 0:
        cells.append(at)
        var k := _from[at]
        if k > 7:
            break
        at -= _steps[k]
        guard -= 1
    cells.append(start)
    cells.reverse()
    return cells


## Where in cell *at* the edge's middle lies, in cells from the cell's own
## middle, the tenth and eleventh bytes the kernel wrote for it.
func shift(at: int) -> Vector2:
    var base := at * 12
    return Vector2(float(_bytes[base + 9]) - 128.0, float(_bytes[base + 10]) - 128.0) / 254.0


## The cell's own cost, nought on a strong edge and 255 on flat ground, the
## ninth byte the kernel wrote for it.
func own_cost(at: Vector2i) -> int:
    return _bytes[(at.y * side + at.x) * 12 + 8]
