## A feather's soft edge reaches the last chunk's neighbour
## and leaves no soft columns where the canvas ends.
##
## The columns at a flat canvas's very edge whole. The chunk before
## the last still read its neighbour's whole texture, and when that last chunk
## is narrower than the radius every read past the canvas found the zeros a
## rectangle leaves there, so a fill through a rectangle that meets the edge
## laid a soft band a few texels in from it. The kernel now stops such a read
## at the canvas's edge texel. Every texel of each fill's alpha is read back
## from VRAM, on the canvases the painters and the probes met it on. The
## constants are shared with the flat-canvas suite. The running app
## is `scenarios/a-feather-s-soft-edge-reaches-the-last-chunk-s-neighbour-and-leaves-soft-columns-where-the-canvas-ends.py`.
##
## SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const FLAT_CANVAS = preload(
    "res://core/api/selection/tests/test_a_soft_selection_edge_that_meets_the_canvas_edge_leaves_no_soft_column_there.gd"
)

## The rows a rectangle ten short of the edges covers, and the row read.
const TOP: int = 100
const HEIGHT: int = 200
const ROW: int = 200

var _surface: SaSurface = null
var _machine: ToolMachine = null
var _doc: SaDocument = null
var _feather_was: float = 0.0


func before_each() -> void:
    _feather_was = SaSettings.selection_feather
    SaSettings.selection_feather = 0.0


func after_each() -> void:
    SaSettings.selection_feather = _feather_was
    _drop()


## Lets the canvas go, between the sizes a test walks and after it.
func _drop() -> void:
    Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null
    _doc = null


func _canvas(size: Vector2i) -> void:
    _surface = Fixtures.make_surface(size)
    _machine = Fixtures.make_bound_machine(_surface)
    _doc = _surface.get_document()
    _doc.active_layer.allocate_grid(_doc.canvas_size)


func _feather(radius: float) -> void:
    var selection := _doc.selection
    var feather := SaSelectionFilters.feather.bind(selection, radius, _doc.canvas_size, _doc.projection.wrapping)
    selection.change(SaSelection.FEATHER_TITLE, feather)


## Every texel of the canvas from the textures *field_at* answers by grid position, *stride*
## floats a texel, *channel* the one read, as one float array row by row.
func _whole(field_at: Callable, stride: int, channel: int) -> PackedFloat32Array:
    var size := _doc.canvas_size
    var out := PackedFloat32Array()
    out.resize(size.x * size.y)
    var side := SaChunk.SIZE
    for gy in ceili(float(size.y) / side):
        for gx in ceili(float(size.x) / side):
            var texture: SaTexture = field_at.call(Vector2i(gx, gy))
            if texture == null:
                continue
            var data := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0).to_float32_array()
            for ly in mini(side, size.y - gy * side):
                var row := (ly * texture.size.x) * stride + channel
                var to := (gy * side + ly) * size.x + gx * side
                for lx in mini(side, size.x - gx * side):
                    out[to + lx] = data[row + lx * stride]
    return out


func _coverage() -> PackedFloat32Array:
    var chunks := _doc.selection.chunks
    var field := func(at: Vector2i) -> SaTexture:
        var chunk: SaChunk = chunks.get(at, null)
        return chunk.field(SaSelection.FIELD) if chunk != null else null
    return _whole(field, 1, 0)


## The fill's alpha over the whole canvas, read back from VRAM.
func _fill_alpha() -> PackedFloat32Array:
    _doc.active_layer.fill(FLAT_CANVAS.FILL)
    return _whole(_doc.active_layer.get_or_create_field, 4, 3)


## How many of *values* fall short of whole, and the least of them, as
## "count, least" for a message.
func _soft(values: PackedFloat32Array) -> Array:
    var count := 0
    var least := 1.0
    for value in values:
        if value < 1.0 - FLAT_CANVAS.TOLERANCE:
            count += 1
        least = minf(least, value)
    return [count, least]


## A rectangle over the whole canvas, feathered by *radius* and filled
## through: no texel of the fill short of whole, the band the tip read
## included.
func _assert_whole(size: Vector2i, radius: float, tip: int) -> void:
    _canvas(size)
    _doc.selection.select_rect(Rect2i(Vector2i.ZERO, size))
    _feather(radius)
    var soft := _soft(_fill_alpha())
    var what := "%s feathered by %s: no texel of the fill is soft (the tip read %d), %d at least %f"
    assert_eq(soft[0], 0, what % [size, radius, tip, soft[0], soft[1]])


func test_the_painter_s_canvas_1800_by_1200_fills_whole_through_a_feather_of_20() -> void:
    _assert_whole(Vector2i(1800, 1200), FLAT_CANVAS.FEATHER, 14400)


func test_the_probes_canvases_fill_whole_through_a_feather_of_20() -> void:
    var tips := {Vector2i(777, 333): 3663, Vector2i(1030, 300): 4200, Vector2i(512, 259): 8704, Vector2i(257, 257): 9405}
    for size: Vector2i in tips:
        _assert_whole(size, FLAT_CANVAS.FEATHER, tips[size])
        _drop()


func test_a_feather_of_two_and_a_half_on_257_by_257_fills_whole() -> void:
    _assert_whole(Vector2i(257, 257), 2.5, 1024)


## A box of 2 FEATHER + 1 texels centred SHORT outside the selection's edge
## holds FEATHER - SHORT + 1 selected texels, the tent the flat-canvas suite reads.
func test_a_rectangle_ten_short_of_the_edges_fades_as_the_tent_lays_it() -> void:
    var expected := float(FLAT_CANVAS.FEATHER - FLAT_CANVAS.SHORT + 1) / float(2 * FLAT_CANVAS.FEATHER + 1)
    for width: int in [1800, 512]:
        _canvas(Vector2i(width, 400))
        _doc.selection.select_rect(Rect2i(FLAT_CANVAS.SHORT, TOP, width - FLAT_CANVAS.SHORT * 2, HEIGHT))
        _feather(FLAT_CANVAS.FEATHER)
        var coverage := _coverage()
        for x: int in [0, width - 1]:
            var got := coverage[ROW * width + x]
            assert_almost_eq(got, expected, FLAT_CANVAS.TOLERANCE, "%d wide: column %d fades to 11 / 41, %f" % [width, x, got])
        _drop()


func test_select_all_feathered_by_20_stays_whole() -> void:
    _canvas(Vector2i(777, 333))
    _doc.selection.select_all(_doc.canvas_size)
    _feather(FLAT_CANVAS.FEATHER)
    var soft := _soft(_coverage())
    assert_eq(soft[0], 0, "Select All feathered by 20 is whole on 777 by 333, %d at least %f" % soft)


## An erode counts the canvas's edge as unselected, so a shrink keeps exactly
## the texels at least the radius from every edge.
func test_a_shrink_of_20_keeps_exactly_the_texels_20_from_every_edge() -> void:
    for size: Vector2i in [Vector2i(777, 333), Vector2i(257, 257)]:
        _canvas(size)
        var selection := _doc.selection
        selection.select_rect(Rect2i(Vector2i.ZERO, size))
        selection.change(SaSelection.SHRINK_TITLE, SaSelectionFilters.shrink.bind(selection, FLAT_CANVAS.FEATHER, size))
        var kept := Rect2i(Vector2i.ONE * FLAT_CANVAS.FEATHER, size - Vector2i.ONE * FLAT_CANVAS.FEATHER * 2)
        var coverage := _coverage()
        var wrong := 0
        for y in size.y:
            for x in size.x:
                var want := 1.0 if kept.has_point(Vector2i(x, y)) else 0.0
                if absf(coverage[y * size.x + x] - want) > FLAT_CANVAS.TOLERANCE:
                    wrong += 1
        assert_eq(wrong, 0, "%s shrunk by 20 keeps exactly the texels 20 from every edge" % size)
        _drop()


## A document whose rows wrap has no edge, and a feather across its seam is
## the far edge's tent, as the neighbouring suite reads it, on a canvas whose last chunk is
## wider than the radius and on the painter's, whose last chunk is 8 wide.
func test_a_feather_across_the_seam_of_a_wrapping_document_is_unchanged() -> void:
    for width: int in [1000, 1800]:
        _canvas(Vector2i(width, 500))
        _doc.projection = SaProjection.new(SaProjection.Equirectangular.new())
        _doc.selection.select_rect(Rect2i(width - 30, 180, 30, 40))
        _feather(8)
        var coverage := _coverage()
        for k in 9:
            var across := coverage[ROW * width + k]
            var mirrored := coverage[ROW * width + width - 31 - k]
            assert_almost_eq(
                across, (8.0 - k) / 17.0, FLAT_CANVAS.TOLERANCE, "%d wide: x %d past the seam is the tent's" % [width, k]
            )
            var what := "%d wide: and x %d before the left edge" % [width, width - 31 - k]
            assert_almost_eq(across, mirrored, FLAT_CANVAS.TOLERANCE, what)
        var inside := coverage[ROW * width + width - 1]
        assert_almost_eq(
            inside, coverage[ROW * width + width - 30], FLAT_CANVAS.TOLERANCE, "%d wide: the two edges inside are alike" % width
        )
        _drop()
