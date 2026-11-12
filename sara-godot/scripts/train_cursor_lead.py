#!/usr/bin/env python3
"""Fit the learned cursor lead from stroke recordings and write its weights.

    python3 scripts/train_cursor_lead.py
    python3 scripts/train_cursor_lead.py --recordings <folder of recordings> --dry-run

The recordings are what `SaStrokeRecorder` writes, one JSON line per pointer
event, and they stay in the review folder because they are a painter's own hand.
Every stroke, the readings between a pen down and the pen up, is resampled
onto an even grid, because the events arrive in bursts per frame and a model
fed raw intervals learns the frame loop rather than the hand. For every grid
point the target is where the pen is one horizon later, and the input is the
last `TAPS` displacements and the distance from the pen to each of the four
edges of the canvas view, clipped at `EDGE_HORIZON` and scaled to one, because a
hand near an edge shortens, turns back and stops. One matrix per horizon, fitted by least squares on
eighty percent of the strokes and scored on the rest, so the numbers printed
are held-out numbers and never the fit's own.

The pen's pressure and tilt are inputs too, because a hand pressing hard
moves differently from one skimming.
Both are the plain numbers the recording holds, at the newest reading. The
pressure enters as itself and times each displacement, so a row's gains move
with how hard the pen presses, and the tilt as its two components, across and
down. Each is fitted beside the positions alone and kept only where it beats
them by `MIN_GAIN` at every horizon on the held-out strokes. The report says
which were kept and why the others were not, and the weights file names the
inputs its rows read.

Three baselines are scored beside it on the same held-out strokes, all in
logical pixels rms: holding still, constant velocity from the last
displacement, and the window fit Sara draws today, a least-squares slope over
the last tenth of a second. The weights already in the weights file are scored
too, the model being replaced, overall and by what the hand was doing:
straight, an arc, a corner or a reversal. The linear lead ships only if it
beats the window fit and the shipped weights at every horizon, and is no worse
than the shipped weights on corners and reversals, and the script exits 1
rather than writing a weights file that would draw a worse ring.

The samples within a horizon of a stroke's last point are a class of their
own, `end`, whose target is that last point, since the pen stopped there. They
stay out of the overall numbers. The report prints their error and how far the
lead went past the last point along the stroke's final direction, and the
script refuses weights whose lead goes further past it than the window fit
does, or the shipped weights, by more than `OVERSHOOT_SHARE` of theirs and
`OVERSHOOT_SLACK`.

The output is `ui/canvas/sa_cursor_lead_weights.gd`, a GDScript with the horizons, the
inputs its rows read and one row of weights per horizon, read by
`SaCursorPrediction.learned_lead`. Nothing in it is edited by hand.
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass, field
from datetime import date
from pathlib import Path

import numpy as np


HERE = Path(__file__).resolve().parent
DEFAULT_RECORDINGS = Path("strokes")
DEFAULT_OUT = HERE.parent / "ui" / "canvas" / "sa_cursor_lead_weights.gd"

# The grid the displacements are read on. Twice a common screen rate, so a
# frame at 60 hertz is two steps and the shortest horizon below is one.
GRID_HZ = 120.0
# Displacements before the newest reading that feed the matrix. Four is a
# thirtieth of a second of hand, which the first fit found enough: eight
# scored the same to a tenth of a pixel and costs twice the window.
TAPS = 4
# The horizons a matrix is fitted for, in milliseconds. 8 is half a frame at
# 60 hertz, 16 a frame, 33 two frames, and 50 the longest number anyone has
# written into cursor_prediction_ms. The ring interpolates between them.
HORIZONS_MS = (8, 16, 33, 50)
# The window Sara's own fit reads velocity over, in seconds, from
# SaCursorPrediction.WINDOW_SECONDS.
WINDOW_SECONDS = 0.10
# The four edge distances a row reads after the displacements, left, top,
# right and bottom, and the distance in logical pixels past which an edge is
# far, from SaCursorPrediction.EDGE_COUNT and EDGE_HORIZON.
EDGES = 4
EDGE_HORIZON = 300.0
# How a held-out sample is classed, by the turn between the tenth of a second
# before it and the tenth after, in degrees, and below what speed in logical
# pixels a second the hand is at rest, from SaCursorPrediction.REST_SPEED.
STRAIGHT_BELOW = 20.0
ARC_BELOW = 60.0
CORNER_BELOW = 150.0
REST_SPEED = 30.0
CLASSES = ("straight", "arc", "corner", "reversal")
# The class of the samples within a horizon of a stroke's last point, scored
# on their own and never among the overall numbers, because their target is
# where the pen stopped and not where it was a horizon later.
END_CLASS = "end"
# How far past a stroke's last point, along its final direction, a lead may
# go before it overshoots, in logical pixels: the lead may not go further past
# than the window fit does on the same samples, nor than the shipped weights,
# by more than this share of theirs and this slack, which is under a pixel of
# noise. A fit is noisy at the shortest horizon, where a stroke end is one grid
# point, so a share is read and not a bare pixel count.
OVERSHOOT_SHARE = 0.25
OVERSHOOT_SLACK = 0.1
# The classes a new fit may not lose on against the shipped weights, the two
# the spec's bar names for the edges.
GUARDED = ("corner", "reversal")
# The groups of inputs a row can read, in the order their columns stand. The
# displacements are the last TAPS steps, x then y each, the edges the four
# edge distances, the pressure the newest reading's pressure followed by that
# pressure times each displacement number, and the tilt the newest reading's
# tilt across and down, the `tx` and `ty` the recorder writes.
INPUTS = ("displacements", "edges", "pressure", "tilt")
# The inputs every fit reads, where the pen has been and where it stands in
# the view.
POSITIONS = ("displacements", "edges")
# The inputs a fit reads only where they win on the held-out strokes.
OPTIONAL = ("pressure", "tilt")
# The tilt's two numbers, and how many of each optional input's first columns
# are the plain numbers the recording holds rather than products of them.
TILT = 2
PLAIN = {"pressure": 1, "tilt": TILT}
# How much lower than the positions alone an optional input's held-out rms
# has to be, at every horizon, for its rows to be written. On strokes whose
# pressure is noise the rows with it land within a few thousandths of the rows
# without, either side, and a gain the next split takes back is not worth the
# arithmetic the ring does every frame.
MIN_GAIN = 0.01
# Strokes shorter than this many events are a tap, not a gesture.
MIN_EVENTS = 10
# The share of strokes trained on. The rest score.
TRAIN_SHARE = 0.8


@dataclass
class Fit:
    """One horizon's matrix and what it scored on held-out strokes."""

    horizon_ms: int
    weights: np.ndarray
    hold: float
    constant_velocity: float
    window_fit: float
    linear: float
    samples: int
    # The weights in the file today on the same strokes, nan when there are none.
    shipped: float = float("nan")
    # Per class, the linear lead's rms, the shipped weights' and the count.
    by_class: dict = field(default_factory=dict)
    # The mean distance past a stroke's last point along its final direction,
    # for the linear lead, the window fit and the shipped weights, in logical
    # pixels, and how many stroke end samples they were read over.
    overshoot: tuple = (float("nan"), float("nan"), float("nan"), 0)
    # The rows over the positions alone, and over the positions and each of
    # `OPTIONAL` by its name, on the same held-out strokes.
    positions: float = float("nan")
    beside: dict = field(default_factory=dict)


@dataclass
class Samples:
    """What `dataset` reads off the strokes, one row per grid point."""

    inputs: np.ndarray
    targets: np.ndarray
    constant: np.ndarray
    window: np.ndarray
    classes: np.ndarray
    # Per sample the unit vector the stroke was travelling in at its last
    # point, a row of nought except in the stroke end class.
    finals: np.ndarray


@dataclass
class Result:
    fits: list = field(default_factory=list)
    strokes: int = 0
    events: int = 0
    files: int = 0
    # The inputs the rows read, in the order of `INPUTS`.
    inputs: tuple = POSITIONS
    # Per optional input, the sentence that says why it was kept or left out.
    verdicts: dict = field(default_factory=dict)

    def beats_the_window_fit(self) -> bool:
        return all(f.linear < f.window_fit for f in self.fits)

    def beats_the_shipped_weights(self) -> bool:
        """Better overall at every horizon, and no worse on a guarded class.
        True where nothing is shipped to compare against."""
        for f in self.fits:
            if np.isnan(f.shipped):
                continue
            if f.linear >= f.shipped:
                return False
            for name in GUARDED:
                linear, shipped, _ = f.by_class.get(name, (float("nan"), float("nan"), 0))
                if not np.isnan(shipped) and linear > shipped:
                    return False
        return True

    def stops_at_the_end(self) -> bool:
        """No fit leads further past a stroke's last point than the window fit
        does, or the shipped weights where there are any, by more than
        `OVERSHOOT_SHARE` of theirs and `OVERSHOOT_SLACK`."""
        for f in self.fits:
            linear, window, shipped, count = f.overshoot
            if count == 0:
                continue
            if linear > window * (1.0 + OVERSHOOT_SHARE) + OVERSHOOT_SLACK:
                return False
            if not np.isnan(shipped) and linear > shipped * (1.0 + OVERSHOOT_SHARE) + OVERSHOOT_SLACK:
                return False
        return True


def read_recording(path: Path) -> list:
    """The strokes of one recording, each an array of (t seconds, x, y, p)
    followed by the four edge distances of `edge_features` and the tilt
    across and down.

    Format 1 and format 2 both: the `z` lines format 2 adds carry the view
    transform, which the lead has no use for, and are skipped. A reading with
    no `v`, the canvas view's rectangle, reads as the middle of a view, and
    one with no `tx` or `ty` as a pen held upright.
    """
    strokes: list = []
    current = None
    with open(path, encoding="utf-8") as handle:
        first = True
        for raw in handle:
            raw = raw.strip()
            if not raw:
                continue
            row = json.loads(raw)
            if first:
                first = False
                if "k" not in row:
                    continue
            kind = row.get("k")
            if kind == "d" and row.get("btn") == 1:
                current = []
            elif kind == "u" and row.get("btn") == 1:
                if current is not None and len(current) >= MIN_EVENTS:
                    strokes.append(np.array(current, dtype=float))
                current = None
            elif kind == "m" and current is not None:
                current.append(
                    (row["t"] / 1e6, row["x"], row["y"], row.get("p", 0.0))
                    + edge_features(row["x"], row["y"], row.get("v"))
                    + (row.get("tx", 0.0), row.get("ty", 0.0))
                )
    return strokes


def edge_features(x: float, y: float, view) -> tuple:
    """The distances from (x, y) to the left, top, right and bottom edges of
    *view*, `[x, y, width, height]`, clipped to nothing and to `EDGE_HORIZON`
    and scaled to one, as `SaCursorPrediction.edge_distances` computes them.
    No view, or an empty one, is the middle of a view."""
    if not view or len(view) < 4 or view[2] <= 0.0 or view[3] <= 0.0:
        return (1.0,) * EDGES
    gaps = (x - view[0], y - view[1], view[0] + view[2] - x, view[1] + view[3] - y)
    return tuple(min(max(g / EDGE_HORIZON, 0.0), 1.0) for g in gaps)


def read_folder(folder: Path) -> tuple:
    strokes: list = []
    files = 0
    for path in sorted(folder.glob("*.jsonl")):
        files += 1
        strokes.extend(read_recording(path))
    return strokes, files


# Where a grid row of `resample` holds the edges, the pressure and the tilt.
GRID_EDGES = slice(3, 3 + EDGES)
GRID_PRESSURE = 3 + EDGES
GRID_TILT = slice(4 + EDGES, 4 + EDGES + TILT)


def resample(stroke: np.ndarray, hz: float = GRID_HZ) -> np.ndarray:
    """The stroke on an even grid, as rows of (t, x, y), the four edge
    distances, the pressure and the tilt across and down. What the stroke does
    not carry reads as a reading in the middle of a view, with no pressure and
    the pen upright."""
    t = np.arange(stroke[0, 0], stroke[-1, 0], 1.0 / hz)

    def column(c: int, missing: float) -> np.ndarray:
        if stroke.shape[1] > c:
            return np.interp(t, stroke[:, 0], stroke[:, c])
        return np.full(len(t), missing)

    edges = [column(c, 1.0) for c in range(4, 4 + EDGES)]
    tilt = [column(c, 0.0) for c in range(4 + EDGES, 4 + EDGES + TILT)]
    return np.column_stack([t, column(1, 0.0), column(2, 0.0)] + edges + [column(3, 0.0)] + tilt)


def input_widths(taps: int = TAPS) -> dict:
    """How many columns each of `INPUTS` takes in a row."""
    return {"displacements": 2 * taps, "edges": EDGES, "pressure": 1 + 2 * taps, "tilt": TILT}


def columns(names, taps: int = TAPS) -> np.ndarray:
    """Where the inputs *names* stand among the columns of a row that reads
    every one of `INPUTS`, in the order of `INPUTS` whatever the order asked."""
    widths = input_widths(taps)
    out: list = []
    start = 0
    for name in INPUTS:
        if name in names:
            out.extend(range(start, start + widths[name]))
        start += widths[name]
    return np.array(out, dtype=int)


def ordered(names) -> tuple:
    """*names* in the order of `INPUTS`."""
    return tuple(name for name in INPUTS if name in names)


def inputs_for_width(width: int, taps: int = TAPS) -> list:
    """The inputs a row of *width* inputs reads when its file does not say:
    the positions alone, with the edges or without, from before the files
    named their inputs. Empty for a width no such file had."""
    if width == 2 * taps:
        return ["displacements"]
    if width == 2 * taps + EDGES:
        return list(POSITIONS)
    return []


def window_slope(points: np.ndarray, hz: float) -> np.ndarray:
    """Least-squares velocity over the grid points in the window, per second,
    the same arithmetic as `SaCursorPrediction._fitted`."""
    count = len(points)
    times = np.arange(count) / hz
    times = times - times.mean()
    spread = float((times * times).sum())
    if spread <= 0.0:
        return np.zeros(2)
    centred = points - points.mean(axis=0)
    return (centred * times[:, None]).sum(axis=0) / spread


def turn_class(before: np.ndarray, after: np.ndarray) -> str:
    """What the hand was doing at a sample, from its travel over the window
    before and the window after: "rest", or one of `CLASSES` by the turn."""
    if np.linalg.norm(before) / WINDOW_SECONDS < REST_SPEED or np.linalg.norm(after) <= 0.0:
        return "rest"
    cosine = float(before @ after) / float(np.linalg.norm(before) * np.linalg.norm(after))
    turn = np.degrees(np.arccos(min(max(cosine, -1.0), 1.0)))
    if turn < STRAIGHT_BELOW:
        return "straight"
    if turn < ARC_BELOW:
        return "arc"
    if turn < CORNER_BELOW:
        return "corner"
    return "reversal"


def dataset(
    strokes: list, horizon_s: float, hz: float = GRID_HZ, taps: int = TAPS, inputs=POSITIONS, ends: bool = False
) -> Samples:
    """Inputs, targets, the two moving baselines' guesses and each sample's
    class, over every grid point of every stroke that has a full window behind
    it and a horizon ahead. A row holds the groups of `INPUTS` that *inputs*
    names, in that order: the last *taps* displacements, the four edge
    distances at the newest one, its pressure and that pressure times each
    displacement, and its tilt. With *ends* the grid points within a horizon of
    the stroke's last point follow, class `END_CLASS`, their target that last
    point, since the pen stopped there, and their `finals` the direction the
    stroke was going."""
    rows, targets, constant, window, classes, finals = [], [], [], [], [], []
    steps = max(1, int(round(horizon_s * hz)))
    window_points = max(2, int(round(WINDOW_SECONDS * hz)))
    names = ordered(inputs)
    for stroke in strokes:
        grid = resample(stroke, hz)
        if len(grid) < window_points + steps + 1:
            continue
        points = grid[:, 1:3]
        displacements = np.diff(points, axis=0)
        last = len(points) - 1
        heading = points[last] - points[last - window_points]
        heading = heading / np.linalg.norm(heading) if np.linalg.norm(heading) > 1e-9 else np.zeros(2)
        for i in range(window_points, last + 1 if ends else last + 1 - steps):
            ending = i + steps > last
            moved = displacements[i - taps:i].ravel()
            parts = {
                "displacements": moved,
                "edges": grid[i, GRID_EDGES],
                "pressure": np.concatenate([[grid[i, GRID_PRESSURE]], grid[i, GRID_PRESSURE] * moved]),
                "tilt": grid[i, GRID_TILT],
            }
            rows.append(np.concatenate([parts[name] for name in names]))
            targets.append(points[min(i + steps, last)] - points[i])
            constant.append(displacements[i - 1] * steps)
            window.append(window_slope(points[i - window_points + 1:i + 1], hz) * horizon_s)
            ahead = points[min(i + window_points, len(points) - 1)] - points[i]
            classes.append(END_CLASS if ending else turn_class(points[i] - points[i - window_points], ahead))
            finals.append(heading if ending else np.zeros(2))
    return Samples(
        np.array(rows), np.array(targets), np.array(constant), np.array(window), np.array(classes), np.array(finals)
    )


def past_the_end(actual: np.ndarray, guess: np.ndarray, finals: np.ndarray) -> float:
    """The mean of how far *guess* lies beyond *actual*, the stroke's last
    point, along each sample's final direction, a guess short of the end
    counting nought, in logical pixels."""
    if len(actual) == 0:
        return float("nan")
    return float(np.maximum(((guess - actual) * finals).sum(axis=1), 0.0).mean())


def shipped_guess(rows: list, index: int, every: np.ndarray, names=None) -> np.ndarray | None:
    """What the weights file's row *index* guesses for *every*, a matrix of
    every one of `INPUTS`, reading the columns of the inputs *names* the file
    declares, or the ones its width says when it declares none. None when the
    file has no row this code can apply."""
    if not rows or index >= len(rows):
        return None
    row = np.array(rows[index], dtype=float)
    width = len(row) // 2 - 1
    names = list(names) if names else inputs_for_width(width)
    if not names or any(name not in INPUTS for name in names):
        return None
    used = every[:, columns(names)]
    if used.shape[1] != width:
        return None
    weights = np.column_stack([row[: width + 1], row[width + 1 :]])
    return with_bias(used) @ weights


def fit_rows(train_set: Samples, test: Samples, names) -> tuple:
    """The least-squares rows over the inputs *names* of *train_set*, and what
    they guess for *test*, both sets holding every one of `INPUTS`."""
    used = columns(names)
    weights, *_ = np.linalg.lstsq(with_bias(train_set.inputs[:, used]), train_set.targets, rcond=None)
    return weights, with_bias(test.inputs[:, used]) @ weights


def held_still(samples: Samples, name: str) -> bool:
    """Whether the plain numbers of the input *name* never move in *samples*,
    which hold every one of `INPUTS`. The pressure is read itself rather than
    its products, which move with the hand whatever the pen does."""
    plain = columns((name,))[: PLAIN[name]]
    return bool(np.all(np.ptp(samples.inputs[:, plain], axis=0) == 0.0))


def verdict(name: str, horizons_ms, positions: list, beside: list, still: bool) -> tuple:
    """Whether the optional input *name* is written, and the sentence the
    report prints for it. *positions* and *beside* are the held-out rms per
    horizon over the positions alone and over the positions and *name*."""
    if still:
        return False, "%s left out: the recording holds it still, so it is noise to the fit" % name
    for horizon_ms, without, with_it in zip(horizons_ms, positions, beside):
        if not with_it < without * (1.0 - MIN_GAIN):
            return False, (
                "%s left out: at %d ms the rows with it score %.3f against %.3f without it, short of the %g%% it has to win by at every horizon"
                % (name, horizon_ms, with_it, without, MIN_GAIN * 100)
            )
    gains = [100.0 * (1.0 - with_it / without) for without, with_it in zip(positions, beside)]
    return True, "%s kept: the rows with it beat the positions alone by %.1f%% to %.1f%% across the horizons" % (
        name,
        min(gains),
        max(gains),
    )


def with_bias(inputs: np.ndarray) -> np.ndarray:
    return np.column_stack([inputs, np.ones(len(inputs))])


def rmse(actual: np.ndarray, guess: np.ndarray) -> float:
    if len(actual) == 0:
        return float("nan")
    return float(np.sqrt(((actual - guess) ** 2).sum(axis=1).mean()))


def split(strokes: list, seed: int) -> tuple:
    order = np.random.default_rng(seed).permutation(len(strokes))
    cut = int(len(strokes) * TRAIN_SHARE)
    return [strokes[i] for i in order[:cut]], [strokes[i] for i in order[cut:]]


def train(strokes: list, seed: int = 1, horizons_ms=HORIZONS_MS, shipped: dict | None = None) -> Result:
    """One matrix per horizon over the positions alone, and over the positions
    and each of `OPTIONAL`, scored on held-out strokes. The optional inputs
    `verdict` keeps join the rows the result holds, which are scored beside
    the baselines and the *shipped* weights, `parse_weights_file`'s answer."""
    result = Result(strokes=len(strokes), events=sum(len(s) for s in strokes))
    training, held_out = split(strokes, seed)
    shipped_rows = (shipped or {}).get("rows", [])
    shipped_horizons = (shipped or {}).get("horizons", [])
    shipped_inputs = (shipped or {}).get("inputs")
    sets = []
    for horizon_ms in horizons_ms:
        horizon_s = horizon_ms / 1e3
        train_set = dataset(training, horizon_s, inputs=INPUTS)
        scored = dataset(held_out, horizon_s, inputs=INPUTS, ends=True)
        at_end = scored.classes == END_CLASS
        test = Samples(*(column[~at_end] for column in vars(scored).values()))
        end = Samples(*(column[at_end] for column in vars(scored).values()))
        if len(train_set.inputs) == 0 or len(test.inputs) == 0:
            raise SystemExit("not enough strokes to fit and to score a %d ms horizon" % horizon_ms)
        sets.append((horizon_ms, train_set, test, end))
    scores = {}
    for names in [POSITIONS] + [ordered(POSITIONS + (name,)) for name in OPTIONAL]:
        scores[names] = [rmse(test.targets, fit_rows(train_set, test, names)[1]) for _, train_set, test, _ in sets]
    kept = []
    for name in OPTIONAL:
        beside = scores[ordered(POSITIONS + (name,))]
        keep, result.verdicts[name] = verdict(name, horizons_ms, scores[POSITIONS], beside, held_still(sets[0][1], name))
        if keep:
            kept.append(name)
    result.inputs = ordered(POSITIONS + tuple(kept))
    for k, (horizon_ms, train_set, test, end) in enumerate(sets):
        weights, guess = fit_rows(train_set, test, result.inputs)
        index = shipped_horizons.index(float(horizon_ms)) if float(horizon_ms) in shipped_horizons else len(shipped_rows)
        before = shipped_guess(shipped_rows, index, test.inputs, shipped_inputs)
        before_end = shipped_guess(shipped_rows, index, end.inputs, shipped_inputs) if len(end.inputs) else None
        guess_end = with_bias(end.inputs[:, columns(result.inputs)]) @ weights if len(end.inputs) else end.targets
        fit = Fit(
            horizon_ms=horizon_ms,
            weights=weights,
            hold=rmse(test.targets, np.zeros_like(test.targets)),
            constant_velocity=rmse(test.targets, test.constant),
            window_fit=rmse(test.targets, test.window),
            linear=rmse(test.targets, guess),
            samples=len(test.targets),
            shipped=float("nan") if before is None else rmse(test.targets, before),
            positions=scores[POSITIONS][k],
            beside={name: scores[ordered(POSITIONS + (name,))][k] for name in OPTIONAL},
        )
        for name in CLASSES:
            mask = test.classes == name
            fit.by_class[name] = (
                rmse(test.targets[mask], guess[mask]),
                float("nan") if before is None else rmse(test.targets[mask], before[mask]),
                int(mask.sum()),
            )
        fit.by_class[END_CLASS] = (
            rmse(end.targets, guess_end),
            float("nan") if before_end is None else rmse(end.targets, before_end),
            len(end.targets),
        )
        fit.overshoot = (
            past_the_end(end.targets, guess_end, end.finals),
            past_the_end(end.targets, end.window, end.finals),
            float("nan") if before_end is None else past_the_end(end.targets, before_end, end.finals),
            len(end.targets),
        )
        result.fits.append(fit)
    return result


def apply_weights(weights: np.ndarray, inputs: np.ndarray) -> np.ndarray:
    """What the ring adds for one sample's *inputs*, the way GDScript reads the
    row: the inputs in the order the file names them, then the bias."""
    return with_bias(inputs.ravel()[None, :])[0] @ weights


def report(result: Result) -> str:
    """The numbers the script prints, held-out rms per horizon with the
    pressure and the tilt and without them beside the other guesses, then per
    class, then which optional inputs the rows read and why."""
    lines = [
        "%d file(s), %d strokes, %d events, %d%% trained on and the rest scored"
        % (result.files, result.strokes, result.events, int(TRAIN_SHARE * 100)),
        "",
        "horizon   hold   const-vel   window-fit   shipped   positions   %s   linear   [rms logical px on held-out strokes]"
        % "   ".join("+%s" % name for name in OPTIONAL),
    ]
    for f in result.fits:
        beside = "".join("     %5.2f   " % f.beside.get(name, float("nan")) for name in OPTIONAL)
        lines.append(
            "%5d ms  %5.2f      %5.2f        %5.2f     %5.2f       %5.2f  %s %5.2f   n=%d"
            % (f.horizon_ms, f.hold, f.constant_velocity, f.window_fit, f.shipped, f.positions, beside, f.linear, f.samples)
        )
    lines += ["", "by class, linear against shipped   [rms logical px, n]"]
    for f in result.fits:
        cells = []
        for name in CLASSES + (END_CLASS,):
            linear, shipped, count = f.by_class.get(name, (float("nan"), float("nan"), 0))
            cells.append("%s %.2f/%.2f n=%d" % (name, linear, shipped, count))
        lines.append("%5d ms  %s" % (f.horizon_ms, "   ".join(cells)))
    lines += ["", "stroke end, the lead past the last point along the stroke's final direction   [mean logical px, n]"]
    for f in result.fits:
        linear, window, shipped, count = f.overshoot
        lines.append("%5d ms  overshoot linear %.2f, window fit %.2f, shipped %.2f   n=%d" % (f.horizon_ms, linear, window, shipped, count))
    lines += ["", "linear reads %s (%d taps)" % (", ".join(result.inputs), TAPS)]
    lines += [result.verdicts[name] for name in OPTIONAL if name in result.verdicts]
    return "\n".join(lines)


def render_weights(result: Result, trained_on: str) -> str:
    """The GDScript the ring reads. Every number is written with enough digits
    to round-trip a float32, and the layout is gdformat's own. `INPUTS` in the
    file names the inputs its rows read, in the order they read them."""
    rows = []
    for f in result.fits:
        numbers = list(f.weights[:, 0]) + list(f.weights[:, 1])
        rows.append("    [\n" + "".join("        %s,\n" % repr(float(n)) for n in numbers) + "    ],\n")
    measures = "\n".join(
        "##   %2d ms: linear %.2f, positions alone %.2f, window fit %.2f, constant velocity %.2f, hold %.2f"
        % (f.horizon_ms, f.linear, f.positions, f.window_fit, f.constant_velocity, f.hold)
        for f in result.fits
    )
    width = sum(input_widths()[name] for name in result.inputs)
    return (
        "## The learned cursor lead's weights.\n"
        "##\n"
        "## Generated by scripts/train_cursor_lead.py from recorded pen strokes, and\n"
        "## never edited by hand. One row per\n"
        "## horizon: the x weights over the inputs INPUTS names, in its order, followed\n"
        "## by the x bias, then the same for y. The displacements are the last TAPS\n"
        "## steps of the pen, x then y each. The edges are the distances to the left,\n"
        "## top, right and bottom of the canvas view. The pressure is the newest\n"
        "## reading's pressure followed by it times each displacement number, and the\n"
        "## tilt is the newest reading's tilt across, then down.\n"
        "## `SaCursorPrediction.learned_lead` reads the two rows around the horizon it\n"
        "## is asked for and interpolates.\n"
        "##\n"
        "## Held-out rms distance from the pen, in logical pixels, on the recording it\n"
        "## was fitted from:\n" + measures + "\n"
        "##\n"
        "## Regenerate with:  python3 scripts/train_cursor_lead.py\n"
        "class_name SaCursorLeadWeights\n"
        "extends RefCounted\n"
        "\n"
        "## The even grid the displacements are read on, in hertz.\n"
        "const GRID_HZ: float = %s\n"
        "\n"
        "## How many displacements before the newest reading feed a row.\n"
        "const TAPS: int = %d\n"
        "\n"
        "## The inputs a row reads, in the order its weights stand.\n"
        "const INPUTS: Array = [%s]\n"
        "\n"
        "## What the weights were fitted from.\n"
        'const TRAINED_ON: String = "%s"\n'
        "\n"
        "## The horizons a row was fitted for, in milliseconds, ascending.\n"
        "const HORIZONS_MS: Array = [%s]\n"
        "\n"
        "## One row per horizon, 2 * (%d + 1) numbers each.\n"
        "const WEIGHTS: Array = [\n%s]\n"
    ) % (
        repr(float(GRID_HZ)),
        TAPS,
        ", ".join('"%s"' % name for name in result.inputs),
        trained_on,
        ", ".join(repr(float(f.horizon_ms)) for f in result.fits),
        width,
        "".join(rows),
    )


def parse_weights_file(text: str) -> dict:
    """The horizons, the inputs and the rows back out of a weights file, for a
    check that the file the ring reads says what the fit said. A file from
    before the files named their inputs reads as the inputs its width says."""
    horizons = []
    inputs = None
    rows: list = []
    section = None
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith("const HORIZONS_MS"):
            horizons = [float(v) for v in stripped.split("[", 1)[1].rstrip("]").split(",") if v.strip()]
        elif stripped.startswith("const INPUTS"):
            inputs = [v.strip().strip('"') for v in stripped.split("[", 1)[1].rstrip("]").split(",") if v.strip()]
        elif stripped.startswith("const WEIGHTS"):
            section = "weights"
        elif section == "weights":
            if stripped == "[":
                rows.append([])
            elif stripped.endswith(","):
                try:
                    rows[-1].append(float(stripped.rstrip(",")))
                except ValueError:
                    pass
    if inputs is None:
        inputs = inputs_for_width(len(rows[0]) // 2 - 1) if rows else []
    return {"horizons": horizons, "inputs": inputs, "rows": rows}


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--recordings", type=Path, default=DEFAULT_RECORDINGS, help="the folder of .jsonl recordings")
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT, help="the weights file to write")
    parser.add_argument("--seed", type=int, default=1, help="which strokes are held out")
    parser.add_argument("--dry-run", action="store_true", help="print the numbers and write nothing")
    args = parser.parse_args(argv)

    if not args.recordings.is_dir():
        print("no recordings folder at %s" % args.recordings, file=sys.stderr)
        return 2
    strokes, files = read_folder(args.recordings)
    if not strokes:
        print("no strokes in %s" % args.recordings, file=sys.stderr)
        return 2
    shipped = parse_weights_file(args.out.read_text(encoding="utf-8")) if args.out.is_file() else None
    result = train(strokes, args.seed, shipped=shipped)
    result.files = files
    print(report(result))
    if not result.beats_the_window_fit():
        print("\nthe linear lead does not beat the window fit at every horizon, so nothing is written", file=sys.stderr)
        return 1
    if not result.beats_the_shipped_weights():
        print(
            "\nthe linear lead does not beat the shipped weights at every horizon, or loses on %s, so nothing is written"
            % " or ".join(GUARDED),
            file=sys.stderr,
        )
        return 1
    if not result.stops_at_the_end():
        print(
            "\nthe linear lead overshoots a stroke end, further past the last point than the window fit or the shipped weights, so nothing is written",
            file=sys.stderr,
        )
        return 1
    if args.dry_run:
        return 0
    trained_on = "%d strokes from %d recording(s), %s" % (result.strokes, files, date.today().isoformat())
    args.out.write_text(render_weights(result, trained_on), encoding="utf-8")
    print("\nwrote %s, its rows reading %s" % (args.out, ", ".join(result.inputs)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
