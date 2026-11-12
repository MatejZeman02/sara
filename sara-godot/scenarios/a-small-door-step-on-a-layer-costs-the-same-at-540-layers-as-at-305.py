#!/usr/bin/env python3
"""A door step on one layer timed at 300 and at 540 layers, and the log it leaves.

    cd sara-godot && .conda/bin/python scenarios/a-small-door-step-on-a-layer-costs-the-same-at-540-layers-as-at-305.py [out] [--mirrors FILE]

For each depth, 300 and then 540, Sara opens a fresh document and the door adds
that many layers, each filled with a thin colour over the four chunks of the
document's top row, every thirtieth wrapped in a group, so the stack is as
deep as the mirrors file and every layer reaches the picture. The top layer is
then put in a group of its own and the group hidden, which is where the
mirrors painter set the night lights of the seasons not on show, and the
layer in the middle of the stack is made active.

The door sets the opacity of the hidden light 50 times, the painter's step,
and of the active layer 50 times, toggles the active layer's eye 200 times,
and sets both opacities 50 times again. Each step is timed from the request
leaving to its answer, which the door sends once the step's frame is drawn.
Last, it asks for the `layers` answer and reads how much the run log grew and
its longest line, and times one `state` request, the whole dump the ask names
at 9.77 s, which is written and not judged.

With `--mirrors`, a `cp` copy of the mirrors file is loaded as well, and taken
away again at the end, since the proof folder is read as text. For each
of the four seasons the door shows one hidden season group under a light group
that is shown, times it to the picture settled and hides it again, and it sets
the opacity of a layer inside a hidden group 50 times, the painter's own step.

Everything goes to `times.json` beside the run, and the run exits 1 when a
clause of the row is not met: the light's steps under 0.1 s at both depths,
before and after the eyes, the median at 540 within a fifth of the one at
300, every season group shown in under 5 s, the mirrors light's step under
0.1 s, and the `layers` answer leaving no line longer than a short one. The
active layer's times and the `state` request are written and not judged,
since a visible layer under others refolds what lies between and the dump
reads the whole run, as the Done paragraph says.

The out folder defaults to this row's folder under `~/.cache/sara/scenario-runs`.
"""
from __future__ import annotations

import json
import shutil
import statistics
import sys
import time
from pathlib import Path

PROJECT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT / "scripts"))

from sara_door import SaraDoor  # noqa: E402

ROW = Path(__file__).stem
PROOF = Path.home() / ".cache" / "sara" / "scenario-runs" / ROW
DEPTHS = (300, 540)
STEP_LIMIT = 0.1
SHOW_LIMIT = 5.0
## The longest line a `layers` answer may leave in the log.
LOG_LINE_LIMIT = 4200
CHUNKS = [[0, 0], [1, 0], [2, 0], [3, 0]]
## How many rounds of quiet `settle` waits, and the frames in each. The fold's
## idle payment starts half a second after the last change, so a round has to
## outlast that and the frames the payment takes.
QUIET_ROUNDS = 3
QUIET_FRAMES = 45
SEASONS = ("spring", "summer", "autumn", "winter")
LAYERS_PREFIX = "SaCapture: layers "


def timed(door: SaraDoor, step: dict) -> float:
    """Seconds from *step* leaving to its answer."""
    began = time.monotonic()
    door.send(step)
    return round(time.monotonic() - began, 4)


def build(door: SaraDoor, depth: int) -> tuple[str, str]:
    """A fresh document of *depth* layers, and the names of its hidden light and its active layer."""
    door.send({"document": "srgb"})
    steps: list[dict] = []
    for i in range(1, depth):
        hue = (i * 37 % 100) / 100.0
        step: dict = {"add": f"L{i}", "fill": [hue, 1.0 - hue, 0.5, 0.05], "chunks": CHUNKS}
        if i % 30 == 0:
            step["group"] = True
        steps.append({"layer": step})
    for at in range(0, len(steps), 60):
        door.send_batch(steps[at : at + 60])
    light = f"L{depth - 1}"
    door.send({"layer": {"of": light, "group": True, "visible": False}})
    middle = f"L{depth // 2 + 1}"
    door.send({"layer": {"activate": middle}})
    settle(door)
    return light, middle


def settle(door: SaraDoor) -> None:
    """Waits out what the changes just made owe, before the next step is timed.

    Three things are owed after a change and paid later: the pictures in the
    rows, which wait a quarter of a second after the paint that marked them,
    the composite the change asked for, and the fold's build of the active
    layer's walk, which starts half a second after the last change and is paid
    fifteen milliseconds a frame. A run that times its first step inside that
    payment reads the stack that was just made and not the step. So the wait
    is a settle, then a second of frames for the quiet to pass and the payment
    to run, three times over, and a settle at the end.
    """
    for _ in range(QUIET_ROUNDS):
        door.send({"until": "settled"})
        door.send({"wait": QUIET_FRAMES})
    door.send({"until": "settled"})


def log_file(door: SaraDoor) -> Path:
    return door.log_dir() / "godot.log"


def read_log(door: SaraDoor, since: int) -> tuple[int, int]:
    """The bytes the log grew by since *since*, and its longest new line."""
    data = log_file(door).read_bytes()[since:]
    longest = max((len(line) for line in data.split(b"\n")), default=0)
    return len(data), longest


def opacities(door: SaraDoor, layer: str, count: int) -> list[float]:
    """*count* opacity steps on *layer*, each timed, after one that is not.

    The untimed one pays for the quiet before it. A window that has drawn
    nothing for a second waits on the compositor for a buffer at the next
    frame, 0.3 s on the nested weston the gate runs in, and the frame trail
    reads it as the draw: `draw 302.0 ms, gpu 0.9 ms, on a core 17.4 ms`, a
    frame that slept rather than one that worked. It is the window system's
    and it falls on whichever step comes first, so it is paid before the
    timing starts.
    """
    door.send({"layer": {"of": layer, "opacity": 0.5}})
    return [timed(door, {"layer": {"of": layer, "opacity": 0.4 if i % 2 == 0 else 0.6}}) for i in range(count)]


def layers_of(answer: dict) -> tuple[list, int]:
    """The stack a `layers` step answered with, and the length of the line it came on."""
    for line in answer.get("verdicts", []):
        if line.startswith(LAYERS_PREFIX):
            return json.loads(line[len(LAYERS_PREFIX) :]), len(line)
    return [], 0


def read_layers(door: SaraDoor) -> list:
    """The stack the `layers` step answers with."""
    return layers_of(door.send({"layers": True}))[0]


def state_seconds(door: SaraDoor, out: Path, depth: int) -> float:
    """Seconds for one `state` request, the 9.77 s the ask names, written and not judged.

    The dump is the whole run, not one layer's property, so its cost is
    allowed to grow with the stack. The file it writes is taken away again,
    since the proof folder is read as text.
    """
    dump = out / f"dump-{depth}.json"
    took = timed(door, {"state": str(dump)})
    dump.unlink(missing_ok=True)
    return took


def depth_run(door: SaraDoor, out: Path, depth: int) -> dict:
    light, middle = build(door, depth)
    # The stack is counted off the `layers` answer at the end rather than here.
    # That answer is a hundred thousand characters, and the frame that hands it
    # over left the step after it 0.15 s at 300 layers and at 540 alike, which
    # is the request's cost and not the step's.
    lights = opacities(door, light, 50)
    actives = opacities(door, middle, 50)
    eyes = [timed(door, {"layer": {"of": middle, "visible": i % 2 == 1}}) for i in range(200)]
    # The eyes are the history the clause asks about, and each owed the fold a
    # payment of its own, so the same wait stands between them and the steps
    # that are read after them.
    settle(door)
    lights_after = opacities(door, light, 50)
    actives_after = opacities(door, middle, 50)
    door.send({"wait": 4})
    size = log_file(door).stat().st_size
    listed, whole = layers_of(door.send({"layers": True}))
    door.send({"wait": 4})
    grew, longest = read_log(door, size)
    return {
        "depth": depth,
        "state": state_seconds(door, out, depth),
        "layers_answered": len(listed),
        "light": light,
        "active": middle,
        "light_opacity": lights,
        "light_median": statistics.median(lights),
        "light_max": max(lights),
        "light_after_eyes": lights_after,
        "light_after_eyes_median": statistics.median(lights_after),
        "light_after_eyes_max": max(lights_after),
        "active_opacity": actives,
        "active_median": statistics.median(actives),
        "active_max": max(actives),
        "eyes": eyes,
        "eyes_median": statistics.median(eyes),
        "eyes_max": max(eyes),
        "active_after_eyes": actives_after,
        "active_after_eyes_median": statistics.median(actives_after),
        "layers_answer_chars": whole,
        "log_grew_bytes": grew,
        "log_longest_line": longest,
    }


def shown(entry: dict, by_name: dict) -> bool:
    """Whether *entry* reaches the picture: itself visible and every group over it."""
    at: dict | None = entry
    guard = 0
    while at is not None and guard < 64:
        if not at["visible"]:
            return False
        at = by_name.get(at["group"]) if at["group"] else None
        guard += 1
    return True


def season_groups(layers: list, by_name: dict) -> list[str]:
    """One hidden season group a season, each inside a light group that is shown.

    The mirrors file holds a group a light and a season, `day-overcast-autumn`
    under `day-overcast` under `day`, and the painter's season switch shows
    those of one season and hides the rest. A group under a hidden light costs
    nothing to show, since nothing of it reaches the picture, so the ones
    taken are those whose groups above are all shown.
    """
    picked: dict[str, str] = {}
    for entry in layers:
        season = entry["name"].rsplit("-", 1)[-1]
        if entry["kind"] != "group" or season in picked or season not in SEASONS:
            continue
        if entry["visible"] or not shown(by_name.get(entry["group"], entry), by_name):
            continue
        picked[season] = entry["name"]
    return list(picked.values())


def mirrors_run(door: SaraDoor, source: Path, out: Path) -> dict:
    """The painter's two steps on a `cp` of the mirrors file: a season group
    shown, and the opacity of a light inside a hidden season."""
    copy = out / "mirrors-copy.sad"
    shutil.copyfile(source, copy)
    loaded = timed(door, {"load": str(copy)})
    settle(door)
    layers = read_layers(door)
    by_name = {entry["name"]: entry for entry in layers}
    shows: dict[str, float] = {}
    for name in season_groups(layers, by_name):
        began = time.monotonic()
        door.send({"layer": {"of": name, "visible": True}})
        door.send({"until": "settled"})
        shows[name] = round(time.monotonic() - began, 3)
        door.send({"layer": {"of": name, "visible": False}})
        door.send({"until": "settled"})
    light = ""
    for entry in layers:
        if entry["kind"] == "plain" and entry["group"] and not shown(entry, by_name):
            light = entry["name"]
            break
    settle(door)
    lights = opacities(door, light, 50) if light else []
    # The copy is 72 MB and the proof folder is read as text, so the run takes
    # it away again once the document it was loaded from is no longer read.
    door.send({"document": "srgb"})
    copy.unlink(missing_ok=True)
    return {
        "layers": len(layers),
        "load": loaded,
        "season_shows": shows,
        "light": light,
        "light_opacity": lights,
        "light_opacity_max": max(lights) if lights else None,
        "light_opacity_median": statistics.median(lights) if lights else None,
    }


def main() -> int:
    args = sys.argv[1:]
    mirrors = None
    if "--mirrors" in args:
        at = args.index("--mirrors")
        mirrors = Path(args[at + 1])
        del args[at : at + 2]
    out = Path(args[0]) if args else PROOF / "scenario"
    out.mkdir(parents=True, exist_ok=True)
    report: dict = {"depths": []}
    with SaraDoor(out_dir=out) as door:
        door.send({"wait": 30})
        for depth in DEPTHS:
            report["depths"].append(depth_run(door, out, depth))
        if mirrors is not None:
            report["mirrors"] = mirrors_run(door, mirrors, out)
    (out / "times.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    failed: list[str] = []
    for run in report["depths"]:
        for key in ("light_max", "light_after_eyes_max"):
            if run[key] >= STEP_LIMIT:
                failed.append(f"{run['depth']} layers: {key} {run[key]} s")
        if run["log_longest_line"] > LOG_LINE_LIMIT:
            failed.append(f"{run['depth']} layers: the layers answer left a line of {run['log_longest_line']}")
        print(
            f"{run['depth']} layers: the light's opacity median {run['light_median']} s, longest {run['light_max']} s, "
            f"after 200 eyes longest {run['light_after_eyes_max']} s, the active layer's median "
            f"{run['active_median']} s and {run['active_after_eyes_median']} s after the eyes, an eye "
            f"{run['eyes_median']} s, a layers answer of {run['layers_answer_chars']} characters left "
            f"{run['log_grew_bytes']} bytes in the log, its longest line {run['log_longest_line']}, a state request "
            f"{run['state']} s"
        )
    shallow, deep = report["depths"][0], report["depths"][-1]
    if deep["light_median"] > shallow["light_median"] * 1.2:
        failed.append(f"540 layers' median {deep['light_median']} s is more than a fifth over 300's {shallow['light_median']} s")
    if "mirrors" in report:
        seen = report["mirrors"]
        print(
            f"mirrors: {seen['layers']} layers loaded in {seen['load']} s, each season group shown in "
            f"{seen['season_shows']}, the light {seen['light']} at a median {seen['light_opacity_median']} s "
            f"and a longest {seen['light_opacity_max']} s"
        )
        failed += [f"showing {name} took {took} s" for name, took in seen["season_shows"].items() if took >= SHOW_LIMIT]
        if not seen["season_shows"]:
            failed.append("no hidden season group under a shown light was found in the mirrors file")
        if seen["light_opacity_max"] is None or seen["light_opacity_max"] >= STEP_LIMIT:
            failed.append(f"the mirrors light's longest opacity step is {seen['light_opacity_max']} s")
    for line in failed:
        print(f"not met: {line}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
