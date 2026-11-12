## The shape that made a selection, a rectangle, an ellipse or a polygon of
## rings, kept beside the mask so a point can be tested against the shape on
## the CPU. The mask itself is `r32f` chunks in VRAM, and the marquee asks
## whether a press lands inside the selection on every pointer motion, which no
## read back may answer (hard rule 1).
##
## **It describes the chunks it was made with and no others.** It holds those
## chunk objects and stands only while the selection holds the same ones, or
## holds them as the hard mask under its feather. A change writes into copies
## or fresh chunks (`SaSelection.own_chunk`), so anything that alters the mask
## after the shape, an add, a subtract, an invert, a move or a wand, leaves the
## record standing for chunks that are gone, and the asker falls back to the
## bounds. An undo or a redo lays the very chunks of its side back, so the shape
## of that side stands again, which is why `SaSelectionHeld` carries it.
class_name SaSelectionShape
extends RefCounted

## The kernel that wrote the shape, the name `SaSelection` dispatches.
var kernel: String
## The box the shape was written over, in document pixels: the rectangle
## itself, or the box an ellipse is inscribed in.
var box: Rect2i
## A polygon's points in document pixels, rings ended by `SaSelectionRings.RING_END`.
var points: PackedVector2Array
## The chunks the shape was written into, grid position to chunk object.
var chunks: Dictionary


func _init(made_by: String, made_over: Rect2i, made_of: PackedVector2Array, made_into: Dictionary) -> void:
    kernel = made_by
    box = made_over
    points = made_of
    chunks = made_into.duplicate()


## Whether this record still describes *selection*, chunk for chunk, under its
## feather when it has one.
func stands_in(selection: SaSelection) -> bool:
    if not selection.active or selection.editing:
        return false
    var hard: Dictionary = selection.feather.hard_under(selection, selection.hold()).chunks
    if hard.size() != chunks.size():
        return false
    for grid_pos: Vector2i in chunks:
        if hard.get(grid_pos, null) != chunks[grid_pos]:
            return false
    return true


## The same shape *by* whole pixels along, written into *moved_into*, the
## chunks a carry of the outline left.
func moved(by: Vector2i, moved_into: Dictionary) -> SaSelectionShape:
    var carried := PackedVector2Array()
    for point in points:
        carried.append(point if point.x >= SaSelectionRings.RING_END else point + Vector2(by))
    return SaSelectionShape.new(kernel, Rect2i(box.position + by, box.size), carried, moved_into)


## Whether *point*, in document pixels, lies inside the shape.
func has_point(point: Vector2) -> bool:
    var area := Rect2(box)
    if not area.has_point(point):
        return false
    match kernel:
        "select_ellipse":
            var radii := area.size * 0.5
            var off := (point - area.get_center()) / radii.max(Vector2(0.5, 0.5))
            return off.length_squared() <= 1.0
        "select_polygon":
            return _inside_rings(point)
    return true


## Even-odd winding over every ring at once, as `selection.gmacs` tests a
## pixel, so a hole or a lasso's crossing reads as outside here too.
func _inside_rings(point: Vector2) -> bool:
    var inside := false
    var start := 0
    var count := points.size()
    while start < count:
        var end := start
        while end < count and points[end].x < SaSelectionRings.RING_END:
            end += 1
        var last := points[end - 1] if end > start else point
        for i in range(start, end):
            var here := points[i]
            if (here.y > point.y) != (last.y > point.y):
                var cross := here.x + (point.y - here.y) * (last.x - here.x) / (last.y - here.y)
                if point.x < cross:
                    inside = not inside
            last = here
        start = end + 1
    return inside
