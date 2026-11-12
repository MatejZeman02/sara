#!/usr/bin/env python3
"""Who owns a unit's proof folder, `sprints/*/units/<id>/` in the review folder.

A proof folder is a path derived from a unit id, so any session on the machine
can write it, and `sara_shot.py` clears its `--out` before every round. Two
sessions at one unit id therefore do not collide, the second destroys the
first's evidence. The claim on the board is a branch on `origin` and says
nothing about a directory, so the directory has to say it itself.

It says it in a `CLAIM` file beside the artefacts, four `key: value` lines
naming the unit, the branch, the clone that holds it and when it was taken:

    unit: d26-a-second-session-...
    branch: unit/d26-a-second-session-...
    clone: /home/you/work/sara-skeleton-q
    taken: 2026-09-10T19:30:12+02:00

The clone path is the identity that matters, because one working tree is one
session. A write from anywhere else is refused with what it found rather than
going ahead, and a session taking an orphaned unit over says so out loud:

    scripts/proof_claim.py <folder>          # take it if it is free
    scripts/proof_claim.py --show <folder>   # print who holds it
    scripts/proof_claim.py --take <folder>   # take it over, orphan or not
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

PROJECT_DIR = Path(__file__).resolve().parent.parent

# The file lives at the proof folder's top, never inside a `capture/` a round
# clears, so a scenario writing into a subfolder leaves the claim alone.
CLAIM_NAME = "CLAIM"

# What a refused run exits with. Not 1, which is any other failure, and not 2,
# which argparse takes for a bad command line.
REFUSED_EXIT = 3

FIELDS = ("unit", "branch", "clone", "taken")


@dataclass(frozen=True)
class Claim:
    """The four lines of a `CLAIM` file."""

    unit: str
    branch: str
    clone: str
    taken: str

    def text(self) -> str:
        return "".join(f"{name}: {getattr(self, name)}\n" for name in FIELDS)


class Refused(Exception):
    """A proof folder another clone holds, and what to tell the reader."""

    def __init__(self, folder: Path, held: Claim, mine: Claim) -> None:
        super().__init__(f"{folder} is held by {held.clone}")
        self.folder = folder
        self.held = held
        self.mine = mine

    def report(self) -> str:
        """The refusal as a painter of boards reads it, path first.

        Every line the reader needs to decide is here, because the alternative
        is a session that deletes another's evidence and neither notices.
        """
        return "\n".join(
            [
                f"  the proof folder {self.folder} belongs to another clone,",
                "  so nothing was cleared and nothing was written.",
                f"    held by  {self.held.clone}",
                f"    on       {self.held.branch}  since {self.held.taken}",
                f"    you are  {self.mine.clone}",
                f"    on       {self.mine.branch}",
                "  Point --out somewhere else. If that session has ended and you are",
                "  taking the unit over, say so:",
                f"    python3 {PROJECT_DIR / 'scripts' / 'proof_claim.py'} --take {self.folder}",
            ]
        )


def proof_root(path: Path) -> Path | None:
    """The `sprints/<plan>/units/<id>` directory *path* is in or is, else None.

    Matched on the shape rather than on one fixed home, so a test can build one
    anywhere and a person with the review directory somewhere else is covered.
    """
    parts = path.resolve().parts
    for index in range(len(parts) - 3):
        if parts[index] == "sprints" and parts[index + 2] == "units":
            return Path(*parts[: index + 4])
    return None


def parse_claim(text: str) -> Claim:
    """A `CLAIM` file's text as a claim, missing lines reading empty."""
    found: dict[str, str] = {}
    for line in text.splitlines():
        name, sep, value = line.partition(":")
        if sep and name.strip() in FIELDS:
            found[name.strip()] = value.strip()
    return Claim(*(found.get(name, "") for name in FIELDS))


def _git(clone: Path, *args: str) -> str:
    """`git` in *clone*, or "" when there is no git or no repository."""
    try:
        done = subprocess.run(
            ["git", "-C", str(clone), *args], capture_output=True, encoding="utf-8", timeout=10
        )
    except (OSError, subprocess.SubprocessError):
        return ""
    return done.stdout.strip() if done.returncode == 0 else ""


def this_session(folder: Path, clone: Path | None = None) -> Claim:
    """The claim this clone would write for *folder*.

    The clone is the working tree `sara_shot.py` was started from, which is what
    a second session differs in even when both are on the same branch name.
    """
    here = (clone or PROJECT_DIR).resolve()
    top = _git(here, "rev-parse", "--show-toplevel")
    return Claim(
        unit=folder.name,
        branch=_git(here, "rev-parse", "--abbrev-ref", "HEAD") or "(no branch)",
        clone=top or str(here),
        taken=datetime.now().astimezone().isoformat(timespec="seconds"),
    )


def held_by(folder: Path) -> Claim | None:
    """The claim on *folder*, or None when nobody has taken it."""
    claim_file = folder / CLAIM_NAME
    if not claim_file.is_file():
        return None
    return parse_claim(claim_file.read_text(encoding="utf-8"))


def hold(out_dir: Path, clone: Path | None = None, take: bool = False) -> Claim | None:
    """Take the proof folder *out_dir* writes into, before anything is cleared.

    Returns the claim now on it, or None when *out_dir* is not under a proof
    folder at all, which is every ordinary capture into `scratch/`. Raises
    `Refused` when another clone holds it and *take* is false.
    """
    folder = proof_root(out_dir)
    if folder is None:
        return None
    mine = this_session(folder, clone)
    standing = held_by(folder) if folder.is_dir() else None
    if standing is not None and standing.clone and standing.clone != mine.clone and not take:
        raise Refused(folder, standing, mine)
    if standing is not None and standing.clone == mine.clone:
        if standing.branch == mine.branch:
            return standing
        # The same clone on another branch, which is a claim run from the base
        # before the switch to the unit's branch. The branch is brought up to
        # date and the time it was first taken kept.
        mine = Claim(mine.unit, mine.branch, mine.clone, standing.taken)
    folder.mkdir(parents=True, exist_ok=True)
    (folder / CLAIM_NAME).write_text(mine.text(), encoding="utf-8")
    return mine


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("folder", type=Path, help="a proof folder, or a path inside one")
    parser.add_argument("--show", action="store_true", help="print who holds it and change nothing")
    parser.add_argument("--take", action="store_true", help="take it over from a session that ended")
    args = parser.parse_args(argv)

    folder = proof_root(args.folder)
    if folder is None:
        print(f"  {args.folder} is not under sprints/<plan>/units/<id>, so there is nothing to hold.")
        return 0
    if args.show:
        standing = held_by(folder)
        if standing is None:
            print(f"  {folder} is free.")
        else:
            print(f"  {folder}\n{standing.text().rstrip()}")
        return 0
    try:
        claim = hold(args.folder, take=args.take)
    except Refused as refusal:
        print(refusal.report(), file=sys.stderr)
        return REFUSED_EXIT
    verb = "taken over by" if args.take else "held by"
    print(f"  {folder}\n  {verb} {claim.clone} on {claim.branch}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
