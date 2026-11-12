"""What `sara_shot.py` does with a run's output, asserted without a run.

    cd sara-godot && python3 -m unittest discover -s scripts -p 'test_*.py'

The scenario runner was once blind to a script error the door reports, on
the strength of a run that printed 146 problem lines, 2 distinct, and a `run.log`
holding no `SCRIPT ERROR` at all. Those are the numbers of a run against the
*fixed* branch, where nothing raises. Against the branch the filing describes the
same runner prints 148 lines, 3 distinct, and `run.log` holds both copies.

So these are the assertions that would have caught the mistake in a second: the
classifier takes a script error, the fold counts it rather than hiding it behind
a repeated warning, and the log carries stdout and stderr whole. None of them
needs Godot, weston or a GPU.
"""

from __future__ import annotations

import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
import unittest.mock
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

import sara_shot
import shell_script

SCRIPTS_DIR = Path(__file__).resolve().parent


SCRIPT_ERROR = "SCRIPT ERROR: Left operand of 'is' is a previously freed instance."


class IsProblemTest(unittest.TestCase):
    def test_a_script_error_is_a_problem(self) -> None:
        self.assertTrue(sara_shot.is_problem(SCRIPT_ERROR))
        self.assertTrue(sara_shot.is_problem("   at: something (res://ui/x.gd:12) SCRIPT ERROR"))

    def test_an_engine_error_and_a_failed_capture_step_are_problems(self) -> None:
        self.assertTrue(sara_shot.is_problem("ERROR: Parameter \"data.tree\" is null."))
        self.assertTrue(sara_shot.is_problem("SaCapture: stroke failed: no dab reached the GPU"))

    def test_a_path_that_contains_the_word_is_not_a_problem(self) -> None:
        """A proof folder called `...-all-failed-is-a-green-run` once had its own
        `wrote` lines listed as problems."""
        wrote = "SaCapture: wrote /tmp/units/a-capture-whose-strokes-all-failed-is-a-green-run/a.png"
        self.assertFalse(sara_shot.is_problem(wrote))
        self.assertTrue(sara_shot.is_problem("SaCapture: failed to write /tmp/a.png (7)"))
        self.assertTrue(sara_shot.is_problem("SaCapture: click failed, no control 'Place'"))

    def test_an_ordinary_line_is_not(self) -> None:
        self.assertFalse(sara_shot.is_problem("SaCapture: wrote 01-painted.png"))
        self.assertFalse(sara_shot.is_problem("WARNING: xdg-toplevel-icon protocol not found!"))

    def test_a_step_that_found_no_control_is_a_problem(self) -> None:
        """The refusal three scenarios drove at length.

        `failed` was the only word the reader knew, and a step that cannot find
        its control does not use it. So `{"choice": {"open": "PickerType"}}`
        printed a refusal, the three steps after it found no open list, and the
        run reported no problems at all.
        """
        self.assertTrue(sara_shot.is_problem("SaCapture: no dropdown called 'PickerType'"))
        self.assertTrue(sara_shot.is_problem("SaCapture: no choice list is open"))
        self.assertTrue(sara_shot.is_problem("SaCapture: found no embedded docker called 'LayersDocker'"))
        self.assertTrue(sara_shot.is_problem("SaCapture: cannot write /tmp/nowhere/shot.png"))
        self.assertTrue(sara_shot.is_problem("SaCapture: could not read scenario probe.json"))

    def test_a_report_that_merely_starts_with_a_negative_word_is_not(self) -> None:
        """The boundary after `no` is what separates the two.

        A refusal names a control it could not find. A report that happens to
        open with `nothing` or `none` is the step saying what it did, and a
        reader that flagged those would be noise an agent learns to skip.
        """
        self.assertFalse(sara_shot.is_problem("SaCapture: nothing to undo"))
        self.assertFalse(sara_shot.is_problem("SaCapture: none of the rows moved"))
        self.assertFalse(sara_shot.is_problem("SaCapture: picked row 3, 'HSV, triangle'"))


class LeakAtExitTest(unittest.TestCase):
    """Seven objects leaked at the end of every capture, and the
    line saying so opens with `WARNING:`, which the reader let through."""

    def test_a_leak_line_is_a_problem_in_either_number(self) -> None:
        plural = "WARNING: 7 ObjectDB instances were leaked at exit (run with `--verbose` for details)."
        single = "WARNING: 1 ObjectDB instance was leaked at exit (run with `--verbose` for details)."
        rids = "ERROR: 3 RID allocations of type 'N10RendererRD14TextureStorage7TextureE' were leaked at exit."
        for line in (plural, single, rids, "WARNING: 2 resources still in use at exit."):
            self.assertTrue(sara_shot.is_problem(line), line)

    def test_a_run_that_leaked_reports_it(self) -> None:
        stdout = "SaCapture: wrote /tmp/a.json\nSaCapture: done\n"
        stderr = "WARNING: 7 ObjectDB instances were leaked at exit (run with `--verbose` for details).\n"
        buffer = io.StringIO()
        with redirect_stderr(buffer):
            sara_shot.report_problems(Completed(stdout, stderr), Path("/tmp/run.log"))
        self.assertIn("7 ObjectDB instances were leaked at exit", buffer.getvalue())
        self.assertIn("1 problem line(s) reported by the run", buffer.getvalue())

    def test_the_pattern_is_the_gates(self) -> None:
        """One pattern in two languages, so the suite holds them to one text."""
        gate = (Path(sara_shot.__file__).resolve().parent.parent / "run_tests.sh").read_text(encoding="utf-8")
        self.assertIn(f'grep -Eq "{sara_shot.LEAK_PATTERN}"', gate)


class RefusalWordsAreTheTreesTest(unittest.TestCase):
    """Every refusal `SaCapture:` line in the tree opens with a word the reader knows.

    The rule in `sara_shot.REFUSAL_OPENERS` is only as good as the messages it
    is checked against, and the messages are in GDScript where no Python test
    would otherwise look. This walks them, so a step kind added tomorrow with a
    refusal worded some other way fails here rather than going quiet in a run.
    """

    def test_every_refusal_message_opens_with_a_known_word(self) -> None:
        import re

        roots = [Path(__file__).resolve().parents[1] / d for d in ("ui", "core", "tools", "render")]
        pattern = re.compile(r"\"SaCapture: ((?:found no|no|cannot|could not|refused)\b[^\"]*)\"")
        seen = 0
        for root in roots:
            if not root.is_dir():
                continue
            for path in root.rglob("*.gd"):
                for match in pattern.finditer(path.read_text(encoding="utf-8")):
                    seen += 1
                    line = "SaCapture: %s" % match.group(1)
                    self.assertTrue(
                        sara_shot.is_problem(line),
                        "%s: the reader would not flag %r" % (path.name, line),
                    )
        self.assertGreater(seen, 40, "the walk found the refusals rather than nothing")


class Completed:
    """The two fields `report_problems` and `write_run_log` read."""

    def __init__(self, stdout: str, stderr: str = "", returncode: int = 0) -> None:
        self.stdout = stdout
        self.stderr = stderr
        self.returncode = returncode


class ReportTest(unittest.TestCase):
    def _report(self, stdout: str, stderr: str = "") -> str:
        buffer = io.StringIO()
        with redirect_stderr(buffer):
            sara_shot.report_problems(Completed(stdout, stderr), Path("/tmp/run.log"))
        return buffer.getvalue()

    def test_a_script_error_reaches_the_report_from_either_stream(self) -> None:
        self.assertIn(SCRIPT_ERROR, self._report(SCRIPT_ERROR + "\n"))
        self.assertIn(SCRIPT_ERROR, self._report("", SCRIPT_ERROR + "\n"))

    def test_two_copies_are_folded_and_counted(self) -> None:
        out = self._report((SCRIPT_ERROR + "\n") * 2)
        self.assertIn("2x " + SCRIPT_ERROR, out)
        self.assertIn("2 problem line(s) reported by the run, 1 distinct", out)

    def test_a_repeated_warning_cannot_crowd_a_script_error_out(self) -> None:
        # What this pins: the cap is on distinct lines, so 500
        # copies of one warning cost one row and the script error keeps its own.
        noisy = "ERROR: Couldn't get Vulkan surface capabilities.\n" * 500
        out = self._report(noisy + SCRIPT_ERROR + "\n")
        self.assertIn(SCRIPT_ERROR, out)
        self.assertIn("501 problem line(s) reported by the run, 2 distinct", out)

    def test_a_clean_run_reports_nothing(self) -> None:
        self.assertEqual(self._report("SaCapture: wrote 01.png\n"), "")


# The two verdicts the stroke step prints, in the shape `_report_stroke` writes
# them. The failed one is a real run's line.
PAINTED_STROKE = "SaCapture: stroke (500, 260) -> (1500, 260)  pressure 1.00  20 frames  750 GPU dispatches"
FAILED_STROKE = (
    "SaCapture: stroke (200, 380) -> (1740, 380)  pressure 1.00  40 frames failed: no dab reached the GPU,"
    " 'Tool Options' covers (200, 380) and took the press from the brush tool"
)
# A pan or a selection stroke, which draws nothing on purpose and is not a failure.
QUIET_STROKE = (
    "SaCapture: stroke (600, 400) -> (900, 400)  pressure 0.80  16 frames  no GPU work,"
    " the press landed on the canvas, so the pan tool drew nothing"
)


class StrokeVerdictTest(unittest.TestCase):
    """A capture whose every stroke lost its press to a docker is
    not a green run, and one where some did says so."""

    def _report(self, stdout: str) -> tuple[int | None, str]:
        buffer = io.StringIO()
        with redirect_stderr(buffer):
            code = sara_shot.report_strokes(stdout)
        return code, buffer.getvalue()

    def test_the_verdict_counts_painted_failed_and_all(self) -> None:
        stdout = "\n".join([PAINTED_STROKE, FAILED_STROKE, QUIET_STROKE, "SaCapture: wrote 1.png"])
        self.assertEqual(sara_shot.stroke_verdict(stdout), (1, 1, 3))

    def test_every_stroke_taken_by_a_docker_is_its_own_exit_code(self) -> None:
        code, said = self._report(FAILED_STROKE + "\n" + FAILED_STROKE + "\n")
        self.assertEqual(code, sara_shot.EXIT_NO_STROKE_PAINTED)
        self.assertIn("no stroke painted: all 2", said)

    def test_some_taken_is_a_line_and_not_a_code(self) -> None:
        code, said = self._report(PAINTED_STROKE + "\n" + FAILED_STROKE + "\n")
        self.assertIsNone(code, "the painted stroke's pictures are real")
        self.assertIn("1 of 2 stroke(s) painted nothing", said)

    def test_a_stroke_that_draws_nothing_on_purpose_is_not_a_failure(self) -> None:
        code, said = self._report(QUIET_STROKE + "\n")
        self.assertIsNone(code)
        self.assertEqual(said, "")

    def test_a_run_with_no_stroke_says_nothing(self) -> None:
        code, said = self._report("SaCapture: wrote 1.png\nSaCapture: done\n")
        self.assertIsNone(code)
        self.assertEqual(said, "")

    def test_the_marker_is_the_one_the_stroke_step_prints(self) -> None:
        """The reader and the writer are two files, so the phrase is checked
        against the writer rather than trusted to match."""
        gd = (SCRIPTS_DIR.parent / "harness" / "scenario" / "sa_scenario_stroke.gd").read_text(encoding="utf-8")
        self.assertIn(sara_shot.STROKE_FAILED.strip(), gd)
        self.assertIn(sara_shot.STROKE_PAINTED.strip(), gd)


@shell_script.runs_here()
class StrokeVerdictEndToEnd(unittest.TestCase):
    """The exit code through `sara_shot.py` itself, with a stub in place of Godot.

    A real capture of a stroke over a docker is a minute of compositor and GPU,
    which this suite exists to avoid, and the real one is recorded beside the
    unit. The stub prints what that run printed and exits 0, which is the whole
    of the bug: the child succeeded and the run was worthless.
    """

    def _stub(self, *lines: str) -> str:
        return (
            'out=""\n'
            'for arg in "$@"; do case "$arg" in --capture-out=*) out="${arg#--capture-out=}" ;; esac; done\n'
            'mkdir -p "$out"\n'
            'printf x > "$out/a-shot.png"\n'
            + "cat <<'LINES'\n"
            + "\n".join(lines)
            + "\nSaCapture: done\nLINES\n"
            + "exit 0\n"
        )

    def _run(self, stub: str) -> subprocess.CompletedProcess:
        with tempfile.TemporaryDirectory() as raw:
            room = Path(raw)
            fake = shell_script.startable(shell_script.stand_in(room / "fake-godot", stub))
            # SARA_GATE_SLOT_HELD, or the stub waits for one of the machine's Godot
            # slots behind every other clone's capture. The first run of these two
            # cases timed out at ninety seconds that way, on a stub that launches
            # nothing.
            env = dict(os.environ, GODOT_BIN=str(fake), SARA_SHOT_TIMEOUT="30", SARA_GATE_SLOT_HELD="1")
            return subprocess.run(
                [
                    sys.executable,
                    str(SCRIPTS_DIR / "sara_shot.py"),
                    "--watch",
                    "--scenario",
                    str(SCRIPTS_DIR.parent / "scenarios" / "a-capture-whose-strokes-all-failed-is-a-green-run.json"),
                    "--out",
                    str(room / "out"),
                ],
                capture_output=True,
                encoding="utf-8",
                env=env,
                timeout=90,
            )

    def test_a_run_whose_every_stroke_failed_exits_non_zero(self) -> None:
        done = self._run(self._stub(FAILED_STROKE))
        self.assertEqual(done.returncode, sara_shot.EXIT_NO_STROKE_PAINTED, done.stderr[-800:])
        self.assertIn("no stroke painted", done.stderr)
        self.assertIn("1 artefact(s)", done.stdout, "and the artefacts are still listed")

    def test_a_run_that_painted_stays_green(self) -> None:
        done = self._run(self._stub(PAINTED_STROKE))
        self.assertEqual(done.returncode, 0, done.stderr[-800:])
        self.assertNotIn("painted nothing", done.stderr)

class RunLogTest(unittest.TestCase):
    def test_the_log_holds_both_streams_whole(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            out_dir = Path(raw)
            proc = Completed("a line of stdout\n", SCRIPT_ERROR + "\n", returncode=0)
            path = sara_shot.write_run_log(out_dir, ["godot", "--capture"], proc)
            text = path.read_text(encoding="utf-8")
        self.assertIn("a line of stdout", text)
        self.assertIn(SCRIPT_ERROR, text)
        self.assertIn("# exit 0", text)


class SuiteRunsTest(unittest.TestCase):
    def test_the_module_imports_without_a_display(self) -> None:
        # `sara_shot` is a script first and a module second, so an import that
        # started weston or parsed argv would make every assertion above a lie.
        proc = subprocess.run(
            [sys.executable, "-c", "import sara_shot"],
            cwd=str(Path(__file__).resolve().parent),
            capture_output=True,
            encoding="utf-8",
            check=False,
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)


class TheClassCache(unittest.TestCase):
    """`run_tests.sh` lets the editor look when a `class_name` is newer than
    the cache and `sara_shot.py` did not, so the order a unit worked in decided
    whether its scenario ran: gate first and it was fine, scenario first and it
    died on `Parse Error: Identifier "SaPresetDiff" not declared in the current
    scope`, in a file the unit had not written.

    The staleness rule is asserted here rather than the pass itself, which is
    four seconds of Godot. `ensure_class_cache` is the rule plus one
    `subprocess.run`, and the rule is the half that can be wrong.
    """

    def _tree(self, room: Path) -> tuple[Path, Path]:
        (room / ".godot").mkdir()
        cache = room / ".godot" / "global_script_class_cache.cfg"
        script = room / "core" / "sa_thing.gd"
        script.parent.mkdir()
        script.write_text("class_name SaThing\n", encoding="utf-8")
        return cache, script

    def test_no_cache_at_all_asks_for_an_import(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            room = Path(raw)
            cache, _ = self._tree(room)
            self.assertEqual(sara_shot.class_cache_state(cache, room), "import")

    def test_a_script_newer_than_the_cache_asks_for_a_rescan(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            room = Path(raw)
            cache, script = self._tree(room)
            cache.write_text("", encoding="utf-8")
            os.utime(cache, (1, 1))
            os.utime(script, (2, 2))
            self.assertEqual(sara_shot.class_cache_state(cache, room), "rescan")

    def test_a_cache_newer_than_every_script_is_current(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            room = Path(raw)
            cache, script = self._tree(room)
            cache.write_text("", encoding="utf-8")
            os.utime(script, (1, 1))
            os.utime(cache, (2, 2))
            self.assertEqual(sara_shot.class_cache_state(cache, room), "current")

    def test_the_four_pruned_directories_are_the_shell_s(self) -> None:
        """`.godot`, `scratch`, `.conda` and `build`. A `.gd` under any of them
        is output or a tool's own, and `scratch` in particular is written by
        every run, so counting it would rescan on every launch for ever."""
        with tempfile.TemporaryDirectory() as raw:
            room = Path(raw)
            cache, script = self._tree(room)
            cache.write_text("", encoding="utf-8")
            os.utime(script, (1, 1))
            os.utime(cache, (2, 2))
            for skipped in sorted(sara_shot.CACHE_SKIPS):
                noisy = room / skipped / "later.gd"
                noisy.parent.mkdir(exist_ok=True)
                noisy.write_text("class_name Later\n", encoding="utf-8")
                os.utime(noisy, (9, 9))
            self.assertEqual(
                sara_shot.class_cache_state(cache, room), "current", "a newer script under a pruned directory is not one"
            )

    def test_the_rule_is_the_one_run_tests_sh_uses(self) -> None:
        """Read from the shell rather than trusted, because two copies of a rule
        that drift are worse than one runner without it."""
        shell = (Path(__file__).resolve().parent.parent / "run_tests.sh").read_text(encoding="utf-8")
        self.assertIn("global_script_class_cache.cfg", shell)
        self.assertIn("--editor --quit", shell)
        for skipped in sara_shot.CACHE_SKIPS:
            self.assertIn(f"-name {skipped}", shell, f"{skipped} is pruned there too")

    def test_the_door_calls_it_too(self) -> None:
        """The door had the same gap for the same reason, and `sara_door.py`
        already imports this module for `find_godot`."""
        door = (Path(__file__).resolve().parent / "sara_door.py").read_text(encoding="utf-8")
        self.assertIn("sara_shot.ensure_class_cache(", door)


class ChildCommand(unittest.TestCase):
    """Where an argument for the app itself lands on the command line.

    `SaBoot.document_path` reads `OS.get_cmdline_user_args()`, everything
    after the `--`, and takes the first entry that does not begin with a dash.
    So the order below is a claim about which entry that is, and every assertion
    here is that claim rather than a restatement of the list.
    """

    def _cmd(self, app_args=None, settings=Path("/cfg")):
        return sara_shot.child_command("godot", "wayland", "--capture=s.json", Path("/out"), settings, app_args)

    def test_an_app_argument_lands_after_the_separator(self) -> None:
        cmd = self._cmd(["user://a.sad"])
        self.assertIn("--", cmd)
        self.assertGreater(cmd.index("user://a.sad"), cmd.index("--"), "the app only reads what is past the separator")

    def test_it_is_the_first_entry_that_is_not_an_option(self) -> None:
        cmd = self._cmd(["user://a.sad"])
        past = cmd[cmd.index("--") + 1 :]
        first_path = next(entry for entry in past if not entry.startswith("-"))
        self.assertEqual(first_path, "user://a.sad", "which is what document_path will take")

    def test_the_harness_flags_are_still_there_and_still_options(self) -> None:
        cmd = self._cmd(["user://a.sad"])
        past = cmd[cmd.index("--") + 1 :]
        self.assertIn("--capture=s.json", past)
        self.assertIn("--capture-out=/out", past)
        self.assertIn("--settings-dir=/cfg", past)
        for flag in ("--capture=s.json", "--capture-out=/out", "--settings-dir=/cfg"):
            self.assertTrue(flag.startswith("-"), "so document_path walks past it")

    def test_several_arguments_keep_their_order(self) -> None:
        cmd = self._cmd(["first.sad", "second.sad"])
        self.assertLess(cmd.index("first.sad"), cmd.index("second.sad"), "the first one asked for is the first one seen")

    def test_a_run_with_no_app_argument_is_what_it_always_was(self) -> None:
        """Every scenario on the board runs through this path, so the empty case
        is the one that must not have moved."""
        self.assertEqual(
            self._cmd(),
            [
                "godot",
                "--path",
                str(sara_shot.PROJECT_DIR),
                "--display-driver",
                "wayland",
                "--",
                "--capture=s.json",
                "--capture-out=/out",
                "--settings-dir=/cfg",
            ],
        )

    def test_watch_drops_the_settings_flag_and_keeps_the_rest(self) -> None:
        cmd = self._cmd(["user://a.sad"], settings=None)
        self.assertFalse(any(entry.startswith("--settings-dir=") for entry in cmd))
        self.assertEqual(cmd[-1], "user://a.sad", "and the app's own argument is still last")


class ScenarioArguments(unittest.TestCase):
    """A scenario naming its own command-line argument.

    The entry has to leave the file before the app is handed it, because
    `sa_capture.gd` warns on a step it does not know and the argument handling does not own that
    branch. So both halves are the claim: what comes out, and what is left.
    """

    def test_the_entry_becomes_an_argument(self) -> None:
        steps, app_args, _, _ = sara_shot.split_harness_steps([{"args": ["user://a.sad"]}, {"wait": 5}])
        self.assertEqual(app_args, ["user://a.sad"])

    def test_the_entry_does_not_reach_the_app(self) -> None:
        steps, _, _, _ = sara_shot.split_harness_steps([{"args": ["user://a.sad"]}, {"wait": 5}])
        self.assertEqual(steps, [{"wait": 5}], "or the app warns about a step it does not know")

    def test_a_bare_string_is_one_argument(self) -> None:
        _, app_args, _, _ = sara_shot.split_harness_steps([{"args": "user://a.sad"}])
        self.assertEqual(app_args, ["user://a.sad"], "so a scenario need not wrap one path in a list")

    def test_several_entries_keep_their_order(self) -> None:
        _, app_args, _, _ = sara_shot.split_harness_steps([{"args": ["one"]}, {"wait": 1}, {"args": ["two", "three"]}])
        self.assertEqual(app_args, ["one", "two", "three"])

    def test_a_scenario_with_no_entry_is_untouched(self) -> None:
        """Every scenario on the board goes through this, so the empty case is
        the one that must not have moved."""
        steps = [{"wait": 5}, {"window": [2560, 1440]}, {"shot": "one"}]
        self.assertEqual(sara_shot.split_harness_steps(list(steps)), (steps, [], False, ""))

    def test_the_window_step_survives_the_strip(self) -> None:
        """`output_size_for` reads the stripped copy, so a scenario that asks for
        both a width and an argument still gets its width."""
        steps, _, _, _ = sara_shot.split_harness_steps([{"args": ["a.sad"]}, {"window": [2560, 1440]}])
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False, encoding="utf-8") as handle:
            json.dump(steps, handle)
        try:
            self.assertEqual(sara_shot.output_size_for(Path(handle.name)), (2560, 1440))
        finally:
            os.unlink(handle.name)

    def test_an_unreadable_scenario_is_no_steps_rather_than_a_crash(self) -> None:
        self.assertEqual(sara_shot.read_steps(Path("/no/such/scenario.json")), [])
        self.assertEqual(sara_shot.read_steps(None), [])


class EngineLog(unittest.TestCase):
    """A capture's log is the checkout's, never the painter's.

    Godot keeps ten logs in `user://logs` and every run writes one, so a watched
    capture used to rotate away the log a painter's freeze had left.
    """

    def test_the_flag_and_the_variable_name_one_file_under_scratch(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            profile = sara_shot.ShotProfile(Path(tmp))
            env: dict = {}
            flags = profile.log_to(env)
            self.assertEqual(flags, ["--log-file", str(profile.log_file)], "the engine's flag and its file")
            self.assertEqual(env["SARA_LOG_FILE"], str(profile.log_file), "and the app told the same file")
            self.assertTrue(profile.log_file.parent.is_dir(), "whose folder is there to be written")
            self.assertTrue(profile.log_file.is_relative_to(Path(tmp) / "scratch"), "in the checkout's scratch")


class SettingsDirectory(unittest.TestCase):
    """Every capture opens on the defaults unless something asks otherwise.

    The app writes the docker layout and the settings file back on exit, so
    before this the layout one scenario left was the layout the next one opened
    with, and a before-and-after pair could be comparing two layouts rather than
    two trees.
    """

    def setUp(self) -> None:
        self.profile = sara_shot.ShotProfile(sara_shot.PROJECT_DIR)
        self.directory = self.profile.settings_dir
        self.saved = None
        if self.directory.exists():
            self.saved = self.directory.with_name("sara-saved-by-a-test")
            shutil.rmtree(self.saved, ignore_errors=True)
            self.directory.rename(self.saved)

    def tearDown(self) -> None:
        shutil.rmtree(self.directory, ignore_errors=True)
        if self.saved is not None:
            self.saved.rename(self.directory)

    def _leave_a_layout(self) -> "Path":
        self.directory.mkdir(parents=True, exist_ok=True)
        written = self.directory / "docker_layout.cfg"
        written.write_text("[MinimapDocker]\nposition=Vector2i(40, 40)\n", encoding="utf-8")
        return written

    def _prepare(self, keep: bool) -> str:
        """The call, with what it printed, because the run log is what a reader
        of a surprising capture reaches for first."""
        said = io.StringIO()
        with redirect_stdout(said):
            self.profile.prepare_settings(keep=keep)
        return said.getvalue()

    def test_a_run_does_not_inherit_the_last_one_s_layout(self) -> None:
        written = self._leave_a_layout()
        self._prepare(keep=False)
        self.assertFalse(written.exists(), "or the next scenario opens on this scenario's dockers")

    def test_the_prefs_a_scenario_set_go_with_it(self) -> None:
        """The settings file is the same trap one file over, so the directory
        goes rather than `docker_layout.cfg` alone."""
        self.directory.mkdir(parents=True, exist_ok=True)
        (self.directory / "settings.cfg").write_text("[TopMenuBar]\nstabilizer_mode=true\n", encoding="utf-8")
        self._prepare(keep=False)
        self.assertFalse((self.directory / "settings.cfg").exists())

    def test_the_directory_is_there_afterwards_either_way(self) -> None:
        for keep in (False, True):
            shutil.rmtree(self.directory, ignore_errors=True)
            said = io.StringIO()
            with redirect_stdout(said):
                self.assertTrue(self.profile.prepare_settings(keep=keep).is_dir())

    def test_keeping_leaves_what_was_there(self) -> None:
        written = self._leave_a_layout()
        self._prepare(keep=True)
        self.assertTrue(written.exists(), "or --keep-settings means nothing")

    def test_the_run_says_which_of_the_two_it_did(self) -> None:
        self.assertIn("cleared", self._prepare(keep=False))

    def test_the_data_root_under_it_is_emptied_but_its_caches_stay(self) -> None:
        """`--settings-dir` makes `<dir>/data` the data root,
        so the painter state a run leaves goes there and so does the SPIR-V
        cache, which a cold capture has timed out compiling before."""
        data = self.directory / self.profile.DATA_ROOT
        (data / "brush_presets").mkdir(parents=True, exist_ok=True)
        (data / "colors.cfg").write_text("", encoding="utf-8")
        for cache in self.profile.USER_CACHES:
            (data / cache).mkdir(exist_ok=True)
            (data / cache / "compiled").write_text("", encoding="utf-8")
        self._prepare(keep=False)
        self.assertFalse((data / "colors.cfg").exists(), "or the next scenario opens on this one's swatches")
        self.assertFalse((data / "brush_presets").exists())
        for cache in self.profile.USER_CACHES:
            self.assertTrue((data / cache / "compiled").exists(), f"{cache} is compiled work, not painter state")


class TwoStreamsInOneCheckout(unittest.TestCase):
    """A gate run in two streams reads each scenario from a profile of its own.

    One `scratch/xdg` per checkout was shared by both streams, so one stream's
    `prepare` emptied the folder under the other and a scenario that left UI
    scale 2 in its settings handed that scale to a neighbour's start."""

    def setUp(self) -> None:
        self.root = Path(tempfile.mkdtemp(prefix="sara-profile-lease-"))
        self.addCleanup(shutil.rmtree, self.root, ignore_errors=True)
        self.profile = sara_shot.ShotProfile(self.root)
        saved = os.environ.pop(self.profile.NAME_ENV, None)
        if saved is not None:
            self.addCleanup(os.environ.__setitem__, self.profile.NAME_ENV, saved)

    def test_without_a_lease_the_run_takes_the_shared_profile(self) -> None:
        self.assertEqual(self.root / "scratch" / "xdg" / "config" / "sara", self.profile.settings_dir)

    def test_two_leases_at_once_never_share_a_profile(self) -> None:
        with self.profile.lease():
            first = self.profile.settings_dir
            with sara_shot.ShotProfile(self.root).lease():
                second = self.profile.settings_dir
        self.assertNotEqual(first, second)
        self.assertNotEqual(self.root / "scratch" / "xdg" / "config" / "sara", first)

    def test_a_lease_given_back_is_taken_again_and_the_env_is_restored(self) -> None:
        with self.profile.lease():
            first = self.profile.settings_dir
        self.assertNotIn(self.profile.NAME_ENV, os.environ)
        with self.profile.lease():
            self.assertEqual(first, self.profile.settings_dir, "or the shader caches in it are never warm")

    def test_a_neighbour_clearing_its_profile_leaves_this_one_alone(self) -> None:
        said = io.StringIO()
        with self.profile.lease():
            mine = self.profile.settings_dir
            mine.mkdir(parents=True)
            (mine / "settings.cfg").write_text("[ui]\nscale=2.0\n", encoding="utf-8")
            with sara_shot.ShotProfile(self.root).lease(), redirect_stdout(said):
                self.profile.prepare(keep=False)
            self.assertTrue((mine / "settings.cfg").exists())


class UserDirectoryIsEmptiedBetweenRuns(unittest.TestCase):
    """`ShotProfile.prepare_user` is the data-home half of the isolation.

    `user://` lives under `XDG_DATA_HOME`, which the offscreen run points at
    `scratch/xdg/data`, and until this only the config home was emptied. A
    swatch a scenario added was in its next run's strip, three runs in a row.
    The GPU caches stay, because a first capture on a cold shader cache has timed
    out on the compile before.
    """

    def setUp(self) -> None:
        self.profile = sara_shot.ShotProfile(sara_shot.PROJECT_DIR)
        self.directory = self.profile.user_dir
        self.saved = None
        if self.directory.exists():
            self.saved = self.directory.with_name("Sara-saved-by-a-test")
            shutil.rmtree(self.saved, ignore_errors=True)
            self.directory.rename(self.saved)

    def tearDown(self) -> None:
        shutil.rmtree(self.directory, ignore_errors=True)
        if self.saved is not None:
            self.saved.rename(self.directory)

    def _leave_a_profile(self) -> None:
        self.directory.mkdir(parents=True, exist_ok=True)
        (self.directory / "colors.cfg").write_text("[lists]\nswatches=Array[Color]([Color(1, 0.4, 0, 1)])\n", encoding="utf-8")
        (self.directory / "brush_presets").mkdir()
        (self.directory / "brush_presets" / "kept.tres").write_text("", encoding="utf-8")
        for cache in self.profile.USER_CACHES:
            (self.directory / cache).mkdir()
            (self.directory / cache / "compiled").write_text("", encoding="utf-8")

    def _prepare(self, keep: bool) -> str:
        said = io.StringIO()
        with redirect_stdout(said):
            self.profile.prepare_user(keep=keep)
        return said.getvalue()

    def test_a_run_does_not_inherit_the_last_one_s_swatches(self) -> None:
        self._leave_a_profile()
        self._prepare(keep=False)
        self.assertFalse((self.directory / "colors.cfg").exists(), "or the next scenario opens on this scenario's chips")
        self.assertFalse((self.directory / "brush_presets").exists(), "and presets are the same trap one folder over")

    def test_the_gpu_caches_stay(self) -> None:
        self._leave_a_profile()
        self._prepare(keep=False)
        for cache in self.profile.USER_CACHES:
            self.assertTrue((self.directory / cache / "compiled").exists(), f"{cache} is compiled work, not painter state")

    def test_keeping_leaves_what_was_there(self) -> None:
        self._leave_a_profile()
        self._prepare(keep=True)
        self.assertTrue((self.directory / "colors.cfg").exists(), "or --keep-settings means nothing here")

    def test_the_directory_is_there_afterwards_either_way(self) -> None:
        for keep in (False, True):
            shutil.rmtree(self.directory, ignore_errors=True)
            with redirect_stdout(io.StringIO()):
                self.assertTrue(self.profile.prepare_user(keep=keep).is_dir())

    def test_the_run_says_what_it_did(self) -> None:
        self.assertIn("cleared", self._prepare(keep=False))
        self.assertIn("kept", self._prepare(keep=True))

    def test_prepare_does_both_halves_and_answers_the_settings_directory(self) -> None:
        self._leave_a_profile()
        with redirect_stdout(io.StringIO()):
            answered = self.profile.prepare(keep=False)
        self.assertEqual(answered, self.profile.settings_dir, "the command line takes the settings half")
        self.assertFalse((self.directory / "colors.cfg").exists(), "and the data half went with it")
        self.assertIn("kept", self._prepare(keep=True))


class ScenarioNamesItsCompositor(unittest.TestCase):
    """`{"renderer": "pixman"}` is the scenario's way of asking.

    It is the harness's entry rather than the app's, so like `{"args": [...]}`
    it has to leave the file before the app is handed it. It exists because the
    two renderers are two different machines and one of them never finishes
    three committed scenarios, so a file that needs the other one says so rather
    than depending on a caller's environment.
    """

    def test_the_entry_asks_for_the_compositor_it_needs(self) -> None:
        _, _, _, renderer = sara_shot.split_harness_steps([{"renderer": "pixman"}, {"wait": 5}])
        self.assertEqual(renderer, "pixman")

    def test_the_entry_does_not_reach_the_app(self) -> None:
        steps, _, _, _ = sara_shot.split_harness_steps([{"renderer": "pixman"}, {"wait": 5}])
        self.assertEqual(steps, [{"wait": 5}], "or the app warns about a step it does not know")

    def test_a_scenario_with_no_entry_asks_for_nothing(self) -> None:
        _, _, _, renderer = sara_shot.split_harness_steps([{"wait": 5}])
        self.assertEqual(renderer, "", "and the environment or the default decides")

    def test_the_scenario_outranks_the_environment(self) -> None:
        """A scenario is a proof another agent repeats, so a pinned variable must
        not be able to put one of the three back into the hang it was filed for."""
        saved = os.environ.get("SARA_WESTON_RENDERER")
        try:
            sara_shot.os.environ["SARA_WESTON_RENDERER"] = "gl"
            command = sara_shot.compositor_command((1920, 1080), "sara-shot-1", "pixman")
        finally:
            if saved is None:
                sara_shot.os.environ.pop("SARA_WESTON_RENDERER", None)
            else:
                sara_shot.os.environ["SARA_WESTON_RENDERER"] = saved
        self.assertIn("--renderer=pixman", command)
        self.assertIn("--backend=headless", command)
        self.assertIn("--socket=sara-shot-1", command)

    def test_the_environment_decides_when_the_scenario_does_not(self) -> None:
        saved = os.environ.get("SARA_WESTON_RENDERER")
        try:
            sara_shot.os.environ["SARA_WESTON_RENDERER"] = "pixman"
            self.assertIn("--renderer=pixman", sara_shot.compositor_command((1920, 1080), "s"))
        finally:
            if saved is None:
                sara_shot.os.environ.pop("SARA_WESTON_RENDERER", None)
            else:
                sara_shot.os.environ["SARA_WESTON_RENDERER"] = saved

    def test_the_default_renderer_is_the_one_the_board_cut_on(self) -> None:
        """The capture harness chooses gl, so a scenario with no opinion and
        no variable around it still gets what every figure in the docs was read
        under."""
        saved = os.environ.pop("SARA_WESTON_RENDERER", None)
        try:
            self.assertIn("--renderer=" + sara_shot.DEFAULT_RENDERER, sara_shot.compositor_command((1920, 1080), "s"))
        finally:
            if saved is not None:
                sara_shot.os.environ["SARA_WESTON_RENDERER"] = saved

    def test_the_three_scenarios_that_ask_are_these(self) -> None:
        """The twin of `test_no_committed_scenario_asks_for_it`, and the same
        reason: a file that starts asking is a claim worth reading. All three
        stop under the default renderer, p1 and p2 once the Preferences window
        rolls up and f20 after `SaCapture: done`, and all three finish under
        pixman. A fourth name here means somebody found another one, and a name
        that leaves means the hang is gone and the entry may go with it."""
        asking = []
        for scenario in sorted((sara_shot.PROJECT_DIR / "scenarios").glob("*.json")):
            _, _, _, renderer = sara_shot.split_harness_steps(sara_shot.read_steps(scenario))
            if renderer:
                asking.append(scenario.name)
        self.assertEqual(
            asking,
            [
                "prefs-minimize-2.json",
                "prefs-minimize.json",
                "the-dockers-menu-follows-the-map.json",
            ],
            "these never finish under the default compositor, and say why",
        )


class ScenarioNamesItsClock(unittest.TestCase):
    """`{"timeout": 300}` is the same rule as the renderer above.

    A scenario that legitimately needs longer than `TIMEOUT_S` says so in its own
    file rather than leaving a caller to remember `SARA_SHOT_TIMEOUT`. The entry
    is the harness's, so it leaves the copy the app is handed, or the app warns
    about a step it does not know.
    """

    def test_the_entry_asks_for_the_clock_it_needs(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            path = Path(raw) / "scenario.json"
            path.write_text('[{"timeout": 300}, {"wait": 5}]', encoding="utf-8")
            self.assertEqual(sara_shot.timeout_for(path), 300)

    def test_the_entry_does_not_reach_the_app(self) -> None:
        steps, _, _, _ = sara_shot.split_harness_steps([{"timeout": 300}, {"wait": 5}])
        self.assertEqual(steps, [{"wait": 5}], "or the app warns about a step it does not know")

    def test_a_scenario_with_no_entry_gets_the_default(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            path = Path(raw) / "scenario.json"
            path.write_text('[{"wait": 5}]', encoding="utf-8")
            self.assertEqual(sara_shot.timeout_for(path), sara_shot.TIMEOUT_S)

    def test_a_file_with_no_scenario_gets_the_default(self) -> None:
        self.assertEqual(sara_shot.timeout_for(None), sara_shot.TIMEOUT_S)

    def test_the_largest_entry_wins(self) -> None:
        """One run has one clock, for the reason `output_size_for` gives about
        windows: a scenario that asks for 300 and then 400 wants both."""
        with tempfile.TemporaryDirectory() as raw:
            path = Path(raw) / "scenario.json"
            path.write_text('[{"timeout": 300}, {"timeout": 400}, {"wait": 5}]', encoding="utf-8")
            self.assertEqual(sara_shot.timeout_for(path), 400)

    def test_the_one_scenario_that_asks_is_this(self) -> None:
        """The twin of `test_the_three_scenarios_that_ask_are_these`, and the same
        reason: a file that starts asking is a claim worth reading. `colour-themes`
        changes the live palette five times, each change re-themes every window, and
        the file needs about 166 seconds on an idle card against a default of 120. A
        second name here means somebody found another one, and a name that leaves
        means the file fits the default again and the entry may go with it. The
        others are scenarios that open a very large document, re-embed every
        docker as a window, sweep many settings pages across several boots, take
        the manual's pictures in one run, save big PNG targets, run long brush
        scribbles, or open a large layered file with the frame trace on. Their
        clocks, 300 to 1500 seconds, are ceilings and have not been tuned to the
        least that fits."""
        asking = []
        for scenario in sorted((sara_shot.PROJECT_DIR / "scenarios").glob("*.json")):
            if sara_shot.timeout_for(scenario) != sara_shot.TIMEOUT_S:
                asking.append(scenario.name)
        kinds = ("airbrush", "basic", "drawn", "eraser", "gradmap", "impasto", "noise", "smudge")
        perf_brushes = [
            f"perf-brushes-{kind}-{size}-{document}.json"
            for kind in kinds
            for size in ("l", "s")
            for document in ("empty", "seasons")
        ]
        scenarios = sara_shot.PROJECT_DIR / "scenarios"
        # A copy leaves some of these scenarios out (they open a file only a
        # maintainer holds), so the list is read against what the folder has.
        expected = sorted(perf_brushes + [
            "a-brush-s-smudge-mixes-the-paint-it-carries-in-the-brush-s-own-blend-mode-frame-time.json",
            "a-group-s-colour-effects-export-as-a-cube-lut-that-davinci-reads.json",
            "a-layer-s-chunk-that-holds-no-paint-at-a-pixel-leaves-the-composite-there-as-it-was.json",
            "a-location-beside-author-picks-the-painter-s-country-for-the-welcome-picture-and-when-ticked-for-an-export-s-metadata.json",
            "a-palette-the-painter-made-is-never-written-over-by-another-palette-s-save.json",
            "a-save-with-an-export-target-never-holds-the-window-while-the-picture-is-written.json",
            "add-noise-at-any-seed-draws-noise-with-no-repeat-every-97-rows-and-film-grain-with-no-step-at-its-cell-edges.json",
            "an-export-of-an-untouched-file-gives-the-same-pixels-however-soon-after-the-load-it-runs-and-twice-in-a-row.json",
            "colour-themes.json",
            "every-settings-page-row-by-row-on-opus-display.json",
            "every-settings-page-row-by-row-on-opus-font-and-slots.json",
            "every-settings-page-row-by-row-on-opus-general-files-performance.json",
            "every-settings-page-row-by-row-on-opus-overflow.json",
            "every-settings-page-row-by-row-on-opus-pages-left-first-try.json",
            "every-settings-page-row-by-row-on-opus-pages-left.json",
            "every-settings-page-row-by-row-on-opus-themes-and-start-again.json",
            "every-settings-page-row-by-row-on-opus-whole.json",
            "every-settings-page-row-by-row-on-opus-workspace-follow-ups.json",
            "every-settings-page-row-by-row-on-opus-workspace-tablet-slots.json",
            "every-settings-page-row-by-row-on-opus.json",
            "every-usual-filter-both-ways.json",
            "exporting-one-layer-and-saving-a-document-keep-the-frames-coming.json",
            "opening-the-seasons-file-holds-no-frame-for-more-than-a-second.json",
            "opening-the-seasons-file-holds-no-frame-over-a-tenth-of-a-second.json",
            "opening-the-seasons-structure-file-holds-no-frame-for-more-than-a-second-again.json",
            "showing-a-group-of-the-seasons-file-holds-no-frame-for-more-than-a-tenth-of-a-second.json",
            "the-cursor-hides-under-a-window-with-subwindows-off.json",
            "the-cursor-is-right-over-a-docker-that-is-a-window-of-its-own.json",
            "the-first-layer-request-after-opening-the-seasons-file-holds-no-frame-over-a-tenth-of-a-second.json",
            "the-interface-s-text-is-as-sharp-at-every-ui-scale-and-text-size-as-at-100.json",
            "the-layers-docker-shows-the-seasons-file-s-756-rows-with-no-frame-over-a-tenth-of-a-second.json",
            "the-manuals-pictures-show-todays-window.json",
        ])
        self.assertEqual(
            asking,
            [name for name in expected if (scenarios / name).exists()],
            "these need longer than the default clock, and say why",
        )




if __name__ == "__main__":
    unittest.main()
