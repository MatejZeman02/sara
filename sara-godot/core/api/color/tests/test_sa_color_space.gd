## SaColorSpace: the document colour descriptor.
##
## Pure maths and serialisation, so no RenderingDevice and this suite runs in the
## fast headless set as well as the full gate.
##
## The matrix tests assert behaviour rather than storage. A transposed matrix
## still inverts, still round-trips and still looks like a colour matrix, so
## comparing elements would pass on a wrong one. Mapping RGB white to the white
## point is the property that only the correct matrix has.
extends "res://tests/test_framework.gd"

## Published sRGB D65 RGB-to-XYZ columns, to four places. Anything reproducing
## these from primaries alone has the construction right.
const SRGB_RED_COLUMN := Vector3(0.4124, 0.2127, 0.0193)
const SRGB_GREEN_COLUMN := Vector3(0.3576, 0.7152, 0.1192)
const SRGB_BLUE_COLUMN := Vector3(0.1804, 0.0722, 0.9503)


func _assert_vec3(actual: Vector3, expected: Vector3, epsilon: float, what: String) -> void:
    assert_almost_eq(actual.x, expected.x, epsilon, "%s x" % what)
    assert_almost_eq(actual.y, expected.y, epsilon, "%s y" % what)
    assert_almost_eq(actual.z, expected.z, epsilon, "%s z" % what)


# ---------------------------------------------------------------------------
# Matrices
# ---------------------------------------------------------------------------


func test_srgb_matrix_matches_the_published_one() -> void:
    var matrix := SaColorSpace.srgb().rgb_to_xyz()
    _assert_vec3(matrix * Vector3(1.0, 0.0, 0.0), SRGB_RED_COLUMN, 1e-4, "sRGB red column")
    _assert_vec3(matrix * Vector3(0.0, 1.0, 0.0), SRGB_GREEN_COLUMN, 1e-4, "sRGB green column")
    _assert_vec3(matrix * Vector3(0.0, 0.0, 1.0), SRGB_BLUE_COLUMN, 1e-4, "sRGB blue column")


func test_rgb_white_lands_on_the_white_point() -> void:
    # The defining property of the construction, and the one a transposed matrix
    # fails. Checked for every preset, since each solves against its own white.
    for space in SaColorSpace.presets():
        var white_xyz := SaColorSpace.xy_to_xyz(space.white)
        var mapped: Vector3 = space.rgb_to_xyz() * Vector3.ONE
        _assert_vec3(mapped, white_xyz, 1e-5, "%s RGB white" % space.id)


func test_xyz_round_trip_is_identity() -> void:
    for space in SaColorSpace.presets():
        var probe := Vector3(0.37, 0.62, 0.11)
        var round_tripped: Vector3 = space.xyz_to_rgb() * (space.rgb_to_xyz() * probe)
        _assert_vec3(round_tripped, probe, 1e-5, "%s XYZ round trip" % space.id)


func test_adaptation_moves_one_white_onto_another() -> void:
    var d65 := SaColorSpace.xy_to_xyz(SaColorSpace.WHITE_D65)
    var d60 := SaColorSpace.xy_to_xyz(SaColorSpace.WHITE_D60)
    var adapted: Vector3 = SaColorSpace.adaptation(SaColorSpace.WHITE_D65, SaColorSpace.WHITE_D60) * d65
    _assert_vec3(adapted, d60, 1e-5, "D65 adapted to D60")


func test_adaptation_to_the_same_white_is_identity() -> void:
    var probe := Vector3(0.42, 0.77, 0.19)
    var same: Vector3 = SaColorSpace.adaptation(SaColorSpace.WHITE_D65, SaColorSpace.WHITE_D65) * probe
    _assert_vec3(same, probe, 1e-6, "D65 to D65")


func test_conversion_to_the_same_space_is_identity() -> void:
    for space in SaColorSpace.presets():
        var probe := Vector3(0.31, 0.59, 0.83)
        var converted: Vector3 = space.to_space_matrix(space) * probe
        _assert_vec3(converted, probe, 1e-5, "%s to itself" % space.id)


func test_conversion_between_spaces_preserves_white() -> void:
    # sRGB white and ACEScg white are different chromaticities, so 1,1,1 in one
    # must still be 1,1,1 in the other. Without the Bradford step it is not, and
    # every neutral in a converted document picks up a cast.
    var source := SaColorSpace.linear_srgb()
    var target := SaColorSpace.acescg()
    var converted: Vector3 = source.to_space_matrix(target) * Vector3.ONE
    _assert_vec3(converted, Vector3.ONE, 1e-4, "white through linear sRGB to ACEScg")


func test_wide_gamut_conversion_produces_negatives() -> void:
    # Not a defect, and the reason the no-clamp work came first: a saturated
    # ACEScg green is outside sRGB, so expressing it in sRGB needs a negative
    # component. If this ever stops being negative, something clamped.
    var converted: Vector3 = SaColorSpace.acescg().to_space_matrix(SaColorSpace.linear_srgb()) * Vector3(0.0, 1.0, 0.0)
    assert_true(converted.x < 0.0, "A saturated ACEScg green is out of sRGB gamut, so red goes negative")


# ---------------------------------------------------------------------------
# Storage and presets
# ---------------------------------------------------------------------------


func test_depth_selects_the_texel_format() -> void:
    var space := SaColorSpace.srgb()
    assert_eq(space.texel_format(), RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT, "F32 is the default depth")
    space.depth = SaColorSpace.Depth.F16
    assert_eq(space.texel_format(), RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, "F16 selects the half format")
    assert_true(SaFieldSpec.BYTES_PER_TEXEL.has(space.texel_format()), "Whatever depth yields must be a known texel size")


func test_linear_srgb_shares_the_srgb_gamut() -> void:
    var gamma := SaColorSpace.srgb()
    var linear := SaColorSpace.linear_srgb()
    assert_eq(linear.primaries, gamma.primaries, "Linear sRGB differs only in its transfer curve")
    assert_eq(linear.white, gamma.white, "and not in its white point")
    assert_true(linear.transfer.is_identity(), "which is the whole difference")
    assert_false(linear.matches(gamma), "so the two must not compare equal")


func test_every_preset_has_a_display_name() -> void:
    for space in SaColorSpace.presets():
        assert_true(SaColorSpace.display_name(space.id) != "Custom", "%s needs a name for the chooser" % space.id)


# ---------------------------------------------------------------------------
# Serialisation
# ---------------------------------------------------------------------------


func test_header_round_trip_preserves_every_preset() -> void:
    for space in SaColorSpace.presets():
        var back := SaColorSpace.from_header({"color_space": space.to_header()})
        assert_true(back.matches(space), "%s must survive a header round trip" % space.id)
        assert_eq(back.id, space.id, "including its id")
        assert_true(back.is_specified, "a descriptor read from a header was specified")


func test_header_round_trip_survives_json() -> void:
    # to_header() feeds JSON.stringify in the real writer, which turns every
    # number into a float and every nested array into an untyped one. Round-trip
    # through JSON rather than trusting the Dictionary.
    var space := SaColorSpace.acescg()
    space.depth = SaColorSpace.Depth.F16
    var encoded := JSON.stringify({"color_space": space.to_header()})
    var json := JSON.new()
    assert_eq(json.parse(encoded), OK, "the header must be valid JSON")
    var back := SaColorSpace.from_header(SaTyped.strings(json.data))
    assert_true(back.matches(space), "ACEScg at F16 must survive JSON")
    assert_eq(back.depth, SaColorSpace.Depth.F16, "including its depth")
    assert_true(back.transfer.is_identity(), "and its transfer")


func test_a_header_without_a_colour_space_is_unspecified() -> void:
    # v4 shipped before this descriptor existed, so headers with no colour space
    # are real files. They must open, and they must not claim to have said sRGB.
    var back := SaColorSpace.from_header({"format": "sad", "version": 4})
    assert_not_null(back, "a header with no colour space must still yield a descriptor")
    assert_false(back.is_specified, "and it must record that the file never said")
    assert_eq(back.id, SaColorSpace.ID_UNSPECIFIED, "under an id that is not a real space")
    assert_true(back.matches(SaColorSpace.srgb()), "while still rendering as what it was painted as")


func test_unspecified_is_distinguishable_from_declared_srgb() -> void:
    var declared := SaColorSpace.srgb()
    var absent := SaColorSpace.unspecified()
    assert_true(absent.matches(declared), "the two describe the same colour")
    assert_true(declared.is_specified and not absent.is_specified, "but only one of them was written down")
    assert_true(declared.id != absent.id, "and they are not the same descriptor")


# ---------------------------------------------------------------------------
# Storage depth
# ---------------------------------------------------------------------------


func test_every_depth_the_enum_has_is_now_allocatable() -> void:
    var supported := SaColorSpace.storage_depths()
    assert_false(supported.is_empty(), "something has to be allocatable")
    assert_true(SaColorSpace.storage_supports_depth(SaColorSpace.Depth.F32), "F32 is the default")
    assert_true(
        SaColorSpace.storage_supports_depth(SaColorSpace.Depth.F16),
        "and F16 too, now that kernels are compiled once per storage format"
    )

    # Still a list rather than "whatever the enum has". The enum is the
    # serialisation contract, and a file may name a depth a future build adds,
    # so a chooser has to ask what can be allocated rather than what can be read.
    for depth: int in supported:
        var space := SaColorSpace.srgb().with_depth(depth as SaColorSpace.Depth)
        assert_true(SaFieldSpec.BYTES_PER_TEXEL.has(space.texel_format()), "every allocatable depth has a known texel size")


func test_a_files_depth_is_read_back_as_what_the_file_said() -> void:
    # The descriptor is data. A .sad recording F16 parses as F16 whatever this
    # build prefers, or a document silently becomes F32 on every round trip.
    var header: Dictionary[String, Variant] = {"color_space": SaColorSpace.srgb().to_header()}
    header["color_space"]["depth"] = "F16"
    var space := SaColorSpace.from_header(header)
    assert_eq(space.depth, SaColorSpace.Depth.F16, "the file said F16, so the descriptor says F16")
    assert_eq(space.texel_format(), RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, "and asks for the matching format")
    assert_true(SaColorSpace.storage_supports_depth(space.depth), "and storage can now honour it")


func test_depth_is_separable_from_what_the_colours_mean() -> void:
    # with_depth() exists so a gamut change never rewrites storage as a side
    # effect. Everything except the depth has to survive it.
    var source := SaColorSpace.acescg()
    var half := source.with_depth(SaColorSpace.Depth.F16)
    assert_eq(half.depth, SaColorSpace.Depth.F16, "the depth changed")
    assert_eq(str(half.id), str(source.id), "the identity did not")
    assert_eq(half.transfer, source.transfer, "nor the transfer curve")
    assert_true(half.shares_gamut(source), "nor the gamut")
    assert_eq(half.is_specified, source.is_specified, "nor whether anyone said so")
