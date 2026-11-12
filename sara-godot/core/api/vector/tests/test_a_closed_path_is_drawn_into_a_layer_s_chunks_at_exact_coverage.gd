## A closed path drawn through `SaVectorFill` lays each pixel's exact share of
## the filled area as the chunk's alpha, under both fill rules, wherever on the
## canvas the path stands, and dispatches only the tiles it reaches.
##
## Two references are computed here, with no line of the renderer in them. The
## exact one integrates the filled spans of each pixel row, taken exactly in x
## from the shape itself (the polygon's crossings or the circle's equation) and
## at 512 rows in y, which leaves it within a thousandth of the true area even
## where an edge lies level, its worst case, half a row's height. The 16 by 16
## one counts which of 256 points in each pixel lie inside. A grid of points
## is not exact: an edge lying along one of its rows flips 16
## of them at once, so it strays from the true area by up to a 32nd, and the
## kernel is held to that reference within its own error and to the exact one
## within a 255th.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const PAINT := Color(1.0, 1.0, 1.0, 1.0)
## Rows in y the exact reference takes per pixel.
const EXACT_ROWS := 512
## Points along each side of a pixel the supersampled reference takes.
const GRID := 16
## How near the exact reference the kernel lands.
const EXACT_TOLERANCE := 1.0 / 255.0
## How near the 16 by 16 reference the kernel lands: that reference's own
## error, half a row of 16 points twice over for an edge along a row.
const GRID_TOLERANCE := 1.0 / 32.0
## A whole number of chunks, so the far shape sits in its chunks exactly as
## the near one does, a little over a million pixels each way.
const FAR := Vector2i(3907 * 256, 3907 * 256)

var _fill: SaVectorFill = null
## Every layer a test made. A layer is a Node standing in no tree, so it is
## freed by hand after the test, and its chunks go with it.
var _layers: Array[SaLayer] = []


func before_each() -> void:
    _fill = SaVectorFill.new()


func after_each() -> void:
    _fill = null
    for layer in _layers:
        layer.free()
    _layers.clear()


func _layer(format: int = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT) -> SaLayer:
    var layer := SaLayer.new()
    layer.schema = SaFieldSpec.default_schema(format)
    _layers.append(layer)
    return layer


## A pentagram round *centre*, its five points one contour that crosses
## itself five times.
static func _star_points(centre: Vector2, radius: float) -> PackedVector2Array:
    var points := PackedVector2Array()
    for k in 5:
        var angle := -PI / 2.0 + k * 4.0 * PI / 5.0
        points.append(centre + Vector2(cos(angle), sin(angle)) * radius)
    return points


## A triangle a little over a pixel wide at one end and a point at the other,
## lying at a shallow slope across several tiles and the chunk seam.
static func _sliver_points() -> PackedVector2Array:
    return PackedVector2Array([Vector2(20.25, 300.6), Vector2(470.8, 331.15), Vector2(20.25, 301.85)])


## The filled spans along the row at *y* of *points* under *rule*, as pairs,
## *y* first so a bound Callable takes it.
static func _polygon_spans(y: float, points: PackedVector2Array, rule: SaVectorPath.FillRule) -> PackedFloat64Array:
    var crossings: Array[Vector2] = []
    for i in points.size():
        var a := points[i]
        var b := points[(i + 1) % points.size()]
        var top := minf(a.y, b.y)
        var bottom := maxf(a.y, b.y)
        if y < top or y >= bottom:
            continue
        var x := a.x + (b.x - a.x) * (y - a.y) / (b.y - a.y)
        crossings.append(Vector2(x, 1.0 if b.y > a.y else -1.0))
    crossings.sort_custom(func(p: Vector2, q: Vector2) -> bool: return p.x < q.x)
    var spans := PackedFloat64Array()
    var winding := 0
    for c in crossings:
        var was := _inside(winding, rule)
        winding += int(c.y)
        var now := _inside(winding, rule)
        if now and not was:
            spans.append(c.x)
        elif was and not now:
            spans.append(c.x)
    return spans


static func _inside(winding: int, rule: SaVectorPath.FillRule) -> bool:
    return winding % 2 != 0 if rule == SaVectorPath.FillRule.EVEN_ODD else winding != 0


static func _circle_spans(y: float, centre: Vector2, radius: float) -> PackedFloat64Array:
    var dy := y - centre.y
    if absf(dy) >= radius:
        return PackedFloat64Array()
    var half := sqrt(radius * radius - dy * dy)
    return PackedFloat64Array([centre.x - half, centre.x + half])


## The exact share of each pixel of *box* the spans cover, row by row, exact in
## x and at EXACT_ROWS rows in y, indexed `y * width + x` from the box's corner.
static func _exact(spans_at: Callable, box: Rect2i) -> PackedFloat64Array:
    var out := PackedFloat64Array()
    out.resize(box.size.x * box.size.y)
    for py in box.size.y:
        var row := PackedFloat64Array()
        row.resize(box.size.x)
        var whole := PackedFloat64Array()
        whole.resize(box.size.x + 1)
        for r in EXACT_ROWS:
            var y := box.position.y + py + (r + 0.5) / EXACT_ROWS
            var spans: PackedFloat64Array = spans_at.call(y)
            for s in range(0, spans.size(), 2):
                _add_span(row, whole, spans[s] - box.position.x, spans[s + 1] - box.position.x, 1.0 / EXACT_ROWS)
        var running := 0.0
        for px in box.size.x:
            running += whole[px]
            out[py * box.size.x + px] = row[px] + running
    return out


## Adds a span from *from* to *to*, in pixels from the box's left side, at
## *weight*: the two end pixels their parts into *row*, and the ones between
## whole as a start and an end in *whole*, summed along the row afterwards.
static func _add_span(row: PackedFloat64Array, whole: PackedFloat64Array, from: float, to: float, weight: float) -> void:
    var width := row.size()
    from = clampf(from, 0.0, width)
    to = clampf(to, 0.0, width)
    if to <= from:
        return
    var first := floori(from)
    var last := floori(to)
    if first == last or first >= width:
        row[mini(first, width - 1)] += (to - from) * weight
        return
    row[first] += (first + 1 - from) * weight
    if last < width:
        row[last] += (to - last) * weight
    whole[first + 1] += weight
    whole[last] -= weight


## The share of the GRID by GRID points of each pixel of *box* that lie inside.
static func _supersampled(spans_at: Callable, box: Rect2i) -> PackedFloat64Array:
    var out := PackedFloat64Array()
    out.resize(box.size.x * box.size.y)
    var samples := box.size.x * GRID
    for py in box.size.y:
        var counts := PackedInt32Array()
        counts.resize(samples + 1)
        for r in GRID:
            var y := box.position.y + py + (r + 0.5) / GRID
            var spans: PackedFloat64Array = spans_at.call(y)
            for s in range(0, spans.size(), 2):
                var first := clampi(ceili((spans[s] - box.position.x) * GRID - 0.5), 0, samples)
                var past := clampi(ceili((spans[s + 1] - box.position.x) * GRID - 0.5), 0, samples)
                if past > first:
                    counts[first] += 1
                    counts[past] -= 1
        var running := 0
        var inside := PackedInt32Array()
        inside.resize(box.size.x)
        for n in samples:
            running += counts[n]
            @warning_ignore("integer_division")
            inside[n / GRID] += running
        for px in box.size.x:
            out[py * box.size.x + px] = float(inside[px]) / (GRID * GRID)
    return out


## The alpha *layer* holds over *box*, indexed as the references are, nought
## where it holds no chunk.
static func _alphas(layer: SaLayer, box: Rect2i) -> PackedFloat64Array:
    var out := PackedFloat64Array()
    out.resize(box.size.x * box.size.y)
    var images: Dictionary[Vector2i, Image] = {}
    for py in box.size.y:
        for px in box.size.x:
            var at := box.position + Vector2i(px, py)
            var grid := Vector2i(floori(at.x / float(SaChunk.SIZE)), floori(at.y / float(SaChunk.SIZE)))
            if not layer.chunks.has(grid):
                continue
            if not images.has(grid):
                images[grid] = SaExport.get_texture_image_float(layer.chunks[grid].albedo())
            out[py * box.size.x + px] = images[grid].get_pixelv(at - grid * SaChunk.SIZE).a
    return out


## The largest difference between *got* and *want*, and where, as text.
static func _worst(got: PackedFloat64Array, want: PackedFloat64Array, box: Rect2i) -> Dictionary:
    var worst := 0.0
    var where := Vector2i.ZERO
    for i in got.size():
        var gap := absf(got[i] - want[i])
        if gap > worst:
            worst = gap
            @warning_ignore("integer_division")
            where = box.position + Vector2i(i % box.size.x, i / box.size.x)
    return {"gap": worst, "at": where}


## Draws *path* and holds its alphas against both references over *box*.
func _holds(label: String, path: SaVectorPath, spans_at: Callable, box: Rect2i) -> void:
    var layer := _layer()
    _fill.draw(layer, path, PAINT)
    var got := _alphas(layer, box)
    var exact := _worst(got, _exact(spans_at, box), box)
    var grid := _worst(got, _supersampled(spans_at, box), box)
    print(
        (
            "vector fill %s: %.6f from the exact area at %s, %.6f from the 16 by 16 points at %s"
            % [label, exact.gap, exact.at, grid.gap, grid.at]
        )
    )
    assert_true(exact.gap <= EXACT_TOLERANCE, "%s lands %.6f from the exact area at %s" % [label, exact.gap, exact.at])
    assert_true(grid.gap <= GRID_TOLERANCE, "%s lands %.6f from the 16 by 16 points at %s" % [label, grid.gap, grid.at])


func test_a_star_that_crosses_itself_fills_exactly_under_non_zero() -> void:
    var points := _star_points(Vector2(250.3, 210.7), 110.0)
    var path := SaVectorPath.polygon(points, SaVectorPath.FillRule.NON_ZERO)
    _holds("star, non-zero", path, _polygon_spans.bind(points, SaVectorPath.FillRule.NON_ZERO), Rect2i(130, 90, 245, 230))


func test_a_star_that_crosses_itself_fills_exactly_under_even_odd() -> void:
    var points := _star_points(Vector2(250.3, 210.7), 110.0)
    var path := SaVectorPath.polygon(points, SaVectorPath.FillRule.EVEN_ODD)
    _holds("star, even-odd", path, _polygon_spans.bind(points, SaVectorPath.FillRule.EVEN_ODD), Rect2i(130, 90, 245, 230))


func test_a_circle_fills_exactly() -> void:
    var centre := Vector2(255.4, 262.9)
    var radius := 61.3
    var path := SaVectorPath.ellipse(centre, Vector2(radius, radius))
    _holds("circle", path, _circle_spans.bind(centre, radius), Rect2i(190, 198, 132, 132))


func test_a_thin_sliver_fills_exactly() -> void:
    var points := _sliver_points()
    var path := SaVectorPath.polygon(points)
    _holds("sliver", path, _polygon_spans.bind(points, SaVectorPath.FillRule.NON_ZERO), Rect2i(16, 296, 460, 40))


## A rectangle whose sides lie on half pixels covers each pixel along a side by
## exactly half, each corner by a quarter, and every pixel inside wholly, in a
## full and in a half precision chunk alike, since a half holds a half and a
## quarter exactly.
func test_a_rectangle_on_half_pixels_covers_its_edge_pixels_by_exactly_half() -> void:
    var rect := Rect2(20.5, 30.5, 280.0, 60.0)
    var box := Rect2i(16, 26, 290, 70)
    for format: int in [RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT, RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT]:
        var layer := _layer(format)
        _fill.draw(layer, SaVectorPath.rectangle(rect), PAINT)
        var got := _alphas(layer, box)
        var wrong := 0
        var first_wrong := ""
        for i in got.size():
            @warning_ignore("integer_division")
            var at := box.position + Vector2i(i % box.size.x, i / box.size.x)
            var across := 1.0 if at.x > 20 and at.x < 300 else (0.5 if at.x == 20 or at.x == 300 else 0.0)
            var down := 1.0 if at.y > 30 and at.y < 90 else (0.5 if at.y == 30 or at.y == 90 else 0.0)
            if got[i] != across * down:
                wrong += 1
                if first_wrong.is_empty():
                    first_wrong = "%s holds %.9f for %.2f" % [at, got[i], across * down]
        assert_eq(wrong, 0, "Format %d: every pixel holds its exact share, the first wrong one %s" % [format, first_wrong])


## The same shapes a little over a million pixels from the origin lay the same
## bits in their chunks as at the origin. A canvas position that far out in a
## 32-bit float is a 16th of a pixel apart from the next one, which is why the
## edges go up relative to their chunk.
func test_a_shape_a_million_pixels_out_draws_the_pixels_it_draws_at_the_origin() -> void:
    var shapes: Array[SaVectorPath] = [
        SaVectorPath.polygon(_star_points(Vector2(250.3, 210.7), 110.0), SaVectorPath.FillRule.EVEN_ODD),
        SaVectorPath.ellipse(Vector2(255.4, 262.9), Vector2(61.3, 40.2)),
        SaVectorPath.polygon(_sliver_points()),
    ]
    for s in shapes.size():
        var near := _layer(RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT)
        var far := _layer(RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT)
        _fill.draw(near, shapes[s], PAINT, Vector2i.ZERO, 7)
        _fill.draw(far, shapes[s], PAINT, FAR, 7)
        var far_grids: Array[Vector2i] = []
        for grid: Vector2i in far.chunks:
            @warning_ignore("integer_division")
            far_grids.append(grid - FAR / SaChunk.SIZE)
        far_grids.sort()
        var near_grids: Array[Vector2i] = near.chunks.keys()
        near_grids.sort()
        assert_eq(far_grids, near_grids, "Shape %d holds chunks at the same places out there" % s)
        var rd := GlobalShaderCompiler.get_rd()
        for grid: Vector2i in near.chunks:
            var here := rd.texture_get_data(near.chunks[grid].albedo().rid, 0)
            @warning_ignore("integer_division")
            var there := rd.texture_get_data(far.chunks[grid + FAR / SaChunk.SIZE].albedo().rid, 0)
            assert_true(here == there, "Shape %d's chunk %s holds the same bits a million pixels out" % [s, grid])


## Only the tiles under the star are dispatched: the tiles the drawer reports
## are exactly those where the exact reference finds any paint, the kernel ran
## one workgroup for each, and no chunk is held where no tile was.
func test_only_the_tiles_under_the_path_are_dispatched() -> void:
    var points := _star_points(Vector2(250.3, 210.7), 110.0)
    var box := Rect2i(128, 96, 256, 224)
    var exact := _exact(_polygon_spans.bind(points, SaVectorPath.FillRule.NON_ZERO), box)
    var under: Dictionary[Vector2i, bool] = {}
    for i in exact.size():
        if exact[i] > 0.0:
            @warning_ignore("integer_division")
            var at := box.position + Vector2i(i % box.size.x, i / box.size.x)
            under[Vector2i(floori(at.x / 16.0), floori(at.y / 16.0))] = true
    SaCompute.reset_counters()
    var layer := _layer()
    _fill.draw(layer, SaVectorPath.polygon(points), PAINT)
    var drawn: Dictionary[Vector2i, bool] = {}
    for rect in _fill.drawn_tiles:
        assert_eq(rect.size, Vector2i(16, 16), "A dispatch rectangle is one tile")
        @warning_ignore("integer_division")
        drawn[rect.position / 16] = true
    assert_eq(drawn.size(), _fill.drawn_tiles.size(), "No tile is dispatched twice")
    var missing := under.keys().filter(func(t: Vector2i) -> bool: return not drawn.has(t))
    var extra := drawn.keys().filter(func(t: Vector2i) -> bool: return not under.has(t))
    print(
        (
            "vector fill star: %d tiles dispatched of the %d its chunks hold, %d under the star"
            % [drawn.size(), layer.chunks.size() * 256, under.size()]
        )
    )
    assert_eq(missing, [], "Every tile under the star is dispatched")
    assert_eq(extra, [], "No tile the star misses is dispatched")
    var tally: Dictionary = SaCompute.kernel_counters().get("%s/%s" % [SaVectorFill.SHADER, SaVectorFill.SHADER], {})
    assert_eq(int(tally.get("workgroups", -1)), drawn.size(), "The kernel ran one workgroup a tile")
    for grid: Vector2i in layer.chunks:
        var holds := drawn.keys().any(func(t: Vector2i) -> bool: return Vector2i(floori(t.x / 16.0), floori(t.y / 16.0)) == grid)
        assert_true(holds, "Chunk %s is held because a tile in it was drawn" % grid)
