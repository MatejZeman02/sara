#!/usr/bin/env python3
"""The check that finds a translated message code glues into a sentence.

    cd sara-godot && PYTHONPATH=scripts python -m unittest scripts.test_check_glued_words

`check_glued_words.py` reads source text, so every case runs it as the gate
does, through `check_translated.py` as a child process, and reads what it
prints. A fixture tree holds one line of each kind, a translated word dropped
into a translated sentence, a colon added to a translated word in code and a
message made from English by a string method, beside a sentence with a name
the painter typed dropped into it, and the check names the three with their
file and line and nothing for the fourth. Over the tree it passes with the
committed list, a fourth `tr("Add %s") % tr(...)` added to a copy of the tree
fails naming that line, and a listed line taken out of a copy of the source
fails naming the line as stale.

No Godot and no GPU, so it runs in the gate's Python line.
"""

from __future__ import annotations

import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import check_glued_words as cg
import check_translated as ct

SCRIPT = Path(ct.__file__).resolve()

HEAD = "extends Label\n\n\nfunc show_it(kind: String, typed: String) -> void:\n"


def run(root: Path, list_file: Path) -> tuple[int, str]:
    """`check_translated.py` over *root*, reading *list_file* as the glued list and an empty list for its own."""
    with tempfile.TemporaryDirectory() as tmp:
        own = Path(tmp) / "own.txt"
        own.write_text("", encoding="utf-8")
        argv = ["--root", str(root), "--list", str(own), "--glued-list", str(list_file)]
        done = subprocess.run(
            [sys.executable, str(SCRIPT), *argv], capture_output=True, encoding="utf-8", check=False
        )
    return done.returncode, done.stdout + done.stderr


def named(out: str) -> list[str]:
    return [line.split(" is not on the list")[0] for line in out.splitlines() if " is not on the list" in line]


def copy_tree(to: Path) -> list[str]:
    """The tracked `.gd` files the check reads, copied under *to*, and their paths."""
    paths = ct.tracked_sources(ct.SARA_GODOT)
    for path in paths:
        (to / path).parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ct.SARA_GODOT / path, to / path)
    return paths


class TestTheFourLinesTheRowNames(unittest.TestCase):
    def setUp(self) -> None:
        self._dir = tempfile.TemporaryDirectory()
        self.addCleanup(self._dir.cleanup)
        self.root = Path(self._dir.name) / "tree"
        self.list_file = Path(self._dir.name) / "glued.txt"
        self.list_file.write_text("", encoding="utf-8")
        files = {
            "ui/dropped.gd": HEAD + '    text = tr("Add %s") % tr(kind)\n',
            "ui/glued.gd": HEAD + '    text = tr("Size") + ": "\n',
            "ui/english.gd": HEAD + '    text = tr(kind.trim_suffix(" Tool"))\n',
            "ui/typed.gd": HEAD + '    text = tr("Rename %s") % typed\n',
        }
        for path, text in files.items():
            (self.root / path).parent.mkdir(parents=True, exist_ok=True)
            (self.root / path).write_text(text, encoding="utf-8")

    def test_the_three_kinds_are_named_with_file_and_line_and_the_typed_name_is_not(self) -> None:
        code, out = run(self.root, self.list_file)
        self.assertEqual(code, 1, out)
        self.assertEqual(
            sorted(named(out)),
            [
                'ui/dropped.gd:5 [dropped] tr("Add %s") % tr(kind)',
                'ui/english.gd:5 [english] tr(kind.trim_suffix(" Tool"))',
                'ui/glued.gd:5 [glued] tr("Size") + ": "',
            ],
        )
        self.assertNotIn("typed.gd", out)

    def test_each_hit_carries_a_line_of_advice(self) -> None:
        _, out = run(self.root, self.list_file)
        for form, advice in cg.ADVICE.items():
            self.assertIn(f"[{form}]", out)
            self.assertIn(advice, out)

    def test_the_three_on_the_list_pass_and_a_reason_after_a_tab_is_ignored(self) -> None:
        self.list_file.write_text(
            'ui/dropped.gd dropped tr("Add %s") % tr(kind)\tthe kinds are an open set\n'
            'ui/glued.gd glued tr("Size") + ": "\n'
            'ui/english.gd english tr(kind.trim_suffix(" Tool"))\n',
            encoding="utf-8",
        )
        code, out = run(self.root, self.list_file)
        self.assertEqual(code, 0, out)
        self.assertIn("1 dropped, 1 glued, 1 english", out)


class TestTheTree(unittest.TestCase):
    def test_the_tree_passes_with_the_committed_list(self) -> None:
        done = subprocess.run([sys.executable, str(SCRIPT)], capture_output=True, encoding="utf-8", check=False)
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertIn("check_glued_words:", done.stdout)

    def test_a_fourth_add_line_fails_naming_that_line(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            copy = Path(tmp)
            paths = copy_tree(copy)
            target = next(p for p in paths if p.startswith("ui/"))
            lines = (copy / target).read_text(encoding="utf-8").splitlines()
            added = ["", "", "func _named_by_the_suite(kind: String) -> String:", '    return tr("Add %s") % tr(kind)']
            (copy / target).write_text("\n".join(lines + added) + "\n", encoding="utf-8")
            code, out = run_tree(copy)
        self.assertEqual(code, 1, out)
        self.assertEqual(named(out), [f'{target}:{len(lines) + 4} [dropped] tr("Add %s") % tr(kind)'])

    def test_a_listed_line_taken_out_of_the_source_is_named_as_stale(self) -> None:
        listed = cg.read_list(cg.LIST)
        path, form, text = next(k for k in listed if k[1] == "dropped")
        with tempfile.TemporaryDirectory() as tmp:
            copy = Path(tmp)
            copy_tree(copy)
            source = (copy / path).read_text(encoding="utf-8").splitlines()
            kept = [line for line in source if not ("%" in line and "tr" in line and _same(line, text))]
            self.assertLess(len(kept), len(source), text)
            (copy / path).write_text("\n".join(kept) + "\n", encoding="utf-8")
            code, out = run_tree(copy)
        self.assertEqual(code, 1, out)
        self.assertIn(f"{cg.LIST.name} names {path} [{form}] {text}, which the tree no longer has", out)


def _same(line: str, text: str) -> bool:
    """Whether a source line is the one a listed hit renders, compared without spaces."""
    return text.replace(" ", "") in line.replace(" ", "")


def run_tree(copy: Path) -> tuple[int, str]:
    """`check_glued_words.py` over a copy of the tree with the committed list."""
    done = subprocess.run(
        [sys.executable, str(Path(cg.__file__).resolve()), "--root", str(copy), "--list", str(cg.LIST)],
        capture_output=True,
        encoding="utf-8",
        check=False,
    )
    return done.returncode, done.stdout + done.stderr


if __name__ == "__main__":
    unittest.main()
