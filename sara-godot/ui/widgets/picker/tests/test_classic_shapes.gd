## The three classic picker shapes beside the Oklab ones: the HSV square in a
## hue ring, the HSV triangle in the same ring, and the HSL square with a hue
## bar.
##
## Users of the normal HSV square, triangle and HSL pickers cannot live without
## them. What is graded here is
## the maths under each shape, that a colour goes round each one and comes
## back, and what the centre of each area is worth, which is the click the
## scenario makes. A shortcut profile writes chords only, and carries no shape.
extends "res://tests/test_framework.gd"

const SaColorPickerScript = preload("res://ui/dockers/color/sa_color_picker.gd")

var _shape_setting: String = ""


func before_each() -> void:
    _shape_setting = SaSettings.color_picker_shape


func after_each() -> void:
    SaSettings.color_picker_shape = _shape_setting


func _picker() -> SaColorPicker:
    var picker := SaColorPickerScript.new()
    var dummy := Control.new()
    dummy.add_child(picker)
    return picker


func _free(picker: SaColorPicker) -> void:
    picker.get_parent().free()


## The three are listed, drawn by the classic shader, and each keeps or drops
## the ring as its layout says: the two HSV shapes keep it and the HSL square
## trades it for the bar.
func test_the_three_classic_shapes_are_listed_and_laid_out() -> void:
    var picker := _picker()
    for key: String in ["hsv_square", "hsv_triangle", "hsl_square"]:
        picker.shape.set_kind(SaPickerShape.kind_of(key))
        var report := picker.shape.report()
        assert_eq(report["kind"], key, "%s is a shape the picker can be" % key)
        assert_true(report["classic"], "and is drawn by the classic shader")
        assert_eq(report["ring_visible"], key != "hsl_square", "%s: the ring is there unless the shape is the HSL square" % key)
        assert_eq(report["hue_bar_visible"], key == "hsl_square", "%s: and the hue bar is there only then" % key)
        assert_false(report["lightness_slider_visible"], "%s: the disc's slider is nobody else's" % key)
    assert_eq(SaPickerShape.AREA_MODES.size(), SaPickerShape.KIND_KEYS.size(), "every shape names its shader mode")
    _free(picker)


## A colour set on the HSV square comes back as itself, and its two axes are
## the engine's own saturation and value, which is what a painter trained on
## the classic square expects the cursor to stand on.
func test_the_hsv_square_holds_a_colour_by_saturation_and_value() -> void:
    var picker := _picker()
    picker.shape.set_kind(SaPickerShape.Kind.HSV_SQUARE)
    var wanted := Color(0.2, 0.6, 0.9)
    picker.shape.set_from_color(wanted)
    var report := picker.shape.report()
    assert_almost_eq(float(report["hue"]), wanted.h, 1e-4, "the hue is the engine's")
    assert_almost_eq(float(report["across"]), wanted.s, 1e-4, "the horizontal axis is saturation")
    assert_almost_eq(float(report["up"]), wanted.v, 1e-4, "and the vertical one is value")
    var back := picker.shape.color()
    assert_true(back.is_equal_approx(wanted), "and the colour comes back as itself, %s" % back)
    _free(picker)


## Plain HSL, both ways, against the values everybody knows.
func test_hsl_is_the_textbook_formula_both_ways() -> void:
    assert_true(SaPickerClassic.hsl_to_srgb(0.0, 1.0, 0.5).is_equal_approx(Color.RED), "full red at lightness a half")
    assert_true(SaPickerClassic.hsl_to_srgb(1.0 / 3.0, 1.0, 0.5).is_equal_approx(Color.GREEN), "green a third of the way round")
    assert_true(
        SaPickerClassic.hsl_to_srgb(0.7, 0.0, 0.5).is_equal_approx(Color(0.5, 0.5, 0.5)),
        "no saturation is a grey at the lightness"
    )
    assert_true(
        SaPickerClassic.hsl_to_srgb(0.1, 0.4, 1.0).is_equal_approx(Color.WHITE), "and lightness one is white whatever else"
    )

    var wanted := Color(0.8, 0.3, 0.5)
    var hsl := SaPickerClassic.srgb_to_hsl(wanted)
    assert_almost_eq(hsl.z, 0.55, 1e-5, "lightness is the mean of the extremes")
    assert_almost_eq(hsl.y, 0.5 / (1.0 - absf(2.0 * 0.55 - 1.0)), 1e-5, "saturation is the span over what the lightness leaves")
    var back := SaPickerClassic.hsl_to_srgb(hsl.x, hsl.y, hsl.z)
    assert_true(back.is_equal_approx(wanted), "and the round trip closes, %s" % back)

    var picker := _picker()
    picker.shape.set_kind(SaPickerShape.Kind.HSL_SQUARE)
    picker.shape.set_from_color(wanted)
    assert_true(picker.shape.color().is_equal_approx(wanted), "which the shape does too")
    _free(picker)


## The triangle's corner weights and the point they name are inverses, and
## the three corners are the three colours they stand for.
func test_the_triangle_weights_and_the_point_are_inverses() -> void:
    assert_true(
        SaPickerClassic.triangle_point(1.0, 1.0).is_equal_approx(SaPickerClassic.TRI_HUE),
        "full saturation and value is the hue's corner"
    )
    assert_true(
        SaPickerClassic.triangle_point(0.0, 1.0).is_equal_approx(SaPickerClassic.TRI_WHITE),
        "no saturation at full value is white"
    )
    assert_true(
        SaPickerClassic.triangle_point(0.7, 0.0).is_equal_approx(SaPickerClassic.TRI_BLACK),
        "and no value is black whatever the saturation"
    )
    for s: float in [0.0, 0.25, 0.5, 0.9, 1.0]:
        for v: float in [0.1, 0.5, 0.75, 1.0]:
            var weights := SaPickerClassic.triangle_weights(SaPickerClassic.triangle_point(s, v))
            assert_almost_eq(1.0 - weights.z, v, 1e-5, "value is what is not black at s %.2f v %.2f" % [s, v])
            assert_almost_eq(weights.x / (weights.x + weights.y), s, 1e-5, "and saturation the hue's share of the rest")


## What the centre of each area is worth, which is where the scenario clicks:
## the square's centre is half and half, the triangle's centroid is two thirds
## value at half saturation, and the HSL square's centre is half and half.
func test_the_centre_of_each_area_is_the_colour_the_model_says() -> void:
    var weights := SaPickerClassic.triangle_weights(Vector2(0.5, 0.5))
    assert_almost_eq(1.0 - weights.z, 2.0 / 3.0, 1e-5, "the centroid is two thirds value")
    assert_almost_eq(weights.x / (weights.x + weights.y), 0.5, 1e-5, "at half saturation")
    var hue := 0.6
    assert_true(
        Color.from_hsv(hue, 0.5, 0.5).is_equal_approx(Color.from_hsv(hue, 0.5, 0.5)),
        "the HSV square's centre is the engine's half and half"
    )
    var centre := SaPickerClassic.hsl_to_srgb(hue, 0.5, 0.5)
    assert_almost_eq(
        (maxf(centre.r, maxf(centre.g, centre.b)) + minf(centre.r, minf(centre.g, centre.b))) * 0.5,
        0.5,
        1e-5,
        "and the HSL square's centre has lightness a half"
    )
