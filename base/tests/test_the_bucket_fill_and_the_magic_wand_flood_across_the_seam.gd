## On a document whose kind wraps, the fill and the wand flood across the
## seam, and the fill's feather reads across it the same way.
##
## The document is 400 by 200, so the grid is two chunks wide and the second
## column is 144 texels, which is the seam the flood has to step over: from the
## last valid texel of a partial chunk to the first texel of the first one,
## with the dead texels of the partial chunk never read as canvas.
##
## The shape is a red ring with a transparent hole, painted in pieces folded
## back onto the canvas, so its hole runs from x 360 over the seam to x 39. A
## click in the hole on the right side is the gesture every case starts from.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const StateBucketFillScript = preload("res://modules/sara-base-modules/base/tools/state_bucket_fill.gd")
const Fixtures = preload("res://tests/fixtures.gd")

const SIZE := Vector2i(400, 200)
const RED := Color(1.0, 0.0, 0.0, 1.0)
const BLUE := Color(0.0, 0.0, 1.0, 1.0)
const CLEAR := Color(0.0, 0.0, 0.0, 0.0)

## The ring's outside and its hole, in unfolded coordinates: x past 400 is the
## far side of the seam.
const WALL := Rect2i(350, 50, 100, 100)
const HOLE := Rect2i(360, 60, 80, 80)
const CLICK := Vector2i(380, 100)

var _surface: SaSurface = null
var _doc: SaDocument = null


func before_each() -> void:
    _surface = Fixtures.make_surface(SIZE)
    _doc = _surface.get_document()


func after_each() -> void:
    _doc.free()
    _surface.easel.free()
    _surface = null
    _doc = null


func _wraps(kind: SaProjection.Kind) -> void:
    _doc.projection = SaProjection.new(kind)


func _tool(antialias: bool = false) -> Object:
    var fill := StateBucketFillScript.new()
    fill.surface = _surface
    SaColors.foreground = BLUE
    fill.antialias = antialias
    return fill


## Paints *rect* folded back onto the canvas on both axes, so one rectangle
## that runs off the right or the bottom edge comes back on the left or the
## top, which is the picture a wrapping document shows.
func _paint_folded(rect: Rect2i, colour: Color) -> void:
    for piece in _folded(rect):
        _doc.selection.select_rect(piece)
        _doc.fill_layer(colour, _doc.active_layer)
        _doc.selection.deselect()


func _folded(rect: Rect2i) -> Array[Rect2i]:
    var pieces: Array[Rect2i] = []
    for across: int in [0, -SIZE.x]:
        for down: int in [0, -SIZE.y]:
            var piece := Rect2i(rect.position + Vector2i(across, down), rect.size).intersection(Rect2i(Vector2i.ZERO, SIZE))
            if piece.has_area():
                pieces.append(piece)
    return pieces


func _ring() -> void:
    _paint_folded(WALL, RED)
    _paint_folded(HOLE, CLEAR)


## Every chunk's texels read once with the texture's width, so a whole-canvas
## count costs one read a chunk and not one a texel.
func _layer_bytes() -> Dictionary:
    var read := {}
    for grid_pos: Vector2i in _doc.active_layer.chunks:
        var chunk: SaChunk = _doc.active_layer.chunks[grid_pos]
        var texture: SaTexture = chunk.field(chunk.fields.keys()[0])
        read[grid_pos] = [GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0), texture.size.x]
    return read


func _selection_bytes() -> Dictionary:
    var read := {}
    for grid_pos: Vector2i in _doc.selection.chunks:
        var texture: SaTexture = _doc.selection.chunks[grid_pos].field(SaSelection.FIELD)
        read[grid_pos] = [GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0), texture.size.x]
    return read


func _texel(read: Dictionary, x: int, y: int) -> Color:
    @warning_ignore("integer_division")
    var grid := Vector2i(x / SaChunk.SIZE, y / SaChunk.SIZE)
    if not read.has(grid):
        return CLEAR
    var bytes: PackedByteArray = read[grid][0]
    var at := ((y % SaChunk.SIZE) * int(read[grid][1]) + x % SaChunk.SIZE) * 16
    return Color(bytes.decode_float(at), bytes.decode_float(at + 4), bytes.decode_float(at + 8), bytes.decode_float(at + 12))


func _coverage(read: Dictionary, x: int, y: int) -> float:
    @warning_ignore("integer_division")
    var grid := Vector2i(x / SaChunk.SIZE, y / SaChunk.SIZE)
    if not read.has(grid):
        return 0.0
    var bytes: PackedByteArray = read[grid][0]
    return bytes.decode_float(((y % SaChunk.SIZE) * int(read[grid][1]) + x % SaChunk.SIZE) * 4)


## Whether the canvas texel at *x*, *y* lies in one of *rects*' folded pieces.
func _inside(rects: Array[Rect2i], x: int, y: int) -> bool:
    for piece in rects:
        if piece.has_point(Vector2i(x, y)):
            return true
    return false


## Counts the canvas texels the fill painted blue, and how many of those lie
## outside *region*, over the whole canvas.
func _blue(region: Array[Rect2i]) -> Vector2i:
    var read := _layer_bytes()
    var counted := Vector2i.ZERO
    for y in SIZE.y:
        for x in SIZE.x:
            if _texel(read, x, y).b > 0.5:
                counted.x += 1
                if not _inside(region, x, y):
                    counted.y += 1
    return counted


## The first clause: a fill in the hole on an equirectangular document reaches
## the hole on both sides of the seam, and nothing outside it.
func test_a_fill_crosses_the_seam_of_an_equirectangular_document() -> void:
    _wraps(SaProjection.Equirectangular.new())
    _ring()

    assert_true(_tool().fill_at(CLICK) > 0, "The click in the hole painted something")

    var read := _layer_bytes()
    assert_almost_eq(_texel(read, 395, 100).b, 1.0, 0.02, "The hole is filled on the right of the seam")
    assert_almost_eq(_texel(read, 5, 100).b, 1.0, 0.02, "and on the left of it")
    assert_almost_eq(_texel(read, 39, 139).b, 1.0, 0.02, "as far as the hole's far corner")
    assert_almost_eq(_texel(read, 355, 100).r, 1.0, 0.02, "The wall on the right is still red")
    assert_almost_eq(_texel(read, 45, 100).r, 1.0, 0.02, "and so is the wall past the seam")
    assert_almost_eq(_texel(read, 200, 100).a, 0.0, 0.02, "The canvas outside the ring is untouched")

    var hole := _folded(HOLE)
    var blue := _blue(hole)
    assert_eq(blue.x, HOLE.get_area(), "Every texel of the hole is filled, on both sides")
    assert_eq(blue.y, 0, "and not one outside it")


## The same shape on a flat document: the hole's right half is closed by the
## canvas's edge, and the fill stops there.
func test_the_same_shape_on_a_flat_document_fills_only_to_the_edge() -> void:
    _ring()

    _tool().fill_at(CLICK)

    var read := _layer_bytes()
    assert_almost_eq(_texel(read, 399, 100).b, 1.0, 0.02, "The fill reaches the canvas's last column")
    assert_almost_eq(_texel(read, 5, 100).a, 0.0, 0.02, "and stops there, the hole past the edge is empty")

    var right: Array[Rect2i] = [Rect2i(360, 60, 40, 80)]
    var blue := _blue(right)
    assert_eq(blue.x, 40 * 80, "The right half of the hole is filled whole")
    assert_eq(blue.y, 0, "and nothing else")


## The second clause's first half: a wand selection of the hole is whole on
## both sides of the seam.
func test_a_wand_selection_of_the_shape_is_whole_on_both_sides() -> void:
    _wraps(SaProjection.Equirectangular.new())
    _ring()

    var selected := SaWand.new().flood(_doc, CLICK, 0.05, SaSelection.Mode.REPLACE, null, _doc.active_layer)
    assert_true(selected > 0, "The wand selected something")

    var read := _selection_bytes()
    var hole := _folded(HOLE)
    var inside := 0
    var outside := 0
    for y in SIZE.y:
        for x in SIZE.x:
            if _coverage(read, x, y) > 0.5:
                if _inside(hole, x, y):
                    inside += 1
                else:
                    outside += 1
    assert_eq(inside, HOLE.get_area(), "Every texel of the hole is selected, on both sides of the seam")
    assert_eq(outside, 0, "and not one outside it")
    var bounds := _doc.selection.bounds
    assert_true(
        bounds.has_point(Vector2i(5, 100)) and bounds.has_point(Vector2i(395, 100)), "The bounds hold both sides, %s" % bounds
    )


## The second clause's second half. One ring has its hole run over the seam
## and stop two texels past it, the other is the same ring two hundred texels
## to the left, in the canvas's middle. Each texel of the feathered fill across
## the seam reads as its twin in the middle does: no edge where the seam is,
## and the softened edge past it the same as anywhere else.
func test_a_feathered_fills_edge_is_the_same_across_the_seam_as_in_the_middle() -> void:
    _wraps(SaProjection.Equirectangular.new())
    var seam_wall := Rect2i(370, 50, 42, 100)
    var seam_hole := Rect2i(380, 60, 22, 80)
    var shift := Vector2i(-200, 0)
    _paint_folded(seam_wall, RED)
    _paint_folded(seam_hole, CLEAR)
    _paint_folded(Rect2i(seam_wall.position + shift, seam_wall.size), RED)
    _paint_folded(Rect2i(seam_hole.position + shift, seam_hole.size), CLEAR)

    _tool(true).fill_at(Vector2i(390, 100))
    _tool(true).fill_at(Vector2i(190, 100))

    var read := _layer_bytes()
    for y: int in [61, 100, 138]:
        for x in range(376, 406):
            var at := posmod(x, SIZE.x)
            var seam := _texel(read, at, y)
            var middle := _texel(read, x + shift.x, y)
            assert_almost_eq(seam.b, middle.b, 0.002, "Blue at x %d, y %d matches the middle's x %d" % [at, y, x + shift.x])
            assert_almost_eq(seam.a, middle.a, 0.002, "and so does alpha")
    assert_almost_eq(_texel(read, 399, 100).b, 1.0, 0.002, "The seam itself is no edge, the last column is filled whole")
    assert_almost_eq(_texel(read, 0, 100).b, 1.0, 0.002, "and so is the first")
    var edge := _texel(read, 2, 100).b
    assert_true(edge > 0.02 and edge < 0.98, "The wall past the seam takes a soft edge, %.3f" % edge)


## Close gaps reads the lines across the seam too. The top wall has a gap of
## eight texels that ends at the last column, so the wall that shuts its right
## half is across the seam, and at a setting of twelve only a close that reads
## past the seam keeps the fill inside. At nought the same gap leaks.
func test_close_gaps_shuts_a_gap_that_ends_at_the_seam() -> void:
    _wraps(SaProjection.Equirectangular.new())
    _ring()
    _paint_folded(Rect2i(392, 50, 8, 10), CLEAR)

    var shut: Object = _tool()
    shut.gap_close = 12
    shut.fill_at(CLICK)
    var read := _layer_bytes()
    assert_almost_eq(_texel(read, 395, 100).b, 1.0, 0.02, "The hole is filled on the right of the seam")
    assert_almost_eq(_texel(read, 5, 100).b, 1.0, 0.02, "and on the left of it")
    assert_almost_eq(_texel(read, 396, 20).a, 0.0, 0.001, "Above the gap the ground is still empty")
    assert_almost_eq(_texel(read, 200, 100).a, 0.0, 0.001, "and so is the canvas away from the ring")

    _ring()
    _paint_folded(Rect2i(392, 50, 8, 10), CLEAR)
    var open: Object = _tool()
    open.gap_close = 0
    open.fill_at(CLICK)
    assert_almost_eq(_texel(_layer_bytes(), 396, 20).b, 1.0, 0.02, "With gaps left open the same gap leaks")


## A torus wraps both axes, so a ring around the canvas's corner fills in all
## four corners and nowhere else.
func test_a_fill_on_a_torus_crosses_both_seams() -> void:
    _wraps(SaProjection.Kind.new(&"torus", "Torus", SaProjection.Wrap.XY))
    var wall := Rect2i(370, 170, 60, 60)
    var hole := Rect2i(380, 180, 40, 40)
    _paint_folded(wall, RED)
    _paint_folded(hole, CLEAR)

    _tool().fill_at(Vector2i(390, 190))

    var blue := _blue(_folded(hole))
    assert_eq(blue.x, hole.get_area(), "All four corners of the hole are filled")
    assert_eq(blue.y, 0, "and nothing outside it")
