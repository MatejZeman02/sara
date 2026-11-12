#!/usr/bin/env python3
"""Run a scenario and fail when Sara aborts at exit or leaves an object alive.

    python3 scripts/check_scenario_exit.py                 # the default scenario
    python3 scripts/check_scenario_exit.py --runs 5        # five runs of it
    python3 scripts/check_scenario_exit.py scenarios/x.json --out ~/proof
    python3 scripts/check_scenario_exit.py --log run.log   # read a run already made

A run that aborts after its last step still writes its pictures, so
`sara_shot.py` treats it as a run, and `# exit -6` in its `run.log` reaches
nobody: a scenario has aborted with `double free or corruption` and printed
"2 ObjectDB instances were leaked at exit" through a green board, because
`run_tests.sh` fails a suite run on that line and nothing failed a scenario run
on it. This
reads the two things off each run's log, the exit line `write_run_log` puts
second and the leak line `shot_problems.LEAK_PATTERN` names, beside the words
glibc and Godot's crash handler print, and exits 1 naming them.

The default scenario opens the one search three ways, so a run boots every
packaged module and builds the settings' rows out of sight. That is where both
faults lived: the Sphere module's preloaded include was a threaded load's token
left alive at exit, and `QuickSearch.found`, a static holding the search
index's lambdas, was freed twice at teardown. `run_tests.sh` runs this after a
full run, beside `check_skeleton_boots.py`, which boots with no module and so
meets neither.

Exit 0 when every run is clean, 1 with the reasons otherwise.
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
import tempfile
from pathlib import Path

PROJECT_DIR = Path(__file__).resolve().parent.parent
SHOT = PROJECT_DIR / "scripts" / "sara_shot.py"
DEFAULT_SCENARIO = PROJECT_DIR / "scenarios" / "f3-the-loupe-and-help-search-open-one-search.json"

EXIT_LINE = re.compile(r"^# exit (-?\d+)$", re.MULTILINE)

# What a teardown that corrupts the heap leaves in the log: glibc's abort
# messages and the first line of Godot's crash handler.
CRASH_MARKERS = (
    "double free or corruption",
    "corrupted size vs. prev_size",
    "free(): invalid",
    "malloc(): ",
    "handle_crash: Program crashed",
)


def leak_pattern() -> re.Pattern[str]:
    """The pattern `run_tests.sh` fails on, read from the module that owns it."""
    sys.path.insert(0, str(SHOT.parent))
    from shot_problems import LEAK_PATTERN  # noqa: E402

    return re.compile(LEAK_PATTERN)


def findings(log_text: str) -> list[str]:
    """What is wrong with one run, read off its `run.log`, empty when clean."""
    found: list[str] = []
    exits = EXIT_LINE.findall(log_text)
    if not exits:
        found.append("the log has no `# exit` line, so the run never ended")
    elif int(exits[0]) != 0:
        found.append(f"# exit {exits[0]}")
    leaks = leak_pattern()
    for line in log_text.splitlines():
        stripped = line.strip()
        if leaks.search(stripped) or any(marker in stripped for marker in CRASH_MARKERS):
            found.append(stripped)
    return found


def run_once(scenario: Path, out_dir: Path) -> str:
    """One run of *scenario* through `sara_shot.py`, and the log it wrote."""
    cmd = [sys.executable, str(SHOT), "--scenario", str(scenario), "--out", str(out_dir)]
    subprocess.run(cmd, capture_output=True, encoding="utf-8", cwd=PROJECT_DIR)
    log_path = out_dir / "run.log"
    return log_path.read_text(encoding="utf-8", errors="replace") if log_path.exists() else ""


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("scenario", nargs="?", type=Path, default=DEFAULT_SCENARIO)
    parser.add_argument("--runs", type=int, default=1, help="how many runs of the scenario")
    parser.add_argument("--out", type=Path, help="keep each run under OUT/run-N rather than a temporary folder")
    parser.add_argument("--log", type=Path, action="append", default=[], help="read a run.log already written")
    args = parser.parse_args(argv)

    reports: list[tuple[str, list[str]]] = []
    if args.log:
        for path in args.log:
            reports.append((str(path), findings(path.read_text(encoding="utf-8", errors="replace"))))
    else:
        for index in range(1, args.runs + 1):
            if args.out is not None:
                out_dir = args.out / f"run-{index}"
                out_dir.mkdir(parents=True, exist_ok=True)
                reports.append((str(out_dir / "run.log"), findings(run_once(args.scenario, out_dir))))
                continue
            with tempfile.TemporaryDirectory(prefix="sara-scenario-exit-") as out:
                reports.append((f"run {index}", findings(run_once(args.scenario, Path(out)))))

    failed = False
    for name, found in reports:
        if found:
            failed = True
            print(f"{name}: not clean", file=sys.stderr)
            for line in found[:8]:
                print(f"  {line}", file=sys.stderr)
        else:
            print(f"{name}: # exit 0, no leak")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
