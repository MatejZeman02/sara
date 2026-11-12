## A pixel function reads a neighbourhood whose reach follows a setting.
##
## `hint_reach` on a uniform's line makes its value how far the gather pads, up
## to the hint's number, `src[at]` reads as `src(at)`, and `premultiplied` and
## `straight` stand beside `src` in both wrappers. Text in, text out, so no GPU.
extends "res://tests/test_framework.gd"

const PixelSource := preload("res://core/custom-shader/dialect/sa_pixel_source.gd")
const PixelNeighbourhood := preload("res://core/custom-shader/dialect/sa_pixel_neighbourhood.gd")

## The box blur's own line, the shape every case below is a variation of.
const REACHING := (
    "uniform int radius: hint_range(1, 20), hint_reach(200) = 3\n\n" + "def pixel(ivec2 at) -> vec4:\n    return src[at]\n"
)


func _field(text: String) -> Dictionary[String, Variant]:
    return PixelNeighbourhood.reaching(PixelSource.uniforms(text))


func test_the_hinted_uniform_is_the_reach() -> void:
    var field := _field(REACHING)
    assert_eq(SaTyped.text_at(field, "name", ""), "radius", "the uniform that carries the hint is the reach")
    assert_eq(PixelNeighbourhood.ceiling(field), 200, "read as far as the hint's number")
    assert_eq(PixelSource.problems(REACHING, "blur"), PackedStringArray(), "and the file has nothing wrong with it")


func test_the_reach_is_the_value_held_kept_within_its_ceiling() -> void:
    var field := _field(REACHING)
    assert_eq(PixelNeighbourhood.reach(field, {}), 3, "with no value held it is the line's default")
    assert_eq(PixelNeighbourhood.reach(field, {"radius": 7}), 7, "and otherwise the value held")
    assert_eq(PixelNeighbourhood.reach(field, {"radius": 150.0}), 150, "a float from a record read whole")
    assert_eq(PixelNeighbourhood.reach(field, {"radius": 900}), 200, "never past the ceiling")
    assert_eq(PixelNeighbourhood.reach(field, {"radius": -4}), 0, "and never below nought")


func test_a_hint_with_no_number_reads_as_far_as_the_range() -> void:
    var field := _field(
        "uniform int size: hint_range(1, 12), hint_reach = 4\n\ndef pixel(ivec2 at) -> vec4:\n    return src(at)\n"
    )
    assert_eq(PixelNeighbourhood.ceiling(field), 12, "the range's highest is the most it reads")


func test_a_file_with_no_hint_has_no_reach() -> void:
    var field := _field("uniform float level: hint_range(0, 1) = 0.5\n\ndef pixel(ivec2 at) -> vec4:\n    return src(at)\n")
    assert_true(field.is_empty(), "a file whose margin is fixed keeps it")


func test_a_reach_that_cannot_be_one_is_a_problem() -> void:
    var floats := PixelSource.problems(
        "uniform float radius: hint_reach = 3.0\n\ndef pixel(ivec2 at) -> vec4:\n    return src(at)\n", "blur"
    )
    assert_eq(floats.size(), 1, "a float reach is refused")
    assert_true(floats[0].contains("only an int"), "saying a reach is an int: %s" % [floats])
    var twice := PixelSource.problems(
        "uniform int a: hint_reach = 1\nuniform int b: hint_reach = 2\n\ndef pixel(ivec2 at) -> vec4:\n    return src(at)\n",
        "blur"
    )
    assert_eq(twice.size(), 1, "and so is a second reach")
    assert_true(twice[0].contains("already carries it"), "naming the first: %s" % [twice])
    var nought := PixelSource.problems(
        "uniform int a: hint_reach(0) = 1\n\ndef pixel(ivec2 at) -> vec4:\n    return src(at)\n", "blur"
    )
    assert_eq(nought.size(), 1, "and a most of nought")


func test_a_bracket_on_src_reads_as_its_call() -> void:
    assert_eq(PixelNeighbourhood.bracketed("    vec4 c = src[at]"), "    vec4 c = src(at)", "a plain read")
    assert_eq(
        PixelNeighbourhood.bracketed("    sum += premultiplied(src[at + ivec2(dx, dy)])"),
        "    sum += premultiplied(src(at + ivec2(dx, dy)))",
        "a read whose index holds a call"
    )
    assert_eq(PixelNeighbourhood.bracketed("    float w = weights[i]"), "    float w = weights[i]", "an array stays an array")
    assert_eq(
        PixelNeighbourhood.bracketed("    float w = my_src[i]"), "    float w = my_src[i]", "and so does a name that ends in src"
    )
    assert_eq(
        PixelNeighbourhood.bracketed("    vec4 c = src[src[at].xy]"), "    vec4 c = src(src(at).xy)", "a read inside a read"
    )


func test_both_wrappers_offer_the_reads_beside_src() -> void:
    var fields := PixelSource.uniforms(REACHING)
    for wrapped: String in [
        PixelSource.wrap("blur", "box_blur_pixels/blur", fields), PixelSource.wrap_layered("blur", "box_blur_pixels/blur", fields)
    ]:
        assert_true(wrapped.contains("def premultiplied(vec4 color) -> vec4:"), "premultiplied is offered")
        assert_true(wrapped.contains("def straight(vec4 sum) -> vec4:"), "and straight")
    assert_true(PixelSource.body(REACHING).contains("return src(at)"), "and the body's bracket is the call")
