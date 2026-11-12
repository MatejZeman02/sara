#!/usr/bin/env python3
"""The Layers docker in English and in the test language, a layer's name read whole in each.

    cd sara-godot && .conda/bin/python scenarios/a-layer-s-name-in-its-row-shows-whole-in-a-language-longer-than-english.py [out]

Sara starts with the test language's module alone and shows the Layers docker
in English, shot `layers-en`, with the `cut_labels` step's answer for it. Then
it is switched to `en_XA`, where the catalogue's Background is longer than its
column, and the docker is shown again, shot `layers-en-xa`, and read again. The
row's Background wraps onto a second line there and nothing is cut, while in
English the row is the one line it always was. Both answers go to
`cut-labels.json` beside the shots.

The out folder defaults to this row's folder under `~/.cache/sara/scenario-runs`.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

PROJECT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT / "scripts"))

from sara_door import SaraDoor  # noqa: E402

ROW = Path(__file__).stem
PROOF = Path.home() / ".cache" / "sara" / "scenario-runs" / ROW
DOCKER = "LayersDocker"
ANSWER = re.compile(r"SaCapture: cut labels '[^']*' \d+ of \d+ read, \d+ in the test language's marks (.*)$")


def look(door: SaraDoor, shot: str) -> list | None:
    """Shows the docker, shoots it as *shot* and returns the labels it cuts."""
    door.send({"docker": DOCKER})
    door.send({"wait": 12})
    door.send({"shot": shot})
    answer = door.send({"cut_labels": {"docker": DOCKER, "name": shot}})
    door.send({"cut_labels": {"shut": DOCKER}})
    door.send({"wait": 4})
    for line in answer.get("printed", []):
        found = ANSWER.search(line)
        if found:
            return json.loads(found.group(1))
    return None


def main() -> int:
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else PROOF / "scenario"
    out.mkdir(parents=True, exist_ok=True)
    report: dict[str, list | None] = {}
    with SaraDoor(out_dir=out, extra_args=["--modules-dir=res://tests/fixtures/modules/pseudo"]) as door:
        door.send({"wait": 45})
        door.send({"prefs": {"ui_scale": 1.0}})
        door.send({"message": {"close": "escape"}})
        door.send({"wait": 10})
        report["layers-en"] = look(door, "layers-en")
        door.send({"prefs": {"ui_language": "en_XA"}})
        door.send({"wait": 20})
        report["layers-en-xa"] = look(door, "layers-en-xa")
    (out / "cut-labels.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    for shot, cut in report.items():
        print(f"{shot}: {'not read' if cut is None else len(cut)} cut")
    return 0 if all(cut == [] for cut in report.values()) else 1


if __name__ == "__main__":
    sys.exit(main())
