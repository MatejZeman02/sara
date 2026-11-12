## A P3 display can be told to act like sRGB, evenly or not.
##
## The three matrices for an sRGB document on a Display P3 panel, which is a common
## desktop: Correct is the profile's own, Native is the identity, and
## Even stretches every primary by one Oklab chroma ratio, blue setting it.
extends "res://tests/test_framework.gd"

const EPSILON := 0.0005

var _saved_fill: String = ""
var _saved_profile: String = ""


func before_each() -> void:
    _saved_fill = SaSettings.display_fill
    _saved_profile = SaSettings.display_profile


func after_each() -> void:
    SaSettings.display_fill = _saved_fill
    SaSettings.display_profile = _saved_profile


func _assert_basis(actual: Basis, expected: Basis, message: String) -> void:
    for column in 3:
        for row in 3:
            assert_almost_eq(actual[column][row], expected[column][row], EPSILON, "%s, column %d row %d" % [message, column, row])


## Oklab chroma over lightness, and hue. Scaling a linear colour scales L, a and b
## by one cube root together, so this pair is what a colour keeps whatever
## intensity a matrix hands it, and a white-preserving matrix sets each primary's
## intensity rather than keeping it.
static func _saturation_and_hue(linear_srgb: Vector3) -> Vector2:
    var lab := SaOklab.from_linear_srgb(linear_srgb)
    return Vector2(sqrt(lab.y * lab.y + lab.z * lab.z) / maxf(lab.x, 0.000001), atan2(lab.z, lab.y))


func test_correct_is_the_profiles_own_matrix() -> void:
    var p3 := SaColorSpace.display_p3()
    var correct := SaDisplayFill.matrix(SaDisplayFill.CORRECT, SaColorSpace.srgb(), p3)
    _assert_basis(correct, p3.to_linear_srgb_matrix().inverse(), "Correct converts into the P3 panel's primaries")
    assert_eq(
        SaDisplayFill.matrix(SaDisplayFill.CORRECT, SaColorSpace.display_p3(), SaColorSpace.srgb()),
        Basis.IDENTITY,
        "and on an sRGB panel it is the identity exactly, whatever the document"
    )


func test_native_sends_the_documents_numbers_unconverted() -> void:
    assert_eq(
        SaDisplayFill.matrix(SaDisplayFill.NATIVE, SaColorSpace.srgb(), SaColorSpace.display_p3()),
        Basis.IDENTITY,
        "an sRGB document's numbers go to the P3 panel as they are"
    )
    var from_p3 := SaDisplayFill.matrix(SaDisplayFill.NATIVE, SaColorSpace.display_p3(), SaColorSpace.srgb())
    _assert_basis(from_p3, SaColorSpace.display_p3().from_linear_srgb_matrix(), "and a P3 document's are its own linear RGB")


## The note's equal stretch. Display P3's blue is sRGB's blue to the last digit,
## so blue has no room at all and the one ratio is 1: on a P3 panel Even
## is Correct, which the record says, and on a Rec. 2020 panel it is not.
func test_even_stretches_every_primary_by_the_ratio_blue_sets() -> void:
    var srgb := SaColorSpace.srgb()
    var p3 := SaColorSpace.display_p3()
    var ratios := SaDisplayFill.stretch_ratios(srgb, p3)
    assert_true(ratios[0] > 1.05, "red has room on a P3 panel, %f" % ratios[0])
    assert_true(ratios[1] > 1.05, "and green has more, %f" % ratios[1])
    assert_almost_eq(ratios[2], 1.0, 0.001, "and blue has none, because the two gamuts share it")
    assert_eq(SaDisplayFill.limiting_primary(srgb, p3), 2, "so blue is the one that sets the ratio")
    var even_on_p3 := SaDisplayFill.matrix(SaDisplayFill.EVEN, srgb, p3)
    _assert_basis(even_on_p3, p3.to_linear_srgb_matrix().inverse(), "which makes Even Correct here")
    assert_eq(SaDisplayFill.limiting_primary(srgb, SaColorSpace.rec2020()), 2, "blue sets it on Rec. 2020 as well")

    for display: SaColorSpace in [p3, SaColorSpace.rec2020()]:
        var ratio := SaDisplayFill.even_ratio(srgb, display)
        var even := SaDisplayFill.matrix(SaDisplayFill.EVEN, srgb, display)
        var to_srgb := display.to_linear_srgb_matrix()
        for channel in 3:
            var unit := Vector3.ZERO
            unit[channel] = 1.0
            var before := _saturation_and_hue(unit)
            var on_panel: Vector3 = even * unit
            var after := _saturation_and_hue(to_srgb * on_panel)
            var label := "%s primary %d" % [display.id, channel]
            assert_almost_eq(after.x / before.x, ratio, 0.002, "%s moves out by the one ratio" % label)
            assert_almost_eq(after.y, before.y, 0.002, "%s keeps its hue" % label)
            assert_true(minf(on_panel.x, minf(on_panel.y, on_panel.z)) > -0.0001, "%s stays on the panel" % label)
        # White is white, because the stretched primaries are normalised to it.
        var white: Vector3 = to_srgb * (even * Vector3.ONE)
        assert_almost_eq(white.x, white.y, 0.001, "%s: white keeps red equal to green" % display.id)
        assert_almost_eq(white.z, white.y, 0.001, "%s: and blue to green" % display.id)
    var wide := SaDisplayFill.even_ratio(srgb, SaColorSpace.rec2020())
    assert_true(wide > 1.05, "a Rec. 2020 panel lets blue stretch too, %f" % wide)


func test_a_document_wider_than_the_panel_is_shrunk_evenly_rather_than_clipped() -> void:
    var ratio := SaDisplayFill.even_ratio(SaColorSpace.display_p3(), SaColorSpace.srgb())
    assert_true(ratio < 1.0, "P3 on an sRGB panel stretches by less than one, %f" % ratio)


func test_the_preference_refuses_a_fill_it_does_not_know() -> void:
    SaSettings.display_fill = "sideways"
    assert_eq(SaSettings.display_fill, SaDisplayFill.CORRECT, "an unknown fill reads as Correct")
    SaSettings.display_fill = SaDisplayFill.EVEN
    assert_eq(SaSettings.display_fill, SaDisplayFill.EVEN, "and a known one is kept")


func test_the_report_carries_all_three_matrices() -> void:
    var report := SaDisplayFill.report(SaDisplayFill.NATIVE, SaColorSpace.srgb(), SaColorSpace.display_p3())
    assert_eq(report["name"], "Unconverted", "the report names the fill that is on")
    for key: String in ["correct", "native", "even"]:
        assert_eq((report[key] as Array).size(), 3, "and carries the %s matrix as three rows" % key)
    assert_eq(report["even_set_by"], "blue", "and which primary set the stretch")
