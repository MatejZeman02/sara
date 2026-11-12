#!/usr/bin/env python3
"""Find a word on screen that skips the translation.

    cd sara-godot && python scripts/check_translated.py
    python scripts/check_translated.py --shrink

The languages spec says every string on screen goes through `tr()`, so the
catalogue a language module registers reaches it, and that a sentence carrying
a count goes through `tr_n()` with the count, since a language with three
plural forms cannot make them from one string with the number already in it.
This check is the guard the spec asks for. It reads source text and needs no
Godot, so it runs in the gate's Python lines and in the workflow a pull request
on GitHub runs.

It reads the `.gd` files git tracks under `sara-godot`, the modules' submodules
included, and leaves out every file under a `tests`, `harness` or `scripts`
folder: the capture harness's messages are the harness talking to itself, and a
script is never on screen. Six forms are flagged:

  bare   a quoted string with a word in it reaching `text`, `tooltip_text` or
         `placeholder_text` by `=` or `+=`, outside every translating call
  built  a quoted string with a word in it passed where the function called
         sets that parameter straight into one of those properties, as
         `SaMake.label(box, "Name", "Open")` does, a control built with its words
  const  a name of a `const` that holds such a string, of the same file or of a
         class (`Panel.HINT`), standing where the bare string would, so the
         words reach the property with no `tr()` on the way. The hit is the
         string the constant holds, in the file that shows it. A web address is not
         a word. A `command.label`
         is not read, since every label of a command is translated where the
         command is shown and `write_pot.py` reads the string a label is given
  count  a string with a `%d` in it passed to `tr()` or to any call that
         translates one string, since a count goes through `tr_n()`
  ellipsis  a string with the one character U+2026 in it passed to any
         translating call, since a shown ellipsis is three dots, "...", as
         the wording rules write it
  tooltip  a string that is the whole of a translating call assigned to
         `tooltip_text` and does not end in a full stop, since the wording rules
         ask of a tooltip "an imperative sentence that ends in a full stop".
         Of a tooltip joined with `+` only the last piece
         is read, and a tooltip held in a variable is not read

What reaches a property is read off the tokens of one statement. A string
counts where it is a value of the assignment's right side, alone, joined with
`+`, formatted with `%` or one arm of an `if`, and not where it is an argument
of some other call or a key in brackets, since those hand the property
something else. A bare `text =` with no object before it counts only in a file
that declares no variable or parameter of that name.

A translating call is `tr`, `atr`, `TranslationServer.translate` and their
plural forms, and every function of the tree whose `return` hands its first
parameter to one of them, `SaPage.translated` among them. A call is matched to
the function it names in its own file, in the class its qualifier names, or,
behind any other receiver, only when every function of that name in the tree
agrees. A word is a letter left once the format codes, the escapes and the
BBCode tags are taken out, so `"%.2f"` and `"\\n"` are not words and `"%d px"` is.

The tree carried hits when this arrived, so they are a list,
`check_translated_list.txt`, one line per hit with its file, form and string,
the strings rather than line numbers so an edit above a hit does not move it. A
hit the list does not name fails with its file and line, and so does a line the
tree no longer has, so the list only shrinks. `--shrink` deletes the lines the
tree no longer has and never adds one. A line under a module whose submodule is
not checked out is left alone. `--root` reads every `.gd` under a folder
instead of what git tracks, and `--list` reads another list, which is how the
suite runs it over a fixture.

Its `main` then runs `check_glued_words.py`, which finds a translated message
code glues into a sentence, over the same tree, and the exit code is 1 when
either fails. Over a `--root` that second check runs only when `--glued-list`
names its list.

Exits 0 when every hit is on the list and every line is a hit, 1 otherwise.
"""

from __future__ import annotations

import re
import subprocess
import sys
from collections import Counter
from dataclasses import dataclass, field
from pathlib import Path

SARA_GODOT = Path(__file__).resolve().parent.parent
LIST = SARA_GODOT / "scripts" / "check_translated_list.txt"

# Folders whose files are never on screen: the suites, the capture harness and
# the Python scripts.
LEFT_OUT = ("tests", "harness", "scripts")

# The properties a control shows as words.
PROPERTIES = ("text", "tooltip_text", "placeholder_text")

# The engine's translating calls, by name and by whether they take a count.
SINGULAR = "singular"
PLURAL = "plural"
ON_ANY_OBJECT = {"tr": SINGULAR, "atr": SINGULAR, "tr_n": PLURAL, "atr_n": PLURAL}
ON_SERVER = {"translate": SINGULAR, "translate_plural": PLURAL}

# The operators longer than one character, longest first, so `==` is never two
# assignments and `+=` is one.
OPERATORS = ("**=", "<<=", ">>=", "==", "!=", "<=", ">=", "+=", "-=", "*=", "/=", "%=", "&=", "|=", "^=", ":=")
OPERATORS += ("->", "**", "<<", ">>", "&&", "||")

KEYWORDS = frozenset(
    "if elif else while for in return and or not is match when await func var const "
    "static class extends signal enum pass break continue super self assert".split()
)

FORMAT_CODE = re.compile(r"%[-+ 0#]*(?:\d+|\*)?(?:\.(?:\d+|\*))?[a-zA-Z%]")
ESCAPE = re.compile(r"\\(?:u[0-9a-fA-F]{4}|U[0-9a-fA-F]{6}|.)")
BBCODE = re.compile(r"\[/?[a-z_]+(?:=[^\]]*)?\]")
COUNT = re.compile(r"%[-+ 0#]*\d*d")
ELLIPSIS = "\u2026"

# A constant that starts so is a web address, which reads the same in every language.
ADDRESS = ("http://", "https://")

# A hit as the list writes it: the file, the form and the string, its runs of
# white space made one space so a string across lines fits on one.
Key = tuple[str, str, str]

HEAD = """\
# The words on screen that skipped the translation when check_translated.py
# arrived, one line per hit: the file under sara-godot, the form, and the
# string as the source writes it. A line leaves when its string goes through
# tr(), or through tr_n() for a count, and no line is ever added.
"""


@dataclass(frozen=True)
class Hit:
    """One flagged string: the file, the line it stands on, the form and the string."""

    path: str
    line: int
    form: str
    text: str

    def key(self) -> Key:
        return (self.path, self.form, " ".join(self.text.split()))


@dataclass(frozen=True)
class Token:
    """A word, a string, an operator or a line end of GDScript, with its line."""

    kind: str
    text: str
    line: int


def tokens(source: str) -> list[Token]:
    """The tokens of one file, comments dropped and every line end kept.

    A string keeps its prefix and its quotes. A line end inside brackets is
    kept as well, since a lambda's body ends at one, and a backslash before a
    line end joins the lines and leaves none.
    """
    out: list[Token] = []
    i = 0
    line = 1
    n = len(source)
    while i < n:
        c = source[i]
        if c == "\\" and source.startswith("\n", i + 1):
            i += 2
            line += 1
            continue
        if c == "\n":
            out.append(Token("nl", "\n", line))
            line += 1
            i += 1
            continue
        if c in " \t\r":
            i += 1
            continue
        if c == "#":
            end = source.find("\n", i)
            i = n if end < 0 else end
            continue
        prefix = re.match(r"[&^]?r?(?=[\"'])", source[i : i + 3])
        if prefix is not None:
            end, lines = _string_end(source, i + len(prefix.group(0)), "r" in prefix.group(0))
            out.append(Token("str", source[i:end], line))
            line += lines
            i = end
            continue
        if c.isalpha() or c == "_":
            j = i + 1
            while j < n and (source[j].isalnum() or source[j] == "_"):
                j += 1
            out.append(Token("id", source[i:j], line))
            i = j
            continue
        if c.isdigit():
            j = i + 1
            while j < n and (source[j].isalnum() or source[j] in "._"):
                j += 1
            out.append(Token("num", source[i:j], line))
            i = j
            continue
        for op in OPERATORS:
            if source.startswith(op, i):
                out.append(Token("op", op, line))
                i += len(op)
                break
        else:
            out.append(Token("op", c, line))
            i += 1
    return out


def _string_end(source: str, start: int, raw: bool) -> tuple[int, int]:
    """Where the string whose quote is at *start* ends, and how many lines it spans."""
    quote = source[start : start + 3] if source.startswith(('"""', "'''"), start) else source[start]
    i = start + len(quote)
    while i < len(source):
        if source[i] == "\\" and i + 1 < len(source) and (not raw or source[i + 1] in "\"'\\"):
            i += 2
            continue
        if source.startswith(quote, i):
            i += len(quote)
            return i, source.count("\n", start, i)
        if source[i] == "\n" and len(quote) == 1:
            return i, 0
        i += 1
    return i, source.count("\n", start, i)


def body(literal: str) -> str:
    """The text inside a string's quotes, prefix and quotes stripped."""
    rest = literal.lstrip("&^r")
    width = 3 if rest.startswith(('"""', "'''")) else 1
    return rest[width:-width] if len(rest) >= 2 * width else rest[width:]


def has_words(literal: str) -> bool:
    """Whether a string carries a letter once its codes, escapes and tags are out."""
    if literal.startswith(("&", "^")):
        return False
    words = BBCODE.sub("", FORMAT_CODE.sub("", ESCAPE.sub("", body(literal))))
    return any(ch.isalpha() for ch in words)


def ends_a_sentence(literal: str) -> bool:
    """Whether a string ends in a full stop, as the wording rules ask of a tooltip."""
    return body(literal).rstrip().endswith(".")


def _alone(toks: list[Token], at: int) -> bool:
    """Whether the string at *at* is the whole first argument of the call around it."""
    before = next((t for t in reversed(toks[:at]) if t.kind != "nl"), None)
    after = next((t for t in toks[at + 1 :] if t.kind != "nl"), None)
    return before is not None and before.text == "(" and after is not None and after.text in (")", ",")


def _joined_after(toks: list[Token], at: int) -> bool:
    """Whether the call holding the string at *at* is followed by a `+`, so its text does not end the tooltip."""
    depth = 0
    for i in range(at + 1, len(toks)):
        if toks[i].text in ("(", "[", "{"):
            depth += 1
        elif toks[i].text in (")", "]", "}"):
            if depth == 0:
                after = next((t for t in toks[i + 1 :] if t.kind != "nl"), None)
                return after is not None and after.text == "+"
            depth -= 1
    return False


def has_count(literal: str) -> bool:
    return COUNT.search(body(literal).replace("%%", "")) is not None


@dataclass
class Definition:
    """A function of the tree as the check sees it: where, and what it does with its words."""

    path: str
    translates: str = ""
    shows: frozenset[int] = frozenset()


@dataclass
class Index:
    """Every function of the tree that translates its parameter or shows it, and every class name.

    A call reaches its definition through here: the same file for a bare call,
    the named class for a qualified one, and for any other receiver only the
    answer every function of that name gives.
    """

    functions: dict[str, list[Definition]] = field(default_factory=dict)
    classes: dict[str, str] = field(default_factory=dict)
    constants: dict[str, dict[str, str]] = field(default_factory=dict)

    FUNC = re.compile(r"^(\s*)(?:static\s+)?func\s+(\w+)\s*\(([^)]*)\)")
    CLASS = re.compile(r"^\s*(?:class_name|class)\s+(\w+)")
    CONSTANT = re.compile(r"^\s*const\s+(\w+)\s*(?::\s*\w+\s*=|:=|=)\s*(\"[^\"\\\\]*(?:\\\\.[^\"\\\\]*)*\")\s*(?:#.*)?$")
    SHOWN = re.compile(r"(?:^\s*|\.|[:;]\s*)(?:%s)\s*\+?=\s*(\w+)\s*$" % "|".join(PROPERTIES))
    TRANSLATED = re.compile(r"\b(?:(?:TranslationServer\.)(translate(?:_plural)?)|(a?tr(?:_n)?))\(\s*(\w+)\s*[,)]")

    def read(self, path: str, source: str) -> None:
        """Add one file's functions and class names."""
        lines = source.splitlines()
        for number, text in enumerate(lines):
            named = self.CLASS.match(text)
            if named:
                self.classes.setdefault(named.group(1), path)
            held = self.CONSTANT.match(text)
            if held and has_words(held.group(2)) and not body(held.group(2)).startswith(ADDRESS):
                self.constants.setdefault(path, {})[held.group(1)] = held.group(2)
            found = self.FUNC.match(text)
            if not found:
                continue
            params = [p.split(":")[0].split("=")[0].strip() for p in found.group(3).split(",") if p.strip()]
            definition = Definition(path)
            shows: set[int] = set()
            for inner in self._body(lines, number, len(found.group(1))):
                code = inner.split("#")[0].rstrip()
                shown = self.SHOWN.search(code)
                if shown and shown.group(1) in params:
                    shows.add(params.index(shown.group(1)))
                said = self.TRANSLATED.search(code)
                if code.lstrip().startswith("return") and said and params and said.group(3) == params[0]:
                    name = said.group(1) or said.group(2)
                    definition.translates = ON_SERVER.get(name) or ON_ANY_OBJECT[name]
            definition.shows = frozenset(shows)
            self.functions.setdefault(found.group(2), []).append(definition)

    @staticmethod
    def _body(lines: list[str], start: int, indent: int) -> list[str]:
        out: list[str] = []
        for text in lines[start + 1 :]:
            stripped = text.strip()
            if stripped and not stripped.startswith("#") and len(text) - len(text.lstrip()) <= indent:
                break
            out.append(text)
        return out

    def constant(self, toks: list[Token], at: int, path: str) -> str | None:
        """The string the constant named at *at* holds, when the name stands alone as a value.

        A bare name is the file's own, a name after `Class.` is the class's. A
        name that is called, indexed or followed by a dot is something else.
        """
        after = toks[at + 1].text if at + 1 < len(toks) else ""
        if after in ("(", "[", ".", ":", "=") or not _is_value(toks, at):
            return None
        if at >= 1 and toks[at - 1].text == ".":
            owner = toks[at - 2].text if at >= 2 and toks[at - 2].kind == "id" else ""
            if at >= 3 and toks[at - 3].text == ".":
                return None
            where = self.classes.get(owner)
            return self.constants.get(where or "", {}).get(toks[at].text)
        return self.constants.get(path, {}).get(toks[at].text)


    def resolve(self, name: str, receiver: str | None, path: str) -> Definition | None:
        """What the call of *name* reaches, *receiver* being the word before its dot.

        None for a bare call, "?" for a receiver that is not a single word.
        """
        if receiver == "TranslationServer" and name in ON_SERVER:
            return Definition("", ON_SERVER[name])
        if name in ON_ANY_OBJECT and name not in self.functions:
            return Definition("", ON_ANY_OBJECT[name])
        known = self.functions.get(name, [])
        if receiver is None or receiver == "self":
            here = [d for d in known if d.path == path]
            return here[0] if here else None
        if receiver in self.classes:
            there = [d for d in known if d.path == self.classes[receiver]]
            return there[0] if there else None
        if known and all((d.translates, d.shows) == (known[0].translates, known[0].shows) for d in known):
            return known[0]
        return None


def _is_value(toks: list[Token], at: int) -> bool:
    """Whether the name at *at* stands as a value to be shown, not in a comparison or a test.

    What comes before it is an opening bracket, a comma, an assignment, a join,
    a format or an `else`, and what comes after it ends the value or goes on
    with a join, a format or an `if`. A name after a dot is read from its class.
    """
    start = at - 2 if at >= 1 and toks[at - 1].text == "." else at
    before = next((t for t in reversed(toks[:start]) if t.kind != "nl"), None)
    after = next((t for t in toks[at + 1 :] if t.kind != "nl"), None)
    opens = before is not None and before.text in ("(", ",", "=", "+=", "+", "%", "else", ":=", "[")
    closes = after is None or after.text in (")", ",", "+", "%", "if", "else", ";", "]")
    return opens and (closes or toks[at + 1].kind == "nl")


@dataclass
class Frame:
    """An open bracket, and for a call what its function does with each argument."""

    opener: str
    reaches: Definition | None = None
    argument: int = 0

    def is_group(self) -> bool:
        return self.opener == "(" and self.reaches is None and self.argument < 0


def hits_in(path: str, source: str, index: Index) -> list[Hit]:
    """Every word on screen in one file that skips the translation."""
    toks = tokens(source)
    declared = _declared(toks)
    found: list[Hit] = []
    stack: list[Frame] = []
    assigned_at: int | None = None
    assigned: str = ""
    params: set[str] = set()
    for at, tok in enumerate(toks):
        before = toks[at - 1] if at > 0 else None
        if tok.kind == "id" and tok.text == "func" and at + 2 < len(toks) and toks[at + 1].kind == "id":
            params = _params(toks, at + 2)
        if tok.kind == "op" and tok.text in ("(", "[", "{"):
            stack.append(_opened(toks, at, index, path))
            continue
        if tok.kind == "op" and tok.text in (")", "]", "}"):
            if stack:
                stack.pop()
            if assigned_at is not None and len(stack) < assigned_at:
                assigned_at = None
            continue
        if tok.kind == "op" and tok.text == "," and stack and stack[-1].argument >= 0:
            stack[-1].argument += 1
            continue
        if (tok.kind == "nl" or tok.text == ";") and assigned_at is not None and len(stack) <= assigned_at:
            assigned_at = None
            continue
        if tok.kind == "op" and tok.text in ("=", "+=") and _is_property(toks, at, declared | params):
            assigned_at = len(stack)
            assigned = toks[at - 1].text
            continue
        translating = [f for f in stack if f.reaches is not None and f.reaches.translates]
        if tok.kind == "id" and not translating and tok.text not in params:
            held = index.constant(toks, at, path)
            if held is not None:
                shows = assigned_at is not None and all(f.is_group() for f in stack[assigned_at:])
                if not shows:
                    call = next((d for d in range(len(stack) - 1, -1, -1) if not stack[d].is_group()), None)
                    frame = stack[call] if call is not None and all(f.is_group() for f in stack[call + 1 :]) else None
                    shows = frame is not None and frame.reaches is not None and frame.argument in frame.reaches.shows
                if shows:
                    found.append(Hit(path, tok.line, "const", held))
            continue
        if tok.kind != "str" or (before is not None and before.text in ("$", "%")):
            continue
        if translating:
            inner = stack[-1]
            singular = inner.reaches is not None and inner.reaches.translates == SINGULAR
            if singular and inner.argument == 0 and has_count(tok.text):
                found.append(Hit(path, tok.line, "count", tok.text))
            if ELLIPSIS in tok.text:
                found.append(Hit(path, tok.line, "ellipsis", tok.text))
            whole_tip = assigned == "tooltip_text" and assigned_at is not None and len(stack) > assigned_at
            whole_tip = whole_tip and all(f.is_group() for f in stack[assigned_at:-1])
            ends_tip = whole_tip and inner.argument == 0 and _alone(toks, at) and not _joined_after(toks, at)
            if ends_tip and not ends_a_sentence(tok.text):
                found.append(Hit(path, tok.line, "tooltip", tok.text))
            continue
        if not has_words(tok.text):
            continue
        if assigned_at is not None and all(f.is_group() for f in stack[assigned_at:]):
            found.append(Hit(path, tok.line, "bare", tok.text))
            continue
        call = next((d for d in range(len(stack) - 1, -1, -1) if not stack[d].is_group()), None)
        if call is None or not all(f.is_group() for f in stack[call + 1 :]):
            continue
        frame = stack[call]
        if frame.reaches is not None and frame.argument in frame.reaches.shows:
            found.append(Hit(path, tok.line, "built", tok.text))
    return found


def _opened(toks: list[Token], at: int, index: Index, path: str) -> Frame:
    """The frame the bracket at *at* opens: a call, a group, an index or a literal."""
    opener = toks[at].text
    before = toks[at - 1] if at > 0 else None
    if opener != "(":
        return Frame(opener, argument=-1)
    declaring = at >= 2 and toks[at - 2].text == "func"
    if before is None or before.kind != "id" or before.text in KEYWORDS or declaring:
        callee_less = before is not None and before.text in (")", "]")
        return Frame(opener, argument=0 if callee_less else -1)
    receiver: str | None = None
    if at >= 2 and toks[at - 2].text == ".":
        word = toks[at - 3] if at >= 3 else None
        lone = word is not None and word.kind == "id" and (at < 4 or toks[at - 4].text != ".")
        receiver = word.text if lone else "?"
    return Frame(opener, index.resolve(before.text, receiver, path), 0)


def _is_property(toks: list[Token], at: int, local: set[str]) -> bool:
    """Whether the `=` at *at* assigns one of the shown properties."""
    if at < 1 or toks[at - 1].kind != "id" or toks[at - 1].text not in PROPERTIES:
        return False
    name = toks[at - 1].text
    lead = toks[at - 2] if at >= 2 else None
    if lead is not None and lead.text == ".":
        return True
    starts = lead is None or lead.kind == "nl" or lead.text in (":", ";")
    return starts and name not in local


def _declared(toks: list[Token]) -> set[str]:
    """The names a file declares with `var`, which a bare assignment then means."""
    return {toks[i + 1].text for i, t in enumerate(toks[:-1]) if t.text == "var" and toks[i + 1].kind == "id"}


def _params(toks: list[Token], at: int) -> set[str]:
    """The parameter names of the function whose bracket is at *at*."""
    out: set[str] = set()
    if at >= len(toks) or toks[at].text != "(":
        return out
    depth = 0
    for i in range(at, len(toks)):
        t = toks[i]
        if t.text in ("(", "[", "{"):
            depth += 1
        elif t.text in (")", "]", "}"):
            depth -= 1
            if depth == 0:
                break
        elif depth == 1 and t.kind == "id" and toks[i - 1].text in ("(", ","):
            out.add(t.text)
    return out


def tracked_sources(root: Path) -> list[str]:
    """The files the check reads, relative to `sara-godot`, from git."""
    listed = subprocess.run(
        ["git", "ls-files", "--recurse-submodules"],
        cwd=root,
        capture_output=True,
        encoding="utf-8",
        check=True,
    ).stdout.splitlines()
    return sorted(p for p in listed if _read(p))


def folder_sources(root: Path) -> list[str]:
    """The files the check reads under a folder that is not a checkout, a fixture's."""
    return sorted(p for p in (f.relative_to(root).as_posix() for f in root.rglob("*.gd")) if _read(p))


def _read(path: str) -> bool:
    return path.endswith(".gd") and not any(part in LEFT_OUT for part in Path(path).parts)


def scan(root: Path, paths: list[str]) -> list[Hit]:
    """Every hit of every file, the index read from all of them first."""
    sources: dict[str, str] = {}
    for path in paths:
        file = root / path
        if file.is_file():
            sources[path] = file.read_text(encoding="utf-8", errors="replace")
    index = Index()
    for path, source in sources.items():
        index.read(path, source)
    found: list[Hit] = []
    for path, source in sources.items():
        found.extend(hits_in(path, source, index))
    return found


def read_list(file: Path) -> list[Key]:
    """The list's lines as keys, an absent file being an empty list."""
    if not file.is_file():
        return []
    out: list[Key] = []
    for line in file.read_text(encoding="utf-8").splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        path, form, text = line.split(" ", 2)
        out.append((path, form, text))
    return out


def write_list(file: Path, keys: list[Key]) -> None:
    file.write_text(HEAD + "".join(f"{p} {f} {t}\n" for p, f, t in sorted(keys)), encoding="utf-8")


def _module_absent(path: str, read: set[str]) -> bool:
    """A line under a module none of whose files was read, a submodule not checked out."""
    parts = Path(path).parts
    if len(parts) < 3 or parts[0] != "modules":
        return False
    folder = f"modules/{parts[1]}/"
    return not any(p.startswith(folder) for p in read)


def compare(found: list[Hit], listed: list[Key], read: set[str], name: str) -> tuple[list[str], list[Key]]:
    """The problems, and the lines of the list called *name* the tree no longer has."""
    allowed = Counter(listed)
    problems: list[str] = []
    for hit in sorted(found, key=lambda h: (h.path, h.line)):
        if allowed[hit.key()] > 0:
            allowed[hit.key()] -= 1
            continue
        problems.append(f"{hit.path}:{hit.line} [{hit.form}] {hit.text} is not on the list, {_advice(hit.form)}")
    stale = [key for key, left in allowed.items() for _ in range(left) if not _module_absent(key[0], read)]
    problems.extend(
        f"{name} names {p} [{f}] {t}, which the tree no longer has, delete the line or run --shrink"
        for p, f, t in stale
    )
    return problems, stale


def _advice(form: str) -> str:
    if form == "count":
        return "a count goes through tr_n() with the count, or the sentence loses the number"
    if form == "ellipsis":
        return 'a shown ellipsis is three dots, "...", never the one character'
    if form == "tooltip":
        return "a tooltip is a sentence that ends in a full stop"
    return "put it through tr()"


def main(argv: list[str]) -> int:
    root = SARA_GODOT
    list_file = LIST
    if "--root" in argv:
        root = Path(argv[argv.index("--root") + 1]).resolve()
    if "--list" in argv:
        list_file = Path(argv[argv.index("--list") + 1]).resolve()
    paths = folder_sources(root) if "--root" in argv else tracked_sources(root)
    found = scan(root, paths)
    listed = read_list(list_file)
    problems, stale = compare(found, listed, set(paths), list_file.name)
    if "--shrink" in argv:
        kept = Counter(listed)
        kept.subtract(Counter(stale))
        listed = sorted(kept.elements())
        write_list(list_file, listed)
        print(f"check_translated: {len(stale)} line(s) taken off {list_file.name}")
        problems, stale = compare(found, listed, set(paths), list_file.name)
    glued = _glued(argv)
    if problems:
        print("\n".join(problems))
        print("check_translated: a word on screen skips the translation")
        return 1
    print(f"check_translated: {len(found)} words on screen skip the translation, every one on the list")
    return glued


def _glued(argv: list[str]) -> int:
    """Run `check_glued_words.py` over the same tree, so the gate's one line reads both.

    Over a `--root` it runs only when `--glued-list` names the list to read, so
    a fixture made for this check alone is not read against the tree's list.
    """
    import check_glued_words

    if "--root" in argv and "--glued-list" not in argv:
        return 0
    passed = [a for a in argv if a == "--shrink"]
    if "--root" in argv:
        passed += ["--root", argv[argv.index("--root") + 1]]
    if "--glued-list" in argv:
        passed += ["--list", argv[argv.index("--glued-list") + 1]]
    return check_glued_words.main(passed)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
