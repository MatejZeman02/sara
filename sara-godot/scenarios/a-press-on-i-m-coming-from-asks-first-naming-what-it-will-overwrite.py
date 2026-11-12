#!/usr/bin/env python3
"""A press on "I'm coming from" asks first, over the Welcome window and over Preferences > Interface, in English and in the test language.

    cd sara-godot && .conda/bin/python scenarios/a-press-on-i-m-coming-from-asks-first-naming-what-it-will-overwrite.py [out]

Sara starts with the test language's module alone, at a UI scale of 1. In
each language the Welcome window is opened, Krita's button of "I'm coming
from" is clicked as a pointer clicks it, and the question it puts up is shot,
`welcome-<lang>`. A state dump read while it is up gives its title and text. Escape answers it,
and the row's values are read back
through the Quick settings step, which presses nothing when it names no
program, so the log says the settings stayed. Then Preferences is opened on
Interface, the same button clicked there and its question shot,
`preferences-<lang>`, and Escape answers it too. Every answer goes to
`answers.json` beside the shots.

The out folder defaults to this row's folder under `~/.cache/sara/scenario-runs`.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

PROJECT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT / "scripts"))

from sara_door import SaraDoor  # noqa: E402

ROW = Path(__file__).stem
PROOF = Path.home() / ".cache" / "sara" / "scenario-runs" / ROW
BUTTON = "ComingFrom_krita"


def printed(answer: dict) -> list:
    """The lines a step printed, or the whole answer when it printed none."""
    return answer.get("printed") or [json.dumps(answer, ensure_ascii=False)[:600]]


def ask_and_shoot(door: SaraDoor, shot: str, answers: dict) -> None:
    """Clicks Krita's button, shoots the question and answers it with Escape."""
    answers[shot + " click"] = printed(door.send({"click": {"control": BUTTON}}))
    door.send({"wait": 20})
    answers[shot + " shot"] = printed(door.send({"shot": shot}))
    state = door.send({"wait": 1}, dump=True).get("state", {})
    message = next((v for k, v in state.items() if isinstance(v, dict) and "text_rect" in v), None)
    if message is None:
        message = {k: v for k, v in state.items() if "message" in k.lower()}
    answers[shot + " question"] = [json.dumps(message, ensure_ascii=False)]
    answers[shot + " escape"] = printed(door.send({"message": {"close": "escape"}}))
    door.send({"wait": 10})


def round_of(door: SaraDoor, lang: str, answers: dict) -> None:
    """The two questions in one language."""
    door.send({"open": "welcome"})
    door.send({"wait": 20})
    # The step reveals the Quick settings pane, and names no program, so
    # it presses nothing.
    door.send({"workspace": {"welcome": True, "coming_from": ""}})
    door.send({"wait": 10})
    ask_and_shoot(door, f"welcome-{lang}", answers)
    answers[f"welcome-{lang} after"] = printed(door.send({"workspace": {"welcome": True, "coming_from": ""}}))
    door.send({"click": {"control": "WelcomeClose"}})
    door.send({"wait": 15})
    door.send({"open": "preferences"})
    door.send({"wait": 20})
    door.send({"page": "Interface"})
    door.send({"wait": 15})
    ask_and_shoot(door, f"preferences-{lang}", answers)
    door.send({"key": "escape"})
    door.send({"wait": 15})


def main() -> int:
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else PROOF / "scenario"
    out.mkdir(parents=True, exist_ok=True)
    answers: dict[str, list] = {}
    with SaraDoor(out_dir=out, extra_args=["--modules-dir=res://tests/fixtures/modules/pseudo"]) as door:
        door.send({"wait": 45})
        door.send({"prefs": {"ui_scale": 1.0}})
        door.send({"message": {"close": "escape"}})
        door.send({"wait": 10})
        round_of(door, "en", answers)
        door.send({"prefs": {"ui_language": "en_XA"}})
        door.send({"wait": 20})
        round_of(door, "en-xa", answers)
    (out / "answers.json").write_text(json.dumps(answers, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    for key, lines in answers.items():
        print(key, "|", " / ".join(str(line) for line in lines)[:300])
    return 0


if __name__ == "__main__":
    sys.exit(main())
