## A projective map of the plane, as nine floats in row order.
##
## In the base module, in the transform's `warps` folder rather than under `core/`:
## the only reader of a homography was the transform tool.
##
## The sibling of `sa_transform.gd` a folder up. The split is
## not only arithmetic: a homography is a thing in its own right, it is what a
## `Transform2D` cannot hold, and both the transform pass and the tool that
## drives it need to send a point through one without either of them owning the
## divide. `core/api/paint/sa_resample_kernel.gd` is the other half of the same split.
##
## **Nine numbers, not a matrix type.** Godot has `Transform2D` and
## `Projection`, and neither fits. `Transform2D` is the affine six, which is the
## whole reason this file exists. `Projection` is a 4 by 4 built for cameras,
## and packing a 2D homography into its corners means every reader has to know
## which corners. A `PackedFloat32Array` of nine is what the push constant wants
## anyway, so it is what is passed about, and an empty one means "no map", which
## is the answer a degenerate solve gives.
##
## The order is the reading order: `h[0]` to `h[2]` are the first row, `h[3]` to
## `h[5]` the second, `h[6]` to `h[8]` the third. An affine map is this with a
## third row of (0, 0, 1), which divides by one, and that is exactly what the
## resample kernel is handed when nothing is in perspective.
class_name SaHomography
extends RefCounted


## *at* through *h*, as a position in the same frame *h*'s output is in.
##
## A point whose `w` comes out at nought is on the line the map sends to
## infinity and has no image at all. It is answered with itself rather than with
## a division by zero, because every caller here is drawing an outline and a
## finite wrong point is easier to see than a NaN.
static func through(h: PackedFloat32Array, at: Vector2) -> Vector2:
    var w := h[6] * at.x + h[7] * at.y + h[8]
    if is_zero_approx(w):
        return at
    return Vector2(h[0] * at.x + h[1] * at.y + h[2], h[3] * at.x + h[4] * at.y + h[5]) / w


## The inverse of *h*, by the adjugate, which for a 3 by 3 is nine 2 by 2
## determinants and no pivoting.
##
## The determinant is not divided out, but its sign is. A homography is only
## ever defined up to scale, so the adjugate is the inverse for every purpose
## here, and the divide by `w` that every use of it ends in cancels the
## magnitude of the common factor. It does not cancel the sign, and that was the
## trap: a map that turns the picture over has a negative determinant, the
## adjugate is then the inverse times a negative number, and the `w` the
## resample kernel reads comes out negative over the whole picture, which the
## kernel takes for "behind the horizon" and leaves blank. A position the
## inverse is handed has its `w` at the determinant over the forward map's own
## `w` at the texel it came from, so multiplying the adjugate by the
## determinant's sign leaves that `w` positive wherever the forward map's is.
##
## **That puts a duty on *h*:** its own `w` has to be positive over the picture,
## which `corners_to_quad` sees to. A map handed in with the picture behind its
## horizon comes out inverted into the same blank.
static func inverse_of(h: PackedFloat32Array) -> PackedFloat32Array:
    var det := h[0] * (h[4] * h[8] - h[5] * h[7]) - h[1] * (h[3] * h[8] - h[5] * h[6]) + h[2] * (h[3] * h[7] - h[4] * h[6])
    var orientation := -1.0 if det < 0.0 else 1.0
    var out := PackedFloat32Array()
    out.resize(9)
    out[0] = orientation * (h[4] * h[8] - h[5] * h[7])
    out[1] = orientation * (h[2] * h[7] - h[1] * h[8])
    out[2] = orientation * (h[1] * h[5] - h[2] * h[4])
    out[3] = orientation * (h[5] * h[6] - h[3] * h[8])
    out[4] = orientation * (h[0] * h[8] - h[2] * h[6])
    out[5] = orientation * (h[2] * h[3] - h[0] * h[5])
    out[6] = orientation * (h[3] * h[7] - h[4] * h[6])
    out[7] = orientation * (h[1] * h[6] - h[0] * h[7])
    out[8] = orientation * (h[0] * h[4] - h[1] * h[3])
    return out


## The map taking the four corners of *from*, clockwise from its top left, onto
## *to*, which is four positions in the same order.
##
## Eight unknowns and eight equations, `h[8]` fixed at one, solved by Gaussian
## elimination with partial pivoting. There is no closed form worth writing out
## here: the classical square-to-quad shortcut needs the source to be the unit
## square, and the source is whatever box the lift covered.
##
## Empty when the four points are degenerate, three of them in a line or two of
## them the same, which the caller reads as "keep the map you had".
##
## **The sign is chosen, not left to the solve.** A homography is the same map
## with all nine numbers negated, and fixing `h[8]` at one picks whichever sign
## makes `w` positive at the document's origin, which has nothing to do with the
## picture. `inverse_of` and the resample kernel draw the side of the map's
## horizon on which `w` is positive and nothing else, so the sign decides what
## is drawn. A map that keeps the whole box on one side of its horizon is drawn
## whole under this sign, because the centre is on that side. Dragging a corner
## through its opposite puts the horizon across the box, and the half that stays
## is the half the box's centre is in. A map whose centre is in front already is
## returned as the solve left it, so `h[8]` is one for it and minus one only
## otherwise.
static func corners_to_quad(from: Rect2i, to: PackedVector2Array) -> PackedFloat32Array:
    if to.size() != 4 or from.size.x <= 0 or from.size.y <= 0:
        return PackedFloat32Array()
    var source := corners_of(from)
    # One row per coordinate of one corner, eight in all, each nine long: eight
    # coefficients and the value the row has to reach.
    var rows: Array = []
    for i in 4:
        var src: Vector2 = source[i]
        var dst: Vector2 = to[i]
        rows.append([src.x, src.y, 1.0, 0.0, 0.0, 0.0, -dst.x * src.x, -dst.x * src.y, dst.x])
        rows.append([0.0, 0.0, 0.0, src.x, src.y, 1.0, -dst.y * src.x, -dst.y * src.y, dst.y])
    for col in 8:
        var pivot := col
        for row in range(col + 1, 8):
            if absf(rows[row][col]) > absf(rows[pivot][col]):
                pivot = row
        if absf(rows[pivot][col]) < 1e-9:
            return PackedFloat32Array()
        var swap: Array = rows[col]
        rows[col] = rows[pivot]
        rows[pivot] = swap
        for row in 8:
            if row == col:
                continue
            var factor: float = rows[row][col] / rows[col][col]
            if is_zero_approx(factor):
                continue
            for k in range(col, 9):
                rows[row][k] -= factor * rows[col][k]
    var out := PackedFloat32Array()
    out.resize(9)
    for i in 8:
        out[i] = rows[i][8] / rows[i][i]
    out[8] = 1.0
    var centre := Vector2(from.position) + Vector2(from.size) * 0.5
    if out[6] * centre.x + out[7] * centre.y + out[8] < 0.0:
        for i in 9:
            out[i] = -out[i]
    return out


## Whether the four corners *points*, in order, fail to make a convex quad.
##
## Each corner's turn is the cross product of the edge into it and the edge out
## of it, and a convex quad turns the same way at all four. A bowtie, a concave
## arrowhead and three corners in a line each have a turn of the other sign or
## of nought, and a nought counts as a fold. Either sign on its own passes, so a
## quad turned over whole, which a flip, Mirrored and an edge dragged past its
## opposite all make, is still a quad.
##
## **Why it is asked at all.** No projective map of a rectangle onto a folded
## quad keeps the whole rectangle in front of its horizon, so one dragged corner
## past its opposite drops the half of the picture the box's centre is not in.
## The perspective drag refuses such a quad and holds the last one that did not
## fold. `corners_to_quad` still solves it, because a freehand
## warp's corners go through it and a warp may fold its cells as it likes.
static func folds(points: PackedVector2Array) -> bool:
    if points.size() != 4:
        return true
    var turning := 0.0
    for i in 4:
        var into := points[i] - points[(i + 3) % 4]
        var out := points[(i + 1) % 4] - points[i]
        var turn := into.cross(out)
        if is_zero_approx(turn):
            return true
        if turning == 0.0:
            turning = signf(turn)
        elif signf(turn) != turning:
            return true
    return false


## The four corners of *box*, clockwise from its top left, which is the order
## `SaTransform.landed_quad` builds and the order `corners_to_quad` reads.
static func corners_of(box: Rect2i) -> PackedVector2Array:
    return PackedVector2Array(
        [
            Vector2(box.position),
            Vector2(box.end.x, box.position.y),
            Vector2(box.end),
            Vector2(box.position.x, box.end.y),
        ]
    )


## The affine map through three of *box*'s four corners under *h*, or *fallback*
## when the box has no area to read one off.
##
## Exact whenever *h* is itself affine, and a reading rather than the truth
## whenever it is not. It exists so the six transform rows in Tool Options, each
## of which is a number read off a `Transform2D`, keep saying something about
## where the picture is instead of freezing at whatever they held when the mode
## changed. Whoever shows those numbers has to say separately that a perspective
## map is in force, which is what `SaTransform.is_perspective` is for.
static func affine_part(h: PackedFloat32Array, box: Rect2i, fallback: Transform2D) -> Transform2D:
    var origin := Vector2(box.position)
    var span := Vector2(box.size)
    if span.x <= 0.0 or span.y <= 0.0:
        return fallback
    var at_origin := through(h, origin)
    var along_x := (through(h, origin + Vector2(span.x, 0.0)) - at_origin) / span.x
    var along_y := (through(h, origin + Vector2(0.0, span.y)) - at_origin) / span.y
    return Transform2D(along_x, along_y, at_origin - along_x * origin.x - along_y * origin.y)


## The inverse of one map, as the four pieces the `resample` kernel's push
## constant wants: the two upper rows, the translation, and the third row.
##
## *h* is the perspective map when a gesture has one and empty otherwise, in
## which case *affine* is the map every other gesture drives. *lift* is the
## origin of the lifted picture, folded in here rather than in the kernel.
##
## An affine map answers a third row of (0, 0, 1), so the kernel divides by one
## and its arithmetic is the plain affine one. Under a
## perspective map the lift's origin has to be folded into the whole row rather
## than added to the translation, because the translation is divided by `w` and
## the origin is not.
static func kernel_rows(h: PackedFloat32Array, affine: Transform2D, lift: Vector2) -> Array:
    if h.size() != 9:
        var back := affine.affine_inverse()
        return [
            Vector2(back.x.x, back.y.x),
            Vector2(back.x.y, back.y.y),
            back.origin - lift,
            Vector3(0.0, 0.0, 1.0),
        ]
    var back_h := inverse_of(h)
    return [
        Vector2(back_h[0], back_h[1]) - Vector2(back_h[6], back_h[7]) * lift.x,
        Vector2(back_h[3], back_h[4]) - Vector2(back_h[6], back_h[7]) * lift.y,
        Vector2(back_h[2] - back_h[8] * lift.x, back_h[5] - back_h[8] * lift.y),
        Vector3(back_h[6], back_h[7], back_h[8]),
    ]
