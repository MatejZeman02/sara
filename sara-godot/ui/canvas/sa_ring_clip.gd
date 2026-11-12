## The ring's arc arithmetic: which parts of a circle fall inside a rectangle,
## and the points to draw them with.
##
## Its own file, and a move rather than a rewrite: every function below is the text
## that was in `ui/canvas/cursor_overlay.gd`, argument for argument, and
## `CursorOverlay.visible_ring_spans` forwards here so the name every test and every
## reader already knows still answers.
##
## **The cut is the natural one.** None of this is about drawing: it takes a
## centre, a radius and a rectangle and answers angles.
class_name SaRingClip
extends RefCounted

## How long a chord of the ring is allowed to be, in logical pixels.
##
## The segment count follows from this and the *visible* arc length, so a ring
## of any radius is drawn at the same smoothness for the same cost. It replaces
## a fixed count of 48, which was coarse at a large radius and forty-seven
## segments of nothing at a radius past the window.
##
## Six pixels, because the error of a chord against its arc is about
## `chord^2 / (8 * radius)`: at six pixels that is under a tenth of a pixel from
## a radius of 50 up, and the eye reads the ring as round from the smallest
## brush a painter uses.
const RING_SEGMENT_PX: float = 6.0

## The most segments one visible span is allowed, whatever the arithmetic says.
##
## A window's diagonal is the longest visible arc there can be, so this is
## reached only by a ring whose radius is close to that diagonal, and it is here
## as a promise rather than as a limit anyone meets: a `NaN` radius or a rect
## with a nonsense size cannot ask the draw loop for a million points.
const RING_MAX_SEGMENTS: int = 720


## The angular spans of the ring that lie inside *rect*, as `[from, to]` pairs
## in radians, ordered and never wrapping past TAU.
##
## **Analytic rather than sampled**, which is the point of it. A circle is
## inside an axis-aligned rectangle where four inequalities hold at once:
## `cos` bounded either side by the rectangle's x edges and `sin` by its y ones.
## Each of the four is one arc of the circle, or all of it, or none, so the
## visible set is the intersection of four arcs and never needs a point tested.
## Sampling the circle to find out which parts are on screen would cost exactly
## what this exists to avoid.
##
## Answered as a list because the intersection of four arcs can have more than
## one component: a ring larger than the window crosses it as two arcs, one at
## each side, and drawing the span between them would draw a chord across the
## canvas.
##
## Static, so `ui/canvas/tests/test_cursor_overlay.gd` can read the geometry without a
## window, and so the prediction can ask the same question of a moved centre.
static func visible_ring_spans(center: Vector2, radius: float, rect: Rect2) -> Array[Vector2]:
    if not is_finite(radius) or radius <= 0.0 or rect.size.x <= 0.0 or rect.size.y <= 0.0:
        return [] as Array[Vector2]

    var spans: Array[Vector2] = [Vector2(0.0, TAU)]
    # The order is the rectangle's four edges: left, right, top, bottom. Each
    # narrows the set, and an edge the ring never reaches narrows it to nothing.
    spans = _intersect_spans(spans, _cos_at_least((rect.position.x - center.x) / radius))
    spans = _intersect_spans(spans, _cos_at_most((rect.end.x - center.x) / radius))
    spans = _intersect_spans(spans, _sin_at_least((rect.position.y - center.y) / radius))
    spans = _intersect_spans(spans, _sin_at_most((rect.end.y - center.y) / radius))
    return spans


## One visible span as a polyline, at [constant RING_SEGMENT_PX] a chord.
##
## The first and last points sit exactly on the span's ends, so a span that
## stops at the window edge stops there rather than a chord short of it.
static func arc_points(center: Vector2, radius: float, from_angle: float, to_angle: float) -> PackedVector2Array:
    var sweep := to_angle - from_angle
    if sweep <= 0.0:
        return PackedVector2Array()
    var wanted := int(ceil(sweep * radius / RING_SEGMENT_PX))
    var segments := clampi(wanted, 1, RING_MAX_SEGMENTS)
    var points := PackedVector2Array()
    points.resize(segments + 1)
    for i in segments + 1:
        var angle := from_angle + sweep * float(i) / float(segments)
        points[i] = center + Vector2(cos(angle), sin(angle)) * radius
    return points


## Where `cos` is at least *bound*, as spans in `[0, TAU]`.
static func _cos_at_least(bound: float) -> Array[Vector2]:
    if bound <= -1.0:
        return [Vector2(0.0, TAU)] as Array[Vector2]
    if bound > 1.0:
        return [] as Array[Vector2]
    var edge := acos(bound)
    return _wrapped_span(-edge, edge)


## Where `cos` is at most *bound*.
static func _cos_at_most(bound: float) -> Array[Vector2]:
    if bound >= 1.0:
        return [Vector2(0.0, TAU)] as Array[Vector2]
    if bound < -1.0:
        return [] as Array[Vector2]
    var edge := acos(bound)
    return _wrapped_span(edge, TAU - edge)


## Where `sin` is at least *bound*. In screen space `sin` grows downwards, which
## costs this nothing: the spans are the same set read the other way up.
static func _sin_at_least(bound: float) -> Array[Vector2]:
    if bound <= -1.0:
        return [Vector2(0.0, TAU)] as Array[Vector2]
    if bound > 1.0:
        return [] as Array[Vector2]
    var edge := asin(bound)
    return _wrapped_span(edge, PI - edge)


## Where `sin` is at most *bound*.
static func _sin_at_most(bound: float) -> Array[Vector2]:
    if bound >= 1.0:
        return [Vector2(0.0, TAU)] as Array[Vector2]
    if bound < -1.0:
        return [] as Array[Vector2]
    var edge := asin(bound)
    return _wrapped_span(PI - edge, TAU + edge)


## *from* to *to*, cut at TAU into spans that do not wrap.
##
## Every span this file works with lives in `[0, TAU]` and runs forwards, which
## is what lets the intersection below be two `max` and `min` calls. The cost is
## that a span across zero arrives as two, and that is why the answer is a list.
static func _wrapped_span(from_angle: float, to_angle: float) -> Array[Vector2]:
    var lo := fmod(from_angle, TAU)
    if lo < 0.0:
        lo += TAU
    var sweep := minf(to_angle - from_angle, TAU)
    if sweep <= 0.0:
        return [] as Array[Vector2]
    var hi := lo + sweep
    if hi <= TAU:
        return [Vector2(lo, hi)] as Array[Vector2]
    return [Vector2(0.0, hi - TAU), Vector2(lo, TAU)] as Array[Vector2]


## The overlap of two span lists, both in `[0, TAU]` and both forwards.
static func _intersect_spans(left: Array[Vector2], right: Array[Vector2]) -> Array[Vector2]:
    var out: Array[Vector2] = []
    for a: Vector2 in left:
        for b: Vector2 in right:
            var lo := maxf(a.x, b.x)
            var hi := minf(a.y, b.y)
            if hi > lo:
                out.append(Vector2(lo, hi))
    out.sort_custom(func(one: Vector2, two: Vector2) -> bool: return one.x < two.x)
    return out
