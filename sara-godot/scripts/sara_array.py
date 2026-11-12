"""An array that lives on the GPU: a layer read as NumPy, run by Sara.

    import sara
    from sara_array import Array, where

    doc = sara.connect()
    a = Array(doc.layer("Paint"))            # what the layer holds, (h, w, 4)
    b = Array(doc.layer("Sky"), [0, 0, 512, 512])
    c = (a[:512, :512] * 0.5 + b).clip(0, 1)  # nothing is sent yet
    c.show()                                  # one kernel, one read back
    c.mean()                                  # one kernel, one reduction

An `Array` holds a handle to a rectangle of a layer, never its pixels. Its
operators and NumPy's function protocol build an expression tree, and only
`evaluate()`, `show()`, `numpy.asarray()` and the reductions send anything.
Then the whole tree is written as one kernel in Sara's dialect, sent through
the `kernel` step into a hidden scratch layer, and read back only when a
picture or an array was asked for. Every call is a round trip through the
door, so an expression wins over NumPy only when it is fused, which is why the
tree is collected first. It runs on any card Sara runs on.

What it covers, and what each call is in the kernel it writes:

| Call | In the kernel |
|---|---|
| `+ - * /`, `np.add` and the rest | the GLSL operator, per channel |
| `-a`, `abs(a)`, `np.negative`, `np.absolute` | `-a`, `abs(a)` |
| `a ** b`, `np.power` | `pow(a, b)`, undefined for a negative base in GLSL |
| `np.sqrt`, `np.exp`, `np.log`, `np.sin`, `np.cos`, `np.tan`, `np.floor`, `np.ceil` | the GLSL function |
| `np.minimum`, `np.maximum` | `min`, `max` |
| `< <= > >= == !=` and their ufuncs | `1.0` where true, `0.0` where not, as float32 |
| `np.where(c, x, y)`, `where(c, x, y)` | `x` where `c` is not zero, else `y` |
| `a.clip(lo, hi)`, `np.clip` | `min(max(a, lo), hi)`, NumPy's own order |
| `a[y0:y1, x0:x1]`, `a[y0:y1, x0:x1, :]` | a rectangle of each layer the tree reads |
| `a.sum()`, `mean`, `min`, `max`, and `np.` of each | the `reduce` step, on the GPU |
| the same with `axis=(0, 1)` | four numbers, one a channel |
| `numpy.asarray(a)`, `a.show()` | the `read_pixels` step |

An operand is an `Array` of the same shape, a number, or four numbers, one a
channel. Numbers go into the kernel's params block while there is room, so the
same expression with other numbers compiles once. What the table does not name
raises `NotCovered`, which says the call: a channel index, a step in a slice,
an `out=` argument, an ndarray operand, a reduction over one axis.

One file and NumPy beside `sara.py`, copied into a student's folder the way it
is. The lessons show the kernel by hand before this, because this hides the
split between the Python and the GPU the course is there to teach.
"""

from __future__ import annotations

import math
import weakref
from typing import Any

import numpy as np

import sara

KERNEL = "array_expr"
# The layers the results are written to, hidden and reused once freed.
SCRATCH = "Array scratch"
# Floats the params block holds besides `extent`, within the 128 bytes of push
# constants every Vulkan card offers. Numbers past it are written as literals.
PARAM_FLOATS = 24
REDUCTIONS = ("sum", "mean", "min", "max")


class NotCovered(TypeError):
    """A call the array does not cover, named in the message."""


# --- The tree ------------------------------------------------------------------


class _Leaf:
    """A rectangle `[x, y, w, h]` of the layer called *name*."""

    def __init__(self, name: str, rect: list[int]) -> None:
        self.name = name
        self.rect = [int(v) for v in rect]

    def key(self) -> tuple:
        return (self.name, *self.rect)


class _Const:
    """A number, or four of them, one a channel, as `vec4` takes either."""

    def __init__(self, values: tuple[float, ...]) -> None:
        self.values = values


class _Op:
    """One call over its arguments, each a node."""

    def __init__(self, name: str, args: tuple) -> None:
        self.name = name
        self.args = args


# The ops, by name, as the kernel line each writes. `{0}` is the first argument.
_BINARY = {
    "add": "({0} + {1})",
    "subtract": "({0} - {1})",
    "multiply": "({0} * {1})",
    "divide": "({0} / {1})",
    "power": "pow({0}, {1})",
    "minimum": "min({0}, {1})",
    "maximum": "max({0}, {1})",
    "less": "vec4(less_than({0}, {1}))",
    "less_equal": "vec4(less_than_equal({0}, {1}))",
    "greater": "vec4(greater_than({0}, {1}))",
    "greater_equal": "vec4(greater_than_equal({0}, {1}))",
    "equal": "vec4(equal({0}, {1}))",
    "not_equal": "vec4(not_equal({0}, {1}))",
}
_UNARY = {
    "negative": "(-{0})",
    "positive": "{0}",
    "absolute": "abs({0})",
    "sqrt": "sqrt({0})",
    "exp": "exp({0})",
    "log": "log({0})",
    "sin": "sin({0})",
    "cos": "cos({0})",
    "tan": "tan({0})",
    "floor": "floor({0})",
    "ceil": "ceil({0})",
}
_OTHER = {
    "where": "mix({2}, {1}, not_equal({0}, vec4(0.0)))",
    "clip": "min(max({0}, {1}), {2})",
}
# NumPy's ufunc names where they differ from the table's.
_UFUNC_NAMES = {"true_divide": "divide", "abs": "absolute", "fabs": "absolute"}


def _nodes(root: Any) -> tuple[list[_Leaf], list[_Const], list[_Op]]:
    """The tree's leaves, numbers and ops, each once, in the order a kernel reads them."""
    leaves: dict[tuple, _Leaf] = {}
    consts: dict[int, _Const] = {}
    ops: dict[int, _Op] = {}

    def walk(node: Any) -> None:
        if isinstance(node, _Leaf):
            leaves.setdefault(node.key(), node)
        elif isinstance(node, _Const):
            consts.setdefault(id(node), node)
        elif id(node) not in ops:
            for arg in node.args:
                walk(arg)
            ops[id(node)] = node

    walk(root)
    return list(leaves.values()), list(consts.values()), list(ops.values())


def _literal(value: float) -> str:
    """*value* as a GLSL float literal, infinities and NaN by their bits."""
    if math.isnan(value):
        return "uint_bits_to_float(0x7fc00000u)"
    if math.isinf(value):
        return "uint_bits_to_float(0x%08xu)" % (0x7F800000 if value > 0 else 0xFF800000)
    text = format(float(np.float32(value)), ".9g")
    return text if any(c in text for c in ".e") else text + ".0"


def kernel_source(root: Any, first: _Leaf | None = None) -> tuple[str, dict, list[_Leaf]]:
    """The kernel *root* is, its params and the leaves it reads, `src` first.

    Pure, so the suite reads the text with no Sara. *first* is the leaf whose
    rectangle the run covers, the first the tree reads when it is left out.
    """
    leaves, consts, ops = _nodes(root)
    if first is not None:
        leaves.sort(key=lambda leaf: leaf.key() != first.key())
    images = {leaf.key(): "src" if i == 0 else f"src{i}" for i, leaf in enumerate(leaves)}
    params: dict[str, float] = {}
    spelled: dict[int, str] = {}
    for const in consts:
        parts = []
        for value in const.values:
            # A constant that is not finite is spelled by its bits, because the
            # door's JSON refuses the bare `Infinity` and `NaN` of json.dumps.
            if len(params) < PARAM_FLOATS and math.isfinite(value):
                name = f"c{len(params)}"
                params[name] = float(value)
                parts.append(name)
            else:
                parts.append(_literal(value))
        spelled[id(const)] = f"vec4({', '.join(parts)})"

    lines = [f"kernel {KERNEL}", ""]
    lines += [f"image {images[leaf.key()]}: readonly" for leaf in leaves]
    lines += ["image dst", "", "params:", "    vec2 extent"]
    lines += [f"    float {name}" for name in params]
    lines += ["", f"def {KERNEL}():", "    if pixel.x >= int(extent.x) or pixel.y >= int(extent.y):", "        return"]
    names: dict[int, str] = {}
    for i, leaf in enumerate(leaves):
        lines.append(f"    vec4 a{i} = image_load({images[leaf.key()]}, pixel)")
        names[leaf.key()] = f"a{i}"

    def spell(node: Any) -> str:
        if isinstance(node, _Leaf):
            return names[node.key()]
        if isinstance(node, _Const):
            return spelled[id(node)]
        return names[id(node)]

    for i, op in enumerate(ops):
        form = _BINARY.get(op.name) or _UNARY.get(op.name) or _OTHER[op.name]
        lines.append(f"    vec4 t{i} = {form.format(*(spell(arg) for arg in op.args))}")
        names[id(op)] = f"t{i}"
    lines.append(f"    image_store(dst, pixel, {spell(root)})")
    return "\n".join(lines) + "\n", params, leaves


# --- Scratch layers --------------------------------------------------------------


class _Scratch:
    """The hidden layers one document's results are written to, reused once freed."""

    def __init__(self, document: sara.Document) -> None:
        self.document = document
        self.free: list[str] = []
        self.made = 0
        self.found = False

    def take(self) -> str:
        """A scratch layer nothing holds, added hidden when none is free."""
        if not self.found:
            self.found = True
            for entry in _stack(self.document):
                if str(entry["name"]).startswith(SCRATCH + " "):
                    self.free.append(str(entry["name"]))
                    self.made = max(self.made, _number(str(entry["name"])))
        if self.free:
            return self.free.pop()
        self.made += 1
        name = f"{SCRATCH} {self.made}"
        active = next((e["name"] for e in _stack(self.document) if e.get("active")), None)
        self.document.door.verdict({"layer": {"add": name, "visible": False}})
        if active is not None:
            # The student's layer stays the one a stroke lands on.
            self.document.door.verdict({"layer": {"activate": active}})
        return name

    def give_back(self, name: str) -> None:
        self.free.append(name)


def _number(name: str) -> int:
    tail = name.rsplit(" ", 1)[-1]
    return int(tail) if tail.isdigit() else 0


_SCRATCH: weakref.WeakKeyDictionary = weakref.WeakKeyDictionary()


def _scratch(document: sara.Document) -> _Scratch:
    if document not in _SCRATCH:
        _SCRATCH[document] = _Scratch(document)
    return _SCRATCH[document]


def _stack(document: sara.Document) -> list[dict]:
    said = document.door.verdict({"layers": True})
    if not isinstance(said, list):
        raise sara.SaraError(f"{sara.VERDICT}layers {said}")
    return said


# --- The array -------------------------------------------------------------------


class Array:
    """A rectangle of a layer, or an expression over some, that Sara computes.

    `Array(layer)` is what the layer holds, the rectangle its chunks cover, where
    `Layer.read()` with no rectangle reads the whole canvas, and `Array(layer,
    [x, y, w, h])` is that rectangle.
    """

    __array_priority__ = 100
    dtype = np.dtype(np.float32)
    ndim = 3

    def __init__(self, layer: sara.Layer, rect: list[int] | None = None) -> None:
        entries = _stack(layer.document)
        if isinstance(layer.key, int):
            entry = next((e for e in entries if e["i"] == layer.key), None)
        else:
            entry = next((e for e in entries if e["name"] == layer.key), None)
        if entry is None:
            raise sara.SaraError(f"no layer {layer.key!r}")
        rect = rect if rect is not None else entry["bounds"]
        if rect is None:
            raise ValueError(f"the layer {entry['name']} holds nothing, so an Array of it needs a rect")
        # By name: a scratch layer added later moves the indices above it.
        self._set(layer.document, _Leaf(str(entry["name"]), rect))

    @classmethod
    def _of(cls, document: sara.Document, node: Any, size: tuple[int, int], owner: Any = None) -> Array:
        made = cls.__new__(cls)
        made._set(document, node, size, owner)
        return made

    def _set(self, document: sara.Document, node: Any, size: tuple[int, int] | None = None, owner: Any = None) -> None:
        self.document = document
        self.node = node
        self._size = size if size is not None else (node.rect[3], node.rect[2])
        if self._size[0] <= 0 or self._size[1] <= 0:
            raise ValueError(f"an Array is at least one texel, not {self._size}")
        # What keeps a scratch layer taken: every Array whose tree reads it.
        self._owners = [owner] if owner is not None else []

    @property
    def shape(self) -> tuple[int, int, int]:
        return (self._size[0], self._size[1], 4)

    @property
    def size(self) -> int:
        return self._size[0] * self._size[1] * 4

    def __len__(self) -> int:
        return self._size[0]

    def __repr__(self) -> str:
        if isinstance(self.node, _Leaf):
            return f"Array({self.node.name!r}, {self.node.rect})"
        return f"Array(<{self.node.name} expression>, shape={self.shape})"

    # -- building the tree ------------------------------------------------------

    def _operand(self, other: Any, call: str) -> tuple[Any, list]:
        if isinstance(other, Array):
            if other.document is not self.document:
                raise ValueError(f"{call}: the two arrays live in two documents")
            if other.shape != self.shape:
                raise ValueError(f"{call}: shapes {self.shape} and {other.shape} do not match")
            return other.node, other._owners
        if isinstance(other, (bool, int, float, np.integer, np.floating)):
            return _Const((float(other),)), []
        values = np.asarray(other)
        if values.shape == () and values.dtype.kind in "biuf":
            return _Const((float(values),)), []
        if values.shape == (4,) and values.dtype.kind in "biuf":
            return _Const(tuple(float(v) for v in values)), []
        raise NotCovered(f"{call}: an operand of type {type(other).__name__} and shape {values.shape}, write it to a layer and take an Array of that")

    def _apply(self, name: str, *others: Any) -> Array:
        args = [self.node]
        owners = list(self._owners)
        for other in others:
            node, held = self._operand(other, name)
            args.append(node)
            owners += held
        made = Array._of(self.document, _Op(name, tuple(args)), self._size)
        made._owners = owners
        return made

    def _swapped(self, name: str, other: Any) -> Array:
        node, held = self._operand(other, name)
        made = Array._of(self.document, _Op(name, (node, self.node)), self._size)
        made._owners = held + self._owners
        return made

    def __add__(self, other: Any) -> Array:
        return self._apply("add", other)

    def __radd__(self, other: Any) -> Array:
        return self._swapped("add", other)

    def __sub__(self, other: Any) -> Array:
        return self._apply("subtract", other)

    def __rsub__(self, other: Any) -> Array:
        return self._swapped("subtract", other)

    def __mul__(self, other: Any) -> Array:
        return self._apply("multiply", other)

    def __rmul__(self, other: Any) -> Array:
        return self._swapped("multiply", other)

    def __truediv__(self, other: Any) -> Array:
        return self._apply("divide", other)

    def __rtruediv__(self, other: Any) -> Array:
        return self._swapped("divide", other)

    def __pow__(self, other: Any) -> Array:
        return self._apply("power", other)

    def __rpow__(self, other: Any) -> Array:
        return self._swapped("power", other)

    def __neg__(self) -> Array:
        return self._apply("negative")

    def __pos__(self) -> Array:
        return self

    def __abs__(self) -> Array:
        return self._apply("absolute")

    def __lt__(self, other: Any) -> Array:
        return self._apply("less", other)

    def __le__(self, other: Any) -> Array:
        return self._apply("less_equal", other)

    def __gt__(self, other: Any) -> Array:
        return self._apply("greater", other)

    def __ge__(self, other: Any) -> Array:
        return self._apply("greater_equal", other)

    def __eq__(self, other: Any) -> Array:  # type: ignore[override]
        return self._apply("equal", other)

    def __ne__(self, other: Any) -> Array:  # type: ignore[override]
        return self._apply("not_equal", other)

    __hash__ = None  # type: ignore[assignment]

    def __bool__(self) -> bool:
        raise NotCovered("bool(Array): an array has no one truth value, reduce it first")

    def __iter__(self) -> Any:
        raise NotCovered("iter(Array): read it with numpy.asarray first")

    def clip(self, lo: Any = None, hi: Any = None) -> Array:
        """NumPy's clip: the maximum with *lo*, then the minimum with *hi*."""
        low = -math.inf if lo is None else lo
        high = math.inf if hi is None else hi
        return self._apply("clip", low, high)

    def __getitem__(self, key: Any) -> Array:
        parts = key if isinstance(key, tuple) else (key,)
        if sum(part is Ellipsis for part in parts) == 1:
            at = next(i for i, part in enumerate(parts) if part is Ellipsis)
            parts = parts[:at] + (slice(None),) * (4 - len(parts)) + parts[at + 1 :]
        if len(parts) == 3 and isinstance(parts[2], slice) and parts[2].indices(4) == (0, 4, 1):
            parts = parts[:2]
        if len(parts) > 2 or not all(isinstance(p, slice) for p in parts):
            raise NotCovered(f"Array[{key!r}]: only whole rectangles, a slice of the rows and one of the columns")
        rows = parts[0] if parts else slice(None)
        cols = parts[1] if len(parts) > 1 else slice(None)
        y0, y1, ys = rows.indices(self._size[0])
        x0, x1, xs = cols.indices(self._size[1])
        if ys != 1 or xs != 1:
            raise NotCovered(f"Array[{key!r}]: a slice with a step")
        if y1 <= y0 or x1 <= x0:
            raise ValueError(f"Array[{key!r}] is empty")
        made = Array._of(self.document, _moved(self.node, x0, y0, x1 - x0, y1 - y0, {}), (y1 - y0, x1 - x0))
        made._owners = list(self._owners)
        return made

    # -- NumPy's protocols --------------------------------------------------------

    def __array_ufunc__(self, ufunc: np.ufunc, method: str, *inputs: Any, **kwargs: Any) -> Array:
        name = _UFUNC_NAMES.get(ufunc.__name__, ufunc.__name__)
        call = f"numpy.{ufunc.__name__}" + ("" if method == "__call__" else f".{method}")
        if method != "__call__" or kwargs or not (name in _BINARY or name in _UNARY):
            raise NotCovered(call + (f" with {sorted(kwargs)}" if kwargs else ""))
        anchor = next(value for value in inputs if isinstance(value, Array))
        if len(inputs) == 1:
            return anchor._apply(name)
        if inputs[0] is anchor:
            return anchor._apply(name, inputs[1])
        return anchor._swapped(name, inputs[0])

    def __array_function__(self, func: Any, types: Any, args: tuple, kwargs: dict) -> Any:
        name = func.__name__
        if name == "where" and len(args) == 3 and not kwargs:
            return where(*args)
        if name == "clip" and isinstance(args[0], Array) and not kwargs.keys() - {"a_min", "a_max", "min", "max"}:
            lo = args[1] if len(args) > 1 else kwargs.get("a_min", kwargs.get("min"))
            hi = args[2] if len(args) > 2 else kwargs.get("a_max", kwargs.get("max"))
            return args[0].clip(lo, hi)
        wanted = {"amin": "min", "amax": "max"}.get(name, name)
        if wanted in REDUCTIONS and len(args) == 1 and not kwargs.keys() - {"axis"}:
            return getattr(args[0], wanted)(axis=kwargs.get("axis"))
        if name == "shape" and len(args) == 1:
            return args[0].shape
        raise NotCovered(f"numpy.{name}")

    def __array__(self, dtype: Any = None, copy: Any = None) -> np.ndarray:
        pixels = self._read()
        return pixels if dtype is None else pixels.astype(dtype)

    # -- sending ---------------------------------------------------------------------

    def evaluate(self) -> Array:
        """The expression run as one kernel into a scratch layer, an Array of that."""
        if isinstance(self.node, _Leaf):
            return self
        first, *_ = _nodes(self.node)[0]
        source, params, leaves = kernel_source(self.node, first)
        scratch = _scratch(self.document)
        name = scratch.take()
        step: dict = {
            "source": source,
            "name": KERNEL,
            "layer": first.name,
            "rect": first.rect,
            "into": name,
            "params": params,
        }
        if len(leaves) > 1:
            step["inputs"] = {
                f"src{i}": {"layer": leaf.name, "at": leaf.rect[:2]} for i, leaf in enumerate(leaves) if i > 0
            }
        try:
            said = self.document.door.verdict({"kernel": step})
        except Exception:
            scratch.give_back(name)
            raise
        if not isinstance(said, dict) or not said.get("ok", False):
            scratch.give_back(name)
            raise sara.SaraError(f"{sara.VERDICT}kernel {said}")
        token = _Token()
        weakref.finalize(token, scratch.give_back, name)
        return Array._of(self.document, _Leaf(name, first.rect), self._size, token)

    def _read(self) -> np.ndarray:
        leaf = self.evaluate()
        pixels = sara.Layer(self.document, leaf.node.name).read(leaf.node.rect)
        del leaf
        return pixels

    def show(self) -> sara.Picture:
        """The array tone-mapped to eight bits for the screen, as `Layer.show()` draws one."""
        return sara.Picture(sara.png_bytes(sara.tone_map(self._read())))

    def _reduce(self, op: str, axis: Any) -> Any:
        whole = axis is None
        if not whole and tuple(sorted(axis if isinstance(axis, tuple) else (axis,))) != (0, 1):
            raise NotCovered(f"Array.{op}(axis={axis!r}): only the whole array or axis=(0, 1)")
        leaf = self.evaluate()
        said = self.document.door.verdict(
            {"reduce": {"layer": leaf.node.name, "rect": leaf.node.rect, "ops": ["sum" if op == "mean" else op]}}
        )
        if not isinstance(said, dict):
            raise sara.SaraError(f"{sara.VERDICT}reduce {said}")
        texels = int(said["texels"])
        if op == "mean":
            channels = np.array(said["sum"], np.float64) / texels
            return np.float32(channels.mean()) if whole else channels.astype(np.float32)
        channels = np.array(said[op], np.float64)
        if not whole:
            return channels.astype(np.float32)
        return np.float32({"sum": channels.sum, "min": channels.min, "max": channels.max}[op]())

    def sum(self, axis: Any = None) -> Any:
        return self._reduce("sum", axis)

    def mean(self, axis: Any = None) -> Any:
        return self._reduce("mean", axis)

    def min(self, axis: Any = None) -> Any:
        return self._reduce("min", axis)

    def max(self, axis: Any = None) -> Any:
        return self._reduce("max", axis)


class _Token:
    """What a result Array holds, so its scratch layer is freed with its last reader."""


def _moved(node: Any, x: int, y: int, w: int, h: int, seen: dict) -> Any:
    """*node* with every leaf's rectangle cut to `[x, y, w, h]` of itself."""
    if id(node) in seen:
        return seen[id(node)]
    if isinstance(node, _Leaf):
        moved: Any = _Leaf(node.name, [node.rect[0] + x, node.rect[1] + y, w, h])
    elif isinstance(node, _Const):
        moved = node
    else:
        moved = _Op(node.name, tuple(_moved(arg, x, y, w, h, seen) for arg in node.args))
    seen[id(node)] = moved
    return moved


def where(condition: Array, x: Any, y: Any) -> Array:
    """*x* where *condition* is not zero and *y* where it is, NumPy's `where`."""
    if not isinstance(condition, Array):
        raise NotCovered("where: a condition that is not an Array")
    return condition._apply("where", x, y)
