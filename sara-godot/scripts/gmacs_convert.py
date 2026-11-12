#!/usr/bin/env python3
"""Turns one of today's GLSL `.gmacs` kernels into the dialect, line for line.

The sweep converts twenty-five kernels and seven libraries, 4432 lines, and
one `.clang-format` shaped every one of them, so the rules that hold for all of
them are a script rather than six units of typing. What the
script cannot do it leaves exactly as it found it with a marked line above it,
so the unit that runs it sees every spot to finish by hand:

    python3 sara-godot/scripts/gmacs_convert.py shaders/compute/fill.gmacs
    python3 sara-godot/scripts/gmacs_convert.py --in-place shaders/compute/*.gmacs

The rewrites are the ones the format change calls for: braces to indentation, semicolons
off, the `[numthreads]` attribute to the `@workgroup_size` decorator, `#kernel`
and `#include` to the keywords `kernel` and `import`, the four `layout(...)`
declarations to their short forms, the push constant block to `params:` with
its reads bare, `//` and `/* */` to `#`, `else if` to `elif`, `switch` to
`match`, and the GLSL spelling of every name in `gmacs_names.json` to the snake
one. `&&`, `||` and unary `!` become `and`, `or` and `not`, and the paren
spacing the `.clang-format` put in comes out, because a dialect file that reads
`image_load( src, pixel )` is not the language the spec shows.

**Every rewrite here keeps the program the same program.** That is what the
manifest checks and it is the reason two of them are narrower than they look.
A `for` becomes `range()` only when it counts up by one or by a step with `<`,
because `i <= n` and `i < n + 1` are not the same SPIR-V and a `range()` that
counts down does not exist. And a trailing pad field is dropped only when it is
a run of `float`s, which is exactly what `SaDialect` writes back: a `vec2 pad`
and two floats are the same eight bytes and not the same struct, so a `vec2`,
`uint` or array pad stays where it was written.

The name table is `core/custom-shader/gmacs_names.json`, read in the direction
the file stores it, GLSL spelling to snake spelling, so this and the transpiler
cannot drift. What a line *is* before any of this reads it, the string spans,
the comment split and the four folds that flatten the tree's brace style, is in
`gmacs_source.py` beside this file.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

from gmacs_source import (
    _bracket_delta,
    _decompose,
    _fold_broken_statements,
    _fold_buffer_blocks,
    _fold_open_braces,
    _pad_drops,
    _params_instance,
    _spans,
    is_dialect,
)

SCRIPTS = Path(__file__).resolve().parent
NAMES_FILE = SCRIPTS.parent / "core" / "custom-shader" / "gmacs_names.json"

## Four spaces a level, the dialect's own indentation.
INDENT = "    "

## What a line the converter could not do carries above it. Greppable on
## purpose: the unit that runs the script finishes every one of them by hand.
MARK = "# gmacs_convert: "


## The line thirty-five kernels open with, which the transpiler now writes on
## the signature itself, so a converted file lets it.
PIXEL_LINE = re.compile(r"^ivec2 pixel = ivec2\((?:gl_GlobalInvocationID|global_id)\.xy\);$")


def load_names(path: Path = NAMES_FILE) -> dict[str, str]:
    """The name table, GLSL spelling to snake spelling, both halves in one."""
    table = json.loads(path.read_text(encoding="utf-8"))
    names: dict[str, str] = {}
    for half in ("variables", "functions"):
        names.update(table.get(half, {}))
    return names



def _inline_body(text: str) -> tuple[str, str] | None:
    """*text* as `(header, body)` when it carries both, or None.

    The tree's `.clang-format` allows a short `if` on one line and writes the
    small helpers of the colour libraries as `bool f() { return x; }`. Only one
    statement fits after the dialect's colon, so a braced body of two is left
    for the hand rather than silently joined.
    """
    if not text.endswith("}"):
        found = re.match(r"^((?:if|else\s+if|while|for)\s*\(.*\))\s*(\S.*;)$", text)
        return (found.group(1), found.group(2)) if found is not None else None

    depth = 0
    for i, c in enumerate(text):
        if c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
        elif c == "{" and depth == 0:
            head = text[:i].strip()
            body = text[i + 1 : -1].strip()
            if not head or body.count(";") != 1 or not body.endswith(";"):
                return None
            return head, body
    return None


class Converter:
    """One file's worth of state: the block stack, the params block, the notes."""

    def __init__(self, names: dict[str, str]) -> None:
        self.names = names
        self.notes: list[str] = []
        self.blocks: list[str] = []
        self.params_instance = ""
        self.bindings = 0
        self.await_instance = False
        self.line_number = 0

    # The rewrites that run on every code line before anything reads it.

    def _prepare(self, code: str) -> str:
        out = ""
        for text, is_string in _spans(code):
            if is_string:
                out += text
                continue
            text = re.sub(r"\(\s+", "(", text)
            text = re.sub(r"\s+\)", ")", text)
            for glsl, snake in self.names.items():
                if glsl in text:
                    text = re.sub(r"\b%s\b" % re.escape(glsl), snake, text)
            text = text.replace("&&", " and ").replace("||", " or ")
            text = re.sub(r"!(?=[A-Za-z_(])", "not ", text)
            if self.params_instance:
                text = re.sub(r"\b%s\s*\.\s*" % re.escape(self.params_instance), "", text)
            out += text
        return re.sub(r"\s{2,}", " ", out.strip()) if out.strip() else out

    def _note(self, reason: str) -> str:
        self.notes.append("line %d: %s" % (self.line_number, reason))
        return MARK + reason

    # The block stack. A `case` is a level of the dialect's indentation that
    # GLSL does not brace, so it is popped by its sibling rather than by a `}`.

    def _pop_cases(self) -> None:
        while self.blocks and self.blocks[-1] == "case":
            self.blocks.pop()

    def convert(self, text: str) -> str:
        lines = text.split("\n")
        pieces = _fold_buffer_blocks(_fold_broken_statements(_fold_open_braces(_decompose(lines))), self.notes)
        self.params_instance, instance_note = _params_instance(pieces)
        if instance_note:
            self.notes.append(instance_note)
        drops, pad_notes = _pad_drops(pieces)
        self.notes.extend(pad_notes)

        out: list[str] = []
        open_brackets = 0
        base_indent = 0
        for index, (code, comment) in enumerate(pieces):
            self.line_number = index + 1
            if code == "\x00":
                continue
            if index in drops:
                if comment is not None:
                    out.append(self._emit("", comment))
                continue
            if open_brackets > 0:
                original = len(code) - len(code.lstrip())
                prepared = self._prepare(code).rstrip()
                open_brackets += _bracket_delta(code)
                if prepared.endswith("{"):
                    prepared = self._note("a block header broken over lines has no dialect form.") + " " + prepared
                out.append(self._emit(prepared.rstrip(";"), comment, max(0, original - base_indent)))
                continue
            if not code.strip():
                out.append(self._emit("", comment, 0))
                continue
            base_indent = len(code) - len(code.lstrip())
            open_brackets = max(0, _bracket_delta(code))
            for written in self._line(self._prepare(code), comment):
                out.append(written)

        while out and not out[-1].strip():
            out.pop()
        return "\n".join(out) + "\n"

    def _emit(self, text: str, comment: str | None, extra: int = 0) -> str:
        line = INDENT * len(self.blocks) + " " * extra + text if text else ""
        if comment is None:
            return line.rstrip()
        rendered = "# " + comment if comment else "#"
        if line:
            return line + "  " + rendered
        return (INDENT * len(self.blocks) + rendered).rstrip()

    def _line(self, text: str, comment: str | None) -> list[str]:
        """One prepared code line as the dialect lines it becomes."""
        if self.await_instance and re.match(r"^\w+\s*;$", text):
            self.await_instance = False
            return [self._emit("", comment)] if comment is not None else []

        while text.startswith("}"):
            self._pop_cases()
            if self.blocks:
                closed = self.blocks.pop()
                if closed == "params":
                    self.await_instance = True
            text = text[1:].lstrip()
            if text.startswith(";"):
                text = text[1:].lstrip()
            if self.await_instance and re.match(r"^\w+\s*;$", text):
                self.await_instance = False
                text = ""

        if not text:
            return [self._emit("", comment)] if comment is not None else []

        if PIXEL_LINE.match(text) is not None:
            return [self._emit("", comment)] if comment is not None else []

        if text.startswith("#"):
            return self._directive(text, comment)

        declaration = self._declaration(text, comment)
        if declaration is not None:
            return declaration

        inline = _inline_body(text)
        if inline is not None:
            return self._inline(inline[0], inline[1], comment)

        opens = text.endswith("{")
        head = text[:-1].strip() if opens else text
        if opens:
            return self._header(head, comment)
        return self._statement(head, comment)

    def _inline(self, head: str, body: str, comment: str | None) -> list[str]:
        """`bool f() { return x; }` and `if (a) return;`, as the dialect's one-line body.

        The transpiler reads a statement written after the colon and closes the
        block on the spot, which is the spec's `if x >= size.x: return`, so a
        line the tree already wrote on one line stays on one.
        """
        written = self._header(head, None)
        self.blocks.pop()
        inner = self._statement(body.strip(), None)
        if not inner or not inner[-1].strip():
            return written[:-1] + [self._emit(written[-1].strip(), comment)]
        return written[:-1] + [self._emit("%s %s" % (written[-1].strip(), inner[-1].strip()), comment)]

    def _directive(self, text: str, comment: str | None) -> list[str]:
        found = re.match(r"^#kernel\s+(\w+)$", text)
        if found is not None:
            return [self._emit("kernel " + found.group(1), comment)]
        found = re.match(r'^#include\s+"([^"]+)"$', text)
        if found is not None:
            return [self._emit("import " + found.group(1), comment)]
        return [
            self._emit(self._note("'%s' is a preprocessor directive the dialect has no word for." % text.split()[0]), None),
            self._emit(text, comment),
        ]

    def _declaration(self, text: str, comment: str | None) -> list[str] | None:
        """The four `layout(...)` kinds, or None when *text* is not one."""
        if not text.startswith("[") and "layout(" not in text:
            return None

        found = re.match(r"^\[numthreads\((.*?)\)\]$", text)
        if found is not None:
            # The attribute on a line of its own duplicates the one on the
            # signature in every kernel of the tree, and the decorator belongs
            # directly above the `def`, so this one goes.
            return [self._emit("", comment)] if comment is not None else []

        found = re.match(r"^layout\(([^)]*)\)\s+uniform\s+(.*?)image2D\s+(\w+)\s*;$", text)
        if found is not None:
            return [self._emit(self._image(found.group(1), found.group(2), found.group(3)), comment)]

        found = re.match(r"^layout\(([^)]*)\)\s+uniform\s+sampler2D\s+(\w+)\s*;$", text)
        if found is not None:
            self.bindings += 1
            return [self._emit("sampler " + found.group(2), comment)]

        found = re.match(r"^layout\(([^)]*)\)\s+buffer\s+\w+\s*\{\s*(.*?)\s*;\s*\}\s*(\w+)\s*;$", text)
        if found is not None:
            self.bindings += 1
            return [self._emit("buffer %s: %s" % (found.group(3), found.group(2)), comment)]

        found = re.match(r"^layout\(\s*push_constant.*?\)\s+uniform\s+\w+\s*\{$", text)
        if found is not None:
            written = self._emit("params:", comment)
            self.blocks.append("params")
            return [written]

        return None

    def _image(self, layout: str, qualifiers: str, name: str) -> str:
        self.bindings += 1
        parts = [part.strip() for part in layout.split(",")]
        formats = [part for part in parts if "=" not in part and part != "SA_STORAGE_FORMAT"]
        memory = [word for word in qualifiers.split() if word]
        tail = ", ".join(formats + memory)
        return "image %s: %s" % (name, tail) if tail else "image " + name

    def _header(self, head: str, comment: str | None) -> list[str]:
        found = re.match(r"^\[numthreads\((.*?)\)\]\s+(.*)$", head)
        decorator: list[str] = []
        if found is not None:
            workgroup = self._workgroup(found.group(1))
            if workgroup:
                decorator = [self._emit(workgroup, None)]
            head = found.group(2).strip()

        found = re.match(r"^else\s+if\s*\((.*)\)$", head)
        if found is not None:
            return self._opened("elif %s:" % found.group(1), comment)

        if head == "else":
            return self._opened("else:", comment)

        found = re.match(r"^(if|while)\s*\((.*)\)$", head)
        if found is not None:
            return self._opened("%s %s:" % (found.group(1), found.group(2)), comment)

        found = re.match(r"^switch\s*\((.*)\)$", head)
        if found is not None:
            return self._opened("match %s:" % found.group(1), comment)

        found = re.match(r"^for\s*\((.*)\)$", head)
        if found is not None:
            return self._for_loop(found.group(1), head, comment)

        found = re.match(r"^struct\s+(\w+)$", head)
        if found is not None:
            return self._opened("struct %s:" % found.group(1), comment)

        found = re.match(r"^([A-Za-z_]\w*)\s+(\w+)\s*\((.*)\)$", head)
        if found is not None:
            arrow = "" if found.group(1) == "void" else " -> " + found.group(1)
            return decorator + self._opened("def %s(%s)%s:" % (found.group(2), found.group(3), arrow), comment)

        marked = self._emit(self._note("'%s' is a block header this script does not know." % head), None)
        return [marked] + self._opened(head + " {", comment)

    def _opened(self, text: str, comment: str | None) -> list[str]:
        """The header at its own level, and the block its body is indented in."""
        written = self._emit(text, comment)
        self.blocks.append("brace")
        return [written]

    def _workgroup(self, args: str) -> str:
        sizes = [arg.strip() for arg in args.split(",")]
        while len(sizes) > 1 and sizes[-1] == "1":
            sizes.pop()
        # The default is what a missing line means, so the default writes
        # nothing.
        if sizes == ["8", "8"]:
            return ""
        return "@workgroup_size(%s)" % ", ".join(sizes)

    def _for_loop(self, clauses: str, head: str, comment: str | None) -> list[str]:
        """The `for` header as `range` or `range_inclusive`, marked when neither fits.

        The dialect emits the comparison and the step it was written with, so a
        loop only converts to the form that comes back as the same program. The
        inclusive bound and the descending step have a spelling of their own,
        and the counter takes its type where it is not an `int`, which is what
        the nine loops in `selection`, `wand`, `graph` and `libs/noise` need.
        """
        parts = clauses.split(";")
        opened = self._range_call(parts) if len(parts) == 3 else ""
        if opened:
            return self._opened(opened, comment)

        marked = self._emit(self._note("this loop's counting has no dialect form."), None)
        return [marked] + self._opened(head + " {", comment)

    def _range_call(self, parts: list[str]) -> str:
        """`for x in range(...)` for the three clauses of a C loop, or ""."""
        declared = re.match(r"^\s*(\w+)\s+(\w+)\s*=\s*(.+?)\s*$", parts[0])
        if declared is None:
            return ""
        counter_type, name, start = declared.group(1), declared.group(2), declared.group(3)
        bound = re.match(r"^\s*%s\s*(<=|>=|<|>)\s*(.+?)\s*$" % re.escape(name), parts[1])
        if bound is None:
            return ""
        comparison, stop = bound.group(1), bound.group(2)

        one = r"^\s*(?:%s%s|%s%s)\s*$"
        advance = ""
        if re.match(one % ("\\+\\+", re.escape(name), re.escape(name), "\\+\\+"), parts[2]) is not None:
            advance = "1"
        elif re.match(one % ("--", re.escape(name), re.escape(name), "--"), parts[2]) is not None:
            advance = "-1"
        else:
            by = re.match(r"^\s*%s\s*\+=\s*(.+?)\s*$" % re.escape(name), parts[2])
            if by is None:
                return ""
            advance = by.group(1)

        counts_down = advance.startswith("-")
        if comparison == "<" and not counts_down:
            call = "range(%s, %s)" % (start, stop) if advance == "1" else "range(%s, %s, %s)" % (start, stop, advance)
        elif comparison == "<=" and not counts_down:
            call = ("range_inclusive(%s, %s)" % (start, stop)) if advance == "1" else ("range_inclusive(%s, %s, %s)" % (start, stop, advance))
        elif comparison == ">=" and counts_down:
            call = "range_inclusive(%s, %s, %s)" % (start, stop, advance)
        else:
            return ""

        prefix = "" if counter_type == "int" else counter_type + " "
        return "for %s%s in %s:" % (prefix, name, call)

    def _statement(self, text: str, comment: str | None) -> list[str]:
        found = re.match(r"^case\s+(.+?)\s*:$", text)
        if found is not None:
            self._pop_cases()
            written = self._emit("case %s:" % found.group(1), comment)
            self.blocks.append("case")
            return [written]

        if text == "default:":
            self._pop_cases()
            written = self._emit("case _:", comment)
            self.blocks.append("case")
            return [written]

        if text == "break;" and self.blocks and self.blocks[-1] == "case":
            # The transpiler inserts the `break` each case needs, and a case
            # that already returned takes none, so the file stops writing it.
            return [self._emit("", comment)] if comment is not None else []

        return [self._emit(text.rstrip(";").rstrip(), comment)]


def convert(text: str, names: dict[str, str] | None = None) -> tuple[str, list[str]]:
    """*text* as the dialect, with the notes for every line left as it was."""
    converter = Converter(load_names() if names is None else names)
    return converter.convert(text), converter.notes


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("files", nargs="+", type=Path, help="the .gmacs files to convert")
    parser.add_argument("-i", "--in-place", action="store_true", help="rewrite each file rather than print it")
    args = parser.parse_args(argv)

    if not args.in_place and len(args.files) > 1:
        print("gmacs_convert: more than one file needs --in-place.", file=sys.stderr)
        return 2

    names = load_names()
    for path in args.files:
        source = path.read_text(encoding="utf-8")
        if is_dialect(source):
            print("%s: already the dialect, left alone." % path, file=sys.stderr)
            continue
        converted, notes = convert(source, names)
        if args.in_place:
            path.write_text(converted, encoding="utf-8")
        else:
            sys.stdout.write(converted)
        for note in notes:
            print("%s:%s" % (path, note), file=sys.stderr)
        marked = [note for note in notes if note.startswith("line ")]
        if marked:
            print("%s: %d line(s) left for the hand." % (path, len(marked)), file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
