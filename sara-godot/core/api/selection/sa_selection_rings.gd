## A polygon made of several closed rings, written as the one list of points
## `SaSelection.select_polygon` hands to the kernel, so a ring inside another
## is a hole: the outline of a donut, or a lasso round a figure with the gap
## under its arm, selects the ring and not what it encloses.
##
## The kernel tests every pixel by even-odd winding over all the rings at
## once, and a ray from inside a hole crosses the hole's ring as well as the
## outer one. Each ring is followed by a point past `RING_END`, which the
## kernel reads as the end of that ring, closing it back to its own first point.
## Joining the rings by plain edges instead would draw a seam through the
## selection where an anti-aliased edge grades the pixels each side of it.
##
## A ring needs no repeat of its first point at its end, and a ring of fewer
## than three points is no ring and is left out.
class_name SaSelectionRings
extends RefCounted

## Where a point stops being one, in `selection.gmacs` as well.
const RING_END: float = 1.0e30


## The points of *rings*, an array of `PackedVector2Array`s in document
## pixels, each followed by the end mark.
static func flatten(rings: Array) -> PackedVector2Array:
    var out := PackedVector2Array()
    for ring: PackedVector2Array in rings:
        if ring.size() < 3:
            continue
        out.append_array(ring)
        out.append(Vector2(RING_END, RING_END))
    return out


## The pixel box *points* covers, the end marks left out, so a ring's floor
## and ceiling box it as a single outline's always did.
static func box_of(points: PackedVector2Array) -> Rect2i:
    var low := Vector2(INF, INF)
    var high := -low
    for point in points:
        if point.x >= RING_END:
            continue
        low = Vector2(minf(low.x, point.x), minf(low.y, point.y))
        high = Vector2(maxf(high.x, point.x), maxf(high.y, point.y))
    if low.x > high.x:
        return Rect2i()
    return Rect2i(Vector2i(floori(low.x), floori(low.y)), Vector2i(ceili(high.x) - floori(low.x), ceili(high.y) - floori(low.y)))
