## The Info docker's VRAM row asks each chunk its own edge and counts only the
## fields a chunk holds. It counted every chunk at 256 pixels and every field of
## the schema, so a half-resolution chunk read four times its cost and a lazy
## field nobody painted read as allocated.
extends "res://tests/test_framework.gd"

const HEIGHT: StringName = &"height"


func _layer() -> SaLayer:
    var layer := SaLayer.new()
    var schema: Array[SaFieldSpec] = [
        SaFieldSpec.albedo(),
        SaFieldSpec.create(HEIGHT, RenderingDevice.DATA_FORMAT_R32_SFLOAT, false),
    ]
    layer.schema = schema
    return layer


## A one-texel texture stands in for each field, because the count reads only
## whether the field is there, and `fields` is typed to hold an `SaTexture`.
func _chunk(scale: float, field_ids: Array[StringName]) -> SaChunk:
    var chunk := SaChunk.new()
    chunk.resolution_scale = scale
    for id in field_ids:
        chunk.fields[id] = SaTexture.new(Vector2i.ONE)
    return chunk


func test_a_full_chunk_counts_its_one_field() -> void:
    var layer := _layer()
    var fields: Array[StringName] = [SaFieldSpec.ALBEDO]
    layer.chunks[Vector2i.ZERO] = _chunk(1.0, fields)
    var edge := float(SaChunk.SIZE)
    assert_almost_eq(SaInfoSection.layer_vram_bytes(layer), edge * edge * 16.0, 0.5, "One RGBA32F chunk at full size")
    layer.free()


func test_a_half_resolution_chunk_costs_a_quarter() -> void:
    var layer := _layer()
    var fields: Array[StringName] = [SaFieldSpec.ALBEDO]
    layer.chunks[Vector2i.ZERO] = _chunk(0.5, fields)
    var edge := float(SaChunk.SIZE) * 0.5
    assert_almost_eq(SaInfoSection.layer_vram_bytes(layer), edge * edge * 16.0, 0.5, "Half the edge, a quarter of the bytes")
    layer.free()


func test_a_field_the_chunk_has_is_added() -> void:
    var layer := _layer()
    var fields: Array[StringName] = [SaFieldSpec.ALBEDO, HEIGHT]
    layer.chunks[Vector2i.ZERO] = _chunk(1.0, fields)
    var edge := float(SaChunk.SIZE)
    assert_almost_eq(SaInfoSection.layer_vram_bytes(layer), edge * edge * 20.0, 0.5, "Colour and height together")
    layer.free()
