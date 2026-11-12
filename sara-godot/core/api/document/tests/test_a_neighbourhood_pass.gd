## A neighbourhood pass reads across the seam between two chunks.
## The box blur, the first filter that reads its neighbours, is attached to
## a layer with two chunks painted side by side and a third position never
## allocated, and the chain's answer for each chunk is read one texel inside the
## shared edge and one beside the empty position.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const BoxBlurFilter = preload("res://modules/sara-base-modules/base/usual/box_blur_filter.gd")

const REQUIRES_GPU := true

const MODULE_DIR := "res://modules/sara-base-modules/base"
const KEY: StringName = &"sara-base-modules.box_blur"
const RADIUS := 4
const RED := Color(1.0, 0.0, 0.0, 1.0)
const BLUE := Color(0.0, 0.0, 1.0, 1.0)
## The row every texel below is read on, far from the canvas's top and bottom
## edges, so only the seams across x reach the box.
const ROW := 128

var _easel: SaEasel = null
var _doc: SaDocument = null
var _layer: SaLayer = null
var _record: SaAttachedFilter = null


func before_each() -> void:
    # Three chunks across and one down: (0, 0) red, (1, 0) blue, (2, 0) never
    # painted.
    _easel = Bench.easel(Vector2i(3 * SaChunk.SIZE, SaChunk.SIZE))
    _doc = _easel.document
    ModuleLoader.module_dirs[&"sara-base-modules"] = MODULE_DIR
    var blur := BoxBlurFilter.new()
    _easel.compositor.filter_chain.registry.register(blur, &"sara-base-modules")
    _layer = _doc.get_node("Background") as SaLayer
    for grid_pos: Vector2i in _layer.chunks.keys():
        _layer.chunks.erase(grid_pos)
    _layer.get_or_create_chunk(Vector2i(0, 0)).clear(RED)
    _layer.get_or_create_chunk(Vector2i(1, 0)).clear(BLUE)
    _record = SaFilterOps.new(_doc).attach(_layer, KEY, {"radius": RADIUS})
    Bench.composite(_easel)


func after_each() -> void:
    _record = null
    _easel.free()
    _easel = null
    _doc = null
    _layer = null


## The chain's answer for the chunk at *grid_pos*, read at *x* along [const ROW]
## in document pixels.
func _filtered(grid_pos: Vector2i, x: int) -> Color:
    var chain := _easel.compositor.filter_chain
    var answer := chain.filtered(_layer, _layer.get_field(grid_pos), grid_pos, SaDocument.WHOLE_CHUNK)
    return Bench.texel(answer, Vector2i(x - grid_pos.x * SaChunk.SIZE, ROW))


func test_the_record_evaluates_to_a_neighbourhood_pass() -> void:
    assert_true(_record.cached_pass is SaNeighbourhoodPass, "The box blur's run recorded a neighbourhood pass")
    if _record.cached_pass is SaNeighbourhoodPass:
        assert_eq((_record.cached_pass as SaNeighbourhoodPass).halo(), RADIUS, "whose halo is the slider's radius")
    assert_eq(_layer.chunks.size(), 2, "The layer holds the two painted chunks and nothing was allocated for the blur")


func test_a_texel_inside_the_shared_edge_reads_its_neighbours_paint() -> void:
    # One pixel inside chunk (0, 0)'s right edge: the box reaches five columns
    # of red and four of blue across the seam.
    var inside := _filtered(Vector2i(0, 0), SaChunk.SIZE - 1)
    assert_almost_eq(inside.r, 5.0 / 9.0, 0.002, "red from its own chunk, %s" % inside)
    assert_almost_eq(inside.b, 4.0 / 9.0, 0.002, "and blue from the neighbour's, %s" % inside)
    assert_almost_eq(inside.a, 1.0, 0.002, "and nothing transparent, %s" % inside)
    # And from the other side of the seam, the first column of chunk (1, 0).
    var across := _filtered(Vector2i(1, 0), SaChunk.SIZE)
    assert_almost_eq(across.r, 4.0 / 9.0, 0.002, "The blue chunk reads four columns of red, %s" % across)
    assert_almost_eq(across.b, 5.0 / 9.0, 0.002, "and five of its own blue, %s" % across)


func test_a_texel_beside_the_unallocated_position_fades_towards_transparent() -> void:
    # The last column of chunk (1, 0), beside (2, 0), which holds no chunk. A
    # mirrored edge would read opaque blue, a transparent one an alpha of five
    # ninths. The blur sums premultiplied colour, so the four
    # transparent columns lend coverage and no colour, and the blue stays blue.
    var beside := _filtered(Vector2i(1, 0), 2 * SaChunk.SIZE - 1)
    assert_almost_eq(beside.a, 5.0 / 9.0, 0.002, "Four of nine columns are transparent, %s" % beside)
    assert_almost_eq(beside.b, 1.0, 0.002, "and they bring no black into the blue, %s" % beside)
    # Deep inside, the blur of a flat colour is the colour.
    var deep := _filtered(Vector2i(1, 0), SaChunk.SIZE + 128)
    assert_almost_eq(deep.b, 1.0, 0.002, "A texel with nothing but blue in reach is blue, %s" % deep)
    assert_almost_eq(deep.a, 1.0, 0.002, "and opaque, %s" % deep)


func test_the_composite_shows_what_the_chain_answers() -> void:
    # The seam through the whole compositor, the layer below the active one.
    assert_true(_doc.active_layer != _layer, "The blurred layer is not the active one")
    var inside := Bench.texel(_easel.output, Vector2i(SaChunk.SIZE - 1, ROW))
    assert_almost_eq(inside.b, 4.0 / 9.0, 0.01, "The canvas shows the neighbour's blue across the seam, %s" % inside)
    var deep := Bench.texel(_easel.output, Vector2i(SaChunk.SIZE + 128, ROW))
    assert_almost_eq(deep.b, 1.0, 0.01, "and flat blue where nothing else is in reach, %s" % deep)


func test_a_record_switched_off_hands_the_seam_back_sharp() -> void:
    SaFilterOps.new(_doc).set_enabled(_record, false)
    Bench.composite(_easel)
    var inside := Bench.texel(_easel.output, Vector2i(SaChunk.SIZE - 1, ROW))
    assert_almost_eq(inside.r, 1.0, 0.01, "Switched off, the last red column is red again, %s" % inside)
    assert_almost_eq(inside.b, 0.0, 0.01, "with no blue in it, %s" % inside)
