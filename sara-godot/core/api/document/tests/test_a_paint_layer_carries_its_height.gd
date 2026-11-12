## A paint layer can carry its height.
##
## Height is a lazy `R16F` field: a layer gains it as one history step, a chunk
## gains a texture of it only where height is written, and every door a chunk
## goes through, undo, the `.sad`, duplicate, Merge Down, flatten and crop,
## carries what it holds, and a merge adds the heights rather than mixing
## them. Every texel is read back, because a height that came back zero looks
## like a height nobody painted rather than like a fault.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

const RED := Color(1.0, 0.0, 0.0, 1.0)

## Three texels of a chunk and the height written there, in millimetres. Each
## is exact in a half float, so a read that differs is a fault and not rounding.
const RIDGE: Dictionary = {
    Vector2i(3, 5): 0.5,
    Vector2i(128, 128): 2.25,
    Vector2i(255, 255): 9.75,
}

var _registries: SaRegistries = null
var _easel: SaEasel = null
var _doc: SaDocument = null


func before_each() -> void:
    _registries = Fixtures.make_registries()
    _easel = SaEasel.create_default(Vector2i(768, 768))
    _easel.compositor.set_registry(_registries.blend_modes)
    _doc = _easel.document


func after_each() -> void:
    _easel.free()
    _easel = null
    _doc = null
    _registries = null


func _texel(texture: SaTexture, at: Vector2i) -> Color:
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return SaFieldSpec.decode_texel(bytes, texture.format, at.y * texture.size.x + at.x)


## Writes RIDGE into a height texture, and *rest* everywhere else.
func _raise(texture: SaTexture, rest: float = 0.0) -> void:
    var bytes := PackedByteArray()
    bytes.resize(texture.size.x * texture.size.y * 2)
    for i in texture.size.x * texture.size.y:
        bytes.encode_half(i * 2, rest)
    for at: Vector2i in RIDGE:
        bytes.encode_half((at.y * texture.size.x + at.x) * 2, RIDGE[at])
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, bytes)


## Paints *color* over the left *columns* texels of a colour texture, and no
## paint over the rest, at whatever depth the document stores colour.
func _paint(texture: SaTexture, color: Color, columns: int = SaChunk.SIZE) -> void:
    var width: int = SaFieldSpec.BYTES_PER_TEXEL[texture.format]
    var half := width == 8
    var bytes := PackedByteArray()
    bytes.resize(texture.size.x * texture.size.y * width)
    for y in texture.size.y:
        for x in mini(columns, texture.size.x):
            var base := (y * texture.size.x + x) * width
            for c in 4:
                if half:
                    bytes.encode_half(base + c * 2, color[c])
                else:
                    bytes.encode_float(base + c * 4, color[c])
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, bytes)


func _assert_ridge(texture: SaTexture, what: String) -> void:
    assert_not_null(texture, "%s holds a height" % what)
    if texture == null:
        return
    for at: Vector2i in RIDGE:
        assert_almost_eq(_texel(texture, at).r, float(RIDGE[at]), 0.0001, "%s keeps the height at %s" % [what, at])


## The grid positions of *layer* whose chunk holds a height texture.
func _heights(layer: SaLayer) -> Array[Vector2i]:
    var found: Array[Vector2i] = []
    for grid_pos: Vector2i in layer.chunks:
        if layer.chunks[grid_pos].has_field(SaFieldSpec.HEIGHT):
            found.append(grid_pos)
    found.sort()
    return found


func _version_of(path: String) -> int:
    var file := FileAccess.open(path, FileAccess.READ)
    file.get_buffer(4)
    var version := file.get_32()
    file.close()
    return version


func test_the_height_spec_is_a_half_float_that_is_never_colour_and_waits_for_a_write() -> void:
    var spec := SaFieldSpec.height()
    assert_eq(spec.id, SaFieldSpec.HEIGHT, "The field is called height")
    assert_eq(spec.format, RenderingDevice.DATA_FORMAT_R16_SFLOAT, "stored as one half float a texel, ruling 2")
    assert_eq(spec.bytes_per_texel(), 2, "which is two bytes")
    assert_false(spec.is_color, "Height is a thickness, never colour")
    assert_true(spec.lazy, "and a chunk holds it only once it is written")
    assert_eq(spec.blank, Color(0, 0, 0, 0), "where it reads zero, bare")


func test_gaining_height_is_a_step_that_undo_takes_back_whole() -> void:
    var layer := _doc.active_layer
    layer.get_or_create_chunk(Vector2i(0, 0))
    var steps := _doc.history.step_count()
    var height := SaHeightOps.new(_doc)
    assert_false(layer.carries_height(), "A paint layer starts with no height")
    assert_true(height.gain(layer), "The first height-writing dab gains it one")
    assert_true(layer.carries_height(), "and the layer carries it")
    assert_eq(_doc.history.step_count(), steps + 1, "as one step of the history")
    assert_false(height.gain(layer), "Asking again is nothing, so an engine asks before every stroke")
    assert_eq(_doc.history.step_count(), steps + 1, "and commits no second step")
    assert_eq(_heights(layer), [] as Array[Vector2i], "Gaining allocates nothing, not even where the layer has paint")

    layer.get_or_create_field(Vector2i(0, 0), SaFieldSpec.HEIGHT)
    assert_true(_doc.undo(), "Undo takes the step back")
    assert_false(layer.carries_height(), "and the layer carries no height")
    assert_eq(_heights(layer), [] as Array[Vector2i], "nor a texture of it anywhere")
    assert_true(_doc.redo(), "Redo gives it again")
    assert_true(layer.carries_height(), "and the layer carries it once more")
    assert_false(SaHeightOps.can_gain(null), "Nothing gains nothing")


func test_a_group_takes_no_height() -> void:
    var group := SaLayer.new()
    group.is_group = true
    assert_false(SaHeightOps.can_gain(group), "A group stores no paint to thicken")
    group.free()


func test_height_is_allocated_only_in_the_chunks_it_is_written_into() -> void:
    var layer := _doc.active_layer
    for grid_pos: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 2)]:
        _paint(layer.get_or_create_field(grid_pos), RED)
    SaHeightOps.new(_doc).gain(layer)
    var fresh := layer.get_or_create_chunk(Vector2i(0, 2))
    assert_false(fresh.has_field(SaFieldSpec.HEIGHT), "A chunk the brush allocates after the gain holds no height yet")

    var first := layer.get_or_create_field(Vector2i(1, 0), SaFieldSpec.HEIGHT)
    var second := layer.get_or_create_field(Vector2i(2, 1), SaFieldSpec.HEIGHT)
    assert_eq(first.format, RenderingDevice.DATA_FORMAT_R16_SFLOAT, "A height texture is a half float")
    assert_almost_eq(_texel(second, Vector2i(200, 17)).r, 0.0, 0.0, "and opens at zero, bare")
    _raise(first)
    _raise(second)
    var two: Array[Vector2i] = [Vector2i(1, 0), Vector2i(2, 1)]
    assert_eq(_heights(layer), two, "Height paints into two chunks and lives in those two")
    assert_eq(layer.get_or_create_field(Vector2i(1, 0), SaFieldSpec.HEIGHT), first, "and a second write finds the same texture")
    assert_null(layer.get_field(Vector2i(0, 0), SaFieldSpec.HEIGHT), "A chunk no height reached reads none")


func test_a_layer_with_no_height_field_gains_no_texture_of_it() -> void:
    var layer := _doc.active_layer
    var none := layer.get_or_create_field(Vector2i(0, 0), SaFieldSpec.HEIGHT)
    assert_null(none, "A field the schema does not list is not allocated")
    assert_false(layer.chunks[Vector2i(0, 0)].has_field(SaFieldSpec.HEIGHT), "and the chunk stays as it was")


func test_a_fill_of_colour_leaves_the_height_standing() -> void:
    var layer := _doc.active_layer
    SaHeightOps.new(_doc).gain(layer)
    _raise(layer.get_or_create_field(Vector2i(0, 0), SaFieldSpec.HEIGHT))
    layer.fill(RED)
    _assert_ridge(layer.get_field(Vector2i(0, 0), SaFieldSpec.HEIGHT), "A filled layer")
    assert_eq(_heights(layer), [Vector2i(0, 0)] as Array[Vector2i], "and the fill allocated no height where it reached")


func test_a_ground_colour_does_not_write_a_thickness() -> void:
    var chunk := SaChunk.new()
    var texture := chunk.add_sparse_field(SaFieldSpec.height())
    _raise(texture)
    chunk.clear(Color(1, 1, 1, 1))
    var ground := _texel(texture, Vector2i(128, 128)).r
    assert_almost_eq(ground, 0.0, 0.0, "A white ground clears a height to zero, not to a millimetre")


func test_a_stroke_that_laid_a_chunks_first_height_is_undone_whole() -> void:
    var layer := _doc.active_layer
    SaHeightOps.new(_doc).gain(layer)
    _paint(layer.get_or_create_field(Vector2i(0, 0)), RED)
    var region := Rect2i(0, 0, 256, 256)
    var state := {Vector2i(0, 0): SaChunkDelta.capture(layer.chunks[Vector2i(0, 0)], region)}
    _raise(layer.get_or_create_field(Vector2i(0, 0), SaFieldSpec.HEIGHT))

    _doc.swap_pixels(layer, state)
    assert_eq(_heights(layer), [] as Array[Vector2i], "Undo takes off the height the stroke brought")
    assert_not_null(layer.get_field(Vector2i(0, 0)), "and leaves the paint")
    _doc.swap_pixels(layer, state)
    _assert_ridge(layer.get_field(Vector2i(0, 0), SaFieldSpec.HEIGHT), "A redone stroke")


func test_a_grown_snapshot_keeps_the_absence_it_began_with() -> void:
    var layer := _doc.active_layer
    SaHeightOps.new(_doc).gain(layer)
    var chunk := layer.get_or_create_chunk(Vector2i(0, 0))
    var early := SaChunkDelta.capture(chunk, Rect2i(0, 0, 64, 64))
    _raise(layer.get_or_create_field(Vector2i(0, 0), SaFieldSpec.HEIGHT))
    var grown := early.grown_to(chunk, Rect2i(0, 0, 256, 256))
    assert_false(grown.fields.has(SaFieldSpec.HEIGHT), "A stroke that grew past its first rectangle still began with no height")
    grown.apply_to(chunk)
    assert_false(chunk.has_field(SaFieldSpec.HEIGHT), "so its undo leaves none")


func test_the_history_pays_two_bytes_a_texel_of_height_and_no_more() -> void:
    var layer := _doc.active_layer
    _paint(layer.get_or_create_field(Vector2i(0, 0)), RED)
    var flat := {Vector2i(0, 0): layer.duplicate_chunk(Vector2i(0, 0))}
    var region := Rect2i(10, 20, 30, 40)
    var flat_part := {Vector2i(0, 0): SaChunkDelta.capture(layer.chunks[Vector2i(0, 0)], region)}
    SaHeightOps.new(_doc).gain(layer)
    layer.get_or_create_field(Vector2i(0, 0), SaFieldSpec.HEIGHT)
    var thick := {Vector2i(0, 0): layer.duplicate_chunk(Vector2i(0, 0))}
    var thick_part := {Vector2i(0, 0): SaChunkDelta.capture(layer.chunks[Vector2i(0, 0)], region)}

    var texels := SaChunk.SIZE * SaChunk.SIZE
    var whole := SaHistory.bytes_of(thick) - SaHistory.bytes_of(flat)
    assert_eq(whole, texels * 2, "A whole chunk with height costs two bytes a texel more")
    var part := SaHistory.bytes_of(thick_part) - SaHistory.bytes_of(flat_part)
    assert_eq(part, 30 * 40 * 2, "and a stroke's part of one two a texel of its part")

    var before := _doc.history.total_bytes()
    _doc.history.commit("Thick", func() -> void: pass, thick)
    var grew := _doc.history.total_bytes() - before
    assert_eq(grew, SaHistory.bytes_of(flat) + texels * 2, "The count grows by the colour and the height")


func test_the_memory_of_a_painted_chunk_with_and_without_height() -> void:
    var layer := _doc.active_layer
    var chunk := layer.get_or_create_chunk(Vector2i(0, 0))
    var colour := chunk.byte_size()
    SaHeightOps.new(_doc).gain(layer)
    layer.get_or_create_field(Vector2i(0, 0), SaFieldSpec.HEIGHT)
    var texels := SaChunk.SIZE * SaChunk.SIZE
    assert_eq(chunk.byte_size() - colour, texels * 2, "Height adds 128 KiB to a painted chunk")
    var depth: int = SaFieldSpec.BYTES_PER_TEXEL[_doc.color_space.texel_format()]
    assert_eq(colour, texels * depth, "on top of the colour at the document's depth")
    print("Height memory: a painted chunk holds %d bytes of colour and %d with height" % [colour, chunk.byte_size()])


func test_a_saved_height_reads_back_equal_and_the_file_says_six() -> void:
    var layer := _doc.active_layer
    var name_was := str(layer.name)
    _paint(layer.get_or_create_field(Vector2i(0, 0)), RED)
    SaHeightOps.new(_doc).gain(layer)
    _raise(layer.get_or_create_field(Vector2i(1, 0), SaFieldSpec.HEIGHT))
    _raise(layer.get_or_create_field(Vector2i(2, 2), SaFieldSpec.HEIGHT), 1.5)

    var path := SaDataRoot.path("test_h1_height.sad")
    assert_eq(SaSadFile.version_for(_doc), 6, "A document carrying height is version 6")
    assert_eq(SaExport.save_sad(_doc, path, 0), OK, "and saves")
    assert_eq(
        _version_of(path),
        SaSadFile.SAD_VERSION_PLANES,
        "and its header says 14, since it holds planes a build that reads 5 refuses"
    )

    var loaded := SaDocument.new()
    assert_eq(SaExport.load_sad(loaded, path, SaCompositor.new()), OK, "It loads")
    var back: SaLayer = loaded.get_node_or_null(name_was)
    assert_not_null(back, "The layer is back")
    if back != null:
        assert_true(back.carries_height(), "carrying its height")
        var spec: SaFieldSpec = SaHeightOps.spec_among([back] as Array[SaLayer])
        assert_true(spec.lazy, "still lazy")
        assert_eq(spec.format, RenderingDevice.DATA_FORMAT_R16_SFLOAT, "and a half float")
        assert_eq(_heights(back), [Vector2i(1, 0), Vector2i(2, 2)] as Array[Vector2i], "in the two chunks it was written into")
        _assert_ridge(back.get_field(Vector2i(1, 0), SaFieldSpec.HEIGHT), "A loaded height")
        var rest := _texel(back.get_field(Vector2i(2, 2), SaFieldSpec.HEIGHT), Vector2i(40, 40))
        assert_almost_eq(rest.r, 1.5, 0.0, "every texel of it")
        assert_true(back.chunks.has(Vector2i(0, 0)), "The chunk of paint with no height is back")
        assert_false(back.chunks[Vector2i(0, 0)].has_field(SaFieldSpec.HEIGHT), "still with none")
    DirAccess.remove_absolute(path)
    loaded.free()


func test_a_document_without_height_keeps_its_version() -> void:
    _doc.active_layer.fill(RED)
    assert_eq(SaSadFile.version_for(_doc), 4, "A plain document is still version 4")
    _doc.active_layer.add_mask()
    assert_eq(SaSadFile.version_for(_doc), 5, "and a masked one still 5")


func test_duplicate_carries_the_height() -> void:
    var layer := _doc.active_layer
    SaHeightOps.new(_doc).gain(layer)
    _paint(layer.get_or_create_field(Vector2i(0, 0)), RED)
    _paint(layer.get_or_create_field(Vector2i(1, 1)), RED)
    _raise(layer.get_or_create_field(Vector2i(1, 1), SaFieldSpec.HEIGHT))
    var copy := SaLayerOps.new(_doc).duplicate(layer)
    assert_true(copy.carries_height(), "The copy carries height")
    assert_eq(_heights(copy), [Vector2i(1, 1)] as Array[Vector2i], "in the chunk its source held it")
    _assert_ridge(copy.get_field(Vector2i(1, 1), SaFieldSpec.HEIGHT), "A duplicated layer")
    assert_true(
        copy.get_field(Vector2i(1, 1), SaFieldSpec.HEIGHT) != layer.get_field(Vector2i(1, 1), SaFieldSpec.HEIGHT),
        "in a texture of its own"
    )


func _two_layers() -> Array[SaLayer]:
    var lower := _doc.active_layer
    var upper := SaLayerOps.new(_doc).add()
    return [lower, upper]


## A merge adds the upper height to the lower, and a flat layer
## adds nought: the view showed the lower height under the flat paint, so the
## merge leaves it there. The mix it replaced gave zero where the paint lay.
func test_flat_paint_merged_onto_height_leaves_the_height_standing() -> void:
    var pair := _two_layers()
    var lower := pair[0]
    var upper := pair[1]
    SaHeightOps.new(_doc).gain(lower)
    _paint(lower.get_or_create_field(Vector2i(0, 0)), RED)
    _raise(lower.get_or_create_field(Vector2i(0, 0), SaFieldSpec.HEIGHT), 4.0)
    _paint(upper.get_or_create_field(Vector2i(0, 0)), Color(0, 0, 1, 1), 128)

    assert_true(SaLayerOps.new(_doc).merge_down(upper), "The flat layer merges down")
    var merged := lower.get_field(Vector2i(0, 0), SaFieldSpec.HEIGHT)
    assert_almost_eq(_texel(merged, Vector2i(3, 5)).r, 0.5, 0.0001, "Where the flat paint lay the height stands")
    assert_almost_eq(_texel(merged, Vector2i(200, 40)).r, 4.0, 0.0001, "and where it had none the height stands")
    assert_almost_eq(_texel(merged, Vector2i(255, 255)).r, 9.75, 0.0001, "the ridge included")
    assert_true(_doc.undo(), "Undo takes the merge back")
    _assert_ridge(lower.get_field(Vector2i(0, 0), SaFieldSpec.HEIGHT), "An unmerged layer")


func test_height_merged_onto_a_flat_layer_gives_it_the_field() -> void:
    var pair := _two_layers()
    var lower := pair[0]
    var upper := pair[1]
    _paint(lower.get_or_create_field(Vector2i(0, 0)), RED)
    SaHeightOps.new(_doc).gain(upper)
    _paint(upper.get_or_create_field(Vector2i(0, 0)), Color(0, 0, 1, 1))
    _raise(upper.get_or_create_field(Vector2i(0, 0), SaFieldSpec.HEIGHT))
    upper.opacity = 0.5

    assert_true(SaLayerOps.new(_doc).merge_down(upper), "The layer with height merges down")
    assert_true(lower.carries_height(), "The flat layer gains the field")
    var merged := lower.get_field(Vector2i(0, 0), SaFieldSpec.HEIGHT)
    assert_not_null(merged, "and a height where the paint went")
    if merged != null:
        var mixed := _texel(merged, Vector2i(128, 128)).r
        assert_almost_eq(mixed, 2.25 * 0.5, 0.001, "added to the zero below by the layer's opacity")
    assert_true(_doc.undo(), "Undo takes the merge back")
    assert_false(lower.carries_height(), "and the field with it")
    assert_eq(_heights(lower), [] as Array[Vector2i], "and every texture of it")
    assert_true(_doc.redo(), "Redo merges again")
    assert_true(lower.carries_height(), "and the field comes back")


func test_flatten_carries_the_height_of_every_layer_that_draws() -> void:
    var pair := _two_layers()
    var lower := pair[0]
    var upper := pair[1]
    _paint(lower.get_or_create_field(Vector2i(0, 0)), RED)
    SaHeightOps.new(_doc).gain(upper)
    _paint(upper.get_or_create_field(Vector2i(1, 1)), Color(0, 0, 1, 1))
    _raise(upper.get_or_create_field(Vector2i(1, 1), SaFieldSpec.HEIGHT))

    assert_true(SaLayerOps.new(_doc).flatten(), "The stack flattens")
    var bottom := SaLayerOps.new(_doc).layers()[0]
    assert_true(bottom.carries_height(), "The flattened layer carries height")
    assert_eq(_heights(bottom), [Vector2i(1, 1)] as Array[Vector2i], "only where a layer that draws had some")
    _assert_ridge(bottom.get_field(Vector2i(1, 1), SaFieldSpec.HEIGHT), "A flattened layer")
    assert_true(_doc.undo(), "Undo takes the flatten back")
    assert_false(SaLayerOps.new(_doc).layers()[0].carries_height(), "and the bottom layer's field with it")


func test_crop_moves_the_height_with_the_paint() -> void:
    var layer := _doc.active_layer
    SaHeightOps.new(_doc).gain(layer)
    _paint(layer.get_or_create_field(Vector2i(0, 0)), RED)
    _paint(layer.get_or_create_field(Vector2i(1, 1)), RED)
    _raise(layer.get_or_create_field(Vector2i(1, 1), SaFieldSpec.HEIGHT))

    assert_true(SaCrop.new(_doc).crop_to(Rect2i(256, 256, 512, 512)), "The canvas crops to the second chunk's corner")
    assert_eq(_heights(layer), [Vector2i(0, 0)] as Array[Vector2i], "The height moved to the chunk the paint moved to")
    _assert_ridge(layer.get_field(Vector2i(0, 0), SaFieldSpec.HEIGHT), "A cropped layer")
    assert_true(_doc.undo(), "Undo takes the crop back")
    _assert_ridge(layer.get_field(Vector2i(1, 1), SaFieldSpec.HEIGHT), "An uncropped layer")


func test_scaling_the_image_scales_the_height_with_the_paint() -> void:
    var layer := _doc.active_layer
    SaHeightOps.new(_doc).gain(layer)
    _paint(layer.get_or_create_field(Vector2i(0, 0)), RED)
    _raise(layer.get_or_create_field(Vector2i(0, 0), SaFieldSpec.HEIGHT), 3.0)

    assert_true(SaResample.new(_doc).resample_to(Vector2i(1536, 1536)), "The image doubles")
    assert_eq(
        _heights(layer),
        [Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 0), Vector2i(1, 1)] as Array[Vector2i],
        "The height spreads over the four chunks its paint now covers"
    )
    var far := _texel(layer.get_field(Vector2i(1, 1), SaFieldSpec.HEIGHT), Vector2i(100, 100))
    assert_almost_eq(far.r, 3.0, 0.001, "at the height it stood at, and never clamped to one")
    assert_true(_doc.undo(), "Undo takes the scale back")
    assert_eq(_heights(layer), [Vector2i(0, 0)] as Array[Vector2i], "and the height with it")
