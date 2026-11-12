#!/usr/bin/env python3
"""The seven deterministic checks a door answer carries.

A script error, an engine error, a refusal, a stroke the tool in hand turned
away, a step that changed nothing, a layer count that disagrees with the
docker's rows, and VRAM that grew across an undo. None of them needs judgement, so none of them should need a model to
notice it, and `sara_door.py` runs them on every answer. The refusal is its
own kind because a gesture the app refused with a sentence for the painter,
read as an engine error, says something broke when nothing did.

**A finding is a flag, not a verdict.** A `no_change` on a step that genuinely
changes nothing visible is expected and correct, and an agent that reads every
finding as a bug files rubbish. Each `says` is worded to be read that way.

Every entry is `{"kind":..., "says":..., "evidence": {...}, "step": {...}}`,
where `step` is the request that raised it. The requests since the last
document load are `Findings.steps`, which the retired MCP `state` tool handed
back with `dump` set, so anything built on a finding replays through
`sara_shot.py --scenario`. A finding carries the one request and not that whole
list, whose cost grows with the session's length.
"""

from __future__ import annotations

import sys
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent))

import godot_console  # noqa: E402

## Dump keys that differ between two answers for reasons that are not the step.
##
## The filter is the whole difficulty of `no_change`, so every exclusion is
## written here with why beside it rather than in a commit message: a filter
## nobody can read is what turns this check into noise an agent learns to skip.
VOLATILE_KEYS: dict[str, str] = {
    # Cumulative since the process started, so they differ after any frame.
    "gpu": "dispatch and workgroup counters are cumulative, so they move on every frame",
    # The last perf window's block, whose VRAM and clock halves are read when it
    # is folded, so a `read` or an `end` between two answers moves it.
    "perf": "the last measuring window's figures, microseconds and driver ticks that never repeat",
    # Wayland refuses a warp, so the real pointer wanders under the app.
    "pointer_screen": "the OS pointer moves on its own under Wayland and the app cannot place it",
    "pointer_warp_works": "a probe result rather than state, and it is answered once per run",
    "door_pointer": "the frame each motion of the door's last press was heard in, which no two answers share",
    # The window's own clock, and a build stamp that carries a timestamp.
    "build": "carries the build stamp, which is not state a step can change",
    "autosave": "carries the wall clock of the last write",
    "last_save": "carries how long a save took, which never repeats",
    # Where the GUI thinks the pointer is, which follows the pointer above.
    "hovered_control": "follows the OS pointer rather than the step",
    "cursor_overlays": "reads the OS pointer position every frame",
}

## Keys inside `canvases[]` that move for the same reasons.
VOLATILE_CANVAS_KEYS: dict[str, str] = {
    "composites": "cumulative, one per composited frame",
    "composite_usec_total": "cumulative microseconds",
    "composite_usec_last": "the last frame's microseconds, which never repeat",
}

## Engine errors the harness itself produces, which are not the session's.
##
## A check that fires on healthy work is worse than no check, and the offscreen
## compositor raises the first of these on nearly every frame: it is weston's
## headless backend having no real surface to report capabilities for, and it
## expected on this setup. Matched on a substring rather than a whole line,
## because the engine appends a code.
IGNORED_ERRORS: dict[str, str] = {
    "Couldn't get Vulkan surface capabilities": "the nested headless compositor has no real surface, and this fires every frame",
    "Vulkan: Cannot create a swapchain": "the same, at the moment the window is first sized",
    "GDScript::open_requested": "the module loader unregisters menus at exit, when the tree is already gone",
}

## What a refusal's warning opens with, `SaProblems.REFUSED` in
## `core/api/sa_problems.gd`, which logs every refusal as a warning so that an
## error line stays a fault.
REFUSED = "Refused, "

## What a door stroke's line holds when the tool in hand turned the stroke
## away, written by `harness/scenario/sa_scenario_stroke.gd`. That line is
## an error of the answer's, so a client reading `errors` sees a stroke
## that laid nothing, and the findings name it as a refused stroke rather than
## as an engine error.
STROKE_LINE = "SaCapture: stroke"
STROKE_REFUSED = "refused by the"

## Steps that are asking a question rather than doing something, so a dump that
## did not change after one is the right answer and not a finding.
##
## The three input steps are here for a reason worth reading rather than for
## quiet. A `press` opens a gesture and the state moves when the gesture does,
## on the motion after it or on the release, so the press itself changing
## nothing is the normal case. A `release` closes one the same way. And an
## injected `move` is not delivered to a Control's `gui_input` at all unless a
## press has already opened a stroke, which `ui/sa_capture_input.gd` records:
## a hover reaches nothing whatever its coordinates. Without these three, the
## eighteen steps of `scenarios/navigate-the-canvas.json` raise two findings that are
## both correct and both noise.
##
## `look` and `measure` are here for the same reason. Both read the canvas and
## write nothing, so without them every one of a painting session's turns raises
## a `no_change` that is the correct answer, and a loop that shows a model its
## findings hands it one false problem per turn.
PASSIVE_STEPS = {
    "state",
    "shot",
    "look",
    "measure",
    "wait",
    "probe",
    "layout_rows",
    "theme_rows",
    "prefs_search",
    "prefs_frame",
    "press",
    "release",
    "move",
}


class Findings:
    """The checks, and the little state they need between answers.

    Held per session rather than per call: three of the six compare an answer
    with the one before it, and one reads the run log from where the last look
    ended.
    """

    def __init__(self, log_dir: Path | None = None) -> None:
        ## Kept for a caller that has no pipe to hand, and unused by the door.
        self.log_dir = log_dir
        self._log_offset = 0
        self._previous: dict | None = None
        self._previous_step: dict | None = None
        ## Requests since the last document load, the window a finding replays
        ## in as a scenario. A finding names its own step only, and this list
        ## goes out once, with the dump.
        self.steps: list[dict] = []

    def start(self) -> None:
        """Called when a session opens, so the log window starts empty."""
        self._log_offset = self._log_size()

    def check(self, step: dict, answer: dict, printed: list[str] | None = None) -> list[dict]:
        """Every finding this step raised, in the order they are cheap to read.

        *printed* is the lines the app wrote while the step ran, which the door
        has off the process pipe. Given them, the log is not read at all: the
        engine's file logger buffers, so a line raised by this step is not in
        the file when this runs and turns up several answers later, attached to
        the wrong step. The pipe is the same lines, live and already split by
        step, and it carries `print` output the log never sees.
        """
        if step.get("load") or step.get("document") or step.get("import"):
            self.steps = []
        self.steps.append(step)

        found: list[dict] = []
        found.extend(self._log_findings(printed))
        found.extend(self._refused_strokes(answer))
        found.extend(self._no_change(step, answer))
        found.extend(self._layer_count(answer))
        found.extend(self._vram_after_undo(step, answer))

        self._previous = answer.get("state")
        self._previous_step = step
        for entry in found:
            entry["step"] = step
        return found

    # --- The five -------------------------------------------------------------

    def _log_findings(self, printed: list[str] | None) -> list[dict]:
        """`SCRIPT ERROR` and `ERROR` lines the step raised, and the refusals.

        Through `godot_console.py`'s own parser rather than a second one, so a
        backtrace is read here exactly the way a person reads it.
        """
        if printed is not None:
            text = "\n".join(printed)
        else:
            if self.log_dir is None:
                return []
            logs = godot_console.collect_logs(Path(self.log_dir), all_runs=False)
            if not logs:
                return []
            text = self._read_since(logs[0])
        if not text:
            return []
        out: list[dict] = []
        for entry in godot_console.deduplicate(godot_console.parse_log_text(text)):
            if refused_stroke(entry.message):
                # The answer's own `errors` entry carries it, read below.
                continue
            if entry.level == "SCRIPT ERROR":
                kind = "script_error"
                says = "a script error was raised while this step ran, which is a bug in the app rather than in the step"
            elif entry.level == "ERROR":
                kind = "engine_error"
                says = "the engine reported an error while this step ran, which may be the step or may be the driver"
            elif entry.level == "WARNING" and entry.message.startswith(REFUSED):
                kind = "refusal"
                says = (
                    "the app refused the step with the sentence a painter reads in the corner, which is the "
                    "app working as meant when the step asked for something that cannot happen"
                )
            else:
                continue
            if any(noise in entry.message for noise in IGNORED_ERRORS):
                continue
            out.append(
                {
                    "kind": kind,
                    "says": says,
                    "evidence": {"message": entry.message, "origin": entry.origin, "count": entry.count},
                }
            )
        return out

    @staticmethod
    def _refused_strokes(answer: dict) -> list[dict]:
        """A stroke the tool in hand turned away, by its entry in the answer's `errors`.

        The step was called and laid nothing, which the line's own words say
        why, a hidden layer or a locked one. It is no fault of the app's, and
        it is the one thing a script that meant to paint has to hear.
        """
        out: list[dict] = []
        for line in answer.get("errors") or []:
            if not refused_stroke(str(line)):
                continue
            out.append(
                {
                    "kind": "refused_stroke",
                    "says": (
                        "the tool in hand turned the stroke away and it laid nothing, for the reason the line "
                        "gives, which is the app working as meant and a stroke that did not happen"
                    ),
                    "evidence": {"message": str(line)},
                }
            )
        return out

    def _no_change(self, step: dict, answer: dict) -> list[dict]:
        """An acting step whose dump is the dump before it."""
        state = answer.get("state") or {}
        if self._previous is None or not state:
            return []
        if any(key in PASSIVE_STEPS for key in step):
            return []
        if filtered(self._previous) != filtered(state):
            return []
        return [
            {
                "kind": "no_change",
                "says": (
                    "nothing in the dump moved, which is expected for a step that changes nothing visible "
                    "and is worth a look for one that should have"
                ),
                "evidence": {"step": step, "compared": "the dump with volatile keys removed"},
            }
        ]

    @staticmethod
    def _layer_count(answer: dict) -> list[dict]:
        """`document.layers` against the rows the docker is showing for layers.

        A filter attached to a layer or to the document is a row of its own,
        `"kind": "filter"`, and no layer, so it is not counted. Counting it
        makes every layer carrying a filter a finding.
        """
        state = answer.get("state") or {}
        document = state.get("document") or {}
        docker = state.get("layers_docker") or {}
        if "layers" not in document or "rows" not in docker:
            return []
        rows = sum(1 for row in docker["rows"] if row.get("kind") != "filter")
        layers = int(document["layers"])
        if rows == layers:
            return []
        return [
            {
                "kind": "layer_count",
                "says": (
                    "the document holds %d layers and the docker is showing %d layer rows, so one of the two "
                    "did not follow the other. A folded group hides its rows on purpose, which is the one "
                    "case where this is not a fault" % (layers, rows)
                ),
                "evidence": {"document_layers": layers, "docker_rows": rows},
            }
        ]

    def _vram_after_undo(self, step: dict, answer: dict) -> list[dict]:
        """VRAM above where it was, across an undo."""
        if "undo" not in step or self._previous is None:
            return []
        before = int(self._previous.get("vram_bytes", 0))
        after = int((answer.get("state") or {}).get("vram_bytes", 0))
        if after <= before:
            return []
        return [
            {
                "kind": "vram_after_undo",
                "says": (
                    "an undo left more texture memory alive than there was before it, %d bytes more. "
                    "The count is every SaTexture including the history's own, so a step that pushes a "
                    "snapshot as it undoes will show here honestly" % (after - before)
                ),
                "evidence": {"before": before, "after": after, "grew_by": after - before},
            }
        ]

    # --- The log window -------------------------------------------------------

    def _log_size(self) -> int:
        if self.log_dir is None:
            return 0
        logs = godot_console.collect_logs(Path(self.log_dir), all_runs=False)
        return logs[0].stat().st_size if logs else 0

    def _read_since(self, path: Path) -> str:
        try:
            with path.open("r", encoding="utf-8", errors="replace") as file:
                file.seek(self._log_offset)
                text = file.read()
                self._log_offset = file.tell()
                return text
        except OSError:
            return ""


def _emptied_if_volatile(block: dict) -> "dict | None":
    """A block that marks itself volatile, with everything but its name gone.

    Emptied rather than dropped, so a block inside a list keeps its place and
    the indices either side of it still line up in a diff.
    """
    if block.get("volatile") is not True:
        return None
    return {key: block[key] for key in ("section", "volatile") if key in block}


def _without_volatile(value: Any) -> Any:
    """The same value with every block that marks itself volatile emptied out.

    **The producer knows and this file does not.** A list of volatile keys kept
    here is right that the GPU counters are cumulative and wrong about where
    they all are: the Info docker's own Performance section holds the same seven
    numbers under `info_docker[].rows`, so `no_change` fires on no step that
    causes a dispatch, and reads as healthy from every angle except a diff
    nobody is taking. A `"volatile": true` written by whatever builds the block
    costs one key in the dump and saves this file from having to know a row
    label it cannot see change.
    """
    if isinstance(value, list):
        return [_without_volatile(item) for item in value]
    if isinstance(value, dict):
        emptied = _emptied_if_volatile(value)
        if emptied is not None:
            return emptied
        return {key: _without_volatile(item) for key, item in value.items()}
    return value


def filtered(state: dict) -> dict[str, Any]:
    """The dump with everything that moves on its own taken out.

    Two rules, and the second is why the first was not enough. The key lists
    above name the blocks this file knows about, and `_without_volatile` walks
    the rest for blocks that say so themselves.
    """
    out = {key: value for key, value in state.items() if key not in VOLATILE_KEYS}
    canvases = out.get("canvases")
    if isinstance(canvases, list):
        out["canvases"] = [
            {key: value for key, value in canvas.items() if key not in VOLATILE_CANVAS_KEYS}
            for canvas in canvases
            if isinstance(canvas, dict)
        ]
    return {key: _without_volatile(value) for key, value in out.items()}


def refused_stroke(message: str) -> bool:
    """Whether *message* is a door stroke's line saying the tool turned it away."""
    return STROKE_LINE in message and STROKE_REFUSED in message
