## That any gamut composes with any transfer curve, and that the composition
## reaches the GPU.
##
## A sibling of `test_color_axes.gd`, split off so both files stay under
## gdlint's cap with room to grow. That file keeps the two axes on their own,
## the transfer curves and the gamuts; this one keeps what only exists once
## both are chosen: composing a space from a pair, converting a document
## between two spaces, and the header round trip. Nothing was rewritten in
## the move.
##
## The load-bearing test here is the last one but two. Composing on the CPU
## proves the model, and a document actually converting through a curve the
## kernel has never heard of proves the model reaches the GPU, which is where
## the F16 lesson says a descriptor value nothing can honour comes from.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice for the conversion dispatch at the end.
const REQUIRES_GPU := true


func _document_in(space: SaColorSpace) -> SaDocument:
    var doc := SaDocument.new()
    doc.setup_default_document(Vector2i(256, 256), SaCompositor.new(), space)
    return doc


func _first_texel(layer: SaLayer) -> Color:
    var texture := layer.get_field(Vector2i(0, 0))
    @warning_ignore("static_called_on_instance")
    var image := SaExport.get_texture_image_float(texture)
    return image.get_pixel(0, 0)


# ---------------------------------------------------------------------------
# Composition
# ---------------------------------------------------------------------------


## The point of the decomposition. Not one of a list of pairs somebody wrote out,
## but every gamut against every curve, each round-tripping through XYZ.
func test_any_gamut_composes_with_any_curve() -> void:
    var probe := Vector3(0.3, 0.6, 0.9)
    for gamut: SaGamut in SaGamut.presets():
        for curve: SaTransferFunction in SaTransferFunction.presets():
            var space := SaColorSpace.create(&"probe", gamut.primaries, SaColorSpace.WHITE_D65, curve)
            var back: Vector3 = space.xyz_to_rgb() * (space.rgb_to_xyz() * probe)
            assert_almost_eq(back.x, probe.x, 1e-5, "%s + %s composes" % [gamut.display_name, curve.display_name])


## A conversion between two combinations is a matrix and two curves, so going
## there and back has to return what it started with, whichever pair is chosen.
func test_a_conversion_and_its_reverse_cancel() -> void:
    var combinations: Array[SaColorSpace] = [
        SaColorSpace.srgb(),
        SaColorSpace.linear_srgb(),
        SaColorSpace.acescg(),
        SaColorSpace.create(&"p3_rec709", SaGamut.display_p3().primaries, SaColorSpace.WHITE_D65, SaTransferFunction.rec709()),
        SaColorSpace.create(&"srgb_g22", SaGamut.srgb().primaries, SaColorSpace.WHITE_D65, SaTransferFunction.gamma22()),
    ]
    for source: SaColorSpace in combinations:
        for target: SaColorSpace in combinations:
            var there := source.conversion_matrix(target)
            var back := target.conversion_matrix(source)
            var probe := Vector3(0.3, 0.6, 0.9)
            var round_trip: Vector3 = back * (there * probe)
            assert_almost_eq(round_trip.x, probe.x, 1e-4, "%s to %s and back" % [source.id, target.id])
            assert_almost_eq(round_trip.z, probe.z, 1e-4, "on blue too")


## The open question was whether the decomposition needed a v5 header. It does not: the
## header already wrote id, primaries, white, transfer and depth, which is the
## decomposed form, so a new curve is a new string in a field that already exists.
func test_an_uncommon_combination_round_trips_through_the_header() -> void:
    var space := SaColorSpace.create(
        &"p3_rec709", SaGamut.display_p3().primaries, SaColorSpace.WHITE_D60, SaTransferFunction.rec709(), SaColorSpace.Depth.F16
    )

    var back := SaColorSpace.from_header({"color_space": space.to_header()})
    assert_eq(back.gamut().id, SaGamut.ID_DISPLAY_P3, "The gamut survives")
    assert_eq(back.transfer.id, SaTransferFunction.ID_REC709, "and the curve, by name")
    assert_eq(back.depth, SaColorSpace.Depth.F16, "and the depth")
    assert_true(back.white.is_equal_approx(SaColorSpace.WHITE_D60), "and the white point")
    assert_true(back.matches(space), "so the two describe the same space")


## A file naming a curve this build does not have must still open, and how well
## depends on whether it also recorded the numbers.
##
## With them, "unknown" only means Sara has no name for it: the four parameters
## are the whole curve, so the document renders exactly right and the name is a
## label. Without them there is nothing to evaluate, and sRGB with a warning beats
## refusing the file. Files written before the parameters were recorded are
## precisely the second case.
func test_a_header_naming_an_unknown_curve_still_opens() -> void:
    var raw := SaColorSpace.srgb().to_header()
    raw["transfer"] = "pq"
    raw.erase("transfer_params")

    var back := SaColorSpace.from_header({"color_space": raw})
    assert_eq(back.transfer.id, SaTransferFunction.ID_SRGB, "A name alone falls back to sRGB rather than refusing the file")

    var described := SaColorSpace.srgb().to_header()
    described["transfer"] = "pq"
    described["transfer_params"] = [1.0, 0.0, 1.0, 2.6]

    var exact := SaColorSpace.from_header({"color_space": described})
    assert_eq(str(exact.transfer.id), "pq", "but a name plus numbers keeps the name")
    assert_almost_eq(exact.transfer.exponent, 2.6, 1e-6, "and renders through the curve the file described")


## A gamma chosen on a slider has no name to record, so the header has to carry
## its numbers or the document would reopen as something else. This is the case
## the transfer parameters were added for.
func test_a_slider_gamma_survives_a_header_round_trip() -> void:
    var space := SaColorSpace.srgb()
    space.transfer = SaTransferFunction.gamma(2.63)

    var back := SaColorSpace.from_header({"color_space": space.to_header()})

    assert_almost_eq(back.transfer.exponent, 2.63, 1e-6, "The exponent came back")
    assert_true(back.transfer.matches(space.transfer), "and so did the rest of the curve")
    assert_true(back.matches(space), "so the two describe the same space")


# ---------------------------------------------------------------------------
# All the way to the GPU
# ---------------------------------------------------------------------------


## A document converted into a curve the kernel has never heard of.
##
## This is the one that matters. The old kernel compared a float against 0.5 and
## could only ever mean sRGB or linear, so a document declaring gamma 2.2 would
## have been written to the header, shown in the info docker, and then composited
## and converted as sRGB. That is the F16 bug exactly: a descriptor value nothing
## can honour. The kernel now takes the curve as four numbers and never learns
## which one it is.
func test_a_document_converts_into_a_curve_the_kernel_never_heard_of() -> void:
    var doc := _document_in(SaColorSpace.srgb())
    doc.active_layer.fill(Color(0.4, 0.6, 0.8, 1.0))
    var before := _first_texel(doc.active_layer)

    var gamma22 := SaColorSpace.create(
        &"srgb_g22", SaGamut.srgb().primaries, SaColorSpace.WHITE_D65, SaTransferFunction.gamma22()
    )
    assert_true(SaColorConversion.new(doc).convert_to(gamma22), "sRGB to gamma 2.2 is a real conversion")

    # Same gamut, so the matrix is exactly the identity and the whole conversion
    # is decode out of one curve and encode into the other. Computed here from
    # the descriptors rather than from a table, which is the composition claim.
    var after := _first_texel(doc.active_layer)
    var srgb_curve := SaTransferFunction.srgb()
    var g22_curve := SaTransferFunction.gamma22()
    for channel: Array in [["red", before.r, after.r], ["green", before.g, after.g], ["blue", before.b, after.b]]:
        var expected: float = g22_curve.encode(srgb_curve.decode(channel[1]))
        assert_almost_eq(channel[2], expected, 1e-4, "%s converts through both curves on the GPU" % channel[0])

    assert_true(absf(after.r - before.r) > 1e-4, "and the pixels really did move")
    assert_almost_eq(after.a, before.a, 0.0, "while alpha is coverage and is never converted")

    doc.free()


## The reverse, to prove the source curve is read as well as the target one.
func test_converting_back_out_of_an_unusual_curve_restores_the_pixels() -> void:
    var gamma22 := SaColorSpace.create(
        &"srgb_g22", SaGamut.srgb().primaries, SaColorSpace.WHITE_D65, SaTransferFunction.gamma22()
    )
    var doc := _document_in(gamma22)
    doc.active_layer.fill(Color(0.4, 0.6, 0.8, 1.0))
    var before := _first_texel(doc.active_layer)

    assert_true(SaColorConversion.new(doc).convert_to(SaColorSpace.srgb()), "gamma 2.2 back to sRGB")
    assert_true(SaColorConversion.new(doc).convert_to(gamma22), "and out again")

    var after := _first_texel(doc.active_layer)
    assert_almost_eq(after.r, before.r, 1e-4, "Two conversions cancel on red")
    assert_almost_eq(after.g, before.g, 1e-4, "on green")
    assert_almost_eq(after.b, before.b, 1e-4, "and on blue")

    doc.free()
