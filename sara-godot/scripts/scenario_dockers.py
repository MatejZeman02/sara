#!/usr/bin/env python3
"""Which committed scenarios aim a gesture at a point a docker covers, without
having said where that docker is.

A capture reads whatever `docker_layout.cfg` the last one left in the checkout's
scratch profile, so a scenario that presses at a fixed viewport point proves one
thing on a used profile and another on a fresh one. A transform scenario drove
every gesture in one checkout and none in another, and the difference was a Tool
Options docker sitting over the first point of its opening stroke.

    python3 sara-godot/scripts/scenario_dockers.py
    python3 sara-godot/scripts/scenario_dockers.py --write-layout <state-dump.json>
    python3 sara-godot/scripts/scenario_dockers.py --check-layout <state-dump.json>

Prints one line per scenario at risk.

**A scenario that aims at a docker on purpose is not a false positive, it is the
same defect from the other side.** `pen-cursor-over-ui.json` hovers UI,
`note-image.json` drags a note box by its title, and `hover-and-click-notes.json` clicks
the toolbox in note mode. A point aimed at a docker is only worth anything when
the scenario has said where that docker is, so those place theirs at the default
rectangle rather than trusting it.

## The layout is generated and the question is asked per docker

A hand-written list of rectangles goes stale the day a unit adds a docker, and
a scan whose list is short reads zero while the strokes under the missing
docker are lost. So the list is generated from a state dump, by
`--write-layout`, and checked against the dockers
`ui/main/sa_builtin_dockers.gd` registers every time the scan runs, so a
twelfth docker fails the scan rather than passing it.

A scenario that placed some dockers has not said where the others are, so the
question is per docker: a point is tested against every docker the scenario did
not put somewhere itself. Answering it for a whole file is what let thirty-one
committed scenarios through at once. The cheap way to answer it in a scenario
is `{"docker": "park"}`, one step that puts every docker at the host's right
edge where none of them covers anything.

## A Tab is read as the app reads it

`{"key": "tab"}` is focus mode, which hides every docker that is open and on the
next Tab shows back those and no others. A scenario that Tabs and then presses
where a docker had stood is asking what the canvas does there, so the scan reads
a Tab as it happens in the app: nothing covers the canvas while the dockers are
away, and the same dockers cover it again after the second Tab.

## A generated file drifts, so it is compared on every run

Generating the file fixes who writes it and not when, and the app moves a
rectangle whenever a docker's board gains a row and the window floors itself to
its column. A record six days old had three of its twelve rectangles wrong, and
five scenarios stroked inside the real Reference docker and outside the
recorded one with the scan calling them clean.

So the file is compared, in two halves that need different things.
`against_defaults` needs nothing but the tree: a fresh profile reads each
docker's position, stored size and visibility from `docker_layout_default.cfg`,
so a recorded rectangle that disagrees with that file cannot be the one the app
opens, and `load_layout` refuses it on every scan. `drift` needs a dump, because
the floor a docker's column puts under its stored size is a fact of the running
app and of nothing a script can read: `--check-layout` over a fresh profile's
dump fails on any rectangle that is not the one the app opened.

**A recorded position is the file's only while the fit moves no docker on the
window the dump was taken on.** The fit keeps a title under
`MainDockers.below_bar`, which is 79 for the two-row bar a fresh profile opens,
and the Filters docker, whose foot passes the capture's 1048 window, is lifted
to 504 tall. A `--write-layout` over a fresh profile's dump writes those as the
record, so the committed file and the app agree.
"""

from __future__ import annotations

import argparse
import configparser
import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCENARIOS = HERE.parent / "scenarios"
LAYOUT_FILE = HERE / "default_docker_layout.json"
BUILTIN_DOCKERS = HERE.parent / "ui" / "main" / "sa_builtin_dockers.gd"
DOCKER_IDS = HERE.parent / "ui" / "main" / "sa_docker_ids.gd"
MODULES = HERE.parent / "modules"
DEFAULT_CFG = HERE.parent / "docker_layout_default.cfg"

# `SaDockerDriver.PARK_AT`, and the two have to agree or a parked scenario is
# tested against a rectangle it is not in. Asserted by the scan's own tests.
PARK_AT = (1920, 78)

VECTOR_RE = re.compile(r"Vector2i?\(\s*(-?[\d.]+)\s*,\s*(-?[\d.]+)\s*\)")


def registered_dockers() -> dict[str, str]:
    """Every built-in docker `ui/main/sa_builtin_dockers.gd` registers, id to title.

    Read out of the source rather than written down again, because a
    hand-written list goes stale the day a unit adds a docker and nothing says
    so. The list names each id by its `SaDockerIds`
    constant, so the constant is read back to its id out of `sa_docker_ids.gd`.
    A docker a module in the tree registers is read too, by `module_dockers`,
    since the shipped layouts place it as they place a built-in.
    """
    ids = dict(re.findall(r'^const (\w+) := &"(\w+)"', DOCKER_IDS.read_text(encoding="utf-8"), re.MULTILINE))
    text = BUILTIN_DOCKERS.read_text(encoding="utf-8")
    found = {
        ids[constant]: title
        for constant, title in re.findall(r'\[SaDockerIds\.(\w+),\s*"([^"]+)",', text)
        if constant in ids
    }
    found.update(module_dockers())
    return found


def module_dockers() -> dict[str, str]:
    """Every docker a module in the tree registers, id to title.

    A module names its docker's script by a preload beside it and registers it
    by that script's `DOCKER_ID`, as `modules/sara-base-modules/exposure/module.gd` does, so the
    preload is followed to the constant and the title read off the call.
    """
    found: dict[str, str] = {}
    for module in sorted(MODULES.rglob("module.gd")):
        text = module.read_text(encoding="utf-8")
        preloads = dict(re.findall(r'^const (\w+) := preload\("([^"]+)"\)', text, re.MULTILINE))
        for name, title in re.findall(r'register_docker\(\s*(\w+)\.DOCKER_ID,\s*"([^"]+)"', text):
            if name not in preloads:
                continue
            script = (module.parent / preloads[name]).read_text(encoding="utf-8")
            docker_id = re.search(r'^const DOCKER_ID := &"(\w+)"', script, re.MULTILINE)
            if docker_id is not None:
                found[docker_id.group(1)] = title
    return found


def normalized(name: str) -> str:
    return "".join(name.lower().split())


def read_default_cfg(text: str) -> dict[str, dict]:
    """What `docker_layout_default.cfg` opens a fresh profile with, by docker id.

    Only the dockers that file names. The Brush Presets and the Undo History
    place themselves in their own `_init` and are not in it, so for those two a
    dump is the only reader.
    """
    parser = configparser.ConfigParser(interpolation=None)
    parser.optionxform = str
    parser.read_string(text)
    out: dict[str, dict] = {}
    for section in parser.sections():
        position = VECTOR_RE.fullmatch(parser[section].get("position", "").strip())
        size = VECTOR_RE.fullmatch(parser[section].get("size", "").strip())
        if position is None or size is None:
            continue
        out[section] = {
            "position": [int(float(position.group(1))), int(float(position.group(2)))],
            "size": [int(float(size.group(1))), int(float(size.group(2)))],
            "open": parser[section].get("visible", "false").strip() == "true",
        }
    return out


def against_defaults(layout: dict[str, dict], defaults: dict[str, dict]) -> list[str]:
    """Every way the recorded layout cannot be what the default layout file opens.

    **The half of the comparison that needs no Godot.** A fresh profile takes a docker's
    position and visibility from the file as they stand, and its size from the
    file floored up to what the docker's column wants. So a recorded position or
    visibility that differs is wrong, and so is a recorded size below the stored
    one, since the floor only ever raises it. How far the floor raises it is the
    other half, which is `drift`.

    **A width, and not a height.** The default layout is fitted
    to the window it opens on, and a column taller than the window gives up
    height from its lowest docker. A capture's window is 1048 high against the
    1080 the file was written for, so the Reference opens 27 shorter than it is
    stored, and only a dump can say by how much.
    """
    found: list[str] = []
    for docker_id, stored in sorted(defaults.items()):
        if docker_id not in layout:
            continue
        x, y, width, height = layout[docker_id]["rect"]
        want_x, want_y = stored["position"]
        stored_width = stored["size"][0]
        if (x, y) != (want_x, want_y):
            found.append(f"{docker_id} is recorded at ({x}, {y}) and the default layout places it at ({want_x}, {want_y})")
        if width < stored_width:
            found.append(
                f"{docker_id} is recorded {width} by {height}, narrower than the {stored_width} "
                "the default layout stores"
            )
        if layout[docker_id]["open"] != stored["open"]:
            said = "shown" if stored["open"] else "hidden"
            found.append(f"{docker_id} is recorded {describe_open(layout[docker_id])} and the default layout has it {said}")
    return found


def describe_open(entry: dict) -> str:
    return "open" if entry["open"] else "shut"


def window_entry(window: dict) -> dict:
    """One embedded window of a state dump, in the layout file's shape."""
    return {
        "title": window["title"],
        "rect": [
            int(window["position"]["x"]),
            int(window["position"]["y"]),
            int(window["size"]["x"]),
            int(window["size"]["y"]),
        ],
        "open": bool(window["visible"]),
    }


def embedded_windows_by_name(state: dict) -> dict[str, list[dict]]:
    """A dump's embedded windows keyed by title with case and spaces dropped.

    The dump names an embedded window by its **title** and the registry names it
    by **id**, and the two differ for the Toolbox, which registers as `ToolBox`
    and titles itself `Toolbox`. The title is unambiguous for all twelve, and
    both readers below say so loudly when it stops being.
    """
    by_name: dict[str, list[dict]] = {}
    for window in state.get("windows", []):
        if window.get("embedded") and window.get("title"):
            by_name.setdefault(normalized(window["title"]), []).append(window)
    return by_name


def drift(layout: dict[str, dict], state: dict) -> list[str]:
    """Every docker whose recorded rectangle is not the one the dump's app opened.

    **The dump has to be of a fresh profile**, which is what `sara_shot.py
    --state-only` takes unless it is told `--keep-settings`. A dump
    from the middle of a scenario reports whatever that scenario moved.
    """
    by_name = embedded_windows_by_name(state)
    found: list[str] = []
    for docker_id, entry in sorted(layout.items()):
        windows = by_name.get(normalized(entry["title"]), [])
        if len(windows) != 1:
            found.append(f"{docker_id} matched {len(windows)} embedded windows called '{entry['title']}' in the dump")
            continue
        opened = window_entry(windows[0])
        if opened["rect"] != entry["rect"] or opened["open"] != entry["open"]:
            found.append(
                f"{docker_id} is recorded {describe_open(entry)} at {entry['rect']} "
                f"and the app opened it {describe_open(opened)} at {opened['rect']}"
            )
    return found


def load_layout() -> dict[str, dict]:
    """The default layout, generated from the running app and checked here.

    Fails rather than warns when the file and the registry disagree, or the
    file and the default layout the app reads, because a scan that quietly
    tests against a rectangle the app does not have is the defect this script
    exists to find, from the inside.
    """
    if not LAYOUT_FILE.exists():
        sys.exit(f"{LAYOUT_FILE.name} is missing. Regenerate it with --write-layout.")
    layout = json.loads(LAYOUT_FILE.read_text(encoding="utf-8"))
    registered = registered_dockers()
    missing = sorted(set(registered) - set(layout))
    extra = sorted(set(layout) - set(registered))
    if missing or extra:
        sys.exit(
            f"{LAYOUT_FILE.name} and ui/main/sa_builtin_dockers.gd disagree.\n"
            f"  registered and not in the file: {missing or 'none'}\n"
            f"  in the file and not registered: {extra or 'none'}\n"
            "Regenerate the file with --write-layout over a fresh-profile state dump."
        )
    wrong = against_defaults(layout, read_default_cfg(DEFAULT_CFG.read_text(encoding="utf-8")))
    if wrong:
        sys.exit(
            f"{LAYOUT_FILE.name} is not what {DEFAULT_CFG.name} opens a fresh profile with.\n  "
            + "\n  ".join(wrong)
            + "\nRegenerate the file with --write-layout over a fresh-profile state dump."
        )
    return layout


def layout_from_state(state: dict, source: object) -> dict[str, dict]:
    """The layout file's contents out of a state dump, one entry per registered docker."""
    by_name = embedded_windows_by_name(state)
    out: dict[str, dict] = {}
    for docker_id, title in registered_dockers().items():
        found = by_name.get(normalized(title), [])
        if len(found) != 1:
            sys.exit(f"{docker_id} matched {len(found)} embedded windows called '{title}' in {source}")
        out[docker_id] = window_entry(found[0])
    return out


def write_layout(dump: Path) -> int:
    """Rewrites the layout file from a state dump taken on a deleted profile."""
    out = layout_from_state(json.loads(dump.read_text(encoding="utf-8")), dump)
    LAYOUT_FILE.write_text(json.dumps(out, indent=1, sort_keys=True) + "\n", encoding="utf-8")
    opened = sum(1 for entry in out.values() if entry["open"])
    print(f"{LAYOUT_FILE.name}: {len(out)} registered dockers, {opened} open on a fresh profile")
    return 0


def check_layout(dump: Path) -> int:
    """Exit 1 when the recorded layout is not the one the dump's app opened."""
    layout = load_layout()
    found = drift(layout, json.loads(dump.read_text(encoding="utf-8")))
    for line in found:
        print(line)
    if found:
        print(f"\n{LAYOUT_FILE.name} is not the layout the app opens. Regenerate it with --write-layout {dump}.")
        return 1
    print(f"{LAYOUT_FILE.name} is the layout the app opened in {dump.name}, all {len(layout)} dockers agree.")
    return 0


def settles_everything(step: dict) -> bool:
    """Whether *step* answers for every docker at once.

    `{"docker": "park"}` puts them all where nothing is, and a named layout
    preset places them all somewhere the scenario chose. Both are a whole
    answer, where a `docker` step naming one docker is a sixth of one.
    """
    if step.get("docker") == "park":
        return True
    preset = step.get("layout_preset")
    return isinstance(preset, dict) and "load" in preset


def is_tab(step: dict) -> bool:
    """Whether *step* is the Tab that toggles focus mode."""
    return step.get("key") == "tab"


def moves(step: dict) -> tuple[str, bool] | None:
    """The docker *step* places and whether it said where, or None.

    A `docker` step with an `at` puts it somewhere the scenario chose, so it
    covers nothing the scenario did not ask for. Without one it lands on the
    stored default, which is a rectangle this scan knows and still has to test.
    """
    if "docker" not in step or settles_everything(step):
        return None
    spec = step["docker"]
    if isinstance(spec, dict):
        return str(spec.get("id", "")), "at" in spec
    return str(spec), False


def covering(layout: dict[str, dict], x: float, y: float, live: set[str]) -> str | None:
    for docker_id in sorted(live):
        dx, dy, w, h = layout[docker_id]["rect"]
        if dx <= x < dx + w and dy <= y < dy + h:
            return layout[docker_id]["title"]
    return None


def points(step: dict) -> list[tuple[float, float]]:
    """Every viewport point *step* aims at.

    `move` is written two ways, `[x, y]` and `{"at": [x, y], "pressure": p}`, and
    reading only the first is what let `cursor-option.json` past this scan
    entirely and made `painting-modes.json` read as one hit where it has
    ten. A scan that half reads the vocabulary is worse than none, because its
    zero is believed.

    A stroke is written two ways as well, `from` and `to` or `points` with an
    `at` each, and the waypoint form is read the same as the other. A
    stroke in `"space": "document"` names document pixels, which this scan has
    no view to map through, so none of its points is tested here and
    `untested_in` counts it instead of letting it pass as clean.
    """
    out: list[tuple[float, float]] = []
    stroke = step.get("stroke")
    if isinstance(stroke, dict) and not in_document_space(step):
        out += [tuple(stroke[k]) for k in ("from", "to") if isinstance(stroke.get(k), list)]
        waypoints = stroke.get("points")
        if isinstance(waypoints, list):
            out += [tuple(p["at"]) for p in waypoints if isinstance(p, dict) and isinstance(p.get("at"), list)]
    for key in ("press", "click", "release", "move"):
        spec = step.get(key)
        if isinstance(spec, dict) and isinstance(spec.get("at"), list):
            out.append(tuple(spec["at"]))
        elif key == "move" and isinstance(spec, list) and len(spec) == 2:
            out.append(tuple(spec))
    return [(float(p[0]), float(p[1])) for p in out if len(p) == 2]


def in_document_space(step: dict) -> bool:
    """Whether *step* is a stroke whose points are document pixels."""
    stroke = step.get("stroke")
    return isinstance(stroke, dict) and stroke.get("space") == "document"


def untested_in(steps: list) -> int:
    """How many strokes in *steps* the window test leaves out, as `points` says."""
    return sum(1 for step in steps if isinstance(step, dict) and in_document_space(step))


def at_risk_in(layout: dict[str, dict], steps: list) -> list[tuple[str, float, float]]:
    """Every point in *steps* that a docker was covering when the step ran.

    **In order, because a layout a scenario settles halfway through only covers
    the half after it.** The scan this replaced answered per file, so a `docker`
    step at step 40 would speak for a stroke at step 3, and a scenario that
    parks late would inherit its own opening gestures from the profile.
    """
    live = {docker_id for docker_id, entry in layout.items() if entry["open"]}
    # The dockers focus mode is holding, or None while it is off.
    away: set[str] | None = None
    found: list[tuple[str, float, float]] = []
    for step in steps:
        if not isinstance(step, dict):
            continue
        found += [(name, x, y) for x, y in points(step) if (name := covering(layout, x, y, live))]
        if is_tab(step):
            live, away = (set(), live) if away is None else (away, None)
            continue
        if settles_everything(step):
            live = set()
            away = set() if away is not None else None
            continue
        moved = moves(step)
        if moved is not None:
            docker_id, said_where = moved
            live.discard(docker_id) if said_where else live.add(docker_id)
    return found


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--write-layout", type=Path, metavar="DUMP", help="rewrite the layout file from a state dump")
    parser.add_argument(
        "--check-layout", type=Path, metavar="DUMP", help="exit 1 when the layout file is not the one a dump's app opened"
    )
    args = parser.parse_args()
    if args.write_layout is not None:
        return write_layout(args.write_layout)
    if args.check_layout is not None:
        return check_layout(args.check_layout)

    layout = load_layout()
    at_risk = 0
    untested = 0
    for path in sorted(SCENARIOS.glob("*.json")):
        try:
            steps = json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as bad:
            print(f"{path.name}: not valid JSON, {bad}")
            continue
        if not isinstance(steps, list):
            continue
        skipped = untested_in(steps)
        if skipped:
            untested += 1
            print(f"{path.name:52s} {skipped:3d} stroke(s) in document space, not tested, no view to map them")
        hits = at_risk_in(layout, steps)
        if hits:
            at_risk += 1
            where, x, y = hits[0]
            print(f"{path.name:52s} {len(hits):3d} under a docker, first ({x:.0f}, {y:.0f}) under {where}")
    if untested:
        print(f"{untested} scenario(s) stroke in document space, which this scan leaves out.")
    if not at_risk:
        print(f"No scenario aims at a point a docker covers without saying where it is. {len(layout)} dockers read.")
        return 0
    print(f"\n{at_risk} scenario(s) aim at a docker they never placed. `{{\"docker\": \"park\"}}` is one step.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
