## A filter on a wrapped document reads across the seam. An
## equirectangular document's left edge meets its right, so the halo of a blur
## past either edge reads the texels at the far side, the position taken modulo
## the canvas's width, and a blur of the sky has no line where it was cut. The
## top and bottom still clamp, and a flat document clamps on all four sides as
## it did.
##
## The picture is black on its left half and white on its right, so the seam
## is a black and white boundary as the middle is, mirrored: a texel a step
## from the seam blends as the texel the same step from the middle does. On a
## canvas whose width is no multiple of the chunk's side, the paint past the
## canvas in its last chunk is green, which a read past the canvas would show.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const GaussianBlurFilter = preload("res://modules/sara-base-modules/base/usual/gaussian_blur_filter.gd")

const REQUIRES_GPU := true

const OWNER: StringName = &"sara-base-modules"
const RADIUS := 9.0
const HEIGHT := 200
const ROW := 100
const BLACK := Color(0.0, 0.0, 0.0, 1.0)
const WHITE := Color(1.0, 1.0, 1.0, 1.0)
const GREEN := Color(0.0, 1.0, 0.0, 1.0)
## A multiple of the chunk's side and one that is not.
const WIDTHS: Array[int] = [2 * SaChunk.SIZE, 300]
## A dab at the right edge of chunk (1, 0) of a canvas two chunks across, in
## its own pixels, the rectangle the brush hands the document.
const DAB := Rect2i(SaChunk.SIZE - 6, 120, 6, 16)

var _easel: SaEasel = null
var _doc: SaDocument = null
var _layer: SaLayer = null
var _filter: SaGaussianBlurFilter = null
var _key: StringName = &""


func after_each() -> void:
    _release()


func _release() -> void:
    _filter = null
    _layer = null
    _doc = null
    if _easel != null:
        _easel.free()
    _easel = null


## A document *size* across, equirectangular when *wrapped*, painted as
## *picture* answers each document pixel, or else black on its left half and
## white on its right with green past the canvas.
func _build(size: Vector2i, wrapped: bool, picture := Callable()) -> void:
    _release()
    _easel = Bench.easel(size)
    _doc = _easel.document
    if wrapped:
        _doc.projection = SaProjection.new(SaProjection.Equirectangular.new())
    _filter = GaussianBlurFilter.new()
    _easel.compositor.filter_chain.registry.register(_filter, OWNER)
    _key = SaFilterRegistry.key_for(OWNER, _filter)
    _layer = _doc.get_node("Background") as SaLayer
    for grid_pos: Vector2i in _layer.chunks.keys():
        _layer.chunks.erase(grid_pos)
    var colour := picture if picture.is_valid() else func(at: Vector2i) -> Color: return _halves(at, size)
    for grid_pos: Vector2i in SaLayer.grid_positions(size):
        _paint(grid_pos, colour)


## The picture at the document pixel *at* of a canvas of *size*.
static func _halves(at: Vector2i, size: Vector2i) -> Color:
    if at.x >= size.x or at.y >= size.y:
        return GREEN
    return BLACK if at.x * 2 < size.x else WHITE


## Writes the chunk at *grid_pos* as *colour* answers each document pixel.
func _paint(grid_pos: Vector2i, colour: Callable) -> void:
    var texture := _layer.get_or_create_chunk(grid_pos).field(SaFieldSpec.ALBEDO)
    assert_eq(texture.format, RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT, "The bench document is F32")
    var values := PackedFloat32Array()
    values.resize(SaChunk.SIZE * SaChunk.SIZE * 4)
    for y in SaChunk.SIZE:
        for x in SaChunk.SIZE:
            var texel: Color = colour.call(grid_pos * SaChunk.SIZE + Vector2i(x, y))
            var i := (y * SaChunk.SIZE + x) * 4
            values[i] = texel.r
            values[i + 1] = texel.g
            values[i + 2] = texel.b
            values[i + 3] = texel.a
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, values.to_byte_array())


## Attaches the blur to *on*, the root when null, and composites everything.
func _attach(on: SaLayer) -> void:
    _filter.set_parameters({"radius": RADIUS})
    SaFilterOps.new(_doc).attach(on, _key, _filter.parameters())
    Bench.composite(_easel)


## The red of every texel of *row* of the composited picture, one read back.
func _composited(row: int) -> PackedFloat32Array:
    var output := _easel.output
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(output.rid, 0)
    var reds := PackedFloat32Array()
    for x in output.size.x:
        reds.append(SaFieldSpec.decode_texel(bytes, output.format, row * output.size.x + x).r)
    return reds


## The red of every texel of *column* of the composited picture.
func _composited_column(column: int) -> PackedFloat32Array:
    var output := _easel.output
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(output.rid, 0)
    var reds := PackedFloat32Array()
    for y in output.size.y:
        reds.append(SaFieldSpec.decode_texel(bytes, output.format, y * output.size.x + column).r)
    return reds


## The red of every texel of *row* of the layer itself, chunk by chunk.
func _stored(row: int, width: int) -> PackedFloat32Array:
    var reds := PackedFloat32Array()
    var held: Dictionary[Vector2i, PackedByteArray] = {}
    for x in width:
        var grid_pos := SaChunkWalk.positions_in(Rect2i(x, row, 1, 1))[0]
        var texture := _layer.get_field(grid_pos)
        if not held.has(grid_pos):
            held[grid_pos] = GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
        var at := Vector2i(x, row) - grid_pos * SaChunk.SIZE
        reds.append(SaFieldSpec.decode_texel(held[grid_pos], texture.format, at.y * SaChunk.SIZE + at.x).r)
    return reds


## Reads *reds*, a row of a blurred canvas *width* across, blending across the
## seam as it does across the middle: a step *d* from the seam on the black
## side reads as a step *d* from the middle on the black side, and so on the
## white side.
func _assert_seam_as_middle(reds: PackedFloat32Array, width: int, what: String) -> void:
    var middle := floori(width / 2.0)
    for d in int(RADIUS) + 3:
        var black_seam := reds[d]
        var black_middle := reds[middle - 1 - d]
        var white_seam := reds[width - 1 - d]
        var white_middle := reds[middle + d]
        assert_almost_eq(black_seam, black_middle, 0.001, "%s, %d in from the left edge as from the middle" % [what, d])
        assert_almost_eq(white_seam, white_middle, 0.001, "%s, %d in from the right edge as from the middle" % [what, d])
    assert_true(reds[0] > 0.2 and reds[0] < 0.5, "%s, the left edge takes in the white across the seam, %f" % [what, reds[0]])
    assert_true(reds[width - 1] > 0.5 and reds[width - 1] < 0.8, "%s, the right edge the black, %f" % [what, reds[width - 1]])


func test_an_attached_blur_blends_across_the_seam_as_across_the_middle() -> void:
    for width: int in WIDTHS:
        _build(Vector2i(width, HEIGHT), true)
        _attach(_layer)
        _assert_seam_as_middle(_composited(ROW), width, "On a layer %d across" % width)
        _assert_seam_as_middle(_composited(0), width, "and on its top row, which clamps")


func test_a_blur_on_the_root_blends_across_the_seam_too() -> void:
    for width: int in WIDTHS:
        _build(Vector2i(width, HEIGHT), true)
        _attach(null)
        _assert_seam_as_middle(_composited(ROW), width, "On the root %d across" % width)


func test_a_one_shot_blur_writes_the_seam_blended() -> void:
    for width: int in WIDTHS:
        _build(Vector2i(width, HEIGHT), true)
        _filter.set_parameters({"radius": RADIUS})
        var ctx := SaFilterContext.new(_doc, _layer, OWNER, _filter.title(), false)
        assert_true(SaFilterApply.call_run(_filter, ctx), "The blur records a pass")
        assert_true(SaFilterApply.apply(ctx, "Gaussian Blur"), "and Apply writes it")
        _assert_seam_as_middle(_stored(ROW, width), width, "Applied %d across" % width)


func test_assigning_a_panorama_under_an_attached_blur_redraws_the_seam() -> void:
    var width: int = WIDTHS[1]
    _build(Vector2i(width, HEIGHT), false)
    _attach(_layer)
    assert_almost_eq(_composited(ROW)[0], 0.0, 0.0001, "Flat, the left edge reads its own black past it")
    assert_true(SaProjection.assign(_doc, SaProjection.new(SaProjection.Equirectangular.new())), "The assign is a step")
    _easel.process_pending_composite()
    _assert_seam_as_middle(_composited(ROW), width, "Assigned equirectangular after the blur")


func test_a_kind_that_wraps_both_ways_reads_across_the_top_and_bottom_too() -> void:
    # No built-in kind joins its top to its bottom, and a module's may, so the
    # padding reads the wrap the kind declares rather than a kind it knows.
    var size := Vector2i(WIDTHS[1], HEIGHT)
    var rows := func(at: Vector2i) -> Color: return BLACK if at.y * 2 < size.y else WHITE
    _build(size, false, rows)
    _doc.projection = SaProjection.new(SaProjection.Kind.new(&"torus", "Torus", SaProjection.Wrap.XY))
    _attach(_layer)
    _assert_seam_as_middle(_composited_column(floori(size.x / 3.0)), size.y, "Down a column of a torus")
    _assert_seam_as_middle(_composited_column(0), size.y, "and down its left edge, past both seams at the corners")


func test_a_flat_document_clamps_at_its_edges_as_it_did() -> void:
    for width: int in WIDTHS:
        _build(Vector2i(width, HEIGHT), false)
        _attach(_layer)
        var reds := _composited(ROW)
        var middle := reds[floori(width / 2.0)]
        assert_almost_eq(reds[0], 0.0, 0.0001, "Flat %d across, the left edge reads its own black past it" % width)
        assert_almost_eq(reds[width - 1], 1.0, 0.0001, "and the right edge its own white")
        assert_true(middle > 0.5 and middle < 1.0, "while the middle blends, %f" % middle)


## The dab painted white into a black chunk (1, 0) and handed to the document,
## as a stroke's dab is, and the dirty set it leaves before the composite.
func _dab() -> Dictionary[Vector2i, Rect2i]:
    var origin := Vector2i(SaChunk.SIZE, 0)
    _paint(Vector2i(1, 0), func(at: Vector2i) -> Color: return WHITE if DAB.has_point(at - origin) else BLACK)
    _doc.invalidate_chunk_regions({Vector2i(1, 0): DAB})
    return _doc._dirty_chunks.duplicate()


func test_a_dab_at_the_right_edge_under_a_blur_redraws_the_left_edges_chunk() -> void:
    var size := Vector2i(2 * SaChunk.SIZE, SaChunk.SIZE)
    var black := func(_at: Vector2i) -> Color: return BLACK
    _build(size, true, black)
    _attach(_layer)
    var before := _composited(DAB.position.y + 8)
    assert_almost_eq(before[0], 0.0, 0.0001, "The left edge is black before the dab")
    var dirty := _dab()
    assert_true(dirty.has(Vector2i.ZERO), "The dab's halo across the seam makes the left edge's chunk stale, %s" % dirty)
    var left: Rect2i = dirty.get(Vector2i.ZERO, Rect2i())
    assert_eq(left.position.x, 0, "from the left edge")
    assert_eq(left.size.x, int(RADIUS), "as far in as the halo reaches past the right edge, %s" % left)
    _easel.request_composite()
    _easel.process_pending_composite()
    var after := _composited(DAB.position.y + 8)
    assert_true(after[0] > 0.01, "and the composite redraws it with the dab's white blurred in, %f" % after[0])
    assert_true(after[0] < after[size.x - 1], "fainter than at the right edge the dab is on, %f" % after[size.x - 1])


func test_a_dab_at_the_right_edge_of_a_flat_document_stays_on_its_side() -> void:
    var size := Vector2i(2 * SaChunk.SIZE, SaChunk.SIZE)
    var black := func(_at: Vector2i) -> Color: return BLACK
    _build(size, false, black)
    _attach(_layer)
    var dirty := _dab()
    assert_false(dirty.has(Vector2i.ZERO), "A flat document's left edge is not stale, %s" % dirty)
    _easel.request_composite()
    _easel.process_pending_composite()
    assert_almost_eq(_composited(DAB.position.y + 8)[0], 0.0, 0.0001, "and stays black")
