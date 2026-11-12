## A closed path: contours of straight, quadratic and cubic pieces, and the
## rule that says which of the areas they bound are filled.
##
## The geometry every drawn shape hands the coverage kernel, a vector object, a
## glyph's outline or a third party's shape alike. Coordinates are document
## pixels in the path's own space, and where the path stands is an offset the
## drawer adds per chunk, so a path flattened once is drawn the same at the
## origin and a million pixels out.
##
## A contour is always closed: [method close] draws the straight piece back to
## its start, and a contour left open is closed the same way when the path is
## flattened, since a fill has no open edges.
@tool
class_name SaVectorPath
extends RefCounted

## Which areas are inside: those the outline winds round any number of times
## but nought, or those it winds round an odd number of times.
enum FillRule { NON_ZERO, EVEN_ODD }

## The constant that makes a cubic follow an arc of a quarter of its circle's
## turn or less, 4/3 tan(a/4) for the arc's angle a, here for an eighth.
const _EIGHTH_ARC_HANDLE := 0.2652164898395402

var fill_rule: FillRule = FillRule.NON_ZERO

## One entry per contour, each an Array of pieces, a piece the PackedVector2Array
## of its end and its control points: one point for a line, two for a
## quadratic, three for a cubic. The contour's start is [member _starts]'s entry.
var _contours: Array[Array] = []
var _starts: PackedVector2Array = PackedVector2Array()


func _init(rule: FillRule = FillRule.NON_ZERO) -> void:
    fill_rule = rule


## Starts a new contour at *at*, closing the one before it.
func move_to(at: Vector2) -> void:
    _starts.append(at)
    _contours.append([])


func line_to(at: Vector2) -> void:
    _piece(PackedVector2Array([at]))


func quad_to(control: Vector2, at: Vector2) -> void:
    _piece(PackedVector2Array([control, at]))


func cubic_to(first: Vector2, second: Vector2, at: Vector2) -> void:
    _piece(PackedVector2Array([first, second, at]))


## Closes the contour in hand. A contour is closed when flattened anyway, so
## this is for a caller that wants to say it.
func close() -> void:
    if not _contours.is_empty() and not _contours[-1].is_empty():
        var last: PackedVector2Array = _contours[-1][-1]
        if last[-1] != _starts[-1]:
            line_to(_starts[-1])


func is_empty() -> bool:
    return _contours.is_empty()


## A path of one contour through *points*, a polygon.
static func polygon(points: PackedVector2Array, rule: FillRule = FillRule.NON_ZERO) -> SaVectorPath:
    var path := SaVectorPath.new(rule)
    if points.is_empty():
        return path
    path.move_to(points[0])
    for i in range(1, points.size()):
        path.line_to(points[i])
    path.close()
    return path


static func rectangle(rect: Rect2, rule: FillRule = FillRule.NON_ZERO) -> SaVectorPath:
    return polygon(
        PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]),
        rule
    )


## An ellipse of *radii* round *centre*, as eight cubic arcs. An eighth of a
## turn per cubic keeps the curve within a few millionths of the radius from
## the true ellipse, where the common four arcs stray by nearly three
## ten-thousandths, which a radius of forty pixels turns into a hundredth of a
## pixel's coverage.
static func ellipse(centre: Vector2, radii: Vector2, rule: FillRule = FillRule.NON_ZERO) -> SaVectorPath:
    var path := SaVectorPath.new(rule)
    var at := func(angle: float) -> Vector2: return centre + Vector2(cos(angle), sin(angle)) * radii
    var tangent := func(angle: float) -> Vector2: return Vector2(-sin(angle), cos(angle)) * radii * _EIGHTH_ARC_HANDLE
    var start: Vector2 = at.call(0.0)
    path.move_to(start)
    for i in 8:
        var from := TAU * i / 8.0
        var to := TAU * (i + 1) / 8.0
        var end: Vector2 = start
        if i < 7:
            end = at.call(to)
        var from_at: Vector2 = at.call(from)
        var from_tangent: Vector2 = tangent.call(from)
        var to_tangent: Vector2 = tangent.call(to)
        path.cubic_to(from_at + from_tangent, end - to_tangent, end)
    return path


## Every contour as a closed polygon whose straight pieces stray from the curve
## by *tolerance* at most, in the path's units, the start not repeated at the
## end. Uniform steps in the curve's parameter, as many as the bound on its
## second derivative asks: a chord of a piece whose second derivative is at
## most D strays from it by D/8 of the square of the step.
func flatten(tolerance: float) -> Array[PackedVector2Array]:
    var flat: Array[PackedVector2Array] = []
    for c in _contours.size():
        var points := PackedVector2Array([_starts[c]])
        var from := _starts[c]
        for piece: PackedVector2Array in _contours[c]:
            match piece.size():
                1:
                    points.append(piece[0])
                2:
                    _flatten_quad(points, from, piece[0], piece[1], tolerance)
                3:
                    _flatten_cubic(points, from, piece[0], piece[1], piece[2], tolerance)
            from = piece[-1]
        if points.size() > 1 and points[-1] == points[0]:
            points.remove_at(points.size() - 1)
        if points.size() >= 3:
            flat.append(points)
    return flat


## The box round every point and control point, in the path's units. The
## curve lies inside its control points' hull, so this holds it.
func bounds() -> Rect2:
    var box := Rect2()
    var first := true
    for c in _contours.size():
        var points := PackedVector2Array([_starts[c]])
        for piece: PackedVector2Array in _contours[c]:
            points.append_array(piece)
        for p in points:
            box = Rect2(p, Vector2.ZERO) if first else box.expand(p)
            first = false
    return box


func _piece(points: PackedVector2Array) -> void:
    if _contours.is_empty():
        move_to(Vector2.ZERO)
    _contours[-1].append(points)


static func _flatten_quad(out: PackedVector2Array, p0: Vector2, p1: Vector2, p2: Vector2, tolerance: float) -> void:
    var bend := (p0 - 2.0 * p1 + p2).length() * 2.0
    var steps := maxi(1, ceili(sqrt(bend / (8.0 * tolerance))))
    for i in range(1, steps + 1):
        var t := float(i) / steps
        var u := 1.0 - t
        if i == steps:
            out.append(p2)
        else:
            out.append(p0 * (u * u) + p1 * (2.0 * u * t) + p2 * (t * t))


static func _flatten_cubic(out: PackedVector2Array, p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, tolerance: float) -> void:
    var bend := maxf((p0 - 2.0 * p1 + p2).length(), (p1 - 2.0 * p2 + p3).length()) * 6.0
    var steps := maxi(1, ceili(sqrt(bend / (8.0 * tolerance))))
    for i in range(1, steps + 1):
        var t := float(i) / steps
        var u := 1.0 - t
        if i == steps:
            out.append(p3)
        else:
            out.append(p0 * (u * u * u) + p1 * (3.0 * u * u * t) + p2 * (3.0 * u * t * t) + p3 * (t * t * t))
