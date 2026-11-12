## A path's outline at one density: straight edges in texels, cut where they
## cross and kept only where the fill rule says one side is inside and the
## other is not, each turned so the inside lies on its right as it runs down.
##
## **Why the crossings are resolved here and not by the kernel.** The kernel
## sums each edge's signed area inside a pixel, the accumulation method, which
## is the pixel's mean winding number. Coverage is that mean only where the
## winding inside the pixel is nought or one. A pixel a star's arms cross holds
## winding nought, one and two at once, and the clamp of the mean then fills
## it by the area of its winding two region a second time, a quarter of a pixel
## at a pentagram's inner corner. Cut at its crossings and kept only where it
## divides inside from outside, the outline winds once round what is filled
## and never twice, so the mean is the exact area under either rule and the
## kernel takes no rule at all.
##
## Every number is a GDScript float, 64 bits, because a crossing found in 32
## would drift off the edges it cuts. The edges are in the path's own space
## times the density, so an outline is the same wherever the path is placed.
@tool
class_name SaVectorOutline
extends RefCounted

## How finely a curve is cut, in texels of the density it is drawn at: the
## straight pieces stray from the curve by this at most. A coverage within a
## 255th of the true one leaves the chord no more than a few thousandths of a
## texel, since the sliver a chord cuts off a pixel is that wide, and a tenth
## would stray by several hundredths. A circle of forty pixels flattens into
## some four hundred edges at this tolerance.
const FLATTEN_TOLERANCE := 0.001

## How far inside a piece's ends a crossing has to lie to cut it, in its
## parameter, so a shared corner is not a crossing.
const _CUT_MARGIN := 1e-9

## How many texels high a band of the crossing search is.
const _BAND := 16.0

## Texels per document pixel this outline was made at.
var density: float = 1.0

## Four floats an edge, x and y of its start and of its end, in texels of the
## path's own space. Every edge runs down or up, never level, since a level
## edge adds no area.
var edges: PackedFloat64Array = PackedFloat64Array()

## The box round every edge, in the same texels.
var bounds: Rect2 = Rect2()


## *path* flattened, cut and kept at *texels_per_pixel*.
static func of(path: SaVectorPath, texels_per_pixel: float = 1.0) -> SaVectorOutline:
    var outline := SaVectorOutline.new()
    outline.density = texels_per_pixel
    var raw := PackedFloat64Array()
    for contour in path.flatten(FLATTEN_TOLERANCE / texels_per_pixel):
        for i in contour.size():
            var a: Vector2 = contour[i]
            var b: Vector2 = contour[(i + 1) % contour.size()]
            # A level edge is kept until the cut, since an edge crossing it
            # crosses from filled to empty there, and dropped after it.
            if a != b:
                raw.append_array([a.x * texels_per_pixel, a.y * texels_per_pixel, b.x * texels_per_pixel, b.y * texels_per_pixel])
    outline.edges = _kept(_cut(raw), path.fill_rule)
    outline.bounds = _box(outline.edges)
    return outline


func edge_count() -> int:
    @warning_ignore("integer_division")
    return edges.size() / 4


## Every edge of *raw* cut at each point where another crosses it or ends on
## it, and every level piece dropped, since it adds no area. Edges are
## compared only within the bands of the search they share.
static func _cut(raw: PackedFloat64Array) -> PackedFloat64Array:
    @warning_ignore("integer_division")
    var count := raw.size() / 4
    var cuts: Array[PackedFloat64Array] = []
    cuts.resize(count)
    for i in count:
        cuts[i] = PackedFloat64Array()
    var bands := _bands(raw)
    var reach := _reach(raw)
    for band: int in bands:
        var members: PackedInt32Array = bands[band]
        for m in members.size():
            var i := members[m]
            var first_i := floori(reach[i * 4 + 2] / _BAND)
            for n in range(m + 1, members.size()):
                var j := members[n]
                # Two edges whose boxes are apart cannot cross, and a pair
                # sharing several bands is tried in the first of them only.
                if reach[i * 4 + 1] < reach[j * 4] or reach[j * 4 + 1] < reach[i * 4]:
                    continue
                if reach[i * 4 + 3] < reach[j * 4 + 2] or reach[j * 4 + 3] < reach[i * 4 + 2]:
                    continue
                if band != maxi(first_i, floori(reach[j * 4 + 2] / _BAND)):
                    continue
                _note_crossing(raw, i, j, cuts)
    var out := PackedFloat64Array()
    for i in count:
        var ax := raw[i * 4]
        var ay := raw[i * 4 + 1]
        var bx := raw[i * 4 + 2]
        var by := raw[i * 4 + 3]
        var ts := cuts[i]
        ts.sort()
        var px := ax
        var py := ay
        for t in ts:
            var qx := ax + (bx - ax) * t
            var qy := ay + (by - ay) * t
            if qy != py:
                out.append_array([px, py, qx, qy])
            px = qx
            py = qy
        if by != py:
            out.append_array([px, py, bx, by])
    return out


## Four floats an edge of *raw*: the left and right of its box, then its top
## and bottom.
static func _reach(raw: PackedFloat64Array) -> PackedFloat64Array:
    var out := PackedFloat64Array()
    out.resize(raw.size())
    @warning_ignore("integer_division")
    for i in raw.size() / 4:
        out[i * 4] = minf(raw[i * 4], raw[i * 4 + 2])
        out[i * 4 + 1] = maxf(raw[i * 4], raw[i * 4 + 2])
        out[i * 4 + 2] = minf(raw[i * 4 + 1], raw[i * 4 + 3])
        out[i * 4 + 3] = maxf(raw[i * 4 + 1], raw[i * 4 + 3])
    return out


## Records where edges *i* and *j* cut each other, the parameter along each,
## when they cross or one ends on the other. Parallel edges never cut.
static func _note_crossing(raw: PackedFloat64Array, i: int, j: int, cuts: Array[PackedFloat64Array]) -> void:
    var ax := raw[i * 4]
    var ay := raw[i * 4 + 1]
    var rx := raw[i * 4 + 2] - ax
    var ry := raw[i * 4 + 3] - ay
    var cx := raw[j * 4]
    var cy := raw[j * 4 + 1]
    var sx := raw[j * 4 + 2] - cx
    var sy := raw[j * 4 + 3] - cy
    var across := rx * sy - ry * sx
    if across == 0.0:
        return
    var qx := cx - ax
    var qy := cy - ay
    var t := (qx * sy - qy * sx) / across
    var u := (qx * ry - qy * rx) / across
    if t < 0.0 or t > 1.0 or u < 0.0 or u > 1.0:
        return
    if t > _CUT_MARGIN and t < 1.0 - _CUT_MARGIN:
        cuts[i].append(t)
    if u > _CUT_MARGIN and u < 1.0 - _CUT_MARGIN:
        cuts[j].append(u)


## The edges of *cut* that divide filled from empty under *rule*, each turned
## to run down where the inside is on its right and up where it is on its
## left, so the winding they make is one inside and nought outside.
##
## The winding just left of an edge is counted at its middle along a ray to
## the left, every other edge the ray crosses adding its direction, and the
## winding just right of it is that plus its own direction.
static func _kept(cut: PackedFloat64Array, rule: SaVectorPath.FillRule) -> PackedFloat64Array:
    var bands := _bands(cut)
    var out := PackedFloat64Array()
    @warning_ignore("integer_division")
    for i in cut.size() / 4:
        var ax := cut[i * 4]
        var ay := cut[i * 4 + 1]
        var bx := cut[i * 4 + 2]
        var by := cut[i * 4 + 3]
        var mx := (ax + bx) * 0.5
        var my := (ay + by) * 0.5
        var direction := 1 if by > ay else -1
        var left := 0
        for j: int in bands.get(floori(my / _BAND), PackedInt32Array()):
            if j == i:
                continue
            var jy0 := cut[j * 4 + 1]
            var jy1 := cut[j * 4 + 3]
            var top := minf(jy0, jy1)
            var bottom := maxf(jy0, jy1)
            if my < top or my >= bottom:
                continue
            var jx0 := cut[j * 4]
            var x := jx0 + (cut[j * 4 + 2] - jx0) * (my - jy0) / (jy1 - jy0)
            if x < mx:
                left += 1 if jy1 > jy0 else -1
        var inside_left := _filled(left, rule)
        var inside_right := _filled(left + direction, rule)
        if inside_left == inside_right:
            continue
        var wanted := 1 if inside_right else -1
        if wanted == direction:
            out.append_array([ax, ay, bx, by])
        else:
            out.append_array([bx, by, ax, ay])
    return out


static func _filled(winding: int, rule: SaVectorPath.FillRule) -> bool:
    if rule == SaVectorPath.FillRule.EVEN_ODD:
        return winding % 2 != 0
    return winding != 0


## Each band of the search, by its index, holding every edge whose height
## reaches into it.
static func _bands(raw: PackedFloat64Array) -> Dictionary[int, PackedInt32Array]:
    var bands: Dictionary[int, PackedInt32Array] = {}
    @warning_ignore("integer_division")
    for i in raw.size() / 4:
        var top := minf(raw[i * 4 + 1], raw[i * 4 + 3])
        var bottom := maxf(raw[i * 4 + 1], raw[i * 4 + 3])
        for band in range(floori(top / _BAND), floori(bottom / _BAND) + 1):
            if not bands.has(band):
                bands[band] = PackedInt32Array()
            bands[band].append(i)
    return bands


static func _box(edges_in: PackedFloat64Array) -> Rect2:
    if edges_in.is_empty():
        return Rect2()
    var left := INF
    var top := INF
    var right := -INF
    var bottom := -INF
    @warning_ignore("integer_division")
    for i in edges_in.size() / 4:
        for k: int in [0, 2]:
            left = minf(left, edges_in[i * 4 + k])
            right = maxf(right, edges_in[i * 4 + k])
            top = minf(top, edges_in[i * 4 + k + 1])
            bottom = maxf(bottom, edges_in[i * 4 + k + 1])
    return Rect2(left, top, right - left, bottom - top)
