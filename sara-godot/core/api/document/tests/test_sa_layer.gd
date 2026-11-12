## GPU integration tests for SaLayer chunk management.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true


func test_layer_grid_allocation_and_chunks() -> void:
    var layer := SaLayer.new()
    assert_true(layer.chunks.is_empty(), "A new layer holds no chunks until paint lands")
    layer.allocate_grid(Vector2i(500, 500))
    # 500 / 256 = 1.95 -> ceil is 2. 2x2 = 4 chunks.
    assert_eq(layer.chunks.size(), 4, "500x500 canvas should allocate 4 chunks when asked for the grid")
    assert_true(layer.chunks.has(Vector2i(0, 0)), "Should have chunk at (0,0)")
    assert_true(layer.chunks.has(Vector2i(1, 1)), "Should have chunk at (1,1)")

    var chunk := layer.get_or_create_chunk(Vector2i(0, 0))
    assert_not_null(chunk, "Chunk should not be null")
    assert_eq(chunk.fields.size(), layer.schema.size(), "A chunk carries one texture per field in the schema")
    assert_true(chunk.albedo().rid.is_valid(), "The albedo field RID should be valid")

    layer.free()


func test_layer_fill_and_duplicate() -> void:
    var layer := SaLayer.new()
    layer.allocate_grid(Vector2i(256, 256))
    layer.fill(Color(1, 0, 0, 1))

    var dup := layer.duplicate_chunk(Vector2i(0, 0))
    assert_not_null(dup, "Duplicate chunk should return a valid copy")
    if dup != null:
        assert_true(dup.albedo().rid.is_valid(), "Duplicate albedo RID should be valid")
        assert_true(dup.albedo().rid != layer.get_field(Vector2i(0, 0)).rid, "Duplicate should have a distinct RID")

    layer.free()


## A layer whose albedo is *derived* resolves it before anything reads it. This
## is the one mechanism impasto (height -> normals) and Kubelka-Munk
## (concentrations + thickness -> RGBA) both need, built and tested here while
## every real layer still paints its albedo directly.
func test_a_derived_field_is_resolved_before_it_is_read() -> void:
    var layer := SaLayer.new()
    var sources: Array[StringName] = [&"thickness"]
    var derived: Array[SaFieldSpec] = [
        SaFieldSpec.create(&"thickness", RenderingDevice.DATA_FORMAT_R32_SFLOAT, false),
        SaFieldSpec.create(SaFieldSpec.ALBEDO, RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT, true, sources),
    ]
    layer.schema = derived
    assert_true(layer.has_derived, "A schema with a sourced field has derived fields")

    var resolved: Array[Vector2i] = []
    layer.resolve_hook = (func(_owner: SaLayer, grid_pos: Vector2i, chunk: SaChunk) -> void:
        resolved.append(grid_pos)
        chunk.albedo().clear(Color(0, 1, 0, 1)))

    layer.get_or_create_chunk(Vector2i.ZERO)
    layer.resolve_pending()
    assert_eq(resolved, [Vector2i.ZERO] as Array[Vector2i], "A newly allocated chunk needs resolving")

    var rd := GlobalShaderCompiler.get_rd()
    var data: PackedByteArray = rd.texture_get_data(layer.get_field(Vector2i.ZERO).rid, 0)
    assert_almost_eq(data.decode_float(4), 1.0, 0.001, "The hook wrote the albedo the compositor will read")

    layer.resolve_pending()
    assert_eq(resolved.size(), 1, "Nothing changed, so nothing is resolved again")

    layer.fill(Color(0, 0, 0, 1))
    layer.resolve_pending()
    assert_eq(resolved.size(), 2, "Writing the authoritative fields makes the derived one stale again")

    layer.free()


## Every layer in Sara today has no derived fields, so the hook must cost nothing
## more than a bool check even if something sets one.
func test_a_layer_with_no_derived_fields_never_calls_the_hook() -> void:
    var layer := SaLayer.new()
    assert_false(layer.has_derived, "The default schema is one painted field")

    var calls: Array[int] = [0]
    layer.resolve_hook = func(_owner: SaLayer, _grid_pos: Vector2i, _chunk: SaChunk) -> void: calls[0] += 1

    layer.get_or_create_chunk(Vector2i.ZERO)
    layer.resolve_pending()
    assert_eq(calls[0], 0, "A layer that paints its albedo resolves nothing")

    layer.free()
