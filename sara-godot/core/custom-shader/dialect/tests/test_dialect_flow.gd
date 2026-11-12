## The dialect's control flow on its way to GLSL: `if`, `elif`, `else`, `while`,
## `match` with the `break` the transpiler inserts, `struct`, the jumps, and a
## one-line body written after the colon.
##
## A sibling of `test_dialect.gd` rather than more of it, because gdlint caps a
## script at 32 public methods and that file is at its own subject's limit. The
## pass is `sa_dialect.gd` either way, and every case here runs offscreen.
##
## The line count is asserted on every case for the reason `test_dialect.gd`
## gives: a closing brace lives on the last line of the block it closes, so a
## form that needed a line of its own would move every glslang error under it.
extends "res://tests/test_framework.gd"

## The last case hands the transpiled kernel to glslang, which needs one.
const REQUIRES_GPU := true

const Dialect := preload("res://core/custom-shader/dialect/sa_dialect.gd")
const KernelSource := preload("res://core/custom-shader/dialect/sa_kernel_source.gd")
const Bindings := preload("res://core/custom-shader/compiler/sa_bindings.gd")

## One kernel carrying every form this unit adds, for the compile proof at the
## end. Written the way a student would, `or` and all.
const FLOW_KERNEL := """kernel flow

image canvas

params:
    float mode

struct Dab:
    vec2 at
    float radius

def levels_curve(float x) -> float:
    float g = mode > 0.0 ? mode : 1.0
    return sign(x) * pow(abs(x), 1.0 / g)

@workgroup_size(8, 8)
def flow():
    ivec2 px = ivec2(gl_GlobalInvocationID.xy)
    ivec2 size = imageSize(canvas)
    if px.x >= size.x or px.y >= size.y: return
    vec4 c = imageLoad(canvas, px)
    int channel = int(mode + 0.5)
    Dab d
    d.at = vec2(px)
    d.radius = 1.0
    float v = 0.0
    while v < 1.0:
        v = v + 0.5
    match channel:
        case 0:
            v = levels_curve(c.r)
        case 4:
            v = levels_curve(c.g)
        case _:
            v = 0.0
    for i in range(0, 3):
        v = v + float(i) * d.radius
    imageStore(canvas, px, vec4(v, c.gba))
"""

## The six `#define` aliases of `shaders/compute/adjust.gmacs` and the function
## that reads them, written as the dialect. The spec names this as the example
## of what the sweep does: "The six `#define` aliases in the levels kernel become
## functions."
const LEVELS_DIALECT := """def lv_in_black() -> float:
    return brightness


def lv_in_gamma() -> float:
    return contrast


def lv_in_white() -> float:
    return hue


def lv_out_black() -> float:
    return saturation


def lv_out_white() -> float:
    return lightness


def lv_channel() -> float:
    return spare


def levels_curve(float x) -> float:
    float span = lv_in_white() - lv_in_black()
    float v = span != 0.0 ? (x - lv_in_black()) / span : x - lv_in_black()
    float g = lv_in_gamma() > 0.0 ? lv_in_gamma() : 1.0
    v = sign(v) * pow(abs(v), 1.0 / g)
    return lv_out_black() + v * (lv_out_white() - lv_out_black())
"""

## The same six and the same function in GLSL, the body quoted from
## `shaders/compute/adjust.gmacs` with each `LV_` alias reading as the call that
## replaces it. The aliases read `brightness` rather than `p.brightness` because
## the maintainers' decision of 2026-09-07 takes the `p.` prefix off, and the block
## the dialect writes is anonymous.
##
## Quoted rather than read off the file, because that file is converted and the
## GLSL half of this comparison has to survive it.
const LEVELS_GLSL := """float lv_in_black() { return brightness; }
float lv_in_gamma() { return contrast; }
float lv_in_white() { return hue; }
float lv_out_black() { return saturation; }
float lv_out_white() { return lightness; }
float lv_channel() { return spare; }
float levels_curve( float x )
{
    float span = lv_in_white() - lv_in_black();
    float v = span != 0.0 ? ( x - lv_in_black() ) / span : x - lv_in_black();
    float g = lv_in_gamma() > 0.0 ? lv_in_gamma() : 1.0;
    v = sign( v ) * pow( abs( v ), 1.0 / g );
    return lv_out_black() + v * ( lv_out_white() - lv_out_black() );
}
"""


## The count of lines in and out, which every case below asserts through here.
func _lines_held(source: String, message: String) -> String:
    var glsl := Dialect.transpile(source)
    assert_eq(glsl.split("\n").size(), source.split("\n").size(), message)
    return glsl


## *glsl* with the whitespace that carries no meaning taken out, so two spellings
## of the same program compare equal. Whitespace runs collapse to one space and a
## space beside anything that is not a letter, a digit or an underscore goes.
func _normalized(glsl: String) -> String:
    var collapse := RegEx.new()
    collapse.compile("\\s+")
    var beside_punctuation := RegEx.new()
    beside_punctuation.compile("\\s+(?=[^\\w\\s])|(?<=[^\\w\\s])\\s+")
    return beside_punctuation.sub(collapse.sub(glsl.strip_edges(), " ", true), "", true)


# --- if, elif, else and while ---------------------------------------------------


func test_if_elif_and_else_take_their_parentheses() -> void:
    var source := "if a > 1:\n    x = 1\nelif b > 2:\n    x = 2\nelse:\n    x = 3\n"

    var glsl := _lines_held(source, "Six lines in, six out")

    assert_eq(
        glsl,
        "if (a > 1) {\n    x = 1;}\nelse if (b > 2) {\n    x = 2;}\nelse {\n    x = 3;}\n",
        "Each branch closes on its own last line and the next one opens under it"
    )


func test_while_takes_its_parentheses() -> void:
    var glsl := _lines_held("while i < 4:\n    i = i + 1\n", "Two lines")

    assert_eq(glsl, "while (i < 4) {\n    i = i + 1;}\n", "The condition is GLSL's already, only the shape moves")


## The spec's own example of the form, `if x >= size.x: return`.
func test_a_one_line_body_after_the_colon_closes_on_the_spot() -> void:
    var glsl := _lines_held("if x >= size.x: return\ntail = 1\n", "Two lines in, two out")

    assert_eq(glsl, "if (x >= size.x) { return; }\ntail = 1;\n", "The block opens and closes on the line it is on")


## The colon of a ternary answers a `?` and belongs to GLSL, so it must not be
## read as the end of a header. Both directions matter: a bare ternary is a
## statement, and a header whose one-line body holds a ternary still splits at
## the header's own colon.
func test_a_ternary_colon_is_not_a_header_colon() -> void:
    var bare := _lines_held("v = a > 0.0 ? b : c\n", "One line")
    var inside := Dialect.transpile("if x > 0: v = a > 0.0 ? b : c\n")

    assert_eq(bare, "v = a > 0.0 ? b : c;\n", "A ternary is an expression and the pass never touches one")
    assert_eq(inside, "if (x > 0) { v = a > 0.0 ? b : c; }\n", "The header's colon is the first one no `?` is waiting on")


# --- match -----------------------------------------------------------------------


func test_match_becomes_a_switch_with_the_break_inserted() -> void:
    var source := "match channel:\n    case 0:\n        x = 1\n    case 4:\n        x = 2\ntail = 3\n"

    var glsl := _lines_held(source, "Six lines in, six out")

    assert_eq(
        glsl,
        "switch (channel) {\n    case 0:\n        x = 1; break;\n    case 4:\n        x = 2; break;}\ntail = 3;\n",
        "A case needs no braces, so its closer is the break and the switch's brace lands on the last case"
    )


## The spec has the transpiler insert "the `break` each case needs", and a case
## that already left needs none. A second `break` there is unreachable code the
## student did not write.
func test_a_case_that_already_left_takes_no_break() -> void:
    var source := "match channel:\n    case 0:\n        return 1.0\n    case 4:\n        break\n"

    var glsl := _lines_held(source, "Five lines in, five out")

    assert_eq(glsl.count("break"), 1, "Only the one the file wrote itself")
    assert_true("        return 1.0;\n" in glsl, "A case that returned is closed already")


## Python's wildcard, which is the spelling a student who writes `match` already
## knows. The spec listed `case 1:` and said nothing about a fallback, so this is
## the case written into it.
func test_case_underscore_is_the_default_label() -> void:
    var source := "match channel:\n    case _:\n        x = 1\n"

    var glsl := _lines_held(source, "Three lines in, three out")

    assert_true("default:\n" in glsl, "`case _:` is GLSL's default label")
    assert_true(glsl.ends_with("        x = 1; break;}\n"), "It closes the way every other case does")


func test_a_one_line_case_carries_its_break_too() -> void:
    var glsl := _lines_held("match channel:\n    case 0: x = 1\n", "Two lines in, two out")

    assert_true("case 0: x = 1; break;" in glsl, "A one-line case is still a case")


# --- struct and the jumps --------------------------------------------------------


func test_a_struct_closes_with_a_semicolon_on_its_last_field() -> void:
    var glsl := _lines_held("struct Dab:\n    vec2 at\n    float radius\n", "Three lines in, three out")

    assert_eq(
        glsl,
        "struct Dab {\n    vec2 at;\n    float radius;};\n",
        "A struct declaration ends in a semicolon, which is the one closer that is not a bare brace"
    )


## `return`, `break`, `continue` and `discard` are GLSL's own and the pass does
## nothing to them but end the statement.
func test_the_jump_statements_pass_through() -> void:
    var source := "def f():\n    return\ndef g():\n    continue\ndef h():\n    discard\n"

    var glsl := _lines_held(source, "Six lines in, six out")

    assert_true("    return;}\n" in glsl, "return")
    assert_true("    continue;}\n" in glsl, "continue")
    assert_true("    discard;}\n" in glsl, "discard")


# --- The levels aliases, which is what the sweep does ----------------------------


## The example the spec names for the sweep: the six `#define` aliases of the
## levels kernel become functions. Written both ways here and compared with the
## whitespace normalized away, so the claim is that the dialect and the GLSL are
## the same program rather than that they read alike.
func test_the_levels_aliases_become_functions_with_the_same_body() -> void:
    var glsl := _lines_held(LEVELS_DIALECT, "Every line of the fixture survives")

    assert_eq(_normalized(glsl), _normalized(LEVELS_GLSL), "The same six functions and the same curve")


## The half of that comparison the normalization could hide. A ternary is the
## one expression in the levels curve that could have been eaten by the header
## scan, and it survives twice on one line.
func test_the_levels_curve_keeps_both_of_its_ternaries() -> void:
    var glsl := Dialect.transpile(LEVELS_DIALECT)

    assert_true("float v = span != 0.0 ? (x - lv_in_black()) / span : x - lv_in_black();" in glsl, "the first")
    assert_true("float g = lv_in_gamma() > 0.0 ? lv_in_gamma() : 1.0;" in glsl, "the second")


## Every form this unit added, in one kernel, transpiled and handed to glslang.
##
## The string comparisons above say the pass writes the GLSL it meant to. This
## one says that GLSL is a program: a `switch` whose cases carry the inserted
## `break`, a `struct` closing with a semicolon on its last field, a one-line
## `if` body and a `while` all sit inside a kernel the compiler front end turns
## into `main`, and glslang reports nothing. It is the only case here that needs
## a RenderingDevice, and it is why this suite declares one.
func test_every_control_flow_form_compiles() -> void:
    var clean := KernelSource.remove_comments(Dialect.transpile(FLOW_KERNEL))
    clean = Bindings.substitute(clean, "rgba32f", {})
    var assembled := KernelSource.assemble_glsl(
        KernelSource.extract_numthreads("flow", clean), KernelSource.replace_kernel_signature("flow", clean)
    )
    var source := RDShaderSource.new()
    source.language = RenderingDevice.SHADER_LANGUAGE_GLSL
    source.source_compute = assembled

    var spirv := RenderingServer.get_rendering_device().shader_compile_spirv_from_source(source, false)

    var reported := spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
    assert_eq(reported, "", "glslang read every form this unit writes")


## The three shapes `range` alone cannot write, and which nine of the
## tree's twenty-four loops are written in. Each comes out as the loop that was
## there rather than as one counting the same values a different way, because
## the sweep's proof is the SPIR-V and `i < r + 1` is not `i <= r`.
func test_an_inclusive_range_closes_the_bound() -> void:
    var closed := _lines_held("for dx in range_inclusive(-r, r):\n    a = dx\n", "Two lines")
    var stepped := Dialect.transpile("for i in range_inclusive(0, 16, 4):\n    a = i\n")

    assert_eq(closed, "for (int dx = -r; dx <= r; dx++) {\n    a = dx;}\n", "The bound is closed and the step is one")
    assert_true(stepped.begins_with("for (int i = 0; i <= 16; i += 4) {"), "A step it takes as well")


func test_a_negative_literal_step_counts_down() -> void:
    var down := Dialect.transpile("for x in range_inclusive(w - 1, 0, -1):\n    a = x\n")
    var by_two := Dialect.transpile("for x in range_inclusive(9, 0, -2):\n    a = x\n")
    var held := Dialect.transpile("for x in range_inclusive(9, 0, step):\n    a = x\n")

    assert_true(down.begins_with("for (int x = w - 1; x >= 0; x--) {"), "A step of -1 is a decrement and the test flips")
    assert_true(by_two.begins_with("for (int x = 9; x >= 0; x += -2) {"), "Any other negative literal flips it too")
    assert_true(held.begins_with("for (int x = 9; x <= 0; x += step) {"), "A step in a variable could be either, so it counts up")


func test_a_counter_names_a_type_that_is_not_int() -> void:
    var counted := Dialect.transpile("for uint i in range(0u, N):\n    a = i\n")
    var closed := Dialect.transpile("for uint i in range_inclusive(0u, N):\n    a = i\n")

    assert_true(counted.begins_with("for (uint i = 0u; i < N; i++) {"), "The type before the name is the counter's")
    assert_true(closed.begins_with("for (uint i = 0u; i <= N; i++) {"), "And it goes with either range")


func test_a_range_of_one_argument_counts_from_nought() -> void:
    var int_loop := _lines_held("for i in range(4):\n    a = i\n", "Two lines")
    var uint_loop := Dialect.transpile("for uint i in range(n):\n    a = i\n")
    var closed_int := Dialect.transpile("for i in range_inclusive(4):\n    a = i\n")
    var closed_uint := Dialect.transpile("for uint i in range_inclusive(n):\n    a = i\n")
    var two_args := Dialect.transpile("for i in range(0, 4):\n    a = i\n")
    var two_args_uint := Dialect.transpile("for uint i in range(0u, n):\n    a = i\n")
    var three_args := Dialect.transpile("for i in range(0, 16, 4):\n    a = i\n")

    assert_eq(int_loop, "for (int i = 0; i < 4; i++) {\n    a = i;}\n", "An int counter counts from nought")
    assert_true(uint_loop.begins_with("for (uint i = 0u; i < n; i++) {"), "A uint counter starts at 0u")
    assert_true(closed_int.begins_with("for (int i = 0; i <= 4; i++) {"), "An inclusive int counter counts from nought")
    assert_true(closed_uint.begins_with("for (uint i = 0u; i <= n; i++) {"), "An inclusive uint counter starts at 0u")
    assert_true(two_args.begins_with("for (int i = 0; i < 4; i++) {"), "Two arguments keep their meaning")
    assert_true(two_args_uint.begins_with("for (uint i = 0u; i < n; i++) {"), "Two arguments for uint keep their meaning")
    assert_true(three_args.begins_with("for (int i = 0; i < 16; i += 4) {"), "Three arguments keep their meaning")
