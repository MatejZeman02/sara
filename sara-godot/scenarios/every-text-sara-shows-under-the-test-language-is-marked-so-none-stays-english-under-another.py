#!/usr/bin/env python3
"""Every text Sara shows in the test language, and each one with no mark listed.

    cd sara-godot && python scenarios/every-text-sara-shows-under-the-test-language-is-marked-so-none-stays-english-under-another.py [out]

A text that reaches the screen without passing through the
catalogue, or that was built before the language was set, shows without the
test language's marks, and that is the text a Czech painter sees in English.
The walk is the one that marks the test language, driven through the door: Sara starts with the test
language's module alone, `--modules-dir=res://tests/fixtures/modules/pseudo`,
is switched to `en_XA` and quits, and starts again on that profile, so what
the boot builds is built in the test language from a fresh start, as a Czech
painter's is.

Then each place is shot and asked for every text it shows, the `cut_labels`
step's `texts` form: the main window with its top bar's hover tips, the
welcome window's four panes, every Preferences page, every docker alone, every
menu of the top bar, and every dialog the rows of File, Layer and Filter open.
A corner message is read off the main window while it stands, after the keys
that post one. `texts.json` holds the answers, and `scripts/unmarked_texts.py`
reads them into `unmarked.md` with a crop of each text left unmarked.

The out folder defaults to this row's folder under `~/.cache/sara/scenario-runs`.
Exits 1 when a text is left that the reader's `KEPT` does not name.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

PROJECT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT / "scripts"))

import unmarked_texts  # noqa: E402
from sara_door import SaraDoor  # noqa: E402

ROW = Path(__file__).stem
PROOF = Path.home() / ".cache" / "sara" / "scenario-runs" / ROW
LOCALE = "en_XA"
PSEUDO = ["--modules-dir=res://tests/fixtures/modules/pseudo"]
ANSWER = re.compile(r"SaCapture: (?:texts|cut labels) (?:'[^']*' \d+ read|list|windows) (.*)$")


def slug(text: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")


def ask(door: SaraDoor, spec: dict) -> object:
    """The JSON a `cut_labels` answer carries, or None."""
    answer = door.send({"cut_labels": spec})
    for line in answer.get("printed", []):
        found = ANSWER.search(line)
        if found:
            return json.loads(found.group(1))
    return None


def look(door: SaraDoor, shot: str, where: str, scopes: list[dict], places: list[dict]) -> None:
    """A shot of the main window and the texts each scope shows, kept in *places*."""
    door.send({"shot": shot})
    texts: list[dict] = []
    for scope in scopes:
        read = ask(door, {"texts": True, "name": where} | scope)
        if isinstance(read, list):
            texts.extend(read)
        else:
            print(f"{where}: {scope} not read")
    places.append({"where": where, "shot": f"{shot}.png", "texts": texts})
    print(f"{where}: {len(texts)} texts, {sum(map(unmarked_texts.is_unmarked, texts))} unmarked")


def close_new(door: SaraDoor, before: list) -> None:
    """Escape, and every window still open that was not before it hidden."""
    door.send({"key": "escape"})
    door.send({"wait": 6})
    now = ask(door, {"texts": True, "open_windows": True}) or []
    left = [path for path in now if path not in before]
    if left:
        door.send({"cut_labels": {"texts": True, "hide": left}})
        door.send({"wait": 4})


def walk(door: SaraDoor, places: list[dict]) -> None:
    door.send({"wait": 45})
    door.send({"prefs": {"ui_scale": 1.0}})
    door.send({"wait": 20})
    main = [{"main": True}, {"windows": True}]
    look(door, "00-start", "start", main, places)

    # The corner message, read while it stands.
    door.send({"key": {"key": "1"}})
    door.send({"wait": 3})
    look(door, "01-notice-opacity", "corner message, opacity", [{"main": True}], places)
    door.send({"key": "escape"})

    base = ask(door, {"texts": True, "open_windows": True}) or []
    door.send({"open": "welcome", "launch": "first"})
    door.send({"wait": 20})
    for i, pane in enumerate(["recent", "news", "tips", "quick-settings"]):
        door.send({"cut_labels": {"texts": True, "tab": {"in": "Panes", "index": i}}})
        door.send({"wait": 10})
        look(door, f"02-welcome-{i}-{pane}", f"welcome window, {pane}", [{"windows": True}], places)
    close_new(door, base)

    door.send({"open": "preferences"})
    door.send({"wait": 20})
    lists = ask(door, {"list": True})
    if not isinstance(lists, dict):
        print("no list of pages, dockers and menus")
        return
    for i, page in enumerate(lists["pages"], 1):
        door.send({"page": page})
        door.send({"wait": 12})
        look(door, f"10-prefs-{i:02d}-{slug(page)}", f"Preferences, {page}", [{"preferences": True}], places)
    door.send({"key": {"key": "comma", "ctrl": True}})
    door.send({"wait": 15})

    for i, docker in enumerate(lists["dockers"], 1):
        door.send({"docker": docker})
        door.send({"wait": 12})
        look(door, f"20-docker-{i:02d}-{slug(docker)}", f"docker {docker}", [{"docker": docker}], places)
        door.send({"cut_labels": {"shut": docker}})
        door.send({"wait": 4})

    for i, menu in enumerate(lists["menus"], 1):
        door.send({"menu": menu})
        door.send({"wait": 12})
        look(door, f"30-menu-{i:02d}-{slug(menu)}", f"menu {menu}", [{"menu": menu}], places)
        door.send({"key": "escape"})
        door.send({"wait": 6})

    base = ask(door, {"texts": True, "open_windows": True}) or []
    rows = ask(door, {"texts": True, "list": True}) or []
    for i, row in enumerate(rows, 1):
        if "filter" in row:
            door.send({"cut_labels": {"texts": True, "invoke": row["filter"]}})
        else:
            door.send({"menu_item": {"menu": row["menu"], "id": row["id"]}})
        door.send({"wait": 20})
        where = f"{row['menu']} > {row['text']}"
        name = slug(row.get("filter", str(row.get("id"))))
        look(door, f"40-dialog-{i:02d}-{slug(row['menu'])}-{name}", where, [{"windows": True}], places)
        close_new(door, base)


def main() -> int:
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else PROOF / "scenario"
    out.mkdir(parents=True, exist_ok=True)
    with SaraDoor(out_dir=out, extra_args=PSEUDO) as door:
        door.send({"wait": 45})
        door.send({"prefs": {"ui_language": LOCALE}})
        door.send({"wait": 20})
    places: list[dict] = []
    with SaraDoor(out_dir=out, extra_args=PSEUDO, keep_settings=True) as door:
        walk(door, places)
    (out / "texts.json").write_text(json.dumps(places, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    left, stays = unmarked_texts.write_page(places, out)
    print(f"{len(places)} places, {len(left)} unmarked texts, {len(stays)} meant to stay, {out / 'unmarked.md'}")
    return 1 if left else 0


if __name__ == "__main__":
    sys.exit(main())
