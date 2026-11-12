#!/usr/bin/env python3
"""The translation template written from the tree.

    cd sara-godot && PYTHONPATH=scripts python -m unittest scripts.test_write_pot

`write_pot.py` reads source text, so every case runs it as the commit that cuts
a release branch does, a child process, and reads the template it writes. A
fixture tree holds each way a message reaches a translating call, a literal, a
constant of the file and of another class, a constant dictionary, a field, an
`if` with two arms, a concatenation, a context, a plural through `tr_n()` and
through `TranslationServer.translate_plural`, a function of the tree that
translates its parameter, a parameter handed to `tr()` through two functions,
a function's result, a column of a constant table a loop reads the way the
skeleton names its blend modes, and a call whose message is built at run time.
It holds strings that stay out as well, one under `harness/`, one in a suite, a
node's `.name` and an `id` a call shows. Every string comes out once with each of its places, the plural
pairs as one entry each, and nothing left out comes out at all.

Over the tree the template is read by `msgfmt --check` where it is installed and
by Godot's own `.po` loader where a Godot is, each skipping with the reason
where it is not. A copy with the placeholder `Plural-Forms` that `xgettext`
writes fails the first, which shows the check can fail.
"""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import write_pot

SCRIPT = Path(write_pot.__file__).resolve()

FIXTURE = {
    "ui/panel.gd": """\
extends Control

const SAVE_TITLE := "Save the picture"
const HINTS := {"colour": "Pick a colour", "layer": "Pick a layer"}


func _ready() -> void:
    $Open.text = tr("Open")
    $Open.tooltip_text = tr("Open")
    $Save.text = tr(SAVE_TITLE)
    var n := 3
    $Count.text = tr_n("%d layer", "%d layers", n) % n
    $Close.text = tr("Close", "menu")
    $Arm.text = tr("Shown" if visible else "Hidden")
    $Joined.text = tr("First half, " + "second half.")
    $Hint.text = tr(HINTS["colour"])
    $Quote.text = tr("Say \\"hi\\"\\nto all")
    $Run.text = tr(name_built_at_run_time())
    $Plain.text = tr("%d")
    _row("Brush size")
    _outer("Two hops")


func name_built_at_run_time() -> String:
    return "Run %d" % randi()


func _row(title: String) -> void:
    $Row.text = tr(title)


func _outer(words: String) -> void:
    _row(words)
""",
    "core/fixture_names.gd": """\
class_name SaFixtureNames
extends RefCounted

const NO_STROKE := "Paint a stroke first"


static func translated(words: String) -> String:
    return TranslationServer.translate(words)


static func kind_name(kind: int) -> String:
    return "Paint Layer" if kind == 0 else "Group"
""",
    "tools/press.gd": """\
extends Node


func _ready() -> void:
    print(tr(SaFixtureNames.NO_STROKE))
    print(SaFixtureNames.translated("Through the page"))
    print(tr(SaFixtureNames.kind_name(1)))
""",
    "render/view.gd": """\
extends Node


func _ready() -> void:
    print(tr("Rendered words"))
    print(TranslationServer.translate_plural("%d frame", "%d frames", 2))
""",
    "modules/demo/module.gd": """\
extends Node

var rows := [{"id": "brush_width", "tooltip": "How wide the brush is"}]


func _ready() -> void:
    var command := Command.new()
    command.label = "Clear Layer"
    $Row.name = "ItemList"
    print(tr(command.label))
    print(tr(rows[0]["tooltip"]))
    print(tr(String(rows[0]["id"])))
""",
    "core/fixture_modes.gd": """\
extends Node

const MODES: Array = [
    [&"glow", "Soft Glow", 10],
    [&"edge", "Hard Edge", 20],
]


func _ready() -> void:
    for row: Array in MODES:
        var made := Descriptor.new()
        made.display_name = row[1]
        print(tr(made.display_name))
    for row: Array in get_meta("rows"):
        print(tr(row[0]))
""",
    "harness/talk.gd": """\
extends Node


func _ready() -> void:
    print(tr("The harness says hello"))
""",
    "ui/tests/test_panel.gd": """\
extends Node


func test_open() -> void:
    print(tr("A suite's own words"))
""",
}


def line_of(path: str, needle: str) -> str:
    """`path:line` of the first fixture line holding *needle*."""
    for number, text in enumerate(FIXTURE[path].splitlines(), start=1):
        if needle in text:
            return f"{path}:{number}"
    raise AssertionError(f"{needle!r} is not in {path}")


def entries(template: str) -> list[dict[str, object]]:
    """The template's entries as dictionaries of their keywords and places, the header left out."""
    out: list[dict[str, object]] = []
    current: dict[str, object] = {"places": []}
    last = ""
    for line in template.splitlines() + [""]:
        if not line.strip():
            if "msgid" in current and current["msgid"] != "":
                out.append(current)
            current = {"places": []}
            continue
        if line.startswith("#:"):
            current["places"].extend(line[2:].split())  # type: ignore[union-attr]
            continue
        if line.startswith("#"):
            continue
        found = re.match(r'^(msgctxt|msgid_plural|msgid|msgstr(?:\[\d\])?) "(.*)"$', line)
        if found:
            last = found.group(1)
            current[last] = unescape(found.group(2))
        elif line.startswith('"'):
            current[last] = str(current[last]) + unescape(line[1:-1])
    return out


def unescape(text: str) -> str:
    return re.sub(r'\\(.)', lambda m: {"n": "\n", "t": "\t", "r": "\r"}.get(m.group(1), m.group(1)), text)


def run(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, str(SCRIPT), *args],
        capture_output=True,
        encoding="utf-8",
        check=False,
    )


class TheFixtureTree(unittest.TestCase):
    """Every string of the fixture once, with its places, and nothing left out."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.folder = tempfile.TemporaryDirectory()
        root = Path(cls.folder.name) / "tree"
        for path, text in FIXTURE.items():
            file = root / path
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_text(text, encoding="utf-8")
        out = Path(cls.folder.name) / "fixture.pot"
        cls.done = run("--root", str(root), "--out", str(out), "--unread")
        cls.template = out.read_text(encoding="utf-8") if out.is_file() else ""
        cls.entries = entries(cls.template)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.folder.cleanup()

    def entry(self, message: str) -> dict[str, object]:
        found = [e for e in self.entries if e["msgid"] == message and "msgctxt" not in e]
        self.assertEqual(len(found), 1, f"{message!r} is one entry of the template")
        return found[0]

    def test_the_script_writes_the_template(self) -> None:
        self.assertEqual(self.done.returncode, 0, self.done.stdout + self.done.stderr)
        self.assertIn('msgid ""\nmsgstr ""\n', self.template)
        self.assertIn('"Plural-Forms: nplurals=2; plural=(n != 1);\\n"', self.template)

    def test_every_string_is_read_once_with_each_of_its_places(self) -> None:
        expected = {
            "Open": [line_of("ui/panel.gd", 'tr("Open")'), line_of("ui/panel.gd", 'tooltip_text = tr("Open")')],
            "Save the picture": [line_of("ui/panel.gd", "const SAVE_TITLE")],
            "Shown": [line_of("ui/panel.gd", '"Shown"')],
            "Hidden": [line_of("ui/panel.gd", '"Hidden"')],
            "First half, second half.": [line_of("ui/panel.gd", "First half")],
            "Pick a colour": [line_of("ui/panel.gd", "const HINTS")],
            "Pick a layer": [line_of("ui/panel.gd", "const HINTS")],
            'Say "hi"\nto all': [line_of("ui/panel.gd", "Say")],
            "Paint a stroke first": [line_of("core/fixture_names.gd", "const NO_STROKE")],
            "Through the page": [line_of("tools/press.gd", "Through the page")],
            "Rendered words": [line_of("render/view.gd", "Rendered words")],
            "Clear Layer": [line_of("modules/demo/module.gd", "Clear Layer")],
            "How wide the brush is": [line_of("modules/demo/module.gd", "How wide")],
            "Brush size": [line_of("ui/panel.gd", '_row("Brush size")')],
            "Two hops": [line_of("ui/panel.gd", '_outer("Two hops")')],
            "Paint Layer": [line_of("core/fixture_names.gd", '"Paint Layer"')],
            "Group": [line_of("core/fixture_names.gd", '"Group"')],
            "Soft Glow": [line_of("core/fixture_modes.gd", '"Soft Glow"')],
            "Hard Edge": [line_of("core/fixture_modes.gd", '"Hard Edge"')],
            # Read as label literals: Godot translates a
            # control's text with no context, and a label no call spells out
            # still stands in the source.
            "Close": [line_of("ui/panel.gd", '"Close"')],
            "Run %d": [line_of("ui/panel.gd", '"Run %d"')],
        }
        for message, places in expected.items():
            with self.subTest(message=message):
                self.assertEqual(self.entry(message)["places"], sorted(set(places)))
        plain = [e["msgid"] for e in self.entries if "msgctxt" not in e and "msgid_plural" not in e]
        self.assertCountEqual(plain, expected, "the singular entries are these and no others")

    def test_a_context_is_the_entrys_msgctxt(self) -> None:
        found = [e for e in self.entries if e["msgid"] == "Close" and "msgctxt" in e]
        self.assertEqual(len(found), 1, "'Close' under its context is one entry")
        close = found[0]
        self.assertEqual(close["msgctxt"], "menu")
        self.assertEqual(close["places"], [line_of("ui/panel.gd", '"Close"')])

    def test_a_plural_pair_is_one_entry_with_its_plural(self) -> None:
        for message, plural, path, needle in (
            ("%d layer", "%d layers", "ui/panel.gd", "tr_n("),
            ("%d frame", "%d frames", "render/view.gd", "translate_plural("),
        ):
            with self.subTest(message=message):
                pair = self.entry(message)
                self.assertEqual(pair["msgid_plural"], plural)
                self.assertEqual((pair["msgstr[0]"], pair["msgstr[1]"]), ("", ""))
                self.assertNotIn("msgstr", pair)
                self.assertEqual(pair["places"], [line_of(path, needle)])
                self.assertEqual([e["msgid"] for e in self.entries].count(plural), 0, "the plural is no entry")

    def test_what_is_left_out_is_absent(self) -> None:
        for absent in ("The harness says hello", "A suite's own words", "ItemList", "brush_width", "%d", "glow"):
            with self.subTest(absent=absent):
                self.assertNotIn(absent, [e["msgid"] for e in self.entries])
        self.assertNotIn("harness/", self.template)
        self.assertNotIn("tests/", self.template)

    def test_a_message_built_at_run_time_or_from_an_id_is_named_and_counted(self) -> None:
        said = self.done.stdout
        self.assertIn(f"{line_of('ui/panel.gd', 'name_built_at_run_time()')}: unread", said)
        # An id reads as nothing, so the call that shows
        # one is read and named nowhere: no catalogue translates an id.
        self.assertNotIn(f"{line_of('modules/demo/module.gd', 'String(rows')}: unread", said)
        self.assertIn(f"{line_of('core/fixture_modes.gd', 'tr(row[0])')}: unread", said)
        self.assertEqual(said.count(": unread ("), 2, said)
        self.assertRegex(said, r"write_pot: 24 messages from 6 files to .*, 23 of 25 calls read, 2 pass")

    def test_a_column_of_a_constant_table_a_loop_reads_is_every_rows_string(self) -> None:
        """The skeleton names each blend mode from a row of its table, `display_name = entry[2]`.

        The loop's variable stands for every row of the constant it runs over, so
        the column it reads is every row's string, each at its own line, and a
        loop over anything the source does not spell out stays unread.
        """
        for message in ("Soft Glow", "Hard Edge"):
            with self.subTest(message=message):
                self.assertEqual(self.entry(message)["places"], [line_of("core/fixture_modes.gd", f'"{message}"')])
        self.assertNotIn(line_of("core/fixture_modes.gd", "display_name = row[1]"), self.done.stdout)


ROWS_FIXTURE = """\
extends Node

const ROWS: Array = [
    {"label": "Hue", "key": "hue", "min": -180.0, "max": 180.0},
    {"key": "saturation", "min": 0.0, "max": 200.0, "label": "Saturation"},
    {"type": "check", "key": "colorize", "label": "Colourise", "default": false},
]


func build() -> void:
    for row: Dictionary in ROWS:
        print(tr(String(row["label"])))
"""


class ARowsLabels(unittest.TestCase):
    """Every `"label"` of a row dictionary, whatever its place among the keys, check rows included."""

    def test_a_check_rows_label_and_a_label_after_other_keys_are_read(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder) / "tree"
            file = root / "modules" / "demo" / "rows_filter.gd"
            file.parent.mkdir(parents=True)
            file.write_text(ROWS_FIXTURE, encoding="utf-8")
            out = Path(folder) / "rows.pot"
            done = run("--root", str(root), "--out", str(out))
            self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
            found = {str(e["msgid"]) for e in entries(out.read_text(encoding="utf-8"))}
        self.assertIn("Hue", found, "a label that is the row's first key")
        self.assertIn("Saturation", found, "a label that is the row's last key")
        self.assertIn("Colourise", found, "the label of a check row, after its type and key")


PIXEL_FIXTURE = """# Soften the picture with a flat average of each pixel's neighbours in a square
# whose reach is the radius, in pixels.
#
# A second paragraph, which is not the sentence.

uniform int radius: hint_range(1, 20) = 3


def pixel(ivec2 at) -> vec4:
    return src(at)
"""

KERNEL_FIXTURE = """# A written kernel, whose comment is no filter's sentence.

kernel blur
"""


class APixelFunctionsSentence(unittest.TestCase):
    """A pixel function's leading comment is its filter's sentence, and the template holds it."""

    def test_the_first_paragraph_of_a_pixel_functions_comment_is_read(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder) / "tree"
            for name, text in (("blur.gmacs", PIXEL_FIXTURE), ("old_blur.gmacs", KERNEL_FIXTURE)):
                file = root / "modules" / "demo" / name
                file.parent.mkdir(parents=True, exist_ok=True)
                file.write_text(text, encoding="utf-8")
            out = Path(folder) / "pixel.pot"
            done = run("--root", str(root), "--out", str(out))
            self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
            found = {str(e["msgid"]) for e in entries(out.read_text(encoding="utf-8"))}
        sentence = "Soften the picture with a flat average of each pixel's neighbours in a square whose reach is the radius, in pixels."
        self.assertIn(sentence, found, "the two lines joined as SaPixelFilter joins them")
        self.assertIn("Radius", found, "beside the slider's title")
        self.assertNotIn("A second paragraph, which is not the sentence.", found, "and nothing past the first paragraph")
        self.assertNotIn("A written kernel, whose comment is no filter's sentence.", found, "nor a written kernel's comment")


class TheTree(unittest.TestCase):
    """The template of the tree itself, read by `msgfmt --check` and by Godot's loader."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.folder = tempfile.TemporaryDirectory()
        cls.pot = Path(cls.folder.name) / "sara.pot"
        cls.done = run("--out", str(cls.pot), "--unread")
        cls.entries = entries(cls.pot.read_text(encoding="utf-8")) if cls.pot.is_file() else []
        cls.count = len(cls.entries)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.folder.cleanup()

    def test_the_tree_gives_a_template(self) -> None:
        self.assertEqual(self.done.returncode, 0, self.done.stdout + self.done.stderr)
        self.assertGreater(self.count, 1000, "the tree passes over a thousand messages")
        self.assertIn(f"write_pot: {self.count} messages", self.done.stdout)

    def test_the_template_holds_every_name_the_skeleton_registers(self) -> None:
        """Every built-in blend mode's name, read off the table the skeleton registers them from."""
        table = "core/loader/skeleton_blend_modes.gd"
        text = (write_pot.SARA_GODOT / table).read_text(encoding="utf-8")
        rows = re.findall(r'^\s*\[&"(\w+)", "\w+", "([^"]+)", \d+,', text, re.M)
        self.assertEqual(len(rows), text.count("SaBlendModeDescriptor.Domain."), "every row of the table is read")
        held = {str(e["msgid"]): e["places"] for e in self.entries if "msgctxt" not in e}
        for mode, name in rows:
            with self.subTest(mode=mode):
                self.assertTrue(name in held, f"{name!r} is in the template")
                self.assertTrue(any(p.startswith(table + ":") for p in held[name]), held[name])
        self.assertNotIn(table + ":", self.done.stdout, "--unread names no line of the table's loop")

    def test_msgfmt_reads_it_without_an_error(self) -> None:
        msgfmt = shutil.which("msgfmt")
        if msgfmt is None:
            self.skipTest("msgfmt is not installed")
        done = subprocess.run(
            [msgfmt, "--check", "-o", os.devnull, str(self.pot)], capture_output=True, encoding="utf-8", check=False
        )
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertNotIn("error", done.stderr)
        placeholder = Path(self.folder.name) / "placeholder.pot"
        placeholder.write_text(
            self.pot.read_text(encoding="utf-8").replace(
                "nplurals=2; plural=(n != 1);", "nplurals=INTEGER; plural=EXPRESSION;"
            ),
            encoding="utf-8",
        )
        refused = subprocess.run(
            [msgfmt, "--check", "-o", os.devnull, str(placeholder)], capture_output=True, encoding="utf-8", check=False
        )
        self.assertNotEqual(refused.returncode, 0, "the check fails a template msgfmt cannot read")

    def test_godots_po_loader_reads_it_without_an_error(self) -> None:
        import sara_shot

        godot = sara_shot.godot_for_a_suite()
        project = Path(self.folder.name) / "project"
        project.mkdir()
        (project / "project.godot").write_text(
            'config_version=5\n\n[application]\n\nconfig/name="write_pot check"\n', encoding="utf-8"
        )
        shutil.copy(self.pot, project / "template.po")
        (project / "read.gd").write_text(
            "extends SceneTree\n\n\nfunc _init() -> void:\n"
            '    var read: Translation = load("res://template.po")\n'
            '    print("POT_READ %d" % (read.get_message_count() if read else -1))\n'
            "    quit(0)\n",
            encoding="utf-8",
        )
        home = Path(self.folder.name) / "home"
        env = dict(os.environ)
        for name in ("XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME", "APPDATA", "LOCALAPPDATA"):
            env[name] = str(home / name.lower())
        done = subprocess.run(
            [godot, "--headless", "--path", str(project), "--script", "res://read.gd"],
            capture_output=True,
            encoding="utf-8",
            errors="replace",
            env=env,
            timeout=120,
            check=False,
        )
        said = done.stdout + done.stderr
        self.assertIn(f"POT_READ {self.count}", said, said[-2000:])
        self.assertNotIn("ERROR", said, said[-2000:])


if __name__ == "__main__":
    unittest.main()
