#!/usr/bin/env python3
"""Launch Sara with no module to load, and read back that it came up.

    python3 scripts/check_skeleton_boots.py

The README claims the skeleton boots with `modules/` empty, which is a claim
nothing else tests. This runs the resting-app scenario under
`SARA_MODULES_ROOT` pointed at an empty directory, which is the door
`core/loader/module_loader.gd` reads in place of `res://modules`, and asserts three
things off the artefacts: the scenario ran to its last step, so the window
opened and every frame it asked for was drawn; the toolbox reports zero tools
and its one visible control is the empty state; and the run's log carries no
problem line beyond the one the offscreen compositor prints on every run.

What it proves and what it does not. The loader finds nothing and the UI
draws its empty states without an error, which is the half a launch can show.
The other half is the parse: the module scripts are still in the tree and
their `class_name`s still resolve, so a skeleton file that names one parses
here and would not in a clone without the submodules.
`tests/test_the_skeleton_without_modules.gd` holds that half, by grep, and its
allowlist is the list of files the claim is still false for.

Exit 0 when every assertion holds, 1 with the reason otherwise. `run_tests.sh`
runs it after the suite on a full run, so it needs what the suite needs: a
compositor, real or nested, and `weston` for the nested one.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

PROJECT_DIR = Path(__file__).resolve().parent.parent
SCENARIO = PROJECT_DIR / "scenarios" / "the-skeleton-without-modules.json"
SHOT = PROJECT_DIR / "scripts" / "sara_shot.py"
STATE = "b-state.json"
ROOT_VARIABLE = "SARA_MODULES_ROOT"

# The nested compositor cannot answer this query and the engine says so on
# every offscreen run, with a second line naming where it was asked.
ENGINE_NOISE = (
    "Couldn't get Vulkan surface capabilities",
    "at: swap_chain_resize",
)


def is_engine_noise(line: str) -> bool:
    return any(marker in line for marker in ENGINE_NOISE)


def problems_in(log_text: str) -> list[str]:
    """Every problem line of a run log that is not the compositor's own."""
    sys.path.insert(0, str(SHOT.parent))
    import sara_shot  # noqa: E402, imported here so `--help` needs no Godot

    return [line for line in log_text.splitlines() if sara_shot.is_problem(line) and not is_engine_noise(line)]


def check(out_dir: Path) -> list[str]:
    """The failures found in one run's artefacts, empty when it booted."""
    failures: list[str] = []
    state_path = out_dir / STATE
    if not state_path.exists():
        return [f"the scenario never reached its state dump, so the window did not come up: {out_dir}"]
    state = json.loads(state_path.read_text(encoding="utf-8"))
    toolbox = state.get("toolbox", {})
    if not toolbox.get("present", False):
        failures.append("the toolbox docker was not built")
    if toolbox.get("tools", -1) != 0:
        failures.append(f"the toolbox reports {toolbox.get('tools')} tool(s), and there is no module to bring one")
    names = [button.get("name") for button in toolbox.get("buttons", [])]
    if names != ["EmptyState"]:
        failures.append(f"the toolbox shows {names} rather than its empty state alone")
    log_path = out_dir / "run.log"
    if not log_path.exists():
        failures.append("the run wrote no run.log")
    else:
        problems = problems_in(log_path.read_text(encoding="utf-8"))
        if problems:
            shown = "\n    ".join(sorted(set(problems))[:8])
            failures.append(f"the console carries {len(problems)} problem line(s):\n    {shown}")
    return failures


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="sara-no-modules-") as empty, tempfile.TemporaryDirectory(
        prefix="sara-boot-check-"
    ) as out:
        env = dict(os.environ)
        env[ROOT_VARIABLE] = empty
        cmd = [sys.executable, str(SHOT), "--scenario", str(SCENARIO), "--out", out]
        proc = subprocess.run(cmd, env=env, capture_output=True, encoding="utf-8", cwd=PROJECT_DIR)
        failures = check(Path(out))
        if proc.returncode not in (0, 2):
            # 2 is the engine failing to tear down after the scenario finished,
            # which sara_shot.py reports and which is not the app failing to boot.
            failures.append(f"sara_shot.py exited {proc.returncode}:\n{proc.stderr.strip()[-2000:]}")
    if failures:
        print("The skeleton did not boot cleanly with no module to load:", file=sys.stderr)
        for failure in failures:
            print(f"  {failure}", file=sys.stderr)
        return 1
    print("The skeleton boots with no module to load: the window opened, the toolbox is empty, no error.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
