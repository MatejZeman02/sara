"""What `gmacs_format.py` does to a dialect file, and what it refuses to touch.

    cd sara-godot && PYTHONPATH=scripts python3 -m unittest scripts.test_gmacs_format

Named on the gate's Python line beside the two suites that already guard a
committed file against the code, and for the same reason: this one guards
`core/custom-shader/gmacs_names.json` and every `.gmacs` in the tree against a
formatter that would rewrite them. It needs no Godot, no GPU and no weston, so it
runs in the docs workflow where the rest of the gate cannot.

The case that matters most is the one that asserts nothing about formatting.
Twenty-six kernels in the tree are GLSL until the sweep is through, and a
detector that called one of them the dialect would reindent a file nobody
touched. That is the same guard `test_dialect.gd` keeps on the GDScript side, and
the two detectors are ports of each other, so it is worth keeping on both.
"""

from __future__ import annotations

import io
import re
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path

import gmacs_format as fmt

REPO = Path(__file__).resolve().parents[2]

# The spec's own example, in the shape the kernel language section prints it.
BLUR_X = """kernel blur_x
import gaussian

image src: readonly
image dst

params:
    float sigma
    int radius


def blur_x():
    vec4 sum = vec4(0.0)
    for i in range(-radius, radius + 1):
        sum += image_load(src, pixel + ivec2(i, 0))
    image_store(dst, pixel, sum)


def luminance(vec3 c) -> float:
    return dot(c, vec3(0.2126, 0.7152, 0.0722))
"""

# A kernel in GLSL, which is what every `.gmacs` in the tree was before the
# S sweep and what a module or a student may still write.
TODAYS_GLSL = """#kernel paint

layout( SA_STORAGE_FORMAT, set = 0, binding = 0 ) uniform image2D canvas;

[numthreads( 8, 8, 1 )] void paint() {
\timageStore(canvas, ivec2(gl_GlobalInvocationID.xy), vec4(1.0));
}
"""


class WhatItRefusesToTouch(unittest.TestCase):
    def setUp(self) -> None:
        self.table = fmt.names()

    def test_every_kernel_in_the_tree_is_read_as_what_it_is_written_in(self) -> None:
        """The one case that would break a kernel nobody touched.

        The tree was all GLSL until files were converted one by one, so the assertion is not that
        nothing in it is the dialect. It is that a file the detector calls GLSL writes no dialect
        line anywhere in it, which is the misread stated the other way round
        and holds for a library that carries no marker either way, and that a
        file it calls the dialect is already formatted, which is what the conversion
        leaves behind.
        """
        files = sorted((fmt.GODOT / "shaders").rglob("*.gmacs")) + sorted((fmt.GODOT / "modules").rglob("*.gmacs"))
        self.assertGreaterEqual(len(files), 20, "the tree has twenty-five kernels and seven libraries")
        for path in files:
            text = path.read_text(encoding="utf-8")
            if not fmt.is_dialect(text):
                marker = r"(?m)^\s*(?:kernel\s+\w|import\s+\w|def\s+\w+\s*\(|@workgroup_size|params\s*:)"
                self.assertNotRegex(text, marker, "%s is GLSL and writes no dialect line" % path.name)
                continue
            self.assertEqual(text, fmt.format_text(text, self.table), "%s is the dialect and is formatted" % path.name)

    def test_a_glsl_file_is_left_alone_and_said_so(self) -> None:
        """On a fixture rather than on the tree, which has no GLSL left in it.

        The tree has no GLSL kernel left, so it cannot answer this. The
        behaviour still matters: a module or a student may keep a GLSL `.gmacs`
        and the formatter has no business rewriting one.
        """
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            (root / "old.gmacs").write_text(TODAYS_GLSL, encoding="utf-8")
            (root / "new.gmacs").write_text(fmt.format_text(BLUR_X, self.table), encoding="utf-8")

            out = io.StringIO()
            with redirect_stdout(out):
                code = fmt.main(["--check", str(root)])

        self.assertEqual(code, 0, "a GLSL file beside a formatted one is not a failure")
        self.assertIn("left alone, written in GLSL", out.getvalue())
        self.assertRegex(out.getvalue(), r"\d+ dialect file\(s\) read")

    def test_the_tree_itself_is_all_dialect_now(self) -> None:
        """What the case above used to assert about `shaders/`, stated forwards.

        The sweep is through, so every `.gmacs` Sara ships is the dialect and
        `--check` over the whole tree passes. A file added in GLSL would show up
        here as a file the formatter left alone.
        """
        out = io.StringIO()
        with redirect_stdout(out):
            code = fmt.main(["--check"])

        self.assertEqual(code, 0, "every kernel in the tree is formatted")
        self.assertNotIn("left alone, written in GLSL", out.getvalue())

    def test_a_marker_decides_and_a_file_without_one_is_glsl(self) -> None:
        self.assertTrue(fmt.is_dialect("kernel paint\n"))
        self.assertTrue(fmt.is_dialect("def paint():\n    a = 1\n"))
        self.assertFalse(fmt.is_dialect(TODAYS_GLSL))
        self.assertFalse(fmt.is_dialect("float gaussian(float x) { return x; }\n"))

    def test_the_shapes_k1_added_are_the_dialect(self) -> None:
        """A row of names, a docstring, a library of constants."""
        self.assertTrue(fmt.is_dialect("import transfer_curve, positive_channels\n"))
        self.assertTrue(fmt.is_dialect("kernel first, second\n"))
        self.assertTrue(fmt.is_dialect("# the limits\nconst float LIMIT = 0.5\n"))
        self.assertFalse(fmt.is_dialect("const float LIMIT = 0.5;\n"))
        self.assertFalse(fmt.is_dialect("const vec3 K = vec3(\n    1.0, 2.0, 3.0);\n"))


class WhatItWrites(unittest.TestCase):
    def setUp(self) -> None:
        self.table = fmt.names()

    def format(self, text: str) -> str:
        return fmt.format_text(text, self.table)

    def test_the_specs_example_changes_only_by_its_range_closed(self) -> None:
        """The page and the formatter agree but for the open range the page still writes."""
        closed = BLUR_X.replace("range(-radius, radius + 1)", "range_inclusive(-radius, radius)")
        self.assertNotEqual(closed, BLUR_X, "the example writes the range open")
        self.assertEqual(self.format(BLUR_X), closed)

    def test_formatting_twice_is_formatting_once(self) -> None:
        once = self.format("kernel k\ndef k():\n\tif a:\n\t\tb = 1\n")
        self.assertEqual(self.format(once), once)

    def test_a_tab_and_a_two_space_level_both_come_out_at_four(self) -> None:
        tabbed = self.format("def k():\n\tif a:\n\t\tb = 1\n")
        narrow = self.format("def k():\n  if a:\n    b = 1\n")

        self.assertEqual(tabbed, "def k():\n    if a:\n        b = 1\n")
        self.assertEqual(narrow, tabbed, "the nesting is read from the file, the width is the formatter's")

    def test_trailing_space_goes_and_the_file_ends_with_one_newline(self) -> None:
        written = self.format("kernel k   \n\nimage src  \n\n\n")

        self.assertEqual(written, "kernel k\n\nimage src\n")

    def test_a_run_of_blank_lines_collapses_to_one(self) -> None:
        """Collapsed rather than inserted: `image src` and `image dst` are a
        group a painter wrote together and the formatter does not split it."""
        written = self.format("kernel k\n\n\n\nimage src\nimage dst\n")

        self.assertEqual(written, "kernel k\n\nimage src\nimage dst\n")

    def test_a_top_level_def_takes_two_blank_lines_and_its_decorator_none(self) -> None:
        written = self.format("image dst\n@workgroup_size(64)\n\ndef k():\n    a = 1\n")

        self.assertEqual(written, "image dst\n\n\n@workgroup_size(64)\ndef k():\n    a = 1\n")

    def test_the_default_decorator_goes_and_any_other_stays(self) -> None:
        for spelling in ["@workgroup_size(8, 8)", "@workgroup_size(8,8,1)", "@numthreads(8, 8, 1)"]:
            written = self.format("image dst\n\n\n%s\ndef k():\n    a = 1\n" % spelling)
            self.assertEqual(written, "image dst\n\n\ndef k():\n    a = 1\n", spelling)
        written = self.format("image dst\n\n\n@workgroup_size(8, 8)  # a note\ndef k():\n    a = 1\n")
        self.assertIn("@workgroup_size(8, 8)  # a note\n", written)
        written = self.format("image dst\n\n\n@workgroup_size(16, 8)\ndef k():\n    a = 1\n")
        self.assertIn("@workgroup_size(16, 8)\n", written)

    def test_a_line_continued_in_a_bracket_is_left_where_it_was_written(self) -> None:
        """A continuation ends in a comma rather than a colon, so reading
        nesting off it opened nothing and pulled the rows of every matrix in
        the tree back to the block's own indent. The dialect continues a line
        Python's way, "so a long call is broken wherever it reads best", and
        where it reads best is a painter's to say.
        """
        text = "def f() -> mat3:\n    return mat3(\n        a, b, c,\n        d, e, g\n    )\n"

        self.assertEqual(fmt.format_text(text, self.table), text, "the rows stay where they were put")

    def test_a_continuation_indented_less_than_its_block_closes_nothing(self) -> None:
        """The same cause the other way round, which no file in the tree has yet.

        A continuation read as a line of its own is also read as a *dedent*, so
        one written left of its block popped the stack and every line after it
        came out at the wrong level. Nothing is popped by a line that is still
        inside a bracket.
        """
        text = "def f() -> float:\n    float v = g(\n  a, b\n    )\n    return v\n"

        out = fmt.format_text(text, self.table)

        self.assertEqual(out, text, "neither the continuation nor the line under it moves")

    def test_a_case_written_level_with_its_match_is_pushed_in(self) -> None:
        """The one place the formatter has an opinion rather than a
        normalization, because C writes a `case` level with its `switch`."""
        written = self.format("def k():\n    match a:\n    case 1:\n        b = 1\n    case 2:\n        b = 2\n")

        self.assertEqual(
            written,
            "def k():\n    match a:\n        case 1:\n            b = 1\n        case 2:\n            b = 2\n",
        )


class TheNames(unittest.TestCase):
    def setUp(self) -> None:
        self.table = fmt.names()

    def test_every_glsl_name_in_the_table_comes_out_snake(self) -> None:
        """Driven by the file the transpiler reads in the other direction, so
        the two cannot drift, and covering every name rather than the ten the
        tree happens to call."""
        self.assertEqual(len(self.table), 88, "six built-in variables and eighty-two camelCase functions")
        for glsl_name, snake in self.table.items():
            line = "    a = %s(x)\n" % glsl_name
            self.assertEqual(fmt.snake_names(line, self.table), "    a = %s(x)\n" % snake)

    def test_image_load_is_the_named_case(self) -> None:
        written = fmt.format_text("def k():\n    a = imageLoad(src, at)\n", self.table)

        self.assertEqual(written, "def k():\n    a = image_load(src, at)\n")

    def test_a_name_in_a_string_or_a_comment_is_not_an_identifier(self) -> None:
        quoted = fmt.snake_names('    a = "imageLoad"\n', self.table)
        commented = fmt.snake_names("    a = 1  # imageLoad is the GLSL spelling\n", self.table)

        self.assertIn('"imageLoad"', quoted)
        self.assertIn("# imageLoad is the GLSL spelling", commented)

    def test_a_docstring_is_prose_and_keeps_its_shape(self) -> None:
        """No name inside one is rewritten, and a colon ending one of its lines
        opens nothing, so the body after it stays where it was."""
        source = 'def k():\n  """Reads imageLoad.\n\n    Returns:\n  """\n  a = imageLoad(src, at)\n'
        written = fmt.format_text(source, self.table)

        self.assertEqual(
            written, 'def k():\n    """Reads imageLoad.\n\n      Returns:\n    """\n    a = image_load(src, at)\n'
        )
        self.assertEqual(fmt.format_text(written, self.table), written, "formatting twice is formatting once")

    def test_a_row_of_names_is_left_as_written(self) -> None:
        source = "kernel first, second\nimport transfer_curve, positive_channels\n"
        self.assertEqual(fmt.format_text(source, self.table), source)

    def test_a_word_the_table_does_not_have_is_left_alone(self) -> None:
        self.assertEqual(fmt.snake_names("    float myImageLoader = 1.0\n", self.table), "    float myImageLoader = 1.0\n")


# A kernel with every place a cast can stand, each name declared the way the
# tree declares it: a param, a constant, a local, a loop counter.
CASTS = """kernel k

params:
    int radius
    uint cells

const uint BINS = 64u


def k():
    vec4 sum = vec4(0.0)
    float side = 4.0
    int n = 2 * radius + 1
    for x in range(0, 4):
        sum += vec4(%s)
"""


class ACastThatDoesNothingGoes(unittest.TestCase):
    """`float()` round an int goes where GLSL converts it on its own, and only there."""

    def setUp(self) -> None:
        self.table = fmt.names()

    def line(self, statement: str) -> str:
        """*statement* as the last line of the kernel above, after the formatter."""
        text = CASTS.replace("        sum += vec4(%s)\n", "    %s\n" % statement)
        return fmt.format_text(text, self.table).rstrip("\n").split("\n")[-1].strip()

    def test_beside_a_float_the_cast_goes_and_a_sum_keeps_its_brackets(self) -> None:
        self.assertEqual(self.line("sum = sum / float(n * n)"), "sum = sum / (n * n)")
        self.assertEqual(self.line("float t = side - float(radius)"), "float t = side - radius")
        self.assertEqual(self.line("float t = 0.5 * float(BINS - 1u)"), "float t = 0.5 * (BINS - 1u)")

    def test_in_an_ordering_beside_a_float_it_goes(self) -> None:
        self.assertEqual(self.line("if float(n) >= side:"), "if n >= side:")

    def test_inside_a_float_constructor_it_goes(self) -> None:
        self.assertEqual(self.line("vec2 p = vec2(float(radius), float(n))"), "vec2 p = vec2(radius, n)")

    def test_as_the_whole_value_given_to_a_float_it_goes(self) -> None:
        self.assertEqual(self.line("float count = float(n * n)"), "float count = n * n")
        self.assertEqual(self.line("side = float(cells)"), "side = cells")

    def test_two_ints_cast_side_by_side_are_both_kept(self) -> None:
        self.assertEqual(self.line("float t = float(n) / float(radius)"), "float t = float(n) / float(radius)")

    def test_beside_an_int_it_is_kept_so_the_division_stays_a_float_one(self) -> None:
        self.assertEqual(self.line("float t = radius / float(n)"), "float t = radius / float(n)")

    def test_round_a_vector_or_a_name_nobody_declared_it_is_kept(self) -> None:
        # `float(v)` of a vector is its first component, so it does something.
        self.assertEqual(self.line("float t = 0.5 * float(sum)"), "float t = 0.5 * float(sum)")
        self.assertEqual(self.line("float t = 0.5 * float(elsewhere)"), "float t = 0.5 * float(elsewhere)")

    def test_handed_to_a_function_or_under_a_minus_it_is_kept(self) -> None:
        self.assertEqual(self.line("float t = exp(float(n))"), "float t = exp(float(n))")
        self.assertEqual(self.line("float t = -float(n) / side"), "float t = -float(n) / side")

    def test_in_a_comment_or_a_continued_line_it_is_kept(self) -> None:
        self.assertEqual(self.line("float t = side  # side / float(n)"), "float t = side  # side / float(n)")
        text = CASTS.replace("        sum += vec4(%s)\n", "    float t = max(side,\n        side / float(n))\n")
        self.assertIn("side / float(n))", fmt.format_text(text, self.table))

    def test_a_constant_an_import_declares_gives_its_type(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            library = Path(folder) / "steps.gmacs"
            library.write_text("const int STEPS = 8\n", encoding="utf-8")
            lines = ["import steps", "def k() -> float:", "    return 0.5 * float(STEPS)"]
            written = fmt.CastsAndRanges(lines, set(), {"steps": library}).rewrite()
            alone = fmt.CastsAndRanges(lines, set(), {}).rewrite()
        self.assertEqual(written[-1], "    return 0.5 * STEPS")
        self.assertEqual(alone[-1], "    return 0.5 * float(STEPS)", "and without the import it is kept")

    def test_every_kept_cast_is_counted_with_its_reason(self) -> None:
        kept: list[tuple[int, str]] = []
        fmt.format_text(CASTS.replace("        sum += vec4(%s)\n", "    float t = exp(float(n))\n"), self.table, kept)
        self.assertEqual([reason for _, reason in kept], ["an argument of a function"])


class ARangeWrittenOpenIsClosed(unittest.TestCase):
    """`range(a, b + 1)` comes out as `range_inclusive(a, b)`, and nothing else does."""

    def setUp(self) -> None:
        self.table = fmt.names()

    def header(self, written: str) -> str:
        text = "kernel k\n\n\ndef k():\n    %s\n        pass\n" % written
        return fmt.format_text(text, self.table).split("\n")[4].strip()

    def test_a_bound_plus_one_is_closed(self) -> None:
        self.assertEqual(self.header("for dy in range(-reach, reach + 1):"), "for dy in range_inclusive(-reach, reach):")
        self.assertEqual(self.header("for b in range(lo, min(hi, n - 1) + 1):"), "for b in range_inclusive(lo, min(hi, n - 1)):")
        self.assertEqual(self.header("for i in range(n + 1):"), "for i in range_inclusive(n):")
        self.assertEqual(self.header("for uint i in range(0u, n + 1u):"), "for uint i in range_inclusive(0u, n):")

    def test_a_bound_that_does_not_end_in_plus_one_is_left(self) -> None:
        for written in (
            "for i in range(0, n + 2):",
            "for i in range(0, (n + 1)):",
            "for i in range(0, n * (k + 1)):",
            "for i in range(0, n + 1, 2):",
            "for i in range_inclusive(0, n + 1):",
        ):
            self.assertEqual(self.header(written), written)


class TheCheckMode(unittest.TestCase):
    def setUp(self) -> None:
        self.table = fmt.names()

    def test_check_names_the_line_and_exits_non_zero(self) -> None:
        bad = REPO / "sara-godot" / "scratch" / "gmacs-format-case.gmacs"
        bad.parent.mkdir(parents=True, exist_ok=True)
        bad.write_text("kernel k\ndef k():\n  a = 1\n", encoding="utf-8")
        try:
            problems = fmt.check(bad, self.table)
            out = io.StringIO()
            with redirect_stdout(out):
                code = fmt.main(["--check", str(bad)])
        finally:
            bad.unlink()

        self.assertEqual(code, 1, "a file that would change is a failure under --check")
        self.assertTrue(problems, "and it says what would change")
        self.assertTrue(
            any(re.search(r":\d+:$", line) for line in problems),
            "every hunk names the line it starts on, got %r" % problems,
        )
        self.assertIn("  a = 1", "\n".join(problems), "and shows the line as it stands")


class TheGateNamesIt(unittest.TestCase):
    """The five lists that have to run this suite, asserted rather than trusted.

    A gate line is a committed file the code cannot check, which is why
    the two suites beside this one exist. A sixth list appearing
    is a case failing here rather than a suite nobody runs.
    """

    LISTS = [
        "AGENTS.md",
        "docs/guides/TESTING.md",
        "docs/agents/BRIEF.md",
        "docs/agents/UNATTENDED.md",
        ".github/workflows/docs.yml",
    ]

    def test_every_gate_list_runs_this_suite(self) -> None:
        # assertTrue rather than assertIn, because a failing assertIn prints the
        # whole of the guide as the haystack and the message is then unreadable.
        if not (REPO / "docs").is_dir():
            self.skipTest("a public copy has no docs folder, and its AGENTS.md is not the gate page")
        if not any((REPO / name).exists() for name in self.LISTS):
            self.skipTest("a copy of the source carries none of the pages that quote the gate")
        for name in self.LISTS:
            if not (REPO / name).exists():
                continue  # a copy of the source carries none of these pages
            text = (REPO / name).read_text(encoding="utf-8")
            self.assertTrue("scripts.test_scenario_dockers" in text, "%s carries the Python line" % name)
            self.assertTrue("scripts.test_gmacs_format" in text, "%s does not run the formatter's suite" % name)


if __name__ == "__main__":
    unittest.main()
