#!/usr/bin/env python3
"""A feathered selection that meets the canvas's edge fills its edge columns whole.

A painter filled through a feathered selection whose
outline met the canvas's left and right edges, and found soft columns at both. This script
starts Sara offscreen through `SaraDoor`, makes the painter's document, 1800 by 1200 so its
last chunk column is 8 texels wide, and runs two fills through the door's `select` step with a
feather of 20, reading the active layer's middle row after each with `read_pixels`:

1. A rectangle from x 0 to the canvas's width. The first and the last columns' alpha must read
   what the column a feather inside reads.
2. A rectangle stopping ten texels short of either edge. Its edge columns must fade as the tent
   a box blur of 41 texels lays, 11 / 41, which is what the integration tip read too.

    cd sara-godot && .conda/bin/python scenarios/a-soft-selection-edge-that-meets-the-canvas-edge-leaves-no-soft-column-there.py [out]

It writes `probe.json` and the two rows as `.npy` into the out folder, which defaults to this
row's folder under `~/.cache/sara/scenario-runs`, and exits 1 when a check fails.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np

PROJECT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT / "scripts"))

from sara_door import SaraDoor  # noqa: E402

ROW = "a-soft-selection-edge-that-meets-the-canvas-edge-leaves-no-soft-column-there"
PROOF = Path.home() / ".cache" / "sara" / "scenario-runs" / ROW
CANVAS = (1800, 1200)
FEATHER = 20
SHORT = 10
ROW_Y = 600
TOLERANCE = 1.0 / 1000.0


def fill_row(door: SaraDoor, out: Path, inset: int, name: str) -> np.ndarray:
    """Selects a band from *inset* to *inset* short of the right edge, feathered, fills it and
    reads the middle row's alpha, undoing the fill afterwards."""
    width = CANVAS[0] - inset * 2
    door.send({"select": {"rect": [inset, 300, width, 600], "feather": FEATHER}})
    door.send({"wait": 8})
    door.send({"fill": [0.1, 0.4, 0.9]})
    door.send({"wait": 14})
    door.send({"read_pixels": {"rect": [0, ROW_Y, CANVAS[0], 1], "file": str(out / f"{name}.npy")}})
    door.send({"undo": 1})
    door.send({"wait": 12})
    return np.load(out / f"{name}.npy")[0, :, 3]


def main() -> int:
    out = (Path(sys.argv[1]) if len(sys.argv) > 1 else PROOF / "scenario").resolve()
    out.mkdir(parents=True, exist_ok=True)
    with SaraDoor(out_dir=out) as door:
        for step in (
            {"wait": 30},
            {"prefs": {"ui_scale": 1.0, "autosave_interval_minutes": 0}},
            {"wait": 20},
            {"document": "srgb"},
            {"wait": 25},
            {"canvas": list(CANVAS)},
            {"wait": 10},
        ):
            door.send(step)
        whole = fill_row(door, out, 0, "meets-the-edges")
        short = fill_row(door, out, SHORT, "ten-short-of-the-edges")
        door.send({"quit": True})

    last = CANVAS[0] - 1
    tent = (FEATHER - SHORT + 1) / (2 * FEATHER + 1)
    record = {
        "meets": {"first": float(whole[0]), "inside_first": float(whole[FEATHER]),
                  "last": float(whole[last]), "inside_last": float(whole[last - FEATHER])},
        "short": {"first": float(short[0]), "last": float(short[last]), "tent": tent},
    }
    (out / "probe.json").write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(record, indent=2))
    meets = record["meets"]
    checks = [
        (abs(meets["first"] - meets["inside_first"]) <= TOLERANCE, "the first column reads the column a feather inside"),
        (abs(meets["last"] - meets["inside_last"]) <= TOLERANCE, "the last column reads the column a feather inside"),
        (abs(record["short"]["first"] - tent) <= TOLERANCE, "ten short, the first column fades to the tent's 11 / 41"),
        (abs(record["short"]["last"] - tent) <= TOLERANCE, "ten short, the last column fades to the tent's 11 / 41"),
    ]
    for held, what in checks:
        print(("ok    " if held else "FAIL  ") + what)
    return 0 if all(held for held, _ in checks) else 1


if __name__ == "__main__":
    sys.exit(main())
