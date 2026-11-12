## Crop and Image Size carry a group's mask and an attached filter's with the
## picture, and their undo puts them back.
##
## Both walked the chunks of paint layers only, where a layer's own
## mask is a field of its chunks. A mask that holds chunks of its own, a
## group's or a filter record's, stayed at its old grid positions and unscaled,
## hiding a part of the picture it was never drawn over.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true

## The selection the masks are made from, in the third chunk of the diagonal.
const PATCH := Rect2i(600, 600, 100, 100)
## The crop, whose origin moves the patch to (88, 88).
const CROP := Rect2i(512, 512, 512, 512)


## What *mask* reads at document pixel *at*: the texel it holds there, or its
## rest where it holds no chunk.
func _reads(mask: SaMask, at: Vector2i) -> float:
    var edge := SaLayer.CHUNK_SIZE
    var grid_pos := Vector2i(floori(float(at.x) / edge), floori(float(at.y) / edge))
    var texture := mask.texture_for(grid_pos)
    if texture == null:
        return mask.rest
    var local := at - grid_pos * edge
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return SaFieldSpec.decode_texel(bytes, texture.format, local.y * texture.size.x + local.x).r


## A 1024 square easel with a group masked from `PATCH` and a paint layer
## whose attached invert is masked from it too, answered as [group, record].
func _masked(easel: SaEasel) -> Array:
    var doc := easel.document
    var layers := SaLayerOps.new(doc)
    doc.active_layer.fill(Color(1, 0, 0, 1))
    var group := layers.group_active()
    var painted := layers.add()
    doc.fill_layer(Color(0, 0, 1, 1), painted)
    var record := SaFilterOps.new(doc).attach(painted, Bench.INVERT)
    var masks := SaMaskOps.new(doc)
    doc.selection.select_rect(PATCH)
    assert_true(masks.add_from_selection(group), "The group is masked from the patch")
    assert_true(masks.add_from_selection(record), "and so is the filter")
    doc.selection.deselect()
    doc.undo_redo.clear_history()
    return [group, record]


func _patch_at(mask: SaMask, inside: Vector2i, outside: Vector2i, what: String) -> void:
    assert_almost_eq(_reads(mask, inside), 1.0, 0.01, "%s shows at %s" % [what, inside])
    assert_almost_eq(_reads(mask, outside), 0.0, 0.01, "%s hides at %s" % [what, outside])


func test_a_crop_moves_the_group_mask_and_the_filter_mask_and_undo_moves_them_back() -> void:
    var easel: SaEasel = Bench.easel(Vector2i(1024, 1024))
    var doc := easel.document
    var owners := _masked(easel)
    var group: SaLayer = owners[0]
    var record: SaAttachedFilter = owners[1]
    var revision := record.revision
    assert_true(SaCrop.new(doc).crop_to(CROP), "The crop runs")
    for mask: SaMask in [group.mask, record.mask]:
        _patch_at(mask, Vector2i(100, 100), Vector2i(50, 50), "Cropped, the mask")
        _patch_at(mask, Vector2i(180, 180), Vector2i(200, 200), "and its far corner")
    assert_true(record.revision > revision, "The record is told its mask moved")

    doc.undo_redo.undo()
    assert_eq(doc.canvas_size, Vector2i(1024, 1024), "The undo gives the size back")
    for mask: SaMask in [group.mask, record.mask]:
        _patch_at(mask, Vector2i(650, 650), Vector2i(550, 550), "Undone, the mask")
        _patch_at(mask, Vector2i(650, 650), Vector2i(100, 100), "and the new top left")

    doc.undo_redo.redo()
    for mask: SaMask in [group.mask, record.mask]:
        _patch_at(mask, Vector2i(100, 100), Vector2i(50, 50), "Redone, the mask")
    easel.free()


func test_a_resample_scales_both_masks_and_undo_puts_them_back() -> void:
    var easel: SaEasel = Bench.easel(Vector2i(1024, 1024))
    var doc := easel.document
    var owners := _masked(easel)
    var group: SaLayer = owners[0]
    var record: SaAttachedFilter = owners[1]
    assert_true(SaResample.new(doc).resample_to(Vector2i(512, 512)), "The resample runs")
    for mask: SaMask in [group.mask, record.mask]:
        _patch_at(mask, Vector2i(325, 325), Vector2i(290, 290), "Halved, the mask")
        _patch_at(mask, Vector2i(340, 340), Vector2i(100, 100), "and away from it")
        assert_almost_eq(_reads(mask, Vector2i(360, 360)), 0.0, 0.01, "Past the halved patch it hides")

    doc.undo_redo.undo()
    assert_eq(doc.canvas_size, Vector2i(1024, 1024), "The undo gives the size back")
    for mask: SaMask in [group.mask, record.mask]:
        _patch_at(mask, Vector2i(650, 650), Vector2i(550, 550), "Undone, the mask")
        _patch_at(mask, Vector2i(690, 690), Vector2i(325, 325), "and where the halved one was")
    easel.free()


func test_a_grow_keeps_the_mask_where_the_picture_went_and_the_margin_at_rest() -> void:
    var easel: SaEasel = Bench.easel(Vector2i(1024, 1024))
    var doc := easel.document
    var group: SaLayer = _masked(easel)[0]
    assert_true(SaCrop.new(doc).resize_to(Vector2i(1280, 1280), Vector2i(2, 2)), "The canvas grows up and left")
    _patch_at(group.mask, Vector2i(900, 900), Vector2i(800, 800), "Grown, the mask")
    assert_almost_eq(_reads(group.mask, Vector2i(10, 10)), 0.0, 0.01, "and the margin reads its rest")
    easel.free()
