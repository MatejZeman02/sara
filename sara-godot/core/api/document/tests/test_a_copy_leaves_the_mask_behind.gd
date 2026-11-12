## A copy leaves the layer's mask behind.
##
## A copy from a masked layer and pasted, and every pasted chunk carried the
## mask as a field the pasted layer's schema did not name, memory nothing
## showed and nothing freed. The pixels are read back, because a chunk with a
## stray field still paints the right picture.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const RED := Color(1.0, 0.0, 0.0, 1.0)

var _easel: SaEasel = null
var _doc: SaDocument = null
## The clipboard under test, the one `SaDocuments` holds for every open document.
var _held: SaClipboard = null


func before_each() -> void:
    _held = SaClipboard.new()
    _easel = SaEasel.create_default(Vector2i(512, 512))
    _doc = _easel.document


func after_each() -> void:
    _easel.free()
    _easel = null
    _doc = null


func _texel(texture: SaTexture, at: Vector2i) -> Color:
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return SaFieldSpec.decode_texel(bytes, texture.format, at.y * texture.size.x + at.x)


## The active layer red over two chunks, under a mask that hides half of it.
func _masked_layer() -> SaLayer:
    var layer := _doc.active_layer
    for grid_pos: Vector2i in [Vector2i(0, 0), Vector2i(1, 0)]:
        layer.get_or_create_chunk(grid_pos).clear(RED)
    layer.add_mask(0.5)
    return layer


func _names(schema: Array[SaFieldSpec]) -> Array[StringName]:
    var names: Array[StringName] = []
    for spec: SaFieldSpec in schema:
        names.append(spec.id)
    return names


func test_the_clipboard_records_no_mask() -> void:
    var source := _masked_layer()
    assert_not_null(source.mask, "The source has a mask")

    assert_eq(_held.copy(_doc, source), 2, "Both chunks are copied")

    assert_false(_names(_held.schema).has(SaFieldSpec.MASK), "The recorded schema has no mask")
    for grid_pos: Vector2i in _held.chunks:
        var copied: SaChunk = _held.chunks[grid_pos]
        assert_false(copied.has_field(SaFieldSpec.MASK), "The copy at %s holds no mask" % grid_pos)
    assert_true(source.chunks[Vector2i(0, 0)].has_field(SaFieldSpec.MASK), "and the source keeps its own")


func test_every_pasted_chunk_holds_only_what_the_pasted_layer_names() -> void:
    var source := _masked_layer()
    _held.copy(_doc, source)

    var pasted := _held.paste(_doc)

    assert_not_null(pasted, "The paste made a layer")
    assert_null(pasted.mask, "The pasted layer has no mask")
    var named := _names(pasted.schema)
    assert_eq(pasted.chunks.size(), 2, "with both chunks")
    for grid_pos: Vector2i in pasted.chunks:
        var chunk: SaChunk = pasted.chunks[grid_pos]
        for field_id: StringName in chunk.fields:
            assert_true(named.has(field_id), "The pasted chunk at %s holds %s, which its layer names" % [grid_pos, field_id])


func test_the_pasted_pixels_are_the_sources() -> void:
    var source := _masked_layer()
    _held.copy(_doc, source)

    var pasted := _held.paste(_doc)

    for grid_pos: Vector2i in source.chunks:
        for at: Vector2i in [Vector2i(0, 0), Vector2i(100, 200), Vector2i(255, 255)]:
            var was := _texel(source.get_field(grid_pos), at)
            var now := _texel(pasted.get_field(grid_pos), at)
            assert_almost_eq(now.r, was.r, 1e-4, "Red at %s of %s" % [at, grid_pos])
            assert_almost_eq(now.a, was.a, 1e-4, "and alpha, what the layer holds rather than what its mask shows")
