#!/usr/bin/env python3
"""A feathered selection that meets the canvas's edge fills every column of the row whole.

The script for a selection that meets the edge read the first and the last columns alone, and the soft band
the painter saw sat 8 texels in from the right edge, over the columns just before
the last chunk, which is 8 texels wide on a canvas 1800 wide. This script starts Sara
offscreen through `SaraDoor`, makes that 1800 by 1200 document, selects a rectangle from x 0
to the canvas's width feathered by 20 through the door's `select` step, fills through it, and
reads the whole middle row of the active layer with `read_pixels`. Every column's alpha must
read whole, x 1780 to 1791 included, where the integration tip read 0.707 at the worst.

    cd sara-godot && .conda/bin/python scenarios/a-feather-s-soft-edge-reaches-the-last-chunk-s-neighbour-and-leaves-soft-columns-where-the-canvas-ends.py [out]

It writes `probe.json` and the row as `row.npy` into the out folder, which defaults to this
row's folder under `~/.cache/sara/scenario-runs`, and exits 1 unless every column reads whole.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np

PROJECT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT / "scripts"))

from sara_door import SaraDoor  # noqa: E402

ROW = "a-feather-s-soft-edge-reaches-the-last-chunk-s-neighbour-and-leaves-soft-columns-where-the-canvas-ends"
PROOF = Path.home() / ".cache" / "sara" / "scenario-runs" / ROW
CANVAS = (1800, 1200)
FEATHER = 20
ROW_Y = 600
TOLERANCE = 0.002


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
            {"select": {"rect": [0, 300, CANVAS[0], 600], "feather": FEATHER}},
            {"wait": 8},
            {"fill": [0.1, 0.4, 0.9]},
            {"wait": 14},
            {"read_pixels": {"rect": [0, ROW_Y, CANVAS[0], 1], "file": str(out / "row.npy")}},
            {"quit": True},
        ):
            door.send(step)

    alpha = np.load(out / "row.npy")[0, :, 3]
    soft = np.flatnonzero(alpha < 1.0 - TOLERANCE)
    record = {
        "columns": int(alpha.size),
        "soft_columns": [int(x) for x in soft],
        "least": float(alpha.min()),
        "band_1780_to_1791": [float(v) for v in alpha[1780:1792]],
    }
    (out / "probe.json").write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(record, indent=2))
    held = alpha.size == CANVAS[0] and soft.size == 0
    print(("ok    " if held else "FAIL  ") + "every column of the middle row reads whole")
    return 0 if held else 1


if __name__ == "__main__":
    sys.exit(main())
