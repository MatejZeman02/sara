## Which numbers a blend mode does its arithmetic on.
##
## The wanted behaviour is "linear for scene-referred documents, the current
## gamma-sRGB behaviour kept as the default for display-referred ones". That is
## already what happens, but only as a consequence of how the kernels are
## written rather than as anything stated, so this suite states it.
##
## The separable modes are arithmetic on stored values, so the blending space is
## the storage encoding and nothing has to convert. The non-separable ones go
## through Oklab, which is defined on light-linear values, so those decode
## through the document's transfer curve first and a linear document and a gamma
## one genuinely differ.
extends "res://tests/test_framework.gd"

## Dispatches the real composite kernels.
const REQUIRES_GPU := true


func _blend(space: SaColorSpace, kernel: String, src: Color, dst: Color) -> Color:
    var rd := GlobalShaderCompiler.get_rd()
    var texel := space.texel_format()
    var canvas := SaTexture.new(Vector2i(8, 8), texel)
    var chunk := SaTexture.new(Vector2i(8, 8), texel)
    canvas.clear(dst)
    chunk.clear(src)

    var compute := SaCompute.new("composite")
    compute.use_storage_format(texel)
    compute.set_texture(0, canvas.rid)
    compute.set_texture(1, chunk.rid)
    compute.set_push_constant_float_array(SaCompute.pack_composite_params(Vector2.ZERO, 1.0, space))
    compute.dispatch(GlobalShaderCompiler.get_kernel_index("composite", kernel), 1, 1, 1)

    return SaFieldSpec.decode_texel(rd.texture_get_data(canvas.rid, 0), texel)


## The property wanted here, and the reason nothing has to be converted to get
## it: a separable mode reads stored values, so a document that stores linear
## light blends in linear and one that stores gamma-encoded sRGB blends in
## gamma. Changing that would change every existing painting.
func test_a_separable_mode_blends_in_whatever_the_document_stores() -> void:
    var half := Color(0.5, 0.5, 0.5, 1.0)

    for kernel: String in ["screen", "overlay", "soft_light", "multiply"]:
        var on_gamma := _blend(SaColorSpace.srgb(), kernel, half, half)
        var on_linear := _blend(SaColorSpace.linear_srgb(), kernel, half, half)

        assert_almost_eq(on_linear.r, on_gamma.r, 0.002, "%s reads stored values, so the encoding does not enter it" % kernel)


## The arithmetic is the textbook one, on the stored numbers, with no transfer
## applied on the way in or out. Asserting the value rather than only that the
## two agree, so "both are wrong in the same way" cannot pass.
func test_the_separable_arithmetic_is_on_the_stored_numbers() -> void:
    var half := Color(0.5, 0.5, 0.5, 1.0)

    var screened := _blend(SaColorSpace.srgb(), "screen", half, half)

    assert_almost_eq(screened.r, 0.75, 0.002, "screen(0.5, 0.5) is 0.75, which is the stored-value answer")


## Oklab is defined on light-linear values, so these decode through the
## document's transfer first. A gamma document and a linear one holding the same
## stored number are holding different light, and the result says so. If these
## agreed, the transfer flag would not be reaching the kernel at all.
func test_a_non_separable_mode_reads_the_documents_transfer_curve() -> void:
    var source := Color(0.8, 0.2, 0.1, 1.0)
    var destination := Color(0.3, 0.6, 0.4, 1.0)

    var on_gamma := _blend(SaColorSpace.srgb(), "hue", source, destination)
    var on_linear := _blend(SaColorSpace.linear_srgb(), "hue", source, destination)

    assert_true(
        absf(on_linear.r - on_gamma.r) > 0.01 or absf(on_linear.g - on_gamma.g) > 0.01,
        "The same stored numbers mean different light, and an Oklab mode has to see that"
    )


## Both documents are stored at the same depth here, so a difference cannot be
## blamed on storage. It is the transfer curve or nothing.
func test_the_two_documents_under_test_differ_only_in_transfer() -> void:
    var gamma := SaColorSpace.srgb()
    var linear := SaColorSpace.linear_srgb()

    assert_eq(gamma.texel_format(), linear.texel_format(), "Same storage format")
    assert_eq(gamma.transfer.id, SaTransferFunction.ID_SRGB, "One is gamma encoded")
    assert_true(linear.transfer.is_identity(), "and the other is scene-referred")


# ---------------------------------------------------------------------------
# Normal, in a space the layer names
# ---------------------------------------------------------------------------
#
# Plain Normal mixes in whatever the document stores, which is why its dropdown
# label carries the document's space in brackets. The three modes below let a
# layer say otherwise, and the whole point is that they disagree: a half-covered
# white over black is a different grey in encoded RGB, in light and in Oklab.


## The one number the three have to differ on, and by more than rounding.
##
## Computed here from the descriptors rather than pinned to a table, so the test
## states what each space *means* rather than what the kernel happened to return
## the day it was written.
func test_the_three_normals_mix_in_three_different_places() -> void:
    var srgb := SaColorSpace.srgb()
    var white := Color(1.0, 1.0, 1.0, 0.5)
    var black := Color(0.0, 0.0, 0.0, 1.0)
    var curve := SaTransferFunction.srgb()

    var on_stored := _blend(srgb, "composite", white, black)
    var on_encoded := _blend(srgb, "composite_srgb", white, black)
    var on_light := _blend(srgb, "composite_linear", white, black)
    var on_perceptual := _blend(srgb, "composite_oklab", white, black)

    # Encoded: the stored numbers themselves, which is what Krita does and what
    # the document already stores, so it must equal plain Normal exactly.
    assert_almost_eq(on_encoded.r, 0.5, 1e-6, "Normal (sRGB) mixes the encoded numbers")
    assert_almost_eq(on_stored.r, on_encoded.r, 1e-6, "and an sRGB document's plain Normal is the same mode")

    # Light: average the photons, then encode. Half of full light is a much
    # lighter grey than half of the encoded number.
    assert_almost_eq(on_light.r, curve.encode(0.5), 2e-3, "Normal (linear) averages light")
    assert_true(on_light.r - on_encoded.r > 0.2, "which is visibly lighter than mixing encoded values")

    # Perceptual: half way up the lightness scale, which sits below the encoded
    # midpoint rather than above it.
    var half_lightness := 0.5 * SaOklab.from_linear_srgb(Vector3.ONE).x
    var expected := SaOklab.to_linear_srgb(Vector3(half_lightness, 0.0, 0.0))
    assert_almost_eq(on_perceptual.r, curve.encode(expected.x), 2e-3, "Normal (Oklab) mixes lightness")
    assert_true(on_encoded.r - on_perceptual.r > 0.05, "which is darker again than mixing encoded values")


## A mode that names the space the document already stores must be the identity
## pair, not a round trip that loses a last bit. This is what makes the bracket on
## plain Normal's label true rather than approximately true.
func test_naming_the_space_the_document_stores_changes_nothing() -> void:
    var pairs := [
        [SaColorSpace.srgb(), "composite_srgb"],
        [SaColorSpace.linear_srgb(), "composite_linear"],
        [SaColorSpace.oklab(), "composite_oklab"],
    ]
    var src := Color(0.62, 0.31, 0.85, 0.5)
    var dst := Color(0.2, 0.7, 0.45, 1.0)

    for pair: Array in pairs:
        var space: SaColorSpace = pair[0]
        var named: Color = _blend(space, pair[1], src, dst)
        var plain: Color = _blend(space, "composite", src, dst)
        assert_almost_eq(named.r, plain.r, 1e-5, "%s on its own document is plain Normal" % pair[1])
        assert_almost_eq(named.g, plain.g, 1e-5, "on green")
        assert_almost_eq(named.b, plain.b, 1e-5, "and on blue")


## And on a document storing something else they must not agree, or the previous
## test would pass for a kernel that ignored its space entirely.
func test_naming_a_different_space_really_converts() -> void:
    var oklab := SaColorSpace.oklab()
    var white := oklab.from_display(Color(1.0, 1.0, 1.0, 0.5))
    var black := oklab.from_display(Color(0.0, 0.0, 0.0, 1.0))

    var perceptual := oklab.to_display(_blend(oklab, "composite", white, black))
    var encoded := oklab.to_display(_blend(oklab, "composite_srgb", white, black))

    assert_almost_eq(encoded.r, 0.5, 2e-3, "Normal (sRGB) on an Oklab document still mixes encoded RGB")
    assert_true(encoded.r - perceptual.r > 0.05, "while that document's plain Normal mixes perceptually")
