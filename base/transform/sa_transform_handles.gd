## The transform box's handles: where the eight sit on a quad, which one a
## press is on, and what pulling or leaning one means as a map.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## This is the arithmetic of a handle drag and nothing else: no tool state,
## no pass, no document. The tool asks it where its handles are and what a
## drag from a press means, and composes the answer onto its own matrix.
class_name SaTransformHandles
extends RefCounted

## The four corners in `SaTransform.landed_quad`'s own order, clockwise from
## the top left, which is the order a homography's four points have to arrive
## in.
const QUAD_CORNERS: Array[Vector2i] = [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1)]

## The eight, in the order a reader would name them, with the centre left out.
const HANDLE_CORNERS: Array[Vector2i] = [
    Vector2i(-1, -1),
    Vector2i(0, -1),
    Vector2i(1, -1),
    Vector2i(-1, 0),
    Vector2i(1, 0),
    Vector2i(-1, 1),
    Vector2i(0, 1),
    Vector2i(1, 1),
]


## Where a handle sits, from the quad's own corners rather than from a
## rectangle, so a turned box keeps its handles on its edges.
static func point_on(quad: PackedVector2Array, corner: Vector2i) -> Vector2:
    var top: Vector2 = quad[0].lerp(quad[1], 0.5 * float(corner.x + 1))
    var bottom: Vector2 = quad[3].lerp(quad[2], 0.5 * float(corner.x + 1))
    return top.lerp(bottom, 0.5 * float(corner.y + 1))


## Which of the eight handles *at* is on, as -1, 0 or 1 per axis, or null for
## a press that is on none, within *reach* document pixels. Typed as a Variant
## for the reason the crop's own `_handle_under` gives: inferring a type from
## a function that can answer null is a warning this project treats as an
## error.
static func under(quad: PackedVector2Array, at: Vector2, reach: float) -> Variant:
    if quad.size() < 4:
        return null
    var best: Variant = null
    var nearest := reach
    for corner: Vector2i in HANDLE_CORNERS:
        var away := point_on(quad, corner).distance_to(at)
        if away <= nearest:
            nearest = away
            best = corner
    return best


## Whether *at* is within *reach* of one of the four corners, from outside or
## in, which is where a rotation starts.
static func near_a_corner(quad: PackedVector2Array, at: Vector2, reach: float) -> bool:
    for corner: Vector2i in QUAD_CORNERS:
        if point_on(quad, corner).distance_to(at) <= reach:
            return true
    return false


## Whether a press at *at* would turn the box: on no cell of the mode strip,
## none of *points*, the warp's nine under Freehand, and none of the handles,
## outside the quad and within the rotation's reach of a corner. The order the
## press asks in, so the pointer's rotate arrow stands exactly where a press
## turns. The reaches are screen pixels, *per_pixel* the strip's measure.
static func turns_at(
    quad: PackedVector2Array, at: Vector2, per_pixel: float, handle_reach: float, rotate_reach: float, points: PackedVector2Array
) -> bool:
    if quad.size() < 4:
        return false
    if SaTransformModeStrip.pick(quad, per_pixel, at) >= 0:
        return false
    if SaTransformMesh.nearest(points, at, handle_reach * per_pixel) >= 0:
        return false
    if under(quad, at, handle_reach * per_pixel) != null:
        return false
    if Geometry2D.is_point_in_polygon(at, quad):
        return false
    return near_a_corner(quad, at, rotate_reach * per_pixel)


## The scale a drag of *grabbed* to *to* asks for, in the box's own frame,
## holding the far side still: the map from the box as it was at the press to
## the box the pointer has pulled it to. *at_press* is the matrix the press
## was made under.
##
## *even*, Shift on a handle, scales both axes by one factor, so the box keeps
## the width to height it had at the press. On a corner the factor is the
## pointer's travel projected onto the diagonal from the held corner to the
## grabbed one, the one factor that leaves the grabbed corner nearest the hand,
## and it goes negative with its sign once the corner passes the held one, a
## flip that keeps the ratio. On a side it is the dragged axis's own, and the
## other axis grows by it about the box's middle line, which `held` names there.
static func pull(box: Rect2i, grabbed: Vector2i, at_press: Transform2D, to: Vector2, even := false) -> Transform2D:
    var half := Vector2(box.size) * 0.5
    var centre := Vector2(box.position) + half
    var held := centre - Vector2(grabbed) * half
    var reach := Vector2(grabbed) * half * 2.0
    var travel := at_press.affine_inverse() * to - held
    var factor := Vector2.ONE
    if even and absf(reach.x) > 0.5 and absf(reach.y) > 0.5:
        # Projected on the canvas rather than in the box's frame, so a box the
        # press found already stretched or turned still follows the hand.
        var diagonal := at_press.basis_xform(reach)
        factor = Vector2.ONE * ((to - at_press * held).dot(diagonal) / diagonal.length_squared())
    elif even:
        factor = Vector2.ONE * (travel.x / reach.x if absf(reach.x) > 0.5 else travel.y / reach.y)
    else:
        if absf(reach.x) > 0.5:
            factor.x = travel.x / reach.x
        if absf(reach.y) > 0.5:
            factor.y = travel.y / reach.y
    return Transform2D(0.0, held) * Transform2D().scaled(factor) * Transform2D(0.0, -held)


## The shear a drag of a handle asks for, the far edge held still, from where
## the press landed in the box's frame, *press_in_box*, to *to*. A corner leans
## the edge it sits on that runs along the drag's longer axis, so sideways leans
## the top or the bottom and up or down a side, and its far edge is the one
## that edge's own handle holds, which `held` already names on that axis.
static func lean(box: Rect2i, grabbed: Vector2i, at_press: Transform2D, press_in_box: Vector2, to: Vector2) -> Transform2D:
    var half := Vector2(box.size) * 0.5
    var centre := Vector2(box.position) + half
    var held := centre - Vector2(grabbed) * half
    var travel := at_press.affine_inverse() * to - press_in_box
    if grabbed.x != 0 and grabbed.y != 0:
        grabbed = Vector2i(0, grabbed.y) if absf(travel.x) >= absf(travel.y) else Vector2i(grabbed.x, 0)
    if grabbed.y != 0 and absf(half.y) > 0.5:
        var k := travel.x / (-Vector2(grabbed).y * half.y * 2.0)
        return Transform2D(Vector2(1.0, 0.0), Vector2(-k, 1.0), Vector2(k * held.y, 0.0))
    if grabbed.x != 0 and absf(half.x) > 0.5:
        var k := travel.y / (-Vector2(grabbed).x * half.x * 2.0)
        return Transform2D(Vector2(1.0, -k), Vector2(0.0, 1.0), Vector2(0.0, k * held.x))
    return Transform2D.IDENTITY


## The two corners of the edge *grabbed* names, as indices into a quad in
## `QUAD_CORNERS` order, or empty when *grabbed* is a corner handle rather than
## a side one.
##
## An edge is two corners, so a side handle under a perspective map moves both
## of them rather than scaling the box, and this is the pair it moves.
static func edge_corners(grabbed: Vector2i) -> PackedInt32Array:
    var out := PackedInt32Array()
    if (grabbed.x == 0) == (grabbed.y == 0):
        return out
    for index in QUAD_CORNERS.size():
        var corner: Vector2i = QUAD_CORNERS[index]
        if corner.x == grabbed.x or corner.y == grabbed.y:
            out.append(index)
    return out


## How far to move *points* so every one stands at least *margin* inside
## *room*, the least such move on each axis. Zero on an axis the points cannot
## all fit across, where no move takes every one in.
static func reach_shift(points: PackedVector2Array, room: Rect2, margin: float) -> Vector2:
    if points.is_empty():
        return Vector2.ZERO
    var span := Rect2(points[0], Vector2.ZERO)
    for point: Vector2 in points:
        span = span.expand(point)
    var inner := room.grow(-margin)
    return Vector2(
        _axis_shift(span.position.x, span.end.x, inner.position.x, inner.end.x),
        _axis_shift(span.position.y, span.end.y, inner.position.y, inner.end.y)
    )


## One axis of `reach_shift`: the span *low* to *high* moved into *room_low* to
## *room_high* by the least it takes, or not at all when it is the wider.
static func _axis_shift(low: float, high: float, room_low: float, room_high: float) -> float:
    if high - low > room_high - room_low:
        return 0.0
    if low < room_low:
        return room_low - low
    if high > room_high:
        return room_high - high
    return 0.0


## `reach_shift`, and then every point at least *margin* clear of each of
## *covers* too, the windows standing over the room that a press on a handle
## under them lands on. The least such move.
##
## A cover in the middle of the room is one `SaView.get_free_rect` leaves in,
## so the room alone does not keep a handle off it. The candidates are the
## room's own move plus, on each axis, nothing or the move that takes a point
## that move left under a cover out past one of that cover's sides, and the
## shortest one that keeps every point in the room and off every cover wins.
## The room's own move stands when no candidate clears them all, which is a box
## no pan frees, and zooming out is the painter's call there as it is above.
static func clear_shift(points: PackedVector2Array, room: Rect2, covers: Array[Rect2], margin: float) -> Vector2:
    var shift := reach_shift(points, room, margin)
    var grown: Array[Rect2] = []
    for cover: Rect2 in covers:
        grown.append(cover.grow(margin))
    var moved := _moved(points, shift)
    if not _under_any(moved, grown):
        return shift
    var across: Array[float] = [0.0]
    var down: Array[float] = [0.0]
    for point: Vector2 in moved:
        for cover: Rect2 in grown:
            if _under(point, cover):
                across.append_array([cover.position.x - point.x, cover.end.x - point.x])
                down.append_array([cover.position.y - point.y, cover.end.y - point.y])
    var inner := room.grow(-margin)
    var span := _span(points)
    var across_fits := span.size.x <= inner.size.x
    var down_fits := span.size.y <= inner.size.y
    var best := shift
    var shortest := INF
    for dx: float in across:
        for dy: float in down:
            var tried := shift + Vector2(dx, dy)
            if tried.length_squared() >= shortest:
                continue
            var landed := _moved(points, tried)
            if _under_any(landed, grown) or not _inside(landed, inner, across_fits, down_fits):
                continue
            best = tried
            shortest = tried.length_squared()
    return best


## *points*, each moved by *shift*.
static func _moved(points: PackedVector2Array, shift: Vector2) -> PackedVector2Array:
    var out := PackedVector2Array()
    for point: Vector2 in points:
        out.append(point + shift)
    return out


## The rectangle *points* span.
static func _span(points: PackedVector2Array) -> Rect2:
    var span := Rect2(points[0], Vector2.ZERO)
    for point: Vector2 in points:
        span = span.expand(point)
    return span


## Whether *point* stands strictly inside *cover*, so a point moved onto its
## edge, which is a reach from the window itself, is clear of it.
static func _under(point: Vector2, cover: Rect2) -> bool:
    return point.x > cover.position.x and point.x < cover.end.x and point.y > cover.position.y and point.y < cover.end.y


static func _under_any(points: PackedVector2Array, covers: Array[Rect2]) -> bool:
    for point: Vector2 in points:
        for cover: Rect2 in covers:
            if _under(point, cover):
                return true
    return false


## Whether every one of *points* is inside *inner*, give or take a rounding,
## on each axis they can all fit across.
static func _inside(points: PackedVector2Array, inner: Rect2, across: bool, down: bool) -> bool:
    var slack := 0.001
    for point: Vector2 in points:
        if across and (point.x < inner.position.x - slack or point.x > inner.end.x + slack):
            return false
        if down and (point.y < inner.position.y - slack or point.y > inner.end.y + slack):
            return false
    return true


## The windows standing over the canvas, which a press on a handle under one
## lands on, in the space the view pans in. Every shown window the main window
## embeds, a docker floating in the middle as much as a column, read off the
## windows themselves as `SaView.get_free_rect` reads its columns, since the
## canvas is drawn in the main window and a let-out docker is a window of its
## own that is not over it.
static func windows_over() -> Array[Rect2]:
    var out: Array[Rect2] = []
    var tree := Engine.get_main_loop() as SceneTree
    if tree == null:
        return out
    for window: Window in tree.root.get_embedded_subwindows():
        if window.visible:
            out.append(Rect2(Vector2(window.position), Vector2(window.size)))
    return out
