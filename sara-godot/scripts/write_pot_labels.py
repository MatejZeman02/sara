"""The template writer's reading of the literals that read as a label.

A control's `text` and `tooltip_text`, a menu row's label and a dropdown's item
are translated by Godot on their own when they reach the screen, with no
context, so a literal handed to one through a table, a field or a builder's
parameter reaches the painter without any `tr()` the template could follow.
A hunt under a catalogue made from the template alone found 799 such texts
still English. This file takes every literal of the read files that
reads as a label, so the template holds them all, each under no context, the
one Godot's own translation of a control asks with.

Literals joined with `+` are one, read whole. A literal is a label when it starts with a capital and a small letter,
or with `A` and a word, `"A soft round ..."`, which is how a preset's sentence opens, holds
one line and no `://`, which is how every label of the tree is written. The
rest are paths, ids, shaders and shell, which no control shows and which would
make the template five times the size. Nor is a literal a label where the
code says it never reaches a control: a node's name, `x.name = "Fold"`, a
`StringName` or a `NodePath`, `&"Fold"` and `^"Fold"`, a literal inside the
call of a log line or a lookup by name, `push_error("...")` or
`get_node("...")`, one word with a capital inside it, which is a class's or a
node's name, a word with a slash or an underscore, a path's or an id's, and
a sentence opening on a class's name and a colon,
`"SaExport: ..."`, which is how the tree writes a log line it builds elsewhere.
`write_pot.py` takes what is left into the template, and `write_pseudo.py`
reads its test language from the tree through the same reader.
"""

from __future__ import annotations

import re
from collections.abc import Callable, Iterator

from check_translated import Token

LABEL = re.compile(r"[A-Z][a-z]|A [a-z]")

# One word with a capital after its first letter, `PopupMenu` or `SaBrushEditor`.
IDENTIFIER = re.compile(r"^[A-Z][A-Za-z0-9_]*[a-z0-9][A-Z][A-Za-z0-9_]*%?d?$")

# A log line's head, a class's name or a dotted function and a colon.
LOG_HEAD = re.compile(r"^(?:Sa[A-Z]\w*(?:\([^)]*\))?|\w*[a-z][A-Z]\w*|\w+\.\w+)[\w.]*: ")

# The calls whose literals never reach a control: what is printed or logged,
# and what names a node, a file, a method, a signal, a setting or a meta.
NEVER_SHOWN = frozenset(
    {
        "print", "printerr", "prints", "printt", "print_rich", "print_verbose",
        "push_error", "push_warning", "assert",
        "get_node", "get_node_or_null", "has_node", "find_child", "find_children",
        "load", "preload", "has_method", "emit_signal",
        "connect", "has_signal", "is_class", "get_meta", "set_meta", "has_meta",
        "NodePath", "StringName",
    }
)


def is_label(text: str) -> bool:
    """Whether *text*, a literal's value, reads as a label."""
    return bool(LABEL.match(text)) and "\n" not in text and "://" not in text


def _shown(text: str) -> bool:
    """Whether a label literal can reach a control, not a class's name or a log line."""
    path = " " not in text and ("/" in text or "_" in text)
    return not path and not IDENTIFIER.match(text) and not LOG_HEAD.match(text)


def label_literals(files: dict[str, list[Token]], decode: Callable[[str], str]) -> Iterator[tuple[str, str, int]]:
    """Every literal of *files*, each file's tokens by its path, that reads as a label, with its file and line.

    *decode* turns a string token, quotes and escapes, into its value, the
    template writer's `literal`, handed in since that file imports this one.
    """
    for path in sorted(files):
        toks = files[path]
        calls: list[str] = []
        for at, token in enumerate(toks):
            if token.kind == "op" and token.text in "([{":
                before = toks[at - 1] if at else None
                calls.append(before.text if token.text == "(" and before and before.kind == "id" else "")
            elif token.kind == "op" and token.text in ")]}":
                calls = calls[:-1]
            elif token.kind == "str" and token.text[0] not in "&^" and not _named(toks, at) and not _joined(toks, at):
                text = decode(token.text) + "".join(decode(t.text) for t in _chain(toks, at))
                if is_label(text) and _shown(text) and not (calls and calls[-1] in NEVER_SHOWN):
                    yield text, path, token.line


def _joined(toks: list[Token], at: int) -> bool:
    """Whether the literal at *at* follows a `+` after another literal, a later part of a joined one."""
    back = at - 1
    while back > 0 and toks[back].kind == "nl":
        back -= 1
    if back < 1 or toks[back].text != "+":
        return False
    back -= 1
    while back > 0 and toks[back].kind == "nl":
        back -= 1
    return toks[back].kind == "str"


def _chain(toks: list[Token], at: int) -> list[Token]:
    """The literals joined to the one at *at* with `+`, line ends between them skipped.

    None when the join goes on with something else, or its last literal is
    the receiver of a call, `", ".join(...)`, since then the source does not
    spell the whole text out.
    """
    out: list[Token] = []
    step = _past_line_ends(toks, at + 1)
    while step + 1 < len(toks) and toks[step].text == "+":
        step = _past_line_ends(toks, step + 1)
        if step >= len(toks) or toks[step].kind != "str":
            return []
        out.append(toks[step])
        step = _past_line_ends(toks, step + 1)
    if out and step < len(toks) and toks[step].text in (".", "[", "%"):
        return []
    return out


def _past_line_ends(toks: list[Token], step: int) -> int:
    while step < len(toks) and toks[step].kind == "nl":
        step += 1
    return step


def _named(toks: list[Token], at: int) -> bool:
    """Whether the literal at *at* is assigned to a `name`, a node's."""
    return at >= 2 and toks[at - 1].text in ("=", ":=") and toks[at - 2].text == "name"
