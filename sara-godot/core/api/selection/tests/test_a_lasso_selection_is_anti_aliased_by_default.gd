## A lasso selection is anti-aliased by default.
##
## Cutting a railing with the lasso and filled it, and across the top of the
## rail the green fell from 207 to 10 in one pixel. The polygon kernel tested
## each pixel's centre and wrote it wholly in or out, though the mask stores
## coverage from 0 to 1. It now grades the edge by the signed distance from the
## centre to the nearest edge, and these read the whole mask back against the
## same sum done here on the CPU, because a coverage that is merely plausible
## is what a wrong kernel returns.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

## Far enough from any number the GPU and the CPU disagree on over a few
## hundred pixels, and far closer than any grade a painter could see.
const CLOSE := 0.0001

var _easel: SaEasel = null
var _doc: SaDocument = null


## Two by two chunks, so a shape can cross a seam.
func before_each() -> void:
    _easel = SaEasel.create_default(Vector2i(512, 512))
    _doc = _easel.document


func after_each() -> void:
    _easel.free()
    _easel = null
    _doc = null


## A triangle whose long edge falls one pixel in two, the slope of the rail,
## across the seam between the two top chunks.
static func _slanted() -> PackedVector2Array:
    return PackedVector2Array([Vector2(120, 20), Vector2(400, 20), Vector2(120, 160)])


## The pixel the slanted edge crosses in column *x*. On this slope its centre
## is a quarter of a pixel above or below the edge, so the pixel one row in is
## at least 0.67 inside and whole, and the pixel one row out is empty.
static func _on_the_edge(x: int) -> Vector2i:
    var y := 20.0 + (400.0 - (float(x) + 0.5)) * 0.5
    return Vector2i(x, floori(y))


func test_a_slanted_edge_is_graded_and_the_pixels_inside_it_are_whole() -> void:
    var points := _slanted()
    _doc.selection.select_polygon(points, SaSelection.Mode.REPLACE, true)
    var mask := _mask()
    var graded := 0
    for x in range(130, 390):
        var on := _on_the_edge(x)
        var cover := _at(mask, on.x, on.y)
        if cover > 0.0 and cover < 1.0:
            graded += 1
        assert_almost_eq(cover, _expected(points, on, true), CLOSE, "Column %d grades as the sum says" % x)
        assert_eq(_at(mask, on.x, on.y - 1), 1.0, "and one pixel in it is whole")
        assert_eq(_at(mask, on.x, on.y + 1), 0.0, "and one out it is empty")
    assert_eq(graded, 260, "Every pixel the edge crosses holds part of a pixel, none of them 0 or 1")
    assert_eq(_mismatches(mask, points, true, _box_of(points)), [], "and every pixel of the box is the sum's")
    assert_eq(_doc.selection.bounds, _box_of(points), "The bounds are the box round the points, as they were")


## An edge on a whole pixel line is half a pixel from every centre beside it,
## so it comes out exactly as hard as the plain test, across a seam as well.
func test_a_polygon_on_whole_pixel_lines_matches_the_hard_mask() -> void:
    var points := PackedVector2Array(
        [Vector2(200, 40), Vector2(320, 40), Vector2(320, 300), Vector2(260, 300), Vector2(260, 120), Vector2(200, 120)]
    )
    _doc.selection.select_polygon(points, SaSelection.Mode.REPLACE, true)
    var soft := _mask()
    var box := _box_of(points).grow(2)
    assert_eq(_mismatches(soft, points, false, box), [], "Anti-aliased, every pixel is today's 0 or 1")
    _doc.selection.select_polygon(points, SaSelection.Mode.REPLACE, false)
    var hard := _mask()
    assert_true(_same(soft, hard), "and every chunk is the hard one byte for byte")
    assert_eq(soft.size(), 4, "The L's box crosses both seams, so four chunks were written")


## An add takes the greater of the mask and the shape, so a part of a pixel
## never lowers what was already whole and never sums with another part.
func test_an_add_across_a_partial_edge_keeps_the_greater() -> void:
    var points := _slanted()
    _doc.selection.select_rect(Rect2i(120, 20, 150, 150))
    _doc.selection.select_polygon(points, SaSelection.Mode.ADD, true)
    var mask := _mask()
    var inside_the_square := _on_the_edge(200)
    assert_eq(_at(mask, inside_the_square.x, inside_the_square.y), 1.0, "A graded pixel inside the square stays whole")
    var past_the_square := _on_the_edge(300)
    assert_almost_eq(
        _at(mask, past_the_square.x, past_the_square.y),
        _expected(points, past_the_square, true),
        CLOSE,
        "and past it the edge is graded"
    )

    # The triangle on the other side of the same edge: each crossed pixel is
    # covered c by one and 1 - c by the other, and the add keeps the greater.
    var other := PackedVector2Array([Vector2(400, 20), Vector2(400, 160), Vector2(120, 160)])
    _doc.selection.select_polygon(points, SaSelection.Mode.REPLACE, true)
    _doc.selection.select_polygon(other, SaSelection.Mode.ADD, true)
    mask = _mask()
    for x: int in [150, 250, 350]:
        var on := _on_the_edge(x)
        var cover := _expected(points, on, true)
        assert_almost_eq(_at(mask, on.x, on.y), maxf(cover, 1.0 - cover), CLOSE, "Column %d keeps the greater part" % x)
        assert_true(cover > 0.0 and cover < 1.0, "of a pixel the edge crosses")


## A subtract takes the lesser of the mask and what the shape leaves, so a
## crossed pixel keeps the part the polygon did not cover.
func test_a_subtract_across_a_partial_edge_leaves_what_the_shape_does_not_cover() -> void:
    var points := _slanted()
    _doc.selection.select_all(_doc.canvas_size)
    _doc.selection.select_polygon(points, SaSelection.Mode.SUBTRACT, true)
    var mask := _mask()
    for x: int in [150, 250, 350]:
        var on := _on_the_edge(x)
        var cover := _expected(points, on, true)
        assert_almost_eq(_at(mask, on.x, on.y), 1.0 - cover, CLOSE, "Column %d keeps what the edge left" % x)
        assert_eq(_at(mask, on.x, on.y - 1), 0.0, "the inside is gone")
        assert_eq(_at(mask, on.x, on.y + 1), 1.0, "and the outside untouched")

    # A second subtract along the same slope half a pixel further in covers
    # these pixels less, so writing its own part would put some of each back.
    # The lesser keeps what the first one took.
    var inward := PackedVector2Array([Vector2(120, 20), Vector2(399, 20), Vector2(120, 159.5)])
    _doc.selection.select_polygon(inward, SaSelection.Mode.SUBTRACT, true)
    var again := _mask()
    for x: int in [150, 250, 350]:
        var on := _on_the_edge(x)
        var first := 1.0 - _expected(points, on, true)
        var second := 1.0 - _expected(inward, on, true)
        assert_true(second < 1.0 and second > first, "The second covers column %d, and less" % x)
        assert_almost_eq(_at(again, on.x, on.y), first, CLOSE, "so it keeps the first's lesser part")


## The option off, and a caller that does not ask, write today's mask: every
## pixel wholly in or out by the even-odd test at its centre.
func test_the_option_off_matches_the_hard_mask() -> void:
    var points := PackedVector2Array()
    for i in 7:
        var angle := TAU * float(i) / 7.0 + 0.3
        points.append(Vector2(256.3, 250.7) + Vector2(cos(angle) * 180.0, sin(angle) * 130.0))
    _doc.selection.select_polygon(points, SaSelection.Mode.REPLACE, false)
    var hard := _mask()
    var box := _box_of(points).grow(1)
    assert_eq(_mismatches(hard, points, false, box), [], "Off, every pixel of the box is the plain test's")
    _doc.selection.select_polygon(points)
    assert_true(_same(_mask(), hard), "and a caller that does not ask gets the same")

    _doc.selection.select_all(_doc.canvas_size)
    _doc.selection.select_polygon(points, SaSelection.Mode.SUBTRACT, false)
    var cut := _mask()
    var holes: Array = []
    for y in range(box.position.y, box.end.y):
        for x in range(box.position.x, box.end.x):
            if _at(cut, x, y) != 1.0 - _expected(points, Vector2i(x, y), false):
                holes.append(Vector2i(x, y))
    assert_eq(holes, [], "and a subtract off takes out exactly those pixels")


## The lasso a painter picks up grades its edge, it declares the Tool Options
## row that says so, and the row's property off gives the hard edge back. The
## row itself is ui's, so the click on it is the unit's scenario rather than a
## docker built here, which a suite under core may not name.
func test_the_lasso_anti_aliases_by_default_and_its_row_turns_it_off() -> void:
    var surface := Fixtures.make_surface(Vector2i(512, 512))
    var machine := Fixtures.make_bound_machine(surface)
    var doc := surface.get_document()
    machine.set_active_tool(&"lasso")
    var tool := machine.active_tool
    assert_true(tool.anti_alias, "A fresh lasso anti-aliases")

    var row: SaOptionSpec = null
    for spec: SaOptionSpec in machine.registry.get_descriptor(&"lasso").options:
        if spec.key == &"lasso_anti_alias":
            row = spec
    assert_not_null(row, "and declares a row for it")
    assert_eq(row.label, "Anti-aliasing", "called Anti-aliasing, as Krita's is")
    assert_eq(row.kind, SaOptionSpec.Kind.BOOL, "a tick")
    assert_eq(row.property, ^"anti_alias", "on the tool's own property")
    assert_true(row.on_tool and not row.bar, "in Tool Options and off the bar")

    var path: Array = [Vector2(120, 20), Vector2(400, 20), Vector2(120, 160)]
    _drag_lasso(surface, tool, path)
    var soft := _mask_of(doc)
    var on := _on_the_edge(250)
    var cover := _at(soft, on.x, on.y)
    assert_true(cover > 0.0 and cover < 1.0, "The dragged edge holds part of a pixel: %f" % cover)

    tool.set_indexed(row.property, false)
    _drag_lasso(surface, tool, path)
    var hard := _mask_of(doc)
    assert_true(_at(hard, on.x, on.y) == 0.0 or _at(hard, on.x, on.y) == 1.0, "and the row off leaves it hard")

    tool.anti_alias = true
    Fixtures.teardown(surface, machine)


## Every mask chunk read back once, by grid position, as its texels and its
## width in texels.
func _mask() -> Dictionary:
    return _mask_of(_doc)


static func _mask_of(document: SaDocument) -> Dictionary:
    var out := {}
    for grid: Vector2i in document.selection.chunks:
        var texture: SaTexture = document.selection.chunks[grid].field(SaSelection.FIELD)
        out[grid] = [GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0), texture.size.x]
    return out


## Whether two read masks hold the same chunks with the same bytes.
static func _same(one: Dictionary, other: Dictionary) -> bool:
    if one.size() != other.size():
        return false
    for grid: Vector2i in one:
        if not other.has(grid) or one[grid][0] != other[grid][0]:
            return false
    return true


## The coverage at a document pixel, 0 where no chunk is.
static func _at(mask: Dictionary, x: int, y: int) -> float:
    var size := SaChunk.SIZE
    var grid := Vector2i(floori(float(x) / size), floori(float(y) / size))
    if not mask.has(grid):
        return 0.0
    var bytes: PackedByteArray = mask[grid][0]
    var width: int = mask[grid][1]
    var texel: int = SaFieldSpec.BYTES_PER_TEXEL[SaSelection.FORMAT]
    return bytes.decode_float(((y - grid.y * size) * width + x - grid.x * size) * texel)


## What the kernel is to write at *pixel*, done here on the CPU: in or out by
## even-odd crossing at the centre, and, when *graded*, 0.5 plus the centre's
## signed distance to the nearest edge, clamped.
static func _expected(points: PackedVector2Array, pixel: Vector2i, graded: bool) -> float:
    var at := Vector2(pixel) + Vector2(0.5, 0.5)
    var inside := false
    var nearest := INF
    var n := points.size()
    for i in n:
        var a := points[i]
        var b := points[(i + 1) % n]
        if (a.y > at.y) != (b.y > at.y) and at.x < a.x + (at.y - a.y) * (b.x - a.x) / (b.y - a.y):
            inside = not inside
        if graded:
            nearest = minf(nearest, at.distance_to(Geometry2D.get_closest_point_to_segment(at, a, b)))
    if not graded:
        return 1.0 if inside else 0.0
    return clampf(0.5 + (nearest if inside else -nearest), 0.0, 1.0)


## Every pixel of *box* whose coverage is not the sum's, with both numbers.
func _mismatches(mask: Dictionary, points: PackedVector2Array, graded: bool, box: Rect2i) -> Array:
    var out: Array = []
    for y in range(box.position.y, box.end.y):
        for x in range(box.position.x, box.end.x):
            var want := _expected(points, Vector2i(x, y), graded)
            var have := _at(mask, x, y)
            if absf(have - want) > CLOSE:
                out.append([Vector2i(x, y), have, want])
    return out


## The box `select_polygon` dispatches over: the points' floor and ceiling.
static func _box_of(points: PackedVector2Array) -> Rect2i:
    var low := points[0]
    var high := points[0]
    for point in points:
        low = low.min(point)
        high = high.max(point)
    var start := Vector2i(floori(low.x), floori(low.y))
    return Rect2i(start, Vector2i(ceili(high.x), ceili(high.y)) - start)


## A freehand lasso drag through *path*, pressed on its first point and released
## on its last.
static func _drag_lasso(surface: SaSurface, tool: ToolState, path: Array) -> void:
    surface.view.mouse_position = path[0]
    tool.handle_input(_button(true))
    for i in range(1, path.size()):
        surface.view.mouse_position = path[i]
        tool.handle_input(InputEventMouseMotion.new())
    tool.handle_input(_button(false))


static func _button(pressed: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    return event
