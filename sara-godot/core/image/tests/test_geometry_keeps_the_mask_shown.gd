## A geometry pass leaves a mask at one where it wrote nothing.
##
## gave a mask a blank of one, so a chunk allocated under the brush opens
## fully shown. The resample and the crop that clears outside each blanked a
## fresh chunk a second time through a kernel that writes zero into every field,
## and zero is no paint for colour and fully hidden for a mask. Every texel here
## is read back, because a mask at zero returns a plausible picture, an empty one.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const RED := Color(1.0, 0.0, 0.0, 1.0)

var _easel: SaEasel = null
var _doc: SaDocument = null


func before_each() -> void:
    _easel = SaEasel.create_default(Vector2i(512, 512))
    _doc = _easel.document


func after_each() -> void:
    _easel.free()
    _easel = null
    _doc = null


func _texel(texture: SaTexture, at: Vector2i) -> Color:
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return SaFieldSpec.decode_texel(bytes, texture.format, at.y * texture.size.x + at.x)


func _mask_at(layer: SaLayer, grid_pos: Vector2i, at: Vector2i) -> float:
    var chunk: SaChunk = layer.chunks.get(grid_pos, null)
    assert_not_null(chunk, "The pass left a chunk at %s" % grid_pos)
    if chunk == null or chunk.field(SaFieldSpec.MASK) == null:
        return -1.0
    return _texel(chunk.field(SaFieldSpec.MASK), at).r


## The active layer holding red in *grid*, under a mask of *value* everywhere.
func _masked_layer(grid: Array[Vector2i], value: float) -> SaLayer:
    var layer := _doc.active_layer
    for grid_pos: Vector2i in grid:
        layer.get_or_create_chunk(grid_pos).clear(RED)
    layer.add_mask(value)
    return layer


func test_a_resample_leaves_the_mask_shown_where_no_source_texel_mapped() -> void:
    var layer := _masked_layer([Vector2i(0, 0)], 1.0)
    assert_true(SaResample.new(_doc).resample_to(Vector2i(300, 300)), "The pass ran")
    assert_almost_eq(_mask_at(layer, Vector2i(0, 0), Vector2i(10, 10)), 1.0, 0.0001, "Where a source texel mapped")
    assert_almost_eq(_mask_at(layer, Vector2i(0, 0), Vector2i(200, 200)), 1.0, 0.0001, "and where none did")


func test_a_resampled_hidden_mask_stays_hidden_up_to_its_own_edge() -> void:
    var layer := _masked_layer([Vector2i(0, 0)], 0.0)
    assert_true(SaResample.new(_doc).resample_to(Vector2i(300, 300)), "The pass ran")
    assert_almost_eq(_mask_at(layer, Vector2i(0, 0), Vector2i(10, 10)), 0.0, 0.0001, "The mask the painter made is kept")
    assert_almost_eq(_mask_at(layer, Vector2i(0, 0), Vector2i(149, 149)), 0.0, 0.0001, "to the last texel it maps into")
    assert_almost_eq(_mask_at(layer, Vector2i(0, 0), Vector2i(150, 150)), 1.0, 0.0001, "and the first past it is shown")
    assert_almost_eq(_mask_at(layer, Vector2i(0, 0), Vector2i(200, 200)), 1.0, 0.0001, "like everything after it")


func test_a_nearest_resample_draws_the_same_line() -> void:
    var layer := _masked_layer([Vector2i(0, 0)], 0.0)
    var geometry := SaResample.new(_doc)
    geometry.filter = SaResampleKernel.Filter.NEAREST
    assert_true(geometry.resample_to(Vector2i(300, 300)), "The pass ran")
    assert_almost_eq(_mask_at(layer, Vector2i(0, 0), Vector2i(149, 149)), 0.0, 0.0001, "The last texel the mask maps into")
    assert_almost_eq(_mask_at(layer, Vector2i(0, 0), Vector2i(150, 150)), 1.0, 0.0001, "and the first past it")


## The resample asks each held chunk and makes no chunk for the hole between two
## of them, rule 3, so what is left to hold is that a chunk the brush makes there
## afterwards still opens shown.
func test_a_hole_inside_the_painted_bounds_resamples_as_shown() -> void:
    var layer := _masked_layer([Vector2i(0, 0), Vector2i(1, 1)], 0.0)
    assert_true(SaResample.new(_doc).resample_to(Vector2i(1024, 1024)), "The pass ran")
    assert_almost_eq(_mask_at(layer, Vector2i(0, 0), Vector2i(128, 128)), 0.0, 0.0001, "The hidden chunk doubles as hidden")
    assert_false(layer.chunks.has(Vector2i(2, 0)), "and the hole nobody held is not made")
    var hole := layer.get_or_create_chunk(Vector2i(2, 0))
    assert_almost_eq(_mask_at(layer, Vector2i(2, 0), Vector2i(128, 128)), 1.0, 0.0001, "A chunk the brush makes there is shown")
    assert_almost_eq(_texel(hole.albedo(), Vector2i(128, 128)).a, 0.0, 0.0001, "while its paint is still none")


func test_a_crop_that_clears_outside_leaves_the_mask_shown_there() -> void:
    var layer := _masked_layer([Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)], 1.0)
    assert_true(SaCrop.new(_doc).crop_to(Rect2i(0, 0, 150, 150), true), "The crop ran")
    assert_almost_eq(_mask_at(layer, Vector2i(0, 0), Vector2i(10, 10)), 1.0, 0.0001, "Inside the rectangle")
    assert_almost_eq(_mask_at(layer, Vector2i(0, 0), Vector2i(200, 200)), 1.0, 0.0001, "and in the overhang it cleared")
    var chunk: SaChunk = layer.chunks.get(Vector2i(0, 0), null)
    if chunk != null:
        assert_almost_eq(_texel(chunk.albedo(), Vector2i(200, 200)).a, 0.0, 0.0001, "whose paint it did clear")


func test_a_crop_that_clears_outside_keeps_a_hidden_mask_inside() -> void:
    var layer := _masked_layer([Vector2i(0, 0)], 0.0)
    assert_true(SaCrop.new(_doc).crop_to(Rect2i(0, 0, 150, 150), true), "The crop ran")
    assert_almost_eq(_mask_at(layer, Vector2i(0, 0), Vector2i(10, 10)), 0.0, 0.0001, "What the painter hid stays hidden")
    assert_almost_eq(_mask_at(layer, Vector2i(0, 0), Vector2i(200, 200)), 1.0, 0.0001, "and the cleared overhang is shown")


## The transform carries the mask with the paint now, so the chunk it
## allocates on the way down takes the moved mask under the landing and keeps
## the blank `SaChunk.clear` gave it everywhere else. Measured here rather
## than assumed, because the filing left it open.
func test_a_transform_that_lands_in_a_fresh_chunk_leaves_its_mask_shown() -> void:
    var layer := _masked_layer([Vector2i(0, 0)], 0.0)
    var box := Rect2i(100, 100, 100, 100)
    _doc.selection.select_rect(box)
    var geometry := SaTransform.new(_doc)
    assert_true(geometry.lift(layer, box), "A selection over paint is something to lift")
    geometry.preview(Vector2i(200, 200))
    geometry.tick()
    assert_true(geometry.commit(), "The move is written down")
    var landed: SaChunk = layer.chunks.get(Vector2i(1, 1), null)
    assert_not_null(landed, "The landing allocated the chunk it fell into")
    if landed == null:
        return
    assert_almost_eq(_texel(landed.albedo(), Vector2i(94, 94)).a, 1.0, 0.0001, "whose paint is the moved picture")
    assert_almost_eq(_mask_at(layer, Vector2i(1, 1), Vector2i(94, 94)), 0.0, 0.0001, "under the hidden mask it carried")
    assert_almost_eq(_mask_at(layer, Vector2i(1, 1), Vector2i(10, 10)), 1.0, 0.0001, "and shows where nothing landed")
    assert_almost_eq(
        _mask_at(layer, Vector2i(0, 0), Vector2i(150, 150)), layer.mask.rest, 0.0001, "The hole it left reads the rest"
    )
    assert_almost_eq(
        _mask_at(layer, Vector2i(0, 0), Vector2i(50, 50)), 0.0, 0.0001, "and outside the selection as the painter made it"
    )
