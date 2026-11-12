## A converted texel stores the nearest half. The colour
## conversion's store into an F16 chunk narrowed by truncating on some GPUs,
## so pure magenta imported into an F16 Oklab document kept an `a` of 0.274414
## where the nearest half is 0.274658, decoded to a green 0.68 of an 8-bit level
## inside the cube and was drawn as (255, 1, 255) by the view, the `look` and a
## PNG export.
##
## The eight vertices of the sRGB cube are put down the way an import puts a
## picture down, once into an F32 Oklab document and once into an F16 one. Both
## run the one kernel, so the F32 chunk holds the float32 Oklab the F16 chunk
## narrowed, and every stored half has to be NumPy's `astype(np.float16)` of
## it, to the bit. NumPy is not in a suite, so its rounding is written out
## below and held to pairs NumPy gave, the vertices' own among them.
extends "res://tests/test_framework.gd"

## The conversion runs on a real device, which is where the narrowing is.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

## The cube's eight vertices as 8-bit colours, one a column of the picture.
const VERTICES: Array[Vector3i] = [
    Vector3i(0, 0, 0),
    Vector3i(255, 0, 0),
    Vector3i(0, 255, 0),
    Vector3i(0, 0, 255),
    Vector3i(255, 255, 0),
    Vector3i(0, 255, 255),
    Vector3i(255, 0, 255),
    Vector3i(255, 255, 255),
]

## Float32 bits and the half bits NumPy's `astype(np.float16)` gives for them,
## taken on 2026-10-04. The first eighteen are the Oklab of the six primaries
## and secondaries as the reference GPU converts them, red's to magenta's in the
## order of VERTICES, and the rest are the corners of the rounding: a tie that
## goes down to even, one that goes up, a carry into the exponent, a half's
## subnormal, a tie between two of them, half the smallest, which is zero, and
## the smallest itself, which is white's `b`.
const NUMPY: Dictionary[int, int] = {
    0x3f20c1af: 0x3906,
    0x3e664283: 0x3332,
    0x3e00dddb: 0x3007,
    0x3f5dcefd: 0x3aee,
    0xbe6f8043: 0xb37c,
    0x3e37ce76: 0x31be,
    0x3ee76e57: 0x373b,
    0xbd04f196: 0xa828,
    0xbe9f809f: 0xb4fc,
    0x3f77cdb6: 0x3bbe,
    0xbd922a02: 0xac91,
    0x3e4b55dd: 0x325b,
    0x3f67c83e: 0x3b3e,
    0xbe1907c8: 0xb0c8,
    0xbd215ff7: 0xa90b,
    0x3f33a0e5: 0x399d,
    0x3e8c93f4: 0x3465,
    0xbe2d3743: 0xb16a,
    0x3f801000: 0x3c00,
    0x3f803000: 0x3c02,
    0x3fffffff: 0x4000,
    0x3649539c: 0x0032,
    0x33c00000: 0x0002,
    0x33000000: 0x0000,
    0x33800000: 0x0001,
}

## Each colour a block this many pixels square, read at its middle.
const BLOCK := 4

## Pure magenta's column, and its `a`, which truncation stored one step low.
const MAGENTA := 6
const A := 1

var _registries: SaRegistries = null
var _easels: Array[SaEasel] = []


func before_each() -> void:
    _registries = Fixtures.make_registries()


func after_each() -> void:
    for easel: SaEasel in _easels:
        easel.free()
    _easels.clear()
    _registries = null


## The vertices put down into an Oklab document at *depth* from sRGB, the way
## an import puts a picture down, and the albedo of the one chunk they land in.
func _converted(depth: SaColorSpace.Depth) -> SaTexture:
    var image := Image.create_empty(VERTICES.size() * BLOCK, BLOCK, false, Image.FORMAT_RGB8)
    for i in VERTICES.size():
        var v := VERTICES[i]
        image.fill_rect(Rect2i(i * BLOCK, 0, BLOCK, BLOCK), Color8(v.x, v.y, v.z))
    var space := SaColorSpace.oklab_srgb_gamma30().with_depth(depth)
    var easel := SaEasel.create_default(image.get_size(), null, space)
    easel.compositor.set_registry(_registries.blend_modes)
    _easels.append(easel)
    var layer := SaImageImport.place(easel.document, image, "p5", SaColorSpace.srgb(), SaImageImport.Fit.ORIGIN)
    assert_not_null(layer, "The picture is put down as a layer")
    if layer == null or not layer.chunks.has(Vector2i.ZERO):
        return null
    return (layer.chunks[Vector2i.ZERO] as SaChunk).albedo()


## Where the middle of vertex *index*'s block starts in *texture*'s bytes.
static func _offset(texture: SaTexture, index: int) -> int:
    var width: int = SaFieldSpec.BYTES_PER_TEXEL[texture.format]
    return ((BLOCK >> 1) * texture.size.x + index * BLOCK + (BLOCK >> 1)) * width


## The raw bits of channel *channel* of vertex *index*'s block in *texture*,
## a float32's or a half's as the texture stores it.
static func _bits(texture: SaTexture, bytes: PackedByteArray, index: int, channel: int) -> int:
    var at := _offset(texture, index)
    if SaFieldSpec.BYTES_PER_TEXEL[texture.format] == 16:
        return bytes.decode_u32(at + channel * 4)
    return bytes.decode_u16(at + channel * 2)


## NumPy's `astype(np.float16)` of the float32 *bits*, as half bits: round to
## nearest with ties to even, below the smallest normal half to a multiple of
## 2^-24, past the largest to infinity, and a NaN kept a NaN.
static func _numpy_half(bits: int) -> int:
    var sign_bit := (bits >> 16) & 0x8000
    var exponent := (bits >> 23) & 0xff
    var mantissa := bits & 0x7fffff
    if exponent == 0xff:
        return sign_bit | 0x7c00 | (0x200 if mantissa != 0 else 0)
    var half_exponent := exponent - 127 + 15
    if half_exponent >= 31:
        return sign_bit | 0x7c00
    var kept := 0
    var dropped := 13
    if half_exponent <= 0:
        if half_exponent < -10:
            return sign_bit
        mantissa |= 0x800000
        dropped = 14 - half_exponent
        kept = mantissa >> dropped
    else:
        kept = (half_exponent << 10) | (mantissa >> dropped)
    var rest := mantissa & ((1 << dropped) - 1)
    var halfway := 1 << (dropped - 1)
    if rest > halfway or (rest == halfway and kept & 1 == 1):
        kept += 1
    return sign_bit | kept


func test_the_rounding_written_here_is_numpys() -> void:
    for float_bits: int in NUMPY:
        var half_bits: int = NUMPY[float_bits]
        assert_eq(_numpy_half(float_bits), half_bits, "0x%08x rounds to NumPy's 0x%04x" % [float_bits, half_bits])


## Every channel of every vertex an F16 Oklab document stores is NumPy's half
## of the float32 the same kernel stores into an F32 one.
func test_the_eight_vertices_store_numpys_half_of_the_float_oklab() -> void:
    var full := _converted(SaColorSpace.Depth.F32)
    var half := _converted(SaColorSpace.Depth.F16)
    assert_not_null(full, "The F32 document holds the vertices")
    assert_not_null(half, "and so does the F16 one")
    if full == null or half == null:
        return
    assert_eq(SaFieldSpec.BYTES_PER_TEXEL[half.format], 8, "The F16 document's chunk is half float")
    var rd := GlobalShaderCompiler.get_rd()
    var full_bytes := rd.texture_get_data(full.rid, 0)
    var half_bytes := rd.texture_get_data(half.rid, 0)
    for i in VERTICES.size():
        for channel in 4:
            var float_bits := _bits(full, full_bytes, i, channel)
            var stored := _bits(half, half_bytes, i, channel)
            var what := "%s channel %d, float 0x%08x" % [VERTICES[i], channel, float_bits]
            assert_eq(stored, _numpy_half(float_bits), "%s, is stored as NumPy's half" % what)


## The rounding is for a half field alone. A float32 field keeps the float the
## kernel computed, which for pure magenta's `a` is not a half.
func test_an_f32_document_keeps_the_float_unrounded() -> void:
    var full := _converted(SaColorSpace.Depth.F32)
    assert_not_null(full, "The F32 document holds the vertices")
    if full == null:
        return
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(full.rid, 0)
    var bits := _bits(full, bytes, MAGENTA, A)
    assert_true(bits & 0x1fff != 0, "Pure magenta's a is stored as the float 0x%08x, past a half's bits" % bits)


## Pure magenta's `a` in particular, the number the fault was read from.
func test_pure_magentas_a_is_the_nearer_half() -> void:
    var half := _converted(SaColorSpace.Depth.F16)
    assert_not_null(half, "The F16 document holds the vertices")
    if half == null:
        return
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(half.rid, 0)
    var stored := bytes.decode_half(_offset(half, MAGENTA) + A * 2)
    assert_almost_eq(stored, 0.2746582, 1e-7, "Pure magenta's a is 0.274658, not the 0.274414 truncation stored")
