## The cage of the transform tool's Cage mode: a polygon a painter clicks round
## the subject, its points dragged after it closes, and the dense mesh the
## picture is bent through by Green coordinates.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## In the base module, two folders below `state_transform.gd`, the one caller,
## which hands a press and a drag here in Cage mode and reads the mesh back off
## the pass. The weights are computed once, when the cage closes, at every point
## of a grid of `SIDE` by `SIDE` over the box the lift takes, and each drag
## moves the grid's points by those weights on the CPU, a few thousand
## multiply-adds. The picture is drawn through that grid by the warp kernel
## Freehand uses, so nothing is read back and the GPU work is the warp the
## tool already had.
##
## **Green coordinates, as Krita's cage.** A point inside the cage is a sum of
## the cage's points by one set of weights and of its edges' outward normals
## by another, Lipman, Levin and Cohen-Or 2008, which keeps a shape from
## shearing where mean value coordinates would. A point of the grid outside
## the cage stays where it is, so the canvas past the cage's edge is never
## moved. The mesh is written as the rest grid plus what the cage's moves
## carry, the same sum of the differences, so a cage nobody has moved gives
## the grid back exactly.
##
## The points are this object's, written by `press`, `close` and `drag` only.
## A suite closes a cage of its own by handing its points to the constructor.
class_name SaTransformCage
extends RefCounted

## The mesh's points along a side: sixteen cells a side, smooth enough for a
## cage's bend and few enough that the kernel's cell walk stays cheap.
const SIDE: int = 17

## The least points a closed cage has.
const LEAST: int = 3

## What a press did, which the tool reads to know whether a drag follows.
enum Press { NONE, PLACED, CLOSED, GRABBED }

## The cage's points in canvas positions, in the order they were clicked until
## it closes, and turned to one winding at the close.
var _points: PackedVector2Array = PackedVector2Array()
## Whether the outline has closed, read by the tool and written here only.
var closed: bool = false
## The points as the cage closed, which the weights were worked out against
## and every move is measured from.
var _at_close: PackedVector2Array = PackedVector2Array()
## The points frozen at the press, and the one it grabbed, so a drag is a
## displacement from where the point stood.
var _at_press: PackedVector2Array = PackedVector2Array()
var _grabbed: int = -1
## The box the grid lies over, the one the lift takes, and the grid at rest.
var box: Rect2i = Rect2i()
var _rest: PackedVector2Array = PackedVector2Array()
## Per point of the grid, its Green coordinates against the closed cage, the
## cage's point weights then its edge weights, or an empty array for a point
## outside the cage, which stays.
var _weights: Array[PackedFloat64Array] = []


## A cage with *clicked* already placed, which a suite closes with `close`.
func _init(clicked: PackedVector2Array = PackedVector2Array()) -> void:
    _points = clicked.duplicate()


## The cage's points as they stand, for the overlay, a dump and a suite.
func points() -> PackedVector2Array:
    return _points.duplicate()


## A press at *at*, *reach* the document pixels a point is taken from. Before
## the cage closes a press near its first point closes it over *over*, the box
## a lift would take, and any other press adds a point. Once closed a press
## near a point grabs it and a press elsewhere takes nothing.
func press(at: Vector2, reach: float, over: Rect2i) -> Press:
    if closed:
        _grabbed = SaTransformMesh.nearest(_points, at, reach)
        _at_press = _points.duplicate()
        return Press.GRABBED if _grabbed >= 0 else Press.NONE
    if _points.size() >= LEAST and _points[0].distance_to(at) <= reach:
        return Press.CLOSED if close(over) else Press.NONE
    _points.append(at)
    return Press.PLACED


## Closes the cage over *over* and works out every grid point's weights. False
## when the cage cannot close: fewer than three points, an empty box, or an
## outline that crosses itself, whose inside Green coordinates do not define.
func close(over: Rect2i) -> bool:
    if closed or _points.size() < LEAST or over.size.x <= 0 or over.size.y <= 0:
        return false
    if Geometry2D.triangulate_polygon(_points).is_empty():
        return false
    # One winding for every cage, so the outward normal is one formula.
    if Green.area(_points) < 0.0:
        _points.reverse()
    box = over
    _rest = SaTransformMesh.grid_over(SaHomography.corners_of(over), SIDE)
    _weights = []
    for point: Vector2 in _rest:
        var inside := Geometry2D.is_point_in_polygon(point, _points)
        _weights.append(Green.weights(_points, point) if inside else PackedFloat64Array())
    _at_close = _points.duplicate()
    closed = true
    return true


## The grabbed point moved to *to*, and the picture put under the mesh it
## makes, through *engine*. False when nothing is grabbed or the lift is over
## another box than the cage closed on.
func drag(to: Vector2, held: Rect2i, engine: SaTransform) -> bool:
    if not closed or _grabbed < 0 or held != box:
        return false
    _points = _at_press.duplicate()
    _points[_grabbed] = to
    engine.preview_mesh(mesh_for(_points))
    return true


## The grid the cage bends to with its points at *moved*, one for each of the
## cage's points in its closed order: each point inside the cage is its rest
## place plus the moves of the cage's points and of its edges' scaled normals
## by its weights, and each point outside is its rest place.
func mesh_for(moved: PackedVector2Array) -> PackedVector2Array:
    if not closed or moved.size() != _points.size():
        return PackedVector2Array()
    var count := moved.size()
    var shifts := Green.shifts(_at_close, moved)
    var out := PackedVector2Array()
    for index in _rest.size():
        var weights: PackedFloat64Array = _weights[index]
        var x := float(_rest[index].x)
        var y := float(_rest[index].y)
        if not weights.is_empty():
            for k in count * 2:
                x += weights[k] * shifts[k * 2]
                y += weights[k] * shifts[k * 2 + 1]
        out.append(Vector2(x, y))
    return out


## The cage as the overlay draws it: its outline, open while it is being
## clicked and shut once closed, and its points, in place of the box's
## handles.
func shape() -> Dictionary:
    var outline := _points.duplicate()
    if closed and not outline.is_empty():
        outline.append(outline[0])
    var lines: Array[PackedVector2Array] = []
    if outline.size() >= 2:
        lines.append(outline)
    return {"lines": lines, "knots": _points.duplicate(), "handles": false}


## Green coordinates in two dimensions, the arithmetic alone. Every number is
## a GDScript float, which is a double, and positions are taken from the
## point weighed so a cage far from the origin loses no digits.
class Green:
    extends RefCounted

    ## Twice the signed area of *polygon*, positive for the winding whose
    ## outward normal of an edge `a` is `(-a.y, a.x)` turned to unit length,
    ## which is anticlockwise on a screen whose y runs down.
    static func area(polygon: PackedVector2Array) -> float:
        var sum := 0.0
        for index in polygon.size():
            var p := polygon[index]
            var q := polygon[(index + 1) % polygon.size()]
            sum += float(p.x) * float(q.y) - float(q.x) * float(p.y)
        return -sum

    ## The weights of *at* inside *cage*: one per cage point, then one per
    ## edge, the edge from point j to point j plus one. Lipman's Algorithm 1,
    ## with the boundary left to the caller, which never weighs a point
    ## outside or on the cage.
    static func weights(cage: PackedVector2Array, at: Vector2) -> PackedFloat64Array:
        var count := cage.size()
        var out := PackedFloat64Array()
        out.resize(count * 2)
        out.fill(0.0)
        for j in count:
            var next := (j + 1) % count
            var ax := float(cage[next].x) - float(cage[j].x)
            var ay := float(cage[next].y) - float(cage[j].y)
            var bx := float(cage[j].x) - float(at.x)
            var by := float(cage[j].y) - float(at.y)
            var q := ax * ax + ay * ay
            var s := bx * bx + by * by
            var r := 2.0 * (ax * bx + ay * by)
            var length := sqrt(q)
            if length <= 0.0 or s <= 0.0:
                continue
            # b against the edge's normal times its length, Lipman's BA with
            # the sign this winding gives it.
            var ba := bx * ay - by * ax
            var root := sqrt(maxf(4.0 * s * q - r * r, 1e-18))
            var l0 := log(s)
            var l1 := log(s + q + r)
            var a0 := atan(r / root) / root
            var a1 := atan((2.0 * q + r) / root) / root
            var a10 := a1 - a0
            var l10 := l1 - l0
            out[count + j] = -length / (4.0 * PI) * ((4.0 * s - r * r / q) * a10 + r / (2.0 * q) * l10 + l1 - 2.0)
            out[next] -= ba / (2.0 * PI) * (l10 / (2.0 * q) - a10 * r / q)
            out[j] += ba / (2.0 * PI) * (l10 / (2.0 * q) - a10 * (2.0 + r / q))
        return out

    ## What each weight multiplies when the cage goes from *rest* to *moved*,
    ## two numbers a weight: each point's move, then each edge's outward unit
    ## normal scaled by how much the edge stretched, less the normal it had.
    static func shifts(rest: PackedVector2Array, moved: PackedVector2Array) -> PackedFloat64Array:
        var count := rest.size()
        var out := PackedFloat64Array()
        for index in count:
            out.append(float(moved[index].x) - float(rest[index].x))
            out.append(float(moved[index].y) - float(rest[index].y))
        for j in count:
            var next := (j + 1) % count
            var before := _normal(rest[j], rest[next], 1.0)
            var stretch := moved[next].distance_to(moved[j]) / maxf(rest[next].distance_to(rest[j]), 1e-9)
            var after := _normal(moved[j], moved[next], stretch)
            out.append(after[0] - before[0])
            out.append(after[1] - before[1])
        return out

    ## The outward unit normal of the edge *from* to *to*, times *scale*.
    static func _normal(from: Vector2, to: Vector2, scale: float) -> PackedFloat64Array:
        var ax := float(to.x) - float(from.x)
        var ay := float(to.y) - float(from.y)
        var length := maxf(sqrt(ax * ax + ay * ay), 1e-12)
        return PackedFloat64Array([-ay / length * scale, ax / length * scale])
