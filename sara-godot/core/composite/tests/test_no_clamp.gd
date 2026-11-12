## The no-clamp invariant: nothing between a paint dab and an export clamps a value.
##
## Float storage already preserves negatives and values above 1.0. What this
## suite proves is that nothing *between* storage and storage throws them away:
## paint -> composite -> export -> read back has to be bit-exact, or Sara cannot
## honestly claim to open an ACEScg render, paint an out-of-gamut colour into it
## and give the file back intact.
##
## Every expected value here is an exact binary fraction, so `==` is the right
## comparison and `assert_almost_eq` would be hiding the very thing under test.
##
## Nothing built on the float pipeline ships until this suite passes.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const PaintKernel = preload("res://tests/fixtures/paint_kernel.gd")

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true

const CHUNK := SaChunk.SIZE
static var scratch_exr_path: String = SaDataRoot.path("test_no_clamp.exr")

## Values a clamp would destroy, each exactly representable in F32 so a
## round-trip can be compared with `==` rather than an epsilon.
const NEGATIVE := -0.25
const ABOVE_ONE := 2.5
const FAR_ABOVE_ONE := 1234.5
const FAR_BELOW_ZERO := -7.75


func after_each() -> void:
    if FileAccess.file_exists(scratch_exr_path):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch_exr_path))


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


## A chunk-sized RGBA32F texture with every texel set to *color*, written from
## the CPU so the starting values are exact by construction.
func _make_texture(color: Color) -> SaTexture:
    var texture := SaTexture.new(Vector2i(CHUNK, CHUNK))
    var texels := PackedFloat32Array()
    texels.resize(CHUNK * CHUNK * 4)
    for i in CHUNK * CHUNK:
        texels[i * 4 + 0] = color.r
        texels[i * 4 + 1] = color.g
        texels[i * 4 + 2] = color.b
        texels[i * 4 + 3] = color.a
    texture.rd.texture_update(texture.rid, 0, texels.to_byte_array())
    return texture


## Reads one texel straight off the GPU, bypassing every export path, so a
## failure can be pinned on the compositor rather than on the readback.
func _read_texel(texture: SaTexture, x: int, y: int) -> Color:
    @warning_ignore("static_called_on_instance")
    var img := SaExport.get_texture_image_float(texture)
    return img.get_pixel(x, y) if img != null else Color(NAN, NAN, NAN, NAN)


## Bit-exact. The pass-through path does no arithmetic on the value, so anything
## other than equality is a clamp or a narrowing.
func _assert_channel(actual: float, expected: float, what: String) -> void:
    assert_true(
        actual == expected,
        "%s must survive the path unchanged: expected %s, got %s" % [what, String.num(expected, 17), String.num(actual, 17)]
    )


## For a value that has been through Oklab. The cube roots and the sRGB transfer
## curve are lossy in float, so exactness is not available here and demanding it
## would be testing the arithmetic rather than the invariant. What must hold is
## that the magnitude survives instead of being crushed into [0, 1].
func _assert_channel_near(actual: float, expected: float, what: String, epsilon: float = 1e-3) -> void:
    assert_true(
        absf(actual - expected) <= epsilon,
        (
            "%s must survive the path: expected %s +/- %s, got %s"
            % [what, String.num(expected, 9), String.num(epsilon, 9), String.num(actual, 9)]
        )
    )


func _assert_finite(value: float, what: String) -> void:
    assert_true(is_finite(value), "%s must stay finite, got %s" % [what, String.num(value, 9)])


## A compositor that resolves the full built-in blend-mode set, which a bare
## SaCompositor does not, it falls back to Normal for every name.
func _make_compositor() -> Array:
    var registries := Fixtures.make_registries()
    var comp := SaCompositor.new()
    comp.set_registry(registries.blend_modes)
    # The registries are returned so the caller can hold them: dropping them
    # takes the descriptors, and the compositor resolves through those.
    return [comp, registries]


# ---------------------------------------------------------------------------
# The export container
# ---------------------------------------------------------------------------


func test_exr_round_trips_out_of_range_values() -> void:
    var img := Image.create_empty(2, 2, false, Image.FORMAT_RGBAF)
    var expected := [
        Color(NEGATIVE, ABOVE_ONE, -0.001953125, 1.0),
        Color(FAR_ABOVE_ONE, FAR_BELOW_ZERO, 0.5, 0.25),
        Color(0.0, 1.0, -0.0, 0.0),
        Color(65504.0, -65504.0, 3.4028235e38, 1.0),
    ]
    for i in 4:
        # A 2x2 grid: i / 2 is the row and i % 2 the column, both exact.
        @warning_ignore("integer_division")
        var row := i / 2
        img.set_pixel(i % 2, row, expected[i])

    assert_eq(img.save_exr(scratch_exr_path, false), OK, "EXR must be writable at runtime, not only in the editor")

    var back := Image.load_from_file(scratch_exr_path)
    assert_not_null(back, "The EXR we just wrote must load back")
    assert_eq(back.get_format(), Image.FORMAT_RGBAF, "EXR must come back as 32-bit float, not half or 8-bit")

    for i in 4:
        var want: Color = expected[i]
        @warning_ignore("integer_division")
        var row := i / 2
        var got := back.get_pixel(i % 2, row)
        _assert_channel(got.r, want.r, "EXR texel %d red" % i)
        _assert_channel(got.g, want.g, "EXR texel %d green" % i)
        _assert_channel(got.b, want.b, "EXR texel %d blue" % i)
        _assert_channel(got.a, want.a, "EXR texel %d alpha" % i)


func test_png_export_still_narrows_deliberately() -> void:
    # Not a bug, and worth pinning: PNG is an 8-bit container, so it clamps by
    # definition. The point of export_exr is that it is the path that does not.
    var img := Image.create_empty(1, 1, false, Image.FORMAT_RGBAF)
    img.set_pixel(0, 0, Color(NEGATIVE, ABOVE_ONE, 0.5, 1.0))
    img.convert(Image.FORMAT_RGBA8)
    var narrowed := img.get_pixel(0, 0)
    assert_true(narrowed.r >= 0.0 and narrowed.g <= 1.0, "RGBA8 clamps, which is why EXR exists")


# ---------------------------------------------------------------------------
# Composite, in isolation from the export
# ---------------------------------------------------------------------------


func test_normal_composite_preserves_out_of_range() -> void:
    var canvas := SaTexture.new(Vector2i(CHUNK, CHUNK))
    canvas.clear(Color.TRANSPARENT)
    var source := _make_texture(Color(NEGATIVE, ABOVE_ONE, FAR_ABOVE_ONE, 1.0))

    var comp := SaCompositor.new()
    comp.composite_chunk(canvas, source, SaLayer.BLEND_MODE.NORMAL, 1.0, Vector2.ZERO)

    var got := _read_texel(canvas, 3, 7)
    _assert_channel(got.r, NEGATIVE, "A negative channel through Normal")
    _assert_channel(got.g, ABOVE_ONE, "A channel above 1.0 through Normal")
    _assert_channel(got.b, FAR_ABOVE_ONE, "A channel far above 1.0 through Normal")
    _assert_channel(got.a, 1.0, "Alpha through Normal")


func test_arithmetic_safe_modes_run_unrestricted() -> void:
    # color-management.md classifies Normal, add, multiply, difference, darken
    # and lighten as arithmetic-safe: "These run unrestricted." A clamp inside
    # one of them is a no-clamp violation, not a mode definition.
    var pair := _make_compositor()
    var comp: SaCompositor = pair[0]
    var registries: SaRegistries = pair[1]

    var canvas := SaTexture.new(Vector2i(CHUNK, CHUNK))
    canvas.clear(Color.TRANSPARENT)
    comp.composite_chunk(canvas, _make_texture(Color(0.75, 0.5, 0.25, 1.0)), SaLayer.BLEND_MODE.NORMAL, 1.0, Vector2.ZERO)
    comp.composite_chunk(canvas, _make_texture(Color(0.75, 2.0, 0.25, 1.0)), &"add", 1.0, Vector2.ZERO)

    var got := _read_texel(canvas, 1, 1)
    _assert_channel(got.r, 1.5, "add of 0.75 over 0.75")
    _assert_channel(got.g, 2.5, "add of 2.0 over 0.5")
    assert_true(registries != null, "registries held for the duration of the composite")


func test_multiply_of_negative_keeps_its_sign() -> void:
    var pair := _make_compositor()
    var comp: SaCompositor = pair[0]
    var registries: SaRegistries = pair[1]

    var canvas := SaTexture.new(Vector2i(CHUNK, CHUNK))
    canvas.clear(Color.TRANSPARENT)
    comp.composite_chunk(canvas, _make_texture(Color(NEGATIVE, 2.0, 1.0, 1.0)), SaLayer.BLEND_MODE.NORMAL, 1.0, Vector2.ZERO)
    comp.composite_chunk(canvas, _make_texture(Color(2.0, 2.0, 1.0, 1.0)), &"multiply", 1.0, Vector2.ZERO)

    var got := _read_texel(canvas, 5, 5)
    _assert_channel(got.r, -0.5, "multiply must not clamp a negative product")
    _assert_channel(got.g, 4.0, "multiply must not clamp a product above 1.0")
    assert_true(registries != null, "registries held for the duration of the composite")


# ---------------------------------------------------------------------------
# The Oklab family, the main offender
# ---------------------------------------------------------------------------


func test_oklab_gamut_mapping_touches_only_chroma() -> void:
    # An achromatic backdrop has no chroma to map, so gamut mapping has nothing
    # to do and must be a no-op. Anything the result loses here was taken by a
    # clamp on lightness or on the final RGB, which is exactly what the rule
    # forbids: the mapping may touch the blend result's chroma and nothing else.
    var pair := _make_compositor()
    var comp: SaCompositor = pair[0]
    var registries: SaRegistries = pair[1]

    var canvas := SaTexture.new(Vector2i(CHUNK, CHUNK))
    canvas.clear(Color.TRANSPARENT)
    var grey := Color(ABOVE_ONE, ABOVE_ONE, ABOVE_ONE, 1.0)
    comp.composite_chunk(canvas, _make_texture(grey), SaLayer.BLEND_MODE.NORMAL, 1.0, Vector2.ZERO)
    # Hue mode takes the backdrop's lightness and chroma, and only the source's
    # hue. The backdrop is achromatic, so the result must still be that grey.
    comp.composite_chunk(canvas, _make_texture(Color(0.2, 0.6, 0.9, 1.0)), &"hue", 1.0, Vector2.ZERO)

    var got := _read_texel(canvas, 9, 9)
    _assert_channel_near(got.r, ABOVE_ONE, "Hue over an achromatic HDR backdrop, red")
    _assert_channel_near(got.g, ABOVE_ONE, "Hue over an achromatic HDR backdrop, green")
    _assert_channel_near(got.b, ABOVE_ONE, "Hue over an achromatic HDR backdrop, blue")
    # Stated separately because it is the failure that actually matters: a clamp
    # lands the result exactly on 1.0, which an epsilon comparison alone reports
    # as "slightly off" rather than as the whole magnitude having been discarded.
    assert_true(got.r > 1.0, "A clamp to the sRGB cube would have pinned this at 1.0")
    assert_true(registries != null, "registries held for the duration of the composite")


func test_oklab_modes_never_produce_nan_from_negatives() -> void:
    # The sRGB transfer pair is a `pow`, which is undefined for a negative base.
    # A NaN is a worse outcome than a clamp: it spreads through every later
    # blend and cannot be undone.
    var pair := _make_compositor()
    var comp: SaCompositor = pair[0]
    var registries: SaRegistries = pair[1]

    for mode: StringName in [&"hue", &"saturation", &"lightness", &"color"]:
        var canvas := SaTexture.new(Vector2i(CHUNK, CHUNK))
        canvas.clear(Color.TRANSPARENT)
        comp.composite_chunk(
            canvas, _make_texture(Color(NEGATIVE, 0.5, FAR_BELOW_ZERO, 1.0)), SaLayer.BLEND_MODE.NORMAL, 1.0, Vector2.ZERO
        )
        comp.composite_chunk(canvas, _make_texture(Color(NEGATIVE, 0.75, 0.5, 1.0)), mode, 1.0, Vector2.ZERO)

        var got := _read_texel(canvas, 2, 2)
        _assert_finite(got.r, "%s red over a negative backdrop" % mode)
        _assert_finite(got.g, "%s green over a negative backdrop" % mode)
        _assert_finite(got.b, "%s blue over a negative backdrop" % mode)
    assert_true(registries != null, "registries held for the duration of the composite")


# ---------------------------------------------------------------------------
# The whole path, end to end
# ---------------------------------------------------------------------------


func test_paint_composite_export_exr_is_bit_exact() -> void:
    # The headline test of the invariant: a real paint dab through the real
    # paint kernel, a real composite, a real EXR on disk, read back and compared
    # bit for bit.
    var easel := SaEasel.create_default(Vector2i(CHUNK, CHUNK))
    var document := easel.document
    var layer := document.active_layer

    var grid_pos := Vector2i.ZERO
    var target := layer.get_or_create_field(grid_pos)

    # A fully opaque, full-flow dab at hardness 1: at the exact centre texel the
    # paint kernel's coverage is 1.0, so the stored colour is the brush colour
    # with no interpolation to blunt the comparison.
    var brush := Color(NEGATIVE, ABOVE_ONE, FAR_ABOVE_ONE, 1.0)
    var centre := Vector2i(64, 64)
    var paint := PaintKernel.compute()
    paint.set_texture(0, target.rid)
    # The paint kernel binds the selection mask too. A 1 by 1 mask is "no
    # selection", and it reads as full coverage everywhere.
    var mask := SaTexture.new(Vector2i(1, 1), SaSelection.FORMAT)
    mask.clear(Color(1.0, 1.0, 1.0, 1.0))
    paint.set_texture(SaSelection.BINDING, mask.rid)
    (
        paint
        . set_push_constant_float_array(
            PackedFloat32Array(
                [
                    float(centre.x),
                    float(centre.y),  # brush_pos
                    0.0,
                    0.0,  # offset
                    brush.r,
                    brush.g,
                    brush.b,
                    brush.a,  # color
                    16.0,  # radius
                    1.0,  # hardness
                    1.0,  # hardness_gamma
                    1.0,  # flow
                    0.0,  # mode: paint, not erase
                    0.0,  # alpha_lock off
                    0.0,
                    0.0,  # padding
                ]
            )
        )
    )
    # Exact: the chunk size and the workgroup are both powers of two.
    @warning_ignore("integer_division")
    var groups := CHUNK / 8
    paint.dispatch_kernel("paint", groups, groups, 1)

    document.invalidate_chunks([grid_pos])
    easel.process_pending_composite()

    # Straight off the GPU first, so an export failure is distinguishable from a
    # composite failure.
    var composited := _read_texel(easel.output, centre.x, centre.y)
    _assert_channel(composited.r, brush.r, "Composited red before export")
    _assert_channel(composited.g, brush.g, "Composited green before export")
    _assert_channel(composited.b, brush.b, "Composited blue before export")

    assert_eq(SaExport.export_exr_texture(easel.output, scratch_exr_path), OK, "The EXR must be written")

    var back := Image.load_from_file(scratch_exr_path)
    assert_not_null(back, "The exported EXR must load back")
    var got := back.get_pixel(centre.x, centre.y)
    _assert_channel(got.r, brush.r, "Exported red after the full paint -> composite -> EXR path")
    _assert_channel(got.g, brush.g, "Exported green after the full paint -> composite -> EXR path")
    _assert_channel(got.b, brush.b, "Exported blue after the full paint -> composite -> EXR path")
    _assert_channel(got.a, 1.0, "Exported alpha after the full paint -> composite -> EXR path")

    easel.free()
