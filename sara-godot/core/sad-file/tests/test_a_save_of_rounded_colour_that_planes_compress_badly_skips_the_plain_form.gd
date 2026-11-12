## A chunk whose planes form compresses badly is stored as
## planes with the plain form never compressed beside it, and a chunk whose
## planes form came out well is chosen as it always was.
##
## The chunk of rounded random colour is the case the guard exists for. It is
## built as the suite of a save the painter asks for builds random colour, an independent value from -3
## to 7 a channel, then rounded to 12 significant bits as a save rounds full
## precision colour, so it is what the rounded save of a document of random
## colour holds: the plain form keeps a run of short matches Zstd codes slowly
## and comes out above its usual size, and the planes form comes out past
## [constant SaSadBlob.PLANES_PLAIN_LIMIT] of the chunk.
##
## The planes form is the only thing a save can skip, so the reading that the
## plain form was not compressed is behavioural: a planes form past the limit is
## stored although the plain form beside it would have won by far, which a
## weighed chunk can never do. The reference suite holds the rest: a planes
## form at or under the limit is weighed exactly as before, and a chunk where
## plain is the smaller is still stored plain.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice: the two forms are read off a texture.
const REQUIRES_GPU := true

## The chunk a case works on, one chunk of a layer at full resolution.
const SIDE := 256
## The chunk of rounded random colour, where the planes form comes out past the
## limit.
const RANDOM := Vector2i(0, 0)
## The chunk of smooth paint, where the planes form comes out well.
const SMOOTH := Vector2i(1, 0)
## The chunk dithered between two far colours, where plain is the smaller.
const DITHER := Vector2i(2, 0)


## One rounded random colour, a value from -3 to 7 a channel as that suite
## makes it, rounded to 12 significant bits as a rounded save now rounds it.
static func rounded_random(side: int, format: int) -> PackedByteArray:
    var layout: Vector2i = SaSadBlob.LAYOUT[format]
    var rng := RandomNumberGenerator.new()
    rng.seed = 164
    var bytes := PackedByteArray()
    bytes.resize(side * side * layout.x * layout.y)
    var word := PackedByteArray()
    word.resize(4)
    var at := 0
    for i in side * side * layout.x:
        word.encode_float(0, rng.randf_range(-3.0, 7.0))
        word.encode_u32(0, SaSadSnapshot.round_bits(word.decode_u32(0)))
        if layout.y == 2:
            bytes.encode_half(at, word.decode_float(0))
        else:
            bytes.encode_u32(at, word.decode_u32(0))
        at += layout.y
    return bytes


## A ramp that crosses zero and white, smooth from one texel to the next, so
## the differences between neighbours are small and their high byte planes
## nearly all zero.
static func smooth(side: int, format: int) -> PackedByteArray:
    var layout: Vector2i = SaSadBlob.LAYOUT[format]
    var bytes := PackedByteArray()
    bytes.resize(side * side * layout.x * layout.y)
    var at := 0
    for y in side:
        for x in side:
            for channel in layout.x:
                var value := sin(x * 0.011 + channel) * 1.7 + cos(y * 0.007 - channel) * 0.9
                if layout.y == 2:
                    bytes.encode_half(at, value)
                else:
                    bytes.encode_float(at, value)
                at += layout.y
    return bytes


## Two far colours chosen at random a texel, where plain Zstd finds each texel a
## repeat of one of two and the planes hold their difference spread over every
## plane.
static func dithered(side: int, format: int) -> PackedByteArray:
    var layout: Vector2i = SaSadBlob.LAYOUT[format]
    var rng := RandomNumberGenerator.new()
    rng.seed = 39
    var bytes := PackedByteArray()
    bytes.resize(side * side * layout.x * layout.y)
    var at := 0
    for y in side:
        for x in side:
            var pick := rng.randi() % 2
            for channel in layout.x:
                var value := 0.137 + channel * 0.21 if pick == 0 else 3.71 - channel * 0.53
                if layout.y == 2:
                    bytes.encode_half(at, value)
                else:
                    bytes.encode_float(at, value)
                at += layout.y
    return bytes


## A full precision document of one layer holding a chunk of rounded random
## colour, a chunk of smooth paint and a chunk of dither, the three the cases
## beside this read.
static func painted() -> SaDocument:
    var rd := GlobalShaderCompiler.get_rd()
    var doc := SaDocument.new()
    doc.setup_default_document(Vector2i(768, 256), SaCompositor.new(), SaColorSpace.srgb().with_depth(SaColorSpace.Depth.F32))
    var layer := doc.active_layer
    layer.chunks.clear()
    for grid_pos: Vector2i in [RANDOM, SMOOTH, DITHER]:
        var size := layer.get_or_create_chunk(grid_pos).pixel_size()
        var texture := layer.get_or_create_field(grid_pos)
        var bytes := rounded_random(size, texture.format)
        if grid_pos == SMOOTH:
            bytes = smooth(size, texture.format)
        elif grid_pos == DITHER:
            bytes = dithered(size, texture.format)
        rd.texture_update(texture.rid, 0, bytes)
    return doc


## The chunk's bytes as they lie and as planes, the two forms a save weighs.
static func forms(texture: SaTexture) -> Array[PackedByteArray]:
    var buffer := SaSadBlob.planes_buffer(SaSadBlob.plane_bytes(texture))
    SaSadBlob.planes_into(texture, buffer)
    return [texture.rd.texture_get_data(texture.rid, 0), buffer.read()]


## Compresses *bytes* as a blob is compressed.
static func packed(bytes: PackedByteArray) -> PackedByteArray:
    return bytes.compress(SaSadFile.SAD_BLOB_COMPRESS)


## The share of the chunk *packed_planes* came out at.
static func share(packed_planes: PackedByteArray, chunk: int) -> float:
    return float(packed_planes.size()) / float(chunk)


func test_the_limit_is_the_research_s_0_3() -> void:
    assert_eq(SaSadBlob.PLANES_PLAIN_LIMIT, 0.3, "the fraction a planes form may leave and still be weighed")


func test_a_rounded_chunk_of_random_colour_stores_the_planes_form() -> void:
    var doc := painted()
    var texture := doc.active_layer.get_field(RANDOM)
    var two := forms(texture)
    var raw: PackedByteArray = two[0]
    var planes: PackedByteArray = two[1]
    var packed_planes := packed(planes)
    var packed_raw := packed(raw)
    assert_true(
        share(packed_planes, raw.size()) > SaSadBlob.PLANES_PLAIN_LIMIT,
        "the planes form of rounded random colour leaves more than the limit of the chunk"
    )
    assert_true(packed_planes.size() < packed_raw.size(), "and is the smaller of the two there anyway")
    var blobs := PackedByteArray()
    var slot: Dictionary[String, Variant] = {}
    SaSadBlob.fill_smaller(slot, planes, raw, blobs)
    assert_true(SaSadBlob.is_planes(slot), "the planes form is named as the transform")
    assert_eq(SaTyped.int_at(slot, "size", -1), packed_planes.size(), "and stored at its own compressed size")
    assert_true(SaSadBlob.read(slot, blobs) == planes, "and every byte of it comes back")
    doc.free()


func test_a_planes_form_past_the_limit_is_stored_without_the_plain_form() -> void:
    var doc := painted()
    var texture := doc.active_layer.get_field(RANDOM)
    var planes: PackedByteArray = forms(texture)[1]
    var cheap: PackedByteArray = dithered(SIDE, texture.format)
    var packed_planes := packed(planes)
    var packed_cheap := packed(cheap)
    assert_true(
        share(packed_planes, planes.size()) > SaSadBlob.PLANES_PLAIN_LIMIT,
        "the planes form leaves more than the limit of the chunk"
    )
    assert_true(packed_cheap.size() < packed_planes.size(), "and the plain form beside it would have won by far")
    var blobs := PackedByteArray()
    var slot: Dictionary[String, Variant] = {}
    SaSadBlob.fill_smaller(slot, planes, cheap, blobs)
    assert_eq(
        SaTyped.int_at(slot, "size", -1),
        packed_planes.size(),
        "the planes form is stored, so the smaller plain form was never compressed"
    )
    assert_true(SaSadBlob.is_planes(slot), "and the transform is named")
    assert_true(SaSadBlob.read(slot, blobs) == planes, "and every byte of it comes back")
    doc.free()


func test_a_chunk_of_smooth_paint_is_chosen_as_before() -> void:
    var doc := painted()
    var smooth_two := forms(doc.active_layer.get_field(SMOOTH))
    var smooth_planes := packed(smooth_two[1])
    var smooth_raw := packed(smooth_two[0])
    assert_true(
        share(smooth_planes, smooth_two[1].size()) <= SaSadBlob.PLANES_PLAIN_LIMIT,
        "the planes form of smooth paint stays at or under the limit"
    )
    var blobs := PackedByteArray()
    var slot: Dictionary[String, Variant] = {}
    SaSadBlob.fill_smaller(slot, smooth_two[1], smooth_two[0], blobs)
    assert_eq(
        SaTyped.int_at(slot, "size", -1),
        mini(smooth_planes.size(), smooth_raw.size()),
        "the smaller of the two forms is stored, as it always was"
    )
    assert_true(SaSadBlob.is_planes(slot), "which is the planes one here")
    assert_true(SaSadBlob.read(slot, blobs) == smooth_two[1], "and every byte of it comes back")
    var dither_two := forms(doc.active_layer.get_field(DITHER))
    var dither_planes := packed(dither_two[1])
    var dither_raw := packed(dither_two[0])
    assert_true(
        share(dither_planes, dither_two[1].size()) <= SaSadBlob.PLANES_PLAIN_LIMIT,
        "the planes form of the dither stays at or under the limit"
    )
    assert_true(dither_raw.size() < dither_planes.size(), "and plain is the smaller form there")
    var dither_slot: Dictionary[String, Variant] = {}
    SaSadBlob.fill_smaller(dither_slot, dither_two[1], dither_two[0], blobs)
    assert_eq(
        SaTyped.int_at(dither_slot, "size", -1),
        dither_raw.size(),
        "so the plain form is stored at its own size, as it always was"
    )
    assert_false(SaSadBlob.is_planes(dither_slot), "with no transform named")
    assert_true(SaSadBlob.read(dither_slot, blobs) == dither_two[0], "and every byte of the plain form comes back")
    doc.free()


func test_a_texture_without_planes_takes_the_plain_form() -> void:
    var raw := smooth(SIDE, RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT)
    var blobs := PackedByteArray()
    var slot: Dictionary[String, Variant] = {}
    SaSadBlob.fill_smaller(slot, PackedByteArray(), raw, blobs)
    assert_eq(SaTyped.int_at(slot, "size", -1), packed(raw).size(), "the bytes as they lie, at their own size")
    assert_false(SaSadBlob.is_planes(slot), "with no transform named")
    assert_true(SaSadBlob.read(slot, blobs) == raw, "and every byte of them comes back")
