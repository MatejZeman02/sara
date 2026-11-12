## The shape a capture's state dump writes a point, a list of points and a
## rectangle in.
##
## Three lines of arithmetic, in one place because the alternative is what the
## tree had: the same `{"x": ..., "y": ...}` literal written out in five files,
## so a reader comparing two dumps had to check that all five agreed. They did,
## and nothing said they had to.
##
## A `class_name` rather than a preload, because a module's tool reports its own
## rectangles through these too and a module cannot be asked to know a skeleton
## path.
extends RefCounted

class_name SaReportShapes


## A point, as the two numbers a dump writes it with.
static func vec(v: Vector2) -> Dictionary:
    return {"x": v.x, "y": v.y}


## A list of points, for a shape a rectangle cannot hold.
static func points(list: PackedVector2Array) -> Array:
    var out: Array = []
    for point: Vector2 in list:
        out.append(vec(point))
    return out


## A rectangle, as the four numbers a dump writes it with.
static func rect(r: Rect2) -> Dictionary:
    return {"x": r.position.x, "y": r.position.y, "w": r.size.x, "h": r.size.y}
