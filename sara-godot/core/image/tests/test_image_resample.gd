## Image > Image Size: scaling the whole document, as numbers.
##
## Everything here is something a screenshot cannot say. A doubled picture looks
## like the picture, so what is asserted is the chunk count the new size needs,
## the tile that stays unallocated because nothing maps into it, the undo that
## brings the size and the picture back together, and the out-of-range value that
## survives the filter, which is hard rule 5.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const RED := Color(1.0, 0.0, 0.0, 1.0)
## Well outside 0 to 1 in every channel.
const BRIGHT := Color(3.5, 2.25, -0.5, 1.0)

var _easel: SaEasel = null
var _doc: SaDocument = null


func before_each() -> void:
    _easel = SaEasel.create_default(Vector2i(512, 512))
    _doc = _easel.document


func after_each() -> void:
    _easel.free()
    _easel = null
    _doc = null


func _texel(texture: SaTexture, x: int, y: int) -> Color:
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return SaFieldSpec.decode_texel(bytes, texture.format, y * texture.size.x + x)


func _layer_texel(layer: SaLayer, x: int, y: int) -> Color:
    var grid := Vector2i(floori(float(x) / SaChunk.SIZE), floori(float(y) / SaChunk.SIZE))
    var texture := layer.get_field(grid)
    if texture == null:
        return Color.TRANSPARENT
    return _texel(texture, x - grid.x * SaChunk.SIZE, y - grid.y * SaChunk.SIZE)


## Paint over the whole 512 canvas, which is four chunks.
func _paint_everything(colour: Color = RED) -> void:
    _doc.active_layer.fill(colour)


# --- The aspect lock, which is arithmetic and needs no GPU ----------------------


func test_the_lock_fills_the_other_number_in() -> void:
    var from := Vector2i(1920, 1080)

    assert_eq(SaResample.locked_height(from, 3840), 2160, "Double the width and the height doubles")
    assert_eq(SaResample.locked_width(from, 2160), 3840, "and it reads the same way round")
    assert_eq(SaResample.locked_height(from, 960), 540, "Half the width and the height halves")


func test_the_lock_rounds_rather_than_truncating() -> void:
    var from := Vector2i(1000, 3)

    # 7 * 3 / 1000 is 0.021, which truncates to zero and is not a canvas.
    assert_eq(SaResample.locked_height(from, 7), 1, "A height that rounds below one is one, not zero")
    assert_eq(SaResample.locked_height(Vector2i(3, 2), 10), 7, "and 10 * 2 / 3 rounds to 7 rather than down to 6")


func test_a_degenerate_source_does_not_divide_by_nothing() -> void:
    assert_eq(SaResample.locked_height(Vector2i(0, 8), 100), 8, "A zero width has no ratio, so the height stands")
    assert_eq(SaResample.locked_width(Vector2i(8, 0), 100), 8, "and the same the other way round")


# --- The pass ------------------------------------------------------------------


func test_a_size_that_changes_nothing_records_no_step() -> void:
    _paint_everything()
    var before := _doc.history.step_count()

    assert_false(SaResample.new(_doc).resample_to(Vector2i(512, 512)), "The size it already is is not a resample")
    assert_eq(_doc.history.step_count(), before, "and nothing went on the undo stack")


func test_a_size_that_is_not_a_canvas_is_refused() -> void:
    _paint_everything()

    assert_false(SaResample.new(_doc).resample_to(Vector2i(0, 512)), "Zero wide is not a canvas")
    assert_false(SaResample.new(_doc).resample_to(Vector2i(512, -8)), "and neither is negative")
    assert_false(SaResample.new(_doc).resample_to(Vector2i(99999, 512)), "and neither is past the ceiling")
    assert_eq(_doc.canvas_size, Vector2i(512, 512), "The document is where it was after all three")


func test_doubling_gives_the_chunk_count_the_new_size_needs() -> void:
    _paint_everything()
    assert_eq(_doc.active_layer.chunks.size(), 4, "512 square is four chunks to start with")

    assert_true(SaResample.new(_doc).resample_to(Vector2i(1024, 1024)), "The pass ran")

    assert_eq(_doc.canvas_size, Vector2i(1024, 1024), "The document is the size that was asked for")
    assert_eq(_doc.active_layer.chunks.size(), 16, "and 1024 square is sixteen chunks, not the four it had")


func test_halving_gives_back_the_chunks_the_smaller_size_does_not_need() -> void:
    _paint_everything()

    assert_true(SaResample.new(_doc).resample_to(Vector2i(256, 256)), "The pass ran")

    assert_eq(_doc.canvas_size, Vector2i(256, 256), "The document halved")
    assert_eq(_doc.active_layer.chunks.size(), 1, "and one chunk holds the whole of it now")


func test_a_region_nothing_maps_into_stays_unallocated() -> void:
    # One chunk of paint in the top left of a canvas four chunks across, so the
    # grown canvas has tiles no source texel can reach. Filled through the chunk
    # rather than through `SaLayer.fill`, which takes the whole grid first
    # because a fill lands everywhere.
    var chunk := _doc.active_layer.get_or_create_chunk(Vector2i.ZERO)
    chunk.clear(RED)
    assert_eq(_doc.active_layer.chunks.size(), 1, "One painted tile to start with")

    assert_true(SaResample.new(_doc).resample_to(Vector2i(1024, 1024)), "The pass ran")

    # The one tile doubles to 512 by 512, which is four tiles of the new grid.
    assert_eq(_doc.active_layer.chunks.size(), 4, "The doubled picture covers four tiles and allocates four")
    assert_false(_doc.active_layer.chunks.has(Vector2i(3, 3)), "The far corner nothing reaches holds no chunk")


func test_the_picture_survives_a_double_and_a_half_back() -> void:
    _paint_everything()

    assert_true(SaResample.new(_doc).resample_to(Vector2i(1024, 1024)), "Doubled")
    assert_true(_layer_texel(_doc.active_layer, 700, 700).is_equal_approx(RED), "The middle of the doubled canvas is red")

    assert_true(SaResample.new(_doc).resample_to(Vector2i(512, 512)), "and halved back")
    assert_eq(_doc.canvas_size, Vector2i(512, 512), "The document is where it started")
    assert_true(_layer_texel(_doc.active_layer, 300, 300).is_equal_approx(RED), "and the picture is still red")


func test_an_out_of_range_value_survives_the_filter() -> void:
    _paint_everything(BRIGHT)

    assert_true(SaResample.new(_doc).resample_to(Vector2i(1024, 1024)), "The pass ran")

    var read := _layer_texel(_doc.active_layer, 500, 500)
    assert_almost_eq(read.r, BRIGHT.r, 0.02, "3.5 is not clamped to 1.0 by the resample")
    assert_almost_eq(read.b, BRIGHT.b, 0.02, "and neither is a negative blue")


func test_nearest_and_bilinear_are_both_reachable() -> void:
    _paint_everything()
    var pass_over := SaResample.new(_doc)
    pass_over.filter = SaResampleKernel.Filter.NEAREST

    assert_true(pass_over.resample_to(Vector2i(1024, 1024)), "The pass ran with nearest chosen")

    assert_true(
        _layer_texel(_doc.active_layer, 600, 600).is_equal_approx(RED),
        "and a solid picture reads the same whichever filter took it"
    )


func test_undo_brings_the_size_and_the_picture_back_together() -> void:
    _paint_everything()
    var steps := _doc.history.step_count()

    assert_true(SaResample.new(_doc).resample_to(Vector2i(1024, 1024)), "The pass ran")
    assert_eq(_doc.history.step_count(), steps + 1, "as one step and not two")

    assert_true(_doc.undo(), "Undo ran")

    assert_eq(_doc.canvas_size, Vector2i(512, 512), "Undo put the size back")
    assert_eq(_doc.active_layer.chunks.size(), 4, "and the four chunks the old size needed")
    assert_true(_layer_texel(_doc.active_layer, 300, 300).is_equal_approx(RED), "and the picture with them")

    assert_true(_doc.redo(), "Redo ran")

    assert_eq(_doc.canvas_size, Vector2i(1024, 1024), "Redo is the same exchange the other way")
    assert_eq(_doc.active_layer.chunks.size(), 16, "with the chunk count that goes with it")


func test_the_undo_step_is_named_for_what_it_did() -> void:
    _paint_everything()

    assert_true(SaResample.new(_doc).resample_to(Vector2i(1024, 1024)), "The pass ran")

    assert_eq(SaResample.ACTION_NAME, "Image Size", "The undo menu says Image Size")
    assert_true(SaResample.ACTION_NAME != SaCrop.RESIZE_ACTION_NAME, "which is not what Canvas Size leaves behind")


func test_the_selection_is_dropped_rather_than_left_pointing_wrong() -> void:
    _paint_everything()
    _doc.selection.select_rect(Rect2i(64, 64, 128, 128))
    assert_true(_doc.selection.active, "There is a selection before the pass")

    assert_true(SaResample.new(_doc).resample_to(Vector2i(1024, 1024)), "The pass ran")

    assert_false(_doc.selection.active, "and it is gone rather than pointing at a quarter of what it meant")


func test_every_layer_is_scaled_and_not_only_the_active_one() -> void:
    _paint_everything()
    var second := SaLayerOps.new(_doc).add()
    second.fill(RED)
    assert_eq(second.chunks.size(), 4, "The second layer is painted too")

    assert_true(SaResample.new(_doc).resample_to(Vector2i(1024, 1024)), "The pass ran")

    assert_eq(second.chunks.size(), 16, "and the layer nobody was standing on grew with the document")
    assert_true(_layer_texel(second, 700, 700).is_equal_approx(RED), "with its picture on it")
