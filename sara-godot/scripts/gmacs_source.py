#!/usr/bin/env python3
"""The text half of the converter: what a `.gmacs` line is, before it is rewritten.

A sibling of `gmacs_convert.py` rather than three hundred more lines in it,
which is the seam the GDScript side already took when `sa_dialect.gd` grew a
`sa_gmacs_names.gd`. Everything here reads text and answers a question about
it, and nothing here knows what the dialect looks like: the string spans, the
comment split, the four folds that turn the tree's brace style into one line
per statement, the push constant block's pad and its instance name, and whether
a file is the dialect already.

The folds are what makes the converter small. The tree is `.clang-format`ed
Microsoft style, so a brace sits on its own line, a buffer is written over
five, and a short helper is written on one. Each of those is a shape the
rewrite would otherwise have to know about, and each is folded here into the
one shape it is: a header that ends in a brace, a declaration on one line, a
statement that ends in a semicolon.
"""

from __future__ import annotations

import re


## A pad field's name, as the tree spells it: `pad`, `pad1`, `_pad0`, `_pad_2`.
PAD_NAME = re.compile(r"^_*pad_*\d*$")

## What says a file is already the dialect, mirroring `SaDialect.is_dialect`:
## the first marker line decides, and a file with no marker at all is GLSL.
## Converting a converted file turns its `#` comments into marked directives and
## flattens its blocks, which is a mess to read back out of git, so the script
## refuses one rather than doing it.
DIALECT_MARKER = re.compile(
    r"^(?:kernel\s+\w+|import\s+[\w/]+|def\s+\w+\s*\(|@(?:workgroup_size|numthreads)\s*\("
    r"|(?:image|sampler|buffer)\s+\w+\s*[:$]|params(?:\s+\w+)?\s*:)"
)
GLSL_MARKER = re.compile(r"^#(?:kernel|include|version|define|pragma|extension|ifdef|ifndef|endif|else|elif|if|undef|line|error)\b|\blayout\s*\(|\[\s*numthreads\s*\(")
## A constant with no semicolon and its brackets closed on the line, which is
## how a library of constants alone says it is the dialect, so the converter
## refuses one it has already converted.
DIALECT_CONSTANT = re.compile(r"^const\s+\w+\s+\w+\s*(?:\[[^\]]*\]\s*)?=[^;]+$")


def is_dialect(text: str) -> bool:
    """True when *text* is written in the dialect already, so there is nothing to do."""
    for line in text.split("\n"):
        body = line.strip()
        if not body:
            continue
        if DIALECT_MARKER.search(body) is not None or re.match(r"^(?:image|sampler|buffer)\s+\w+$", body) is not None:
            return True
        # A constant holds no string, so its comment is whatever follows a hash.
        code = body.split("#", 1)[0].strip()
        if DIALECT_CONSTANT.search(code) is not None and _bracket_delta(code) == 0:
            return True
        if GLSL_MARKER.search(body) is not None:
            return False
    return False



def _spans(code: str) -> list[tuple[str, bool]]:
    """*code* as `(text, is_string_literal)` pairs, so a rewrite skips strings."""
    out: list[tuple[str, bool]] = []
    quote = ""
    start = 0
    i = 0
    while i < len(code):
        c = code[i]
        if not quote:
            if c in "\"'":
                out.append((code[start:i], False))
                start = i
                quote = c
        elif c == "\\":
            i += 1
        elif c == quote:
            out.append((code[start : i + 1], True))
            start = i + 1
            quote = ""
        i += 1
    if start < len(code):
        out.append((code[start:], bool(quote)))
    return out


def _bracket_delta(code: str) -> int:
    """Round and square brackets opened minus closed, outside strings.

    Braces are the block structure and are counted by the caller, not here.
    """
    depth = 0
    for text, is_string in _spans(code):
        if is_string:
            continue
        for c in text:
            if c in "([":
                depth += 1
            elif c in ")]":
                depth -= 1
    return depth


def _brace_delta(code: str) -> int:
    depth = 0
    for text, is_string in _spans(code):
        if is_string:
            continue
        for c in text:
            if c == "{":
                depth += 1
            elif c == "}":
                depth -= 1
    return depth


def _decompose(lines: list[str]) -> list[tuple[str, str | None]]:
    """Each line as `(code, comment)`, the comment without its marker.

    A `/* */` that spans lines gives every line it covers a comment, its `*`
    decoration off, so the header comment Sara's kernels open with comes out as
    a run of `#` lines rather than one paragraph on one.
    """
    out: list[tuple[str, str | None]] = []
    in_block = False
    for raw in lines:
        code = ""
        parts: list[str] = []
        opened = in_block
        quote = ""
        i = 0
        while i < len(raw):
            if in_block:
                if i == 0:
                    # The one space after the `*` is the marker's and is taken
                    # off by `_comment_text` with every other marker's, so that
                    # a line indented past it keeps exactly what it was indented.
                    raw_head = re.match(r"^\s*\*(?!/)", raw)
                    if raw_head is not None:
                        i = raw_head.end()
                        continue
                end = raw.find("*/", i)
                if end < 0:
                    parts.append(raw[i:])
                    i = len(raw)
                else:
                    parts.append(raw[i:end])
                    in_block = False
                    i = end + 2
                continue
            c = raw[i]
            if quote:
                code += c
                if c == "\\" and i + 1 < len(raw):
                    code += raw[i + 1]
                    i += 2
                    continue
                if c == quote:
                    quote = ""
                i += 1
                continue
            if c in "\"'":
                quote = c
                code += c
                i += 1
                continue
            if raw.startswith("//", i):
                parts.append(raw[i + 2 :])
                i = len(raw)
                continue
            if raw.startswith("/*", i):
                in_block = True
                i += 2
                continue
            code += c
            i += 1
        opened = opened or in_block or bool(parts)
        comment = " ".join(_comment_text(part) for part in parts).rstrip() if opened else None
        if comment == "" and not code.strip() and raw.strip() in ("/*", "*/", "/**"):
            # The delimiter lines of a block comment carry nothing, so they go
            # rather than leaving two bare hashes around the paragraph.
            comment = None
            code = "\x00"
        out.append((code, comment))
    return out


def _comment_text(part: str) -> str:
    """One comment fragment with its marker's own space off and its own indent on.

    Stripping the fragment outright is what flattened a list, a formula or a
    code block written inside a block comment: the `*` decoration and the one
    space after it are the marker, and everything past that is the writer's
    layout. So exactly one leading space goes, which is the one a person types
    after `//` or after `*`, and whatever is indented past it stays.
    """
    return (part[1:] if part.startswith(" ") else part).rstrip()


def _fold_open_braces(pieces: list[tuple[str, str | None]]) -> list[tuple[str, str | None]]:
    """A `{` alone on a line goes back onto the header it opens.

    The tree is formatted Microsoft style, brace on its own line, and the
    dialect's colon belongs on the header. Folding here means the block machine
    below sees one shape rather than two.
    """
    folded = list(pieces)
    for i, (code, comment) in enumerate(folded):
        if code.strip() != "{":
            continue
        previous = i - 1
        while previous >= 0 and not folded[previous][0].strip():
            previous -= 1
        if previous < 0:
            continue
        folded[previous] = (folded[previous][0].rstrip() + " {", folded[previous][1])
        folded[i] = ("" if comment is not None else "\x00", comment)
    return folded


def _fold_broken_statements(pieces: list[tuple[str, str | None]]) -> list[tuple[str, str | None]]:
    """A statement broken over lines outside its brackets becomes one line.

    The dialect continues a line the way Python does, inside an open bracket
    and nowhere else, so `return a\n    && b;` has no form of its own and is
    joined here. A break that *is* inside a bracket is left alone, because the
    dialect allows it and the writer put it where it reads best.
    """
    folded = list(pieces)
    i = 0
    while i < len(folded):
        body = folded[i][0].strip()
        if not body or body == "\x00" or body.startswith("#") or re.match(r"^\[numthreads", body) is not None:
            i += 1
            continue
        depth = _bracket_delta(folded[i][0])
        if depth > 0:
            while depth > 0 and i + 1 < len(folded):
                i += 1
                depth += _bracket_delta(folded[i][0])
            i += 1
            continue
        if body[-1] in ";{}:":
            i += 1
            continue
        j = i + 1
        while j < len(folded) and folded[j][0].strip() in ("", "\x00"):
            j += 1
        if j >= len(folded):
            i += 1
            continue
        folded[i] = (folded[i][0].rstrip() + " " + folded[j][0].strip(), folded[i][1])
        folded[j] = ("" if folded[j][1] is not None else "\x00", folded[j][1])
    return folded


def _fold_buffer_blocks(pieces: list[tuple[str, str | None]], notes: list[str]) -> list[tuple[str, str | None]]:
    """A storage buffer written over five lines becomes the one line it is.

    The dialect writes `buffer flood: uint changed` and the transpiler puts the
    braces back, so a block whose members are on lines of their own has to be
    joined before the declaration can be read. Members keep their order and
    their semicolons between them, which is what the transpiler expects to find
    after the colon, so a buffer of four fields still declares four.
    """
    folded = list(pieces)
    i = 0
    while i < len(folded):
        found = re.match(r"^\s*layout\s*\(([^)]*)\)\s+buffer\s+(\w+)\s*\{?\s*$", folded[i][0])
        if found is None:
            i += 1
            continue
        members: list[str] = []
        instance = ""
        end = -1
        j = i + 1
        while j < len(folded):
            body = folded[j][0].strip()
            if body.startswith("}"):
                rest = body[1:].strip().rstrip(";").strip()
                if rest:
                    instance, end = rest, j
                    break
                k = j + 1
                while k < len(folded) and folded[k][0].strip() in ("", "\x00"):
                    k += 1
                if k < len(folded):
                    instance, end = folded[k][0].strip().rstrip(";").strip(), k
                break
            if body and body != "\x00":
                members.append(body.rstrip(";").strip())
            j += 1
        if end < 0 or not re.match(r"^\w+$", instance):
            i += 1
            continue
        declaration = "layout(%s) buffer %s { %s; } %s;" % (found.group(1).strip(), found.group(2), "; ".join(members), instance)
        comments = [folded[k][1] for k in range(i, end + 1) if folded[k][1] is not None]
        if comments:
            notes.append("line %d: %d comment(s) on the members of buffer '%s' now sit above it, so reword them." % (i + 1, len(comments), instance))
        # The comments go above the declaration rather than under it. A member's
        # comment left below a one-line buffer reads as though it described the
        # whole block.
        fits = i + len(comments) <= end
        target = i + len(comments) if fits else i
        for slot in range(i, end + 1):
            if slot == target:
                folded[slot] = (declaration, None)
            elif fits:
                folded[slot] = ("", comments[slot - i]) if slot < target else ("\x00", None)
            else:
                folded[slot] = ("", comments[slot - i - 1]) if slot - i - 1 < len(comments) else ("\x00", None)
        i = end + 1
    return folded


def _pad_drops(pieces: list[tuple[str, str | None]]) -> tuple[set[int], list[str]]:
    """The trailing `float` pad lines of the push constant block, by index.

    They are dropped because `SaDialect` writes back exactly that, one `float`
    per four bytes short of sixteen. A pad of any other type is kept where it
    stands and named in the notes, because replacing it would change the struct
    and the manifest reads the struct.
    """
    start = -1
    for i, (code, _comment) in enumerate(pieces):
        if re.search(r"layout\s*\(\s*push_constant", code) is not None:
            start = i
            break
    if start < 0:
        return set(), []

    depth = 0
    end = len(pieces)
    for i in range(start, len(pieces)):
        depth += _brace_delta(pieces[i][0])
        if depth == 0 and i > start:
            end = i
            break

    fields: list[tuple[int, str, str, bool]] = []
    for i in range(start + 1, end):
        found = re.match(r"^\s*(\w+)\s+(\w+)\s*(\[[^\]]*\])?\s*;\s*$", pieces[i][0])
        if found is not None:
            fields.append((i, found.group(1), found.group(2), found.group(3) is not None))

    drops: set[int] = set()
    notes: list[str] = []
    for index, field_type, name, is_array in reversed(fields):
        if not PAD_NAME.match(name):
            break
        if field_type == "float" and not is_array:
            drops.add(index)
            continue
        notes.append(
            "line %d: '%s %s' is a pad the transpiler cannot write back as itself, so it stays a field." % (index + 1, field_type, name)
        )
        break
    return drops, notes


def _params_instance(pieces: list[tuple[str, str | None]]) -> tuple[str, str]:
    """The name a `p.` read carries in this file, and why, as `(name, note)`.

    A kernel says it outright: the push constant block closes with `} p;`. A
    library declares no block and reads its includer's, so `p.` there is the
    same prefix and comes off too, unless the file declares a `p` of its own,
    which `noise.gmacs` does in every one of its functions.
    """
    code = "\n".join(piece[0] for piece in pieces)
    found = re.search(r"layout\s*\(\s*push_constant[\s\S]*?\}\s*(\w+)\s*;", code)
    if found is not None:
        return found.group(1), ""
    if re.search(r"\bp\s*\.", code) is None:
        return "", ""
    if re.search(r"\b\w+\s+p\s*[,;)=]", code) is not None:
        return "", "this file declares a 'p' of its own, so no read of it was made bare."
    return "p", "this file reads the push constant of whatever includes it, so it converts with them."
