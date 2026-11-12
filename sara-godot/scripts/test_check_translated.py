#!/usr/bin/env python3
"""The check that finds a word on screen that skips the translation.

    cd sara-godot && PYTHONPATH=scripts python -m unittest scripts.test_check_translated

`check_translated.py` reads source text, so every case here runs it as the gate
does, a child process over a folder, and reads what it prints. A fixture tree
holds a bare `text = "Open"`, a `tr("Open")`, a `tr()` string with `%d` and the
same bare line under `harness/`, and the first and third are named while the
other two pass. Over the tree it passes with today's list, and over a copy of
the tree with one bare string added to a file under `ui/` it fails naming that
file and line and nothing else, which shows the copy is the tree. The other
cases hold the forms the docstring of the check names and the list's two ways
of failing.

No Godot and no GPU, so it runs in the gate's Python line.
"""

from __future__ import annotations

import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import check_translated as ct

SCRIPT = Path(ct.__file__).resolve()

LABEL_HEAD = "extends Button\n\n\nfunc _ready() -> void:\n"


def run(root: Path, list_file: Path, *extra: str) -> tuple[int, str]:
    done = subprocess.run(
        [sys.executable, str(SCRIPT), "--root", str(root), "--list", str(list_file), *extra],
        capture_output=True,
        encoding="utf-8",
        check=False,
    )
    return done.returncode, done.stdout + done.stderr


class Fixture:
    """A folder of `.gd` files and an empty list beside it, gone at the end."""

    def __init__(self, files: dict[str, str]) -> None:
        self._dir = tempfile.TemporaryDirectory()
        self.root = Path(self._dir.name) / "tree"
        self.list_file = Path(self._dir.name) / "list.txt"
        for path, text in files.items():
            file = self.root / path
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_text(text, encoding="utf-8")
        self.list_file.write_text("", encoding="utf-8")

    def close(self) -> None:
        self._dir.cleanup()


class TestTheFourLinesTheRowNames(unittest.TestCase):
    def setUp(self) -> None:
        self.tree = Fixture(
            {
                "ui/bare.gd": LABEL_HEAD + '    text = "Open"\n',
                "ui/translated.gd": LABEL_HEAD + '    text = tr("Open")\n',
                "ui/counted.gd": LABEL_HEAD + '    text = tr("%d layers") % get_child_count()\n',
                "harness/capture.gd": LABEL_HEAD + '    text = "Open"\n',
            }
        )
        self.addCleanup(self.tree.close)

    def test_the_bare_string_and_the_count_are_named_and_the_others_pass(self) -> None:
        code, out = run(self.tree.root, self.tree.list_file)
        self.assertEqual(code, 1, out)
        self.assertIn('ui/bare.gd:5 [bare] "Open"', out)
        self.assertIn('ui/counted.gd:5 [count] "%d layers"', out)
        self.assertNotIn("translated.gd", out)
        self.assertNotIn("harness", out)

    def test_the_two_on_the_list_pass(self) -> None:
        self.tree.list_file.write_text(
            'ui/bare.gd bare "Open"\nui/counted.gd count "%d layers"\n', encoding="utf-8"
        )
        code, out = run(self.tree.root, self.tree.list_file)
        self.assertEqual(code, 0, out)


class TestTheTree(unittest.TestCase):
    def test_the_tree_passes_with_today_s_list(self) -> None:
        done = subprocess.run(
            [sys.executable, str(SCRIPT)], capture_output=True, encoding="utf-8", check=False
        )
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)

    def test_a_bare_string_added_under_ui_fails_naming_its_file_and_line(self) -> None:
        paths = ct.tracked_sources(ct.SARA_GODOT)
        target = next(p for p in paths if p.startswith("ui/"))
        with tempfile.TemporaryDirectory() as tmp:
            copy = Path(tmp)
            for path in paths:
                (copy / path).parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(ct.SARA_GODOT / path, copy / path)
            lines = (copy / target).read_text(encoding="utf-8").splitlines()
            added = ["", "", "func _named_by_the_suite(shown: Label) -> void:", '    shown.text = "Open"']
            (copy / target).write_text("\n".join(lines + added) + "\n", encoding="utf-8")
            code, out = run(copy, ct.LIST)
        self.assertEqual(code, 1, out)
        named = [line for line in out.splitlines() if not line.startswith("check_translated:")]
        self.assertEqual(named, [f'{target}:{len(lines) + 4} [bare] "Open" is not on the list, put it through tr()'])


class TestTheForms(unittest.TestCase):
    def hits(self, files: dict[str, str]) -> list[str]:
        tree = Fixture(files)
        self.addCleanup(tree.close)
        _, out = run(tree.root, tree.list_file)
        return [line.split(" is not on the list")[0] for line in out.splitlines() if " is not on the list" in line]

    def test_a_control_built_with_its_words(self) -> None:
        make = (
            "class_name Make\n\n\n"
            "static func label(parent: Node, node_name: String, text: String = \"\") -> Label:\n"
            "    var made := Label.new()\n"
            "    made.text = text\n"
            "    parent.add_child(made)\n"
            "    return made\n"
        )
        page = (
            "extends VBoxContainer\n\n\nfunc _ready() -> void:\n"
            '    Make.label(self, "Title", "Layers")\n'
            '    Make.label(self, "Hint", tr("Layers"))\n'
        )
        self.assertEqual(self.hits({"ui/make.gd": make, "ui/page.gd": page}), ['ui/page.gd:5 [built] "Layers"'])

    def test_a_string_reaching_the_property_through_an_expression(self) -> None:
        body = (
            "extends Label\n\n\nfunc show_it(count: int, on: bool) -> void:\n"
            '    tooltip_text = "Close " + name\n'
            '    text = tr("Pause") if on else "Play"\n'
            '    text += " more"\n'
            '    text = "%.2f" % 0.5\n'
            '    text = String({"name": "x"}["name"])\n'
            '    text = tr_n("%d layer", "%d layers", count) % count\n'
            '    text = TranslationServer.translate("Step %d") % count\n'
            '    print("the harness ran %d steps" % count)\n'
        )
        self.assertEqual(
            self.hits({"ui/label.gd": body}),
            [
                'ui/label.gd:5 [bare] "Close "',
                'ui/label.gd:6 [bare] "Play"',
                'ui/label.gd:7 [bare] " more"',
                'ui/label.gd:11 [count] "Step %d"',
            ],
        )

    def test_a_wrapper_that_translates_its_parameter_translates(self) -> None:
        page = (
            "class_name Page\n\n\n"
            "static func translated(text: String) -> String:\n"
            "    return String(TranslationServer.translate(text))\n\n\n"
            "static func fill(shown: Label) -> void:\n"
            '    shown.text = Page.translated("Save")\n'
            '    shown.text = Page.translated("Preset %d") % 2\n'
        )
        self.assertEqual(self.hits({"ui/page.gd": page}), ['ui/page.gd:10 [count] "Preset %d"'])

    def test_a_local_named_text_is_not_the_property(self) -> None:
        body = 'extends Node\n\n\nfunc words(text: String) -> String:\n    text = "Open"\n    return text\n'
        self.assertEqual(self.hits({"ui/node.gd": body}), [])

    def test_a_translated_string_with_the_one_character_ellipsis_fails(self) -> None:
        # A scratch tr("Open…") fails and three dots pass,
        # through a wrapper and across a parenthesised join too.
        page = (
            "class_name Page\n\n\n"
            "static func translated(text: String) -> String:\n"
            "    return String(TranslationServer.translate(text))\n\n\n"
            "static func fill(shown: Button) -> void:\n"
            '    shown.text = tr("Open…")\n'
            '    shown.text = tr("Open...")\n'
            '    shown.text = Page.translated("Choose…")\n'
            '    shown.tooltip_text = tr(("Save… keeps it. " + "Twice."))\n'
        )
        self.assertEqual(
            self.hits({"ui/page.gd": page}),
            [
                'ui/page.gd:9 [ellipsis] "Open…"',
                'ui/page.gd:11 [ellipsis] "Choose…"',
                'ui/page.gd:12 [ellipsis] "Save… keeps it. "',
            ],
        )

    def test_a_tooltip_without_a_full_stop_fails(self) -> None:
        # The note's scratch tr("Curve preset") fails and a
        # sentence passes. Of a join only the last piece ends the tooltip.
        body = (
            LABEL_HEAD
            + '    tooltip_text = tr("Curve preset")\n'
            + '    tooltip_text = tr("Load the curve preset.")\n'
            + '    tooltip_text = (\n        tr("Show every preset") if true else tr("Hide them.")\n    )\n'
            + '    tooltip_text = tr("Slot %s holds %s") % ["1", "Ink"]\n'
            + '    tooltip_text = tr("Curve") + ": " + tr("Linear")\n'
            + '    text = tr("Curve preset")\n'
        )
        self.assertEqual(
            self.hits({"ui/tip.gd": body}),
            [
                'ui/tip.gd:5 [tooltip] "Curve preset"',
                'ui/tip.gd:8 [tooltip] "Show every preset"',
                'ui/tip.gd:10 [tooltip] "Slot %s holds %s"',
                'ui/tip.gd:11 [tooltip] "Linear"',
            ],
        )

    def test_an_ellipsis_outside_a_translation_is_not_this_check_s(self) -> None:
        body = LABEL_HEAD + '    text = tr("Long") + "…"\n'
        self.assertNotIn("[ellipsis]", " ".join(self.hits({"ui/cut.gd": body})))


    def test_a_constant_reaching_a_property_with_no_translation(self) -> None:
        body = (
            "extends Label\n\nconst HINT := \"Click to zoom\"\nconst TITLE: String = \"Blend\"\n"
            "const ADDRESS := \"https://example.org/sara\"\nconst KEY := \"salt_and_pepper\"\n\n\n"
            "func _ready() -> void:\n"
            "    text = HINT\n"
            "    tooltip_text = tr(TITLE)\n"
            "    placeholder_text = ADDRESS\n"
            "    var kept := get_children().filter(func(one: Node) -> bool: return one.name != KEY)\n"
            "    text = HINT if kept.is_empty() else tr(TITLE)\n"
        )
        self.assertEqual(
            self.hits({"ui/hint.gd": body}),
            ['ui/hint.gd:10 [const] "Click to zoom"', 'ui/hint.gd:14 [const] "Click to zoom"'],
        )

    def test_a_constant_of_a_class_and_a_constant_built_into_a_control(self) -> None:
        owner = 'class_name Panel\n\nconst NOTE := "Nothing open"\n'
        make = (
            "class_name Make\n\n\n"
            "static func label(parent: Node, text: String = \"\") -> Label:\n"
            "    var made := Label.new()\n"
            "    made.text = text\n"
            "    return made\n"
        )
        page = (
            "extends Control\n\n\nfunc _ready() -> void:\n"
            "    $Label.text = Panel.NOTE\n"
            "    Make.label(self, Panel.NOTE)\n"
            "    $Label.text = tr(Panel.NOTE)\n"
        )
        self.assertEqual(
            self.hits({"ui/panel.gd": owner, "ui/make.gd": make, "ui/page.gd": page}),
            ['ui/page.gd:5 [const] "Nothing open"', 'ui/page.gd:6 [const] "Nothing open"'],
        )

    def test_a_command_label_given_a_constant_is_translated_where_the_command_is_shown(self) -> None:
        body = 'extends RefCounted\n\nconst NAME := "Edit Contents"\n\n\nfunc make(command: Object) -> void:\n    command.label = NAME\n'
        self.assertEqual(self.hits({"ui/command.gd": body}), [])


class TestTheListOnlyShrinks(unittest.TestCase):
    def setUp(self) -> None:
        self.tree = Fixture({"ui/bare.gd": LABEL_HEAD + '    text = tr("Open")\n    tooltip_text = "Close"\n'})
        self.addCleanup(self.tree.close)
        self.tree.list_file.write_text(
            'ui/bare.gd bare "Open"\nui/bare.gd bare "Close"\n', encoding="utf-8"
        )

    def test_a_line_the_tree_no_longer_has_fails(self) -> None:
        code, out = run(self.tree.root, self.tree.list_file)
        self.assertEqual(code, 1, out)
        self.assertIn('names ui/bare.gd [bare] "Open", which the tree no longer has', out)
        self.assertNotIn('"Close", which', out)

    def test_shrink_drops_that_line_and_adds_none(self) -> None:
        (self.tree.root / "ui" / "new.gd").write_text(LABEL_HEAD + '    text = "New"\n', encoding="utf-8")
        code, out = run(self.tree.root, self.tree.list_file, "--shrink")
        self.assertEqual(code, 1, out)
        self.assertIn('ui/new.gd:5 [bare] "New"', out)
        kept = [line for line in self.tree.list_file.read_text(encoding="utf-8").splitlines() if not line.startswith("#")]
        self.assertEqual(kept, ['ui/bare.gd bare "Close"'])


if __name__ == "__main__":
    unittest.main()
