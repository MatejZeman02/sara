"""The template writer's reading of a bare name.

`write_pot.py` reads a message the source spells out at the call, in a
constant, a field, a parameter, a result or a table's column. This file teaches
it the shapes a name takes besides:

  a local            `var line := "..."` and `tr(line)` below it, every value
                     the function assigns to the name, `var`, `=` and both
                     arms of an `if`, read as a message is
  a local's item     `var why := _refusal(layer)` and `tr(str(why[0]))`, the
                     item of every array the value is, or every array the
                     function it calls returns, an empty one adding nothing
  a loop's variable  `for title in TITLES:`, the elements of an array, the
                     keys of a dictionary, `.keys()`, `.values()`, a local, a
                     member, a copy `PackedStringArray(x)`, or a parameter
  a member           every value the file gives it and every element it
                     appends, `append`, `push_back` and an `append_array` of a
                     literal, with a window's own `title` among them
  an inherited name  a constant or a member of a class the file extends
  a constant table   `LABELS[kind]` and `A.Inner.LABELS[kind]`, every value,
                     and `TABLE.get(key, otherwise)` the fallback as well
  a parameter        what every call passes, when the parameter is the
                     message itself: the calls in its own file, every call of
                     a function one file alone defines, and every
                     `Class.new()` of the tree for a constructor's

A local read from a `name`, a node's or a layer's, is a name and never a
message. A `Vector2(...)` and the engine's other values are never words, and a
sentence already passed through `tr()` and filled in adds no message. A value
the source does not spell out leaves the call unread, as any other message
does.

It is its own file because the writer stands near a thousand lines, and the
writer asks it once, in `Tree.resolve`.
"""

from __future__ import annotations

import dataclasses
from typing import Any, Callable

from check_translated import Token

# A local holding a node's or a layer's `name` is a name, never a message, and
# reading it as a field would take every node name the tree sets into the template.
NODE_NAME = "name"

# The item a read such as `labels[i]` takes, any of them.
ANY = -2

Statement = Callable[[list[Token], int], list[Token]]


# The engine's values that are never words, `Vector2(x, y)` handed to
# `Transform2D.translated`, which shares its name with `SaPage.translated`.
NOT_WORDS = ("Vector2", "Vector2i", "Rect2", "Rect2i", "Transform2D", "Color")

# The engine's members that hold words, read as a member the file sets.
ENGINE_WORDS = ("title",)

# A value that is a translated sentence filled in, `tr("Apply %s Again") % x`,
# was read at its own call, and handing it on to another adds no message.

# The calls that copy an array into another kind of array, keeping its elements.
COPIES = ("Array", "PackedStringArray")


def read(tree: Any, span: list[Token], source: Any, seen: set[tuple[str, str]], statement: Statement) -> Any | None:
    """What the local *span* names reads as, or None when *span* is no local of its function.

    *statement* is the writer's own cut of a statement from its first token,
    handed in so the two files cut a value the same way.
    """
    texts = [t.text for t in span]
    if not span or span[0].kind != "id":
        return None
    if texts[0] in NOT_WORDS and len(span) > 2 and texts[1] == "(" and _closes(span, 1) == len(span) - 1:
        return _nothing(tree)
    if texts[0] == "tr" and len(span) > 2 and texts[1] == "(" and texts[_closes(span, 1) + 1 : _closes(span, 1) + 2] == ["%"]:
        return _nothing(tree)
    item = -1
    head = _dotted(span)
    if head > 1 and len(span) > head + 2 and texts[head] == "[" and _closes(span, head) == len(span) - 1:
        values = _elements(tree, span[:head], source, statement, 0, _key_text(span[head + 1 : -1], source) or True)
        return None if values is None else _resolved(tree, values, span, source, seen)
    if len(span) == 4 and texts[1] == "[" and texts[2].isdigit() and texts[3] == "]":
        item = int(texts[2])
    elif len(span) > 3 and texts[1] == "[" and texts[-1] == "]" and _closes(span, 1) == len(span) - 1:
        item = ANY
    elif len(span) != 1:
        return None
    if _assigned_from(source.toks, span[0]):
        return None
    direct = all(key[1][:1].isdigit() for key in seen)
    spans = _named(tree, span[0], source, item, statement, span[2:-1], direct)
    return None if spans is None else _resolved(tree, spans, span, source, seen)


def _nothing(tree: Any) -> Any:
    """A reading of no message at all, built from the writer's own `Reading`.

    The writer runs as `__main__`, so its class is found through the tree
    rather than imported, which would load the writer a second time.
    """
    return type(tree).resolve.__globals__["Reading"]()


def _dotted(span: list[Token]) -> int:
    """How many tokens a dotted name `A.B.C` at the start of *span* takes."""
    at = 1 if span and span[0].kind == "id" else 0
    while at + 1 < len(span) and span[at].text == "." and span[at + 1].kind == "id":
        at += 2
    return at


def _resolved(
    tree: Any, spans: list[tuple[list[Token], Any]], span: list[Token], source: Any, seen: set[tuple[str, str]]
) -> Any | None:
    """The values *spans* hold read as one, or None when one of them names a node."""
    texts = [t.text for t in span]
    key = (source.path, f"{span[0].line}:{texts[0]}")
    if key in seen:
        return None
    seen = seen | {key}
    out = None
    for part, where in spans:
        reading = tree.resolve(part, where, seen)
        if out is None:
            out = dataclasses.replace(
                reading, strings=list(reading.strings), fields=set(reading.fields), keys=set(reading.keys)
            )
        else:
            out.add(reading)
    if out is not None and NODE_NAME in out.fields | out.keys:
        return None
    return out


def _named(
    tree: Any, name: Token, source: Any, item: int, statement: Statement, index: list[Token], direct: bool = False
) -> list[tuple[list[Token], Any]] | None:
    """The values *name* can hold, a local's, a loop's over what the source spells out, or a member's.

    With *item* at 0 or more, the item of that index of each, and with *item*
    at `ANY` what `name[index]` reads, a dictionary's values under the key
    *index* spells out, or under every key when it spells none. A parameter
    is what its calls pass when it is the translating call's own message or
    reached from it through locals and members alone, *direct*, or a
    constructor's: a parameter read through a result is more
    often an id a function hands back when it finds nothing.
    """
    if item == ANY:
        return _elements(tree, [name], source, statement, 0, _key_text(index, source) or True)
    values = assigned(source.toks, name, statement)
    if values is not None:
        if item < 0:
            return [(value, source) for value in values]
        return _every(tree, [(value, source) for value in values], item, statement, 0)
    if item >= 0 and source.looped(name.text, name.line) is not None:
        rows = _elements(tree, list(source.looped(name.text, name.line)), source, statement, 0)
        return None if rows is None else _every(tree, rows, item, statement, 0)
    if item >= 0:
        handed = _handed(source, name, statement)
        if handed is None and _member(source.toks, name.text):
            handed = _member_values(tree, source, name.text, statement, False)
        return None if handed is None else _every(tree, handed, item, statement, 0)
    over = source.looped(name.text, name.line)
    if over is not None:
        return _elements(tree, list(over), source, statement, 0)
    start, _, params = _function(source.toks, name.line)
    if start >= 0 and name.text in params and (direct or source.toks[start + 1].text == "_init"):
        return _handed(source, name, statement, tree)
    field = [Token("id", "self", name.line), Token("op", ".", name.line), Token("id", name.text, name.line)]
    if start >= 0 and name.text not in params and not _member(source.toks, name.text):
        value, where = _constant_value(tree, [name], source)
        if value:
            return [(value, where)]
        base = _base(tree, source)
        while base is not None and not _member(base.toks, name.text):
            base = _base(tree, base)
        return None if base is None else [(field, source)]
    if start < 0 or name.text in params:
        return None
    values = _member_values(tree, source, name.text, statement, False)
    if values is None:
        return None
    return values + [(field, source)]


def _elements(
    tree: Any, over: list[Token], source: Any, statement: Statement, depth: int, indexed: bool | str = False
) -> list[tuple[list[Token], Any]] | None:
    """What a `for` over *over* gives its variable, as far as the source spells it out.

    An array literal gives its items and a dictionary literal its keys, a
    constant, a local or a member the elements of every value it holds, and
    `.keys()` and `.values()` of one the keys or the values.
    """
    over = _bare(over)
    texts = [t.text for t in over]
    if not over or depth > 4:
        return None
    arms = _arms(over)
    if arms:
        out: list[tuple[list[Token], Any]] = []
        for arm in arms:
            found = _elements(tree, arm, source, statement, depth + 1, indexed)
            if found is None:
                return None
            out.extend(found)
        return out
    if texts[0] == "[" and texts[-1] == "]":
        return [(cell, source) for cell in _cells(over) if not _an_id(cell)]
    if texts[0] == "{" and texts[-1] == "}":
        cells = _cells(over)
        if isinstance(indexed, str):
            cells = [cell for cell in cells if _key_text(_half(cell, 0), source) == indexed]
        halves = [_half(cell, 1 if indexed is not False else 0) for cell in cells]
        return [(half, source) for half in halves if not _an_id(half)]
    if texts[-3:] in ([".", "keys", "("], [".", "values", "("]) or texts[-4:-1] in (
        [".", "keys", "("],
        [".", "values", "("],
    ):
        whole = over[: texts.index(".", len(texts) - 4)]
        half = 0 if "keys" in texts[-3:] else 1
        found = _elements(tree, whole, source, statement, depth + 1) if whole else None
        if found is None or not whole or _bare(_constant_value(tree, whole, source)[0])[:1] == []:
            return None
        value, where = _constant_value(tree, whole, source)
        value = _bare(value)
        if not value or value[0].text != "{":
            return None
        return [(_half(cell, half), where) for cell in _cells(value)]
    value, where = _constant_value(tree, over, source)
    if value:
        return _elements(tree, value, where, statement, depth + 1, indexed)
    if len(over) > 2 and texts[0] in COPIES and texts[1] == "(" and _closes(over, 1) == len(over) - 1:
        return [] if len(over) == 3 else _elements(tree, over[2:-1], source, statement, depth + 1, indexed)
    if len(over) != 1 or over[0].kind != "id":
        return None
    looped = source.looped(over[0].text, over[0].line)
    if looped is not None:
        rows = _elements(tree, list(looped), source, statement, depth + 1)
        if rows is None:
            return None
        out = []
        for row, where in rows:
            found = _elements(tree, row, where, statement, depth + 1, indexed)
            if found is None:
                return None
            out.extend(found)
        return out
    values = assigned(source.toks, over[0], statement)
    if values is None:
        handed = _handed(source, over[0], statement, tree)
        if handed is not None:
            out = []
            for each, where in handed:
                found = _elements(tree, each, where, statement, depth + 1, indexed)
                if found is None:
                    return None
                out.extend(found)
            return out
        if _function(source.toks, over[0].line)[0] >= 0 and not _member(source.toks, over[0].text):
            return None
        return _member_values(tree, source, over[0].text, statement, True)
    out: list[tuple[list[Token], Any]] = []
    for each in values:
        found = _elements(tree, each, source, statement, depth + 1, indexed)
        if found is None:
            return None
        out.extend(found)
    return out


def _constant_value(tree: Any, span: list[Token], source: Any) -> tuple[list[Token], Any]:
    """The value of the constant *span* names, through every constant it names, or nothing.

    A bare name may be a constant of a class the file extends, `LINE` in a menu.
    """
    named = tree._constant(span, source)
    texts = [t.text for t in span]
    if named is None and len(span) == 5 and texts[1] == texts[3] == "." and span[4].kind == "id":
        path = source.aliases.get(texts[0]) or tree.index.classes.get(texts[0])
        where = tree.files.get(path or "")
        if where is not None and texts[4] in where.consts:
            named = (where, texts[4], [])
    if named is None and len(span) == 1 and span[0].kind == "id":
        base = _base(tree, source)
        while base is not None and named is None:
            named = (base, span[0].text, []) if span[0].text in base.consts else None
            base = _base(tree, base) if named is None else base
    if named is None or named[2]:
        return [], source
    value, where = tree._followed(named[0], named[1])
    return value, where


def _base(tree: Any, source: Any) -> Any | None:
    """The file of the class *source* extends by its class name, or None."""
    toks = source.toks
    at = next((i for i, t in enumerate(toks[:-1]) if t.text == "extends" and (i == 0 or toks[i - 1].kind == "nl")), -1)
    if at < 0:
        return None
    return tree.files.get(tree.index.classes.get(toks[at + 1].text) or "")


def _key_text(span: list[Token], source: Any) -> str:
    """The key a lone string or a constant of a string spells out, or empty."""
    if len(span) == 1 and span[0].kind == "id" and span[0].text in source.consts:
        span = source.consts[span[0].text]
    if len(span) == 1 and span[0].kind == "str":
        return span[0].text.lstrip("&^").strip("\"'")
    return ""


def _an_id(cell: list[Token]) -> bool:
    """Whether *cell* is a lone `&"..."`, a StringName, which the tree keeps for ids and never for a message."""
    return len(cell) == 1 and cell[0].kind == "str" and cell[0].text.startswith("&")


def _handed(
    source: Any, name: Token, statement: Statement, tree: Any = None
) -> list[tuple[list[Token], Any]] | None:
    """What the calls of the function around *name* in its own file pass for it, when it is a parameter.

    A parameter of `_init` is what every `Class.new()` of the tree passes,
    when *tree* is given and the file has a class name. With *tree*, a
    function one file alone defines is read at its calls in every file, a
    subclass's call of its base's among them. None when it is no parameter,
    or when nothing calls the function.
    """
    start, _, params = _function(source.toks, name.line)
    if start < 0 or name.text not in params:
        return None
    toks = source.toks
    function = toks[start + 1].text
    position = _parameters(toks, start).index(name.text)
    fallback = _default(toks, start, position)
    out: list[tuple[list[Token], Any]] = []
    if function == "_init" and tree is not None:
        return _constructed(tree, source, position, toks[start].line)
    for at in range(len(toks) - 1):
        if toks[at].text != function or toks[at + 1].text != "(" or (at > 0 and toks[at - 1].text in ("func", ".")):
            continue
        args = _cells([toks[at + 1]] + toks[at + 2 : _closes(toks, at + 1)] + [toks[_closes(toks, at + 1)]])
        if position >= len(args):
            if fallback is None:
                return None
            out.append((fallback, source))
            continue
        out.append((args[position], source))
    if tree is not None and _alone(tree, function):
        for where in tree.files.values():
            if where is source:
                continue
            there = where.toks
            for at in range(1, len(there) - 1):
                if there[at].text != function or there[at + 1].text != "(" or there[at - 1].text == "func":
                    continue
                closing = _closes(there, at + 1)
                args = _cells([there[at + 1]] + there[at + 2 : closing] + [there[closing]])
                if position >= len(args):
                    if fallback is None:
                        return None
                    out.append((fallback, source))
                    continue
                out.append((args[position], where))
    return out or None


def _alone(tree: Any, function: str) -> bool:
    """Whether one file of the tree alone defines *function*, so every call of the name is a call of it."""
    return sum(1 for where in tree.files.values() if _defines(where.toks, function)) == 1


def _defines(toks: list[Token], function: str) -> bool:
    return any(
        tok.text == "func" and toks[at + 1].text == function for at, tok in enumerate(toks[:-1])
    )


def _constructed(tree: Any, source: Any, position: int, line: int) -> list[tuple[list[Token], Any]] | None:
    """The argument at *position* of every `Class.new()` the tree makes of the class whose `_init` is at *line*.

    An inner class is made by its bare name in its own file, and the file's
    class by its class name anywhere in the tree.
    """
    inner = _inner_class(tree, source, line)
    if inner:
        names, files = [inner], [source]
    else:
        names = [name for name, path in tree.index.classes.items() if path == source.path]
        files = list(tree.files.values())
    out: list[tuple[list[Token], Any]] = []
    for where in files:
        toks = where.toks
        for at in range(len(toks) - 3):
            if toks[at].text not in names or [t.text for t in toks[at + 1 : at + 4]] != [".", "new", "("]:
                continue
            closing = _closes(toks, at + 3)
            args = _cells([toks[at + 3]] + toks[at + 4 : closing] + [toks[closing]])
            if position >= len(args):
                return None
            out.append((args[position], where))
    return out or None


def _inner_class(tree: Any, source: Any, line: int) -> str:
    """The inner class the indented *line* stands in, or empty at the file's own level.

    The tokens keep no indentation, so the file's own lines are read for it,
    from the tree the writer stands in. A file not there, as under `--root`,
    or a line that is no `func` there, is taken as the file's own level.
    """
    lines = _lines(tree, source.path)
    if line > len(lines) or "func" not in lines[line - 1] or not lines[line - 1][:1].isspace():
        return ""
    for above in range(line - 2, -1, -1):
        text = lines[above]
        if text.strip() and not text[:1].isspace():
            words = text.split()
            return words[1].rstrip(":") if words[0] == "class" and len(words) > 1 else ""
    return ""


_LINES: dict[str, list[str]] = {}


def _lines(tree: Any, path: str) -> list[str]:
    """The lines of the tree's file *path*, read once."""
    if path not in _LINES:
        root = type(tree).resolve.__globals__["SARA_GODOT"]
        try:
            _LINES[path] = (root / path).read_text(encoding="utf-8").split("\n")
        except OSError:
            _LINES[path] = []
    return _LINES[path]


def _default(toks: list[Token], start: int, position: int) -> list[Token] | None:
    """The default value of the parameter at *position* of the function at *start*, or None when it has none."""
    signature = _cells(toks[start + 2 : _closes(toks, start + 2) + 1])
    if position >= len(signature):
        return None
    cell = signature[position]
    at = next((i for i, t in enumerate(cell) if t.text in ("=", ":=")), -1)
    return cell[at + 1 :] if at >= 0 else None


def _after(toks: list[Token], at: int) -> str:
    """The token before *at* that is not a line's end, which a signature over several lines has."""
    at -= 1
    while at > 0 and toks[at].kind == "nl":
        at -= 1
    return toks[at].text


def _parameters(toks: list[Token], start: int) -> list[str]:
    """The names of the parameters of the function whose `func` is at *start*, in order."""
    out: list[str] = []
    depth = 0
    for at in range(start + 2, len(toks)):
        text = toks[at].text
        if text in ("(", "[", "{"):
            depth += 1
        elif text in (")", "]", "}"):
            depth -= 1
            if depth == 0:
                break
        elif depth == 1 and toks[at].kind == "id" and _after(toks, at) in ("(", ","):
            out.append(text)
    return out


def _half(cell: list[Token], side: int) -> list[Token]:
    """The key or the value of a dictionary literal's entry."""
    texts = [t.text for t in cell]
    cut = texts.index(":") if ":" in texts else (texts.index("=") if "=" in texts else -1)
    if cut < 0:
        return cell
    return cell[:cut] if side == 0 else cell[cut + 1 :]


def _member(toks: list[Token], name: str) -> bool:
    """Whether the file declares a `var` *name*, asked once the function around a use declares none.

    The lexer keeps no indentation, so a member of an inner class, declared
    below the outer class's functions, is told from a local this way. A
    window's `title`, the engine's, is one when the file sets it.
    """
    if name in ENGINE_WORDS and any(
        tok.text == name and toks[at + 1].text == "=" and toks[at - 1].kind == "nl" for at, tok in enumerate(toks[:-1])
    ):
        return True
    return any(tok.text == "var" and toks[at + 1].text == name for at, tok in enumerate(toks[:-1]))


def _member_values(
    tree: Any, source: Any, name: str, statement: Statement, elements: bool
) -> list[tuple[list[Token], Any]] | None:
    """Every value the file gives the member *name*, or with *elements* every element it puts in it.

    An element is what `append`, `push_back` or `push_front` adds, each item
    of an array literal `append_array` adds, or what an assigned array holds.
    A `+=`, an `insert` or an `append_array` of anything else leaves the
    member unread, and so does a value given from outside the file.
    """
    toks = source.toks
    out: list[tuple[list[Token], Any]] = []
    for at, tok in enumerate(toks[:-1]):
        if tok.kind != "id" or tok.text != name or (at > 0 and toks[at - 1].text == "."):
            continue
        after = toks[at + 1].text
        if after in ("+=", "-="):
            return None
        value: list[Token] | None = None
        if after == "=" or (after in (":", ":=") and at > 0 and toks[at - 1].text == "var"):
            start = next((i + 1 for i in range(at + 1, len(toks)) if toks[i].text in ("=", ":=") or toks[i].kind == "nl"), None)
            if start is None or toks[start - 1].kind == "nl":
                continue
            value = statement(toks, start)
            if not elements:
                out.append((value, source))
                continue
            found = _elements(tree, value, source, statement, 1)
            if found is None:
                return None
            out.extend(found)
        elif after == "." and at + 3 < len(toks) and toks[at + 3].text == "(":
            method = toks[at + 2].text
            if method == "append_array" and elements:
                added = _bare(statement(toks, at + 4))
                if not added or added[0].text != "[" or _closes(added, 0) != len(added) - 1:
                    return None
                out.extend((cell, source) for cell in _cells(added))
            elif method in ("append_array", "insert", "assign"):
                return None
            if elements and method in ("append", "push_back", "push_front"):
                out.append((statement(toks, at + 4), source))
    return out


def _assigned_from(toks: list[Token], name: Token) -> bool:
    """Whether *name* stands as the value given a field or a dictionary key, `x.kind = kind` or `{"kind": kind}`.

    The writer reads such a value only because some call reads the field, and
    a local there is more often an id than a message, a step's kind among them.
    A typed local's declaration, `var title: String = name`, is no field.
    """
    at = next((i for i, t in enumerate(toks) if t is name), 0)
    if at < 1 or toks[at - 1].text not in (":", "="):
        return False
    start = at - 1
    while start > 0 and toks[start - 1].kind != "nl":
        start -= 1
    return not (toks[at - 1].text == "=" and toks[start].text == "var")


def assigned(toks: list[Token], name: Token, statement: Statement) -> list[list[Token]] | None:
    """Every value the function around *name* assigns to it, or None when it is no local there."""
    start, end, params = _function(toks, name.line)
    if start < 0 or name.text in params:
        return None
    values: list[list[Token]] = []
    for at in range(start, end):
        tok = toks[at]
        if tok.kind != "id" or tok.text != name.text:
            continue
        before = toks[at - 1].text if at > 0 else ""
        after = toks[at + 1].text if at + 1 < end else ""
        if before in ("for", "+=") or after in ("+=", "-="):
            return None
        if before == "var":
            at_value = _value_of_declaration(toks, at + 1, end)
            if at_value is not None:
                values.append(statement(toks, at_value))
        elif after == "=" and toks[at - 1].kind == "nl":
            values.append(statement(toks, at + 2))
    return values or None


def _function(toks: list[Token], line: int) -> tuple[int, int, set[str]]:
    """The first and last token of the named function holding *line*, and its parameters."""
    start = -1
    params: set[str] = set()
    for at, tok in enumerate(toks[:-2]):
        if tok.text != "func" or toks[at + 1].kind != "id" or toks[at + 2].text != "(":
            continue
        if tok.line > line:
            return (start, at, params) if start >= 0 else (-1, -1, set())
        start = at
        params = set()
        depth = 0
        for inner in range(at + 2, len(toks)):
            text = toks[inner].text
            if text == "(":
                depth += 1
            elif text == ")":
                depth -= 1
                if depth == 0:
                    break
            elif depth == 1 and toks[inner].kind == "id" and _after(toks, inner) in ("(", ","):
                params.add(text)
    return (start, len(toks), params) if start >= 0 else (-1, -1, set())


def _value_of_declaration(toks: list[Token], at: int, end: int) -> int | None:
    """The token after a `var` declaration's `=` or `:=`, or None when it declares no value."""
    while at < end and toks[at].kind != "nl":
        if toks[at].text in ("=", ":="):
            return at + 1
        at += 1
    return None


def _items(
    tree: Any, value: list[Token], source: Any, item: int, statement: Statement, depth: int = 0
) -> list[tuple[list[Token], Any]] | None:
    """The item *item* of every array *value* can be, or None when one of them is not spelled out.

    An array literal gives its own item, a call the item of every array its
    function returns, and a local every array it is assigned, so a function
    that keeps one refusal in a local and returns it in two places is read.
    An array too short to have the item adds nothing, since the code that
    reads one guards it by its size. A `.get(key, otherwise)` is every value of what it is asked and the
    fallback. A loop's variable is every row of what it runs over, and a constant
    StringName among the rows is a divider with no item.
    """
    value = _bare(value)
    if not value or depth > 4:
        return None
    if value[0].text == "[" and value[-1].text == "]":
        cells = _cells(value)
        if not cells:
            return []
        return [(cells[item], source)] if item < len(cells) else []
    arms = _arms(value)
    if arms:
        return _every(tree, [(arm, source) for arm in arms], item, statement, depth)
    if value[-1].text == "]" and _opening(value) > 0:
        rows = _elements(tree, value[: _opening(value)], source, statement, depth + 1, True)
        return None if rows is None else _every(tree, rows, item, statement, depth)
    if len(value) == 1 and value[0].kind == "id":
        constant, _ = _constant_value(tree, value, source)
        if _an_id(_bare(constant)):
            return []
        values = assigned(source.toks, value[0], statement)
        over = source.looped(value[0].text, value[0].line) if values is None else None
        if over is not None:
            rows = _elements(tree, list(over), source, statement, depth + 1)
            return None if rows is None else _every(tree, rows, item, statement, depth)
        if values is None:
            return None
        return _every(tree, [(v, source) for v in values], item, statement, depth)
    texts = [t.text for t in value]
    got = texts.index("get") if "get" in texts else -1
    if got > 1 and texts[got - 1] == "." and texts[got + 1 : got + 2] == ["("] and _closes(value, got + 1) == len(value) - 1:
        rows = _elements(tree, value[: got - 1], source, statement, depth + 1, True)
        passed = _cells(value[got + 1 :])
        if rows is None or len(passed) != 2:
            return None
        return _every(tree, rows + [(passed[1], source)], item, statement, depth)
    targets = _targets(tree, value, source, statement)
    if not targets:
        return None
    return _every(tree, [(r, where) for where, name in targets for r in where.returns[name]], item, statement, depth)


def _every(
    tree: Any, values: list[tuple[list[Token], Any]], item: int, statement: Statement, depth: int
) -> list[tuple[list[Token], Any]] | None:
    out: list[tuple[list[Token], Any]] = []
    for value, where in values:
        found = _items(tree, value, where, item, statement, depth + 1)
        if found is None:
            return None
        out.extend(found)
    return out


def _arms(span: list[Token]) -> list[list[Token]]:
    """The two values of `A if condition else B` at the top level of *span*, or nothing."""
    depth = 0
    cut_if = -1
    for i, tok in enumerate(span):
        if tok.text in ("(", "[", "{"):
            depth += 1
        elif tok.text in (")", "]", "}"):
            depth -= 1
        elif depth == 0 and tok.text == "if" and cut_if < 0:
            cut_if = i
        elif depth == 0 and tok.text == "else" and cut_if > 0:
            return [span[:cut_if], span[i + 1 :]]
    return []


def _opening(span: list[Token]) -> int:
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


def _closes(span: list[Token], at: int) -> int:
    """The index of the bracket that closes the one at *at*, or -1."""
    depth = 0
    for i in range(at, len(span)):
        if span[i].text in ("(", "[", "{"):
            depth += 1
        elif span[i].text in (")", "]", "}"):
            depth -= 1
            if depth == 0:
                return i
    return -1


def _bare(span: list[Token]) -> list[Token]:
    while span and span[0].text == "(" and span[-1].text == ")":
        span = span[1:-1]
    return span


def _cells(array: list[Token]) -> list[list[Token]]:
    """The items of an array literal, at its top level."""
    out: list[list[Token]] = [[]]
    depth = 0
    for tok in array[1:-1]:
        if tok.text in ("(", "[", "{"):
            depth += 1
        elif tok.text in (")", "]", "}"):
            depth -= 1
        elif depth == 0 and tok.text == ",":
            out.append([])
            continue
        if tok.kind != "nl":
            out[-1].append(tok)
    return [cell for cell in out if cell]


def _targets(
    tree: Any, call: list[Token], source: Any, statement: Statement | None = None
) -> list[tuple[Any, str]]:
    """The files and name of the function *call* reaches: its own file's, a class's, or every one of its name.

    A receiver that is a local made by `Class.new()` reaches its class's.
    """
    if call[-1].text != ")":
        return []
    depth = 0
    opener = -1
    for i in range(len(call) - 1, -1, -1):
        if call[i].text in (")", "]", "}"):
            depth += 1
        elif call[i].text in ("(", "[", "{"):
            depth -= 1
            if depth == 0:
                opener = i
                break
    if opener < 1 or call[opener - 1].kind != "id":
        return []
    name = call[opener - 1].text
    head = [t.text for t in call[: opener - 1]]
    if not head or head == ["self", "."]:
        return [(source, name)] if name in source.returns else []
    owner = head[0]
    if len(head) == 2 and statement is not None and owner not in source.aliases and owner not in tree.index.classes:
        made = [_bare(v) for v in assigned(source.toks, call[0], statement) or []]
        if made and all(len(v) >= 4 and v[0].kind == "id" and [t.text for t in v[1:4]] == [".", "new", "("] for v in made):
            owner = made[0][0].text
    if len(head) == 2 or head[1:3] == [".", "new"]:
        path = source.aliases.get(owner) or tree.index.classes.get(owner)
        there = tree.files.get(path or "")
        if there is not None:
            return [(there, name)] if name in there.returns else []
    return [(f, name) for f in tree.files.values() if name in f.returns]
