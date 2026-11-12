## The eight handles on a picked object's box, the corners and the middles of
## the edges, what the overlay draws and what a press of the Object tool takes.
##
## The handles are drawn by the canvas's selection overlay in screen space,
## never into the document, and their reach is in logical pixels turned into
## document pixels by the zoom (hard rule 7), so a handle is as easy to take at
## every zoom.
@tool
extends RefCounted

const VectorRecipe := preload("res://modules/sara-base-modules/vector/sa_vector_recipe.gd")

## A handle's side on screen, in logical pixels.
const SIDE := 9.0
## How far from a handle's centre a press still takes it, in logical pixels.
const REACH := 10.0
## How far from an object's edge a press still picks it, in logical pixels.
const PICK_REACH := 4.0
## The smallest side a resize leaves a box, in document pixels.
const SMALLEST := 1.0

## The handles in order: the four corners clockwise from the top left, then
## the middles of the top, right, bottom and left edges. Each is the side or
## sides it moves, as signs: -1 the low edge, 1 the high edge, 0 neither.
const PULLS: Array[Vector2i] = [
    Vector2i(-1, -1),
    Vector2i(1, -1),
    Vector2i(1, 1),
    Vector2i(-1, 1),
    Vector2i(0, -1),
    Vector2i(1, 0),
    Vector2i(0, 1),
    Vector2i(-1, 0),
]


## Where each handle of *box* stands, in [constant PULLS]'s order.
static func points(box: Rect2) -> PackedVector2Array:
    var out := PackedVector2Array()
    var middle := box.get_center()
    for pull: Vector2i in PULLS:
        var x := box.position.x if pull.x < 0 else (box.end.x if pull.x > 0 else middle.x)
        var y := box.position.y if pull.y < 0 else (box.end.y if pull.y > 0 else middle.y)
        out.append(Vector2(x, y))
    return out


## The index of the handle of *box* within *reach* document pixels of *at*,
## the nearest when two are, or -1.
static func under(box: Rect2, at: Vector2, reach: float) -> int:
    var best := -1
    var nearest := reach
    var spots := points(box)
    for i in spots.size():
        var distance := spots[i].distance_to(at)
        if distance <= nearest:
            nearest = distance
            best = i
    return best


## *box* with the handle *handle* pulled by *by* document pixels. A side
## pulled past the opposite one is held a pixel short of it, and *square*
## keeps a corner's pull to the box's own proportions.
static func pulled(box: Rect2, handle: int, by: Vector2, square: bool = false) -> Rect2:
    if handle < 0 or handle >= PULLS.size():
        return box
    var pull := PULLS[handle]
    var low := box.position
    var high := box.end
    if square and pull.x != 0 and pull.y != 0 and box.size.x > 0.0 and box.size.y > 0.0:
        var grow := maxf(by.x * pull.x / box.size.x, by.y * pull.y / box.size.y)
        by = Vector2(grow * box.size.x * pull.x, grow * box.size.y * pull.y)
    if pull.x < 0:
        low.x = minf(low.x + by.x, high.x - SMALLEST)
    elif pull.x > 0:
        high.x = maxf(high.x + by.x, low.x + SMALLEST)
    if pull.y < 0:
        low.y = minf(low.y + by.y, high.y - SMALLEST)
    elif pull.y > 0:
        high.y = maxf(high.y + by.y, low.y + SMALLEST)
    return Rect2(low, high - low)


## What the overlay draws for *box*: its outline and its handles, sized in
## screen pixels, or nothing for an empty box.
static func preview(box: Rect2) -> Dictionary:
    if box.size == Vector2.ZERO:
        return {}
    return {"rect": box, "handles": true, "handle_side": SIDE}


## The box around every picked object of *recipe* in *picked*, or an empty one.
static func picked_box(recipe: VectorRecipe, picked: PackedStringArray) -> Rect2:
    var out := Rect2()
    if recipe == null:
        return out
    for object_id in picked:
        var object := recipe.find(object_id)
        if object != null:
            out = object.box if out.size == Vector2.ZERO else out.merge(object.box)
    return out
