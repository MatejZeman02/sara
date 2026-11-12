#!/usr/bin/env python3
"""Comparing what a scenario file left behind with what a conversation left.

The comparator lives here rather than in `test_door_replay.py` so that the
door's `scenario` tool checks a file it wrote with the same rules the replay
test checks one with. A second copy of this list would drift, and the first
thing to drift would be the reasons.

    from sara_replay import differences, replay

    final = replay(Path("scenarios/navigate-the-canvas.json"))
    for line in differences(final, live_dump):
        print(line)

`differences` answers a list of one-line complaints, empty when the two dumps
agree. A short list of keys is allowed to disagree and every one of them is
named below with its reason. Everything else has to be equal: if it is not,
either the door is not running the same executor or the dump has a key nobody
knew was unstable, and both of those are worth a failure.
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent
PROJECT_DIR = SCRIPTS.parent

## Top-level dump keys the two runs may disagree on, and why each one.
ALLOWED: dict[str, str] = {
    # Cumulative from process start, and the two runs reach the last step
    # through a different number of frames.
    "gpu": "dispatch and workgroup counters are cumulative over the process",
    "perf": "a measuring window's microseconds, driver ticks and frame counts are the run's own",
    "vram_bytes": "one run has written a PNG and the other has not, and a shot allocates",
    # The pointer is the compositor's, and Wayland will not let a client place it.
    "pointer_screen": "the OS pointer is where the person left it, in both runs",
    "pointer_warp_works": "a probe of the compositor rather than state of the app",
    "door_pointer": "the frame numbers its motions were heard in are the run's own",
    "hovered_control": "follows the OS pointer",
    "cursor_overlays": "reads the OS pointer every frame",
    # Wall clock, process identity and where each run was told to write.
    "build": "carries the build stamp",
    "autosave": "carries the wall clock of the last write",
    "last_save": "carries how long a save took",
    "windows": "carries each window's own title, and the scenario run names its output in it",
    # The scenario run ends with a shot and the door run does not, so the
    # canvas's composite counters and timings differ by that frame.
    "canvases": "compared field by field below, minus the three cumulative ones",
    "info_docker": "compared section by section below: its GPU section is the counters above as strings",
    "docker_layout": "compared field by field below, minus the one that is a clock reading",
    "brush_dabs": "compared below, minus the two fields of its sample that are readings of the clock",
    "toggles": "compared below, minus the instance counter Godot puts in an auto-generated node name",
}

## `@PanelContainer@682`, the name Godot gives a node nobody named, in the paths
## `toggles` reports.
##
## The number is a process-wide instance counter, so it says how many nodes the
## run had built by the time that one was made and nothing whatever about the
## app. A session that opened two documents and restarted reads
## `@PanelContainer@789` where a five-step replay of the file it wrote reads
## `@PanelContainer@682`, and the nine layer-row toggles under it were the
## whole of the disagreement. Matched on the whole segment rather than on the
## digits alone, so a node somebody named `Foo@3` is left as it is.
AUTO_NODE_NAME = re.compile(r"@[^@/]+@\d+")

## The one field of `docker_layout` that is a clock rather than a layout.
##
## `saves_allowed` is `_is_ready_done and Time.get_ticks_msec() - _startup_ticks
## >= LAYOUT_SETTLE_MS`, which is 1500 in `ui/main/main_dockers.gd`. A scenario file
## that finishes inside a second and a half reads false and a conversation,
## which by its nature does not, reads true, so the two runs disagree on it
## whenever the file half is quick and agree whenever it is slow. That made
## `test_door_replay.py` fail six runs in eight rather than eight in eight,
## which is the worse of the two, because a fixer who runs it once sees it pass.
##
## The rest of the block is compared, because where the dockers are is exactly
## what a replay of a scenario that places them has to agree on.
ALLOWED_DOCKER_LAYOUT = {"saves_allowed"}

## The one Info docker section that carries the cumulative counters and the
## frame timings, which is the `gpu` key again in the words a painter reads.
ALLOWED_INFO_SECTIONS = {"GPU"}

## Rows of the other Info sections that restate an allowed key, by section.
## `VRAM all` is `vram_bytes` in megabytes, allowed above because a shot
## allocates, and a door session on an exported build read 111.6 MB where the
## replay of its file read 113.6 MB, and 113.6 on a second try.
ALLOWED_INFO_ROWS = {"Document": {"VRAM all"}}

## Fields inside `canvases[]` that move for the same reason.
ALLOWED_CANVAS = {"composites", "composite_usec_total", "composite_usec_last"}

## The two fields of `brush_dabs.sample` that are readings of the clock.
##
## `elapsed_ms` is the time since the press and `drawing_speed` is distance over
## that time, so a stroke sent down two paths disagrees on both by however busy
## the machine was: 6098.0 against 5694.0 milliseconds, and 0.126 against 0.093,
## in the session that filed this. Everything else the sample carries is where
## the pointer was, how hard it pressed and how far it had gone, which two runs
## of the same stroke have to agree on, and so are the dabs themselves.
##
## A block the dump gains and this list does not hear about leaves the
## comparison green only while no scenario exercises it: `brush_dabs` was green
## until `f101-navigate-scenario-navigates-nothing` put two strokes into the one
## file the door's own proof replays.
ALLOWED_DAB_SAMPLE = {"elapsed_ms", "drawing_speed"}

## How long a replay of one scenario may take before it is a hang rather than a
## slow shader compile. The first run of a new `.gmacs` is most of it.
REPLAY_TIMEOUT_S = 300


def differences(reference: dict, other: dict) -> list[str]:
    """Every way the two dumps disagree that is not on the allowed list.

    *reference* is conventionally the run from the file and *other* the live
    session, but the comparison is symmetric and the messages name neither.
    """
    if reference is None or other is None:
        return ["one of the two runs left no state dump at all"]
    out: list[str] = []
    only_reference = sorted(set(reference) - set(other))
    only_other = sorted(set(other) - set(reference))
    if only_reference or only_other:
        out.append(f"the two runs answer with different keys: {only_reference} against {only_other}")
    for key in sorted(set(reference) & set(other)):
        if key in ALLOWED:
            continue
        if reference[key] != other[key]:
            out.append(f"{key} differs")
    out.extend(_canvas_differences(reference, other))
    out.extend(_info_differences(reference, other))
    out.extend(_docker_layout_differences(reference, other))
    out.extend(_brush_dabs_differences(reference, other))
    out.extend(_toggles_differences(reference, other))
    return out


def _brush_dabs_differences(reference: dict, other: dict) -> list[str]:
    """The dabs the brush evaluated and what it read them from, without the
    sample's two clock fields.

    A whole `ALLOWED` entry is the other way to answer the clock fields and the
    wrong one: the block exists because a stroke that came out the wrong weight is a
    wrong number in one of nine options and no screenshot can say which, so a
    replay that agrees about everything except the dabs has proved the least
    interesting half of a painting session. Two fields are a clock and the rest
    is the point.
    """
    left = dict(reference.get("brush_dabs") or {})
    right = dict(other.get("brush_dabs") or {})
    left["sample"] = {k: v for k, v in (left.get("sample") or {}).items() if k not in ALLOWED_DAB_SAMPLE}
    right["sample"] = {k: v for k, v in (right.get("sample") or {}).items() if k not in ALLOWED_DAB_SAMPLE}
    if left != right:
        moved = sorted(k for k in set(left) | set(right) if left.get(k) != right.get(k))
        return [f"brush_dabs differs outside the sample's clock fields: {moved}"]
    return []


def _toggles_differences(reference: dict, other: dict) -> list[str]:
    """Every toggle button, whether it is on and whether it is styled as on,
    with the instance counter taken out of the path it is reported under.

    A whole `ALLOWED` entry is the other way and the wrong one for the same
    reason `brush_dabs` is not one: the block is in the dump so that a
    button that says nothing about being on is a failure a replay can see, and
    a replay that stopped reading the toggles would agree about all of them.
    The counter is the only part of the block two runs may disagree on.
    """
    left = _named_toggles(reference.get("toggles"))
    right = _named_toggles(other.get("toggles"))
    if left == right:
        return []
    if left is None or right is None:
        return ["one run reports toggles and the other does not"]
    moved = sorted(
        entry.get("path", entry.get("name", "?"))
        for entry in left + right
        if (entry not in left) or (entry not in right)
    )
    return [f"toggles differs outside the auto-generated node names: {sorted(set(moved))}"]


def _named_toggles(block: object) -> list | None:
    """*block* with `@PanelContainer@682` cut back to `@PanelContainer@` in
    every path, so two runs that built a different number of nodes compare."""
    if not isinstance(block, list):
        return None
    out = []
    for entry in block:
        if not isinstance(entry, dict):
            out.append(entry)
            continue
        trimmed = dict(entry)
        if isinstance(trimmed.get("path"), str):
            trimmed["path"] = AUTO_NODE_NAME.sub("@", trimmed["path"])
        out.append(trimmed)
    return out


def _docker_layout_differences(reference: dict, other: dict) -> list[str]:
    """Where every docker is, which is the half of `docker_layout` a replay has
    to agree on, without the one field that is a reading of the clock."""
    left = {k: v for k, v in (reference.get("docker_layout") or {}).items() if k not in ALLOWED_DOCKER_LAYOUT}
    right = {k: v for k, v in (other.get("docker_layout") or {}).items() if k not in ALLOWED_DOCKER_LAYOUT}
    if left != right:
        moved = sorted(k for k in set(left) | set(right) if left.get(k) != right.get(k))
        return [f"docker_layout differs outside its settle flag: {moved}"]
    return []


def _canvas_differences(reference: dict, other: dict) -> list[str]:
    """The canvas is the one allowed key worth going into, because the view is
    what a navigation scenario moves and what a reader would check by hand."""
    left = reference.get("canvases") or []
    right = other.get("canvases") or []
    if len(left) != len(right):
        return [f"one run has {len(left)} canvases and the other {len(right)}"]
    out: list[str] = []
    for i, (one, two) in enumerate(zip(left, right)):
        trimmed_one = {k: v for k, v in one.items() if k not in ALLOWED_CANVAS}
        trimmed_two = {k: v for k, v in two.items() if k not in ALLOWED_CANVAS}
        if trimmed_one != trimmed_two:
            out.append(f"canvas {i} differs outside its cumulative fields")
    return out


def _info_differences(reference: dict, other: dict) -> list[str]:
    """The Info docker is the dump in the words a painter reads, so every
    section but the counters is worth the same comparison: the document, the
    history, the colour space and the active layer all have to agree."""
    if _compared_info(reference) != _compared_info(other):
        return ["the Info docker says something different outside its GPU section"]
    return []


def _compared_info(dump: dict) -> list[dict]:
    """The Info docker's sections minus the allowed ones and the allowed rows."""
    out = []
    for section in dump.get("info_docker") or []:
        name = section.get("section")
        if name in ALLOWED_INFO_SECTIONS:
            continue
        dropped = ALLOWED_INFO_ROWS.get(name, set())
        rows = section.get("rows")
        if dropped and isinstance(rows, dict):
            section = {**section, "rows": {k: v for k, v in rows.items() if k not in dropped}}
        out.append(section)
    return out


def state_names(steps: list[dict]) -> list[str]:
    """Every `state` step's name, in order, each name once.

    A scenario may write the same name twice and the second write overwrites
    the first, so the dump on disk under a repeated name is the last one and
    there is nothing to compare the earlier ones against. The order kept is
    the order of first appearance, which is the order a reader of the file
    sees.
    """
    out: list[str] = []
    for step in steps:
        if not isinstance(step, dict) or "state" not in step:
            continue
        name = str(step["state"])
        if name not in out:
            out.append(name)
    return out


def last_state_name(steps: list[dict]) -> str | None:
    """The name of the last `state` step. A scenario with none cannot be
    compared against anything."""
    names = [step["state"] for step in steps if isinstance(step, dict) and "state" in step]
    return str(names[-1]) if names else None


def differences_at_each_state(replayed: dict, live: dict) -> list[str]:
    """Every way two runs of the same scenario disagree, at every dump it
    writes rather than at its last one.

    Both arguments are `{state name: dump}`. Each line carries the name of the
    step it came from, because "canvas 0 differs outside its cumulative fields"
    over an eight-dump scenario says nothing about where to look.

    **The last dump alone is not a verification.** A scenario that ends on an
    undo has the document it started with in its last dump whichever way the
    run went, and one such run drew no crop rectangle at all and installed as
    verified. Every state the scenario bothered to write is a state its author
    thought worth reading, and a middle one that disagrees is the whole of what
    that reading was for.
    """
    out: list[str] = []
    only_replayed = [name for name in replayed if name not in live]
    only_live = [name for name in live if name not in replayed]
    if only_replayed or only_live:
        out.append(f"the two runs wrote different dumps: {sorted(only_replayed)} against {sorted(only_live)}")
    for name in replayed:
        if name not in live:
            continue
        out.extend(f"at {name!r}: {line}" for line in differences(replayed[name], live[name]))
    return out


def dump_at_the_last_state(steps: list[dict], answers: list[dict]) -> dict:
    """The door's dump from the step `replay()` reads on the other side.

    `replay()` answers the file the *last `state` step* wrote, so a caller that
    compares it against the *last answer* is comparing two moments whenever a
    scenario has steps after that state. Three committed scenarios do:
    `toolbox-flyouts-reorder-by-drag` closes the flyout, puts the toolbox
    back to a row and deletes a layout preset in its last ten steps, and
    `the-texture-page` and `d11-...-with-the-editor-open` each close the
    Brush Editor in one. Compared at the last answer all three read as the door
    reaching a different state, and compared here all three agree exactly.

    Raises when the scenario has no `state` step or the answers do not carry
    the one it names, because a comparison that quietly fell back to the last
    answer is the bug this exists to stop.
    """
    want = last_state_name(steps)
    if want is None:
        raise RuntimeError("the scenario holds no state step, so there is no dump to compare")
    if len(answers) != len(steps):
        raise RuntimeError(f"{len(steps)} steps were sent and {len(answers)} answers came back")
    for step, answer in zip(reversed(steps), reversed(answers)):
        if isinstance(step, dict) and step.get("state") == want:
            dump = answer.get("state")
            if not dump:
                raise RuntimeError(f"the answer to the {want!r} step carries no dump")
            return dump
    raise RuntimeError(f"no answer belongs to the {want!r} step")


def replay_states(scenario: Path, out_dir: Path, timeout: float = REPLAY_TIMEOUT_S) -> dict:
    """Runs a scenario file through `sara_shot.py --scenario` and answers every
    dump it wrote, `{state name: dump}`, in the file's own order.

    Raises `RuntimeError` when the run failed or wrote no dump for a name the
    file asks for, because a replay that did not happen must never read as a
    replay that agreed, and a middle step that wrote nothing is exactly the
    case this exists to catch.
    """
    steps = json.loads(Path(scenario).read_text(encoding="utf-8"))
    names = state_names(steps)
    if not names:
        raise RuntimeError(f"{scenario} holds no state step, so there is no dump to compare")
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    run = subprocess.run(
        [sys.executable, str(SCRIPTS / "sara_shot.py"), "--scenario", str(scenario), "--out", str(out_dir)],
        capture_output=True,
        encoding="utf-8",
        timeout=timeout,
    )
    if run.returncode != 0:
        raise RuntimeError(f"the replay of {scenario} exited with {run.returncode}: {run.stderr[-2000:]}")
    out: dict = {}
    for name in names:
        written = out_dir / f"{name}.json"
        if not written.exists():
            raise RuntimeError(f"the replay of {scenario} wrote no {written.name}, so the run did not reach that step")
        out[name] = json.loads(written.read_text(encoding="utf-8"))
    return out


def replay(scenario: Path, out_dir: Path, timeout: float = REPLAY_TIMEOUT_S) -> dict:
    """The dump a scenario's last `state` step wrote, for a caller that wants
    the one moment rather than all of them."""
    steps = json.loads(Path(scenario).read_text(encoding="utf-8"))
    name = last_state_name(steps)
    if name is None:
        raise RuntimeError(f"{scenario} holds no state step, so there is no dump to compare")
    return replay_states(scenario, out_dir, timeout)[name]
