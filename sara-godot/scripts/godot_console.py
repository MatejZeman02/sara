#!/usr/bin/env python3
"""
Reads Godot's debug console output for this project.

Two independent surfaces, because neither one sees what the other does:

  * Run log  - what the project printed while it ran: runtime errors, engine
               warnings, GDScript backtraces and plain print() notes. Sara
               writes this to user://logs/godot.log for every run, whether the
               project was launched from the editor's Play button or the CLI.
  * LSP      - compile-time diagnostics for every script, pulled live from a
               running editor. Catches unused variables, shadowing and parse
               errors that a run would never reach.

A runtime error like "add_child() failed" only ever appears in the run log; an
unused-variable warning only ever appears over LSP. Check both.
"""

import argparse
import os
import re
import subprocess
import sys
from collections import OrderedDict
from pathlib import Path

# A console entry starts with one of these and continues on indented lines.
ENTRY_RE = re.compile(r"^(USER )?(SCRIPT ERROR|ERROR|WARNING):\s*(.*)$")
# First project-owned frame in a GDScript backtrace, which is the useful one.
FRAME_RE = re.compile(r"\[\d+\]\s+(.*?)\s+\((res://[^)]+)\)")
AT_RE = re.compile(r"^\s+at:\s*(.*)$")

LEVEL_ORDER = {"SCRIPT ERROR": 0, "ERROR": 1, "WARNING": 2, "NOTE": 3}


class Entry:
    """One console entry plus the indented lines Godot attached to it."""

    def __init__(self, level: str, message: str):
        self.level = level
        self.message = message
        self.detail: list[str] = []
        self.count = 1

    @property
    def origin(self) -> str:
        """First res:// frame, so the reader gets a file:line to jump to."""
        for line in self.detail:
            frame = FRAME_RE.search(line)
            if frame:
                func, path = frame.group(1), frame.group(2)
                return "%s in %s" % (path.replace("res://", ""), func)
        for line in self.detail:
            at = AT_RE.match(line)
            if at:
                return at.group(1)
        return ""

    @property
    def key(self) -> tuple:
        return (self.level, self.message, self.origin)


def project_name(project_root: Path) -> str:
    """Read config/name out of project.godot; it names the user data folder."""
    godot_file = project_root / "project.godot"
    if not godot_file.is_file():
        return ""
    for line in godot_file.read_text(encoding="utf-8", errors="replace").splitlines():
        if line.startswith("config/name="):
            return line.split("=", 1)[1].strip().strip('"')
    return ""


def log_dir(project_root: Path, override: str) -> Path:
    if override:
        return Path(override).expanduser()
    name = project_name(project_root)
    base = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share"))
    return base / "godot/app_userdata" / name / "logs"


def collect_logs(directory: Path, all_runs: bool) -> list[Path]:
    if not directory.is_dir():
        return []
    # godot.log is the most recent run unless a second Sara wrote its own beside it.
    logs = sorted(directory.glob("*.log"), key=lambda p: p.stat().st_mtime, reverse=True)
    return logs if all_runs else logs[:1]


def parse_log(path: Path, keep_notes: bool) -> list[Entry]:
    return parse_log_text(path.read_text(encoding="utf-8", errors="replace"), keep_notes)


def parse_log_text(text: str, keep_notes: bool = False) -> list[Entry]:
    """The same parse over a string rather than a file.

    Split out for `sara_findings.py`, which reads the window of the log written
    since the last door answer and must not have a second parser: a backtrace
    read one way for a person and another way for an agent is two truths.
    """
    entries: list[Entry] = []
    current: Entry | None = None

    for raw in text.splitlines():
        match = ENTRY_RE.match(raw)
        if match:
            level = match.group(2)
            current = Entry(level, match.group(3).strip())
            entries.append(current)
            continue

        # Indented lines belong to the entry above ("at:", backtrace frames).
        if current is not None and raw.startswith((" ", "\t")) and raw.strip():
            current.detail.append(raw)
            continue

        current = None
        if keep_notes and raw.strip():
            entries.append(Entry("NOTE", raw.strip()))

    return entries


def deduplicate(entries: list[Entry]) -> list[Entry]:
    """Godot repeats the same error every frame; collapse to one line with a count."""
    merged: OrderedDict[tuple, Entry] = OrderedDict()
    for entry in entries:
        existing = merged.get(entry.key)
        if existing:
            existing.count += 1
        else:
            merged[entry.key] = entry
    return list(merged.values())


def wanted(entry: Entry, level: str) -> bool:
    if level == "all":
        return True
    if level == "error":
        return entry.level in ("ERROR", "SCRIPT ERROR")
    if level == "warning":
        return entry.level in ("ERROR", "SCRIPT ERROR", "WARNING")
    return True


def report_log(entries: list[Entry], source: Path, full: bool, limit: int) -> int:
    if not entries:
        print("[run log] %s - clean, no errors or warnings." % source.name)
        return 0

    print("[run log] %s" % source)
    entries.sort(key=lambda e: (LEVEL_ORDER.get(e.level, 9), -e.count))
    shown = entries if full else entries[:limit]

    for entry in shown:
        repeat = " (x%d)" % entry.count if entry.count > 1 else ""
        origin = entry.origin
        location = "  ->  %s" % origin if origin else ""
        print("  [%s]%s %s%s" % (entry.level, repeat, entry.message, location))
        if full:
            for line in entry.detail:
                print("      %s" % line.strip())

    hidden = len(entries) - len(shown)
    if hidden > 0:
        print("  ... %d more (use --full to see every entry)" % hidden)

    return sum(1 for e in entries if e.level in ("ERROR", "SCRIPT ERROR"))


def default_port(script_dir: Path) -> int:
    """The port this checkout's editor listens on, by the rule check_lsp_errors.py owns."""
    sys.path.insert(0, str(script_dir))
    import check_lsp_errors

    return check_lsp_errors.lsp_port(str(script_dir.parent))


def report_lsp(script_dir: Path, port: int) -> int:
    checker = script_dir / "check_lsp_errors.py"
    if not checker.is_file():
        print("[lsp] check_lsp_errors.py not found next to this script; skipped.")
        return 0

    print()
    result = subprocess.run(
        [sys.executable, str(checker), "--port", str(port)],
        capture_output=True,
        encoding="utf-8",
    )
    output = (result.stdout + result.stderr).strip()
    print(output if output else "[lsp] no output.")

    if "Connection refused" in output or "Could not connect" in output:
        print("[lsp] Editor not running, so compile-time diagnostics were not checked.")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Read Godot's debug console output: run-log entries plus live LSP diagnostics."
    )
    parser.add_argument("--project-root", default="", help="Godot project directory (default: parent of this script)")
    parser.add_argument("--log-dir", default="", help="Override the user://logs directory")
    parser.add_argument("--all-runs", action="store_true", help="Scan every rotated log, not just the latest run")
    parser.add_argument(
        "--level",
        choices=["error", "warning", "all"],
        default="warning",
        help="Lowest severity to report from the run log (default: warning)",
    )
    parser.add_argument("--notes", action="store_true", help="Include plain print() output as NOTE entries")
    parser.add_argument("--full", action="store_true", help="Show every entry with its full backtrace")
    parser.add_argument("--limit", type=int, default=25, help="Max entries to list when not using --full")
    parser.add_argument("--no-lsp", action="store_true", help="Skip the editor LSP diagnostics pass")
    parser.add_argument(
        "--port",
        type=int,
        default=None,
        help="Godot LSP port (default: this checkout's own, as check_lsp.sh picks it)",
    )
    args = parser.parse_args()

    script_dir = Path(__file__).resolve().parent
    project_root = Path(args.project_root).expanduser() if args.project_root else script_dir.parent

    directory = log_dir(project_root, args.log_dir)
    logs = collect_logs(directory, args.all_runs)

    errors = 0
    if not logs:
        print("[run log] No logs in %s" % directory)
        print("[run log] Run the project once; Godot writes user://logs/godot.log on every run.")
    else:
        for path in logs:
            entries = [e for e in deduplicate(parse_log(path, args.notes)) if wanted(e, args.level)]
            errors += report_log(entries, path, args.full, args.limit)

    if not args.no_lsp:
        report_lsp(script_dir, args.port if args.port is not None else default_port(script_dir))

    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
