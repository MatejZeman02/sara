## A document whose chunks hold Oklab rather than red, green and blue.
##
## Approved on 2026-08-31: a document may store any coordinate system its
## descriptor fully describes. Oklab is the first one, and the reason to want it
## is that Normal then mixes along the perceptual axis and the four non-separable
## modes stop converting at all.
##
## The rule the seventeen kernels follow is item 2 of Phase 5c: convert only where
## the document's coordinates and the mode's own disagree. So this suite has to
## show three different things, and showing only the first would be the easy
## mistake. An RGB-defined mode must give the same *colour* it gives on the
## equivalent sRGB document, because that is what keeps Multiply agreeing with
## Krita. A coordinate-agnostic mode must not, because mixing perceptually is the
## entire feature. And an Oklab-defined mode must touch the stored numbers
## directly, gamut mapping included, or rather excluded.
extends "res://tests/test_framework.gd"

## Dispatches the real composite kernels.
const REQUIRES_GPU := true

## Loose enough for a cube root and its inverse in float32 on the GPU, tight
## enough that an 8-bit display step (about 0.004) is four times larger.
const ROUND_TRIP_EPSILON := 0.001


func _oklab_space() -> SaColorSpace:
    return SaColorSpace.oklab()


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


func _lab_of(stored: Color) -> Vector3:
    return Vector3(stored.r, stored.g, stored.b)


# ---------------------------------------------------------------------------
# The descriptor
# ---------------------------------------------------------------------------


## The axis is orthogonal to the other three. An Oklab document still declares a
## gamut, a white point and a curve, and those still mean something: they are its
## RGB view, which every separable blend mode works in.
func test_the_axis_composes_with_the_other_three() -> void:
    var space := SaColorSpace.linear_srgb().with_coordinates(SaColorSpace.Coordinates.OKLAB)

    assert_eq(space.coordinates, SaColorSpace.Coordinates.OKLAB, "The coordinate system is what was asked for")
    assert_true(space.is_linear(), "and the transfer axis is untouched by it")
    assert_eq(space.depth, SaColorSpace.Depth.F32, "as is the depth")

    var deeper := space.with_depth(SaColorSpace.Depth.F16)
    assert_eq(deeper.coordinates, SaColorSpace.Coordinates.OKLAB, "Changing depth does not drop the coordinates")


## Two documents that differ only in what their numbers are do not describe the
## same thing, so Image > Convert must be willing to run between them. `matches`
## is what decides that, which is why it is asserted rather than assumed.
func test_an_oklab_document_does_not_match_its_rgb_twin() -> void:
    assert_false(SaColorSpace.oklab().matches(SaColorSpace.srgb()), "Oklab storage is not sRGB storage")
    assert_true(SaColorSpace.oklab().matches(SaColorSpace.oklab()), "and it does match itself")


## The axis reaches `.sad` and comes back. A file that records the pixels without
## recording what they are is a file only the build that wrote it can open.
func test_the_axis_survives_a_sad_round_trip() -> void:
    var header := SaColorSpace.oklab().to_header()
    var reopened := SaColorSpace.from_header({"color_space": header})

    assert_eq(reopened.coordinates, SaColorSpace.Coordinates.OKLAB, "The coordinate system came back")
    assert_true(reopened.matches(SaColorSpace.oklab()), "and so did everything else")


## Every `.sad` written before this axis existed names no coordinate system, and
## those documents hold RGB. A missing key must read as that rather than as zero
## meaning something else later.
func test_a_file_without_the_key_reads_as_rgb() -> void:
    var header := SaColorSpace.srgb().to_header()
    header.erase("coordinates")

    var reopened := SaColorSpace.from_header({"color_space": header})
    assert_eq(reopened.coordinates, SaColorSpace.Coordinates.RGB, "An absent key means RGB")


## The kernel reads the coordinate system positionally out of the push constant.
## If either side's layout moves this is the cheap test that says so, before a
## GPU one has to.
func test_the_coordinate_system_reaches_the_push_constant() -> void:
    var params := SaCompute.pack_composite_params(Vector2.ZERO, 1.0, SaColorSpace.oklab())

    assert_eq(params.size(), 32, "The block is 32 floats, 128 bytes")
    assert_almost_eq(params[26], float(SaColorSpace.Coordinates.OKLAB), 0.0, "and says what the chunks hold")


# ---------------------------------------------------------------------------
# The picker, on both sides
# ---------------------------------------------------------------------------


## What the brush writes and the eyedropper reads. An Oklab document is reached
## from linear sRGB by the fixed matrices, never through its own gamut matrix,
## because Oklab carries no gamut of its own.
func test_a_picked_colour_round_trips_through_oklab_storage() -> void:
    var space := _oklab_space()

    for picked: Color in [Color(0.2, 0.6, 0.9, 1.0), Color(1.0, 0.0, 0.0, 0.5), Color(0.5, 0.5, 0.5, 1.0)]:
        var stored := space.from_display(picked)
        var shown := space.to_display(stored)

        assert_almost_eq(shown.r, picked.r, ROUND_TRIP_EPSILON, "red survives the trip into Oklab and back")
        assert_almost_eq(shown.g, picked.g, ROUND_TRIP_EPSILON, "green too")
        assert_almost_eq(shown.b, picked.b, ROUND_TRIP_EPSILON, "and blue")
        assert_almost_eq(shown.a, picked.a, 0.0, "while alpha is coverage and is never converted")


## Storage really is different, not merely labelled so. Mid grey is 0.5 in an
## sRGB document and is not 0.5 in an Oklab one, and a brush that skipped the
## conversion would put the wrong number in the chunk.
func test_oklab_storage_is_not_the_picked_number() -> void:
    var stored := _oklab_space().from_display(Color(0.5, 0.5, 0.5, 1.0))

    assert_true(absf(stored.r - 0.5) > 0.05, "Mid grey does not store as 0.5 in Oklab")
    assert_almost_eq(stored.g, 0.0, 0.001, "and a neutral has no a")
    assert_almost_eq(stored.b, 0.0, 0.001, "and no b")


## A document storing perceptual coordinates cannot take the passthrough, or the
## view would read L, a and b as red, green and blue.
func test_oklab_storage_is_never_display_ready() -> void:
    assert_false(_oklab_space().is_display_ready(), "Oklab storage always needs the view transform")
    assert_true(SaColorSpace.srgb().is_display_ready(), "while an sRGB document still takes the passthrough")


# ---------------------------------------------------------------------------
# The eleven RGB-defined modes
# ---------------------------------------------------------------------------


## The claim option 2 was chosen for. A mode defined on RGB channels gives the
## same colour whatever the document stores, because it converts out to the
## document's RGB view, applies itself there, and goes home.
##
## Compared as colours rather than as stored numbers, which is the only
## comparison that means anything across two coordinate systems.
func test_an_rgb_defined_mode_gives_the_same_colour_on_both_documents() -> void:
    var srgb := SaColorSpace.srgb()
    var oklab := _oklab_space()
    var src := Color(0.7, 0.35, 0.2, 1.0)
    var dst := Color(0.25, 0.55, 0.8, 1.0)

    for kernel: String in ["multiply", "screen", "overlay", "darken", "difference", "hard_light"]:
        var on_srgb := _blend(srgb, kernel, src, dst)
        var on_oklab := _blend(oklab, kernel, oklab.from_display(src), oklab.from_display(dst))
        var as_colour := oklab.to_display(on_oklab)

        assert_almost_eq(as_colour.r, on_srgb.r, 0.002, "%s agrees on red across both documents" % kernel)
        assert_almost_eq(as_colour.g, on_srgb.g, 0.002, "%s agrees on green" % kernel)
        assert_almost_eq(as_colour.b, on_srgb.b, 0.002, "%s agrees on blue" % kernel)


## And it is a real round trip rather than the kernel accidentally leaving the
## numbers alone. Multiplying stored Oklab directly would multiply two signed
## numbers centred on zero, which is not a darker colour but nothing at all, so
## the stored result must not be the product of the stored inputs.
func test_the_rgb_modes_do_not_multiply_the_stored_oklab() -> void:
    var oklab := _oklab_space()
    var src := oklab.from_display(Color(0.7, 0.35, 0.2, 1.0))
    var dst := oklab.from_display(Color(0.25, 0.55, 0.8, 1.0))

    var stored := _blend(oklab, "multiply", src, dst)
    var naive := Vector3(src.r * dst.r, src.g * dst.g, src.b * dst.b)

    assert_true(
        _lab_of(stored).distance_to(naive) > 0.01, "Multiply on an Oklab document is not the product of the stored triples"
    )


# ---------------------------------------------------------------------------
# The two coordinate-agnostic modes
# ---------------------------------------------------------------------------


## The reason to store Oklab at all. Normal is Porter-Duff, which is a lerp, and
## a lerp is well defined wherever the values live, so it converts nothing and
## mixes along whichever axis the document is written in.
##
## Half-covered white over black is the case where the two axes visibly part: the
## sRGB document lands on stored 0.5, and the Oklab one lands on the colour half
## way up the perceptual scale, which is darker.
func test_normal_mixes_along_the_documents_own_axis() -> void:
    var oklab := _oklab_space()
    var white := oklab.from_display(Color(1.0, 1.0, 1.0, 0.5))
    var black := oklab.from_display(Color(0.0, 0.0, 0.0, 1.0))

    var stored := _blend(oklab, "composite", white, black)
    var expected_l: float = 0.5 * SaOklab.from_linear_srgb(Vector3.ONE).x

    assert_almost_eq(stored.r, expected_l, 0.002, "Normal lerped the stored lightness directly")

    var as_colour := oklab.to_display(stored)
    var on_srgb := _blend(SaColorSpace.srgb(), "composite", Color(1.0, 1.0, 1.0, 0.5), Color(0.0, 0.0, 0.0, 1.0))
    assert_true(on_srgb.r - as_colour.r > 0.05, "and that is a different, darker colour than the same lerp done in sRGB")


## Erase only carves alpha away, so it has nothing to convert either, and the
## backdrop's stored numbers must come through untouched rather than round-tripped
## through an RGB view they never asked for.
func test_erase_leaves_the_stored_colour_exactly_alone() -> void:
    var oklab := _oklab_space()
    var backdrop := oklab.from_display(Color(0.3, 0.7, 0.45, 1.0))

    var stored := _blend(oklab, "erase", Color(0.0, 0.0, 0.0, 0.5), backdrop)

    assert_almost_eq(stored.r, backdrop.r, 0.0, "L is bit-exact through erase")
    assert_almost_eq(stored.g, backdrop.g, 0.0, "a is bit-exact")
    assert_almost_eq(stored.b, backdrop.b, 0.0, "b is bit-exact")
    assert_almost_eq(stored.a, 0.5, 1e-6, "and only alpha moved")


# ---------------------------------------------------------------------------
# The four Oklab-defined modes
# ---------------------------------------------------------------------------


## These already worked in Oklab, so on an Oklab document they convert nothing.
## Asserted against the polar recombination computed here from the stored values,
## which is the whole of what the kernel should be doing.
func test_hue_recombines_the_stored_coordinates_directly() -> void:
    var oklab := _oklab_space()
    var src := oklab.from_display(Color(0.9, 0.1, 0.1, 1.0))
    var dst := oklab.from_display(Color(0.2, 0.4, 0.7, 1.0))

    var stored := _blend(oklab, "hue", src, dst)

    var backdrop := SaOklab.to_polar(_lab_of(dst))
    var source := SaOklab.to_polar(_lab_of(src))
    var expected := SaOklab.from_polar(Vector3(backdrop.x, backdrop.y, source.z))

    assert_almost_eq(stored.r, expected.x, 0.001, "Hue keeps the backdrop's lightness")
    assert_almost_eq(stored.g, expected.y, 0.001, "takes the source's hue angle on a")
    assert_almost_eq(stored.b, expected.z, 0.001, "and on b")


## Gamut mapping exists because swapping polar components between two in-gamut
## RGB colours can land outside the RGB cube, and storing a clamped triple there
## would drag hue and lightness with it. An Oklab document has no cube to leave:
## its storage is gamut-independent, so the chroma the backdrop had is the chroma
## the result keeps.
##
## The same blend on the sRGB twin is bisected in, and asserting that too is what
## makes this a statement about the coordinate system rather than about the
## colours happening to be tame.
func test_an_oklab_document_gives_up_no_chroma_to_gamut_mapping() -> void:
    var oklab := _oklab_space()
    var vivid := Color(0.0, 0.35, 1.0, 1.0)
    var backdrop := Color(0.05, 0.85, 0.1, 1.0)

    var stored := _blend(oklab, "hue", oklab.from_display(vivid), oklab.from_display(backdrop))
    var kept := SaOklab.to_polar(_lab_of(stored)).y
    var wanted := SaOklab.to_polar(_lab_of(oklab.from_display(backdrop))).y

    assert_almost_eq(kept, wanted, 0.002, "The backdrop's chroma survives intact")

    var on_srgb := _blend(SaColorSpace.srgb(), "hue", vivid, backdrop)
    var mapped := SaOklab.to_polar(SaOklab.from_linear_srgb(_srgb_to_linear(on_srgb))).y
    assert_true(wanted - mapped > 0.01, "while the sRGB document had to bisect chroma away to stay in its cube")


func _srgb_to_linear(c: Color) -> Vector3:
    var curve := SaTransferFunction.srgb()
    return Vector3(curve.decode(c.r), curve.decode(c.g), curve.decode(c.b))


# ---------------------------------------------------------------------------
# Image > Convert Colour Space
# ---------------------------------------------------------------------------


func _document_in(space: SaColorSpace) -> SaDocument:
    var doc := SaDocument.new()
    doc.setup_default_document(Vector2i(256, 256), SaCompositor.new(), space)
    return doc


func _first_texel(layer: SaLayer) -> Color:
    var texture := layer.get_field(Vector2i(0, 0))
    @warning_ignore("static_called_on_instance")
    var image := SaExport.get_texture_image_float(texture)
    return image.get_pixel(0, 0)


## Convert is the operation defined to leave the picture alone, so moving a
## document into Oklab has to store the same colours in different numbers. Both
## halves are asserted: the colour that survived, and that the numbers really
## moved, because a conversion that quietly did nothing would pass the first.
func test_converting_into_oklab_keeps_the_colour_and_changes_the_numbers() -> void:
    var doc := _document_in(SaColorSpace.srgb())
    doc.active_layer.fill(Color(0.4, 0.6, 0.8, 1.0))
    var before := _first_texel(doc.active_layer)

    assert_true(SaColorConversion.new(doc).convert_to(_oklab_space()), "sRGB into Oklab is a real conversion")

    var after := _first_texel(doc.active_layer)
    var as_colour := _oklab_space().to_display(after)

    assert_almost_eq(as_colour.r, before.r, 0.002, "Red looks the same after the conversion")
    assert_almost_eq(as_colour.g, before.g, 0.002, "green too")
    assert_almost_eq(as_colour.b, before.b, 0.002, "and blue")
    assert_true(absf(after.r - before.r) > 0.01, "while the stored numbers really did move")
    assert_almost_eq(after.a, before.a, 0.0, "and alpha is coverage, never converted")

    doc.free()


## And the trip back. Two conversions that cancel are the cheapest statement that
## the kernel is running the same maths in both directions rather than two
## different approximations of it.
func test_out_to_oklab_and_back_cancels() -> void:
    var doc := _document_in(SaColorSpace.srgb())
    doc.active_layer.fill(Color(0.4, 0.6, 0.8, 1.0))
    var before := _first_texel(doc.active_layer)

    assert_true(SaColorConversion.new(doc).convert_to(_oklab_space()), "out to Oklab")
    assert_true(SaColorConversion.new(doc).convert_to(SaColorSpace.srgb()), "and back to sRGB")

    var after := _first_texel(doc.active_layer)
    assert_almost_eq(after.r, before.r, 0.002, "Two conversions cancel on red")
    assert_almost_eq(after.g, before.g, 0.002, "on green")
    assert_almost_eq(after.b, before.b, 0.002, "and on blue")

    doc.free()


## Oklab carries no gamut of its own, so two Oklab documents hold the same numbers
## however their descriptors differ about primaries. Convert must leave every
## pixel exactly alone rather than take a round trip through linear sRGB that can
## only lose a last bit.
func test_a_conversion_between_two_oklab_documents_moves_no_pixel() -> void:
    var doc := _document_in(_oklab_space())
    doc.active_layer.fill(Color(0.55, -0.1, 0.12, 1.0))
    var before := _first_texel(doc.active_layer)

    var wide := SaColorSpace.display_p3().with_coordinates(SaColorSpace.Coordinates.OKLAB)
    assert_true(SaColorConversion.new(doc).convert_to(wide), "The descriptors differ, so a conversion is offered")

    var after := _first_texel(doc.active_layer)
    assert_almost_eq(after.r, before.r, 0.0, "L is bit-exact")
    assert_almost_eq(after.g, before.g, 0.0, "a is bit-exact")
    assert_almost_eq(after.b, before.b, 0.0, "and b is bit-exact")

    doc.free()


# ---------------------------------------------------------------------------
# The whole path, not one kernel
# ---------------------------------------------------------------------------


## Everything above dispatches the composite kernel directly, which proves the
## kernel and skips everything that has to hand it the right descriptor. This
## runs a real easel over a real document instead: SaCompositor packs the push
## constant, SaDocument decides which chunks are dirty, and the output texture is
## what a view would bind.
##
## Multiply rather than Normal, deliberately. Normal converts nothing on either
## document, so it would pass even if the coordinate system never left the
## descriptor, and a test that cannot fail is worse than no test.
func test_a_real_easel_composites_an_oklab_document_like_its_srgb_twin() -> void:
    var backdrop := Color(0.6, 0.7, 0.55, 1.0)
    var over := Color(0.45, 0.3, 0.9, 1.0)

    var on_srgb := _composite_through_easel(SaColorSpace.srgb(), backdrop, over)
    var oklab := _oklab_space()
    var stored := _composite_through_easel(oklab, oklab.from_display(backdrop), oklab.from_display(over))
    var as_colour := oklab.to_display(stored)

    # The guard that makes the three assertions below mean anything. A bare
    # SaCompositor has no blend mode registry, so an unregistered id resolves to
    # Normal, and Normal converts nothing on either document: this test passed
    # while running the wrong kernel and could not have failed. Multiply darkens,
    # so a result no darker than the source is that failure coming back.
    assert_true(on_srgb.r < over.r - 0.05, "Multiply really ran rather than falling back to Normal")

    assert_almost_eq(as_colour.r, on_srgb.r, 0.003, "The easel's own output agrees on red")
    assert_almost_eq(as_colour.g, on_srgb.g, 0.003, "on green")
    assert_almost_eq(as_colour.b, on_srgb.b, 0.003, "and on blue")


## Fills the background and multiplies the paint layer over it, then returns what
## the easel actually wrote into the texture a view binds.
func _composite_through_easel(space: SaColorSpace, background: Color, over: Color) -> Color:
    var easel := SaEasel.create_default(Vector2i(64, 64))
    easel.document.color_space = space
    for child in easel.document.get_children():
        if child is SaLayer and child != easel.document.active_layer:
            (child as SaLayer).fill(background)
    # Registered by hand: a bare SaCompositor carries no registry, and the module
    # that normally fills one is not booted in a suite.
    easel.compositor.register_blend_mode(&"multiply", "composite", GlobalShaderCompiler.get_kernel_index("composite", "multiply"))
    easel.document.active_layer.blend_mode = &"multiply"
    easel.document.active_layer.fill(over)

    easel.document.update_caches(Rect2(0, 0, 64, 64))
    easel.compositor.composite_all_layers(easel.output, easel.document, Rect2(0, 0, 64, 64))

    @warning_ignore("static_called_on_instance")
    var image := SaExport.get_texture_image_float(easel.output)
    var texel := image.get_pixel(4, 4)
    easel.free()
    return texel


# ---------------------------------------------------------------------------
# What a new document starts on
# ---------------------------------------------------------------------------


## A new document's background is mid grey, and mid grey is a colour rather than
## three numbers.
##
## The literal 0.5, 0.5, 0.5 used to go straight into the chunk. An Oklab document
## read that as lightness 0.5 with a and b both at 0.5, which is a saturated
## orange, so a new Oklab document opened orange. The same bug was in every
## non-sRGB document and merely quieter: a linear one read it as light-linear and
## came up a lighter grey than intended.
func test_a_new_document_starts_on_grey_whatever_it_stores() -> void:
    for space: SaColorSpace in [SaColorSpace.srgb(), SaColorSpace.linear_srgb(), _oklab_space()]:
        var doc := _document_in(space)
        var background: SaLayer = null
        for child in doc.get_children():
            if child is SaLayer and (child as SaLayer).name == "Background":
                background = child as SaLayer
        assert_not_null(background, "A new document has a background layer")
        if background != null:
            var stored := _first_texel(background)
            var shown := space.to_display(stored)
            for channel: Array in [["red", shown.r], ["green", shown.g], ["blue", shown.b]]:
                assert_almost_eq(channel[1], 0.5, 0.002, "%s: the background reads as mid grey on %s" % [channel[0], space.id])
        doc.free()


## And an sRGB document's background must not have moved by a last bit, because
## every document anyone has ever opened is one.
func test_an_srgb_background_is_untouched() -> void:
    var doc := _document_in(SaColorSpace.srgb())
    var background: SaLayer = null
    for child in doc.get_children():
        if child is SaLayer and (child as SaLayer).name == "Background":
            background = child as SaLayer
    var stored := _first_texel(background)

    assert_almost_eq(stored.r, 0.5, 0.0, "Mid grey still stores as exactly 0.5 in an sRGB document")
    assert_almost_eq(stored.g, 0.5, 0.0, "on green")
    assert_almost_eq(stored.b, 0.5, 0.0, "and on blue")

    doc.free()
