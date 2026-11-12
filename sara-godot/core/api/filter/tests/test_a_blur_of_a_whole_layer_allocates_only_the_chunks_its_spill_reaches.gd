## A blur of a whole layer writes a chunk the layer did not hold only where its
## halo carried paint into it. A short line far from its chunk's edges, blurred
## twice by the Box Blur's own pass, leaves the layer holding that one chunk,
## and a line on a chunk's right edge spills into the neighbour on that side
## alone, which undo takes away again.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const BoxBlurFilter = preload("res://modules/sara-base-modules/base/usual/box_blur_filter.gd")

const REQUIRES_GPU := true

const RADIUS := 3
const PAINT := Color(0.25, 0.5, 0.75, 1.0)
const MIDDLE := Vector2i(1, 1)

var _easel: SaEasel = null
var _doc: SaDocument = null
var _layer: SaLayer = null


func before_each() -> void:
    ModuleLoader.module_dirs[&"sara-base-modules"] = "res://modules/sara-base-modules/base"
    _easel = Bench.easel(Vector2i(3 * SaChunk.SIZE, 3 * SaChunk.SIZE))
    _doc = _easel.document
    _layer = _doc.active_layer
    for grid_pos: Vector2i in _layer.chunks.keys():
        _layer.chunks.erase(grid_pos)
    _doc.history.reset()
    _doc.undo_redo.clear_history()


func after_each() -> void:
    _easel.free()
    _easel = null
    _doc = null
    _layer = null


## The middle row of a chunk, where the lines are painted.
func _row() -> int:
    return floori(SaChunk.SIZE / 2.0)


## A line of [const PAINT] three texels high across the chunk's own columns
## *from* to *to*, at its middle row, on a chunk at [const MIDDLE].
func _line(from: int, to: int) -> void:
    var side := SaChunk.SIZE
    var texture := _layer.get_or_create_chunk(MIDDLE).albedo()
    var image := Image.create_empty(side, side, false, Image.FORMAT_RGBAF)
    for y: int in range(_row() - 1, _row() + 2):
        for x: int in range(from, to):
            image.set_pixel(x, y, PAINT)
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, image.get_data())


## The Box Blur at [const RADIUS] applied over the whole layer, as its Apply
## walks it.
func _blur() -> bool:
    var radius := {"radius": RADIUS}
    var recorded := SaNeighbourhoodPass.new(BoxBlurFilter.SHADER, "blur_across", SaTyped.strings(radius), RADIUS)
    recorded.then("blur_down", SaTyped.strings(radius)).then("blur", SaTyped.strings(radius))
    var compute := SaCompute.new(BoxBlurFilter.SHADER)
    compute.use_storage_format(_layer.get_field(MIDDLE).format)
    return SaFilterApply.apply_neighbourhood(_doc, _layer, recorded, compute, "Box blur")


func _held() -> Array:
    var held := _layer.chunks.keys()
    held.sort()
    return held


func test_a_line_far_from_its_chunk_s_edges_stays_in_its_one_chunk() -> void:
    _line(100, 120)
    assert_true(_blur(), "The first blur writes")
    assert_eq(_held(), [MIDDLE], "and the layer holds the line's chunk alone")
    assert_true(_blur(), "The second blur writes")
    assert_eq(_held(), [MIDDLE], "and the grid is still the line's own chunk, with no ring of empty ones round it")
    var softened := Bench.texel(_layer.get_field(MIDDLE), Vector2i(100 - RADIUS + 1, _row()))
    assert_true(softened.a > 0.0, "The blur did spread the line within its chunk")


func test_a_line_on_a_chunk_s_edge_spills_into_the_neighbour_and_undo_takes_it_away() -> void:
    _line(SaChunk.SIZE - 20, SaChunk.SIZE)
    assert_true(_blur(), "The blur writes")
    var right := MIDDLE + Vector2i(1, 0)
    assert_eq(_held(), [MIDDLE, right], "The spill past the right edge allocates the chunk on that side alone")
    var spilt := Bench.texel(_layer.get_field(right), Vector2i(0, _row()))
    assert_true(spilt.a > 0.0, "which holds the spilt paint")
    assert_true(_doc.undo_redo.undo(), "The blur undoes")
    assert_eq(_held(), [MIDDLE], "and the neighbour goes with it")
