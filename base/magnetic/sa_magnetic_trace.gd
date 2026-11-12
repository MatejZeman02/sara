## One trace of the Magnetic Lasso: its anchors, the segments between them,
## and the live path from the last anchor to the pointer.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **The window.** Each time an anchor is laid or taken away, a cost window
## of `SaMagneticCost.SIDE` cells is weighed round the last anchor and the
## search starts again from it. A pointer that leaves the window lays an
## anchor where the live path meets the window's edge, so the trace follows a
## hand of any reach.
##
## **The pointer's snap.** The live path ends on the cheapest cell within the
## Width option of the pointer, the paper's cursor snap, so a hand a few pixels
## off the edge still draws along it. Where no cell within reach is any edge,
## it ends under the pointer.
##
## **Path cooling**, the paper's section 4. A cell that has stayed on the live
## path through [constant COOL_UPDATES] updates in a row is cooled, and once
## the cooled part of the path reaches [method spacing] cells from the last
## anchor an anchor is laid at its far end. The Frequency option sets the
## spacing, so a high one lays anchors close together and nought lays none
## but the clicks.
##
## **Freehand.** While Alt is held the live path is a straight line from the
## last anchor to the pointer, and a drag with the button down draws freehand,
## as Photoshop's tool does. Letting Alt go makes what was drawn a segment and
## its end an anchor, and the magnetic path takes over from there.
extends RefCounted

const SaMagneticCostScript = preload("res://modules/sara-base-modules/base/magnetic/sa_magnetic_cost.gd")
const SaLiveWireScript = preload("res://modules/sara-base-modules/base/magnetic/sa_live_wire.gd")

## Updates in a row a cell has to stay on the live path to be cooled.
const COOL_UPDATES: int = 6
## Cells one update of the pointer settles at the most, about four
## milliseconds of the search, so a move never waits on the whole window. The
## rest is settled by the next updates and by [method tick].
const BUDGET: int = 1500
## Cells kept between the pointer and the window's edge. A pointer nearer the
## edge than this lays an anchor and the window moves.
const MARGIN: int = 8
## The own cost, of 255, below which a cell within the Width counts as an
## edge for the snap. Above it the pointer's own cell is the end.
const SNAP_COST: int = 200

## The anchors in document pixels, the first where the trace began.
var anchors: PackedVector2Array = PackedVector2Array()
## The live path, the last anchor first and its end last, in document pixels.
var live: PackedVector2Array = PackedVector2Array()
## The snap's reach in cells, the contrast in Oklab units a pixel and the
## frequency, 0 to 1, as the tool's options set them before an update.
var width_cells: int = 5
var contrast: float = 0.01
var frequency: float = 0.57
## How many times the window was weighed, read by the suite.
var windows: int = 0

## The segments laid so far, segment i from anchor i to anchor i + 1.
var _segments: Array[PackedVector2Array] = []
var _cost := SaMagneticCostScript.new()
var _wire := SaLiveWireScript.new()
## Answers what the cost reads, `[space, merged, layer]`, asked each time a
## window is weighed so a layer shown a moment ago is in it.
var _picture: Callable = Callable()
var _cell: float = 1.0
## The cell the live path ends on, and how many updates in a row each cell of
## the path, counted from the anchor, has stood where it stands.
var _target: Vector2i = Vector2i.ZERO
var _path: PackedInt32Array = PackedInt32Array()
var _ages: PackedInt32Array = PackedInt32Array()
## The path's cells the last cooling read, to tell which still stand.
var _path_was: PackedInt32Array = PackedInt32Array()
## Where the pointer was at the last [method move], in document pixels.
var _pointer: Vector2 = Vector2.ZERO
## The freehand part under way while Alt is held, the last anchor first.
var _free: PackedVector2Array = PackedVector2Array()


## Starts a trace at *at*, in document pixels, with cells *cell* document
## pixels across, reading the picture *picture* answers.
func _init(at: Vector2, cell: float, picture: Callable) -> void:
    _cell = maxf(cell, 1.0)
    _picture = picture
    anchors = PackedVector2Array([at])
    live = PackedVector2Array([at])
    _pointer = at
    _weigh()


## Whether a freehand part is under way.
func drawing_freehand() -> bool:
    return not _free.is_empty()


## Moves the live path's end to the pointer at *at*.
func move(at: Vector2) -> void:
    if drawing_freehand():
        return
    _pointer = at
    if not _inside(_cost.to_cell(at)) and live.size() > 2:
        # Off the window, so the path so far becomes a segment and the window
        # moves to stand round its end.
        _lay(live.size() - 1)
    _aim()
    if _cool():
        _aim()


## Settles more of the search towards the pointer's cell when the last update
## did not reach it. True when the live path changed.
func tick() -> bool:
    if drawing_freehand() or _wire.start < 0 or _wire.settles(_target):
        return false
    _search()
    return true


## Lays an anchor at the live path's end, a click's anchor.
func click() -> void:
    if drawing_freehand():
        _free.append(_free[_free.size() - 1])
        return
    if live.size() >= 2:
        _lay(live.size() - 1)


## Starts or carries on the freehand part to *at*, with Alt held. *drawing*
## says the button is down, so the point is kept, and up it is the straight
## line's end alone.
func freehand(at: Vector2, drawing: bool) -> void:
    if _free.is_empty():
        _free = PackedVector2Array([anchors[anchors.size() - 1]])
    if drawing:
        _free.append(at)
        live = _free.duplicate()
        return
    live = _free.duplicate()
    live.append(at)


## Alt was let go: what the freehand part drew becomes a segment, its end an
## anchor, and the magnetic path takes over from there.
func end_freehand() -> void:
    if _free.size() < 2:
        _free = PackedVector2Array()
        return
    var drawn := _free
    _free = PackedVector2Array()
    _segments.append(drawn)
    anchors.append(drawn[drawn.size() - 1])
    _weigh()


## Takes the last anchor away and the segment that led to it. False when only
## the first is left, which the tool takes as the trace abandoned.
func back() -> bool:
    _free = PackedVector2Array()
    if anchors.size() <= 1:
        return false
    anchors.remove_at(anchors.size() - 1)
    _segments.pop_back()
    _weigh()
    return true


## The outline as it stands: every segment, then the live path.
func outline() -> PackedVector2Array:
    var points := PackedVector2Array()
    for segment: PackedVector2Array in _segments:
        points = _join(points, segment)
    return _join(points, live)


## The outline closed back to the first anchor: the live path's end runs on
## along the cheapest path to it when the window holds it, and in a straight
## line when it does not.
func closed() -> PackedVector2Array:
    var points := outline()
    var first := anchors[0]
    var cell := _cost.to_cell(first)
    if anchors.size() > 1 and not drawing_freehand() and _inside(cell):
        var home := _wire.clamp_cell(cell)
        _wire.reach(home, _wire.side * _wire.side)
        var back_home := _points_of(_wire.path(home))
        if back_home.size() >= 2:
            back_home[back_home.size() - 1] = first
            # The path to the first anchor starts at the last anchor, so it
            # replaces the live path rather than running on from its end.
            points = PackedVector2Array()
            for segment: PackedVector2Array in _segments:
                points = _join(points, segment)
            points = _join(points, back_home)
    if points.size() > 1 and points[points.size() - 1].is_equal_approx(first):
        points.remove_at(points.size() - 1)
    return points


## A segment from anchor *index* of the live path's points is laid: the path
## up to it is kept and an anchor stands at its end.
func _lay(index: int) -> void:
    var segment := live.slice(0, index + 1)
    if segment.size() < 2:
        return
    _segments.append(segment)
    anchors.append(segment[segment.size() - 1])
    _weigh()


## The live path to the pointer's snapped cell in the window as it stands.
func _aim() -> void:
    _target = _snap(_wire.clamp_cell(_cost.to_cell(_pointer)))
    _search()


## A new window round the last anchor, and a search from it.
func _weigh() -> void:
    var anchor := anchors[anchors.size() - 1]
    var half := float(SaMagneticCostScript.SIDE) * 0.5 * _cell
    var corner := ((anchor - Vector2(half, half)) / _cell).floor() * _cell
    var said: Array = _picture.call() if _picture.is_valid() else [null, null, null]
    var bytes: PackedByteArray = _cost.window(said[0], corner, _cell, contrast, said[1], said[2])
    windows += 1
    live = PackedVector2Array([anchor])
    _path = PackedInt32Array()
    _ages = PackedInt32Array()
    if bytes.is_empty():
        _wire.start = -1
        return
    _wire.begin(bytes, SaMagneticCostScript.SIDE, _cost.to_cell(anchor))
    _target = _wire.clamp_cell(_cost.to_cell(anchor))


## The search towards the target, and the live path it gives.
func _search() -> void:
    if _wire.start < 0:
        live = PackedVector2Array([anchors[anchors.size() - 1], _cost.to_document(_target)])
        return
    _wire.reach(_target, BUDGET)
    if not _wire.reached(_target):
        return
    _path = _wire.path(_target)
    live = _points_of(_path)


## Ages the cells of the live path and lays an anchor where the cooled part
## has reached the spacing the Frequency asks for. True when it laid one.
func _cool() -> bool:
    var spacing := spacing_cells()
    if spacing <= 0 or _path.is_empty():
        _ages = PackedInt32Array()
        return false
    var ages := PackedInt32Array()
    ages.resize(_path.size())
    var kept := mini(_path.size(), _ages.size())
    var was: PackedInt32Array = _ages
    var cooled := -1
    for i in _path.size():
        var age := 1
        if i < kept and i < _path_was.size() and _path_was[i] == _path[i]:
            age = was[i] + 1
        ages[i] = age
        if age >= COOL_UPDATES:
            cooled = i
    _ages = ages
    _path_was = _path.duplicate()
    if cooled < spacing or cooled >= live.size() - 1:
        return false
    _lay(cooled)
    _path_was = PackedInt32Array()
    return true


## The cells of cooled path an anchor waits for, from the Frequency, or
## nought for none: 120 cells at a frequency near nought down to 10 at one.
func spacing_cells() -> int:
    if frequency <= 0.0:
        return 0
    return int(round(lerpf(120.0, 10.0, clampf(frequency, 0.0, 1.0))))


## The cheapest cell within the Width of *cell*, the nearer one on a tie,
## while it is an edge at all, and *cell* itself when none within reach is.
func _snap(cell: Vector2i) -> Vector2i:
    if _wire.start < 0 or width_cells <= 0:
        return cell
    var best := cell
    var best_cost := _wire.own_cost(cell)
    var best_far := 0
    var reach := width_cells
    for dy in range(-reach, reach + 1):
        for dx in range(-reach, reach + 1):
            var far := dx * dx + dy * dy
            if far > reach * reach:
                continue
            var at := _wire.clamp_cell(cell + Vector2i(dx, dy))
            var cost := _wire.own_cost(at)
            if cost < best_cost or (cost == best_cost and far < best_far):
                best = at
                best_cost = cost
                best_far = far
    return best if best_cost < SNAP_COST else cell


## Whether *cell* lies inside the window, the margin in from its edge.
func _inside(cell: Vector2i) -> bool:
    var side := SaMagneticCostScript.SIDE
    return cell.x >= MARGIN and cell.y >= MARGIN and cell.x < side - MARGIN and cell.y < side - MARGIN


## The document pixels of the cells *path* names, the last anchor's own place
## for the first.
func _points_of(path: PackedInt32Array) -> PackedVector2Array:
    var points := PackedVector2Array()
    var side := SaMagneticCostScript.SIDE
    for at: int in path:
        @warning_ignore("integer_division")
        var middle := _cost.to_document(Vector2i(at % side, at / side))
        points.append(middle + _wire.shift(at) * _cost.cell)
    if not points.is_empty():
        points[0] = anchors[anchors.size() - 1]
    return points


## *points* with *more* after them, leaving out its first point where it
## repeats the last one there.
static func _join(points: PackedVector2Array, more: PackedVector2Array) -> PackedVector2Array:
    var joined := points
    for i in more.size():
        if i == 0 and not joined.is_empty() and joined[joined.size() - 1].is_equal_approx(more[0]):
            continue
        joined.append(more[i])
    return joined
