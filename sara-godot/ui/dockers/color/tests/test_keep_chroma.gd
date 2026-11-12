## The colour docker's wheel has a Keep chroma switch, under which a turn of the
## hue ring holds the colour's Oklab lightness and its distance from the a,b origin.
##
## Driven through the docker's own option and the shape's ring gesture, on one
## shape of each family: the Wheel, the Triangle and the HSV square.
extends "res://tests/test_framework.gd"

const SaColorPickerScript = preload("res://ui/dockers/color/sa_color_picker.gd")
const OkhslConversionsScript = preload("res://utils/okhsl_conversions.gd")

const CYAN := Color(0.0, 1.0, 1.0, 1.0)
const YELLOW := Color(1.0, 1.0, 0.0, 1.0)
const SHAPES: Array[int] = [SaPickerShape.Kind.WHEEL, SaPickerShape.Kind.TRIANGLE, SaPickerShape.Kind.HSV_SQUARE]


func _picker(keep: bool) -> SaColorPicker:
    var picker := SaColorPickerScript.new()
    picker._register_keep_chroma_option()
    SaSettings.set_docker_option("ColorPicker", SaColorPickerScript.KEEP_CHROMA_KEY, keep)
    picker.apply_shape_setting()
    return picker


func _done(picker: SaColorPicker, shape_was: String) -> void:
    SaSettings.set_docker_option("ColorPicker", SaColorPickerScript.KEEP_CHROMA_KEY, false)
    SaSettings.color_picker_shape = shape_was
    picker.free()


## Turns the ring to where *col* sits on it, the way a pointer on the ring would.
func _turn_to(picker: SaColorPicker, col: Color) -> void:
    var shape := picker.shape
    var classic := SaPickerShape.is_classic(shape.kind)
    var at_hue := col.h if classic else OkhslConversionsScript.srgb_to_oklch(col).x
    shape._drag_ring(Vector2.from_angle(TAU * SaPickerShape.ring_angle(at_hue, classic)) * 100.0)


func _lch(col: Color) -> Vector3:
    return OkhslConversionsScript.srgb_to_oklch(col)


func test_the_switch_is_a_docker_option_and_off_by_default() -> void:
    var picker := SaColorPickerScript.new()
    picker._register_keep_chroma_option()
    var found := {}
    for option: Dictionary in SaSettings.docker_options("ColorPicker"):
        if option["key"] == SaColorPickerScript.KEEP_CHROMA_KEY:
            found = option
    assert_eq(found.get("kind"), SaSettingsLayout.OPTION_SWITCH, "Keep chroma is a switch on the docker's page")
    assert_eq(found.get("default"), false, "and it is off unless the painter turns it on")
    picker.apply_shape_setting()
    assert_false(picker.shape.keep_chroma, "so a fresh picker turns its ring the way it did before")
    picker.free()


## Cyan to yellow keeps L and chroma, since yellow holds more at cyan's
## lightness than cyan has.
func test_cyan_to_yellow_keeps_lightness_and_chroma() -> void:
    var was: String = SaSettings.color_picker_shape
    var picker := _picker(true)
    for kind: int in SHAPES:
        picker.set_shape_kind(kind)
        picker.apply_shape_setting()
        picker.shape.set_from_color(CYAN)
        var before := _lch(picker.shape.color())
        _turn_to(picker, YELLOW)
        var after := _lch(picker.shape.color())
        var name: String = SaPickerShape.KIND_KEYS[kind]
        assert_almost_eq(after.z, before.z, 0.003, "%s: the Oklab lightness is the cyan's" % name)
        assert_almost_eq(after.y, before.y, 0.003, "%s: and so is the distance from grey" % name)
        assert_true(absf(after.x - _lch(YELLOW).x) < 0.03, "%s: at a yellow hue, %.3f" % [name, after.x])
    _done(picker, was)


## Yellow to cyan cannot keep a saturated yellow's chroma, so the point stops
## on the gamut's edge, and turning back to yellow in the same gesture gives the
## yellow the gesture started from.
func test_yellow_to_cyan_stops_at_the_edge_and_comes_back() -> void:
    var was: String = SaSettings.color_picker_shape
    var picker := _picker(true)
    for kind: int in SHAPES:
        picker.set_shape_kind(kind)
        picker.apply_shape_setting()
        picker.shape.set_from_color(YELLOW)
        var first := picker.shape.color()
        var before := _lch(first)
        _turn_to(picker, CYAN)
        var at_cyan := _lch(picker.shape.color())
        var angle := TAU * at_cyan.x
        var edge := OkhslConversionsScript.gamut_chroma(cos(angle), sin(angle), at_cyan.z)
        var name: String = SaPickerShape.KIND_KEYS[kind]
        assert_almost_eq(at_cyan.z, before.z, 0.003, "%s: the lightness is kept at cyan" % name)
        assert_true(at_cyan.y < before.y * 0.5, "%s: cyan holds far less chroma there, %.3f" % [name, at_cyan.y])
        assert_almost_eq(at_cyan.y, edge, 0.004, "%s: and the point sits on the gamut's edge" % name)
        _turn_to(picker, YELLOW)
        var back := picker.shape.color()
        assert_almost_eq(back.r, first.r, 0.004, "%s: back at yellow, red is the first colour's" % name)
        assert_almost_eq(back.g, first.g, 0.004, "%s: green" % name)
        assert_almost_eq(back.b, first.b, 0.004, "%s: and blue" % name)
    _done(picker, was)


## With the switch off a ring turn writes the hue and leaves both axes where
## they were, which is what it did before the switch existed.
func test_off_leaves_the_axes_alone() -> void:
    var was: String = SaSettings.color_picker_shape
    var picker := _picker(false)
    for kind: int in SHAPES:
        picker.set_shape_kind(kind)
        picker.apply_shape_setting()
        picker.shape.set_from_color(CYAN)
        var before := picker.shape.report()
        _turn_to(picker, YELLOW)
        var after := picker.shape.report()
        var name: String = SaPickerShape.KIND_KEYS[kind]
        assert_almost_eq(float(after["across"]), float(before["across"]), 1e-6, "%s: across is untouched" % name)
        assert_almost_eq(float(after["up"]), float(before["up"]), 1e-6, "%s: and so is up" % name)
    _done(picker, was)
