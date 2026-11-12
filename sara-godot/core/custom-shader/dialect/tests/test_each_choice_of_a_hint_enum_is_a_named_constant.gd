## Each choice of a `hint_enum` is a `const int` of its index the body can name,
## `DITHER_WHITE_NOISE` for the label "White noise" of `dither`, in the short
## form's wrapper and in the pass form's alike, and a name that cannot be
## formed or would clash is a problem naming it and the uniform's line.
##
## Text only, as `sa_pixel_source.gd` is, so no device is asked. That the
## constants hold what the drop-down sends is run on a layer in
## `harness/tests/test_a_kernel_names_the_choice_its_drop_down_sent.gd`.
extends "res://tests/test_framework.gd"

const Dialect := preload("res://core/custom-shader/dialect/sa_dialect.gd")
const PixelSource := preload("res://core/custom-shader/dialect/sa_pixel_source.gd")

const DITHERED := """uniform int dither: hint_enum("Bayer", "White noise", "Off") = 0

def pixel(ivec2 at) -> vec4:
    if dither == DITHER_BAYER:
        return vec4(1.0, 0.0, 0.0, 1.0)
    if dither == DITHER_WHITE_NOISE:
        return vec4(0.0, 1.0, 0.0, 1.0)
    return src(at)
"""


func _fields() -> Array:
    return PixelSource.uniforms(DITHERED)


func test_the_short_form_wrapper_declares_each_choice_at_its_index() -> void:
    assert_eq(Array(PixelSource.problems(DITHERED, "dithered")), [], "the source is a pixel function with nothing wrong")
    var wrapped := PixelSource.wrap("dithered", "cells/dithered", _fields())
    for expected: String in ["const int DITHER_BAYER = 0", "const int DITHER_WHITE_NOISE = 1", "const int DITHER_OFF = 2"]:
        assert_true(wrapped.contains("\n%s\n" % expected), "the wrapper declares %s" % expected)
    assert_true(
        wrapped.find("const int DITHER_BAYER") < wrapped.find("import cells/dithered"),
        "above the body's import, so the body is in its scope"
    )
    var glsl := Dialect.transpile(wrapped)
    assert_true(glsl.contains("const int DITHER_WHITE_NOISE = 1;"), "the dialect writes it as GLSL: %s" % glsl)


func test_the_pass_form_wrapper_declares_them_too() -> void:
    for in_place: bool in [false, true]:
        var wrapped := PixelSource.wrap_layered("dithered", "modules/dithered", _fields(), in_place)
        assert_true(
            wrapped.contains("\nconst int DITHER_OFF = 2\n"), "the pass form declares the last choice, in place %s" % in_place
        )
    var ruled := PixelSource.wrap_layered("dithered", "modules/dithered", _fields(), false, false)
    assert_true(ruled.contains("\nconst int DITHER_BAYER = 0\n"), "and the rule form")


func test_a_kernel_with_no_hint_enum_is_the_text_it_was() -> void:
    var plain := PixelSource.uniforms("uniform float level: hint_range(0, 1) = 0.5\n")
    var wrapped := PixelSource.wrap("plain", "cells/plain", plain)
    assert_false(wrapped.contains("const int"), "no constant is written")
    assert_true(wrapped.contains("    float level\n\n\ndef src("), "and the params end two blank lines above src, as they did")


func test_a_name_is_the_parameter_and_the_label_upper_cased() -> void:
    var formed := PixelSource.EnumConstants.name_of("dither", "  Blue-noise (64 px)! ")
    assert_eq(formed, "DITHER_BLUE_NOISE_64_PX", "every run of other characters is one underscore and none at the ends")
    assert_eq(PixelSource.EnumConstants.name_of("level", "2"), "LEVEL_2", "a label of digits names one after the prefix")
    assert_eq(PixelSource.EnumConstants.name_of("level", "--"), "", "a label with no letter or digit names none")


func test_two_choices_forming_one_name_are_refused_with_the_line() -> void:
    var source := "\n" + DITHERED.replace('"Off"', '"White-noise"')
    var said := " ".join(PixelSource.problems(source, "dithered"))
    assert_true(said.contains("line 2"), "the uniform's line is named: %s" % said)
    assert_true(said.contains("`DITHER_WHITE_NOISE`"), "and the constant: %s" % said)


func test_a_body_that_declares_the_constant_is_refused_with_the_line() -> void:
    var source := DITHERED.replace("\ndef pixel", "\nconst int DITHER_BAYER = 7\n\ndef pixel")
    var said := " ".join(PixelSource.problems(source, "dithered"))
    assert_true(said.contains("line 1"), "the uniform's line is named: %s" % said)
    assert_true(said.contains("`DITHER_BAYER`"), "and the constant: %s" % said)
    assert_true(said.contains("the body declares"), "and what holds it: %s" % said)


func test_a_uniform_of_that_name_is_refused_with_the_line() -> void:
    var source := DITHERED.replace("\ndef pixel", "uniform float DITHER_BAYER = 0.5\n\ndef pixel")
    var said := " ".join(PixelSource.problems(source, "dithered"))
    assert_true(said.contains("line 1"), "the enum's line is named: %s" % said)
    assert_true(said.contains("`DITHER_BAYER`"), "and the constant: %s" % said)
    assert_true(said.contains("the uniform on line 2"), "and the uniform that holds it: %s" % said)


func test_a_label_that_forms_no_name_is_refused_with_the_line() -> void:
    var source := DITHERED.replace('"Off"', '"…"')
    var said := " ".join(PixelSource.problems(source, "dithered"))
    assert_true(said.contains("line 1") and said.contains("no letter or digit"), "the label is refused: %s" % said)
