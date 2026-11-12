## GPU integration tests for SaTexture.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true


func test_texture_creation_and_cleanup() -> void:
    var tex := SaTexture.new(Vector2i(64, 64))
    assert_true(tex.rid.is_valid(), "Texture RID should be valid upon creation")
    assert_eq(tex.size, Vector2i(64, 64), "Texture size should match requested")
    assert_not_null(tex.rd, "RenderingDevice reference should not be null")

    var rd := tex.rd
    var rid_copy := tex.rid
    assert_true(rd.texture_is_valid(rid_copy), "Texture should be valid on RenderingDevice")

    # Test predelete cleanup
    tex = null
    assert_false(rd.texture_is_valid(rid_copy), "Texture RID should be freed on RenderingDevice after object destruction")


## Allocation no longer defines the contents, so anything that needs a known
## starting state has to ask. This is the call that replaced the opaque grey
## clear every allocation used to pay for and immediately throw away.
func test_clear_writes_a_known_value() -> void:
    var tex := SaTexture.new(Vector2i(8, 8))
    tex.clear(Color(0.25, 0.5, 0.75, 1.0))

    var data: PackedByteArray = tex.rd.texture_get_data(tex.rid, 0)
    assert_almost_eq(data.decode_float(0), 0.25, 0.001, "Red should be what clear() wrote")
    assert_almost_eq(data.decode_float(4), 0.5, 0.001, "Green should be what clear() wrote")
    assert_almost_eq(data.decode_float(8), 0.75, 0.001, "Blue should be what clear() wrote")
    assert_almost_eq(data.decode_float(12), 1.0, 0.001, "Alpha should be what clear() wrote")


## A fresh chunk must still be transparent: the layer does the clear now.
func test_a_new_chunk_is_transparent() -> void:
    var layer := SaLayer.new()
    var chunk: SaTexture = layer.get_or_create_field(Vector2i.ZERO)

    var data := chunk.rd.texture_get_data(chunk.rid, 0)
    assert_almost_eq(data.decode_float(12), 0.0, 0.001, "A newly allocated chunk must be transparent")

    layer.free()
