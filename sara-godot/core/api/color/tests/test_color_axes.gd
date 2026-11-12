## The two axes a colour space is made of: the transfer curve and the gamut.
##
## `SaColorSpace` used to be four fields with the maths for pairs written into
## it: an enum of two transfer curves branched on by hand in five places, and
## primaries as a bare array of numbers with no identity. The colour-axes work pulls the
## gamut and the transfer out as values that carry their own maths, so a document
## can be any combination of them rather than one of a list somebody enumerated.
##
## A sibling, `test_color_axes_composition.gd`, split off, keeps what
## only exists once both axes are chosen: composing a space from a pair,
## converting a document between two spaces on the GPU, and the header round
## trip. Nothing was rewritten in the move.
extends "res://tests/test_framework.gd"

# ---------------------------------------------------------------------------
# The transfer axis
# ---------------------------------------------------------------------------


## The invariant the whole four-parameter form rests on. If it ever fails for a
## curve, that curve cannot be sent to a kernel, because the offset it needs is
## not the one that gets derived.
func test_every_curve_encodes_full_scale_to_full_scale() -> void:
    for curve: SaTransferFunction in SaTransferFunction.presets():
        assert_almost_eq(curve.encode(1.0), 1.0, 1e-6, "%s must map 1.0 to 1.0" % curve.display_name)
        assert_almost_eq(curve.offset(), curve.gain - 1.0, 0.0, "%s: b is a - 1 by construction" % curve.display_name)


func test_every_curve_round_trips_including_negatives() -> void:
    for curve: SaTransferFunction in SaTransferFunction.presets():
        for value: float in [0.0, 0.001, 0.05, 0.5, 1.0, 3.0, -0.5, -2.0]:
            var back := curve.encode(curve.decode(value))
            assert_almost_eq(back, value, 1e-5, "%s round trips %s" % [curve.display_name, value])


## The cube-root curve, which exists for an Oklab document: it makes the
## document's RGB view, the space the eleven RGB-defined blend modes work in, use
## the same kind of scale the storage does.
##
## Pinned by value because "gamma 3.0" names the decode and it is the encode a
## reader is likely to picture. Encode is the cube root, decode is the cube.
func test_the_cube_root_curve_is_a_cube_root() -> void:
    var curve := SaTransferFunction.gamma30()

    assert_almost_eq(curve.encode(0.125), 0.5, 1e-6, "Gamma 3.0 encodes by cube root")
    assert_almost_eq(curve.decode(0.5), 0.125, 1e-6, "and decodes by cubing")
    assert_almost_eq(curve.offset(), 0.0, 0.0, "A pure power curve has no offset")
    assert_false(curve.is_identity(), "and it is not the identity, so kernels must not skip it")

    # Reachable by name, which is what a `.sad` records. A curve a chooser offers
    # and `from_id` cannot find would write files this build could not reopen.
    assert_not_null(SaTransferFunction.from_id(SaTransferFunction.ID_GAMMA30), "and a file can name it")


## The published sRGB anchors, so a change to the constants shows up as a wrong
## number rather than as a picture nobody compares.
func test_the_srgb_curve_matches_its_published_values() -> void:
    var srgb := SaTransferFunction.srgb()
    assert_almost_eq(srgb.decode(0.5), 0.21404114, 1e-6, "mid grey decodes to the sRGB linear value")
    assert_almost_eq(srgb.encode(0.5), 0.73535698, 1e-6, "and half the light encodes back to it")
    assert_almost_eq(srgb.linear_threshold(), 0.0031308, 1e-7, "The straight segment ends where the standard says")


## Rec. 709 is close to sRGB and is not the same curve. Pinned so nobody
## quietly collapses the two.
func test_rec709_is_not_srgb() -> void:
    var rec := SaTransferFunction.rec709()
    var srgb := SaTransferFunction.srgb()
    assert_almost_eq(rec.linear_threshold(), 0.018, 1e-6, "Its straight segment ends at the broadcast value")
    assert_true(absf(rec.decode(0.5) - srgb.decode(0.5)) > 1e-3, "and mid grey decodes differently")


## Not almost the identity. Bit-exact, because a linear document put through the
## general form would come back perturbed by `pow(x, 1.0)`.
func test_linear_is_exactly_the_identity() -> void:
    var linear := SaTransferFunction.linear()
    assert_true(linear.is_identity(), "Linear reports itself as flat")
    for value: float in [0.0, 0.37, 1.0, 4.25, -0.6]:
        assert_true(linear.decode(value) == value, "decode leaves %s untouched" % value)
        assert_true(linear.encode(value) == value, "encode leaves %s untouched" % value)


## A curve this build does not have is a real situation, and what to do about it
## differs between a loader and a chooser, so the lookup refuses rather than
## guessing.
func test_an_unknown_curve_is_refused_rather_than_guessed() -> void:
    assert_null(SaTransferFunction.from_id(&"pq"), "A curve nobody registered has no answer")
    assert_not_null(SaTransferFunction.from_id(SaTransferFunction.ID_GAMMA22), "and a known one does")


# ---------------------------------------------------------------------------
# The gamut axis
# ---------------------------------------------------------------------------


## The construction's whole purpose: RGB 1,1,1 has to land exactly on the white
## point, whichever white the document declares. Getting this wrong produces a
## matrix that still inverts and still looks like a colour matrix.
func test_every_gamut_sends_full_white_to_its_white_point() -> void:
    for gamut: SaGamut in SaGamut.presets():
        for white: Vector2 in [SaColorSpace.WHITE_D65, SaColorSpace.WHITE_D60]:
            var xyz: Vector3 = gamut.rgb_to_xyz(white) * Vector3.ONE
            var expected := SaGamut.xy_to_xyz(white)
            assert_almost_eq(xyz.x, expected.x, 1e-5, "%s at that white: X" % gamut.display_name)
            assert_almost_eq(xyz.y, expected.y, 1e-5, "%s at that white: Y" % gamut.display_name)
            assert_almost_eq(xyz.z, expected.z, 1e-5, "%s at that white: Z" % gamut.display_name)


func test_every_gamut_matrix_inverts() -> void:
    for gamut: SaGamut in SaGamut.presets():
        var probe := Vector3(0.3, 0.6, 0.9)
        var back: Vector3 = gamut.xyz_to_rgb(SaColorSpace.WHITE_D65) * (gamut.rgb_to_xyz(SaColorSpace.WHITE_D65) * probe)
        assert_almost_eq(back.x, probe.x, 1e-5, "%s round trips red" % gamut.display_name)
        assert_almost_eq(back.y, probe.y, 1e-5, "%s round trips green" % gamut.display_name)
        assert_almost_eq(back.z, probe.z, 1e-5, "%s round trips blue" % gamut.display_name)


## A document's primaries get their name back, so the browser and the info docker
## can say "Display P3" rather than three pairs of numbers, and a set that matches
## nothing is still a usable gamut rather than an error.
func test_a_documents_primaries_are_named_again() -> void:
    assert_eq(SaColorSpace.display_p3().gamut().id, SaGamut.ID_DISPLAY_P3, "Display P3 is recognised from its numbers")
    assert_eq(SaColorSpace.acescg().gamut().id, SaGamut.ID_AP1, "and ACEScg's primaries are AP1")

    var odd := SaColorSpace.srgb()
    odd.primaries = PackedVector2Array([Vector2(0.7, 0.3), Vector2(0.2, 0.7), Vector2(0.1, 0.05)])
    assert_eq(odd.gamut().id, SaColorSpace.ID_CUSTOM, "A set that matches nothing is custom, not an error")
    assert_true(odd.gamut().rgb_to_xyz(odd.white).determinant() != 0.0, "and still has a usable matrix")
