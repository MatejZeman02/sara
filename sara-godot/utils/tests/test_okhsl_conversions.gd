extends "res://tests/test_framework.gd"

## Sara's own OKHSL and OKLCh, the models the two new picker shapes read
## their area with. Numbers rather than pixels, for the reason
## `test_okhsv_shader.gd` gives: GDScript cannot call into a `.gdshader`, so
## what the shader draws is proved by a capture and what the cursor computes
## is proved here.

const OkhslConversionsScript = preload("res://utils/okhsl_conversions.gd")
const OkhsvConversionsScript = preload("res://utils/okhsv_conversions.gd")

const SAMPLES: Array[Color] = [
    Color(0.1, 0.5, 0.9),
    Color(0.9, 0.2, 0.1),
    Color(0.2, 0.8, 0.3),
    Color(0.5, 0.5, 0.5),
    Color(0.95, 0.95, 0.2),
    Color(0.05, 0.05, 0.08),
]


## `SRGB_MAX_CHROMA` is the ceiling over the whole gamut, which the triangle
## used as its right edge until every hue had its own. It is still the
## number a shape wanting one scale for every hue would take, so the sweep that
## proves nothing reaches past it stays.
func test_no_hue_reaches_past_the_srgb_ceiling() -> void:
    var highest := 0.0
    for step in 72:
        var angle := TAU * float(step) / 72.0
        for l_step in 40:
            var lightness := float(l_step + 1) / 41.0
            highest = maxf(highest, OkhslConversionsScript.gamut_chroma(cos(angle), sin(angle), lightness))
    assert_true(
        highest < OkhslConversionsScript.SRGB_MAX_CHROMA,
        "The widest sRGB chroma found was %f, inside the %f ceiling" % [highest, OkhslConversionsScript.SRGB_MAX_CHROMA]
    )
    # And not so far above the gamut that it is a round number rather than a
    # measurement, which is what would make a shape drawn against it small.
    assert_true(
        highest > 0.8 * OkhslConversionsScript.SRGB_MAX_CHROMA,
        "and the ceiling is a tight one rather than a round number picked high"
    )


func test_okhsl_survives_a_round_trip() -> void:
    for sample in SAMPLES:
        var hsl := OkhslConversionsScript.srgb_to_okhsl(sample)
        var back := OkhslConversionsScript.okhsl_to_srgb(hsl.x, hsl.y, hsl.z)
        assert_almost_eq(back.r, sample.r, 0.01, "R of %s" % sample.to_html(false))
        assert_almost_eq(back.g, sample.g, 0.01, "G of %s" % sample.to_html(false))
        assert_almost_eq(back.b, sample.b, 0.01, "B of %s" % sample.to_html(false))


func test_oklch_survives_a_round_trip() -> void:
    for sample in SAMPLES:
        var lch := OkhslConversionsScript.srgb_to_oklch(sample)
        var back := OkhslConversionsScript.oklch_to_srgb(lch.x, lch.y, lch.z)
        assert_almost_eq(back.r, sample.r, 0.01, "R of %s" % sample.to_html(false))
        assert_almost_eq(back.g, sample.g, 0.01, "G of %s" % sample.to_html(false))
        assert_almost_eq(back.b, sample.b, 0.01, "B of %s" % sample.to_html(false))


## The claim the ok-hsl square makes: saturation is the fraction of the chroma
## the hue reaches at that lightness, so a full-saturation column is the gamut
## edge at every height and a zero one is a grey.
func test_okhsl_saturation_is_the_fraction_of_the_reachable_chroma() -> void:
    for l_step in 9:
        var l := float(l_step + 1) / 10.0
        var grey := OkhslConversionsScript.okhsl_to_srgb(0.3, 0.0, l)
        assert_true(OkhsvConversionsScript.is_achromatic(grey), "Saturation zero at l=%f is a grey" % l)

        var edge := OkhslConversionsScript.okhsl_to_srgb(0.3, 1.0, l)
        var lightness: float = OkhsvConversionsScript.toe_inv(l)
        var reachable := OkhslConversionsScript.gamut_chroma(cos(TAU * 0.3), sin(TAU * 0.3), lightness)
        assert_almost_eq(OkhslConversionsScript.srgb_to_oklch(edge).y, reachable, 0.005, "Saturation one at l=%f is the edge" % l)


## The triangle's two axes are what the note named them: Oklab lightness up
## the Y axis and Oklab chroma along X, neither of them re-scaled on the way.
## The scale the picker divides X by moved from one constant to the
## hue's own cusp, and this holds what the axes mean either way.
func test_the_triangles_axes_are_lightness_and_chroma() -> void:
    for point: Vector2 in [Vector2(0.3, 0.25), Vector2(0.5, 0.6), Vector2(0.15, 0.85)]:
        var chroma: float = point.x * OkhslConversionsScript.SRGB_MAX_CHROMA
        var read := OkhslConversionsScript.srgb_to_oklch(OkhslConversionsScript.oklch_to_srgb(0.08, chroma, point.y))
        assert_almost_eq(read.z, point.y, 0.005, "Y is the lightness asked for")
        assert_almost_eq(read.y, chroma, 0.005, "and X the chroma")


## A press past the gamut edge is a press on it, so the cursor rides the
## triangle's slope rather than sitting in the empty corner beside it.
func test_a_chroma_past_the_edge_lands_on_the_edge() -> void:
    var lightness := 0.9
    var reachable := OkhslConversionsScript.gamut_chroma(cos(TAU * 0.7), sin(TAU * 0.7), lightness)
    var clamped := OkhslConversionsScript.srgb_to_oklch(OkhslConversionsScript.oklch_to_srgb(0.7, 1.0, lightness))
    assert_almost_eq(clamped.y, reachable, 0.005, "Pulled back to the chroma this lightness holds")
    assert_almost_eq(clamped.z, lightness, 0.005, "at the lightness that was asked for")


## Black and white are the triangle's other two corners, and no hue has any
## chroma at either, which is what makes the shape a triangle rather than a box.
func test_the_triangle_closes_at_black_and_at_white() -> void:
    for h: float in [0.0, 0.25, 0.5, 0.75]:
        var angle := TAU * h
        assert_eq(OkhslConversionsScript.gamut_chroma(cos(angle), sin(angle), 0.0), 0.0, "No chroma at black")
        assert_eq(OkhslConversionsScript.gamut_chroma(cos(angle), sin(angle), 1.0), 0.0, "and none at white")
