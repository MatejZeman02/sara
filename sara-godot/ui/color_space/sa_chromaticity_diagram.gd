## The CIE 1931 xy diagram: the horseshoe, a gamut triangle over it, and the
## white point.
##
## Every chromaticity a human can see lies inside the horseshoe, and no three
## real primaries can cover all of it, which is why a gamut is a triangle drawn
## over a curved shape it can never fill. That is the whole argument the picture
## makes, and both halves of it have to be right for it to make it: a shape with
## visible corners reads as an approximation of something, and an interior whose
## colours come from a triangulation rather than from the chromaticities reads
## as decoration.
##
## Cut out of `ui/color_space/color_space_browser.gd`, following `SaGamutSolid` beside it. A
## class that owns something rather than a cut by count: this one owns the shape of the
## locus, how densely it is sampled, the colour of every point inside it and the marks drawn
## over it, and the browser owns the page the three drawings sit on.
@tool
class_name SaChromaticityDiagram
extends Control

## The CIE 1931 2-degree observer, 10 nm steps from 380 to 700 nm.
##
## Control points rather than the drawing. `locus()` runs a spline through them
## and the drawing uses that, because 10 nm is four long chords across the green
## flank between 480 and 520 nm, where the locus turns hardest, and those chords
## are the edged shape to avoid.
const OBSERVER: Array[Vector2] = [
    Vector2(0.1741, 0.0050),
    Vector2(0.1738, 0.0049),
    Vector2(0.1733, 0.0048),
    Vector2(0.1726, 0.0048),
    Vector2(0.1714, 0.0051),
    Vector2(0.1689, 0.0069),
    Vector2(0.1644, 0.0109),
    Vector2(0.1566, 0.0177),
    Vector2(0.1440, 0.0297),
    Vector2(0.1241, 0.0578),
    Vector2(0.0913, 0.1327),
    Vector2(0.0454, 0.2950),
    Vector2(0.0082, 0.5384),
    Vector2(0.0139, 0.7502),
    Vector2(0.0743, 0.8338),
    Vector2(0.1547, 0.8059),
    Vector2(0.2296, 0.7543),
    Vector2(0.3016, 0.6923),
    Vector2(0.3731, 0.6245),
    Vector2(0.4441, 0.5547),
    Vector2(0.5125, 0.4866),
    Vector2(0.5752, 0.4242),
    Vector2(0.6270, 0.3725),
    Vector2(0.6658, 0.3340),
    Vector2(0.6915, 0.3083),
    Vector2(0.7079, 0.2920),
    Vector2(0.7190, 0.2809),
    Vector2(0.7260, 0.2740),
    Vector2(0.7300, 0.2700),
    Vector2(0.7320, 0.2680),
    Vector2(0.7334, 0.2666),
    Vector2(0.7344, 0.2656),
    Vector2(0.7347, 0.2653),
]

## The plotted window in CIE xy. Wide enough for Rec. 2020's green, which sits
## well outside anything an sRGB-shaped axis would show.
const PLOT_MAX := Vector2(0.8, 0.9)

## The longest chord the drawn locus may have, in the control's own pixels.
## Under one pixel is the whole requirement: a chord shorter than a pixel cannot
## be seen as a straight run however hard the locus is turning there.
const CHORD_PX := 1.0

## Samples used to guess a spline segment's length before subdividing it, and
## how many times a segment may be subdivided again when the guess came out
## short. Centripetal Catmull-Rom does not space equal steps of *t* equally
## along the curve, so the first guess is about a quarter under on the sharpest
## segment and the measure-and-subdivide-again pass is what actually holds
## [constant CHORD_PX].
const ARC_SAMPLES: int = 8
const FIT_PASSES: int = 4

## The tallest the diagram grows to, logical units, and the shortest it is.
##
## The picture is square-axis, so its size is whichever of the two the control
## has less of, and a control that expands across a maximised page and keeps a
## fixed height would leave the picture the size a 240-wide page gave it and the
## rest of the row empty. The height follows the width up to this, and the cap
## is here so the drawing does not push the transfer curve and the volume under
## it off the page: a page that is a metre wide does not want a metre of
## horseshoe.
const MIN_HEIGHT: int = 250
const MAX_HEIGHT: int = 520

## The baked interior, in texels. The aspect is [constant PLOT_MAX]'s exactly,
## so the picture stretches into the control with no distortion, and it is one
## picture for every size and every colour space: what is inside the horseshoe
## does not depend on which triangle is drawn over it.
const PICTURE := Vector2i(256, 288)

var space: SaColorSpace = null

## The larger gamut to compare against, or null to draw *space* alone the way
## this first looked.
var compare: SaGamut = null

## The interior, built on the first ask and kept for the life of the process,
## the way [method SaGamutPreview.picture] keeps its own.
static var _picture: ImageTexture = null

var _locus: PackedVector2Array = PackedVector2Array()
var _locus_at: Vector2 = Vector2.ZERO


func _init() -> void:
    custom_minimum_size = Vector2(float(SaUI.px(240)), float(SaUI.px(MIN_HEIGHT)))
    size_flags_horizontal = Control.SIZE_EXPAND_FILL
    # The interior is baked at a fixed resolution and stretched, so the upscale
    # has to be smoothed. A nearest-neighbour stretch of a smooth field is the
    # one way to put edges back into a picture drawn to have none.
    texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR


func _notification(what: int) -> void:
    if what != NOTIFICATION_RESIZED:
        return
    # The height follows the width, which is what lets a wider page draw a
    # bigger picture rather than the same one with more empty space beside it.
    # Written only when it changes, because a minimum size set inside a resize
    # is a resize, and a container asked to sort its children every pass over
    # the same numbers never settles.
    var wanted := clampf(size.x * PLOT_MAX.y / PLOT_MAX.x, float(SaUI.px(MIN_HEIGHT)), float(SaUI.px(MAX_HEIGHT)))
    if is_equal_approx(custom_minimum_size.y, wanted):
        return
    custom_minimum_size.y = wanted
    update_minimum_size()


## The part of the control the diagram is drawn in: as large as fits, centred,
## and with x and y at the same scale.
##
## A chromaticity diagram with unequal axes is not the wanted shape
## either. The control is a row of a `VBoxContainer` and expands to the width of
## the page, which is three times its height on a maximised window, and the
## horseshoe was drawn stretched across all of it: the same curve, in a picture
## nobody would recognise from a colour text. The section does not name this,
## and it is the same sentence, so it is fixed here and said in the record.
func plot_rect() -> Rect2:
    if size.x <= 0.0 or size.y <= 0.0:
        return Rect2()
    var span := minf(size.x / PLOT_MAX.x, size.y / PLOT_MAX.y)
    var drawn := PLOT_MAX * span
    return Rect2(Vector2((size.x - drawn.x) * 0.5, (size.y - drawn.y) * 0.5), drawn)


## CIE xy to control pixels, y up.
func to_plot(xy: Vector2) -> Vector2:
    var rect := plot_rect()
    return Vector2(rect.position.x + xy.x / PLOT_MAX.x * rect.size.x, rect.end.y - xy.y / PLOT_MAX.y * rect.size.y)


## An approximate display colour for a chromaticity, for the fill only.
##
## Normalised to its own peak rather than gamut-mapped, so this is a legible
## picture and not a colorimetric claim: most of the horseshoe is outside any
## display's gamut by construction and cannot be shown honestly.
##
## *to_rgb* is handed in rather than asked for, because the fill asks this about
## forty thousand times and `SaColorSpace.srgb()` builds a colour space each
## time it is called.
static func swatch(xy: Vector2, to_rgb: Basis) -> Color:
    if xy.y <= 0.0001:
        return Color(0.1, 0.1, 0.1)
    var xyz := Vector3(xy.x / xy.y, 1.0, (1.0 - xy.x - xy.y) / xy.y)
    var linear: Vector3 = to_rgb * xyz
    linear = Vector3(maxf(linear.x, 0.0), maxf(linear.y, 0.0), maxf(linear.z, 0.0))
    var peak: float = maxf(linear.x, maxf(linear.y, linear.z))
    if peak <= 0.0:
        return Color(0.1, 0.1, 0.1)
    linear /= peak
    return Color(linear.x, linear.y, linear.z).linear_to_srgb()


## The locus as a curve with no chord longer than *max_px*, in CIE xy.
##
## *per_unit* is xy to pixels, so the density follows the size the picture is drawn
## at rather than a number written down here: the same curve is asked for at one
## density for a 240-wide preview and at another for a maximised page, and both
## answers are chord-free at their own size.
##
## Centripetal Catmull-Rom through [constant OBSERVER] rather than 1 nm observer
## data. Interpolating is acceptable here and the table is what the repo
## has, and 321 more constants would be a data file pretending to be a class.
static func curve(per_unit: Vector2, max_px: float) -> PackedVector2Array:
    var out := PackedVector2Array()
    var last := OBSERVER.size() - 1
    var step := maxf(max_px, 0.01)
    for i in last:
        var p0: Vector2 = OBSERVER[maxi(i - 1, 0)]
        var p1: Vector2 = OBSERVER[i]
        var p2: Vector2 = OBSERVER[i + 1]
        var p3: Vector2 = OBSERVER[mini(i + 2, last)]
        var points := _segment(p0, p1, p2, p3, ARC_SAMPLES)
        var steps := maxi(1, int(ceil(_arc(points, per_unit) / step)))
        for _pass in FIT_PASSES:
            points = _segment(p0, p1, p2, p3, steps)
            var longest := _longest(points, per_unit)
            if longest <= step:
                break
            steps = int(ceil(float(steps) * longest / step))
        for k in points.size() - 1:
            out.append(points[k])
    out.append(OBSERVER[last])
    return out


## One spline segment as *steps* chords, ends included.
static func _segment(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, steps: int) -> PackedVector2Array:
    var out := PackedVector2Array()
    for k in steps + 1:
        out.append(_spline(p0, p1, p2, p3, float(k) / float(steps)))
    return out


## The longest chord of *points*, measured in the pixels *per_unit* puts them in.
static func _longest(points: PackedVector2Array, per_unit: Vector2) -> float:
    var longest := 0.0
    for i in points.size() - 1:
        longest = maxf(longest, ((points[i + 1] - points[i]) * per_unit).length())
    return longest


## The length of the chain *points*, in the same pixels.
static func _arc(points: PackedVector2Array, per_unit: Vector2) -> float:
    var total := 0.0
    for i in points.size() - 1:
        total += ((points[i + 1] - points[i]) * per_unit).length()
    return total


## Centripetal Catmull-Rom at *t* in the *p1* to *p2* span.
##
## Centripetal rather than uniform, which is the alpha 0.5 in the knot spacing:
## a uniform spline loops back on itself where the samples bunch, and the
## observer's samples bunch at both ends of the locus, where ten nanometres of
## wavelength move the chromaticity almost nowhere.
static func _spline(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
    var t0 := 0.0
    var t1 := t0 + sqrt(p0.distance_to(p1))
    var t2 := t1 + sqrt(p1.distance_to(p2))
    var t3 := t2 + sqrt(p2.distance_to(p3))
    if t1 <= t0 or t2 <= t1 or t3 <= t2:
        return p1.lerp(p2, t)
    var at := t1 + (t2 - t1) * t
    var a1 := _knot(p0, p1, t0, t1, at)
    var a2 := _knot(p1, p2, t1, t2, at)
    var a3 := _knot(p2, p3, t2, t3, at)
    var b1 := _knot(a1, a2, t0, t2, at)
    var b2 := _knot(a2, a3, t1, t3, at)
    return _knot(b1, b2, t1, t2, at)


static func _knot(a: Vector2, b: Vector2, ta: float, tb: float, at: float) -> Vector2:
    if tb <= ta:
        return a
    return a.lerp(b, (at - ta) / (tb - ta))


## The locus at this control's own size, kept until the size changes.
func locus() -> PackedVector2Array:
    var rect := plot_rect()
    if rect.size == _locus_at and not _locus.is_empty():
        return _locus
    _locus_at = rect.size
    if rect.size.x <= 0.0:
        _locus = PackedVector2Array()
        return _locus
    _locus = curve(Vector2(rect.size.x / PLOT_MAX.x, rect.size.y / PLOT_MAX.y), CHORD_PX)
    return _locus


## The interior, one texel per chromaticity, built on the first ask and kept.
##
## Every texel inside the horseshoe is its own chromaticity's colour and every
## texel outside it is transparent, which avoids weird
## colours: `draw_polygon` with a colour per vertex hands Godot a concave
## polygon, and what came back was a triangulation of thirty-three boundary
## swatches interpolated across, so an interior pixel's colour depended on which
## three vertices its triangle happened to be built from.
##
## The edge is anti-aliased by coverage rather than left hard, because this is
## stretched to about twice its size on the page and a hard edge would upscale
## into a two-pixel staircase under the outline.
static func picture() -> ImageTexture:
    if _picture != null:
        return _picture
    var image := Image.create_empty(PICTURE.x, PICTURE.y, false, Image.FORMAT_RGBA8)
    var to_rgb := SaColorSpace.srgb().xyz_to_rgb()
    var texel := Vector2(PLOT_MAX.x / float(PICTURE.x), PLOT_MAX.y / float(PICTURE.y))
    var spans := _spans()
    image.fill(Color(0.0, 0.0, 0.0, 0.0))
    for py in PICTURE.y:
        var top: Vector2 = spans[py * 2]
        var bottom: Vector2 = spans[py * 2 + 1]
        if top.y < top.x and bottom.y < bottom.x:
            continue
        var y := PLOT_MAX.y - (float(py) + 0.5) * texel.y
        for px in PICTURE.x:
            var left := float(px)
            var right := left + 1.0
            var covered := _overlap(left, right, top) + _overlap(left, right, bottom)
            if covered <= 0.0:
                continue
            var color := swatch(Vector2((float(px) + 0.5) * texel.x, y), to_rgb)
            color.a = covered * 0.5
            image.set_pixel(px, py, color)
    _picture = ImageTexture.create_from_image(image)
    return _picture


## How much of the texel from *left* to *right* the *span* covers, nought to one.
static func _overlap(left: float, right: float, span: Vector2) -> float:
    return clampf(minf(right, span.y) - maxf(left, span.x), 0.0, 1.0)


## The horseshoe as an x span per half-texel row of the picture, in texels.
##
## Two rows per texel, so the coverage above is exact across a texel and
## averaged down it. The region is convex, being the hull of the spectral
## colours, so a row meets the boundary twice and one span says all of it, and
## walking the edges once and writing into the rows they cross costs the length
## of the boundary rather than the boundary times the rows.
static func _spans() -> Array:
    var rows := PICTURE.y * 2
    var spans: Array = []
    spans.resize(rows)
    spans.fill(Vector2(INF, -INF))
    var per_unit := Vector2(float(PICTURE.x) / PLOT_MAX.x, float(rows) / PLOT_MAX.y)
    var points := curve(per_unit, CHORD_PX)
    for i in points.size():
        # The last edge closes the shape: the line of purples, which joins the
        # two spectral ends and matches no single wavelength.
        var a := Vector2(points[i].x * per_unit.x, float(rows) - points[i].y * per_unit.y)
        var next: Vector2 = points[(i + 1) % points.size()]
        var b := Vector2(next.x * per_unit.x, float(rows) - next.y * per_unit.y)
        if a.y > b.y:
            var swap := a
            a = b
            b = swap
        var first := maxi(0, int(ceil(a.y - 0.5)))
        var beyond := mini(rows, int(ceil(b.y - 0.5)))
        for row in range(first, beyond):
            var at := float(row) + 0.5
            var x: float = a.x if b.y - a.y <= 0.0 else a.x + (b.x - a.x) * (at - a.y) / (b.y - a.y)
            var span: Vector2 = spans[row]
            spans[row] = Vector2(minf(span.x, x), maxf(span.y, x))
    return spans


## The two triangles, in the plot's own pixels, and whether they differ, beside
## how finely the locus is drawn at this size.
##
## The same claim the volume's report makes, one dimension down: a picture of
## two triangles and a picture of one drawn twice are the same picture. The two
## locus keys are there because a shot says the edge looks curved and only these
## say the curve is sampled finely enough that it cannot be anything else.
## `plot` says where inside the control the square-axis picture landed.
func report() -> Dictionary:
    var out := {
        "space": String(space.id) if space != null else "",
        "compare": String(compare.id) if compare != null else "",
        "space_triangle": _triangle_of(space.primaries if space != null else PackedVector2Array()),
        "compare_triangle": _triangle_of(compare.primaries if compare != null else PackedVector2Array()),
        "size": [size.x, size.y],
        "plot": [plot_rect().position.x, plot_rect().position.y, plot_rect().size.x, plot_rect().size.y],
    }
    var spread := 0.0
    var a: Array = out["space_triangle"]
    var b: Array = out["compare_triangle"]
    if a.size() == b.size() and not a.is_empty():
        for i in a.size():
            spread = maxf(spread, Vector2(a[i][0], a[i][1]).distance_to(Vector2(b[i][0], b[i][1])))
    out["spread"] = spread
    out["distinct"] = spread > 1.0
    out["locus_points"] = locus().size()
    out["locus_chord_px"] = longest_chord()
    return out


## The longest gap between two adjacent drawn locus points, in control pixels.
func longest_chord() -> float:
    var points := locus()
    var longest := 0.0
    for i in points.size() - 1:
        longest = maxf(longest, to_plot(points[i]).distance_to(to_plot(points[i + 1])))
    return longest


## Three chromaticities as points of this plot.
func _triangle_of(primaries: PackedVector2Array) -> Array:
    var out: Array = []
    if primaries.size() < 3:
        return out
    for i in 3:
        var at := to_plot(primaries[i])
        out.append([at.x, at.y])
    return out


func _draw() -> void:
    if size.x <= 0.0 or size.y <= 0.0:
        return
    draw_texture_rect(picture(), plot_rect(), false)

    var points := PackedVector2Array()
    for xy: Vector2 in locus():
        points.append(to_plot(xy))
    draw_polyline(points, Color(0.85, 0.88, 0.86, 0.6), 1.0)
    # The line of purples closes the horseshoe. It joins the two spectral
    # ends and is the one edge matching no single wavelength.
    draw_line(points[points.size() - 1], points[0], Color(0.85, 0.88, 0.86, 0.6), 1.0)

    # The bigger gamut first, in colour, so the selected one draws over it
    # dimmed rather than the other way round.
    if compare != null and compare.primaries.size() >= 3:
        var compare_triangle := PackedVector2Array(
            [
                to_plot(compare.primaries[0]),
                to_plot(compare.primaries[1]),
                to_plot(compare.primaries[2]),
                to_plot(compare.primaries[0]),
            ]
        )
        draw_polyline(compare_triangle, Color(1.0, 0.82, 0.3, 0.9), 2.0)

    if space == null or space.primaries.size() < 3:
        return

    var triangle := PackedVector2Array(
        [to_plot(space.primaries[0]), to_plot(space.primaries[1]), to_plot(space.primaries[2]), to_plot(space.primaries[0])]
    )
    draw_polyline(triangle, Color(1.0, 1.0, 1.0, 0.4 if compare != null else 0.95), 2.0)

    var labels := ["R", "G", "B"]
    for i in 3:
        var at := to_plot(space.primaries[i])
        draw_circle(at, 3.0, Color.WHITE)
        var font := ThemeDB.fallback_font
        var label_size := SaUI.font_size_for(SaUI.fraction_of(11))
        draw_string(font, at + Vector2(5.0, -4.0), labels[i], HORIZONTAL_ALIGNMENT_LEFT, -1, label_size, Color.WHITE)

    var white := to_plot(space.white)
    draw_line(white - Vector2(6.0, 0.0), white + Vector2(6.0, 0.0), Color.WHITE, 1.5)
    draw_line(white - Vector2(0.0, 6.0), white + Vector2(0.0, 6.0), Color.WHITE, 1.5)
