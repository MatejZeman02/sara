#!/usr/bin/env python3
"""The GLSL to dialect converter, one case per rewrite it claims.

    cd sara-godot && python3 -m unittest scripts.test_gmacs_convert

The first case is the reference one: `blur_x` written in
GLSL comes out as the documented dialect text, byte for byte, so the two pages
cannot drift from each other without this failing. The rest take one rewrite
each, because a fixture that covers everything says only that something broke.
"""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPTS))

import gmacs_convert as convert  # noqa: E402

## `blur_x` of the scripting specification, written the way the tree writes GLSL
## today: the kernel directive, the include, the four declarations, the
## attribute on the signature, and a trailing pad closing the push constant
## block on sixteen bytes.
BLUR_X_GLSL = """\
#kernel blur_x
#include "gaussian"

layout(SA_STORAGE_FORMAT, set = 0, binding = 0) uniform readonly image2D src;
layout(SA_STORAGE_FORMAT, set = 0, binding = 1) uniform image2D dst;

layout(push_constant, std430) uniform Params {
    float sigma;
    int radius;
    float _pad0;
    float _pad1;
}
p;

[numthreads(8, 8, 1)] void blur_x() {
    ivec2 pixel = ivec2(gl_GlobalInvocationID.xy);
    vec4 sum = vec4(0.0);
    float weight = 0.0;
    for (int i = -p.radius; i < p.radius + 1; i++) {
        float w = gaussian(float(i), p.sigma);
        sum += w * imageLoad(src, pixel + ivec2(i, 0));
        weight += w;
    }
    imageStore(dst, pixel, sum / weight);
}


float luminance(vec3 c) {
    return dot(c, vec3(0.2126, 0.7152, 0.0722));
}
"""

## The same kernel as the scripting specification prints it, quoted here so the
## comparison is against that page and not against the converter's own habits.
BLUR_X_DIALECT = """\
kernel blur_x
import gaussian

image src: readonly
image dst

params:
    float sigma
    int radius

def blur_x():
    vec4 sum = vec4(0.0)
    float weight = 0.0
    for i in range(-radius, radius + 1):
        float w = gaussian(float(i), sigma)
        sum += w * image_load(src, pixel + ivec2(i, 0))
        weight += w
    image_store(dst, pixel, sum / weight)


def luminance(vec3 c) -> float:
    return dot(c, vec3(0.2126, 0.7152, 0.0722))
"""


def converted(text: str) -> str:
    return convert.convert(text)[0]


def notes(text: str) -> list[str]:
    return convert.convert(text)[1]


class TheSpecsKernel(unittest.TestCase):
    def test_blur_x_comes_out_as_the_spec_prints_it(self) -> None:
        self.assertEqual(BLUR_X_DIALECT, converted(BLUR_X_GLSL))

    def test_blur_x_needs_no_hand(self) -> None:
        self.assertEqual([], notes(BLUR_X_GLSL))


class BracesAndSemicolons(unittest.TestCase):
    def test_a_brace_on_its_own_line_goes_back_on_the_header(self) -> None:
        source = "void f()\n{\n    int a = 1;\n}\n"
        self.assertEqual("def f():\n    int a = 1\n", converted(source))

    def test_nesting_is_four_spaces_a_level(self) -> None:
        source = "void f() {\n    if (a) {\n        while (b) {\n            c();\n        }\n    }\n}\n"
        self.assertIn("            c()\n", converted(source))

    def test_a_statement_broken_over_lines_keeps_its_shape(self) -> None:
        source = "void f() {\n    float x = mix(a,\n                  b, t);\n}\n"
        self.assertEqual("def f():\n    float x = mix(a,\n                  b, t)\n", converted(source))


class BrokenStatements(unittest.TestCase):
    def test_a_break_outside_the_brackets_is_joined(self) -> None:
        source = "void f() {\n    return all(a)\n        && all(b);\n}\n"
        self.assertEqual("def f():\n    return all(a) and all(b)\n", converted(source))

    def test_a_break_inside_them_is_left_where_it_was(self) -> None:
        source = "void f() {\n    return mat3(\n        a, b,\n        c, d\n    );\n}\n"
        self.assertIn("    return mat3(\n", converted(source))


class Declarations(unittest.TestCase):
    def test_the_storage_image_is_bare(self) -> None:
        source = "layout( SA_STORAGE_FORMAT, set = 0, binding = 0 ) uniform image2D canvas;\n"
        self.assertEqual("image canvas\n", converted(source))

    def test_a_format_and_a_qualifier_come_after_the_colon(self) -> None:
        source = "layout( r32f, set = 0, binding = 1 ) uniform readonly image2D mask;\n"
        self.assertEqual("image mask: r32f, readonly\n", converted(source))

    def test_the_sampler(self) -> None:
        source = "layout( set = 0, binding = 2 ) uniform sampler2D tip;\n"
        self.assertEqual("sampler tip\n", converted(source))

    def test_a_buffer_written_over_five_lines_becomes_one(self) -> None:
        source = "layout( std430, set = 0, binding = 4 ) buffer Flood\n{\n    uint changed;\n    uint pad1;\n}\nflood;\n"
        self.assertEqual("buffer flood: uint changed; uint pad1\n", converted(source))

    def test_a_members_comment_goes_above_the_buffer_and_is_noted(self) -> None:
        source = (
            "layout( std430, set = 0, binding = 4 ) buffer Flood\n{\n    uint changed;\n"
            "    // What is behind the picture at the seed.\n    vec4 backdrop;\n}\nflood;\n"
        )
        expected = "# What is behind the picture at the seed.\nbuffer flood: uint changed; vec4 backdrop\n"
        self.assertEqual(expected, converted(source))
        self.assertEqual(1, len(notes(source)))

    def test_the_buffer(self) -> None:
        source = "layout( std430, set = 0, binding = 3 ) buffer Table { float values[]; } table;\n"
        self.assertEqual("buffer table: float values[]\n", converted(source))


class ThePushConstantBlock(unittest.TestCase):
    def test_the_block_becomes_params_and_the_instance_goes(self) -> None:
        source = "layout( push_constant, std430 ) uniform Params\n{\n    float opacity;\n    float _pad0;\n" "    float _pad1;\n    float _pad2;\n}\np;\n"
        self.assertEqual("params:\n    float opacity\n", converted(source))

    def test_a_read_loses_its_prefix(self) -> None:
        source = "layout( push_constant, std430 ) uniform Params\n{\n    vec4 color;\n}\np;\n\nvoid f()\n{\n    x = p.color.rgb;\n}\n"
        self.assertIn("    x = color.rgb\n", converted(source))

    def test_a_pad_the_transpiler_cannot_write_back_stays(self) -> None:
        source = "layout( push_constant, std430 ) uniform Params\n{\n    vec2 offset;\n    vec2 pad;\n}\np;\n"
        self.assertEqual("params:\n    vec2 offset\n    vec2 pad\n", converted(source))
        self.assertEqual(1, len(notes(source)))


class TheDecorator(unittest.TestCase):
    def test_the_attribute_becomes_the_decorator(self) -> None:
        source = "#kernel f\n[numthreads( 8, 8, 1 )] void f() {\n    return;\n}\n"
        self.assertEqual("kernel f\ndef f():\n    return\n", converted(source))

    def test_the_default_size_writes_no_decorator_and_another_does(self) -> None:
        source = "[numthreads( 16, 8, 1 )] void f() {\n    return;\n}\n"
        self.assertIn("@workgroup_size(16, 8)\n", converted(source))

    def test_a_one_dimensional_kernel_writes_one_number(self) -> None:
        source = "[numthreads( 64, 1, 1 )] void f() {\n    return;\n}\n"
        self.assertIn("@workgroup_size(64)\n", converted(source))

    def test_the_attribute_on_a_line_of_its_own_goes(self) -> None:
        source = "#kernel f\n[numthreads( 8, 8, 1 )]\nlayout( SA_STORAGE_FORMAT, set = 0, binding = 0 ) uniform image2D t;\n"
        self.assertEqual("kernel f\nimage t\n", converted(source))


class TheDirectives(unittest.TestCase):
    def test_kernel_and_include_lose_their_hash(self) -> None:
        source = '#kernel fill\n#include "transfer_curve"\n'
        self.assertEqual("kernel fill\nimport transfer_curve\n", converted(source))

    def test_an_owner_qualified_include_keeps_its_slash(self) -> None:
        self.assertEqual("import mixing/noise\n", converted('#include "mixing/noise"\n'))

    def test_a_define_is_left_where_it_stands(self) -> None:
        converted_text = converted("#define TAU 6.28318\n")
        self.assertIn(convert.MARK, converted_text)
        self.assertIn("#define TAU 6.28318", converted_text)


class Comments(unittest.TestCase):
    def test_a_line_comment_becomes_a_hash(self) -> None:
        self.assertEqual("# why this is here\n", converted("// why this is here\n"))

    def test_a_trailing_comment_stays_on_its_line(self) -> None:
        source = "layout( push_constant, std430 ) uniform Params\n{\n    float lock; // 0.0 = off\n    vec2 pad;\n}\np;\n"
        self.assertIn("    float lock  # 0.0 = off\n", converted(source))

    def test_a_block_comment_becomes_a_run_of_hashes(self) -> None:
        source = "/*\n* Kernel: fill\n* Fills a chunk.\n*/\n"
        self.assertEqual("# Kernel: fill\n# Fills a chunk.\n", converted(source))

    def test_a_hash_in_a_comment_is_not_rewritten(self) -> None:
        self.assertEqual("# imageLoad reads a texel\n", converted("// imageLoad reads a texel\n"))

    def test_a_list_inside_a_block_comment_keeps_its_indentation(self) -> None:
        """Every comment fragment was stripped outright, so a list, a
        formula or a code block written inside a header came out flush against
        the hash and reached the reader as a wall of prose. One space after the
        `*` is the marker's and goes. What a painter indented past it stays.
        """
        source = "/*\n * Four groups:\n *   - one, which\n *     continues here\n * and prose after them.\n */\n"

        self.assertEqual(
            "# Four groups:\n#   - one, which\n#     continues here\n# and prose after them.\n", converted(source)
        )

    def test_a_line_comment_keeps_what_is_indented_past_its_marker(self) -> None:
        """The same rule on `//`, where the one space is the one after the
        slashes rather than the one after the star.
        """
        self.assertEqual("# out = W * f(x)\n", converted("// out = W * f(x)\n"))
        self.assertEqual("#     out = W * f(x)\n", converted("//     out = W * f(x)\n"))

    def test_a_comment_with_no_space_after_its_marker_is_left_where_it_is(self) -> None:
        """`thumbnail.gmacs` opens with a block whose stars carry no space, so
        taking one off unconditionally would eat the first letter.
        """
        self.assertEqual("# Kernels: thumb_clear\n", converted("/*\n*Kernels: thumb_clear\n*/\n"))


class ControlFlow(unittest.TestCase):
    def test_else_if_becomes_elif(self) -> None:
        source = "void f() {\n    if (a) {\n        x();\n    } else if (b) {\n        y();\n    } else {\n        z();\n    }\n}\n"
        expected = "def f():\n    if a:\n        x()\n    elif b:\n        y()\n    else:\n        z()\n"
        self.assertEqual(expected, converted(source))

    def test_a_counting_loop_becomes_range(self) -> None:
        source = "void f() {\n    for ( int i = 0; i < n; ++i ) {\n        g(i);\n    }\n}\n"
        self.assertEqual("def f():\n    for i in range(0, n):\n        g(i)\n", converted(source))

    def test_a_loop_with_a_step_carries_it(self) -> None:
        source = "void f() {\n    for ( int i = 0; i < n; i += 2 ) {\n        g(i);\n    }\n}\n"
        self.assertIn("    for i in range(0, n, 2):\n", converted(source))

    def test_a_loop_that_counts_down_takes_the_inclusive_range(self) -> None:
        source = "void f() {\n    for ( int x = w - 1; x >= 0; x-- ) {\n        g(x);\n    }\n}\n"
        self.assertEqual("def f():\n    for x in range_inclusive(w - 1, 0, -1):\n        g(x)\n", converted(source))
        self.assertEqual([], notes(source))

    def test_a_loop_that_stops_on_or_equal_takes_it_too(self) -> None:
        source = "void f() {\n    for ( int d = -r; d <= r; d++ ) {\n        g(d);\n    }\n}\n"
        self.assertIn("    for d in range_inclusive(-r, r):\n", converted(source))

    def test_a_counter_that_is_not_an_int_names_its_type(self) -> None:
        source = "void f() {\n    for ( uint i = 0u; i < N; ++i ) {\n        g(i);\n    }\n}\n"
        self.assertIn("    for uint i in range(0u, N):\n", converted(source))

    def test_a_loop_the_dialect_cannot_write_is_still_marked(self) -> None:
        source = "void f() {\n    for ( int x = n; x > 0; x-- ) {\n        g(x);\n    }\n}\n"
        result = converted(source)
        self.assertIn(convert.MARK, result)
        self.assertIn("for (int x = n; x > 0; x--) {", result)
        self.assertEqual(1, len(notes(source)))

    def test_switch_becomes_match_and_the_break_goes(self) -> None:
        source = (
            "void f() {\n"
            "    switch (mode) {\n"
            "        case 1:\n"
            "            a();\n"
            "            break;\n"
            "        default:\n"
            "            b();\n"
            "            break;\n"
            "    }\n"
            "}\n"
        )
        expected = "def f():\n    match mode:\n        case 1:\n            a()\n        case _:\n            b()\n"
        self.assertEqual(expected, converted(source))

    def test_a_struct_keeps_its_fields(self) -> None:
        source = "struct Sample\n{\n    vec4 color;\n    float weight;\n};\n"
        self.assertEqual("struct Sample:\n    vec4 color\n    float weight\n", converted(source))

    def test_a_helper_takes_a_return_arrow(self) -> None:
        source = "float luminance( vec3 c )\n{\n    return dot( c, vec3( 0.2126 ) );\n}\n"
        self.assertEqual("def luminance(vec3 c) -> float:\n    return dot(c, vec3(0.2126))\n", converted(source))


class Operators(unittest.TestCase):
    def test_the_word_operators(self) -> None:
        source = "void f() {\n    if (a && b || !c) {\n        g();\n    }\n}\n"
        self.assertIn("    if a and b or not c:\n", converted(source))

    def test_not_equal_is_not_touched(self) -> None:
        source = "void f() {\n    if (a != b) {\n        g();\n    }\n}\n"
        self.assertIn("    if a != b:\n", converted(source))

    def test_the_ternary_stays_glsl(self) -> None:
        source = "void f() {\n    float x = a > 0.0 ? b : c;\n}\n"
        self.assertIn("    float x = a > 0.0 ? b : c\n", converted(source))


class TheNames(unittest.TestCase):
    def test_the_table_is_the_one_the_transpiler_reads(self) -> None:
        names = convert.load_names()
        self.assertEqual("image_load", names["imageLoad"])
        self.assertEqual("global_id", names["gl_GlobalInvocationID"])

    def test_a_camel_case_built_in_comes_out_snake(self) -> None:
        source = "void f() {\n    vec4 c = imageLoad(src, at);\n    imageStore(dst, at, c);\n}\n"
        self.assertIn("    vec4 c = image_load(src, at)\n", converted(source))
        self.assertIn("    image_store(dst, at, c)\n", converted(source))

    def test_a_built_in_variable_gets_its_short_name(self) -> None:
        source = "void f() {\n    ivec2 at = ivec2(gl_GlobalInvocationID.xy) + ivec2(gl_WorkGroupID.xy);\n}\n"
        self.assertIn("ivec2(global_id.xy) + ivec2(group_id.xy)", converted(source))

    def test_the_pixel_line_goes_because_the_transpiler_writes_it(self) -> None:
        source = "#kernel f\n[numthreads( 8, 8, 1 )] void f() {\n    ivec2 pixel = ivec2( gl_GlobalInvocationID.xy );\n    g(pixel);\n}\n"
        self.assertEqual("kernel f\ndef f():\n    g(pixel)\n", converted(source))

    def test_a_local_by_another_name_is_left_alone(self) -> None:
        source = "void f() {\n    ivec2 pixel_coords = ivec2( gl_GlobalInvocationID.xy );\n}\n"
        self.assertIn("    ivec2 pixel_coords = ivec2(global_id.xy)\n", converted(source))


class AlreadyTheDialect(unittest.TestCase):
    def test_a_glsl_kernel_is_not(self) -> None:
        self.assertFalse(convert.is_dialect(BLUR_X_GLSL))

    def test_its_own_output_is(self) -> None:
        self.assertTrue(convert.is_dialect(BLUR_X_DIALECT))

    def test_a_file_of_comments_alone_is_read_as_glsl(self) -> None:
        self.assertFalse(convert.is_dialect("// nothing here\n"))

    def test_a_row_of_imports_or_of_kernels_is(self) -> None:
        """A row naming several things is the dialect's."""
        self.assertTrue(convert.is_dialect("import transfer_curve, positive_channels\n"))
        self.assertTrue(convert.is_dialect("kernel first, second\n"))

    def test_a_docstring_under_a_def_is(self) -> None:
        self.assertTrue(convert.is_dialect('def f():\n    """Nothing."""\n    return\n'))

    def test_a_library_of_constants_alone_is(self) -> None:
        """No `def` and no declaration, so the missing semicolon is the only tell."""
        self.assertTrue(convert.is_dialect("# the limits\nconst float LIMIT = 0.5  # half\n"))
        self.assertFalse(convert.is_dialect("const float LIMIT = 0.5;\n"))
        self.assertFalse(convert.is_dialect("const vec3 K = vec3(\n    1.0, 2.0, 3.0);\n"))

    def test_a_converted_library_of_constants_is_not_converted_twice(self) -> None:
        """It used to read as GLSL once converted, so a second run would take it apart."""
        once = converted("// the limits\nconst float LIMIT = 0.5;\nconst int STEPS = 3;\n")
        self.assertEqual("# the limits\nconst float LIMIT = 0.5\nconst int STEPS = 3\n", once)
        self.assertTrue(convert.is_dialect(once))


class TheTree(unittest.TestCase):
    """The converter runs over every kernel in the tree without throwing.

    Not a proof that the output is right, which each conversion's own review
    covers. What it says is that no file in the tree makes the script
    raise, so a run gets a file and a list rather than a stack.
    """

    def test_every_kernel_converts_or_says_what_it_could_not(self) -> None:
        root = SCRIPTS.parent / "shaders" / "compute"
        files = sorted(root.glob("*.gmacs")) + sorted((root / "libs").glob("*.gmacs"))
        self.assertGreater(len(files), 20)
        names = convert.load_names()
        for path in files:
            with self.subTest(kernel=path.name):
                text, _found = convert.convert(path.read_text(encoding="utf-8"), names)
                self.assertTrue(text.endswith("\n"))
                for line in text.split("\n"):
                    self.assertEqual(line.rstrip(), line, "trailing space in %s" % path.name)


if __name__ == "__main__":
    unittest.main()
