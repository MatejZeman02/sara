## A group's or a record's mask made from a selection, a colour range or an
## invert holds chunks only where its source does.
##
## The three once walked every grid position of the canvas for an owner
## with no chunks of its own, so a group masked from a selection the size of a
## face on a 4096 by 4096 canvas held 256 mask chunks, all but one of them
## zeros. A mask now carries the value a position with no chunk reads, its
## rest, and the composite binds a 1 by 1 texture of it there.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true

const RED := Color(1.0, 0.0, 0.0, 1.0)

## The first chunk, which the selection covers, and a texel in it and outside.
const FIRST_CHUNK := Rect2i(0, 0, 256, 256)
const INSIDE := Vector2i(100, 100)
const OUTSIDE := Vector2i(400, 300)


func _texel(texture: SaTexture, at: Vector2i) -> Color:
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return SaFieldSpec.decode_texel(bytes, texture.format, at.y * texture.size.x + at.x)


func _composite(easel: SaEasel) -> void:
    easel.document.update_caches()
    easel.request_full_composite()
    easel.process_pending_composite()


func _is_red(colour: Color) -> bool:
    return colour.r > 0.9 and colour.g < 0.1 and colour.b < 0.1 and colour.a > 0.9


## A red layer wrapped in a group of its own, on *easel*'s document.
func _red_group(easel: SaEasel) -> SaLayer:
    var doc := easel.document
    doc.active_layer.fill(RED)
    var group := SaLayerOps.new(doc).group_active()
    doc.undo_redo.clear_history()
    return group


func test_a_groups_mask_from_a_one_chunk_selection_holds_one_chunk_on_a_large_canvas() -> void:
    var easel := SaEasel.create_default(Vector2i(4096, 4096))
    var doc := easel.document
    var group := SaLayerOps.new(doc).group_active()
    doc.selection.select_rect(FIRST_CHUNK)
    var ops := SaMaskOps.new(doc)
    assert_true(ops.add_from_selection(group), "The group is masked from the selection")
    assert_eq(group.mask.grid_positions().size(), 1, "The mask holds the one chunk the selection holds, of 256")
    assert_almost_eq(group.mask.rest, 0.0, 0.0001, "and reads zero everywhere else")
    assert_true(ops.invert(group), "The invert runs")
    assert_eq(group.mask.grid_positions().size(), 1, "and still holds one chunk")
    assert_almost_eq(group.mask.rest, 1.0, 0.0001, "reading one everywhere else")
    doc.undo_redo.undo()
    assert_eq(group.mask.grid_positions().size(), 1, "The undo of the invert holds one chunk")
    assert_almost_eq(group.mask.rest, 0.0, 0.0001, "and gives the rest of zero back")
    easel.free()


func test_the_composite_reads_the_rest_before_and_after_the_invert() -> void:
    var easel := SaEasel.create_default(Vector2i(512, 512))
    var doc := easel.document
    var group := _red_group(easel)
    doc.selection.select_rect(FIRST_CHUNK)
    var ops := SaMaskOps.new(doc)
    assert_true(ops.add_from_selection(group), "The group is masked from the first chunk")
    doc.selection.deselect()
    _composite(easel)
    assert_true(_is_red(_texel(easel.output, INSIDE)), "The group shows inside the selection")
    assert_false(_is_red(_texel(easel.output, OUTSIDE)), "and is hidden outside it, where the mask holds no chunk")

    assert_true(ops.invert(group), "The invert runs")
    _composite(easel)
    assert_false(_is_red(_texel(easel.output, INSIDE)), "Inverted, the group is hidden inside")
    assert_true(_is_red(_texel(easel.output, OUTSIDE)), "and shown outside")

    group.mask.enabled = false
    _composite(easel)
    assert_true(_is_red(_texel(easel.output, INSIDE)), "A mask switched off hides nothing, its rest included")
    easel.free()


func test_a_colour_range_mask_holds_the_chunks_its_coverage_names() -> void:
    var easel := SaEasel.create_default(Vector2i(512, 512))
    var doc := easel.document
    var group := _red_group(easel)
    var ops := SaMaskOps.new(doc)
    assert_true(ops.add(group), "A plain mask first")
    group.mask.get_or_create(Vector2i(1, 1))
    var coverage: Dictionary[Vector2i, SaChunk] = {Vector2i(0, 0): doc.selection.make_chunk(1.0)}
    assert_true(ops.from_color_range(group, coverage), "The colour range replaces it")
    assert_eq(group.mask.grid_positions(), [Vector2i(0, 0)] as Array[Vector2i], "holding the one chunk the coverage names")
    assert_almost_eq(group.mask.rest, 0.0, 0.0001, "and hiding the rest by its rest")
    _composite(easel)
    assert_true(_is_red(_texel(easel.output, INSIDE)), "The group shows where the range chose")
    assert_false(_is_red(_texel(easel.output, OUTSIDE)), "and nowhere else")
    doc.undo_redo.undo()
    assert_eq(group.mask.grid_positions().size(), 1, "The undo gives back the chunk the mask held")
    assert_almost_eq(group.mask.rest, 1.0, 0.0001, "and the rest of one")
    easel.free()


func test_a_new_chunk_opens_at_the_rest() -> void:
    var mask := SaMask.own()
    mask.rest = 0.0
    var texture := mask.get_or_create(Vector2i(2, 3))
    assert_almost_eq(_texel(texture, Vector2i(5, 5)).r, 0.0, 0.0001, "A chunk a brush allocates reads what the position read")
    assert_almost_eq(_texel(mask.absent(), Vector2i.ZERO).r, 0.0, 0.0001, "and so does the stand-in")
    mask.rest = 1.0
    assert_almost_eq(_texel(mask.absent(), Vector2i.ZERO).r, 1.0, 0.0001, "which follows the rest when it moves")
    assert_null(mask.coverage(Vector2i(0, 0)), "A position that reads one is skipped")


func test_the_rest_goes_to_disk_and_back() -> void:
    var mask := SaMask.own()
    mask.rest = 0.0
    mask.get_or_create(Vector2i(0, 0))
    var blobs := PackedByteArray()
    var entry := SaSadFile.write_mask(mask, blobs, GlobalShaderCompiler.get_rd())
    assert_almost_eq(float(entry.get("rest", -1.0)), 0.0, 0.0001, "The entry carries the rest")
    var back := SaSadFile.read_mask(entry, blobs)
    assert_almost_eq(back.rest, 0.0, 0.0001, "and the reader gives it back")
    assert_eq(back.grid_positions().size(), 1, "with the one chunk")
    var plain := SaSadFile.write_mask(SaMask.own(), PackedByteArray(), GlobalShaderCompiler.get_rd())
    assert_false(plain.has("rest"), "A mask resting at one writes no key, as before")
