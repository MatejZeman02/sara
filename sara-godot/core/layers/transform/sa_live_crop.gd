## The crop of a layer's live transform: a rectangle of the layer's own pixels
## outside which the layer draws nothing, while its chunks keep every pixel
## painted there until Layer > Convert to Ordinary Layer writes the crop in.
##
## **A value.** The rectangle is set in the constructor and never written
## again, so a change of the crop is a new object, held by a new
## `SaLiveTransform`, and one history step swaps the two transforms.
##
## **No crop** is the rectangle with no area, and keeps everything:
## [method kept] answers [constant EVERYWHERE], a rectangle past any canvas a
## layer has, which the kernel and the footprints read like any other.
##
## **Through a map.** A box a painter drags is in document pixels, and
## [method through] takes it back through the map into the layer's own, the
## smallest whole-pixel rectangle holding its four corners. [method box] goes
## the other way, which is what a tool reports.
##
## **Strips.** Two crops under one map differ by bands of the layer's pixels,
## and [method owed] is the part of one chunk the two disagree on, which is
## all a drag of the box draws again.
class_name SaLiveCrop
extends RefCounted

## The key a layer's `.sad` entry keeps the crop under, beside the map: its
## position and size in the layer's own pixels. Absent for no crop.
const KEY := "crop"
## What no crop keeps, a rectangle past any canvas a layer has.
const EVERYWHERE := Rect2i(-(1 << 29), -(1 << 29), 1 << 30, 1 << 30)
## How near a whole pixel a corner through a map counts as on it, so a quarter
## turn or a move gives a rectangle back exact.
const SNAP := 1.0e-3

## The rectangle of the layer's own pixels the layer draws, empty for all of
## them.
var rect := Rect2i()


func _init(held: Rect2i = Rect2i()) -> void:
    rect = held if held.has_area() else Rect2i()


## Whether there is a crop at all.
func any() -> bool:
    return rect.has_area()


## The rectangle the layer draws, [constant EVERYWHERE] for no crop.
func kept() -> Rect2i:
    return rect if rect.has_area() else EVERYWHERE


## The crop that keeps *dragged*, a rectangle in document pixels, under
## *map*, which takes the layer's pixels to the document's. No crop when the
## rectangle has no area or a corner lies past the map's horizon.
static func through(map: Basis, dragged: Rect2i) -> SaLiveCrop:
    if not dragged.has_area() or absf(map.determinant()) < 1.0e-12:
        return SaLiveCrop.new()
    return SaLiveCrop.new(bounds(map.inverse(), Rect2(dragged)))


## The crop through *map*, in document pixels, empty for no crop.
func box(map: Basis) -> Rect2i:
    return bounds(map, Rect2(rect)) if rect.has_area() else Rect2i()


## The part of *cell*, in document pixels, that one of *before* and this crop
## keeps and the other does not, as the smallest rectangle holding it, local to
## the cell. Empty where the two agree.
func owed(before: SaLiveCrop, cell: Rect2i) -> Rect2i:
    var a := before.kept().intersection(cell)
    var b := kept().intersection(cell)
    if a == b:
        return Rect2i()
    var strip := Rect2i()
    for piece: Rect2i in _less(a, b) + _less(b, a):
        strip = strip.merge(piece) if strip.has_area() else piece
    return Rect2i(strip.position - cell.position, strip.size)


## *whole* less *taken*, as the bands above, below, left and right of their
## overlap that have an area.
static func _less(whole: Rect2i, taken: Rect2i) -> Array[Rect2i]:
    var bands: Array[Rect2i] = []
    if not whole.has_area():
        return bands
    var shared := whole.intersection(taken)
    if not shared.has_area():
        bands.append(whole)
        return bands
    for band: Rect2i in [
        Rect2i(whole.position.x, whole.position.y, whole.size.x, shared.position.y - whole.position.y),
        Rect2i(whole.position.x, shared.end.y, whole.size.x, whole.end.y - shared.end.y),
        Rect2i(whole.position.x, shared.position.y, shared.position.x - whole.position.x, shared.size.y),
        Rect2i(shared.end.x, shared.position.y, whole.end.x - shared.end.x, shared.size.y),
    ]:
        if band.has_area():
            bands.append(band)
    return bands


## The smallest whole-pixel rectangle holding *area*'s four corners through
## *map*, a corner within [constant SNAP] of a whole pixel counting as on it.
## Empty when a corner is past the map's horizon.
static func bounds(map: Basis, area: Rect2) -> Rect2i:
    var corners: Array[Vector2] = [
        area.position, Vector2(area.end.x, area.position.y), area.end, Vector2(area.position.x, area.end.y)
    ]
    var box_found := Rect2()
    for i in range(corners.size()):
        var mapped := map * Vector3(corners[i].x, corners[i].y, 1.0)
        if mapped.z <= SaLiveTransform.HORIZON:
            return Rect2i()
        var point := Vector2(mapped.x, mapped.y) / mapped.z
        box_found = Rect2(point, Vector2.ZERO) if i == 0 else box_found.expand(point)
    var low := Vector2i((box_found.position + Vector2(SNAP, SNAP)).floor())
    var high := Vector2i((box_found.end - Vector2(SNAP, SNAP)).ceil())
    return Rect2i(low, high - low)


## The four numbers a `.sad` entry keeps, its position and its size.
func numbers() -> Array[int]:
    return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]


## The crop four numbers describe, as [method numbers] wrote them, and no
## crop for anything else.
static func read(numbers_kept: Variant) -> SaLiveCrop:
    if not numbers_kept is Array:
        return SaLiveCrop.new()
    var given: Array = numbers_kept
    if given.size() != 4:
        return SaLiveCrop.new()
    for number: Variant in given:
        if not (number is float or number is int):
            return SaLiveCrop.new()
    var n := PackedFloat64Array(given)
    return SaLiveCrop.new(Rect2i(roundi(n[0]), roundi(n[1]), roundi(n[2]), roundi(n[3])))
