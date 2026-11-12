## The freehand warp's mesh: nine control points over the lifted picture, and
## the arithmetic a tool, a pass and an overlay ask of them.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## In the base module, a folder below `sa_transform.gd`, which is its one reader in the
## skeleton or out of it.
##
## **Nine points, row by row from the top left**, which is the order the `warp`
## kernel reads them in and the order `SaWarpKernel.dispatch` packs. The four
## outer ones are the box's corners in `landed_quad`'s own order once
## `corners_of` picks them out, so everything that already reads a quad reads a
## warped box the same way. Static throughout: a mesh is a `PackedVector2Array`
## the tool holds, and nothing here keeps one.
##
## **A grid of any side for what a pass reads.** The cage bends the picture
## through a dense grid, `SaTransformCage` in `cage`, so the forward map, the
## reach and the corners read a mesh of side by side points, whose side is
## `side_of`. The grid, the edges and the lines a painter grabs are
## Freehand's nine.
class_name SaTransformMesh
extends RefCounted

const POINTS: int = 9
const SIDE: int = 3


## How many points run along a side of *mesh*, or 0 when it is no square grid
## of at least two by two.
static func side_of(mesh: PackedVector2Array) -> int:
    var side := roundi(sqrt(float(mesh.size())))
    return side if side >= 2 and side * side == mesh.size() else 0


## The grid over *quad*, whose four corners come in the quad order: each point
## is the bilinear blend of the corners at its thirds, or at *side* minus one
## parts for a denser grid, so a box already turned or leaned gets a grid that
## follows its edges.
static func grid_over(quad: PackedVector2Array, side: int = SIDE) -> PackedVector2Array:
    var out := PackedVector2Array()
    if quad.size() < 4 or side < 2:
        return out
    for row in side:
        var v := float(row) / float(side - 1)
        for column in side:
            var u := float(column) / float(side - 1)
            var top: Vector2 = quad[0].lerp(quad[1], u)
            var bottom: Vector2 = quad[3].lerp(quad[2], u)
            out.append(top.lerp(bottom, v))
    return out


## The four outer points, in the quad order: top left, top right, bottom
## right, bottom left.
static func corners_of(mesh: PackedVector2Array) -> PackedVector2Array:
    var out := PackedVector2Array()
    var side := side_of(mesh)
    if side == 0:
        return out
    for index: int in [0, side - 1, side * side - 1, side * (side - 1)]:
        out.append(mesh[index])
    return out


## The axis-aligned box around every point, one texel wider on each side,
## which is the skirt a bilinear read needs: the centre point dragged out
## past the corners is inside this and outside the corners' own box.
static func bounds_of(mesh: PackedVector2Array) -> Rect2i:
    if side_of(mesh) == 0:
        return Rect2i()
    var low := mesh[0]
    var high := mesh[0]
    for point: Vector2 in mesh:
        low = low.min(point)
        high = high.max(point)
    var origin := Vector2i(floori(low.x) - 1, floori(low.y) - 1)
    return Rect2i(origin, Vector2i(ceili(high.x) + 1, ceili(high.y) + 1) - origin)


## Where a document position of the lifted picture, *at* inside *bounds*, lands
## under the mesh: its cell by which half of the box it is in, and the bilinear
## blend of that cell's four points, for a grid of any side. The forward map, which the pass uses for
## where the box is, while the kernel solves the inverse per texel.
static func through(mesh: PackedVector2Array, bounds: Rect2i, at: Vector2) -> Vector2:
    var side := side_of(mesh)
    if side == 0 or bounds.size.x <= 0 or bounds.size.y <= 0:
        return at
    var unit := (at - Vector2(bounds.position)) / Vector2(bounds.size)
    var scaled := unit.clamp(Vector2.ZERO, Vector2.ONE) * float(side - 1)
    var column := mini(floori(scaled.x), side - 2)
    var row := mini(floori(scaled.y), side - 2)
    var u := scaled.x - float(column)
    var v := scaled.y - float(row)
    var first := row * side + column
    var top: Vector2 = mesh[first].lerp(mesh[first + 1], u)
    var bottom: Vector2 = mesh[first + side].lerp(mesh[first + side + 1], u)
    return top.lerp(bottom, v)


## The point within *reach* of *at*, nearest first, or -1 for none.
static func nearest(mesh: PackedVector2Array, at: Vector2, reach: float) -> int:
    var best := -1
    var nearest_away := reach
    for index in mesh.size():
        var away := mesh[index].distance_to(at)
        if away <= nearest_away:
            nearest_away = away
            best = index
    return best


## The six lines of the grid, three across and three down, for an overlay to
## draw so a painter sees the cells and not only their corners.
static func lines_of(mesh: PackedVector2Array) -> Array[PackedVector2Array]:
    var out: Array[PackedVector2Array] = []
    if mesh.size() != POINTS:
        return out
    for row in SIDE:
        var across := PackedVector2Array()
        for column in SIDE:
            across.append(mesh[row * SIDE + column])
        out.append(across)
    for column in SIDE:
        var down := PackedVector2Array()
        for row in SIDE:
            down.append(mesh[row * SIDE + column])
        out.append(down)
    return out


## The three control points along the edge *grabbed* names, as indices into a
## mesh, or empty when *grabbed* is a corner handle rather than a side one.
## One of the rows or columns `lines_of` draws, picked by the handle.
##
## The handle's own -1 and 1 per axis are already the first and the last of the
## grid, which is what makes this a lookup rather than arithmetic: -1 is row or
## column nought and 1 is the last of the three.
static func edge_points(grabbed: Vector2i) -> PackedInt32Array:
    var out := PackedInt32Array()
    if (grabbed.x == 0) == (grabbed.y == 0):
        return out
    var wanted_row := -1 if grabbed.y == 0 else (SIDE - 1 if grabbed.y > 0 else 0)
    var wanted_column := -1 if grabbed.x == 0 else (SIDE - 1 if grabbed.x > 0 else 0)
    for row in SIDE:
        for column in SIDE:
            if row == wanted_row or column == wanted_column:
                out.append(row * SIDE + column)
    return out
