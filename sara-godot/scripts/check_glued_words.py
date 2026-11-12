#!/usr/bin/env python3
"""Find a translated message that code glues into a sentence a translator cannot see whole.

    cd sara-godot && python scripts/check_glued_words.py
    python scripts/check_glued_words.py --shrink

`check_translated.py` runs this from its `main`, so the gate's line for it
reads both. It reads the same `.gd` files with the same lexer and the same
index of translating calls, and looks at what code does with a message once
it is translated. Three kinds are flagged:

  dropped  a translated sentence holding a placeholder whose value is another
           translated message, `tr("Add %s") % tr(kind)`, or a variable this
           function set from one, since a language with grammatical cases
           needs the word in the case the sentence asks for
  glued    a translated message with a string literal of punctuation or space
           added before or after it in code, `tr("Size") + ": "`, or dropped
           into a format string with no words, `"%s:" % tr("Size")`, since
           French puts a space before a colon and Czech has its own quotes
  english  a translating call whose message is made from English by a string
           method, a concatenation or a format, `tr(name.trim_suffix(" Tool"))`,
           since the template cannot read the message and a translator never
           sees it

A sentence into which a name the painter typed or a number is dropped is not a
hit, because nothing translated goes in. A literal that is only line breaks
between two messages is not glue either, since a break means the same in
every language.

The tree carried hits when this arrived, so they are a list,
`check_glued_words_list.txt`, one line per hit with its file, kind and the
code that hits, so an edit above a hit does not move it. A hit the list does
not name fails with its file, line and advice, and so does a line the tree no
longer has, so the list only shrinks. `--shrink` deletes the stale lines and
never adds one. `--root` reads every `.gd` under a folder instead of what git
tracks, and `--list` reads another list, which is how the suite runs it over a
fixture.

Exits 0 when every hit is on the list and every line is a hit, 1 otherwise.
"""

from __future__ import annotations

import re
import sys
from collections import Counter
from dataclasses import dataclass
from pathlib import Path

import check_translated as ct

LIST = ct.SARA_GODOT / "scripts" / "check_glued_words_list.txt"

HEAD = """\
# The translated messages code glued into sentences when check_glued_words.py
# arrived, one line per hit: the file under sara-godot, the kind, and the code
# that hits. A line leaves when its sentence is written whole, and no line is
# ever added. A line that stays says why after a tab, and the reason is
# ignored when the line is matched.
"""

DROPPED = "dropped"
GLUED = "glued"
ENGLISH = "english"

ADVICE = {
    DROPPED: "write the whole sentence for each word as its own message, so a language with cases can decline the word",
    GLUED: "put the punctuation inside the message, tr(\"Size: %s\"), so a language can space or quote it its own way",
    ENGLISH: "translate a message the template can read, a literal or a constant table, never one made from English",
}

STRING_METHODS = frozenset(
    {
        "capitalize",
        "to_lower",
        "to_upper",
        "trim_prefix",
        "trim_suffix",
        "replace",
        "replacen",
        "substr",
        "left",
        "right",
        "strip_edges",
        "to_snake_case",
        "to_camel_case",
        "to_pascal_case",
        "format",
        "join",
        "lstrip",
        "rstrip",
        "insert",
        "repeat",
    }
)

PLACEHOLDER = re.compile(r"%[-+ 0#]*(?:\d+|\*)?(?:\.(?:\d+|\*))?[a-zA-Z]|\{\w*\}")
BREAK_ONLY = re.compile(r"^(?:\\n|\\t|\\r|[ \t])*\\n(?:\\n|\\t|\\r|[ \t])*$")


@dataclass(frozen=True)
class Hit:
    """One flagged piece of code: the file, the line, the kind and the code."""

    path: str
    line: int
    form: str
    text: str

    def key(self) -> ct.Key:
        return (self.path, self.form, self.text)


@dataclass(frozen=True)
class Call:
    """A translating call: the first token of its name, its brackets, and its first argument's end."""

    start: int
    open: int
    close: int
    first_end: int


def render(toks: list[ct.Token]) -> str:
    """A span of tokens written back as one line of code, spaced the same whatever the source did."""
    out = ""
    for i, tok in enumerate(toks):
        if tok.kind == "nl":
            continue
        prev = toks[i - 1] if i else None
        tight = prev is None or prev.text in ("(", "[", ".", "{") or tok.text in (")", "]", ".", ",", "}")
        if tok.text in ("(", "[") and prev is not None and (prev.kind == "id" or prev.text in (")", "]")):
            tight = True
        out += ("" if tight or not out else " ") + tok.text
    return out


def _matching(toks: list[ct.Token]) -> dict[int, int]:
    """Each opening bracket's index mapped to its closing bracket's."""
    pairs: dict[int, int] = {}
    stack: list[int] = []
    for i, tok in enumerate(toks):
        if tok.kind != "op":
            continue
        if tok.text in ("(", "[", "{"):
            stack.append(i)
        elif tok.text in (")", "]", "}") and stack:
            pairs[stack.pop()] = i
    return pairs


def _calls(toks: list[ct.Token], pairs: dict[int, int], index: ct.Index, path: str) -> list[Call]:
    """Every call in the file that translates its first argument."""
    out: list[Call] = []
    for at, tok in enumerate(toks):
        if tok.text != "(" or at not in pairs:
            continue
        frame = ct._opened(toks, at, index, path)
        if frame.reaches is None or not frame.reaches.translates:
            continue
        start = at - 1
        if start >= 2 and toks[start - 1].text == "." and toks[start - 2].kind == "id":
            start -= 2
        close = pairs[at]
        first_end = close
        depth = 0
        for i in range(at + 1, close):
            text = toks[i].text
            if text in ("(", "[", "{"):
                depth += 1
            elif text in (")", "]", "}"):
                depth -= 1
            elif text == "," and depth == 0:
                first_end = i
                break
        out.append(Call(start, at, close, first_end))
    return out


def _is_glue(tok: ct.Token) -> bool:
    """A string literal of punctuation or space only, and not a bare line break."""
    if tok.kind != "str" or tok.text.startswith(("&", "^")):
        return False
    inner = ct.body(tok.text)
    if not inner or BREAK_ONLY.match(inner):
        return False
    return not any(ch.isalnum() for ch in ct.ESCAPE.sub("", inner))


def _value_end(toks: list[ct.Token], at: int, pairs: dict[int, int]) -> int:
    """The index past the operand that starts at *at*, a bracket or a chain of names, calls and indexes."""
    if at >= len(toks):
        return at
    if toks[at].text in ("(", "[", "{") and at in pairs:
        i = pairs[at] + 1
    elif toks[at].kind in ("id", "str", "num"):
        i = at + 1
    else:
        return at + 1
    while i < len(toks):
        if toks[i].text in ("(", "[") and i in pairs:
            i = pairs[i] + 1
        elif toks[i].text == "." and i + 1 < len(toks) and toks[i + 1].kind == "id":
            i += 2
        else:
            break
    return i


class FileScan:
    """The hits of one file, read off its tokens once the translating calls are found."""

    def __init__(self, path: str, source: str, index: ct.Index) -> None:
        self.path = path
        self.toks = ct.tokens(source)
        self.pairs = _matching(self.toks)
        self.calls = _calls(self.toks, self.pairs, index, path)
        self.starts = {c.start: c for c in self.calls}
        self.closes = {c.close: c for c in self.calls}
        self.words = self._translated_names()

    def hits(self) -> list[Hit]:
        found: list[Hit] = []
        for call in self.calls:
            found.extend(self._english(call))
            found.extend(self._dropped(call))
            found.extend(self._glued_around(call))
        found.extend(self._glued_by_format())
        return sorted(set(found), key=lambda h: (h.line, h.form, h.text))

    def _translated_names(self) -> dict[int, set[str]]:
        """For each token, the variables its function set from a translated message before it."""
        names: set[str] = set()
        out: dict[int, set[str]] = {}
        for at, tok in enumerate(self.toks):
            if tok.kind == "id" and tok.text == "func":
                names = set()
            out[at] = names
            target = self._assigned(at)
            if target is None:
                continue
            if at + 1 in self.starts:
                names = names | {target}
            elif target in names:
                names = names - {target}
        return out

    def _assigned(self, at: int) -> str | None:
        """The variable a statement `var x := ...`, `var x: T = ...` or `x = ...` sets at *at*, or None."""
        if self.toks[at].text not in ("=", ":="):
            return None
        first = at
        while first > 0 and self.toks[first - 1].kind != "nl":
            first -= 1
        head = self.toks[first:at]
        if head and head[0].text == "var":
            head = head[1:]
        if not head or head[0].kind != "id":
            return None
        if len(head) == 1 or (head[1].text == ":" and all(t.kind == "id" or t.text == "." for t in head[2:])):
            return head[0].text
        return None

    def _translated(self, start: int, end: int) -> bool:
        """Whether the span holds a translating call or a variable set from one."""
        if any(start <= c.start < end and not self._inside_call(start, c.start) for c in self.calls):
            return True
        known = self.words.get(start, set())
        return any(
            t.kind == "id" and t.text in known and (i == 0 or self.toks[i - 1].text != ".")
            for i, t in ((i, self.toks[i]) for i in range(start, end))
        )

    def _inside_call(self, start: int, at: int) -> bool:
        """Whether *at* sits in the brackets of a call that opens at or after *start*, whose result is not the word."""
        return any(
            self.toks[j].text == "(" and self.pairs.get(j, -1) > at and self.toks[j - 1].kind == "id"
            for j in range(start, at)
        )

    def _hit(self, form: str, at: int, start: int, end: int) -> Hit:
        return Hit(self.path, self.toks[at].line, form, render(self.toks[start:end]))

    def _english(self, call: Call) -> list[Hit]:
        """The message is made from English by a method, a `+` or a `%`."""
        span = range(call.open + 1, call.first_end)
        if all(self.toks[i].kind in ("str", "nl") or self.toks[i].text in ("(", ")", "+") for i in span):
            return []
        for i in span:
            tok = self.toks[i]
            inner = any(c.open < i <= c.close and c is not call and c.start > call.start for c in self.calls)
            if inner:
                continue
            method = tok.kind == "id" and tok.text in STRING_METHODS and self.toks[i - 1].text == "."
            joined = tok.text in ("+", "%") and (
                self.toks[i - 1].kind == "str" or (i + 1 < len(self.toks) and self.toks[i + 1].kind == "str")
            )
            if method or joined:
                return [self._hit(ENGLISH, call.start, call.start, call.close + 1)]
        return []

    def _dropped(self, call: Call) -> list[Hit]:
        """A translated sentence with a placeholder, filled with another translated message."""
        if call.first_end != call.open + 2 or call.first_end != call.close:
            return []
        message = self.toks[call.open + 1]
        if message.kind != "str" or not PLACEHOLDER.search(ct.body(message.text).replace("%%", "")):
            return []
        after = call.close + 1
        if after < len(self.toks) and self.toks[after].text == "%":
            end = _value_end(self.toks, after + 1, self.pairs)
            if self._translated(after + 1, end):
                return [self._hit(DROPPED, call.start, call.start, end)]
        if after + 2 < len(self.toks) and self.toks[after].text == "." and self.toks[after + 1].text == "format":
            end = _value_end(self.toks, after, self.pairs)
            if self._translated(after + 2, end):
                return [self._hit(DROPPED, call.start, call.start, end)]
        return []

    def _glued_around(self, call: Call) -> list[Hit]:
        """A literal of punctuation joined by `+` right before or right after the translated message."""
        out: list[Hit] = []
        end = _value_end(self.toks, call.start, self.pairs)
        if end + 1 < len(self.toks) and self.toks[end].text == "+" and _is_glue(self.toks[end + 1]):
            out.append(self._hit(GLUED, call.start, call.start, end + 2))
        before = call.start - 1
        if before >= 1 and self.toks[before].text == "+" and _is_glue(self.toks[before - 1]):
            out.append(self._hit(GLUED, call.start, before - 1, end))
        return out

    def _glued_by_format(self) -> list[Hit]:
        """A format string with no words, outside every translating call, filled with a translated message."""
        out: list[Hit] = []
        for at, tok in enumerate(self.toks):
            if tok.kind != "str" or at + 1 >= len(self.toks) or self.toks[at + 1].text != "%":
                continue
            inner = ct.body(tok.text)
            if not PLACEHOLDER.search(inner) or ct.has_words(tok.text) or tok.text.startswith(("&", "^")):
                continue
            if any(c.open < at <= c.first_end for c in self.calls):
                continue
            words = PLACEHOLDER.sub("", inner.replace("%%", ""))
            if not words.strip(" ") or BREAK_ONLY.match(words):
                continue
            end = _value_end(self.toks, at + 2, self.pairs)
            if self._translated(at + 2, end):
                out.append(self._hit(GLUED, at, at, end))
        return out


def scan(root: Path, paths: list[str]) -> list[Hit]:
    """Every hit of every file, the index of translating calls read from all of them first."""
    sources: dict[str, str] = {}
    for path in paths:
        file = root / path
        if file.is_file():
            sources[path] = file.read_text(encoding="utf-8", errors="replace")
    index = ct.Index()
    for path, source in sources.items():
        index.read(path, source)
    found: list[Hit] = []
    for path, source in sources.items():
        found.extend(FileScan(path, source, index).hits())
    return found


def read_list(file: Path) -> list[ct.Key]:
    """The list's lines as keys, the reason after a tab dropped, an absent file being an empty list."""
    if not file.is_file():
        return []
    out: list[ct.Key] = []
    for line in file.read_text(encoding="utf-8").splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        path, form, text = line.split("\t")[0].split(" ", 2)
        out.append((path, form, text))
    return out


def shrink(file: Path, stale: list[ct.Key]) -> None:
    """Delete the stale lines from the list, keeping its comments and reasons."""
    left = Counter(stale)
    kept: list[str] = []
    for line in file.read_text(encoding="utf-8").splitlines():
        if line.strip() and not line.startswith("#"):
            path, form, text = line.split("\t")[0].split(" ", 2)
            if left[(path, form, text)] > 0:
                left[(path, form, text)] -= 1
                continue
        kept.append(line)
    file.write_text("\n".join(kept) + "\n", encoding="utf-8")


def compare(found: list[Hit], listed: list[ct.Key], read: set[str], name: str) -> tuple[list[str], list[ct.Key]]:
    """The problems, and the lines of the list called *name* the tree no longer has."""
    allowed = Counter(listed)
    problems: list[str] = []
    for hit in sorted(found, key=lambda h: (h.path, h.line)):
        if allowed[hit.key()] > 0:
            allowed[hit.key()] -= 1
            continue
        problems.append(f"{hit.path}:{hit.line} [{hit.form}] {hit.text} is not on the list, {ADVICE[hit.form]}")
    stale = [key for key, left in allowed.items() for _ in range(left) if not ct._module_absent(key[0], read)]
    problems.extend(
        f"{name} names {p} [{f}] {t}, which the tree no longer has, delete the line or run --shrink"
        for p, f, t in stale
    )
    return problems, stale


def counts(found: list[Hit]) -> str:
    kinds = Counter(h.form for h in found)
    return ", ".join(f"{kinds[k]} {k}" for k in (DROPPED, GLUED, ENGLISH))


def main(argv: list[str]) -> int:
    root = ct.SARA_GODOT
    list_file = LIST
    if "--root" in argv:
        root = Path(argv[argv.index("--root") + 1]).resolve()
    if "--list" in argv:
        list_file = Path(argv[argv.index("--list") + 1]).resolve()
    paths = ct.folder_sources(root) if "--root" in argv else ct.tracked_sources(root)
    found = scan(root, paths)
    listed = read_list(list_file)
    problems, stale = compare(found, listed, set(paths), list_file.name)
    if "--shrink" in argv and stale:
        shrink(list_file, stale)
        print(f"check_glued_words: {len(stale)} line(s) taken off {list_file.name}")
        problems, stale = compare(found, read_list(list_file), set(paths), list_file.name)
    if problems:
        print("\n".join(problems))
        print("check_glued_words: code glues a translated message into a sentence")
        return 1
    print(f"check_glued_words: {len(found)} glued messages ({counts(found)}), every one on the list")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
