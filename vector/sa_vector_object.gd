## One object of a vector layer: a rectangle with rounded corners or an
## ellipse, its solid fill and its stroke, each a float colour in the
## document's own space that nothing clamps (hard rule 5).
##
## **Kept as its numbers**, a box in document pixels and a corner radius,
## so a resize is exact and a redraw at any zoom is sharp. The renderer sees it only as the two
## closed paths [method parts] hands over, the fill and the stroke's ring,
## drawn through `SaVectorFill` relative to the chunk being drawn.
##
## **The stroke is centred on the outline.** A rectangle's ring is its box
## grown by half the width with a mitred corner, or a radius grown by as much,
## less its box shrunk by the same half. An ellipse's ring is its two parallel
## curves sampled finely enough that a chord leaves a thousandth of a pixel,
## which the kernel's flattening tolerance is, so the ring's edge is as exact
## as the fill's. An inner curve past the ellipse's tightest bend would loop,
## so there the hole is Godot's offset of the outline instead.
@tool
extends RefCounted

enum Kind { RECT, ELLIPSE }

## A cubic handle that draws a quarter circle within a ten thousandth of it.
const QUARTER_ARC := 0.5522847498307936
## How far a chord of the ellipse's ring may stray from the curve, in pixels,
## the tolerance the kernel flattens a curve to.
const RING_TOLERANCE := SaVectorOutline.FLATTEN_TOLERANCE
## The fewest and the most points a ring's curve is sampled at.
const RING_POINTS_MIN := 64
const RING_POINTS_MAX := 8192

## Stable in the document, a short string the door and the list name it by.
var id: String = ""
## What the objects list shows.
var name: String = ""
var kind: Kind = Kind.RECT
## The rectangle's own box, or the box the ellipse is inscribed in.
var box: Rect2 = Rect2()
## A rectangle's corner radius in document pixels, held to half its shorter
## side when drawn. An ellipse has none.
var radius: float = 0.0
## The fill's colour, alpha its opacity, and whether there is a fill.
var fill: Color = Color.WHITE
var filled: bool = true
## The stroke's colour and width in document pixels, none at a width of 0.
var stroke: Color = Color.BLACK
var stroke_width: float = 0.0
var visible: bool = true
## A locked object is drawn and listed and never picked on the canvas.
var locked: bool = false
## The object's opacity, multiplied into the fill's and the stroke's alpha.
var opacity: float = 1.0
## Whether the stroke is drawn under the fill, which comic lettering wants.
var stroke_first: bool = false

## The shape [method parts] made its paths for, and those paths.
var _shape_key: String = ""
var _fill_held: SaVectorPath = null
var _stroke_held: SaVectorPath = null


func _init(made_kind: Kind = Kind.RECT, made_box: Rect2 = Rect2()) -> void:
    kind = made_kind
    box = made_box.abs()


## The pixels the object draws on, its stroke's outer half and a pixel of edge
## included, in whole document pixels.
func bounds() -> Rect2i:
    var reach := box.grow(_half())
    var start := Vector2i(floori(reach.position.x), floori(reach.position.y)) - Vector2i.ONE
    var end := Vector2i(ceili(reach.end.x), ceili(reach.end.y)) + Vector2i.ONE
    return Rect2i(start, end - start)


## Whether *point*, in document pixels, lands on the object, a fill or a
## stroke, within *reach* pixels of its outer edge.
func has_point(point: Vector2, reach: float = 0.0) -> bool:
    var grown := _half() + maxf(reach, 0.0)
    if kind == Kind.RECT:
        return box.grow(grown).has_point(point)
    var radii := box.size * 0.5 + Vector2(grown, grown)
    if radii.x <= 0.0 or radii.y <= 0.0:
        return false
    var offset := (point - box.get_center()) / radii
    return offset.length_squared() <= 1.0


## The closed paths the object is drawn from, bottom first, each with the
## colour it is painted in: `[[SaVectorPath, Color], ...]`, in pixels from
## [method origin].
##
## The paths are made again only when the shape changes, and a move by whole
## pixels changes only the origin, so the same two paths reach the kernel
## frame after frame and it resolves their outline once (`SaVectorFill`).
func parts() -> Array[Array]:
    var key := var_to_str([kind, _local_box(), _corner(), _half()])
    if key != _shape_key:
        _shape_key = key
        _fill_held = fill_path()
        _stroke_held = stroke_path()
    var fill_part: Array = []
    var stroke_part: Array = []
    if filled and fill.a * opacity > 0.0 and box.size.x > 0.0 and box.size.y > 0.0:
        fill_part = [_fill_held, _faded(fill)]
    if stroke_width > 0.0 and stroke.a * opacity > 0.0:
        stroke_part = [_stroke_held, _faded(stroke)]
    var out: Array[Array] = []
    for part: Array in [stroke_part, fill_part] if stroke_first else [fill_part, stroke_part]:
        if not part.is_empty() and not (part[0] as SaVectorPath).is_empty():
            out.append(part)
    return out


## The whole document pixel the paths of [method parts] are drawn from, the
## box's corner rounded down.
func origin() -> Vector2i:
    return Vector2i(floori(box.position.x), floori(box.position.y))


## The filled outline, from [method origin].
func fill_path() -> SaVectorPath:
    var local := _local_box()
    if kind == Kind.ELLIPSE:
        return SaVectorPath.ellipse(local.get_center(), local.size * 0.5)
    var path := SaVectorPath.new()
    _rounded(path, local, _corner())
    return path


## The stroke's ring, filled under the even-odd rule so the inner contour
## is a hole whichever way it winds, from [method origin].
func stroke_path() -> SaVectorPath:
    var path := SaVectorPath.new(SaVectorPath.FillRule.EVEN_ODD)
    var local := _local_box()
    var half := _half()
    if half <= 0.0:
        return path
    if kind == Kind.RECT:
        var corner := _corner()
        _rounded(path, local.grow(half), corner + half if corner > 0.0 else 0.0)
        var inner := local.grow(-half)
        if inner.size.x > 0.0 and inner.size.y > 0.0:
            _rounded(path, inner, maxf(corner - half, 0.0))
        return path
    _contour(path, ring(local, half))
    var radii := local.size * 0.5
    var tightest := minf(radii.x, radii.y) ** 2 / maxf(maxf(radii.x, radii.y), 1e-9)
    if half < tightest:
        _contour(path, ring(local, -half))
        return path
    for hole: PackedVector2Array in Geometry2D.offset_polygon(ring(local, 0.0), -half):
        _contour(path, hole)
    return path


## The curve *offset* pixels outside the ellipse inscribed in *ellipse_box*,
## inside for a negative *offset*, sampled so a chord strays from it by
## [constant RING_TOLERANCE] at most. A chord's stray is largest where the
## curve bends most, the ends of the long axis, and there it is the long
## radius times the square of the angle's step over eight.
static func ring(ellipse_box: Rect2, offset: float) -> PackedVector2Array:
    var radii := ellipse_box.size * 0.5
    var centre := ellipse_box.get_center()
    var widest := maxf(maxf(radii.x, radii.y) + absf(offset), 1.0)
    var step := sqrt(8.0 * RING_TOLERANCE / widest)
    var count := clampi(ceili(TAU / step), RING_POINTS_MIN, RING_POINTS_MAX)
    var points := PackedVector2Array()
    points.resize(count)
    for i in count:
        var angle := TAU * i / count
        var along := Vector2(cos(angle) * radii.x, sin(angle) * radii.y)
        var normal := Vector2(cos(angle) * radii.y, sin(angle) * radii.x)
        var length := normal.length()
        points[i] = centre + along + (normal / length * offset if length > 0.0 else Vector2.ZERO)
    return points


## Everything the object is, as plain values: the kind's own numbers, a
## rectangle's corner and size and an ellipse's centre and radii.
func to_json() -> Dictionary:
    var fill_json: Variant = null
    if filled:
        fill_json = [fill.r, fill.g, fill.b, fill.a]
    var out := {
        "id": id,
        "name": name,
        "kind": "ellipse" if kind == Kind.ELLIPSE else "rect",
        "fill": fill_json,
        "stroke": [stroke.r, stroke.g, stroke.b, stroke.a],
        "stroke_width": stroke_width,
        "visible": visible,
        "locked": locked,
        "opacity": opacity,
        "paint_order": "stroke" if stroke_first else "fill",
    }
    if kind == Kind.ELLIPSE:
        var centre := box.get_center()
        out["centre"] = [centre.x, centre.y]
        out["radii"] = [box.size.x * 0.5, box.size.y * 0.5]
    else:
        out["corner"] = [box.position.x, box.position.y]
        out["size"] = [box.size.x, box.size.y]
        out["radius"] = radius
    return out


## Becomes what *saved*, a dictionary [method to_json] wrote, describes, and
## answers whether its kind is a rectangle or an ellipse. One that is neither
## is left as it was.
func read(saved: Dictionary) -> bool:
    var saved_kind: String = String(saved.get("kind", ""))
    if saved_kind != "rect" and saved_kind != "ellipse":
        return false
    id = String(saved.get("id", ""))
    name = String(saved.get("name", ""))
    if saved_kind == "ellipse":
        var centre := _pair(saved.get("centre"))
        var radii := _pair(saved.get("radii")).abs()
        kind = Kind.ELLIPSE
        box = Rect2(centre - radii, radii * 2.0)
        radius = 0.0
    else:
        kind = Kind.RECT
        box = Rect2(_pair(saved.get("corner")), _pair(saved.get("size"))).abs()
        radius = maxf(float(saved.get("radius", 0.0)), 0.0)
    var held_fill: Variant = saved.get("fill")
    filled = held_fill is Array and (held_fill as Array).size() == 4
    if filled:
        fill = _colour(held_fill)
    stroke = _colour(saved.get("stroke", [0.0, 0.0, 0.0, 1.0]))
    stroke_width = maxf(float(saved.get("stroke_width", 0.0)), 0.0)
    visible = bool(saved.get("visible", true))
    locked = bool(saved.get("locked", false))
    opacity = clampf(float(saved.get("opacity", 1.0)), 0.0, 1.0)
    stroke_first = String(saved.get("paint_order", "fill")) == "stroke"
    return true


## The box from [method origin].
func _local_box() -> Rect2:
    return Rect2(box.position - Vector2(origin()), box.size)


func _half() -> float:
    return maxf(stroke_width, 0.0) * 0.5


func _corner() -> float:
    if kind != Kind.RECT:
        return 0.0
    return clampf(radius, 0.0, minf(box.size.x, box.size.y) * 0.5)


func _faded(colour: Color) -> Color:
    return Color(colour.r, colour.g, colour.b, colour.a * opacity)


## Adds *rect* to *path* as one closed contour, its corners rounded to
## *corner* pixels by quarter circles drawn as cubics.
static func _rounded(path: SaVectorPath, rect: Rect2, corner: float) -> void:
    var r := clampf(corner, 0.0, minf(rect.size.x, rect.size.y) * 0.5)
    var a := rect.position
    var b := rect.end
    if r <= 0.0:
        path.move_to(a)
        path.line_to(Vector2(b.x, a.y))
        path.line_to(b)
        path.line_to(Vector2(a.x, b.y))
        path.close()
        return
    var k := r * (1.0 - QUARTER_ARC)
    path.move_to(Vector2(a.x + r, a.y))
    path.line_to(Vector2(b.x - r, a.y))
    path.cubic_to(Vector2(b.x - k, a.y), Vector2(b.x, a.y + k), Vector2(b.x, a.y + r))
    path.line_to(Vector2(b.x, b.y - r))
    path.cubic_to(Vector2(b.x, b.y - k), Vector2(b.x - k, b.y), Vector2(b.x - r, b.y))
    path.line_to(Vector2(a.x + r, b.y))
    path.cubic_to(Vector2(a.x + k, b.y), Vector2(a.x, b.y - k), Vector2(a.x, b.y - r))
    path.line_to(Vector2(a.x, a.y + r))
    path.cubic_to(Vector2(a.x, a.y + k), Vector2(a.x + k, a.y), Vector2(a.x + r, a.y))
    path.close()


static func _contour(path: SaVectorPath, points: PackedVector2Array) -> void:
    if points.size() < 3:
        return
    path.move_to(points[0])
    for i in range(1, points.size()):
        path.line_to(points[i])
    path.close()


static func _pair(held: Variant) -> Vector2:
    if held is Array and (held as Array).size() == 2:
        return Vector2(float(held[0]), float(held[1]))
    return Vector2.ZERO


static func _colour(held: Variant) -> Color:
    if held is Array and (held as Array).size() == 4:
        return Color(float(held[0]), float(held[1]), float(held[2]), float(held[3]))
    return Color.BLACK
