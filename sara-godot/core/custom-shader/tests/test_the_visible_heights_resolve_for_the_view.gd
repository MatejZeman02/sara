## The visible heights resolve into one texture for the view.
##
## Every layer that shows and carries height is summed by its opacity into one
## dense texture beside the composite, over the same dirty rectangles, and a
## normal is derived from the sum. The suite reads the resolved texture back
## texel by texel: across a chunk's seam, under a hidden layer and a halved
## one, under a mask, where the window has not reached, and in the dispatch
## tally, which says whether a stroke's resolve stays inside its rectangles.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

## A ramp of this many millimetres a pixel, exact in a half float over the two
## chunks it spans, so a normal that differs is a fault and not rounding.
const RAMP_MM: float = 0.0625

var _registries: SaRegistries = null
var _easel: SaEasel = null
var _doc: SaDocument = null


func before_each() -> void:
    _registries = Fixtures.make_registries()
    _easel = SaEasel.create_default(Vector2i(768, 768))
    _easel.compositor.set_registry(_registries.blend_modes)
    _doc = _easel.document
    _easel.process_pending_composite()


func after_each() -> void:
    _easel.free()
    _easel = null
    _doc = null
    _registries = null


func _texel(texture: SaTexture, at: Vector2i) -> Color:
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return SaFieldSpec.decode_texel(bytes, texture.format, at.y * texture.size.x + at.x)


## Gives *layer* its height through the step and writes a chunk of it at
## *grid_pos*, each texel's height what *height_of* answers for its canvas
## pixel, then marks the chunk dirty the way a dab does.
func _raise(layer: SaLayer, grid_pos: Vector2i, height_of: Callable) -> void:
    SaHeightOps.new(_doc).gain(layer)
    var texture := layer.get_or_create_field(grid_pos, SaFieldSpec.HEIGHT)
    var side := texture.size
    var bytes := PackedByteArray()
    bytes.resize(side.x * side.y * 2)
    for y in side.y:
        for x in side.x:
            var pixel := grid_pos * SaLayer.CHUNK_SIZE + Vector2i(x, y)
            bytes.encode_half((y * side.x + x) * 2, float(height_of.call(pixel)))
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, bytes)
    _doc.invalidate_chunks([grid_pos])


func _flat(height: float) -> Callable:
    return func(_pixel: Vector2i) -> float: return height


func _ramp(pixel: Vector2i) -> float:
    return float(pixel.x) * RAMP_MM


func test_a_document_with_no_height_allocates_nothing_and_dispatches_nothing() -> void:
    SaCompute.reset_counters()
    _doc.invalidate_all_allocated_chunks()
    _easel.request_full_composite()
    _easel.process_pending_composite()
    var tally := SaCompute.kernel_counters()
    assert_null(_easel.relief.texture, "No layer carries height, so no relief texture is allocated")
    assert_false(tally.has("relief_sum/sum_height"), "and no cell is summed")
    assert_false(tally.has("relief_normal/derive_normal"), "and no normal derived")


func test_a_normal_across_a_chunk_seam_has_no_step() -> void:
    var layer := _doc.active_layer
    _raise(layer, Vector2i(0, 0), _ramp)
    _raise(layer, Vector2i(1, 0), _ramp)
    _easel.process_pending_composite()
    var relief := _easel.relief.texture
    assert_not_null(relief, "Height on a visible layer allocates the relief")
    if relief == null:
        return
    assert_eq(relief.size, _doc.canvas_size, "the size of the view's composite")
    var pixel_mm := 25.4 / _doc.dpi
    var slope := RAMP_MM / pixel_mm
    var expected := Vector3(-slope, 0.0, 1.0).normalized()
    var seam := SaLayer.CHUNK_SIZE
    for x: int in [seam - 3, seam - 2, seam - 1, seam, seam + 1, seam + 2]:
        var texel := _texel(relief, Vector2i(x, 40))
        assert_almost_eq(texel.r, expected.x, 0.002, "The normal at x %d leans with the ramp, seam or not" % x)
        assert_almost_eq(texel.g, 0.0, 0.002, "and not along y at x %d" % x)
        assert_almost_eq(texel.b, expected.z, 0.002, "and faces the viewer at x %d" % x)
        assert_almost_eq(texel.a, float(x) * RAMP_MM, 0.0001, "The height at x %d is the ramp's" % x)
    var last := _texel(relief, Vector2i(seam - 1, 40))
    var first := _texel(relief, Vector2i(seam, 40))
    assert_almost_eq(first.r - last.r, 0.0, 0.0005, "The two texels either side of the seam lean the same")


func test_a_hidden_layer_leaves_the_sum_and_a_halved_one_counts_half() -> void:
    var lower := _doc.active_layer
    var upper := SaLayerOps.new(_doc).add()
    _raise(lower, Vector2i(1, 1), _flat(2.0))
    _raise(upper, Vector2i(1, 1), _flat(4.0))
    _easel.process_pending_composite()
    var at := Vector2i(300, 300)
    assert_almost_eq(_texel(_easel.relief.texture, at).a, 6.0, 0.001, "Two visible layers add their heights")
    assert_almost_eq(_texel(_easel.relief.heights, at).r, 6.0, 0.001, "in the summed height as well")

    var ops := SaLayerOps.new(_doc)
    ops.set_visible(lower, false)
    _easel.process_pending_composite()
    assert_almost_eq(_texel(_easel.relief.texture, at).a, 4.0, 0.001, "A hidden layer leaves the sum")

    ops.set_opacity(upper, 0.5)
    _easel.process_pending_composite()
    assert_almost_eq(_texel(_easel.relief.texture, at).a, 2.0, 0.001, "and a layer at half opacity counts half")

    ops.set_visible(lower, true)
    _easel.process_pending_composite()
    assert_almost_eq(_texel(_easel.relief.texture, at).a, 4.0, 0.001, "Shown again, the lower layer adds back")
    assert_almost_eq(_texel(_easel.relief.texture, at).b, 1.0, 0.0001, "and a flat height faces the viewer")


func test_a_masked_out_layer_shows_no_height() -> void:
    var layer := _doc.active_layer
    _raise(layer, Vector2i(0, 0), _flat(3.0))
    _easel.process_pending_composite()
    assert_almost_eq(_texel(_easel.relief.texture, Vector2i(20, 20)).a, 3.0, 0.001, "The layer's height shows")
    layer.add_mask(0.0)
    _doc.invalidate_chunks([Vector2i(0, 0)])
    _easel.process_pending_composite()
    assert_almost_eq(_texel(_easel.relief.texture, Vector2i(20, 20)).a, 0.0, 0.001, "and a mask hiding it hides it")


func test_height_that_goes_away_leaves_the_cell_bare() -> void:
    var layer := _doc.active_layer
    _raise(layer, Vector2i(2, 0), _flat(5.0))
    _easel.process_pending_composite()
    assert_almost_eq(_texel(_easel.relief.texture, Vector2i(600, 10)).a, 5.0, 0.001, "The height shows")
    layer.drop_field(SaFieldSpec.HEIGHT)
    _doc.invalidate_chunks([Vector2i(2, 0)])
    SaCompute.reset_counters()
    _easel.process_pending_composite()
    assert_almost_eq(_texel(_easel.relief.texture, Vector2i(600, 10)).a, 0.0, 0.001, "and bare once it is gone")
    assert_eq(int(SaCompute.kernel_counters()["relief_sum/sum_height"]["dispatches"]), 1, "in one dispatch")
    _doc.invalidate_chunks([Vector2i(2, 0)])
    SaCompute.reset_counters()
    _easel.process_pending_composite()
    assert_false(SaCompute.kernel_counters().has("relief_sum/sum_height"), "and a bare cell costs nothing after")


func test_a_cell_the_window_misses_waits_for_it() -> void:
    var layer := _doc.active_layer
    _easel.shown_rect = func() -> Rect2: return Rect2(0, 0, 10, 10)
    _raise(layer, Vector2i(2, 2), _flat(1.5))
    _easel.process_pending_composite()
    assert_null(_easel.relief.texture, "A height the window cannot reach is not resolved")
    _easel.shown_rect = func() -> Rect2: return Rect2(500, 500, 100, 100)
    _easel.process_pending_composite()
    assert_not_null(_easel.relief.texture, "and is once the window reaches it")
    if _easel.relief.texture != null:
        assert_almost_eq(_texel(_easel.relief.texture, Vector2i(700, 700)).a, 1.5, 0.001, "at its height")


func test_a_dirty_rectangle_resolves_that_rectangle_and_its_ring() -> void:
    var layer := _doc.active_layer
    _raise(layer, Vector2i(1, 1), _flat(2.0))
    _easel.process_pending_composite()
    SaCompute.reset_counters()
    _doc.invalidate_chunk_regions({Vector2i(1, 1): Rect2i(40, 40, 16, 16)})
    _easel.process_pending_composite()
    var tally := SaCompute.kernel_counters()
    var summed: Dictionary = tally.get("relief_sum/sum_height", {})
    var derived: Dictionary = tally.get("relief_normal/derive_normal", {})
    assert_eq(int(summed.get("dispatches", 0)), 1, "One layer over one dirty rectangle is one dispatch")
    assert_eq(int(summed.get("workgroups", 0)), 4, "of the rectangle's four groups, never the cell's 1024")
    assert_eq(int(derived.get("workgroups", 0)), 9, "and the normal over the rectangle grown by a texel, nine")
