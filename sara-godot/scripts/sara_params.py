"""The `PARAMS` dict of a live NumPy function, read the way the Krita plugin template reads it.

    PARAMS = {
        "amount": (1.0, 0.0, 1.0),             # a slider: (default, min, max[, step])
        "steps": (4, 1, 8),                    # all whole numbers: a whole-number slider
        "tint": "#ff8c32",                     # a colour, "#rrggbbaa" adds an alpha
        "mode": ["Multiply", "Screen"],        # a drop-down, the first label the default
        "invert": False,                       # a checkbox
        "weights": [[0, 1, 0], [1, -4, 1], [0, 1, 0]],   # an n by n grid of numbers
    }

One block of this runs in `sara.live` and in the plugin unchanged, so the dict
imports nothing and the value's kind decides the widget. The courses session
built the template outside Sara and sent the format, and this reads it as it
is: the same five kinds in the same order, `bool` first because `True` is an
`int`, and the same refusals. `parse` answers one `Param` per key in the dict's
order, and `Param.value` turns what a widget holds into what `apply` gets.

NumPy and the standard library only, with no widgets, so it is copied beside
`sara.py` as it is and the tests run without a notebook.
"""

from __future__ import annotations

import math
import re
from numbers import Integral, Real
from typing import Any, NamedTuple

import numpy as np

BOOL, INT, FLOAT, COLOR, CHOICE, MATRIX = "bool", "int", "float", "color", "choice", "matrix"

FORMS = (
    "a bool (a checkbox), "
    "a tuple (default, min, max) or (default, min, max, step) of numbers (a slider), "
    'a "#rrggbb" or "#rrggbbaa" string (a colour), '
    "a non-empty list of str (a drop-down), "
    "or a non-empty list of n lists of n numbers (an n by n grid)"
)
_COLOR = re.compile(r"^#(?:[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$")


class ParamError(ValueError):
    """A `PARAMS` entry that is none of the five kinds, naming the entry and the forms there are."""


class Param(NamedTuple):
    """One entry of `PARAMS`: what widget it is, its default and the limits that widget takes.

    `default` is the number, the flag, the `"#rrggbb[aa]"` text, the label or the rows of numbers as
    written. `low`, `high` and `step` are set for a slider only, `labels` for a drop-down only, and
    `size` is a grid's n.
    """

    name: str
    kind: str
    default: Any
    low: float | None = None
    high: float | None = None
    step: float | None = None
    labels: tuple[str, ...] = ()
    size: int = 0

    @property
    def alpha(self) -> bool:
        """Whether a colour was written with its alpha, the eight-digit form."""
        return self.kind == COLOR and len(self.default) == 9

    def initial(self) -> Any:
        """What `apply` gets for this entry before any widget moves."""
        return self.value(self.default)

    def value(self, raw: Any) -> Any:
        """What `apply` gets for *raw*, the value the entry's widget holds.

        A bool, an `int` or a `float` as itself, a colour's `"#rrggbb[aa]"` text as a tuple of three or four
        floats from 0 to 1 (the sRGB numbers the picker shows, alpha last as written, no linear conversion), a
        drop-down's label as the label, and rows of numbers as a new `float32` array of shape `(n, n)`, so
        `apply` may change what it is handed.
        """
        if self.kind == BOOL:
            return bool(raw)
        if self.kind == INT:
            return int(raw)
        if self.kind == FLOAT:
            return float(raw)
        if self.kind == COLOR:
            return color(raw)
        if self.kind == CHOICE:
            return str(raw)
        return np.array(raw, dtype=np.float32).reshape(self.size, self.size)


def color(text: str) -> tuple[float, ...]:
    """The three or four channels of `"#rrggbb"` or `"#rrggbbaa"` as floats from 0 to 1, alpha last."""
    if not isinstance(text, str) or _COLOR.match(text) is None:
        raise ParamError(f'{text!r} is not "#rrggbb" or "#rrggbbaa"')
    return tuple(int(text[at : at + 2], 16) / 255.0 for at in range(1, len(text), 2))


def parse(params: dict) -> list[Param]:
    """One `Param` for each key of *params*, in the dict's order, or a `ParamError` for the first that is refused."""
    if not isinstance(params, dict):
        raise ParamError(f"PARAMS is a dict of name to value, not {type(params).__name__}")
    return [_entry(name, value) for name, value in params.items()]


def _refuse(name: object, why: str) -> ParamError:
    return ParamError(f"parameter {name!r}: {why}. A parameter is {FORMS}")


def _number(value: object) -> bool:
    """Whether *value* is a real number `PARAMS` may hold: not a bool, not NaN or infinite."""
    return isinstance(value, Real) and not isinstance(value, (bool, np.bool_)) and math.isfinite(value)


def _entry(name: object, value: Any) -> Param:
    if not isinstance(name, str) or not name.isidentifier():
        raise ParamError(f"parameter {name!r}: a name is a Python identifier, because `apply` gets it as a keyword")
    # A bool is checked first, because True is an int.
    if isinstance(value, bool):
        return Param(name, BOOL, value)
    if isinstance(value, tuple):
        return _slider(name, value)
    if isinstance(value, str):
        if _COLOR.match(value) is None:
            raise _refuse(name, f'{value!r} is not "#rrggbb" or "#rrggbbaa"')
        return Param(name, COLOR, value)
    if isinstance(value, list):
        if not value:
            raise _refuse(name, "the list is empty")
        if all(isinstance(item, str) for item in value):
            return Param(name, CHOICE, value[0], labels=tuple(value))
        if all(isinstance(item, (list, tuple)) for item in value):
            return _matrix(name, value)
        raise _refuse(name, "a list holds only str, or only lists of numbers")
    raise _refuse(name, f"{type(value).__name__} {value!r} is none of them")


def _slider(name: str, spec: tuple) -> Param:
    if len(spec) not in (3, 4):
        raise _refuse(name, f"a slider tuple holds 3 or 4 numbers, this holds {len(spec)}")
    if not all(_number(item) for item in spec):
        raise _refuse(name, f"a slider tuple holds numbers only, {spec!r} does not")
    whole = all(isinstance(item, Integral) for item in spec)
    default, low, high = spec[:3]
    step = spec[3] if len(spec) == 4 else 1 if whole else (high - low) / 100.0
    if low >= high:
        raise _refuse(name, f"the minimum {low} is not below the maximum {high}")
    if not low <= default <= high:
        raise _refuse(name, f"the default {default} is outside {low} to {high}")
    if step <= 0:
        raise _refuse(name, f"the step {step} is not above 0")
    cast = int if whole else float
    return Param(name, INT if whole else FLOAT, cast(default), cast(low), cast(high), cast(step))


def _matrix(name: str, rows: list) -> Param:
    size = len(rows)
    if any(len(row) != size for row in rows):
        lengths = [len(row) for row in rows]
        raise _refuse(name, f"a grid is square, this has {size} rows of lengths {lengths}")
    if not all(_number(item) for row in rows for item in row):
        raise _refuse(name, "a grid holds numbers only")
    return Param(name, MATRIX, tuple(tuple(float(item) for item in row) for row in rows), size=size)
