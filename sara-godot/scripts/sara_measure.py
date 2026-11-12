"""How fast a kernel is and how far a layer is from an array, `sara.bench` and `sara.check`.

    import sara
    doc, layer, a = sara.init()
    sara.bench(doc.layer("cells"))     # the medians of the GPU time and the round trip, printed
    sara.check(layer, mine)            # the largest difference and the share past the tolerance

`sara.py`'s `bench` and `check` are these two calls, and `sara.Timing` and
`sara.Difference` the answers they give, kept in a file of their own because
they read the client and nothing in it reads them. `bench` reruns the `kernel`
step the document kept, `check` reads the layer and compares on the CPU.
Nothing outside the standard library and NumPy but `sara` itself, for its
layers and its error, the way `sara_documents.py` imports it.
"""

from __future__ import annotations

import statistics
from typing import NamedTuple

import numpy as np

import sara


class Timing(NamedTuple):
    """A kernel's GPU time, its dispatch alone, and the round trip Python saw, in milliseconds."""

    gpu_ms: float | None
    round_trip_ms: float

    def line(self, unknown: str = "") -> str:
        """The two as a cell shows them, `GPU 0.21 ms, round trip 38 ms`, with *unknown*, the app's
        reason, where there is no GPU time."""
        gpu = f"GPU {_ms(self.gpu_ms)} ms" if self.gpu_ms is not None else f"GPU time not known ({unknown})"
        return f"{gpu}, round trip {self.round_trip_ms:.0f} ms"


def _ms(value: float) -> str:
    """Two decimals, and two figures for a kernel under a tenth of a millisecond."""
    return f"{value:.2f}" if value >= 0.1 else f"{value:.2g}"


def bench(layer: sara.Layer | str | int, runs: int = 20) -> Timing:
    """Reruns the kernel that last wrote *layer*, a Layer or its name or index, with its values, *runs*
    times, a request each so each has its round trip, prints the medians of both times and answers them.
    The reruns write what the kernel wrote already, so they leave no undo step. A kernel that read the
    layer it wrote changes it each time, and its reruns are one step called "Bench <name>"."""
    layer = sara.layer_of(layer)
    # A kernel is kept under the name it wrote, so an index is looked up in the stack.
    name = layer.key if isinstance(layer.key, str) else layer._entry()["name"]
    step = layer.document.kernels.get(name)
    if step is None:
        raise sara.SaraError(f"no kernel has written {name!r} since connect(), run its cell and name its layer")
    in_place = name in layer.document.in_place
    said = []
    for n in range(max(1, int(runs))):
        # An in-place rerun records once, the first, and the step undoes and redoes all of them.
        record = dict(step, step=f"Bench {step['name']}") if in_place and n == 0 else dict(step, history=False)
        said.append(layer.document.kernel(record))
    gpu = [s["gpu_ms"] for s in said if s.get("gpu_ms") is not None]
    medians = Timing(statistics.median(gpu) if gpu else None, statistics.median(s["round_trip_ms"] for s in said))
    print(f"{medians.line(said[-1].get('gpu_unknown', ''))} (median of {len(said)})")
    return medians


class Difference(NamedTuple):
    """How far a layer is from an array: the largest difference of a channel, the pixel it is in as
    `(x, y)`, None where nothing differs, and the per cent of pixels past the tolerance."""

    largest: float
    where: tuple[int, int] | None
    percent: float


def check(layer: sara.Layer | str | int, array: np.ndarray, tolerance: float = 0.01) -> Difference:
    """Reads *layer*, a Layer or its name or index, and prints how far it is from *array*, `(h, w, 4)`, `(h, w, 3)` for the colour
    alone or `(h, w)` for a grey, and answers the same. Feedback rather than a grade, so it never
    raises on a difference: a pixel on a level boundary that rounds the other way on the GPU is a
    whole level off, and the share past *tolerance* says that it is one pixel in thousands."""
    mine = np.asarray(array, dtype=np.float32)
    if mine.ndim == 2:
        mine = mine[..., None]
    pixels = sara.layer_of(layer).read()
    if mine.ndim != 3 or mine.shape[:2] != pixels.shape[:2] or mine.shape[2] not in (1, 3, 4):
        raise ValueError(f"the layer is {pixels.shape[1]} by {pixels.shape[0]}, the array's shape {np.shape(array)}")
    channels = 3 if mine.shape[2] == 1 else mine.shape[2]
    # A NaN on either side is as far as can be, never quietly equal.
    apart = np.nan_to_num(np.abs(pixels[..., :channels] - mine), nan=np.inf).max(axis=2)
    largest = float(apart.max())
    y, x = np.unravel_index(int(apart.argmax()), apart.shape)
    found = Difference(largest, (int(x), int(y)) if largest > 0 else None, 100.0 * float(np.mean(apart > tolerance)))
    at = f" at x {found.where[0]}, y {found.where[1]}" if found.where else ""
    said = f"largest difference {_figures(largest)}{at}, {_figures(found.percent)} %"
    print(f"{said} of pixels differ by more than {_figures(tolerance)}")
    return found


def _figures(value: float) -> str:
    """Two significant figures with no exponent, so one pixel in two million reads `0.000048 %`.
    A value of 1 or more keeps every whole digit, because 254 rounded to two figures reads 250."""
    if np.isfinite(value) and abs(value) >= 1:
        return np.format_float_positional(value, precision=max(2 - len(str(int(abs(value)))), 0), trim="-")
    return np.format_float_positional(value, precision=2, fractional=False, trim="-")
