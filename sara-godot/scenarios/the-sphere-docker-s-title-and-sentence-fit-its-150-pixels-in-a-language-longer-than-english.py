#!/usr/bin/env python3
"""The Sphere docker in English and in the test language, its title and sentence read whole in each.

    cd sara-godot && .conda/bin/python scenarios/the-sphere-docker-s-title-and-sentence-fit-its-150-pixels-in-a-language-longer-than-english.py [out]

Sara starts with the test language's module alone and shows the Sphere docker
on the fresh document, which is flat, so the docker shows its sentence in
place of the ball. It is shot in English, `sphere-en`, with the `cut_labels`
step's answer for it, then switched to `en_XA`, where the title is one word
wider than the bar gives it and the sentence two lines longer, and shown, shot
and read again, `sphere-en-xa`. Both answers go to `cut-labels.json` beside
the shots, and the docker's window in each, its place and size on the
screen, to `windows.json`.

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
DOCKER = "SphereDocker"
ANSWER = re.compile(r"SaCapture: cut labels '[^']*' \d+ of \d+ read, \d+ in the test language's marks (.*)$")


def look(door: SaraDoor, shot: str, sizes: dict) -> list | None:
    """Shows the docker, shoots it as *shot* and returns the labels it cuts."""
    door.send({"docker": DOCKER})
    door.send({"wait": 12})
    door.send({"shot": shot})
    state = door.send({"wait": 1}, dump=True).get("state", {})
    window = next((w for w in state.get("windows", []) if w.get("title") == "Sphere" and w.get("visible")), None)
    sizes[shot] = window and {"position": window["position"], "size": window["size"]}
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
    sizes: dict[str, dict | None] = {}
    with SaraDoor(out_dir=out, extra_args=["--modules-dir=res://tests/fixtures/modules/pseudo"]) as door:
        door.send({"wait": 45})
        door.send({"prefs": {"ui_scale": 1.0}})
        door.send({"message": {"close": "escape"}})
        door.send({"wait": 10})
        report["sphere-en"] = look(door, "sphere-en", sizes)
        door.send({"prefs": {"ui_language": "en_XA"}})
        door.send({"wait": 20})
        report["sphere-en-xa"] = look(door, "sphere-en-xa", sizes)
    (out / "cut-labels.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (out / "windows.json").write_text(json.dumps(sizes, indent=2) + "\n", encoding="utf-8")
    for shot, cut in report.items():
        print(f"{shot}: {'not read' if cut is None else len(cut)} cut, window {sizes.get(shot)}")
    return 0 if all(cut == [] for cut in report.values()) else 1


if __name__ == "__main__":
    sys.exit(main())
