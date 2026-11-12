"""What a `.gmacs` expression is and what type each part of it has.

    from gmacs_types import Expression, KernelTypes

The formatter's cast and range rewrites read an expression rather than
a line: a `float()` it drops has to hold an int and sit where GLSL converts an
int on its own, and `range(a, b + 1)` has to end in a `+ 1` that belongs to the
whole bound. So this parses one expression into a tree and reads the type of
each node from what the file declares, its params, its uniforms, its
constants, its locals, its loop counters and what its imports declare.

It is a reader of types, never a checker. A name it cannot place, a call it does
not know and a mix of types GLSL would refuse all read as no type at all, and
the formatter keeps every cast whose inside or neighbour reads that way.
"""

from __future__ import annotations

import re
from pathlib import Path

SCALAR_INTS = ("int", "uint")
FLOAT_VECTORS = ("vec2", "vec3", "vec4")
TYPE_NAMES = frozenset(
    ["float", "int", "uint", "bool"]
    + ["%s%d" % (kind, n) for kind in ("vec", "ivec", "uvec", "bvec") for n in (2, 3, 4)]
    + ["mat2", "mat3", "mat4"]
)
# The built-ins whose result has the type of their arguments when the
# arguments agree, which is all a cast's inside needs to be read as an int.
SAME_TYPE_BUILTINS = frozenset(["min", "max", "abs", "clamp", "sign"])
FLOAT_BUILTINS = frozenset(["length", "distance", "dot"])
# One token of an expression: a number with its suffix, a name, or an operator,
# the longest first so that `<=` is never read as `<` and `=`.
TOKEN = re.compile(
    r"\s*(?:(?P<number>0[xX][0-9a-fA-F]+[uU]?|(?:\d+\.\d*|\.\d+|\d+)(?:[eE][+-]?\d+)?[fFuU]?)"
    r"|(?P<name>[A-Za-z_]\w*)"
    r"|(?P<op><<=|>>=|\*\*|<<|>>|<=|>=|==|!=|\+=|-=|\*=|/=|%=|&=|\|=|\^=|&&|\|\||->|[-+*/%<>=!&|^~?:,.()\[\]]))"
)
# How tightly each binary operator binds, GLSL's order with the dialect's
# `and` and `or` beside their C spellings.
BINARY = {
    "or": 1, "||": 1, "and": 2, "&&": 2, "|": 3, "^": 4, "&": 5, "==": 6, "!=": 6,
    "<": 7, ">": 7, "<=": 7, ">=": 7, "<<": 8, ">>": 8, "+": 9, "-": 9, "*": 10, "/": 10, "%": 10,
}
ARITHMETIC = ("+", "-", "*", "/")
ORDERING = ("<", ">", "<=", ">=")
DECLARATION = re.compile(r"^(?:(?:const|shared|uniform)\s+)?(?P<type>[A-Za-z_]\w*)\s+(?P<rest>[A-Za-z_]\w*.*)$")
DEF_LINE = re.compile(r"^def\s+(?P<name>\w+)\s*\((?P<args>[^)]*)\)\s*(?:->\s*(?P<type>\w+))?\s*:")
FOR_LINE = re.compile(r"^for\s+(?:(?P<type>\w+)\s+)?(?P<name>\w+)\s+in\s+range\s*\((?P<args>.*)\)\s*:$")
IMPORT = re.compile(r"^import\s+([\w/]+)")


class Node:
    """One piece of a parsed expression: its kind, its span in the line and its parts."""

    def __init__(self, kind: str, start: int, end: int, value: str = "", parts: list | None = None) -> None:
        self.kind = kind
        self.start = start
        self.end = end
        self.value = value
        self.parts = parts or []


class Expression:
    """A precedence climbing parser over one expression of a line.

    It builds the tree the rewrites need and nothing more: a cast and what it
    sits beside. Anything it does not know, a token or an unclosed bracket, is
    an error, and the caller then leaves the whole line as it was written.
    """

    def __init__(self, text: str) -> None:
        self.text = text
        self.tokens: list[tuple[str, str, int, int]] = []
        at = 0
        while at < len(text):
            found = TOKEN.match(text, at)
            if not found or found.end() == at:
                if text[at:].strip():
                    raise ValueError("an unknown character")
                break
            kind = found.lastgroup or ""
            self.tokens.append((kind, found.group(kind), found.start(kind), found.end(kind)))
            at = found.end()
        self.at = 0

    def parse(self) -> Node:
        node = self._ternary()
        if self.at != len(self.tokens):
            raise ValueError("more than one expression")
        return node

    def _peek(self) -> tuple[str, str, int, int] | None:
        return self.tokens[self.at] if self.at < len(self.tokens) else None

    def _take(self, value: str) -> tuple[str, str, int, int]:
        token = self._peek()
        if not token or token[1] != value:
            raise ValueError("expected %s" % value)
        self.at += 1
        return token

    def _ternary(self) -> Node:
        node = self._binary(1)
        token = self._peek()
        if token and token[1] == "?":
            self.at += 1
            then = self._ternary()
            self._take(":")
            other = self._ternary()
            return Node("ternary", node.start, other.end, "?", [node, then, other])
        return node

    def _binary(self, least: int) -> Node:
        node = self._unary()
        while True:
            token = self._peek()
            if not token or token[0] == "number" or token[1] not in BINARY or BINARY[token[1]] < least:
                return node
            self.at += 1
            right = self._binary(BINARY[token[1]] + 1)
            node = Node("binary", node.start, right.end, token[1], [node, right])

    def _unary(self) -> Node:
        token = self._peek()
        if token and token[1] in ("-", "+", "!", "~", "not"):
            self.at += 1
            inner = self._unary()
            return Node("unary", token[2], inner.end, token[1], [inner])
        return self._postfix(self._primary())

    def _primary(self) -> Node:
        token = self._peek()
        if not token:
            raise ValueError("an expression ends early")
        self.at += 1
        if token[0] == "number":
            return Node("number", token[2], token[3], token[1])
        if token[0] == "name" and token[1] not in BINARY:
            return Node("name", token[2], token[3], token[1])
        if token[1] == "(":
            inner = self._ternary()
            close = self._take(")")
            return Node("paren", token[2], close[3], "", [inner])
        raise ValueError("an unexpected %s" % token[1])

    def _postfix(self, node: Node) -> Node:
        while True:
            token = self._peek()
            if not token:
                return node
            if token[1] == "(" and node.kind in ("name", "member"):
                self.at += 1
                args: list[Node] = []
                if self._peek() and self._peek()[1] != ")":
                    args.append(self._ternary())
                    while self._peek() and self._peek()[1] == ",":
                        self.at += 1
                        args.append(self._ternary())
                close = self._take(")")
                node = Node("call", node.start, close[3], node.value if node.kind == "name" else "", [node] + args)
            elif token[1] == "[":
                self.at += 1
                index = self._ternary()
                close = self._take("]")
                node = Node("index", node.start, close[3], "", [node, index])
            elif token[1] == ".":
                self.at += 1
                field = self._peek()
                if not field or field[0] != "name":
                    raise ValueError("a member with no name")
                self.at += 1
                node = Node("member", node.start, field[3], field[1], [node])
            else:
                return node


class KernelTypes:
    """The type of every name a kernel file declares, read from its own lines and its imports.

    A name declared twice with two types has none, and so has a name the file
    never declares, so a cast whose inside or neighbour it cannot read is kept.
    That is the whole of the safety: the rewrite is only as sure as this table.
    """

    def __init__(self, lines: list[str], libraries: dict[str, Path], seen: frozenset[str] = frozenset()) -> None:
        self.names: dict[str, str | None] = {}
        self.returns: dict[str, str | None] = {}
        self.locals: list[dict[str, str | None]] = []
        self.gives: list[str] = []
        self.owner: list[int] = []
        current: dict[str, str | None] | None = None
        in_params = False
        for line in lines:
            code = line.rstrip()
            body = code.strip()
            top = bool(body) and not line[:1].isspace()
            if top:
                current = None
                in_params = body.startswith("params")
            found = IMPORT.match(body) if top else None
            if found and found.group(1) in libraries and found.group(1) not in seen:
                path = libraries[found.group(1)]
                lib = KernelTypes(path.read_text(encoding="utf-8").split("\n"), libraries, seen | {found.group(1)})
                for name, kind in lib.names.items():
                    _note(self.names, name, kind)
                for name, kind in lib.returns.items():
                    _note(self.returns, name, kind)
            found = DEF_LINE.match(body) if top else None
            if found:
                _note(self.returns, found.group("name"), found.group("type") or "void")
                current = {}
                self.locals.append(current)
                self.gives.append(found.group("type") or "void")
                for arg in found.group("args").split(","):
                    words = arg.split()
                    if len(words) >= 2:
                        _note(current, words[-1], words[-2])
            self.owner.append(len(self.locals) - 1 if current is not None else -1)
            target = current if current is not None else (self.names if top or in_params else None)
            if target is not None and body:
                self._declare(body, target)

    def _declare(self, body: str, into: dict[str, str | None]) -> None:
        found = FOR_LINE.match(body) or re.match(
            r"^for\s+(?:(?P<type>\w+)\s+)?(?P<name>\w+)\s+in\s+range_inclusive\b", body
        )
        if found:
            _note(into, found.group("name"), found.group("type") or "int")
            return
        found = DECLARATION.match(body)
        if not found or found.group("type") not in TYPE_NAMES:
            return
        for piece in split_args(found.group("rest").split(":")[0] if body.startswith("uniform") else found.group("rest")):
            name = re.match(r"^([A-Za-z_]\w*)\s*(\[[^\]]*\])?", piece.strip())
            if name:
                _note(into, name.group(1), found.group("type") + ("[]" if name.group(2) else ""))

    def of(self, name: str, line: int) -> str | None:
        owner = self.owner[line] if line < len(self.owner) else -1
        if owner >= 0 and name in self.locals[owner]:
            local = self.locals[owner][name]
            if name in self.names and self.names[name] != local:
                return None
            return local
        return self.names.get(name)

    def returned(self, line: int) -> str | None:
        owner = self.owner[line] if line < len(self.owner) else -1
        return self.gives[owner] if owner >= 0 else None


    def of_node(self, node: Node, line: int) -> str | None:
        """The GLSL type *node* has, or None when the file does not say."""
        if node.kind == "number":
            if re.search(r"[uU]$", node.value):
                return "uint"
            if node.value[:2].lower() == "0x":
                return "int"
            return "float" if re.search(r"[.eEfF]", node.value) else "int"
        if node.kind == "name":
            return {"true": "bool", "false": "bool"}.get(node.value) or self.of(node.value, line)
        if node.kind == "paren":
            return self.of_node(node.parts[0], line)
        if node.kind == "unary":
            return "bool" if node.value in ("!", "not") else self.of_node(node.parts[0], line)
        if node.kind == "member":
            base = self.of_node(node.parts[0], line)
            if not base or not re.fullmatch(r"[iub]?vec[234]", base) or not re.fullmatch(r"[xyzwrgba]{1,4}", node.value):
                return None
            scalar = {"i": "int", "u": "uint", "b": "bool"}.get(base[0], "float")
            return scalar if len(node.value) == 1 else base.rstrip("234") + str(len(node.value))
        if node.kind == "index":
            base = self.of_node(node.parts[0], line)
            if base and base.endswith("[]"):
                return base[:-2]
            if base and re.fullmatch(r"[iub]?vec[234]", base):
                return {"i": "int", "u": "uint", "b": "bool"}.get(base[0], "float")
            return None
        if node.kind == "call":
            return self._call_type(node, line)
        if node.kind == "ternary":
            then, other = (self.of_node(part, line) for part in node.parts[1:])
            return then if then == other else None
        if node.kind == "binary":
            return self._binary_type(node, line)
        return None

    def _call_type(self, node: Node, line: int) -> str | None:
        name = node.value
        args = [self.of_node(part, line) for part in node.parts[1:]]
        if name in TYPE_NAMES:
            return name
        if name in ("image_size", "imageSize"):
            return "ivec2"
        if name == "length" and node.parts[0].kind == "member" and not args:
            return "int"
        if name in SAME_TYPE_BUILTINS and args and len(set(args)) == 1:
            return args[0]
        if name in FLOAT_BUILTINS:
            return "float"
        return self.returns.get(name) if node.parts[0].kind == "name" else None

    def _binary_type(self, node: Node, line: int) -> str | None:
        left, right = (self.of_node(part, line) for part in node.parts)
        if node.value in ORDERING + ("==", "!=", "and", "or", "&&", "||"):
            return "bool"
        if left is None or right is None:
            return None
        if node.value in ("<<", ">>"):
            return left if left in SCALAR_INTS or left.startswith(("ivec", "uvec")) else None
        if left == right:
            return left
        pair = {left, right}
        if pair == {"int", "uint"}:
            return "uint"
        if pair <= {"int", "uint", "float"} and node.value in ARITHMETIC:
            return "float"
        vectors = [kind for kind in pair if re.fullmatch(r"[iu]?vec[234]", kind)]
        if len(vectors) == 1 and (pair - set(vectors)) <= {"int", "uint", "float"} and node.value in ARITHMETIC:
            vector = vectors[0]
            scalar = (pair - set(vectors)).pop()
            if vector.startswith("vec"):
                return vector
            if scalar == "float":
                return "vec" + vector[-1]
            return vector if scalar == ("uint" if vector[0] == "u" else "int") else None
        return None


def _note(table: dict[str, str | None], name: str, kind: str | None) -> None:
    """Records *name* as *kind*, or as unknown once two declarations disagree."""
    if name in table and table[name] != kind:
        table[name] = None
    else:
        table[name] = kind


def split_args(text: str) -> list[str]:
    """*text* split at the commas outside any bracket."""
    pieces = [""]
    depth = 0
    for c in text:
        if c in "([":
            depth += 1
        elif c in ")]":
            depth -= 1
        if c == "," and depth == 0:
            pieces.append("")
        else:
            pieces[-1] += c
    return pieces


def parses(text: str) -> bool:
    """True when *text* is one whole expression."""
    try:
        Expression(text).parse()
    except ValueError:
        return False
    return True
