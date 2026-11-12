#!/usr/bin/env python3
"""Write the translation template, the `.pot`, from the tree.

    cd sara-godot && python scripts/write_pot.py
    python scripts/write_pot.py --out translations/sara.pot --unread

The languages spec puts the string freeze at the cut of a release branch:
strings change freely on `dev`, never on a `release/` branch, and the template
is generated in the commit that cuts the branch. This is the script that commit
runs, the step the release model names. It is not on the gate, because a
template written on `dev` is out of date the next day.

It reads the `.gd` files git tracks under `sara-godot`, the modules' submodules
included, which covers `ui/`, `core/`, `render/`, `tools/` and the modules, and
leaves out every file under a `tests`, `harness` or `scripts` folder as
`check_translated.py` does: the capture harness's messages are the harness
talking to itself, and a suite or a script is never on screen. The lexer, the
folders left out and the index of the tree's own translating functions are
that check's, imported rather than written twice.

A translating call is `tr`, `atr`, `tr_n`, `atr_n`, `TranslationServer.translate`
and `translate_plural`, and every function of the tree whose `return` hands its
first parameter to one of them, `SaPage.translated` among them. Its message is
read where the tree spells it out:

  a literal          `tr("Open")`, and both arms of `tr("A" if x else "B")`
  a constant         `tr(SAVE_TITLE)`, a `const` of the same file, or
                     `tr(SaShiftPress.NO_STROKE_YET)` of the class or the
                     preloaded script the name before the dot stands for
  a collection       `tr(HINTS[kind])`, every string value of a constant
                     array or dictionary
  a field            `tr(spec.label)` or `tr(row["label"])`, every string the
                     read files assign to a field or a dictionary key of that
                     name, `command.label = "Clear Layer"` or `{"label": "Size"}`
  a parameter        `tr(title)` where `title` is a parameter of the function
                     around the call, read at every call of that function the
                     tree makes, through as many functions as hand it on
  a result           `tr(SaColorSpace.depth_name(depth))`, every string the
                     function's `return` statements spell out, and for
                     `tr(filter.title())` behind a receiver of no named class,
                     those of every function of that name in the tree
  a table's column   `tr(row[2])` or `descriptor.display_name = row[2]` in the
                     body of `for row in BLEND_MODES:`, the string in that
                     column of every row of the constant array, which is how
                     the skeleton names its blend modes

`String(...)` and `str(...)` around the message are read through, and so is a
concatenation of strings the source spells out. A plural call is one entry, its
message and its plural, and the context argument of the engine's own calls is
the entry's `msgctxt`. A string with no letter in it is left out, since it reads
the same in every language. Each entry carries the file and line of every place
its string stands, relative to `sara-godot`.

Godot translates a control's `text` and `tooltip_text` on its own, with no
context, so a label handed to one as a literal reaches the screen with no call
the reader could follow. Every literal that reads as a label is therefore an
entry under no context as well, read by `write_pot_labels.py`, which says what
reads as one. The `.pot` text is laid out by `write_pot_text.py`.

What the source does not spell out, a loop's variable over anything but a
constant, a value read from a setting or a sentence built at run time, is a
message no reader of the source can know. The script counts the calls and the
call sites that pass one and prints the count, and `--unread` prints each with
its file and line, so whoever cuts the branch sees what the template could not
hold.

The header's `Plural-Forms` is English's, the source language's, because Godot's
`.po` loader refuses a `msgid_plural` under the placeholder `xgettext` writes. A
catalogue made from the template sets its own language's rule.

`--root` reads every `.gd` under a folder instead of what git tracks, which is
how the suite runs it over a fixture, and `--out` names the file, `-` for
standard output. The default is `translations/sara.pot` under `sara-godot`.
Exits 0 when the template is written.
"""

from __future__ import annotations

import datetime
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

from check_translated import (
    KEYWORDS,
    PLURAL,
    SINGULAR,
    Index,
    Token,
    folder_sources,
    tokens,
    tracked_sources,
)
from write_pot_locals import read as read_local
from write_pot_kernels import kernel_sources, leading_sentences, uniform_titles
from write_pot_labels import label_literals
from write_pot_text import template

SARA_GODOT = Path(__file__).resolve().parent.parent
TEMPLATE = SARA_GODOT / "translations" / "sara.pot"

# The fields never read as a message. An `id` is what the code matches on, and a
# call that falls back to showing one, `String(descriptor.id)` for a layer kind
# with no name, would otherwise take every id of the tree into the template. It
# reads as nothing rather than as unread, since no catalogue translates an id.
NEVER_A_MESSAGE = frozenset({"id"})

# The calls that read their message through, the value inside them being the message.
READ_THROUGH = ("String", "str", "StringName")

FORMAT_CODE = re.compile(r"%[-+ 0#]*(?:\d+|\*)?(?:\.(?:\d+|\*))?[a-zA-Z%]")
BBCODE = re.compile(r"\[/?[a-z_]+(?:=[^\]]*)?\]")
ESCAPES = {"n": "\n", "t": "\t", "r": "\r", "a": "\a", "b": "\b", "f": "\f", "v": "\v"}



@dataclass(frozen=True)
class Place:
    """Where a string stands: the file under `sara-godot` and the line."""

    path: str
    line: int


@dataclass(frozen=True)
class Found:
    """A string the source spells out, and where."""

    text: str
    place: Place


@dataclass
class Entry:
    """One message of the template, its plural when it has one, and every place it stands."""

    context: str
    message: str
    plural: str = ""
    places: set[Place] = field(default_factory=set)

    def hold(self, place: Place, plural: str) -> bool:
        """Add a place, and the plural when there is none yet, false when the entry has another."""
        self.places.add(place)
        if plural and self.plural and self.plural != plural:
            return False
        self.plural = plural or self.plural
        return True

    def first(self) -> tuple[str, int]:
        place = min(self.places, key=lambda p: (p.path, p.line))
        return (place.path, place.line)


@dataclass
class Reading:
    """What one translating call's message resolved to.

    *strings* are what the source spells out. *fields* are the names read as
    `x.name`, whose strings are whatever the tree assigns to a field or a
    dictionary key of that name, and *keys* the names read as `x["name"]`, a
    dictionary's only, so a node's `.name` is never a message. *read* is false
    when part of the message is not in the source at all.
    """

    strings: list[Found] = field(default_factory=list)
    fields: set[str] = field(default_factory=set)
    keys: set[str] = field(default_factory=set)
    read: bool = True

    def add(self, other: Reading) -> None:
        self.strings.extend(other.strings)
        self.fields |= other.fields
        self.keys |= other.keys
        self.read = self.read and other.read

    def named(self) -> bool:
        return bool(self.fields or self.keys)


UNREAD = Reading(read=False)


@dataclass(frozen=True)
class Loop:
    """A `for`: its variable, the first and last line of its body, and the tokens of what it runs over."""

    name: str
    first: int
    last: int
    over: tuple[Token, ...]


@dataclass
class Source:
    """One file as the template reads it: its tokens, constants, preloaded scripts, loops and what each function returns."""

    path: str
    toks: list[Token]
    consts: dict[str, list[Token]] = field(default_factory=dict)
    aliases: dict[str, str] = field(default_factory=dict)
    returns: dict[str, list[list[Token]]] = field(default_factory=dict)
    loops: list[Loop] = field(default_factory=list)

    @classmethod
    def of(cls, path: str, text: str) -> Source:
        made = cls(path, tokens(text))
        made._read_consts()
        made._read_returns()
        made._read_loops(text.split("\n"))
        return made

    def looped(self, name: str, line: int) -> tuple[Token, ...] | None:
        """What the innermost `for` of *name* whose body holds *line* runs over, or None."""
        holding = [loop for loop in self.loops if loop.name == name and loop.first <= line <= loop.last]
        return max(holding, key=lambda loop: loop.first).over if holding else None

    def _read_loops(self, lines: list[str]) -> None:
        """Every `for` and its body, the lines after it indented deeper than its own, blank and comment lines kept."""
        toks = self.toks
        for at, tok in enumerate(toks[:-2]):
            if tok.text != "for" or tok.kind != "id" or toks[at + 1].kind != "id":
                continue
            head = statement(toks, at + 2)
            words = [t.text for t in head]
            if "in" not in words:
                continue
            over = head[words.index("in") + 1 :]
            over = over[: [t.text for t in over].index(":")] if ":" in [t.text for t in over] else over
            last = tok.line
            for number in range(tok.line + 1, len(lines) + 1):
                text = lines[number - 1]
                if text.strip() and not text.strip().startswith("#"):
                    if _indent(text) <= _indent(lines[tok.line - 1]):
                        break
                    last = number
            self.loops.append(Loop(toks[at + 1].text, tok.line, last, tuple(over)))

    def _read_returns(self) -> None:
        toks = self.toks
        function = ""
        for at, tok in enumerate(toks[:-2]):
            if tok.text == "func" and toks[at + 1].kind == "id" and toks[at + 2].text == "(":
                function = toks[at + 1].text
                self.returns.setdefault(function, [])
            elif tok.text == "return" and tok.kind == "id" and function:
                value = statement(toks, at + 1)
                if value:
                    self.returns[function].append(value)

    def _read_consts(self) -> None:
        toks = self.toks
        for at, tok in enumerate(toks[:-1]):
            if tok.text != "const" or toks[at + 1].kind != "id":
                continue
            start = _after_assignment(toks, at + 2)
            if start is None:
                continue
            value = statement(toks, start)
            self.consts.setdefault(toks[at + 1].text, value)
            loaded = _preloaded(value)
            if loaded:
                self.aliases[toks[at + 1].text] = loaded


def _indent(line: str) -> int:
    return len(line) - len(line.lstrip(" \t"))


def _after_assignment(toks: list[Token], at: int) -> int | None:
    """The token after the `=` or `:=` of a declaration whose name ends before *at*."""
    while at < len(toks) and toks[at].kind != "nl":
        if toks[at].text in ("=", ":="):
            return at + 1
        at += 1
    return None


def _preloaded(value: list[Token]) -> str:
    """The file a `preload("res://...")` value names, relative to `sara-godot`, or empty."""
    texts = [t.text for t in value]
    if len(texts) == 4 and texts[0] in ("preload", "load") and texts[1] == "(" and texts[3] == ")":
        named = literal(value[2].text)
        if named.startswith("res://"):
            return named[len("res://") :]
    return ""


def statement(toks: list[Token], start: int) -> list[Token]:
    """The tokens from *start* to the end of their statement, line ends inside brackets dropped."""
    out: list[Token] = []
    depth = 0
    for tok in toks[start:]:
        if tok.text in ("(", "[", "{"):
            depth += 1
        elif tok.text in (")", "]", "}"):
            depth -= 1
            if depth < 0:
                break
        elif depth == 0 and (tok.kind == "nl" or tok.text == ";"):
            break
        elif depth == 0 and tok.text == "," and out:
            break
        if tok.kind != "nl":
            out.append(tok)
    return out


def literal(text: str) -> str:
    """The value of a GDScript string literal, its prefix, quotes and escapes undone."""
    raw = "r" in text[:3].split('"')[0].split("'")[0]
    rest = text.lstrip("&^r")
    width = 3 if rest.startswith(('"""', "'''")) else 1
    inner = rest[width:-width] if len(rest) >= 2 * width else rest[width:]
    if raw:
        return inner
    out: list[str] = []
    i = 0
    while i < len(inner):
        c = inner[i]
        if c != "\\" or i + 1 >= len(inner):
            out.append(c)
            i += 1
            continue
        n = inner[i + 1]
        if n in ESCAPES:
            out.append(ESCAPES[n])
            i += 2
        elif n in "uU":
            width = 4 if n == "u" else 6
            digits = inner[i + 2 : i + 2 + width]
            out.append(chr(int(digits, 16)) if re.fullmatch(r"[0-9a-fA-F]+", digits or "x") else n)
            i += 2 + width
        elif n == "\n":
            i += 2
        else:
            out.append(n)
            i += 2
    return "".join(out)


def has_letter(text: str) -> bool:
    """Whether a message carries a letter once its format codes and tags are out."""
    return any(c.isalpha() for c in BBCODE.sub("", FORMAT_CODE.sub("", text)))


def matching(toks: list[Token], at: int) -> int:
    """The index of the bracket that closes the one at *at*, or the last token."""
    depth = 0
    for i in range(at, len(toks)):
        if toks[i].text in ("(", "[", "{"):
            depth += 1
        elif toks[i].text in (")", "]", "}"):
            depth -= 1
            if depth == 0:
                return i
    return len(toks) - 1


def arguments(toks: list[Token], opener: int) -> list[list[Token]]:
    """The arguments of the call whose bracket is at *opener*, line ends dropped."""
    out: list[list[Token]] = [[]]
    depth = 0
    for tok in toks[opener + 1 : matching(toks, opener)]:
        if tok.text in ("(", "[", "{"):
            depth += 1
        elif tok.text in (")", "]", "}"):
            depth -= 1
        elif tok.text == "," and depth == 0:
            out.append([])
            continue
        if tok.kind != "nl":
            out[-1].append(tok)
    return [a for a in out if a] if out != [[]] else []


@dataclass
class Call:
    """One call: its file and line, its argument tokens, and the function it stands in.

    *plural* and *engine* say what a translating call takes, and *function* and
    *params* are the named function around it, whose parameters a message can be.
    """

    path: str
    line: int
    args: list[list[Token]]
    function: str = ""
    params: list[str] = field(default_factory=list)
    plural: bool = False
    engine: bool = False

    def text(self) -> str:
        return ", ".join(" ".join(t.text for t in a) for a in self.args)


@dataclass(frozen=True)
class Opening:
    """A bracket that opens a call, the name called, the word before its dot, and the function around it."""

    at: int
    name: str
    receiver: str | None
    function: str
    params: tuple[str, ...]


# A function of the tree as `path` and name, the key a handed parameter is filed under.
Function = tuple[str, str]


class Tree:
    """The read files, and every message their translating calls pass."""

    def __init__(self, sources: dict[str, str], kernels: dict[str, str] | None = None):
        self.kernels = kernels or {}
        self.index = Index()
        for path, text in sources.items():
            self.index.read(path, text)
        self.files = {path: Source.of(path, text) for path, text in sources.items()}
        self.entries: dict[tuple[str, str], Entry] = {}
        self.unread: list[Call] = []
        self.calls = 0
        self.clashes: list[str] = []

    def read(self) -> None:
        """Every call of every file, the callers of each parameter handed on, then the fields named."""
        named = Reading()
        handed: dict[Function, set[int]] = {}
        waiting: list[tuple[Call, Function]] = []
        for source in self.files.values():
            for call in self._calls(source):
                self.calls += 1
                position = self._handed(call, source)
                if position is None:
                    named.add(self._take(call, source))
                    continue
                handed.setdefault((call.path, call.function), set()).add(position)
                waiting.append((call, (call.path, call.function)))
        called = self._follow(handed, named)
        self.unread.extend(call for call, function in waiting if function not in called)
        for source in self.files.values():
            for found in self._assigned(source, named.fields, named.keys):
                self._add("", found, "")
        for title, path, line in uniform_titles(self.kernels):
            self._add("", Found(title, Place(path, line)), "")
        for sentence, path, line in leading_sentences(self.kernels):
            self._add("", Found(sentence, Place(path, line)), "")
        plurals = {entry.plural for entry in self.entries.values()}
        files = {path: source.toks for path, source in self.files.items()}
        for text, path, line in label_literals(files, literal):
            if text not in plurals:
                self._add("", Found(text, Place(path, line)), "")

    def _openings(self, source: Source) -> list[Opening]:
        """Every bracket of *source* that opens a call, with the named function it stands in."""
        toks = source.toks
        out: list[Opening] = []
        function = ""
        params: tuple[str, ...] = ()
        for at, tok in enumerate(toks):
            if tok.text != "(" or at == 0 or toks[at - 1].kind != "id":
                continue
            name = toks[at - 1].text
            if at >= 2 and toks[at - 2].text == "func":
                function = name
                params = tuple(a[0].text for a in arguments(toks, at) if a[0].kind == "id")
                continue
            if name in KEYWORDS:
                continue
            receiver: str | None = None
            if at >= 2 and toks[at - 2].text == ".":
                word = toks[at - 3] if at >= 3 else None
                lone = word is not None and word.kind == "id" and (at < 4 or toks[at - 4].text != ".")
                receiver = word.text if lone else "?"
            out.append(Opening(at, name, receiver, function, params))
        return out

    def _calls(self, source: Source) -> list[Call]:
        """Every translating call of *source*, but the one a translating function hands its parameter.

        That call's messages are its callers', which the index already makes
        translating calls of their own.
        """
        out: list[Call] = []
        for opening in self._openings(source):
            reaches = self.index.resolve(opening.name, opening.receiver, source.path)
            if reaches is None or not reaches.translates:
                continue
            args = arguments(source.toks, opening.at)
            own = self.index.resolve(opening.function, None, source.path) if opening.function else None
            wraps = own is not None and own.translates and opening.params
            if wraps and args and [t.text for t in args[0]] == [opening.params[0]]:
                continue
            line = source.toks[opening.at].line
            plural = reaches.translates == PLURAL
            made = Call(source.path, line, args, opening.function, list(opening.params), plural, reaches.path == "")
            out.append(made)
        return out

    def _handed(self, call: Call, source: Source) -> int | None:
        """The position of the parameter a singular call's message is, when it is one."""
        if call.plural or not call.args:
            return None
        message = _unwrapped(call.args[0])
        if len(message) != 1 or message[0].kind != "id" or message[0].text not in call.params:
            return None
        if message[0].text in source.consts:
            return None
        return call.params.index(message[0].text)

    def _follow(self, handed: dict[Function, set[int]], named: Reading) -> set[Function]:
        """Read the messages the callers of each function in *handed* pass, and return the functions called.

        A caller that hands on a parameter of its own adds its function, so a
        message passed through two functions is still read where it is written.
        """
        called: set[Function] = set()
        done: set[tuple[str, int, int]] = set()
        grew = True
        while grew:
            grew = False
            names = {name for _, name in handed}
            for source in self.files.values():
                for opening in self._openings(source):
                    if opening.name not in names:
                        continue
                    target = self._target(opening, source, handed)
                    if target is None:
                        continue
                    called.add(target)
                    args = arguments(source.toks, opening.at)
                    line = source.toks[opening.at].line
                    for position in sorted(handed[target]):
                        if (source.path, opening.at, position) in done or position >= len(args):
                            continue
                        done.add((source.path, opening.at, position))
                        site = Call(source.path, line, [args[position]], opening.function, list(opening.params))
                        self.calls += 1
                        passed = self._handed(site, source)
                        if passed is not None:
                            function = (source.path, opening.function)
                            if passed not in handed.setdefault(function, set()):
                                handed[function].add(passed)
                                grew = True
                            continue
                        reading = self.resolve(args[position], source, set())
                        if not reading.read:
                            self.unread.append(site)
                        for found in reading.strings:
                            self._add("", found, "")
                        named.add(Reading(fields=reading.fields, keys=reading.keys))
        return called

    def _target(self, opening: Opening, source: Source, handed: dict[Function, set[int]]) -> Function | None:
        """The function of *handed* a call reaches: its own file's, its qualifier's, or the only one of its name."""
        if opening.receiver in (None, "self"):
            here = (source.path, opening.name)
            return here if here in handed else None
        path = source.aliases.get(opening.receiver or "") or self.index.classes.get(opening.receiver or "")
        if path:
            there = (path, opening.name)
            return there if there in handed else None
        known = {d.path for d in self.index.functions.get(opening.name, [])}
        if len(known) == 1:
            only = (known.pop(), opening.name)
            return only if only in handed else None
        return None

    def _take(self, call: Call, source: Source) -> Reading:
        """Add the call's entries and return the field and key names its message is read from."""
        want = 2 if call.plural else 1
        if len(call.args) < want:
            self.unread.append(call)
            return Reading()
        readings = [self.resolve(call.args[i], source, set()) for i in range(want)]
        context = ""
        where = 3 if call.plural else 1
        if call.engine and len(call.args) > where:
            said = self.resolve(call.args[where], source, set())
            if not said.read or said.named() or len({f.text for f in said.strings}) != 1:
                self.unread.append(call)
                return Reading()
            context = said.strings[0].text
        if call.plural:
            message, plural = readings
            if not (message.read and plural.read) or message.named() or plural.named():
                self.unread.append(call)
                return Reading()
            if len(message.strings) != 1 or len(plural.strings) != 1:
                self.unread.append(call)
                return Reading()
            self._add(context, message.strings[0], plural.strings[0].text)
            return Reading()
        reading = readings[0]
        if not reading.read:
            self.unread.append(call)
        for found in reading.strings:
            self._add(context, found, "")
        return Reading(fields=reading.fields, keys=reading.keys)

    def _add(self, context: str, found: Found, plural: str) -> None:
        if not has_letter(found.text):
            return
        key = (context, found.text)
        entry = self.entries.setdefault(key, Entry(context, found.text))
        if not entry.hold(found.place, plural):
            self.clashes.append(f"{found.place.path}:{found.place.line}: {found.text!r} has two plurals")

    def resolve(self, span: list[Token], source: Source, seen: set[tuple[str, str]]) -> Reading:
        """What the message *span* of *source* is, as far as the source spells it out."""
        span = _unwrapped(span)
        if not span:
            return UNREAD
        arms = _arms(span)
        if arms:
            out = Reading()
            for arm in arms:
                out.add(self.resolve(arm, source, seen))
            return out
        parts = _split(span, "+")
        if len(parts) > 1:
            return self._joined(parts, source, seen)
        texts = [t.text for t in span]
        if len(span) == 1 and span[0].kind == "str":
            if span[0].text.startswith("^"):
                return UNREAD
            return Reading([Found(literal(span[0].text), Place(source.path, span[0].line))])
        named = self._constant(span, source)
        if named is not None:
            where, name, rest = named
            key = (where.path, name)
            if key in seen:
                return UNREAD
            if not rest:
                return self.resolve(where.consts[name], where, seen | {key})
            if rest[0] == "[" and texts[-1] == "]" or rest[:2] == [".", "get"]:
                return _collection(*self._followed(where, name))
            return UNREAD
        column = self._column(span, source, seen)
        if column is not None:
            return column
        if len(span) >= 2 and texts[-2] == "." and span[-1].kind == "id":
            return Reading() if texts[-1] in NEVER_A_MESSAGE else Reading(fields={texts[-1]})
        if len(span) >= 3 and texts[-1] == "]" and span[-2].kind == "str" and texts[-3] == "[":
            key = literal(texts[-2])
            return Reading() if key in NEVER_A_MESSAGE else Reading(keys={key})
        keyed = _got(span)
        if keyed:
            return Reading() if keyed in NEVER_A_MESSAGE else Reading(keys={keyed})
        returned = self._returned(span, source, seen) or read_local(self, span, source, seen, statement)
        return UNREAD if returned is None else returned

    def _returned(self, span: list[Token], source: Source, seen: set[tuple[str, str]]) -> Reading | None:
        """What a message that is a call returns, or None when the span is no call of the tree.

        A translating call is read through to its message. Any other function
        is the one of its own file, of its qualifier's class or preloaded script,
        and behind any other receiver every function of that name, so
        `filter.title()` reads the title every filter returns.
        """
        if span[-1].text != ")":
            return None
        opener = _opener_of_last(span)
        if opener < 1 or span[opener - 1].kind != "id":
            return None
        name = span[opener - 1].text
        head = [t.text for t in span[: opener - 1]]
        if not head or head == ["self", "."]:
            receiver: str | None = None
        elif len(head) == 2 and head[1] == "." and span[0].kind == "id":
            receiver = head[0]
        elif head[-1] == ".":
            receiver = "?"
        else:
            return None
        reaches = self.index.resolve(name, receiver, source.path)
        if reaches is not None and reaches.translates == SINGULAR:
            args = arguments(span, opener)
            return self.resolve(args[0], source, seen) if args else UNREAD
        if receiver is None:
            targets = [source] if name in source.returns else []
        else:
            path = source.aliases.get(receiver) or self.index.classes.get(receiver)
            if path:
                there = self.files.get(path)
                targets = [there] if there is not None and name in there.returns else []
            else:
                targets = [f for f in self.files.values() if name in f.returns]
        if not targets:
            return None
        out = Reading()
        for where in targets:
            key = (where.path, name + "()")
            if key in seen:
                continue
            for value in where.returns[name]:
                out.add(self.resolve(value, where, seen | {key}))
        return out

    def _column(self, span: list[Token], source: Source, seen: set[tuple[str, str]]) -> Reading | None:
        """Every row's cell of a column `row[2]` reads, when `row` is a loop's over a constant array of arrays.

        None when *span* is no such read, so the message is read on as before.
        """
        texts = [t.text for t in span]
        if len(span) != 4 or span[0].kind != "id" or texts[1] != "[" or not texts[2].isdigit() or texts[3] != "]":
            return None
        over = source.looped(texts[0], span[0].line)
        named = self._constant(list(over), source) if over else None
        if named is None or named[2]:
            return None
        table, where = self._followed(named[0], named[1])
        key = (where.path, named[1] + "[]")
        if not table or table[0].text != "[" or key in seen:
            return None
        out = Reading()
        for row in map(_unwrapped, arguments(table, 0)):
            cells = arguments(row, 0) if row and row[0].text == "[" and matching(row, 0) == len(row) - 1 else []
            if int(texts[2]) < len(cells):
                out.add(self.resolve(cells[int(texts[2])], where, seen | {key}))
            else:
                out.read = False
        return out

    def _joined(self, parts: list[list[Token]], source: Source, seen: set[tuple[str, str]]) -> Reading:
        """The one string a concatenation of strings the source spells out makes."""
        pieces: list[Found] = []
        for part in parts:
            reading = self.resolve(part, source, seen)
            if not reading.read or reading.named() or len(reading.strings) != 1:
                return UNREAD
            pieces.append(reading.strings[0])
        return Reading([Found("".join(p.text for p in pieces), pieces[0].place)])

    def _followed(self, where: Source, name: str) -> tuple[list[Token], Source]:
        """The value of a constant, through every constant it names, `const A := B.C` and on."""
        seen: set[tuple[str, str]] = set()
        while (where.path, name) not in seen:
            seen.add((where.path, name))
            value = where.consts[name]
            named = self._constant(value, where) if value else None
            if named is None or named[2]:
                return value, where
            where, name = named[0], named[1]
        return [], where

    def _constant(self, span: list[Token], source: Source) -> tuple[Source, str, list[str]] | None:
        """The file and name of the constant *span* starts with, and the tokens after it."""
        texts = [t.text for t in span]
        if span[0].kind != "id":
            return None
        if texts[0] in source.consts and texts[0] not in source.aliases:
            return (source, texts[0], texts[1:])
        if len(texts) >= 3 and texts[1] == "." and span[2].kind == "id":
            path = source.aliases.get(texts[0]) or self.index.classes.get(texts[0])
            where = self.files.get(path or "")
            if where is not None and texts[2] in where.consts:
                return (where, texts[2], texts[3:])
        return None

    def _assigned(self, source: Source, fields: set[str], keys: set[str]) -> list[Found]:
        """Every string *source* assigns to one of *fields* or *keys*.

        A field takes `x.name = ...` and a dictionary's `name` key, a key only
        the dictionary's: `{"name": ...}`, `{name = ...}` and `x["name"] = ...`.
        """
        either = fields | keys
        toks = source.toks
        out: list[Found] = []
        for at, tok in enumerate(toks[:-1]):
            after = toks[at + 1].text
            before = toks[at - 1].text if at > 0 else ""
            start: int | None = None
            if tok.kind == "id" and after == "=" and before == "." and tok.text in fields:
                start = at + 2
            elif tok.kind == "id" and after == "=" and before in ("{", ",") and tok.text in either:
                start = at + 2 if _inside_brace(toks, at) else None
            elif tok.kind == "str" and not tok.text.startswith("^") and literal(tok.text) in either:
                if after == ":" and _inside_brace(toks, at):
                    start = at + 2
                elif before == "[" and after == "]" and at + 2 < len(toks) and toks[at + 2].text == "=":
                    start = at + 3
            if start is None:
                continue
            reading = self.resolve(statement(toks, start), source, set())
            out.extend(reading.strings)
        return out

    def template(self, version: str, now: datetime.datetime) -> str:
        """The `.pot` text of every entry read, as `write_pot_text.py` lays it out."""
        return template(list(self.entries.values()), version, now)



def _unwrapped(span: list[Token]) -> list[Token]:
    """*span* with every `String(...)`, `str(...)` and bracket around the whole of it taken off."""
    while span:
        texts = [t.text for t in span]
        if texts[0] == "(" and matching(span, 0) == len(span) - 1:
            span = span[1:-1]
        elif len(span) > 2 and texts[0] in READ_THROUGH and texts[1] == "(" and matching(span, 1) == len(span) - 1:
            span = span[2:-1]
        else:
            return span
    return span


def _arms(span: list[Token]) -> list[list[Token]]:
    """The two values of a span that is one `A if condition else B`, or nothing."""
    depth = 0
    cut_if = cut_else = -1
    for i, tok in enumerate(span):
        if tok.text in ("(", "[", "{"):
            depth += 1
        elif tok.text in (")", "]", "}"):
            depth -= 1
        elif depth == 0 and tok.text == "if" and cut_if < 0:
            cut_if = i
        elif depth == 0 and tok.text == "else" and cut_if >= 0:
            cut_else = i
            break
    if cut_if <= 0 or cut_else < 0:
        return []
    return [span[:cut_if], span[cut_else + 1 :]]


def _opener_of_last(span: list[Token]) -> int:
    """The index of the bracket the last token of *span* closes, or -1."""
    depth = 0
    for i in range(len(span) - 1, -1, -1):
        if span[i].text in (")", "]", "}"):
            depth += 1
        elif span[i].text in ("(", "[", "{"):
            depth -= 1
            if depth == 0:
                return i
    return -1


def _split(span: list[Token], operator: str) -> list[list[Token]]:
    """*span* cut at every *operator* outside its brackets."""
    out: list[list[Token]] = [[]]
    depth = 0
    for tok in span:
        if tok.text in ("(", "[", "{"):
            depth += 1
        elif tok.text in (")", "]", "}"):
            depth -= 1
        elif depth == 0 and tok.text == operator and tok.kind == "op":
            out.append([])
            continue
        out[-1].append(tok)
    return out


def _got(span: list[Token]) -> str:
    """The key of a span ending `.get("key")` or `.get("key", default)`, or empty."""
    texts = [t.text for t in span]
    if texts[-1] != ")" or "get" not in texts:
        return ""
    at = len(texts) - 1 - texts[::-1].index("get")
    opener = at + 1
    if at < 1 or texts[at - 1] != "." or opener >= len(span) or texts[opener] != "(":
        return ""
    if matching(span, opener) != len(span) - 1:
        return ""
    args = arguments(span, opener)
    if args and len(args[0]) == 1 and args[0][0].kind == "str":
        return literal(args[0][0].text)
    return ""


def _collection(value: list[Token], where: Source) -> Reading:
    """Every string value one level inside a constant array or dictionary."""
    if not value or value[0].text not in ("[", "{"):
        return UNREAD
    out = Reading()
    for item in arguments(value, 0):
        texts = [t.text for t in item]
        if ":" in texts and value[0].text == "{":
            item = item[texts.index(":") + 1 :]
        elif len(texts) > 2 and texts[1] == "=" and value[0].text == "{":
            item = item[2:]
        item = _unwrapped(item)
        for arm in _arms(item) or [item]:
            if len(arm) == 1 and arm[0].kind == "str" and not arm[0].text.startswith("^"):
                out.strings.append(Found(literal(arm[0].text), Place(where.path, arm[0].line)))
            elif _spelt_out(arm):
                text = "".join(literal(t.text) for t in arm if t.kind == "str")
                out.strings.append(Found(text, Place(where.path, arm[0].line)))
    return out


def _spelt_out(span: list[Token]) -> bool:
    """Whether *span* is two or more string literals joined by `+`, a sentence cut across lines."""
    if len(span) < 3 or len(span) % 2 == 0:
        return False
    strings = all(t.kind == "str" and not t.text.startswith("^") for t in span[0::2])
    return strings and all(t.text == "+" for t in span[1::2])


def _inside_brace(toks: list[Token], at: int) -> bool:
    """Whether the innermost bracket open at *at* is a dictionary's `{`."""
    depth = 0
    for i in range(at - 1, -1, -1):
        text = toks[i].text
        if text in (")", "]", "}"):
            depth += 1
        elif text in ("(", "[", "{"):
            if depth == 0:
                return text == "{"
            depth -= 1
    return False


def version_of(root: Path) -> str:
    """The version `project.godot` declares under *root*, or `unknown`."""
    project = root / "project.godot"
    if project.is_file():
        found = re.search(r'^config/version="([^"]*)"', project.read_text(encoding="utf-8"), re.M)
        if found:
            return found.group(1)
    return "unknown"


def main(argv: list[str]) -> int:
    root = SARA_GODOT
    out = TEMPLATE
    if "--root" in argv:
        root = Path(argv[argv.index("--root") + 1]).resolve()
    if "--out" in argv:
        named = argv[argv.index("--out") + 1]
        out = Path("-") if named == "-" else Path(named).resolve()
    paths = folder_sources(root) if "--root" in argv else tracked_sources(root)
    sources: dict[str, str] = {}
    for path in paths:
        file = root / path
        if file.is_file():
            sources[path] = file.read_text(encoding="utf-8", errors="replace")
    tree = Tree(sources, kernel_sources(root, "--root" not in argv))
    tree.read()
    text = tree.template(version_of(root), datetime.datetime.now(datetime.timezone.utc))
    if str(out) == "-":
        sys.stdout.write(text)
    else:
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(text, encoding="utf-8", newline="\n")
    report = sys.stderr if str(out) == "-" else sys.stdout
    if "--unread" in argv:
        for call in sorted(tree.unread, key=lambda c: (c.path, c.line)):
            print(f"{call.path}:{call.line}: unread ({call.text()})", file=report)
    for clash in tree.clashes:
        print(clash, file=report)
    where = "standard output" if str(out) == "-" else out
    print(
        f"write_pot: {len(tree.entries)} messages from {len(sources)} files to {where}, "
        f"{tree.calls - len(tree.unread)} of {tree.calls} calls read, "
        f"{len(tree.unread)} pass a message the source does not spell out (--unread names them)",
        file=report,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
