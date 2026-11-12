## A snapshot of part of a chunk, which is what undo history keeps for a stroke.
extends "res://tests/test_framework.gd"

## Real texture copies.
const REQUIRES_GPU := true

const BEFORE := Color(1.0, 0.0, 0.0, 1.0)
const AFTER := Color(0.0, 1.0, 0.0, 1.0)
const LATER := Color(0.0, 0.0, 1.0, 1.0)


func _layer() -> SaLayer:
    var layer := SaLayer.new()
    layer.allocate_grid(Vector2i(256, 256))
    return layer


## The red, green and blue of one texel of a chunk.
func _texel(layer: SaLayer, x: int, y: int) -> Color:
    var rd := GlobalShaderCompiler.get_rd()
    var data := rd.texture_get_data(layer.get_field(Vector2i.ZERO).rid, 0)
    var at := (y * SaChunk.SIZE + x) * 16
    return Color(data.decode_float(at), data.decode_float(at + 4), data.decode_float(at + 8))


## Restoring a region puts that region back and leaves everything else alone.
##
## Leaving the rest alone is the half worth asserting. A snapshot that quietly
## restored the whole tile would pass any test that only looked inside the region,
## and it would undo more than the stroke did.
func test_a_delta_restores_its_region_and_only_its_region() -> void:
    var layer := _layer()
    layer.fill(BEFORE)
    var chunk := layer.get_or_create_chunk(Vector2i.ZERO)

    var delta := SaChunkDelta.capture(chunk, Rect2i(32, 32, 64, 64))
    assert_not_null(delta, "A region of an existing chunk is capturable")
    chunk.albedo().clear(AFTER)
    assert_almost_eq(_texel(layer, 40, 40).g, 1.0, 0.01, "The whole tile was painted over")

    delta.apply_to(chunk)
    assert_almost_eq(_texel(layer, 40, 40).r, 1.0, 0.01, "Inside the region the old pixels are back")
    assert_almost_eq(_texel(layer, 40, 40).g, 0.0, 0.01, "and the paint is gone")
    assert_almost_eq(_texel(layer, 200, 200).g, 1.0, 0.01, "Outside it nothing was touched")

    layer.free()


## Growing a snapshot keeps what it already held and reads only the new bands.
##
## The case is painting straight into a layer, which erase and alpha lock do: the
## region widens under a snapshot that has already been taken, and the pixels
## inside the old rectangle have been painted on since. Reading them again would
## save the half-finished stroke, so an undo would restore it.
func test_growing_a_delta_does_not_re_read_what_it_already_saved() -> void:
    var layer := _layer()
    layer.fill(BEFORE)
    var chunk := layer.get_or_create_chunk(Vector2i.ZERO)

    var delta := SaChunkDelta.capture(chunk, Rect2i(0, 0, 64, 64))
    # A dab lands inside the captured region, so this pixel is no longer pristine.
    chunk.albedo().clear(AFTER)
    var grown := delta.grown_to(chunk, Rect2i(0, 0, 128, 128))
    assert_eq(grown.rect, Rect2i(0, 0, 128, 128), "The snapshot now covers both")

    # Paint again, so restoring cannot accidentally look right.
    chunk.albedo().clear(LATER)
    grown.apply_to(chunk)

    assert_almost_eq(_texel(layer, 10, 10).r, 1.0, 0.01, "The original region still holds what it held first")
    assert_almost_eq(_texel(layer, 10, 10).g, 0.0, 0.01, "not the paint that landed after it was captured")
    assert_almost_eq(_texel(layer, 100, 100).g, 1.0, 0.01, "and the band added later holds what was there then")
    assert_almost_eq(_texel(layer, 200, 200).b, 1.0, 0.01, "Outside the snapshot, untouched")

    layer.free()


## A region already covered costs nothing and changes nothing.
func test_growing_into_a_region_already_covered_is_a_no_op() -> void:
    var layer := _layer()
    layer.fill(BEFORE)
    var chunk := layer.get_or_create_chunk(Vector2i.ZERO)

    var delta := SaChunkDelta.capture(chunk, Rect2i(0, 0, 128, 128))
    var same := delta.grown_to(chunk, Rect2i(16, 16, 32, 32))
    assert_eq(same, delta, "The same snapshot comes back rather than a copy of it")

    layer.free()


## A stroke's snapshot is a fraction of the tile, which is the point of all this.
func test_a_delta_costs_its_region_rather_than_the_chunk() -> void:
    var layer := _layer()
    layer.fill(BEFORE)
    var chunk := layer.get_or_create_chunk(Vector2i.ZERO)

    var delta := SaChunkDelta.capture(chunk, Rect2i(0, 0, 64, 64))
    assert_eq(delta.byte_size(), 64 * 64 * 16, "A 64x64 snapshot is 64x64 texels")
    assert_eq(chunk.byte_size(), SaChunk.SIZE * SaChunk.SIZE * 16, "against a whole tile, sixteen times larger")

    layer.free()
