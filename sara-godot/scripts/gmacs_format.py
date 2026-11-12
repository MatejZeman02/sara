#!/usr/bin/env python3
"""The formatter for the Python-shaped `.gmacs` dialect.

    python3 sara-godot/scripts/gmacs_format.py --check
    python3 sara-godot/scripts/gmacs_format.py path/to/kernel.gmacs

The spec asks for one, and says what it is for: "A formatter is ours and comes
with the transpiler, its rules being indentation, blank lines and trailing space
rather than braces and parentheses, and the `.clang-format` in the tree retires
with the last brace." So this is not clang-format with different settings. There
are no braces to place and no parentheses to align, and what is left is the small
set of things a dialect written by indentation can get wrong.

Python rather than GDScript, so that it runs in CI without Godot and the sweep
can be checked on a machine with no engine on it. It is named on the gate's
Python line beside the two suites that already guard a committed file against
the code.

## The rules

- **Four spaces a level, and no tab.** The nesting is read from the file's own
  relative indentation the way `sa_dialect.gd` reads it, so a file indented with
  two spaces or with tabs comes out at four and means the same thing.
- **A `case` sits inside its `match`.** The one place the formatter has an
  opinion rather than a normalization: a `case` written level with its `match`,
  which is how C writes it, is pushed in one level.
- **No trailing space, and a blank line is empty.**
- **One newline at the end**, and none at the start.
- **One blank line between declarations**, which is a run of blanks collapsed to
  one rather than a blank inserted: `image src` and `image dst` are a group the
  writer put together and the formatter has no business separating them.
- **Two above a top-level `def` or `struct`**, GDScript's own spacing and the
  spacing every example on the spec page uses, counted above the decorator when
  there is one, because the decorator belongs to the `def` under it.
- **None between a decorator and its `def`.**
- **Every name in `gmacs_names.json` written snake**, outside strings and
  comments. A dialect with two cases is two dialects, and this is the rule that
  makes the tree one, the only one that changes what a line says rather than
  where it sits. The transpiler
  reads the same file in the other direction, so the two cannot drift.
- **A `float()` that does nothing goes.** A cast whose inside
  is an int or a uint and which stands where GLSL 4.5 converts an int on its
  own, beside a float in `+ - * /` or an ordering, as an argument of `float`
  or a `vec`, or as the whole value given to a float, is written without it,
  `sum / float(n * n)` as `sum / (n * n)`. The SPIR-V is the same, because the
  conversion glslang writes for the cast is the one it writes on its own. The
  types are read from what the file and its imports declare, in
  `gmacs_types.py`, and a cast whose inside or neighbour that table cannot
  place is kept, as are two ints cast side by side, `float(a) / float(b)`, and
  a cast handed to a function. `--casts` counts the kept ones by reason.
- **A range written open is closed.** `range(a, b + 1)` is written
  `range_inclusive(a, b)`, which counts the same values with one instruction
  fewer on every test, as `GMACS.md` asks.

## What it will not touch

A GLSL `.gmacs`, which is every kernel in the tree until the sweep is through.
The detector is `sa_dialect.gd`'s, ported: the first marker line in the file
decides, and a file with no marker at all is GLSL. A GLSL file named on the
command line is reported as left alone rather than passed over in silence,
because a formatter that quietly does nothing is a formatter you stop trusting.
"""

from __future__ import annotations

import argparse
import difflib
import functools
import json
import re
import sys
from pathlib import Path

from gmacs_types import (
    ARITHMETIC,
    DECLARATION,
    DEF_LINE,
    FLOAT_VECTORS,
    FOR_LINE,
    ORDERING,
    SCALAR_INTS,
    TYPE_NAMES,
    Expression,
    KernelTypes,
    Node,
    parses,
    split_args,
)

GODOT = Path(__file__).resolve().parents[1]
NAMES_FILE = GODOT / "core" / "custom-shader" / "gmacs_names.json"

INDENT = "    "
TAB_WIDTH = 4

# A decorator that names the default, 8 by 8, which a missing line already
# means. The line is optional so that most kernels write nothing, and a
# converter that writes it above every one of them undoes that, so it is
# dropped here. Either spelling, the third number allowed as 1, no comment on
# the line, because a comment is its writer's and stays with whatever it was
# written against.
DEFAULT_DECORATOR = re.compile(r"^@(?:workgroup_size|numthreads)\s*\(\s*8\s*,\s*8\s*(?:,\s*1\s*)?\)$")

# The same two patterns `SaDialect.is_dialect` carries, in Python's spelling. A
# marker is a line whose opening can only belong to one of the two forms.
DIALECT_MARKER = re.compile(
    r"^(?:kernel\s+\w+|import\s+[\w/]+|def\s+\w+\s*\("
    r"|@(?:workgroup_size|numthreads)\s*\(|(?:image|sampler|buffer)\s+\w+\s*:"
    r"|params(?:\s+\w+)?\s*:)"
)
GLSL_MARKER = re.compile(
    r'^#(?:kernel\s+\w|include\s*["<]|version\s+\d|define\s+\w'
    r"|pragma\b|extension\b|ifdef\b|ifndef\b|endif\b|else\b|elif\b|if\b|undef\b|line\b|error\b)"
)
GLSL_SHAPE = re.compile(r"\blayout\s*\(|\[\s*numthreads\s*\(")
BARE_DECLARATION = re.compile(r"^(?:image|sampler|buffer)\s+\w+$")
# A constant with no semicolon, which is how a library of constants alone says
# it is the dialect. Its brackets must close on the line, because GLSL writes a
# long initialiser over several and its first line has no semicolon either.
DIALECT_CONSTANT = re.compile(r"^const\s+\w+\s+\w+\s*(?:\[[^\]]*\]\s*)?=[^;]+$")

DECORATOR = re.compile(r"^@\w+\s*\(")
TOP_LEVEL_BLOCK = re.compile(r"^(?:def|struct)\b")
DEF_HEADER = re.compile(r"^\s*def\s+\w+\s*\(")
DOCSTRING_FENCES = ('"""', "'''")
CASE = re.compile(r"^case\b")
MATCH = re.compile(r"^match\b")


def names() -> dict[str, str]:
    """GLSL spelling to snake spelling, both tables in one dictionary.

    The file is written in this direction for this reader and for the
    converter. `sa_dialect.gd` is the one that inverts it.
    """
    table = json.loads(NAMES_FILE.read_text(encoding="utf-8"))
    out: dict[str, str] = {}
    for half in ("variables", "functions"):
        out.update(table.get(half, {}))
    return out


def code_spans(code: str) -> list[tuple[str, bool]]:
    """*code* as `(text, is_string_literal)` spans, so a rewrite skips literals."""
    spans: list[tuple[str, bool]] = []
    quote = ""
    start = 0
    i = 0
    while i < len(code):
        c = code[i]
        if not quote:
            if c in ('"', "'"):
                spans.append((code[start:i], False))
                start = i
                quote = c
        elif c == "\\":
            i += 1
        elif c == quote:
            spans.append((code[start : i + 1], True))
            start = i + 1
            quote = ""
        i += 1
    if start < len(code):
        spans.append((code[start:], bool(quote)))
    return spans


def bracket_delta(code: str) -> int:
    """Round and square brackets opened minus closed in *code*, outside strings.

    Braces are not counted. The dialect writes none, and a `{` inside a comment
    or a string is not structure either, which is why this reads spans rather
    than characters.
    """
    depth = 0
    for text, is_string in code_spans(code):
        if is_string:
            continue
        for c in text:
            if c in "([":
                depth += 1
            elif c in ")]":
                depth -= 1
    return depth


def split_comment(line: str) -> tuple[str, str]:
    """One physical line as its code and its `#` comment, the hash kept.

    A hash inside a string literal is not a comment, which is the whole reason
    this is a scan rather than a `find`.
    """
    quote = ""
    i = 0
    while i < len(line):
        c = line[i]
        if quote:
            if c == "\\":
                i += 2
                continue
            if c == quote:
                quote = ""
        elif c in ('"', "'"):
            quote = c
        elif c == "#":
            return line[:i], line[i:]
        i += 1
    return line, ""


def is_dialect(text: str) -> bool:
    """True when *text* is written in the dialect rather than in GLSL.

    `SaDialect.is_dialect`'s rule, and the same reasoning: the first marker line
    decides, because counting them would let one stray line change a file's
    dialect and reading the last one would let an appended line do it.
    """
    for line in text.split("\n"):
        body = line.strip()
        if not body:
            continue
        if DIALECT_MARKER.search(body) or BARE_DECLARATION.search(body) or is_dialect_constant(body):
            return True
        if GLSL_MARKER.search(body) or GLSL_SHAPE.search(body):
            return False
    return False


def is_dialect_constant(body: str) -> bool:
    """`const float LIMIT = 0.5` with no semicolon and its brackets closed."""
    code = split_comment(body)[0].strip()
    return DIALECT_CONSTANT.search(code) is not None and bracket_delta(code) == 0


def docstring_lines(lines: list[str]) -> set[int]:
    """The index of every line of every function's docstring.

    `SaDialect._docstrings`, ported: the string a `def` opens its body with,
    three quotes over as many lines as it likes or one quote closed on its own
    line. A docstring that never closes is not one, so the rest of a file is
    never read as prose.
    """
    found: set[int] = set()
    i = 0
    while i < len(lines):
        code = split_comment(lines[i])[0]
        if not DEF_HEADER.search(code):
            i += 1
            continue
        depth = bracket_delta(code)
        while depth > 0 and i + 1 < len(lines):
            i += 1
            code = split_comment(lines[i])[0]
            depth += bracket_delta(code)
        i += 1
        if not code.strip().endswith(":"):
            continue
        while i < len(lines) and not lines[i].strip():
            i += 1
        i = _docstring_from(lines, i, found)
    return found


def _docstring_from(lines: list[str], at: int, found: set[int]) -> int:
    """Adds the docstring starting on line *at*, if one does, and says where to go on."""
    if at >= len(lines):
        return at
    body = lines[at].strip()
    for fence in DOCSTRING_FENCES:
        if not body.startswith(fence):
            continue
        close = body.find(fence, len(fence))
        if close >= 0:
            if body[close + len(fence) :].strip():
                return at
            found.add(at)
            return at + 1
        for end in range(at + 1, len(lines)):
            last = lines[end].strip()
            close = last.find(fence)
            if close < 0:
                continue
            if last[close + len(fence) :].strip():
                return at
            found.update(range(at, end + 1))
            return end + 1
        return at
    pieces = [span for span in code_spans(body) if span[0]]
    if len(pieces) == 1 and pieces[0][1] and len(body) >= 2 and body[-1] == body[0]:
        found.add(at)
        return at + 1
    return at


def leading_space(line: str) -> int:
    """The line's indentation in spaces, a tab counting as TAB_WIDTH."""
    width = 0
    for c in line:
        if c == " ":
            width += 1
        elif c == "\t":
            width += TAB_WIDTH
        else:
            break
    return width


def snake_names(line: str, table: dict[str, str]) -> str:
    """Every GLSL name in *line* written snake, outside strings and comments."""
    code, comment = split_comment(line)
    out = ""
    for text, is_string in code_spans(code):
        if not is_string:
            for word in set(re.findall(r"[A-Za-z_]\w*", text)):
                if word in table:
                    text = re.sub(r"\b%s\b" % re.escape(word), table[word], text)
        out += text
    return out + comment
# The constructors whose arguments GLSL converts to float one by one, so a
# cast written inside one converts twice.
FLOAT_CONSTRUCTORS = ("float",) + FLOAT_VECTORS
ASSIGNMENT = re.compile(r"^(?P<target>[A-Za-z_]\w*)\s*(?P<op>[-+*/]?=)(?!=)\s*(?P<expr>.+)$")
FLOW = re.compile(r"^(?P<word>return|if|elif|while)\b\s*(?P<expr>.*?)(?P<colon>:?)$")


class CastsAndRanges:
    """Drops a `float()` GLSL's own conversion makes, and closes `range(a, b + 1)`.

    A cast goes only where the value cannot change: its inside reads as an int
    or a uint scalar, and it stands where GLSL 4.5 converts an int to a float on
    its own, beside a float in arithmetic or an ordering, as an argument of a
    float constructor, or as the whole value given to a float. Two casts side by
    side are both kept, `float(a) / float(b)` being a ratio of ints that reads
    as one. Every cast kept is counted with its reason in `kept`.
    """

    def __init__(self, lines: list[str], prose: set[int], libraries: dict[str, Path]) -> None:
        self.lines = lines
        self.prose = prose
        self.skip = continued_lines(lines, prose)
        self.types = KernelTypes(["" if i in prose else split_comment(line)[0] for i, line in enumerate(lines)], libraries)
        self.kept: list[tuple[int, str]] = []

    def rewrite(self) -> list[str]:
        out = []
        for index, line in enumerate(self.lines):
            if index in self.prose:
                out.append(line)
                continue
            if index in self.skip:
                out.append(line)
                self._count(line, index, "a line continued in a bracket")
                continue
            code, comment = split_comment(line)
            out.append(self._statement(code, index) + comment)
        return out

    def _count(self, code: str, line: int, reason: str) -> None:
        for _ in re.finditer(r"\bfloat\s*\(", split_comment(code)[0]):
            self.kept.append((line, reason))

    def _statement(self, code: str, line: int) -> str:
        body = code.strip()
        lead = code[: len(code) - len(code.lstrip())]
        trail = code[len(code.rstrip()) :]
        if not body or any(text and is_string for text, is_string in code_spans(body)):
            self._count(body, line, "a line holding a string")
            return code
        found = FOR_LINE.match(body)
        if found:
            self._count(body, line, "a loop header")
            return lead + self._range(body, found) + trail
        context = None
        start = 0
        end = len(body)
        found = DECLARATION.match(body)
        if found and found.group("type") in TYPE_NAMES and "=" in body and not body.startswith("uniform"):
            equals = re.search(r"(?<![=!<>])=(?!=)", body)
            if equals and len(split_args(body[: equals.start()])) == 1 and "[" not in body[: equals.start()]:
                context = found.group("type")
                start = equals.end()
        elif FLOW.match(body):
            found = FLOW.match(body)
            start = found.start("expr")
            end = found.end("expr")
            if found.group("word") == "return":
                context = self.types.returned(line)
            elif not found.group("colon"):
                self._count(body, line, "a statement after a colon")
                return code
        elif DEF_LINE.match(body) or body.startswith(("def ", "match ", "case ", "else", "for ", "import ", "kernel ", "@")):
            self._count(body, line, "a header or a one-line def")
            return code
        elif ASSIGNMENT.match(body):
            found = ASSIGNMENT.match(body)
            start = found.start("expr")
            context = self.types.of(found.group("target"), line)
        else:
            target = re.match(r"^(.+?)\s*[-+*/]?=(?!=)\s*", body)
            if target and parses(target.group(1)) and not re.search(r"[<>!=]$", target.group(1)):
                start = target.end()
        try:
            tree = Expression(body[start:end]).parse()
        except ValueError:
            self._count(body, line, "an expression the formatter does not parse")
            return code
        edits: list[tuple[int, int, str]] = []
        self._walk(tree, None, context, body[start:end], line, edits)
        text = body[start:end]
        for begin, finish, replacement in sorted(edits, reverse=True):
            text = text[:begin] + replacement + text[finish:]
        return lead + body[:start] + text + body[end:] + trail

    def _range(self, body: str, found: re.Match) -> str:
        args = split_args(found.group("args"))
        if len(args) not in (1, 2):
            return body
        try:
            bound = Expression(args[-1].strip()).parse()
        except ValueError:
            return body
        last = bound.parts[1] if bound.kind == "binary" and bound.value == "+" else None
        if not last or last.kind != "number" or last.value not in ("1", "1u"):
            return body
        text = args[-1].strip()
        closed = text[: bound.parts[0].end]
        written = ", ".join([arg.strip() for arg in args[:-1]] + [closed])
        return body[: found.start("args")].replace("range", "range_inclusive", 1).rstrip("(") + "(" + written + "):"

    def _walk(self, node: Node, parent: Node | None, context: str | None, text: str, line: int, edits: list) -> None:
        if self._is_cast(node):
            reason = self._why_kept(node, parent, context, line)
            if reason:
                self.kept.append((line, reason))
            else:
                inner = node.parts[1]
                bare = parent is None or (parent.kind == "call" and node is not parent.parts[0])
                written = text[inner.start : inner.end]
                if not bare and inner.kind not in ("name", "number", "call", "member", "index", "paren"):
                    written = "(" + written + ")"
                edits.append((node.start, node.end, written))
        for part in node.parts:
            self._walk(part, node, context, text, line, edits)

    @staticmethod
    def _is_cast(node: Node) -> bool:
        return node.kind == "call" and node.value == "float" and len(node.parts) == 2

    def _why_kept(self, node: Node, parent: Node | None, context: str | None, line: int) -> str:
        if self.types.of_node(node.parts[1], line) not in SCALAR_INTS:
            return "an inside not known to be an int"
        if parent is None:
            return "" if context == "float" else "a value given to something not known to be a float"
        if parent.kind == "call":
            return "" if parent.value in FLOAT_CONSTRUCTORS else "an argument of a function"
        if parent.kind != "binary" or parent.value not in ARITHMETIC + ORDERING:
            return "under a unary %s" % parent.value if parent.kind == "unary" else "a place GLSL does not convert"
        other = parent.parts[1] if parent.parts[0] is node else parent.parts[0]
        if self._is_cast(other) and self.types.of_node(other.parts[1], line) in SCALAR_INTS:
            return "two ints cast side by side"
        kind = self.types.of_node(other, line)
        wanted = ("float",) if parent.value in ORDERING else ("float",) + FLOAT_VECTORS
        return "" if kind in wanted else "a neighbour not known to be a float"


def continued_lines(lines: list[str], prose: set[int]) -> set[int]:
    """Every line of a statement that opens a bracket and closes it on a later line."""
    found: set[int] = set()
    depth = 0
    for index, line in enumerate(lines):
        if index in prose:
            continue
        delta = bracket_delta(split_comment(line)[0])
        if depth > 0 or delta > 0:
            found.add(index)
        depth = max(0, depth + delta)
    return found


@functools.cache
def libraries() -> dict[str, Path]:
    """Every kernel file Sara ships, by the name an `import` gives it.

    A name two files share is left out, since the formatter cannot tell which
    one an import means, and a name it cannot read has no type.
    """
    found: dict[str, Path | None] = {}
    for path in GODOT.rglob("*.gmacs"):
        parts = path.relative_to(GODOT).parts
        if parts[0] in (".godot", "tests") or "fixtures" in parts:
            continue
        found[path.stem] = None if path.stem in found else path
    return {name: path for name, path in found.items() if path}


def format_text(text: str, table: dict[str, str], kept: list[tuple[int, str]] | None = None) -> str:
    """*text* as the formatter would write it, each cast it keeps added to *kept* with its reason."""
    lines = [line.rstrip() for line in text.split("\n") if not DEFAULT_DECORATOR.match(line.strip())]
    # A docstring is prose: its names are not rewritten, a colon at the end of
    # one of its lines opens nothing, and its lines keep their places relative
    # to its first, which is indented as the body it opens.
    docs = docstring_lines(lines)
    lines = [line if i in docs else snake_names(line, table) for i, line in enumerate(lines)]
    rewrite = CastsAndRanges(lines, docs, libraries())
    lines = rewrite.rewrite()
    if kept is not None:
        kept.extend(rewrite.kept)
    shift = 0

    # Pass one: the indentation, read from the file's own nesting the way the
    # transpiler reads it. Each open block remembers the indent and the keyword
    # of the line that opened it, the keyword only so that a `case` can decline
    # to close the `match` it belongs to.
    out: list[str] = []
    stack: list[tuple[int, str]] = []
    open_brackets = 0
    for index, line in enumerate(lines):
        body = line.strip()
        if index in docs and index - 1 in docs:
            out.append(" " * max(0, leading_space(line) + shift) + body if body else "")
            continue
        if open_brackets > 0:
            # A statement still inside an open bracket is its writer's to lay
            # out. The dialect continues a line Python's way, "so a long call is
            # broken wherever it reads best", and a continuation ends in a comma
            # rather than a colon, so a formatter that reads nesting off it
            # opens nothing and flattens the rows of every matrix in the tree
            # back to the block's own indent. Such a line cannot be allowed to
            # pop the stack either: indented less than its block, it would
            # re-indent everything under it.
            out.append(line)
            open_brackets += bracket_delta(split_comment(body)[0])
            continue
        if not body:
            out.append("")
            continue
        indent = leading_space(line)
        while stack and indent <= stack[-1][0]:
            if CASE.search(body) and stack[-1][1] == "match" and indent == stack[-1][0]:
                break
            stack.pop()
        out.append(INDENT * len(stack) + body)
        if index in docs:
            shift = len(INDENT) * len(stack) - indent
            continue
        code, _ = split_comment(body)
        if code.rstrip().endswith(":"):
            stack.append((indent, "match" if MATCH.search(body) else ""))
        open_brackets = max(0, bracket_delta(code))

    return "\n".join(_blank_lines(out)) + "\n"


def _blank_lines(lines: list[str]) -> list[str]:
    """The blank line rules, over already-indented lines.

    Runs collapse to one rather than being inserted, so a group of declarations
    the writer put together stays a group. A top-level `def` or `struct` takes
    two, counted above its decorator when it has one, and a decorator and its
    `def` take none between them.
    """
    out: list[str] = []
    for i, line in enumerate(lines):
        if not line:
            if not out or not out[-1]:
                continue
            nxt = next((text for text in lines[i + 1 :] if text), "")
            if DECORATOR.search(nxt) or TOP_LEVEL_BLOCK.search(nxt):
                continue  # the run is written whole when its owner is reached
            out.append("")
            continue
        if (DECORATOR.search(line) or TOP_LEVEL_BLOCK.search(line)) and not line.startswith(" ") and out:
            wanted = 0 if out and DECORATOR.search(out[-1]) else 2
            while out and not out[-1]:
                out.pop()
            out.extend([""] * wanted)
        out.append(line)
    while out and not out[-1]:
        out.pop()
    return out


def check(path: Path, table: dict[str, str]) -> list[str]:
    """What *path* would change, as a diff whose every hunk names its line.

    A diff rather than a line-for-line comparison, because most of what this
    fixes inserts or removes a line and every line under it then reads as wrong.
    One missing blank above a `def` printed thirteen changed lines that way, and
    a report nobody can act on is a check nobody runs.
    """
    original = path.read_text(encoding="utf-8")
    if not is_dialect(original):
        return []
    formatted = format_text(original, table)
    if formatted == original:
        return []
    problems = []
    was = original.split("\n")
    now = formatted.split("\n")
    for group in difflib.SequenceMatcher(None, was, now).get_opcodes():
        tag, i1, i2, j1, j2 = group
        if tag == "equal":
            continue
        problems.append("%s:%d:" % (path, i1 + 1))
        for line in was[i1:i2]:
            problems.append("  - %s" % line)
        for line in now[j1:j2]:
            problems.append("  + %s" % line)
    return problems


def gmacs_files(roots: list[Path]) -> list[Path]:
    out: list[Path] = []
    for root in roots:
        if root.is_file():
            out.append(root)
        else:
            out.extend(sorted(root.rglob("*.gmacs")))
    return out


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("paths", nargs="*", type=Path, help="files or directories, default the whole project")
    parser.add_argument("--check", action="store_true", help="report rather than rewrite, non-zero when anything would change")
    parser.add_argument("--casts", action="store_true", help="count every float() cast the formatter keeps, by its reason, and change nothing")
    args = parser.parse_args(argv)

    roots = args.paths or [GODOT / "shaders", GODOT / "modules"]
    table = names()
    dialect = 0
    glsl: list[Path] = []
    problems: list[str] = []
    written: list[Path] = []
    changed = 0
    kept: list[tuple[int, str]] = []
    for path in gmacs_files(roots):
        text = path.read_text(encoding="utf-8")
        if not is_dialect(text):
            glsl.append(path)
            continue
        dialect += 1
        formatted = format_text(text, table, kept)
        if formatted == text or args.casts:
            continue
        changed += 1
        if args.check:
            problems.extend(check(path, table))
        else:
            path.write_text(formatted, encoding="utf-8")
            written.append(path)

    # A GLSL file is said out loud rather than passed over, because a formatter
    # that quietly does nothing is one you stop trusting. The tree is all GLSL
    # until the sweep is through, so this is the ordinary case today.
    if glsl:
        print("left alone, written in GLSL: %d file(s)" % len(glsl))
        for path in glsl[:5]:
            print("  %s" % path)
        if len(glsl) > 5:
            print("  and %d more" % (len(glsl) - 5))
    for line in problems:
        print(line)
    if args.casts:
        reasons: dict[str, int] = {}
        for _, reason in kept:
            reasons[reason] = reasons.get(reason, 0) + 1
        print("%d float() cast(s) kept" % len(kept))
        for reason, count in sorted(reasons.items(), key=lambda item: -item[1]):
            print("  %4d  %s" % (count, reason))
    for path in written:
        print("formatted %s" % path)
    print("%d dialect file(s) read, %d changed" % (dialect, len(written) or changed))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
