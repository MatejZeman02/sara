## Unit tests for exact OKHSV <-> sRGB colour conversions.
extends "res://tests/test_framework.gd"

const OkhsvConversionsScript = preload("res://utils/okhsv_conversions.gd")


func test_okhsv_conversions_black_white() -> void:
    var srgb_black := Color.BLACK
    var hsv_black := OkhsvConversionsScript.srgb_to_okhsv(srgb_black)
    var back_black := OkhsvConversionsScript.okhsv_to_srgb(hsv_black.x, hsv_black.y, hsv_black.z)
    assert_true(back_black.is_equal_approx(Color.BLACK), "Black should round-trip")

    var srgb_white := Color.WHITE
    var hsv_white := OkhsvConversionsScript.srgb_to_okhsv(srgb_white)
    var back_white := OkhsvConversionsScript.okhsv_to_srgb(hsv_white.x, hsv_white.y, hsv_white.z)
    assert_true(back_white.is_equal_approx(Color.WHITE), "White should round-trip")


func test_okhsv_conversions_primaries() -> void:
    var srgb_red := Color(1.0, 0.0, 0.0, 1.0)
    var hsv_red := OkhsvConversionsScript.srgb_to_okhsv(srgb_red)
    var back_red := OkhsvConversionsScript.okhsv_to_srgb(hsv_red.x, hsv_red.y, hsv_red.z)
    assert_almost_eq(back_red.r, 1.0, 0.01, "Red should round-trip approximately")
    assert_almost_eq(back_red.g, 0.0, 0.01, "Red G should be ~0")
    assert_almost_eq(back_red.b, 0.0, 0.01, "Red B should be ~0")


func test_okhsv_conversions_arbitrary() -> void:
    var test_col := Color(0.2, 0.6, 0.8, 1.0)
    var hsv_col := OkhsvConversionsScript.srgb_to_okhsv(test_col)
    var back_col := OkhsvConversionsScript.okhsv_to_srgb(hsv_col.x, hsv_col.y, hsv_col.z)
    assert_almost_eq(back_col.r, test_col.r, 0.02, "Arbitrary R should match")
    assert_almost_eq(back_col.g, test_col.g, 0.02, "Arbitrary G should match")
    assert_almost_eq(back_col.b, test_col.b, 0.02, "Arbitrary B should match")

    var test_col2 := Color(0.1, 0.5, 0.9, 1.0)
    var hsv_col2 := OkhsvConversionsScript.srgb_to_okhsv(test_col2)
    var back_col2 := OkhsvConversionsScript.okhsv_to_srgb(hsv_col2.x, hsv_col2.y, hsv_col2.z)
    assert_almost_eq(back_col2.r, test_col2.r, 0.02, "Col2 R should match")
    assert_almost_eq(back_col2.g, test_col2.g, 0.02, "Col2 G should match")
    assert_almost_eq(back_col2.b, test_col2.b, 0.02, "Col2 B should match")


## An exact grey has no direction in Oklab, and the angle a conversion
## reads off it is the rounding in the matrices. Measured at 1e-8 for
## every grey from 0.2 to 1.0, and it always answers hue 0.2497, so a pick of
## the background snapped the wheel to the same wrong place every time.
func test_a_grey_reports_no_hue_rather_than_its_rounding_error() -> void:
    for level: float in [0.0, 0.2, 0.5, 0.752941, 1.0]:
        var grey := Color(level, level, level, 1.0)
        assert_true(OkhsvConversionsScript.is_achromatic(grey), "%f grey has no hue" % level)
        assert_eq(OkhsvConversionsScript.srgb_to_okhsv(grey).x, 0.0, "and reports zero for it")


## The threshold sits below anything a 16-bit channel can hold, so a colour a
## person could distinguish keeps its own hue.
func test_a_colour_one_16_bit_step_off_grey_keeps_its_hue() -> void:
    var near_grey := Color(0.5, 0.5, 0.5 + 1.0 / 65535.0, 1.0)
    assert_false(OkhsvConversionsScript.is_achromatic(near_grey), "A 16-bit step off grey is a colour")
    assert_true(OkhsvConversionsScript.srgb_to_okhsv(near_grey).x > 0.0, "with a hue of its own")


## The golden angle walk: every step differs, none lands where an earlier one
## did, and the whole thing stays inside one turn.
func test_the_golden_angle_step_never_repeats_a_hue() -> void:
    assert_almost_eq(OkhsvConversionsScript.GOLDEN_ANGLE_TURNS, 0.381966, 1e-5, "137.5 degrees of a turn")
    var seen: Array[float] = []
    var h := 0.0
    for i in 12:
        h = OkhsvConversionsScript.step_hue(h)
        assert_true(h >= 0.0 and h < 1.0, "Step %d stays inside a turn" % i)
        for earlier in seen:
            assert_true(absf(earlier - h) > 0.05, "Step %d is not where an earlier one landed" % i)
        seen.append(h)


## Wrapping is the whole point of `fposmod` here: `fmod` would return a
## negative hue for a negative input, and the wheel would draw nothing.
func test_the_step_wraps_a_hue_from_below_zero() -> void:
    assert_almost_eq(OkhsvConversionsScript.step_hue(-0.5), 0.881966, 1e-5, "A hue below zero wraps up")
    assert_almost_eq(OkhsvConversionsScript.step_hue(0.9), 0.281966, 1e-5, "and one past the top wraps down")
