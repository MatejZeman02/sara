## SaChunk and SaFieldSpec: the multi-field chunk substrate.
##
## Sara has one field today. These tests are written against two, because the
## whole point of the field mechanism is that adding the second one changes nothing here.
extends "res://tests/test_framework.gd"

## Allocates real textures.
const REQUIRES_GPU := true

const HEIGHT: StringName = &"height"


func _two_field_schema() -> Array[SaFieldSpec]:
    var schema: Array[SaFieldSpec] = [
        SaFieldSpec.albedo(),
        SaFieldSpec.create(HEIGHT, RenderingDevice.DATA_FORMAT_R32_SFLOAT, false),
    ]
    return schema


func test_the_default_schema_is_one_authoritative_colour_field() -> void:
    var schema := SaFieldSpec.default_schema()
    assert_eq(schema.size(), 1, "A layer nobody configured has exactly one field")

    var albedo := schema[0]
    assert_eq(albedo.id, SaFieldSpec.ALBEDO, "That field is albedo")
    assert_false(albedo.is_derived(), "Albedo is painted, not resolved")
    assert_true(albedo.is_color, "Albedo participates in colour conversion")
    assert_eq(albedo.bytes_per_texel(), 16, "RGBA32F is 16 bytes per texel")


## The readback offsets in the exporter and the eyedropper must come from here,
## because F16 storage and single-channel fields are both decided features.
func test_bytes_per_texel_is_not_always_sixteen() -> void:
    assert_eq(SaFieldSpec.create(&"a", RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT).bytes_per_texel(), 8, "RGBA16F")
    assert_eq(SaFieldSpec.create(&"h", RenderingDevice.DATA_FORMAT_R32_SFLOAT).bytes_per_texel(), 4, "R32F")
    assert_eq(SaFieldSpec.create(&"h", RenderingDevice.DATA_FORMAT_R16_SFLOAT).bytes_per_texel(), 2, "R16F")


func test_a_derived_field_names_its_sources() -> void:
    var sources: Array[StringName] = [HEIGHT]
    var normals := SaFieldSpec.create(&"normals", RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT, false, sources)
    assert_true(normals.is_derived(), "A field with sources is resolved, not painted")
    assert_eq(normals.derived_from, sources, "It remembers what it is resolved from")


func test_find_locates_a_spec_by_id() -> void:
    var schema := _two_field_schema()
    assert_eq(SaFieldSpec.find(schema, HEIGHT).format, RenderingDevice.DATA_FORMAT_R32_SFLOAT, "Finds the height spec")
    assert_null(SaFieldSpec.find(schema, &"nothing"), "An id not in the schema is null, not an error")


func test_a_chunk_allocates_one_texture_per_field_in_its_format() -> void:
    var chunk := SaChunk.create(_two_field_schema())

    assert_eq(chunk.fields.size(), 2, "One texture per schema entry")
    assert_true(chunk.has_field(SaFieldSpec.ALBEDO), "Albedo is allocated")
    assert_true(chunk.has_field(HEIGHT), "Height is allocated")
    assert_null(chunk.field(&"nothing"), "A field outside the schema is null")

    assert_eq(chunk.albedo().format, RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT, "Albedo is RGBA32F")
    assert_eq(chunk.field(HEIGHT).format, RenderingDevice.DATA_FORMAT_R32_SFLOAT, "Height keeps its own format")
    assert_eq(chunk.albedo().size, Vector2i(SaChunk.SIZE, SaChunk.SIZE), "Full resolution is SIZE across")


## Nothing may assume a chunk is SIZE pixels across. Adaptive resolution
## makes this per chunk, and it is read from
## day one so that change stays additive.
func test_resolution_scale_drives_the_texture_size_and_the_dispatch() -> void:
    var full := SaChunk.create(SaFieldSpec.default_schema())
    assert_eq(full.pixel_size(), 256, "Full resolution is 256 pixels")
    assert_eq(full.workgroups(), 32, "256 pixels is 32 workgroups of 8")

    var half := SaChunk.create(SaFieldSpec.default_schema(), 0.5)
    assert_eq(half.pixel_size(), 128, "Half resolution is 128 pixels")
    assert_eq(half.workgroups(), 16, "128 pixels is 16 workgroups, not 32")
    assert_eq(half.albedo().size, Vector2i(128, 128), "The texture is allocated at the reduced size")

    var tiny := SaChunk.create(SaFieldSpec.default_schema(), 0.0)
    assert_eq(tiny.pixel_size(), 1, "A degenerate scale still yields a dispatchable chunk")
    assert_eq(tiny.workgroups(), 1, "...and at least one workgroup")


func test_clear_writes_every_field() -> void:
    var chunk := SaChunk.create(_two_field_schema())
    chunk.clear(Color(0.25, 0.0, 0.0, 0.5))

    var rd := GlobalShaderCompiler.get_rd()
    var albedo: PackedByteArray = rd.texture_get_data(chunk.albedo().rid, 0)
    assert_almost_eq(albedo.decode_float(0), 0.25, 0.001, "Albedo red")
    assert_almost_eq(albedo.decode_float(12), 0.5, 0.001, "Albedo alpha")

    var height: PackedByteArray = rd.texture_get_data(chunk.field(HEIGHT).rid, 0)
    assert_almost_eq(height.decode_float(0), 0.25, 0.001, "The single-channel field is cleared too")


## Undo copies a chunk, and a chunk is now more than one texture.
func test_duplicate_copies_every_field_into_new_textures() -> void:
    var chunk := SaChunk.create(_two_field_schema())
    chunk.clear(Color(0.75, 0.0, 0.0, 1.0))

    var copy := chunk.duplicate_chunk()
    assert_eq(copy.fields.size(), 2, "The copy has the same fields")
    assert_eq(copy.resolution_scale, chunk.resolution_scale, "...and the same resolution")
    assert_true(copy.albedo().rid != chunk.albedo().rid, "The copy is a distinct texture, not an alias")

    var rd := GlobalShaderCompiler.get_rd()
    var data: PackedByteArray = rd.texture_get_data(copy.albedo().rid, 0)
    assert_almost_eq(data.decode_float(0), 0.75, 0.001, "The copy carries the original's pixels")

    var height: PackedByteArray = rd.texture_get_data(copy.field(HEIGHT).rid, 0)
    assert_almost_eq(height.decode_float(0), 0.75, 0.001, "Every field is copied, not just albedo")


## Writing through one must not reach the other, or undo restores nothing.
func test_a_duplicate_is_independent_of_its_original() -> void:
    var chunk := SaChunk.create(SaFieldSpec.default_schema())
    chunk.clear(Color(1.0, 0.0, 0.0, 1.0))
    var copy := chunk.duplicate_chunk()
    chunk.clear(Color(0.0, 1.0, 0.0, 1.0))

    var rd := GlobalShaderCompiler.get_rd()
    var data: PackedByteArray = rd.texture_get_data(copy.albedo().rid, 0)
    assert_almost_eq(data.decode_float(0), 1.0, 0.001, "The copy still holds what the original held")
    assert_almost_eq(data.decode_float(4), 0.0, 0.001, "...and not what was written afterwards")


## One place decides how a texel is laid out, because two places disagreed. The
## eyedropper decoded four bytes per channel whatever the format, which on an
## F16 texture reads red as two halves glued together and blue past the end of a
## one-texel buffer, and the export path built an RGBAF image from half as many
## bytes as that needs.
func test_a_texel_is_decoded_at_the_format_it_was_stored_in() -> void:
    var f32 := PackedByteArray()
    f32.resize(16)
    f32.encode_float(0, 0.25)
    f32.encode_float(4, 0.5)
    f32.encode_float(8, 0.75)
    f32.encode_float(12, 1.0)

    var f16 := PackedByteArray()
    f16.resize(8)
    f16.encode_half(0, 0.25)
    f16.encode_half(2, 0.5)
    f16.encode_half(4, 0.75)
    f16.encode_half(6, 1.0)

    var from_f32 := SaFieldSpec.decode_texel(f32, RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT)
    var from_f16 := SaFieldSpec.decode_texel(f16, RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT)

    assert_almost_eq(from_f32.r, 0.25, 0.0001, "F32 red")
    assert_almost_eq(from_f32.a, 1.0, 0.0001, "F32 alpha, at the far end of the texel")
    assert_almost_eq(from_f16.r, 0.25, 0.001, "The same value stored as a half decodes the same")
    assert_almost_eq(from_f16.b, 0.75, 0.001, "including the channel decode_float could not reach")
    assert_almost_eq(from_f16.a, 1.0, 0.001, "and alpha")


## Indexing has to scale with the format too, or the second texel of an F16
## buffer is read from the middle of the first.
func test_the_texel_index_steps_by_the_format_width() -> void:
    var bytes := PackedByteArray()
    bytes.resize(16)
    bytes.encode_half(0, 1.0)
    bytes.encode_half(8, 0.5)

    var second := SaFieldSpec.decode_texel(bytes, RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, 1)

    assert_almost_eq(second.r, 0.5, 0.001, "Texel 1 of an F16 buffer starts eight bytes in")


## A single-channel field has no colour. Returning its one value in red with
## opaque alpha is what a heightfield preview wants, and it must not read three
## channels that are not there.
func test_a_single_channel_field_decodes_without_reading_past_itself() -> void:
    var bytes := PackedByteArray()
    bytes.resize(4)
    bytes.encode_float(0, 0.375)

    var decoded := SaFieldSpec.decode_texel(bytes, RenderingDevice.DATA_FORMAT_R32_SFLOAT)

    assert_almost_eq(decoded.r, 0.375, 0.0001, "The one value it has")
    assert_almost_eq(decoded.a, 1.0, 0.0001, "and opaque, so a preview shows it")


## A truncated readback is a failure to report, not a buffer to guess at.
func test_a_buffer_too_short_for_a_texel_decodes_to_nothing() -> void:
    var bytes := PackedByteArray()
    bytes.resize(4)

    var decoded := SaFieldSpec.decode_texel(bytes, RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT)

    assert_eq(decoded, Color.TRANSPARENT, "Four bytes are not an RGBA32F texel")
    assert_eq(SaFieldSpec.decode_texel(bytes, 999999), Color.TRANSPARENT, "and an unknown format is not decodable")
