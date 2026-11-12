## The colour space helpers a filter reaches through its context.
##
## A filter meets the document's space, whatever that is, so the assertions here
## are round trips: convert out, convert back, and read the numbers that came
## home. They are read through `SaExport`, which is the one readback hard rule 1
## permits a test, and the helpers themselves never read a texel.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const SaExportScript = preload("res://core/export/sa_export.gd")

## An Oklab value with a real chroma and a negative b, so a round trip that
## clamped or dropped a sign would show it.
const OKLAB_VALUE := Color(0.62, 0.08, -0.11, 1.0)

## A mid grey in whatever space the document stores, for the identity cases.
const GREY := Color(0.5, 0.5, 0.5, 1.0)

var _easel: SaEasel = null


func after_each() -> void:
    if _easel != null:
        _easel.free()
        _easel = null


## A context on a fresh document in *space*, with one painted chunk so the
## helpers have a layer to belong to.
func _context(space: SaColorSpace) -> SaFilterContext:
    _easel = SaEasel.create_default(Vector2i(512, 512), null, space)
    var layer := _easel.document.active_layer
    layer.get_or_create_chunk(Vector2i(0, 0))
    return SaFilterContext.new(_easel.document, layer)


## A small texture of one flat value, at the document's depth.
func _flat(ctx: SaFilterContext, value: Color) -> SaTexture:
    var texture := ctx.blank_like(ctx.layer_pixels(0))
    texture.clear(value)
    return texture


func _texel(texture: SaTexture) -> Color:
    return SaExportScript.get_texture_image_float(texture).get_pixel(4, 4)


func _assert_round_trip(was: Color, now: Color, what: String) -> void:
    assert_almost_eq(now.r, was.r, 1e-3, "%s comes home in the first channel" % what)
    assert_almost_eq(now.g, was.g, 1e-3, "and in the second")
    assert_almost_eq(now.b, was.b, 1e-3, "and in the third")
    assert_almost_eq(now.a, was.a, 1e-6, "with alpha untouched, because alpha is coverage")


# ---------------------------------------------------------------------------
# What the document is
# ---------------------------------------------------------------------------


func test_the_context_says_what_space_its_pixels_are_in() -> void:
    assert_eq(_context(SaColorSpace.oklab()).color_space(), "Oklab over sRGB", "An Oklab document says which gamut it carries")
    after_each()
    assert_eq(_context(SaColorSpace.srgb()).color_space(), "sRGB", "and an sRGB one says sRGB")


# ---------------------------------------------------------------------------
# The round trip
# ---------------------------------------------------------------------------


func test_an_oklab_texture_survives_a_trip_through_srgb() -> void:
    var ctx := _context(SaColorSpace.oklab())
    var source := _flat(ctx, OKLAB_VALUE)

    var home := ctx.from_srgb(ctx.to_srgb(source))

    _assert_round_trip(OKLAB_VALUE, _texel(home), "An Oklab value")


func test_the_trip_through_srgb_really_moves_the_numbers() -> void:
    var ctx := _context(SaColorSpace.oklab())
    var source := _flat(ctx, OKLAB_VALUE)

    var encoded := _texel(ctx.to_srgb(source))

    # Without this the round trip above would pass on a to_srgb that did
    # nothing at all, which is exactly the bug it is there to catch.
    assert_true(absf(encoded.r - OKLAB_VALUE.r) > 0.01, "Oklab lightness is not an sRGB red")
    assert_true(absf(encoded.b - OKLAB_VALUE.b) > 0.01, "and Oklab b is not an sRGB blue")


func test_an_oklab_texture_survives_a_trip_through_linear_light() -> void:
    var ctx := _context(SaColorSpace.oklab())
    var source := _flat(ctx, OKLAB_VALUE)

    var home := ctx.from_linear(ctx.to_linear(source))

    _assert_round_trip(OKLAB_VALUE, _texel(home), "An Oklab value through linear light")


# ---------------------------------------------------------------------------
# The identity, and what linear means
# ---------------------------------------------------------------------------


func test_to_srgb_on_an_srgb_document_is_the_identity() -> void:
    var ctx := _context(SaColorSpace.srgb())
    var source := _flat(ctx, GREY)

    var converted := ctx.to_srgb(source)

    _assert_round_trip(GREY, _texel(converted), "A document already in sRGB")


func test_the_identity_still_answers_a_texture_of_its_own() -> void:
    var ctx := _context(SaColorSpace.srgb())
    var source := _flat(ctx, GREY)

    var converted := ctx.to_srgb(source)
    converted.clear(Color(0.0, 0.0, 0.0, 1.0))

    assert_true(converted != source, "The answer is never the texture that was handed in")
    assert_almost_eq(_texel(source).r, GREY.r, 1e-4, "so writing to it does not write to the source")


func test_to_linear_decodes_the_srgb_curve() -> void:
    var ctx := _context(SaColorSpace.srgb())
    var source := _flat(ctx, GREY)

    var linear := _texel(ctx.to_linear(source))

    # 0.5 through the sRGB decode is 0.21404, which is the one number that says
    # this went through the transfer curve rather than through a copy.
    assert_almost_eq(linear.r, 0.21404, 1e-3, "Mid grey in sRGB is a fifth of the light")
    assert_almost_eq(linear.a, 1.0, 1e-6, "and alpha is not light, so it is left alone")


func test_a_conversion_without_a_texture_is_refused() -> void:
    var ctx := _context(SaColorSpace.srgb())

    SaProblems.announce = false
    var answer := ctx.to_srgb(null)
    SaProblems.announce = true

    assert_true(answer == null, "Nothing in is nothing out, said once rather than crashed on")
