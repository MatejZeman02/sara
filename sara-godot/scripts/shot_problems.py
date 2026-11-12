"""What a capture run printed that its reader has to be told, and how it is told.

A run of `sara_shot.py` prints hundreds of lines and a person reads none of
them, so this is the whole of what reaches them: a script error, an engine
`ERROR:`, a capture step refusing, and a leak at exit, folded and counted. It
is one question, what counts as a problem, and the runner that launches Godot
is another, so the two live apart, which also keeps `sara_shot.py` under the
thousand lines a run fails on. `sara_shot` imports every name here, and its
callers read them there.
"""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

# How many *distinct* problem lines the terminal shows before it says how many
# more there are and points at the log.
DISTINCT_PROBLEMS = 20

# The words a `SaCapture:` line opens with when the step found nothing to act on.
#
# `failed` is the rarest of them: a step that cannot find its control says
# `no dropdown called \'X\'` or `found no embedded docker called \'X\'` and carries
# on, so a reader who is told about `failed` alone is told nothing about a
# scenario that drives a control which is not there and shoots the docker with
# nothing open. Three were committed that way, two of them for a board and a
# half.
#
# A rule rather than a list of strings, checked against every `SaCapture:`
# message in the tree: a refusal opens with one of these and a report never
# does. `nothing` and `none` are not here on purpose, because the boundary after
# `no` is what keeps `SaCapture: nothing to undo` out of a list of controls that
# could not be found.
REFUSAL_OPENERS = ("no ", "found no ", "cannot ", "could not ")

# The word a failing step prints, bounded so a path or a name that merely
# contains it is not a problem.
FAILED_WORD = re.compile(r"(?<![\w/.-])failed(?![\w/-])")

# What Godot prints at exit for anything left alive, the pattern `run_tests.sh`
# fails the gate on, character for character, and a suite holds the two equal.
# The line opens with `WARNING:`, so a reader that takes `ERROR:` for the whole
# of a run's bad news reports nothing while seven objects leak at the end of
# every scenario.
LEAK_PATTERN = r"(RIDs? of type .* leaked|RID allocations of type .* leaked|ObjectDB instances? (was|were) leaked|resources? still in use at exit)"
LEAK_LINE = re.compile(LEAK_PATTERN)


# What the app printed that a reader wants to be told about without asking. A
# `SaCapture:` line that says `failed`, or that opens with a refusal, is a step
# refusing, which is a problem whatever the exit code says. So is a leak at exit,
# which the gate would fail the run for.
def is_problem(line: str) -> bool:
    if "SCRIPT ERROR" in line or line.startswith("ERROR:"):
        return True
    if LEAK_LINE.search(line):
        return True
    if "SaCapture:" not in line:
        return False
    # "failed" as a word, not inside a path: a proof folder named
    # `...-strokes-all-failed-is-a-green-run` is enough to make every
    # `SaCapture: wrote` line of a run a problem, because the file it wrote is
    # in it.
    if FAILED_WORD.search(line):
        return True
    message = line.split("SaCapture:", 1)[1].strip()
    return message.startswith(REFUSAL_OPENERS)


def report_problems(proc: subprocess.CompletedProcess, log_path: Path) -> None:
    """The run's problems, folded, and the truth about what is not shown.

    **Identical lines are folded with a count.** One engine error repeated a
    few hundred times, or the nine lines every capture in a clone with a stale
    preset opens with, otherwise fill the list on their own and hide whatever
    the run was about.

    The cap is on distinct lines rather than on lines, and when it bites the
    trailer says so and names the log, so the list cannot be read as the whole
    of what happened.
    """
    problems: dict[str, int] = {}
    for line in (proc.stdout + proc.stderr).splitlines():
        if is_problem(line):
            problems[line] = problems.get(line, 0) + 1
    if not problems:
        return
    total = sum(problems.values())
    shown = list(problems.items())[:DISTINCT_PROBLEMS]
    print(f"\n  {total} problem line(s) reported by the run, {len(problems)} distinct:", file=sys.stderr)
    for line, count in shown:
        prefix = f"{count:>4d}x " if count > 1 else "      "
        print(f"    {prefix}{line}", file=sys.stderr)
    if len(problems) > len(shown):
        print(f"    ... and {len(problems) - len(shown)} more distinct line(s)", file=sys.stderr)
    print(f"    the whole run is in {log_path}", file=sys.stderr)
