## A selection with a hole selects the ring and not the hole,
## and a clear under it touches nothing outside the ring's outline. A painter
## working through the door sent a polygon as rings, an outer outline and a
## hole, and the step stopped on a script error with nothing selected, so the
## clear took the whole layer, the hole and everything past the edge with it.
##
## A polygon, an ellipse and a rectangle each get a hole made both ways the
## door makes one: rings joined by `SaSelectionRings` into one polygon, the
## ellipse as a polygon of many sides and the rectangle as its corners, and the
## outer shape with the inner one subtracted. Then the opaque layer is cleared
## and every texel of the canvas is read back from VRAM against the same rule
## tested on the CPU at each pixel's centre, which is how the kernels decide.
## A centre within a hundredth of a pixel of an edge may go either way, since
## the two sides round differently there.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const PaintKernel = preload("res://tests/fixtures/paint_kernel.gd")

## Two by two chunks, and every shape crosses both seams.
const SIZE := Vector2i(512, 512)
const OUTER := Rect2i(100, 100, 300, 300)
const HOLE := Rect2i(200, 200, 112, 112)
## Past this box every shape here is out by pixels, so a texel there is read
## as outside without testing it against an edge.
const NEAR := Rect2i(96, 96, 308, 308)
## The outer polygon leans, so its edges are staircases.
const LEANING: Array[Vector2] = [Vector2(100, 100), Vector2(400, 112), Vector2(388, 400), Vector2(112, 388)]
const ROUND_SIDES := 64

var _surface: SaSurface = null
var _machine: ToolMachine = null
var _doc: SaDocument = null
var _feather_was: float = 0.0


func before_each() -> void:
    _surface = Fixtures.make_surface(SIZE)
    _machine = Fixtures.make_bound_machine(_surface)
    _doc = _surface.get_document()
    _feather_was = SaSettings.selection_feather
    SaSettings.selection_feather = 0.0
    _doc.fill_layer(Color(0.2, 0.5, 0.9, 1.0))


func after_each() -> void:
    SaSettings.selection_feather = _feather_was
    Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null
    _doc = null


# ---------------------------------------------------------------------------
# Rings in one polygon
# ---------------------------------------------------------------------------


func test_a_polygon_given_as_rings_keeps_its_hole() -> void:
    var outer := PackedVector2Array(LEANING)
    var hole := _corners(HOLE)
    _doc.selection.select_polygon(SaSelectionRings.flatten([outer, hole]))
    _clear_and_check("rings of a polygon", outer, hole)


func test_an_ellipse_given_as_rings_keeps_its_hole() -> void:
    var outer := _round(OUTER)
    var hole := _round(HOLE)
    _doc.selection.select_polygon(SaSelectionRings.flatten([outer, hole]))
    _clear_and_check("rings of an ellipse", outer, hole)


func test_a_rectangle_given_as_rings_keeps_its_hole() -> void:
    var outer := _corners(OUTER)
    var hole := _corners(HOLE)
    _doc.selection.select_polygon(SaSelectionRings.flatten([outer, hole]))
    _clear_and_check("rings of a rectangle", outer, hole)


## Anti-aliased, the rings meet in no seam: the end mark closes each ring on
## itself, so no edge runs from one ring to the next.
func test_anti_aliased_rings_draw_no_seam_between_them() -> void:
    _doc.selection.select_polygon(SaSelectionRings.flatten([_corners(OUTER), _corners(HOLE)]), SaSelection.Mode.REPLACE, true)
    _doc.clear_layer()
    var alpha := _alpha()
    var seam := 0
    for x in range(OUTER.position.x + 1, HOLE.position.x - 1):
        for y: int in [150, 350]:
            if alpha[y * SIZE.x + x] > 0.0:
                seam += 1
    assert_eq(seam, 0, "Every texel of the ring between the two outlines is cleared, with no seam joining them")
    assert_eq(alpha[256 * SIZE.x + 256], 1.0, "The hole keeps its paint anti-aliased")
    assert_eq(alpha[256 * SIZE.x + OUTER.end.x], 1.0, "The column right of the edge keeps its paint")


## A stroke reads the same mask a clear does: one dab over the whole canvas on
## an empty layer lays paint in the ring and nowhere else.
func test_a_stroke_under_rings_paints_the_ring_alone() -> void:
    _doc.clear_layer()
    _doc.selection.select_rings([PackedVector2Array(LEANING), _corners(HOLE)])
    var compute := PaintKernel.compute()
    var centre := Vector2(SIZE) * 0.5
    var radius := float(SIZE.x)
    _doc.begin_stroke(1.0, SaLayer.BLEND_MODE.NORMAL)
    var paint := SaPaintContext.for_region(_doc, Rect2(centre - Vector2(radius, radius), Vector2(radius, radius) * 2.0), false)
    paint.dispatch_batch(
        compute,
        "paint",
        func(target: SaPaintContext.Target) -> void:
            compute.set_texture(0, target.texture.rid)
            compute.set_push_constant_float_array(
                PaintKernel.pack_params(paint.local_point(target, centre), target.render_offset, Color.RED, radius, 1.0, 1.0, 1.0)
            )
    )
    paint.commit_invalidation()
    _doc.commit_stroke()
    var alpha := _alpha()
    var outer := PackedVector2Array(LEANING)
    var hole := _corners(HOLE)
    var spilt := 0
    var bare := 0
    for y in SIZE.y:
        for x in SIZE.x:
            var at := Vector2(x + 0.5, y + 0.5)
            if _near_edge(at, outer) or _near_edge(at, hole):
                continue
            var in_ring := _inside(at, outer) and not _inside(at, hole)
            var a := alpha[y * SIZE.x + x]
            if not in_ring and a != 0.0:
                spilt += 1
            elif in_ring and a <= 0.0:
                bare += 1
    assert_eq(spilt, 0, "No texel outside the ring, the hole and past the edge, takes paint")
    assert_eq(bare, 0, "Every texel of the ring takes paint")


# ---------------------------------------------------------------------------
# A shape subtracted
# ---------------------------------------------------------------------------


func test_a_polygon_with_a_polygon_subtracted_keeps_its_hole() -> void:
    var outer := PackedVector2Array(LEANING)
    var hole := _corners(HOLE)
    _doc.selection.select_polygon(outer)
    _doc.selection.select_polygon(hole, SaSelection.Mode.SUBTRACT)
    _clear_and_check("a polygon less a polygon", outer, hole)


func test_an_ellipse_with_an_ellipse_subtracted_keeps_its_hole() -> void:
    _doc.selection.select_ellipse(OUTER)
    _doc.selection.select_ellipse(HOLE, SaSelection.Mode.SUBTRACT)
    _clear_and_check("an ellipse less an ellipse", PackedVector2Array(), PackedVector2Array())


func test_a_rectangle_with_a_rectangle_subtracted_keeps_its_hole() -> void:
    _doc.selection.select_rect(OUTER)
    _doc.selection.select_rect(HOLE, SaSelection.Mode.SUBTRACT)
    _clear_and_check("a rectangle less a rectangle", _corners(OUTER), _corners(HOLE))


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


## Clears the layer under the selection and reads every texel against the ring
## between *outer* and *hole*, or between the two ellipses inscribed in `OUTER`
## and `HOLE` when both are empty.
func _clear_and_check(what: String, outer: PackedVector2Array, hole: PackedVector2Array) -> void:
    _doc.clear_layer()
    var alpha := _alpha()
    var spilt := 0
    var kept := 0
    var first := ""
    for y in SIZE.y:
        for x in SIZE.x:
            var centre := Vector2(x + 0.5, y + 0.5)
            var in_ring := 0
            if not NEAR.has_point(Vector2i(x, y)):
                pass
            elif outer.is_empty():
                in_ring = 1 if _in_ellipse(centre, OUTER) and not _in_ellipse(centre, HOLE) else 0
            else:
                if _near_edge(centre, outer) or _near_edge(centre, hole):
                    continue
                in_ring = 1 if _inside(centre, outer) and not _inside(centre, hole) else 0
            var a := alpha[y * SIZE.x + x]
            if in_ring == 0 and a != 1.0:
                spilt += 1
                if first.is_empty():
                    first = "(%d, %d) outside the ring reads %.3f" % [x, y, a]
            elif in_ring == 1 and a != 0.0:
                kept += 1
                if first.is_empty():
                    first = "(%d, %d) in the ring reads %.3f" % [x, y, a]
    assert_eq(spilt, 0, "%s: no texel outside the ring, the hole and past the edge, is cleared. %s" % [what, first])
    assert_eq(kept, 0, "%s: every texel of the ring is cleared. %s" % [what, first])


## The layer's alpha at every texel, row by row, each chunk read back once.
func _alpha() -> PackedFloat32Array:
    var out := PackedFloat32Array()
    out.resize(SIZE.x * SIZE.y)
    var layer := _doc.active_layer
    for grid_pos: Vector2i in layer.chunks:
        var texture := layer.get_field(grid_pos)
        var size := texture.size
        var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
        var origin := grid_pos * size
        # The alpha word alone, a float or a half, rather than a whole colour
        # decoded per texel, which is most of the suite's time otherwise.
        var width: int = SaFieldSpec.BYTES_PER_TEXEL[texture.format]
        var wide := width == 16
        for y in mini(size.y, SIZE.y - origin.y):
            for x in mini(size.x, SIZE.x - origin.x):
                var at := (y * size.x + x) * width + (width >> 2) * 3
                out[(origin.y + y) * SIZE.x + origin.x + x] = bytes.decode_float(at) if wide else bytes.decode_half(at)
    return out


static func _corners(rect: Rect2i) -> PackedVector2Array:
    return PackedVector2Array(
        [Vector2(rect.position), Vector2(rect.end.x, rect.position.y), Vector2(rect.end), Vector2(rect.position.x, rect.end.y)]
    )


## The ellipse inscribed in *rect* as a polygon of `ROUND_SIDES` sides.
static func _round(rect: Rect2i) -> PackedVector2Array:
    var out := PackedVector2Array()
    var centre := Vector2(rect.position) + Vector2(rect.size) * 0.5
    for i in ROUND_SIDES:
        var turn := TAU * i / ROUND_SIDES
        out.append(centre + Vector2(cos(turn), sin(turn)) * Vector2(rect.size) * 0.5)
    return out


## Even-odd from *at* to the right, as `select_polygon` in `selection.gmacs`.
static func _inside(at: Vector2, points: PackedVector2Array) -> bool:
    var inside := false
    for i in points.size():
        var a := points[i]
        var b := points[(i + 1) % points.size()]
        if (a.y > at.y) != (b.y > at.y):
            if at.x < a.x + (at.y - a.y) * (b.x - a.x) / (b.y - a.y):
                inside = not inside
    return inside


static func _near_edge(at: Vector2, points: PackedVector2Array) -> bool:
    for i in points.size():
        var closest := Geometry2D.get_closest_point_to_segment(at, points[i], points[(i + 1) % points.size()])
        if closest.distance_to(at) < 0.01:
            return true
    return false


## Inside the ellipse inscribed in *rect* at *at*, as `select_ellipse` tests.
static func _in_ellipse(at: Vector2, rect: Rect2i) -> bool:
    var radii := Vector2(maxf(rect.size.x * 0.5, 0.5), maxf(rect.size.y * 0.5, 0.5))
    var d := (at - (Vector2(rect.position) + Vector2(rect.size) * 0.5)) / radii
    return d.dot(d) <= 1.0
