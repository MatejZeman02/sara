#!/usr/bin/env python3
"""SIGTERM to a door Sara, with a changed document and with an unchanged one.

    cd sara-godot && .conda/bin/python scenarios/sigterm-ends-sara-within-seconds-whatever-the-document-holds.py [out] [--build SARA]

Each case starts Sara offscreen through the door, makes a document and saves
it into the out folder, so its recovery copy has a place beside it. The first
case then changes it with a door stroke, the second leaves it as saved. Each
sends SIGTERM to the process, reads how it exited and how long that took, and
counts the recovery copies Sara wrote, by the save's own end lines on the pipe
and by the file beside the document.

The guard is that a termination signal still ends Sara within 10 seconds in
both cases, so a painter's `kill` never meets a Sara waiting at its quit
question. Godot 4.7 installs no SIGTERM handler on Linux, so the process ends
by the signal's default action, exit 143 or -15 as Python reports it, and
writes no recovery copy. The copies are counted and recorded, not required,
since a copy on termination would need a native handler nobody has asked for.
Everything goes to `sigterm.json` in the out folder, and the run exits 1 when
either case outlives the limit.

The out folder defaults to this row's folder under `~/.cache/sara/scenario-runs`.
"""

from __future__ import annotations

import json
import os
import signal
import subprocess
import sys
import time
from pathlib import Path

PROJECT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT / "scripts"))

from sara_door import SaraDoor  # noqa: E402

ROW = "sara-ignores-sigterm-after-a-run-of-exports-and-writes-its-recovery-copy-again-instead-of-quitting"
PROOF = Path.home() / ".cache" / "sara" / "scenario-runs" / ROW
EXIT_LIMIT_S = 10.0
WROTE = "SaSadSave: wrote "


def one_case(out: Path, build: str | None, changed: bool) -> dict:
    """One Sara, its document saved and changed or not, ended by SIGTERM."""
    name = "changed" if changed else "unchanged"
    folder = out / name
    folder.mkdir(parents=True, exist_ok=True)
    document = folder / f"{name}.sad"
    copy = folder / f"{name}.autosave.sad"
    for stale in (document, copy):
        stale.unlink(missing_ok=True)
    door = SaraDoor(out_dir=folder / "door", build=build)
    door.__enter__()
    try:
        door.send({"document": "srgb"})
        door.send({"save": str(document)})
        # The save runs in the background and marks the document saved as it
        # lands, so a stroke before then would be marked saved with it.
        for _ in range(100):
            if document.is_file() and not door.send({"state": "saved"})["state"]["document"]["modified"]:
                break
            door.send({"wait": 5})
        if changed:
            door.send({"tool": "brush"})
            door.send({"stroke": {"route": "tool", "space": "document", "from": [300, 300], "to": [700, 500], "pressure": 0.8}})
        modified = bool(door.send({"state": "before"})["state"]["document"]["modified"])
        assert door.proc is not None
        began = time.monotonic()
        os.kill(door.proc.pid, signal.SIGTERM)
        try:
            code: int | None = door.proc.wait(timeout=EXIT_LIMIT_S + 5)
        except subprocess.TimeoutExpired:
            code = None
        seconds = round(time.monotonic() - began, 2)
        time.sleep(0.5)
        lines = door._drain()
        if code is None:
            door.proc.kill()
            door.proc.wait()
    finally:
        door.link = None
        door.proc = None
        door.close()
    writes = [line for line in lines if WROTE in line and str(copy) in line]
    return {
        "case": name,
        "modified_before_the_signal": modified,
        "exit_code": code,
        "seconds_to_exit": seconds,
        "recovery_writes": len(writes),
        "recovery_copy_on_disk": copy.is_file(),
        "trail": [line for line in lines if line.startswith("Sara trail:")][-8:],
    }


def main() -> int:
    args = [arg for arg in sys.argv[1:]]
    build = None
    if "--build" in args:
        at = args.index("--build")
        build = args[at + 1]
        del args[at : at + 2]
    out = Path(args[0]) if args else PROOF
    out.mkdir(parents=True, exist_ok=True)
    changed = one_case(out, build, True)
    unchanged = one_case(out, build, False)
    clauses = {
        "changed exits within 10 s": changed["exit_code"] is not None and changed["seconds_to_exit"] <= EXIT_LIMIT_S,
        "unchanged exits within 10 s": unchanged["exit_code"] is not None
        and unchanged["seconds_to_exit"] <= EXIT_LIMIT_S,
    }
    report = {"cases": [changed, unchanged], "clauses": clauses}
    (out / "sigterm.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    for clause, met in clauses.items():
        print(f"{'met    ' if met else 'NOT MET'} {clause}")
    for case in (changed, unchanged):
        print(f"{case['case']}: exit {case['exit_code']} in {case['seconds_to_exit']} s, {case['recovery_writes']} copies")
    return 0 if all(clauses.values()) else 1


if __name__ == "__main__":
    sys.exit(main())
