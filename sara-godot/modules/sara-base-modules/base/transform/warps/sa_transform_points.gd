## The points a hand places on a transform that a matrix cannot hold, and the
## corner, edge and warp drags that place them.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Perspective and Mirrored read the picture as four corners through a
## homography, and Freehand as nine control points through a mesh. Every drag
## here is a displacement from where the points stood at the press rather than
## an accumulation of motions, so the four and the nine are frozen at each
## press whatever the press turns out to mean.
##
## Cut out of the tool's state, `state_transform.gd`, which keeps the press
## that chooses a gesture, the affine gestures a `Transform2D` holds and the
## matrix they write. This owns the points, their copies frozen at the press, the
## control point grabbed, and what a drag, a carry or a flip makes of them. It
## keeps no reference to the tool or to the pass: the pass a placing is
## previewed through and the box the homography maps from arrive with each
## call, and the tool reads the matrix back off the pass when a call answers
## that it placed something.
class_name SaTransformPoints
extends RefCounted

## The four corners a perspective drag has placed, clockwise from the box's own
## top left, in canvas positions. Empty while no perspective drag has begun,
## which is what tells the press to start one from the box as it stands.
var _corners: PackedVector2Array = PackedVector2Array()
## The same four, frozen at the press, so a corner drag is a displacement from
## where the corner was rather than an accumulation of motions.
var _corners_at_press: PackedVector2Array = PackedVector2Array()
## The freehand warp's nine control points in canvas positions, row by row from
## the top left, and the one the press grabbed. Empty while no warp has begun,
## which is what tells the press to lay the grid over the box as it stands.
var _mesh: PackedVector2Array = PackedVector2Array()
var _mesh_grabbed: int = -1
## The nine, frozen at the press for the reason `_corners_at_press` is, and the
## grid over the box as it stands when a freehand press is the first one.
var _mesh_at_press: PackedVector2Array = PackedVector2Array()


## Starts with *corners* placed, the four a layer's perspective transform puts
## the box's corners at, so a move or a turn carries that map rather than
## flattening it to its affine part. None for a box nothing has placed.
func _init(corners: PackedVector2Array = PackedVector2Array()) -> void:
    if corners.size() == 4:
        _corners = corners
        _corners_at_press = corners


## Whether a hand has placed a map a matrix cannot hold, the nine control
## points or the four corners, which an affine gesture and a flip carry rather
## than replace.
func holds() -> bool:
    return _mesh.size() == SaTransformMesh.POINTS or _corners.size() == 4


## Freezes the points at a press, *quad* being the box as it stands, and under
## *freehand* grabs the control point within *reach* of *at*. True when it
## grabbed one, which makes the press a warp.
##
## The four corners are the ones a perspective drag placed, or the box's own
## once none has. Under Freehand the nine are the handles, laid over the box
## as it stands when no warp has begun. A press on none of them is the tool's
## to answer, and inside the box it takes nothing, since a missed point that
## slid the whole picture away would read as the mode doing nothing at all.
func press(quad: PackedVector2Array, at: Vector2, reach: float, freehand: bool) -> bool:
    _corners_at_press = _corners.duplicate() if _corners.size() == 4 else quad
    _mesh_at_press = _mesh
    if not freehand:
        return false
    if _mesh_at_press.size() != SaTransformMesh.POINTS:
        _mesh_at_press = SaTransformMesh.grid_over(quad)
    var index := SaTransformMesh.nearest(_mesh_at_press, at, reach)
    if index < 0:
        return false
    _mesh = _mesh_at_press
    _mesh_grabbed = index
    return true


## Lets go of what the mode just picked has no handle for: the four corners
## unless *keep_corners*, the nine control points unless *keep_mesh*. True when
## either went, which is when the pass has to be shown the affine part alone.
func drop(keep_corners: bool, keep_mesh: bool) -> bool:
    var dropped := false
    if not keep_corners and not _corners.is_empty():
        _corners = PackedVector2Array()
        dropped = true
    if not keep_mesh and not _mesh.is_empty():
        _mesh = PackedVector2Array()
        dropped = true
    return dropped


## The corner handle *grabbed* moved to *to*, and the picture put under the
## homography through the four. True when the four were placed.
##
## Unless *paired* the other three stay exactly where they were, which is what
## Shift asks of Perspective and what separates a corner from a scale. Paired
## and *mirrored*, the diagonally opposite corner moves with it. Paired alone,
## the other end of the edge the drag runs closer to moves by the mirror of the
## drag across that edge's middle, which is Photoshop's Perspective: the top
## left corner dragged left takes the top right one right by as much and widens
## the top, and dragged up takes the bottom left one down and stretches the
## left side.
func drag_corner(grabbed: Vector2i, to: Vector2, paired: bool, mirrored: bool, box: Rect2i, engine: SaTransform) -> bool:
    # The quad's own order, clockwise from the top left, which is what
    # `landed_quad` builds and is not the order the eight handles are listed in.
    var index := SaTransformHandles.QUAD_CORNERS.find(grabbed)
    if index < 0 or _corners_at_press.size() != 4:
        return false
    var wanted := _corners_at_press.duplicate()
    var by := to - _corners_at_press[index]
    wanted[index] = to
    if paired and mirrored:
        # The opposite corner is two along the clockwise order, and it goes
        # the same distance the other way, which keeps the diagonal's midpoint
        # where it was.
        wanted[(index + 2) % 4] -= by
    elif paired:
        var partner := _neighbour_along(index, by)
        # Turned round along the edge and kept across it, so the edge's middle
        # moves only across the edge and the two ends spread or close about it.
        wanted[partner] += by - 2.0 * by.project(_corners_at_press[partner] - _corners_at_press[index])
    return _place(wanted, box, engine)


## Which of corner *index*'s two neighbours, one and three along the clockwise
## order, ends the edge that *by* runs closer to, read as the smaller angle
## between the drag and each edge as the four stood at the press. A tie, and a
## drag that has not moved, goes to the top or bottom edge.
func _neighbour_along(index: int, by: Vector2) -> int:
    # The top left and bottom right corners meet their top or bottom edge going
    # clockwise, and the other two meet it going back.
    var horizontal := (index + 1) % 4 if index % 2 == 0 else (index + 3) % 4
    var vertical := (index + 3) % 4 if index % 2 == 0 else (index + 1) % 4
    var at := _corners_at_press[index]
    var along_horizontal := absf(by.dot((_corners_at_press[horizontal] - at).normalized()))
    var along_vertical := absf(by.dot((_corners_at_press[vertical] - at).normalized()))
    return horizontal if along_horizontal >= along_vertical else vertical


## The edge handle *grabbed* moved by *by* since the press: its two corners
## under a perspective map, its three control points under *freehand*, and the
## opposite edge as the mode says. True when the points were placed.
##
## A displacement rather than a place, because a side handle is a whole edge
## and the pointer is one point. Unless *paired*, and always under *freehand*,
## the edge follows the hand and nothing else moves, so a corner already placed
## stays placed, which is what Shift asks of Perspective. Paired and
## *mirrored*, the opposite edge goes the other way by the whole drag. Paired
## alone, the drag is read along the edge and across it, the edge as its two
## corners stood at the press, and the opposite edge goes the other way by the
## part along and stays where it was across: the top handle dragged right skews
## the picture about its middle, and dragged up raises the top alone.
func drag_edge(
    grabbed: Vector2i, by: Vector2, paired: bool, freehand: bool, mirrored: bool, box: Rect2i, engine: SaTransform
) -> bool:
    var edge := SaTransformMesh.edge_points(grabbed) if freehand else SaTransformHandles.edge_corners(grabbed)
    var points := (_mesh_at_press if freehand else _corners_at_press).duplicate()
    if edge.is_empty() or points.is_empty():
        return false
    for index: int in edge:
        points[index] += by
    if paired and not freehand:
        # The opposite edge is the other two corners, pushed the other way.
        var back := by if mirrored else by.project(_corners_at_press[edge[1]] - _corners_at_press[edge[0]])
        for index: int in SaTransformHandles.edge_corners(-grabbed):
            points[index] -= back
    return _place(points, box, engine)


## The control point the press grabbed, moved to *to*. The other eight stay,
## which is the whole of the mode: a cell's four corners are wherever the
## painter left them and the pixels follow the bilinear patch between.
func drag_point(to: Vector2, box: Rect2i, engine: SaTransform) -> bool:
    if _mesh_grabbed < 0 or _mesh_grabbed >= _mesh_at_press.size():
        return false
    var wanted := _mesh_at_press.duplicate()
    wanted[_mesh_grabbed] = to
    return _place(wanted, box, engine)


## The placed points carried through *delta*, the canvas-side part of an
## affine gesture. True when they were placed, false as well when none are
## held, so the tool asks `holds` first to know the drag is theirs.
##
## Move and rotate over a perspective quad or a warp are the callers that
## matter: carrying the points rather than replacing the map with the
## gesture's own affine one, which would flatten a picture whose corners were
## placed one by one back to a box.
func carry(delta: Transform2D, box: Rect2i, engine: SaTransform) -> bool:
    if not holds():
        return false
    var placed := _mesh_at_press if _mesh.size() == SaTransformMesh.POINTS else _corners_at_press
    var carried := PackedVector2Array()
    for point: Vector2 in placed:
        carried.append(delta * point)
    return _place(carried, box, engine)


## The placed points re-read in mirror order, across the box's own vertical
## middle when *horizontal* and its horizontal one otherwise. True when they
## were placed, false as well when none are held.
##
## The quad's corners swap left for right, and the mesh's columns or rows trade
## ends. That is the same homography or warp composed with the same mirror,
## which is all the matrix product says for the affine case.
func flip(horizontal: bool, box: Rect2i, engine: SaTransform) -> bool:
    if _mesh.size() == SaTransformMesh.POINTS:
        return _place(_mirrored(_mesh, SaTransformMesh.SIDE, horizontal), box, engine)
    if _corners.size() != 4:
        return false
    # Clockwise from the top left, so a mirror across the vertical middle
    # trades the first two and the last two, and across the horizontal one
    # the first with the last and the middle two.
    var order := PackedInt32Array([1, 0, 3, 2]) if horizontal else PackedInt32Array([3, 2, 1, 0])
    var turned := PackedVector2Array()
    for index: int in order:
        turned.append(_corners[index])
    return _place(turned, box, engine)


## The nine-point mesh as a preview entry: its six grid lines and its points, in
## place of the eight handles. Empty for anything that is not a mesh, so the
## overlay is handed nothing to draw and the eight handles stay.
##
## A `mesh` key saying both of these things at once would mean the skeleton's
## overlay knew what a `SaTransformMesh` was and what the four modes are.
## `lines`, `knots` and `cells` are all it knows: polylines, points and boxes
## with a shape in them.
static func shape_of(mesh: PackedVector2Array) -> Dictionary:
    if mesh.size() != SaTransformMesh.POINTS:
        return {}
    return {"lines": SaTransformMesh.lines_of(mesh), "knots": mesh, "handles": false}


## The points sent to *engine* as the map through them: nine of them are the
## freehand mesh and four are the perspective quad from *box*, which is the
## whole of the difference between the two modes here. True when they were
## kept.
##
## A quad the four points cannot describe, three of them in a line or two of
## them the same, is refused, and so is one that folds, since its horizon
## crosses the box and half the paint would go (`SaHomography.folds`), and so
## is one the engine does not keep, which a layer's live transform refuses
## when the horizon crosses the canvas. The drag holds the last map that
## worked.
func _place(points: PackedVector2Array, box: Rect2i, engine: SaTransform) -> bool:
    if points.size() == SaTransformMesh.POINTS:
        _mesh = points
        engine.preview_mesh(_mesh)
        return true
    if points.size() != 4 or box.size.x <= 0 or box.size.y <= 0:
        return false
    var homography := SaHomography.corners_to_quad(box, points)
    if homography.is_empty() or SaHomography.folds(points) or not engine.preview_homography(homography):
        return false
    _corners = points
    return true


## A grid of *side* by *side* points, row by row, with each row reversed for a
## mirror across the vertical middle and the rows reversed otherwise.
static func _mirrored(points: PackedVector2Array, side: int, horizontal: bool) -> PackedVector2Array:
    var out := PackedVector2Array()
    for row in side:
        for column in side:
            var from_row := row if horizontal else side - 1 - row
            var from_column := side - 1 - column if horizontal else column
            out.append(points[from_row * side + from_column])
    return out
