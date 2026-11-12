#!/usr/bin/env python3
"""The home table: where each suite in `sara-godot/tests` goes, and its new name.

The rows that move suites move them by its table, `suite_homes.tsv` beside
it, through `move_suites.py`.

    python3 scripts/suite_homes.py            # write the table, keeping hand lines
    python3 scripts/suite_homes.py --check    # fail when a suite has no line

What a line says. A suite goes to the `tests` folder of the package whose
classes it names most, weighed by how few suites name each class, since
`SaDocument` is named by half the tree and says little about any one suite.
A suite named for a source file, `test_sa_console.gd` for `sa_console.gd`,
goes beside that file whatever else it names. A suite that walks the tree
from `res://`, or carries the `SKIP_DIRS` every walker of the tree names,
checks the whole of it, and stays, and so does one that names
none of Sara's classes. Its new name is its old one without a board row's
prefix, `test_d13_` and its kind, and a name another suite in the same folder
already takes keeps its prefix and reads `clash` for somebody to decide.

The fifth column says who wrote a line. `guess` is this script's, and a run
writes it afresh. `hand` is a person's or an agent's correction, and a run
keeps it as it stands, so the table is generated and corrected by hand the
way intended, and running it again never undoes a correction.
"""

from __future__ import annotations

import argparse
import collections
import math
import re
import sys
from pathlib import Path, PurePosixPath

import gen_file_map as gen

TABLE = Path(__file__).resolve().parent / "suite_homes.tsv"
STAY = "tests"

# The board rows that move suites, by the folder a suite goes to. The
# first prefix that matches a home decides, so the longer ones come first.
ROWS = (
    ("s2", ("core/api", "core/composite", "core/layers", "core/export", "core/presets", "core/image", "core/sad-file", "core/colors")),
    ("s3", ("core",)),
    ("s4", ("ui/dockers", "ui/widgets", "ui/brush_editor", "ui/themes", "ui/tool_options", "ui/canvas", "ui/presets")),
    ("s5", ("ui",)),
    ("s6", ("harness", "render", "tools", "utils")),
    ("s7", ("modules",)),
)
# A board row's prefix: `test_d13_`, `test_a2_`, `test_x13_`, `test_f95b_`.
ROW_PREFIX = re.compile(r"^test_[a-z]{1,2}\d+[a-z]?_")
# A suite that lists the tree from its root is one of the tree's own checks.
WALKS_THE_TREE = re.compile(r"""(?:DirAccess\.(?:open|get_directories_at|get_files_at)|_walk\w*)\(\s*"res://"\s*[,)]""")
# Areas a suite never lives in: a kernel is tested through the class that
# dispatches it, and a pattern through the brush that reads it.
UNHOMED = ("shaders/", "patterns")
HEADER = "suite\thome\tname\trow\tby"


class Line:
    """One suite's home, new name, row and author."""

    def __init__(self, suite: str, home: str, name: str, row: str, by: str) -> None:
        self.suite = suite
        self.home = home
        self.name = name
        self.row = row
        self.by = by

    def text(self) -> str:
        return "\t".join((self.suite, self.home, self.name, self.row, self.by))

    def destination(self) -> str:
        """The suite's path after its move, relative to `sara-godot`."""
        if self.home == STAY:
            return "%s/%s" % (STAY, self.name)
        return "%s/tests/%s" % (self.home, self.name)


def row_of(home: str) -> str:
    """The row that moves a suite to *home*, `s8` for one that stays."""
    for row, prefixes in ROWS:
        if any(home == prefix or home.startswith(prefix + "/") for prefix in prefixes):
            return row
    return "s8"


def read_table(path: Path = TABLE) -> dict[str, Line]:
    """Every line of the table by the suite it names, or none with no table."""
    if not path.exists():
        return {}
    lines: dict[str, Line] = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        if not raw or raw.startswith("#") or raw == HEADER:
            continue
        suite, home, name, row, by = raw.split("\t")
        lines[suite] = Line(suite, home, name, row, by)
    return lines


def owners() -> dict[str, str]:
    """Every file name and class name in the map, to the package that holds it."""
    mapped = {name for name, _ in gen.areas()}
    owner: dict[str, str] = {}
    for rel in gen.tracked_source():
        home = gen.directory_of(rel)
        if home not in mapped:
            continue
        path = gen.GODOT / rel
        for ident in gen.identifiers_of(path, path.read_text(encoding="utf-8")):
            owner.setdefault(ident, home)
    return owner


class Guesser:
    """The home the classes a suite names point to."""

    def __init__(self, owner: dict[str, str], texts: dict[str, str]) -> None:
        self.owner = owner
        self.pattern = re.compile(r"\b(?:%s)\b" % "|".join(re.escape(ident) for ident in sorted(owner, key=len, reverse=True)))
        self.named = {suite: collections.Counter(self.pattern.findall(text)) for suite, text in texts.items()}
        naming = collections.Counter(ident for counts in self.named.values() for ident in counts)
        self.weight = {ident: math.log((len(texts) + 1) / (count + 0.5)) for ident, count in naming.items()}
        self.texts = texts

    def home(self, suite: str) -> str:
        text = self.texts[suite]
        if WALKS_THE_TREE.search(text) or "SKIP_DIRS" in text:
            return STAY
        stem = ROW_PREFIX.sub("test_", PurePosixPath(suite).stem).removeprefix("test_")
        if stem + ".gd" in self.owner:
            return self.owner[stem + ".gd"]
        scores: collections.Counter[str] = collections.Counter()
        for ident, count in self.named[suite].items():
            if not self.owner[ident].startswith(UNHOMED):
                scores[self.owner[ident]] += (1 + math.log(count)) * self.weight[ident]
        return scores.most_common(1)[0][0] if scores else STAY


def guessed(lines: dict[str, Line]) -> list[Line]:
    """A line for every suite in `sara-godot/tests`, hand lines kept."""
    suites = [rel.as_posix() for rel in gen.test_paths() if not gen.suite_home(rel)]
    texts = {suite: (gen.GODOT / suite).read_text(encoding="utf-8") for suite in suites}
    guesser = Guesser(owners(), texts)
    taken: dict[str, set[str]] = collections.defaultdict(set)
    for rel in gen.test_paths():
        if gen.suite_home(rel):
            taken[gen.suite_home(rel)].add(rel.name)
    out: list[Line] = []
    for suite in suites:
        kept = lines.get(suite)
        if kept is not None and kept.by == "hand":
            taken[kept.home].add(kept.name)
            out.append(kept)
    for suite in suites:
        if suite in lines and lines[suite].by == "hand":
            continue
        home = guesser.home(suite)
        old = PurePosixPath(suite).name
        name = ROW_PREFIX.sub("test_", old)
        by = "guess"
        if name in taken[home] or (name != old and name in {PurePosixPath(other).name for other in suites}):
            name, by = old, "clash"
        taken[home].add(name)
        out.append(Line(suite, home, name, row_of(home), by))
    return sorted(out, key=lambda line: line.suite)


def counts(lines: list[Line]) -> list[str]:
    """The comment lines above the table: how many suites each row and area takes."""
    by_row = collections.Counter(line.row for line in lines)
    by_area = collections.Counter(line.home.split("/")[0] for line in lines)
    out = ["# The home of each suite in sara-godot/tests, written by suite_homes.py and corrected by hand."]
    out.append("# %d suites. By row: %s." % (len(lines), ", ".join("%s %d" % item for item in sorted(by_row.items()))))
    out.append("# By area: %s." % ", ".join("%s %d" % item for item in sorted(by_area.items(), key=lambda item: -item[1])))
    renamed = sum(1 for line in lines if line.name != PurePosixPath(line.suite).name)
    out.append("# Renamed %d, by hand %d, clashes left %d." % (renamed, sum(line.by == "hand" for line in lines), sum(line.by == "clash" for line in lines)))
    return out


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    parser.add_argument("--check", action="store_true", help="fail when a suite in sara-godot/tests has no line")
    args = parser.parse_args(argv)
    lines = read_table()
    if args.check:
        missing = [rel.as_posix() for rel in gen.test_paths() if not gen.suite_home(rel) and rel.as_posix() not in lines]
        for suite in missing:
            print("no line in %s: %s" % (TABLE.name, suite))
        return 1 if missing else 0
    fresh = guessed(lines)
    TABLE.write_text("\n".join(counts(fresh) + [HEADER] + [line.text() for line in fresh]) + "\n", encoding="utf-8")
    print("wrote %s, %d suites" % (TABLE.name, len(fresh)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
