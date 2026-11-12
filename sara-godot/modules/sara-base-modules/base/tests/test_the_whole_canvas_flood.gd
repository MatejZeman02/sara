## The flood on a layer with nothing in it, and the sweeps it no longer repeats.
##
## A fill on a full HD empty canvas must not take seconds. A flood that sweeps every chunk costs 813
## dispatches for that click, most of them sweeps of chunks where the region has
## already stopped. Two things answer it here. A layer with no chunks reads one
## transparent texel everywhere, so its flood is the whole canvas and is built
## without a sweep. And a sweep runs again only over the chunks where the region
## can still move, which every other flood gains from.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const RED := Color(1.0, 0.0, 0.0, 1.0)

## Neither side a whole number of chunks, so the edge chunks are part-canvas.
const CANVAS := Vector2i(600, 300)

var _easel: SaEasel = null
var _doc: SaDocument = null


func before_each() -> void:
    _easel = SaEasel.create_default(CANVAS)
    _doc = _easel.document
    SaCompute.reset_counters()


func after_each() -> void:
    _easel.free()
    _easel = null
    _doc = null


func _flood(start: Vector2i, mode: int = SaSelection.Mode.REPLACE) -> int:
    return SaWand.new().flood(_doc, start, 0.05, mode, null, _doc.active_layer)


func _sweeps() -> int:
    var entry: Dictionary = SaCompute.kernel_counters().get("wand/sweep_rows", {})
    return int(entry.get("dispatches", 0))


func _mask_bytes() -> Dictionary:
    var bytes: Dictionary = {}
    for grid_pos: Vector2i in _doc.selection.chunks:
        var texture := (_doc.selection.chunks[grid_pos] as SaChunk).field(SaSelection.FIELD)
        bytes[grid_pos] = GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return bytes


func _coverage(x: int, y: int) -> float:
    @warning_ignore("integer_division")
    var chunk: SaChunk = _doc.selection.chunks.get(Vector2i(x / SaChunk.SIZE, y / SaChunk.SIZE), null)
    if chunk == null:
        return 0.0
    var texture := chunk.field(SaSelection.FIELD)
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return bytes.decode_float(((y % SaChunk.SIZE) * texture.size.x + x % SaChunk.SIZE) * 4)


func test_an_empty_layer_floods_the_whole_canvas_without_a_sweep() -> void:
    assert_true(_doc.active_layer.chunks.is_empty(), "The fixture's layer holds no chunk")
    var reached := _flood(Vector2i(300, 150))
    assert_eq(reached, 6, "Three chunks by two cover a 600 by 300 canvas")
    assert_eq(_sweeps(), 0, "and no sweep ran to find that out")
    assert_eq(_doc.selection.bounds, Rect2i(Vector2i.ZERO, CANVAS), "The box is the canvas")
    assert_almost_eq(_coverage(0, 0), 1.0, 0.001, "The first texel is selected")
    assert_almost_eq(_coverage(599, 299), 1.0, 0.001, "and the last")
    assert_almost_eq(_coverage(600, 10), 0.0, 0.001, "and an edge chunk's texel past the canvas is not")
    assert_almost_eq(_coverage(10, 300), 0.0, 0.001, "down the other edge either")


func test_the_whole_canvas_is_what_the_sweeps_would_have_selected() -> void:
    _flood(Vector2i(300, 150))
    var shortcut := _mask_bytes()
    # One transparent chunk in the layer, so the flood reads the same picture
    # through the sweeps rather than the shortcut.
    _doc.active_layer.get_or_create_chunk(Vector2i(1, 0))
    _doc.selection.deselect()
    SaCompute.reset_counters()
    _flood(Vector2i(300, 150))
    assert_true(_sweeps() > 0, "The second flood swept")
    var swept := _mask_bytes()
    assert_eq(swept.keys().size(), shortcut.keys().size(), "Both reach the same chunks")
    for grid_pos: Vector2i in shortcut:
        assert_true(swept.has(grid_pos) and swept[grid_pos] == shortcut[grid_pos], "and chunk %s is the same mask" % grid_pos)
    assert_eq(_doc.selection.bounds, Rect2i(Vector2i.ZERO, CANVAS), "with the same box")


func test_the_whole_canvas_joins_a_selection_in_the_mode_asked() -> void:
    _doc.selection.select_rect(Rect2i(10, 10, 20, 20))
    _flood(Vector2i(300, 150), SaSelection.Mode.SUBTRACT)
    assert_almost_eq(_coverage(15, 15), 0.0, 0.001, "Taking the canvas out of a selection leaves nothing of it")
    assert_eq(_doc.selection.bounds.size, Vector2i.ZERO, "and an empty box")


## A region reaching every chunk of a transparent layer, on a full HD
## canvas. Sweeping every chunk the region holds on every sweep cost
## 192 row sweeps here. A chunk now sweeps again only when it or a neighbour
## changed, which came to 116, about three a chunk.
func test_a_chunk_is_swept_again_only_while_the_region_can_move_in_it() -> void:
    _easel.free()
    _easel = SaEasel.create_default(Vector2i(1920, 1080))
    _doc = _easel.document
    _doc.active_layer.get_or_create_chunk(Vector2i(0, 0))
    SaCompute.reset_counters()
    var reached := _flood(Vector2i(960, 540))
    assert_eq(reached, 40, "The region reaches all forty chunks")
    assert_eq(_doc.selection.bounds, Rect2i(0, 0, 1920, 1080), "and the whole canvas")
    assert_true(_sweeps() < 192, "in fewer row sweeps than sweeping every chunk every time took")


## A sweep that takes nothing must not end the flood before the edges it
## reached are read, so a region that met a seam on its first sweep never
## crossed it.
func test_a_region_crosses_a_seam_it_meets_on_the_first_sweep() -> void:
    _doc.selection.select_rect(Rect2i(250, 100, 7, 1))
    _doc.fill_layer(RED, _doc.active_layer)
    _doc.selection.deselect()
    _flood(Vector2i(256, 100))
    assert_almost_eq(_coverage(256, 100), 1.0, 0.001, "The seed is selected")
    assert_almost_eq(_coverage(250, 100), 1.0, 0.001, "and the red across the seam")
    assert_eq(_doc.selection.bounds, Rect2i(250, 100, 7, 1), "and nothing else")
