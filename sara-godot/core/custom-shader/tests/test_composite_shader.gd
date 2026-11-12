## GPU integration tests for composite compute shader.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true


func test_composite_shader_execution() -> void:
    var rd := GlobalShaderCompiler.get_rd()
    assert_not_null(rd, "RenderingDevice should be available")

    # Create 64x64 destination canvas (transparent)
    var canvas_tex := SaTexture.new(Vector2i(64, 64))
    rd.texture_clear(canvas_tex.rid, Color(0, 0, 0, 0), 0, 1, 0, 1)

    # Create 64x64 source chunk (solid red)
    var chunk_tex := SaTexture.new(Vector2i(64, 64))
    rd.texture_clear(chunk_tex.rid, Color(1, 0, 0, 1), 0, 1, 0, 1)

    var comp := SaCompute.new("composite")
    comp.set_texture(0, canvas_tex.rid)
    comp.set_texture(1, chunk_tex.rid)

    # Composite with 0.5 opacity at offset (0, 0)
    var params := SaCompute.pack_composite_params(Vector2(0, 0), 0.5)
    comp.set_push_constant_float_array(params)

    # Dispatch 8x8 groups (since 64/8 = 8)
    comp.dispatch_kernel("composite", 8, 8, 1)

    # Read back pixel data
    var data: PackedByteArray = rd.texture_get_data(canvas_tex.rid, 0)
    assert_true(data.size() >= 16, "Texture data should have at least 16 bytes for pixel (0,0)")

    if data.size() >= 16:
        var r: float = data.decode_float(0)
        var g: float = data.decode_float(4)
        var b: float = data.decode_float(8)
        var a: float = data.decode_float(12)

        assert_almost_eq(r, 1.0, 0.01, "Red channel should be ~1.0")
        assert_almost_eq(g, 0.0, 0.01, "Green channel should be ~0.0")
        assert_almost_eq(b, 0.0, 0.01, "Blue channel should be ~0.0")
        assert_almost_eq(a, 0.5, 0.01, "Alpha channel should be ~0.5")


func test_multiply_mode() -> void:
    var rd := GlobalShaderCompiler.get_rd()
    var canvas_tex := SaTexture.new(Vector2i(64, 64))
    rd.texture_clear(canvas_tex.rid, Color(0.5, 0.8, 1.0, 1.0), 0, 1, 0, 1)

    var chunk_tex := SaTexture.new(Vector2i(64, 64))
    rd.texture_clear(chunk_tex.rid, Color(0.5, 0.5, 0.5, 1.0), 0, 1, 0, 1)

    var comp := SaCompute.new("composite")
    comp.set_texture(0, canvas_tex.rid)
    comp.set_texture(1, chunk_tex.rid)
    comp.set_push_constant_float_array(SaCompute.pack_composite_params(Vector2.ZERO, 1.0))
    comp.dispatch_kernel("multiply", 8, 8, 1)

    var data: PackedByteArray = rd.texture_get_data(canvas_tex.rid, 0)
    if data.size() >= 16:
        assert_almost_eq(data.decode_float(0), 0.25, 0.01, "Multiply Red")
        assert_almost_eq(data.decode_float(4), 0.40, 0.01, "Multiply Green")
        assert_almost_eq(data.decode_float(8), 0.50, 0.01, "Multiply Blue")


func test_screen_mode() -> void:
    var rd := GlobalShaderCompiler.get_rd()
    var canvas_tex := SaTexture.new(Vector2i(64, 64))
    rd.texture_clear(canvas_tex.rid, Color(0.5, 0.5, 0.5, 1.0), 0, 1, 0, 1)

    var chunk_tex := SaTexture.new(Vector2i(64, 64))
    rd.texture_clear(chunk_tex.rid, Color(0.5, 0.5, 0.5, 1.0), 0, 1, 0, 1)

    var comp := SaCompute.new("composite")
    comp.set_texture(0, canvas_tex.rid)
    comp.set_texture(1, chunk_tex.rid)
    comp.set_push_constant_float_array(SaCompute.pack_composite_params(Vector2.ZERO, 1.0))
    comp.dispatch_kernel("screen", 8, 8, 1)

    var data: PackedByteArray = rd.texture_get_data(canvas_tex.rid, 0)
    if data.size() >= 16:
        assert_almost_eq(data.decode_float(0), 0.75, 0.01, "Screen Red")
        assert_almost_eq(data.decode_float(4), 0.75, 0.01, "Screen Green")
        assert_almost_eq(data.decode_float(8), 0.75, 0.01, "Screen Blue")


func test_overlay_mode() -> void:
    var rd := GlobalShaderCompiler.get_rd()
    var canvas_tex := SaTexture.new(Vector2i(64, 64))
    rd.texture_clear(canvas_tex.rid, Color(0.2, 0.8, 0.5, 1.0), 0, 1, 0, 1)

    var chunk_tex := SaTexture.new(Vector2i(64, 64))
    rd.texture_clear(chunk_tex.rid, Color(0.5, 0.5, 0.5, 1.0), 0, 1, 0, 1)

    var comp := SaCompute.new("composite")
    comp.set_texture(0, canvas_tex.rid)
    comp.set_texture(1, chunk_tex.rid)
    comp.set_push_constant_float_array(SaCompute.pack_composite_params(Vector2.ZERO, 1.0))
    comp.dispatch_kernel("overlay", 8, 8, 1)

    var data: PackedByteArray = rd.texture_get_data(canvas_tex.rid, 0)
    if data.size() >= 16:
        assert_almost_eq(data.decode_float(0), 0.2, 0.01, "Overlay Red (dst <= 0.5)")
        assert_almost_eq(data.decode_float(4), 0.8, 0.01, "Overlay Green (dst > 0.5)")
        assert_almost_eq(data.decode_float(8), 0.5, 0.01, "Overlay Blue (dst == 0.5)")


func test_add_mode() -> void:
    var rd := GlobalShaderCompiler.get_rd()
    var canvas_tex := SaTexture.new(Vector2i(64, 64))
    rd.texture_clear(canvas_tex.rid, Color(0.6, 0.3, 0.1, 1.0), 0, 1, 0, 1)

    var chunk_tex := SaTexture.new(Vector2i(64, 64))
    rd.texture_clear(chunk_tex.rid, Color(0.5, 0.4, 0.9, 1.0), 0, 1, 0, 1)

    var comp := SaCompute.new("composite")
    comp.set_texture(0, canvas_tex.rid)
    comp.set_texture(1, chunk_tex.rid)
    comp.set_push_constant_float_array(SaCompute.pack_composite_params(Vector2.ZERO, 1.0))
    comp.dispatch_kernel("add", 8, 8, 1)

    var data: PackedByteArray = rd.texture_get_data(canvas_tex.rid, 0)
    if data.size() >= 16:
        # Add is arithmetic-safe, so it sums without a ceiling: 0.6 + 0.5 is 1.1
        # and stays 1.1. This used to assert 1.0, pinning a min() in the kernel
        # that discarded the headroom a float canvas exists to hold. See
        # core/composite/tests/test_no_clamp.gd.
        assert_almost_eq(data.decode_float(0), 1.1, 0.01, "Add Red, above 1.0 and kept")
        assert_almost_eq(data.decode_float(4), 0.7, 0.01, "Add Green")
        assert_almost_eq(data.decode_float(8), 1.0, 0.01, "Add Blue")


## Dispatches one composite kernel over a 64x64 pair of solid textures and
## returns the resulting pixel. Keeps the many blend-mode cases below readable.
func _blend(kernel: String, backdrop: Color, source: Color) -> Color:
    var rd := GlobalShaderCompiler.get_rd()
    var canvas_tex := SaTexture.new(Vector2i(64, 64))
    rd.texture_clear(canvas_tex.rid, backdrop, 0, 1, 0, 1)

    var chunk_tex := SaTexture.new(Vector2i(64, 64))
    rd.texture_clear(chunk_tex.rid, source, 0, 1, 0, 1)

    var comp := SaCompute.new("composite")
    comp.set_texture(0, canvas_tex.rid)
    comp.set_texture(1, chunk_tex.rid)
    comp.set_push_constant_float_array(SaCompute.pack_composite_params(Vector2.ZERO, 1.0))
    comp.dispatch(comp.index_of_kernel(kernel), 8, 8, 1)

    var data: PackedByteArray = rd.texture_get_data(canvas_tex.rid, 0)
    assert_true(data.size() >= 16, "Composite output should contain pixel (0,0)")
    if data.size() < 16:
        return Color(0, 0, 0, 0)
    return Color(data.decode_float(0), data.decode_float(4), data.decode_float(8), data.decode_float(12))


func test_color_dodge_mode() -> void:
    # Blue channel checks the W3C rule that a black backdrop stays black.
    var out := _blend("color_dodge", Color(0.25, 0.5, 0.0, 1.0), Color(0.5, 0.0, 0.5, 1.0))
    assert_almost_eq(out.r, 0.5, 0.01, "Color dodge Red (0.25 / (1 - 0.5))")
    assert_almost_eq(out.g, 0.5, 0.01, "Color dodge Green (source 0 leaves backdrop)")
    assert_almost_eq(out.b, 0.0, 0.01, "Color dodge Blue (black backdrop stays black)")


func test_darken_and_lighten_modes() -> void:
    var backdrop := Color(0.2, 0.8, 0.5, 1.0)
    var source := Color(0.6, 0.3, 0.5, 1.0)

    var dark := _blend("darken", backdrop, source)
    assert_almost_eq(dark.r, 0.2, 0.01, "Darken Red")
    assert_almost_eq(dark.g, 0.3, 0.01, "Darken Green")
    assert_almost_eq(dark.b, 0.5, 0.01, "Darken Blue (equal channels)")

    var light := _blend("lighten", backdrop, source)
    assert_almost_eq(light.r, 0.6, 0.01, "Lighten Red")
    assert_almost_eq(light.g, 0.8, 0.01, "Lighten Green")
    assert_almost_eq(light.b, 0.5, 0.01, "Lighten Blue (equal channels)")


func test_soft_light_mode() -> void:
    var out := _blend("soft_light", Color(0.25, 0.64, 0.5, 1.0), Color(0.25, 0.75, 0.5, 1.0))
    assert_almost_eq(out.r, 0.15625, 0.01, "Soft light Red (source below 0.5 darkens)")
    assert_almost_eq(out.g, 0.72, 0.01, "Soft light Green (source above 0.5 lightens towards sqrt)")
    assert_almost_eq(out.b, 0.5, 0.01, "Soft light Blue (source at 0.5 is a no-op)")


func test_hard_light_mode() -> void:
    var out := _blend("hard_light", Color(0.2, 0.8, 0.5, 1.0), Color(0.25, 0.75, 0.5, 1.0))
    assert_almost_eq(out.r, 0.1, 0.01, "Hard light Red (source below 0.5 multiplies)")
    assert_almost_eq(out.g, 0.9, 0.01, "Hard light Green (source above 0.5 screens)")
    assert_almost_eq(out.b, 0.5, 0.01, "Hard light Blue")


func test_difference_and_exclusion_modes() -> void:
    var backdrop := Color(0.2, 0.8, 0.5, 1.0)
    var source := Color(0.6, 0.3, 0.5, 1.0)

    var diff := _blend("difference", backdrop, source)
    assert_almost_eq(diff.r, 0.4, 0.01, "Difference Red")
    assert_almost_eq(diff.g, 0.5, 0.01, "Difference Green")
    assert_almost_eq(diff.b, 0.0, 0.01, "Difference Blue (equal channels cancel)")

    var excl := _blend("exclusion", backdrop, source)
    assert_almost_eq(excl.r, 0.56, 0.01, "Exclusion Red")
    assert_almost_eq(excl.g, 0.62, 0.01, "Exclusion Green")
    assert_almost_eq(excl.b, 0.5, 0.01, "Exclusion Blue")


## Signed Add reads the colour on top as a change from middle grey, so grey
## leaves the backdrop alone, and a sum past white or under black is kept
## rather than clamped, as Add keeps it.
func test_signed_add_mode() -> void:
    var out := _blend("signed_add", Color(0.2, 0.8, 0.3, 1.0), Color(0.5, 0.75, 0.0, 1.0))
    assert_almost_eq(out.r, 0.2, 0.001, "Signed add Red (grey on top changes nothing)")
    assert_almost_eq(out.g, 1.05, 0.001, "Signed add Green (lighter lightens, past white)")
    assert_almost_eq(out.b, -0.2, 0.001, "Signed add Blue (darker darkens, under black)")


## Guards oklab_to_linear_srgb(): its matrices were transposed and wrong, which
## made the Oklab round trip inside the non-separable modes return garbage.
## Blending a colour against itself in 'color' mode must be the identity.
func test_oklab_roundtrip_is_identity() -> void:
    var original := Color(0.8, 0.35, 0.15, 1.0)
    var out := _blend("color", original, original)
    assert_almost_eq(out.r, original.r, 0.005, "Oklab round trip Red")
    assert_almost_eq(out.g, original.g, 0.005, "Oklab round trip Green")
    assert_almost_eq(out.b, original.b, 0.005, "Oklab round trip Blue")


## An achromatic backdrop carries no chroma or hue, so 'lightness' must return
## the source grey exactly. A broken Oklab inverse cannot satisfy this.
func test_lightness_mode_takes_source_lightness() -> void:
    var out := _blend("lightness", Color(0.3, 0.3, 0.3, 1.0), Color(0.7, 0.7, 0.7, 1.0))
    assert_almost_eq(out.r, 0.7, 0.005, "Lightness Red takes the source grey")
    assert_almost_eq(out.g, 0.7, 0.005, "Lightness Green takes the source grey")
    assert_almost_eq(out.b, 0.7, 0.005, "Lightness Blue takes the source grey")


## An achromatic source has zero chroma, so 'saturation' must desaturate the
## backdrop while holding its lightness.
func test_saturation_mode_desaturates_with_grey_source() -> void:
    var out := _blend("saturation", Color(0.2, 0.4, 0.8, 1.0), Color(0.5, 0.5, 0.5, 1.0))
    assert_almost_eq(out.g, out.r, 0.005, "Saturation output should be achromatic (R == G)")
    assert_almost_eq(out.b, out.r, 0.005, "Saturation output should be achromatic (R == B)")


## 'hue' keeps the backdrop's lightness and chroma, so a grey backdrop has no
## chroma to re-tint and must survive unchanged whatever the source hue is.
func test_hue_mode_leaves_grey_backdrop_grey() -> void:
    var out := _blend("hue", Color(0.45, 0.45, 0.45, 1.0), Color(0.9, 0.1, 0.2, 1.0))
    assert_almost_eq(out.r, 0.45, 0.005, "Hue Red on a grey backdrop")
    assert_almost_eq(out.g, 0.45, 0.005, "Hue Green on a grey backdrop")
    assert_almost_eq(out.b, 0.45, 0.005, "Hue Blue on a grey backdrop")


## Erase is destination-out: it carves alpha and must leave backdrop colour alone.
func test_erase_mode_carves_alpha() -> void:
    var out := _blend("erase", Color(0.3, 0.6, 0.9, 1.0), Color(1.0, 1.0, 1.0, 0.25))
    assert_almost_eq(out.a, 0.75, 0.01, "Erase should reduce backdrop alpha by the source alpha")
    assert_almost_eq(out.r, 0.3, 0.01, "Erase should preserve backdrop Red")
    assert_almost_eq(out.g, 0.6, 0.01, "Erase should preserve backdrop Green")
    assert_almost_eq(out.b, 0.9, 0.01, "Erase should preserve backdrop Blue")


## Runs one composite kernel over a single 8x8 workgroup and returns the RGB it
## wrote. The colour space is the whole point: it reaches the kernel through the
## push constant rather than through a generated include.
func _blend_with_space(kernel_name: String, backdrop: Color, source: Color, space: SaColorSpace) -> Vector3:
    var rd := GlobalShaderCompiler.get_rd()
    var canvas_tex := SaTexture.new(Vector2i(8, 8))
    rd.texture_clear(canvas_tex.rid, backdrop, 0, 1, 0, 1)
    var chunk_tex := SaTexture.new(Vector2i(8, 8))
    rd.texture_clear(chunk_tex.rid, source, 0, 1, 0, 1)

    var comp := SaCompute.new("composite")
    comp.set_texture(0, canvas_tex.rid)
    comp.set_texture(1, chunk_tex.rid)
    comp.set_push_constant_float_array(SaCompute.pack_composite_params(Vector2.ZERO, 1.0, space))
    comp.dispatch(GlobalShaderCompiler.get_kernel_index("composite", kernel_name), 1, 1, 1)

    var data: PackedByteArray = rd.texture_get_data(canvas_tex.rid, 0)
    return Vector3(data.decode_float(0), data.decode_float(4), data.decode_float(8))


## The non-separable modes decode through the document's colour space, so the
## same two pixels blended in two different documents must not agree.
##
## Before the descriptor reached the kernel, composite.gmacs read every document
## as gamma sRGB whatever its header said, which is wrong twice over for an
## ACEScg document: the wrong transfer curve and the wrong primaries.
func test_non_separable_modes_follow_the_document_color_space() -> void:
    var backdrop := Color(0.5, 0.5, 0.5, 1.0)
    var source := Color(0.2, 0.6, 0.9, 1.0)

    var as_srgb := _blend_with_space("lightness", backdrop, source, SaColorSpace.srgb())
    var as_linear := _blend_with_space("lightness", backdrop, source, SaColorSpace.linear_srgb())
    var as_acescg := _blend_with_space("lightness", backdrop, source, SaColorSpace.acescg())

    assert_true(as_srgb.distance_to(as_linear) > 0.01, "A linear document must not be decoded with the sRGB curve")
    assert_true(as_srgb.distance_to(as_acescg) > 0.01, "An ACEScg document must not be blended through sRGB primaries")

    # A caller with no document in hand gets the sRGB path exactly, which is what
    # every caller got before documents carried a descriptor at all.
    var as_default := _blend_with_space("lightness", backdrop, source, null)
    assert_almost_eq(as_default.x, as_srgb.x, 0.0, "A null colour space must be the sRGB path bit for bit")
    assert_almost_eq(as_default.y, as_srgb.y, 0.0, "A null colour space must be the sRGB path bit for bit")
    assert_almost_eq(as_default.z, as_srgb.z, 0.0, "A null colour space must be the sRGB path bit for bit")


## The separable modes are arithmetic on stored values and decode nothing, so the
## colour space must not reach them. If this ever fails, a mode was moved onto the
## Oklab path without its formula being reconsidered.
func test_separable_modes_ignore_the_document_color_space() -> void:
    var backdrop := Color(0.5, 0.8, 1.0, 1.0)
    var source := Color(0.5, 0.5, 0.5, 1.0)

    for mode: String in ["multiply", "add", "darken"]:
        var as_srgb := _blend_with_space(mode, backdrop, source, SaColorSpace.srgb())
        var as_acescg := _blend_with_space(mode, backdrop, source, SaColorSpace.acescg())
        assert_almost_eq(as_acescg.x, as_srgb.x, 0.0, "%s must not depend on the document colour space" % mode)
        assert_almost_eq(as_acescg.y, as_srgb.y, 0.0, "%s must not depend on the document colour space" % mode)
        assert_almost_eq(as_acescg.z, as_srgb.z, 0.0, "%s must not depend on the document colour space" % mode)


## Kernel names resolve to the positions the file declares, and a name the file
## does not declare resolves to nothing.
##
## The whole point of naming kernels is that this mapping is derived rather than
## written down, so the assertion is against composite.gmacs itself: its first
## two kernels, the first two formulas of `libs/composite_blend_modes.gmacs`
## that `import kernels_of/...` makes into kernels, and the three space-named
## Normals, which no one counts.
func test_kernels_resolve_by_name_rather_than_by_position() -> void:
    var comp := SaCompute.new("composite")

    assert_eq(comp.index_of_kernel("composite"), 0, "The first #kernel directive is index 0")
    assert_eq(comp.index_of_kernel("multiply"), 1, "The second #kernel directive is index 1")

    for named: String in ["composite_srgb", "composite_linear", "composite_oklab"]:
        assert_true(comp.index_of_kernel(named) > 0, "%s resolves without anyone counting directives" % named)

    assert_eq(comp.index_of_kernel("no_such_kernel"), -1, "A name the shader does not declare resolves to -1")


## An index outside the shader's kernel list submits no work at all.
##
## This is the failure the naming replaces, and it is silent rather than loud: a
## negative index counts from the end in GDScript, so `kernels[-1]` used to bind
## composite_oklab, a real pipeline that really runs and paints a visibly
## different colour. Asserting on the texture rather than on the error message is
## the point, because an error printed after the work was submitted fixes nothing.
##
## Both calls deliberately print one "SaCompute" error each, an expected refusal.
func test_a_kernel_index_outside_the_shader_dispatches_nothing() -> void:
    var rd := GlobalShaderCompiler.get_rd()
    var untouched := Color(0.25, 0.5, 0.75, 1.0)

    var canvas_tex := SaTexture.new(Vector2i(64, 64))
    rd.texture_clear(canvas_tex.rid, untouched, 0, 1, 0, 1)
    var chunk_tex := SaTexture.new(Vector2i(64, 64))
    rd.texture_clear(chunk_tex.rid, Color(1, 0, 0, 1), 0, 1, 0, 1)

    var comp := SaCompute.new("composite")
    comp.set_texture(0, canvas_tex.rid)
    comp.set_texture(1, chunk_tex.rid)
    comp.set_push_constant_float_array(SaCompute.pack_composite_params(Vector2.ZERO, 1.0))

    comp.dispatch(-1, 8, 8, 1)
    var after_negative := rd.texture_get_data(canvas_tex.rid, 0)
    assert_almost_eq(after_negative.decode_float(0), untouched.r, 0.0, "A negative index must not bind the last kernel")
    assert_almost_eq(after_negative.decode_float(4), untouched.g, 0.0, "A negative index must not bind the last kernel")

    comp.dispatch_kernel("no_such_kernel", 8, 8, 1)
    var after_name := rd.texture_get_data(canvas_tex.rid, 0)
    assert_almost_eq(after_name.decode_float(0), untouched.r, 0.0, "An unknown kernel name must dispatch nothing")
    assert_almost_eq(after_name.decode_float(4), untouched.g, 0.0, "An unknown kernel name must dispatch nothing")


## A composite writes only inside the region it was given.
##
## This is the property a screenshot cannot check, and the reason the first attempt
## at region-limited compositing was reverted: a wrong region does not error, it leaves
## part of a chunk holding the wrong pixels, and whether that shows depends on what
## happened to be underneath.
##
## Both halves of the region have to be exercised or the test is theatre. The
## origin is non-zero, so ignoring it moves the write. The size is 20, which is not
## a multiple of the 8-wide workgroup, so the dispatch covers 24 and four rows and
## columns of threads must decline to write. An earlier version of this test used
## origin (0, 0) and a size of exactly 16, and passed against a shader that ignored
## the region completely.
func test_a_composite_writes_only_inside_its_region() -> void:
    var rd := GlobalShaderCompiler.get_rd()
    var untouched := Color(0.25, 0.5, 0.75, 1.0)

    var canvas_tex := SaTexture.new(Vector2i(64, 64))
    rd.texture_clear(canvas_tex.rid, untouched, 0, 1, 0, 1)
    var chunk_tex := SaTexture.new(Vector2i(64, 64))
    rd.texture_clear(chunk_tex.rid, Color(1, 0, 0, 1), 0, 1, 0, 1)

    var comp := SaCompute.new("composite")
    comp.set_texture(0, canvas_tex.rid)
    comp.set_texture(1, chunk_tex.rid)
    comp.set_push_constant_float_array(SaCompute.pack_composite_params(Vector2.ZERO, 1.0, null, 0.0, 1.0, Rect2i(16, 16, 20, 20)))
    comp.dispatch_kernel("composite", 3, 3, 1)

    var data: PackedByteArray = rd.texture_get_data(canvas_tex.rid, 0)
    assert_almost_eq(_red_at(data, 20, 20), 1.0, 0.01, "Inside the region the source was composited")
    assert_almost_eq(_red_at(data, 0, 0), untouched.r, 0.0, "Before the origin the canvas is bit for bit unchanged")
    assert_almost_eq(_red_at(data, 8, 20), untouched.r, 0.0, "and to the left of it")
    assert_almost_eq(_red_at(data, 38, 20), untouched.r, 0.0, "Past the size the overhanging threads wrote nothing")
    assert_almost_eq(_red_at(data, 20, 38), untouched.r, 0.0, "on the other axis too")

    # An unset region means the whole chunk, which is what every caller that
    # changes all of one passes and what the shader saw before the field existed.
    comp.set_push_constant_float_array(SaCompute.pack_composite_params(Vector2.ZERO, 1.0))
    comp.dispatch_kernel("composite", 8, 8, 1)
    var whole: PackedByteArray = rd.texture_get_data(canvas_tex.rid, 0)
    assert_almost_eq(_red_at(whole, 0, 0), 1.0, 0.01, "and then the far corner is composited too")
    assert_almost_eq(_red_at(whole, 60, 60), 1.0, 0.01, "along with the rest of the chunk")


## The red channel of one texel of a 64-wide RGBA32F readback.
func _red_at(data: PackedByteArray, x: int, y: int) -> float:
    return data.decode_float((y * 64 + x) * 16)
