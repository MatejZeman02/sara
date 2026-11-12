"""What `check_shots.py` says about each scenario and variant, with the app stood in for.

    cd sara-godot && PYTHONPATH=scripts python3 -m unittest scripts.test_check_shots

The run itself is the one thing replaced: every case hands `check_set`,
`check_scenario`, `record_scenario` or `main` a shooter that writes pictures
into the folder `sara_shot.py` would have, copied from a committed variant or
edited from one, and a GPU list and a display in place of `vulkaninfo` and
`xrandr`. No Godot, no weston, no GPU, so it sits in phase 4 with the other
Python suites. The last class reads the committed variants themselves, because
a variant with no GPU named is one every machine reads as its own.
"""

from __future__ import annotations

import io
import json
import shutil
import subprocess
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

import check_shots
import shot_diff

PROJECT = Path(__file__).resolve().parent.parent
SET = "the-shot-is-read-against-a-record"
LAPTOP = "NVIDIA GeForce RTX 3070 Laptop GPU"
# The committed variant every case copies its pictures from.
SOURCE = check_shots.RECORDS / SET / "rtx-3070-laptop"
SCREEN = "1920x1080"
VARIANT = check_shots.variant_name(LAPTOP)
RTX_3090 = "NVIDIA GeForce RTX 3090"
SUMMARY = """\
==========
GPU0:
\tapiVersion         = 1.4.328
\tdeviceType         = PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU
\tdeviceName         = Intel(R) UHD Graphics (TGL GT1)
GPU1:
\tdeviceType         = PHYSICAL_DEVICE_TYPE_DISCRETE_GPU
\tdeviceName         = NVIDIA GeForce RTX 3070 Laptop GPU
"""
XRANDR = """\
Screen 0: minimum 16 x 16, current 3200 x 1080, maximum 32767 x 32767
DP-1 connected 1280x1024+1920+0 (normal left inverted right x axis y axis) 380mm x 300mm
HDMI-1 connected primary 1920x1080+0+0 (normal left inverted right x axis y axis) 530mm x 300mm
   1920x1080     60.00*+
DP-2 disconnected (normal left inverted right x axis y axis)
"""
WLR_RANDR = """\
HDMI-A-1 "Dell Inc. DELL U2412M"
  Enabled: yes
  Modes:
    1920x1200 px, 59.950001 Hz (preferred)
    1600x1200 px, 60.000000 Hz (current)
"""


def manifest_for(gpu: str = LAPTOP, resolution: str = SCREEN, **more) -> dict:
    return {"gpu": gpu, "display": {"resolution": resolution, "aspect": check_shots.aspect_of(resolution)}, **more}


def machine(gpus: "list[str] | None" = None, resolution: str = SCREEN, why: str = "") -> check_shots.Machine:
    return check_shots.Machine([LAPTOP] if gpus is None else gpus, why, resolution, why)


class Shooter:
    """Stands in for `sara_shot.py`: writes pictures and a run log, counts calls.

    `move` edits one picture on every run, and `move_on` on that run only, so
    two runs of a recording can be made to disagree.
    """

    def __init__(
        self, source: Path, code: int = 0, device: str = LAPTOP, move: "str | None" = None, move_on: int = 0
    ) -> None:
        self.source = source
        self.code = code
        self.device = device
        self.move = move
        self.move_on = move_on
        self.calls = 0

    def __call__(self, scenario: Path, out: Path) -> "tuple[int, str]":
        self.calls += 1
        out.mkdir(parents=True, exist_ok=True)
        for picture in self.source.glob("*.png"):
            shutil.copy(picture, out / picture.name)
        if self.move is not None and self.move_on in (0, self.calls):
            picture = shot_diff.read_png(out / self.move)
            pixels = bytearray(picture.pixels)
            for x in range(40, 42):
                index = (300 * picture.width + x) * picture.channels
                pixels[index] = (pixels[index] + 128) % 256
            moved = shot_diff.Picture(picture.width, picture.height, picture.channels, pixels)
            shot_diff.write_png(out / self.move, moved)
        (out / "run.log").write_text(f"Vulkan 1.4 - Forward+ - Using Device #0: Vendor - {self.device}\n", encoding="utf-8")
        return self.code, "the last lines sara_shot.py printed"


class Scratch(unittest.TestCase):
    """A temporary copy of one committed variant, so a case may edit it."""

    def setUp(self) -> None:
        self.dir = Path(tempfile.mkdtemp(prefix="check-shots-"))
        self.records = self.dir / "records"
        self.scenario = self.records / SET
        self.folder = self.scenario / VARIANT
        shutil.copytree(SOURCE, self.folder)
        self.manifest(manifest_for(taken="d9492d4c1", repeats=True))
        self.out = self.dir / "out"

    def tearDown(self) -> None:
        shutil.rmtree(self.dir)

    def manifest(self, data, folder: "Path | None" = None) -> None:
        text = data if isinstance(data, str) else json.dumps(data)
        ((folder or self.folder) / check_shots.MANIFEST).write_text(text, encoding="utf-8")

    def other_variant(self, gpu: str, resolution: str = SCREEN) -> Path:
        folder = self.scenario / check_shots.variant_name(gpu)
        shutil.copytree(SOURCE, folder)
        self.manifest(manifest_for(gpu, resolution), folder)
        return folder

    def check(self, shooter: Shooter, gpus: "list[str] | None" = None, why_none: str = "") -> check_shots.Outcome:
        record = check_shots.Record(self.folder)
        return check_shots.check_set(record, self.out / SET, [LAPTOP] if gpus is None else gpus, why_none, shooter)


class RecordTests(Scratch):
    def test_a_committed_manifest_names_its_gpu(self) -> None:
        record = check_shots.Record(SOURCE)
        self.assertEqual(record.problem, "")
        self.assertEqual(record.gpu, LAPTOP)
        self.assertEqual(record.name, f"{SET}/rtx-3070-laptop")
        self.assertTrue(record.repeats)

    def test_a_variant_with_no_manifest_names_no_gpu(self) -> None:
        (self.folder / check_shots.MANIFEST).unlink()
        self.assertIn("names no GPU", check_shots.Record(self.folder).problem)

    def test_a_manifest_that_is_not_json_says_so(self) -> None:
        self.manifest("{gpu")
        self.assertIn("is not JSON", check_shots.Record(self.folder).problem)

    def test_an_empty_gpu_is_no_gpu(self) -> None:
        self.manifest({"gpu": "  "})
        self.assertIn("names no GPU", check_shots.Record(self.folder).problem)

    def test_a_manifest_without_a_display_is_whole(self) -> None:
        self.manifest({"gpu": LAPTOP})
        record = check_shots.Record(self.folder)
        self.assertEqual((record.problem, record.resolution), ("", check_shots.UNKNOWN))
        self.assertTrue(record.matches(machine()))

    def test_a_set_that_does_not_repeat_says_why(self) -> None:
        self.manifest(manifest_for(repeats=False))
        self.assertIn("not why", check_shots.Record(self.folder).problem)
        self.manifest(manifest_for(repeats=False, why="a clock in the frame"))
        record = check_shots.Record(self.folder)
        self.assertEqual((record.problem, record.repeats, record.why), ("", False, "a clock in the frame"))

    def test_a_variant_matches_its_gpu_whatever_the_display(self) -> None:
        record = check_shots.Record(self.folder)
        self.assertTrue(record.matches(machine()))
        self.assertTrue(record.matches(machine(resolution="1280x1024")))
        self.assertTrue(record.matches(machine(resolution="")))
        self.assertFalse(record.matches(machine(gpus=[RTX_3090])))


class CheckSetTests(Scratch):
    def test_the_same_pictures_pass(self) -> None:
        shooter = Shooter(SOURCE)
        outcome = self.check(shooter)
        self.assertEqual((outcome.state, shooter.calls), ("ok", 1))
        self.assertIn("3 shot(s) match", outcome.lines[0])

    def test_two_moved_texels_fail_and_name_the_set_and_the_picture(self) -> None:
        outcome = self.check(Shooter(SOURCE, move="2-one-stroke.png"))
        self.assertEqual(outcome.state, "FAIL")
        self.assertIn(f"{SET}/{VARIANT}", outcome.lines[0])
        self.assertIn("1 of 3 shot(s)", outcome.lines[0])
        said = "\n".join(outcome.lines)
        self.assertIn("2-one-stroke.png  2 texel(s)", said)
        diff = self.out / SET / ("2-one-stroke" + shot_diff.DIFF_SUFFIX)
        self.assertIn(str(diff), said)
        self.assertTrue(diff.is_file())

    def test_the_engine_on_another_device_is_a_skip(self) -> None:
        outcome = self.check(Shooter(SOURCE, device="llvmpipe (LLVM 22.1.8, 256 bits)"))
        self.assertEqual(outcome.state, "skip")
        self.assertIn("the engine drew with llvmpipe", outcome.lines[0])

    def test_a_set_that_does_not_repeat_is_skipped_by_name(self) -> None:
        self.manifest(manifest_for(repeats=False, why="a clock in the frame"))
        shooter = Shooter(SOURCE)
        outcome = self.check(shooter)
        self.assertEqual((outcome.state, shooter.calls), ("skip", 0))
        self.assertIn(f"{SET}/{VARIANT}  does not repeat: a clock in the frame", outcome.lines[0])

    def test_a_run_that_failed_fails_with_its_log(self) -> None:
        outcome = self.check(Shooter(SOURCE, code=3))
        self.assertEqual(outcome.state, "FAIL")
        self.assertIn("sara_shot.py exited 3", outcome.lines[0])
        self.assertIn("run.log", outcome.lines[0])

    def test_a_run_that_hung_after_finishing_is_still_read(self) -> None:
        outcome = self.check(Shooter(SOURCE, code=check_shots.EXIT_FINISHED_BUT_HUNG))
        self.assertEqual(outcome.state, "ok")
        self.assertIn("the engine hung on exit", outcome.lines[0])
        moved = Shooter(SOURCE, code=check_shots.EXIT_FINISHED_BUT_HUNG, move="2-one-stroke.png")
        self.assertEqual(self.check(moved).state, "FAIL")

    def test_a_missing_shot_fails(self) -> None:
        empty = self.dir / "empty"
        empty.mkdir()
        outcome = self.check(Shooter(empty))
        self.assertEqual(outcome.state, "FAIL")
        self.assertIn("the shot folder", outcome.lines[0])

    def test_a_manifest_problem_fails_without_a_run(self) -> None:
        (self.folder / check_shots.MANIFEST).unlink()
        shooter = Shooter(SOURCE)
        self.assertEqual((self.check(shooter).state, shooter.calls), ("FAIL", 0))


class CheckScenarioTests(Scratch):
    def states(self, shooter: Shooter, here: check_shots.Machine) -> "list[tuple[str, str]]":
        return [(o.state, o.name) for o in check_shots.check_scenario(self.scenario, self.out, here, shooter)]

    def test_the_matching_variant_runs_and_the_others_get_a_skip_line(self) -> None:
        self.other_variant(RTX_3090, "1280x1024")
        self.other_variant("AMD Radeon RX 7600")
        shooter = Shooter(SOURCE)
        outcomes = check_shots.check_scenario(self.scenario, self.out, machine(), shooter)
        self.assertEqual(shooter.calls, 1)
        self.assertEqual([o.state for o in outcomes], ["ok", "other", "other"])
        self.assertIn(f"{SET}/{VARIANT}", outcomes[0].lines[0])
        self.assertTrue(outcomes[1].lines[0].startswith("  skip    "))
        self.assertIn(f"{SET}/rtx-3090  for {RTX_3090}", "\n".join(o.lines[0] for o in outcomes[1:]))

    def test_another_display_still_runs_the_gpus_variant(self) -> None:
        for resolution in ("1280x1024", ""):
            with self.subTest(resolution):
                shooter = Shooter(SOURCE)
                outcomes = check_shots.check_scenario(self.scenario, self.out, machine(resolution=resolution), shooter)
                self.assertEqual(([o.state for o in outcomes], shooter.calls), (["ok"], 1))

    def test_another_gpu_is_a_request_without_a_run_and_the_software_card_is_not_offered(self) -> None:
        here = machine(gpus=[RTX_3090, "llvmpipe (LLVM 22.1.8, 256 bits)"])
        shooter = Shooter(SOURCE)
        outcomes = check_shots.check_scenario(self.scenario, self.out, here, shooter)
        self.assertEqual(shooter.calls, 0)
        self.assertEqual([o.state for o in outcomes], ["REQUEST", "other"])
        said = outcomes[0].lines[0]
        self.assertIn(f"REQUEST {SET}  no pictures for {RTX_3090}, record them with", said)
        self.assertIn(f"python scripts/check_shots.py --record {SET}", said)
        self.assertNotIn("llvmpipe", said)

    def test_a_machine_that_names_no_gpu_skips_and_says_why(self) -> None:
        shooter = Shooter(SOURCE)
        here = machine(gpus=[], why="vulkaninfo is not installed")
        outcomes = check_shots.check_scenario(self.scenario, self.out, here, shooter)
        self.assertEqual(([o.state for o in outcomes], shooter.calls), (["skip"], 0))
        self.assertIn("vulkaninfo is not installed", outcomes[0].lines[0])

    def test_pictures_left_in_the_scenario_folder_fail(self) -> None:
        shutil.rmtree(self.folder)
        shutil.copytree(SOURCE, self.scenario, dirs_exist_ok=True)
        self.assertEqual(self.states(Shooter(SOURCE), machine()), [("FAIL", SET)])

    def test_two_variants_for_one_machine_fail(self) -> None:
        twin = self.scenario / "a-twin"
        shutil.copytree(self.folder, twin)
        self.assertEqual(self.states(Shooter(SOURCE), machine()), [("FAIL", SET)])

    def test_a_broken_variant_fails_beside_the_matching_one(self) -> None:
        broken = self.other_variant("AMD Radeon RX 7600")
        (broken / check_shots.MANIFEST).unlink()
        self.assertEqual(
            sorted(self.states(Shooter(SOURCE), machine())),
            [("FAIL", f"{SET}/{broken.name}"), ("ok", f"{SET}/{VARIANT}")],
        )


class RecordScenarioTests(Scratch):
    def record(self, shooter: Shooter, here: "check_shots.Machine | None" = None) -> check_shots.Outcome:
        return check_shots.record_scenario(SET, self.records, self.out, here or machine(), shooter, lambda: "abc123")

    def test_two_runs_that_agree_become_this_machines_variant(self) -> None:
        shooter = Shooter(SOURCE, device=RTX_3090)
        outcome = self.record(shooter, machine(gpus=[RTX_3090], resolution="1280x1024"))
        self.assertEqual((outcome.state, shooter.calls), ("ok", 2))
        folder = self.scenario / "rtx-3090"
        self.assertIn(f"{SET}/rtx-3090  recorded 3 shot(s)", outcome.lines[0])
        self.assertEqual(check_shots.pictures_in(folder), check_shots.pictures_in(SOURCE))
        written = json.loads((folder / check_shots.MANIFEST).read_text(encoding="utf-8"))
        self.assertEqual(
            written,
            {
                "gpu": RTX_3090,
                "display": {"resolution": "1280x1024", "aspect": "5:4"},
                "taken": "abc123",
                "repeats": True,
            },
        )
        self.assertTrue(check_shots.Record(folder).matches(machine([RTX_3090], "1280x1024")))

    def test_a_display_that_cannot_be_found_is_left_out_of_the_record(self) -> None:
        shooter = Shooter(SOURCE, device=RTX_3090)
        outcome = self.record(shooter, machine(gpus=[RTX_3090], resolution=""))
        self.assertEqual(outcome.state, "ok")
        written = json.loads((self.scenario / "rtx-3090" / check_shots.MANIFEST).read_text(encoding="utf-8"))
        self.assertNotIn("display", written)

    def test_two_runs_that_disagree_are_refused_and_nothing_is_written(self) -> None:
        before = (self.folder / "2-one-stroke.png").read_bytes()
        shooter = Shooter(SOURCE, move="2-one-stroke.png", move_on=2)
        outcome = self.record(shooter)
        self.assertEqual((outcome.state, shooter.calls), ("FAIL", 2))
        self.assertIn("refused, the two runs disagree on 1 of 3 shot(s)", outcome.lines[0])
        self.assertIn("does not repeat must not own a record", outcome.lines[0])
        self.assertEqual((self.folder / "2-one-stroke.png").read_bytes(), before)

    def test_a_retake_replaces_the_matching_variant_in_place(self) -> None:
        outcome = self.record(Shooter(SOURCE, move="2-one-stroke.png"))
        self.assertEqual(outcome.state, "ok")
        self.assertEqual([path.name for path in self.scenario.iterdir()], [VARIANT])
        written = json.loads((self.folder / check_shots.MANIFEST).read_text(encoding="utf-8"))
        self.assertEqual(written["taken"], "abc123")

    def test_a_shot_the_variants_leave_out_stays_out(self) -> None:
        self.manifest(manifest_for(leaves_out=["3-the-same-frame-again.png"]))
        shooter = Shooter(SOURCE, move="3-the-same-frame-again.png", move_on=2, device=RTX_3090)
        outcome = self.record(shooter, machine(gpus=[RTX_3090]))
        self.assertEqual(outcome.state, "ok")
        folder = self.scenario / "rtx-3090"
        self.assertEqual(check_shots.pictures_in(folder), ["1-the-white-canvas.png", "2-one-stroke.png"])
        self.assertEqual(check_shots.Record(folder).leaves_out, ["3-the-same-frame-again.png"])

    def test_a_failed_run_is_refused(self) -> None:
        self.assertEqual(self.record(Shooter(SOURCE, code=3)).state, "FAIL")


class MainTests(Scratch):
    def run_main(
        self, argv: "list[str]", shooter: Shooter, gpus=([LAPTOP], ""), display=(SCREEN, "")
    ) -> "tuple[int, str]":
        said = io.StringIO()
        with redirect_stdout(said), redirect_stderr(said):
            code = check_shots.main(
                [*argv, "--records", str(self.records), "--out", str(self.out)],
                shooter,
                lambda: gpus,
                lambda: display,
                lambda: "abc123",
            )
        return code, said.getvalue()

    def test_a_passing_set_exits_zero_with_one_line_and_a_count(self) -> None:
        code, said = self.run_main([], Shooter(SOURCE))
        self.assertEqual(code, check_shots.EXIT_PASSED)
        self.assertIn(f"  ok      {SET}/{VARIANT}", said)
        self.assertIn("1 scenario(s): 1 matched, 0 skipped, 0 requested, 0 failed", said)

    def test_a_failing_set_exits_one(self) -> None:
        code, said = self.run_main([SET], Shooter(SOURCE, move="1-the-white-canvas.png"))
        self.assertEqual(code, check_shots.EXIT_FAILED)
        self.assertIn(f"  FAIL    {SET}/{VARIANT}", said)

    def test_a_skipped_set_exits_zero(self) -> None:
        code, said = self.run_main([], Shooter(SOURCE), ([], "no GPU here"))
        self.assertEqual(code, check_shots.EXIT_PASSED)
        self.assertIn("0 matched, 1 skipped, 0 requested, 0 failed", said)

    def test_a_request_exits_zero_and_is_counted(self) -> None:
        code, said = self.run_main([], Shooter(SOURCE), gpus=([RTX_3090], ""))
        self.assertEqual(code, check_shots.EXIT_PASSED)
        self.assertIn(f"REQUEST {SET}", said)
        self.assertIn("0 matched, 0 skipped, 1 requested, 0 failed, 1 variant(s) of other machines not read", said)

    def test_an_unknown_set_is_refused(self) -> None:
        code, said = self.run_main(["no-such-set"], Shooter(SOURCE))
        self.assertEqual(code, check_shots.EXIT_UNKNOWN_SET)
        self.assertIn("no record set called no-such-set", said)

    def test_record_with_no_names_takes_only_what_this_machine_lacks(self) -> None:
        shooter = Shooter(SOURCE)
        code, said = self.run_main(["--record"], shooter)
        self.assertEqual((code, shooter.calls), (check_shots.EXIT_PASSED, 0))
        self.assertIn("0 scenario(s) to record", said)
        shooter = Shooter(SOURCE, device=RTX_3090)
        code, said = self.run_main(["--record"], shooter, gpus=([RTX_3090], ""))
        self.assertEqual((code, shooter.calls), (check_shots.EXIT_PASSED, 2))
        self.assertIn("1 recorded, 0 refused", said)
        self.assertTrue((self.scenario / "rtx-3090").is_dir())

    def test_record_all_retakes_what_already_matches(self) -> None:
        shooter = Shooter(SOURCE)
        code, said = self.run_main(["--record", "--all"], shooter)
        self.assertEqual((code, shooter.calls), (check_shots.EXIT_PASSED, 2))

    def test_a_refused_recording_exits_one(self) -> None:
        code, said = self.run_main(["--record", SET], Shooter(SOURCE, move="2-one-stroke.png", move_on=1))
        self.assertEqual(code, check_shots.EXIT_FAILED)
        self.assertIn("0 recorded, 1 refused", said)

    def test_record_needs_a_gpu_it_can_name(self) -> None:
        code, said = self.run_main(["--record", SET], Shooter(SOURCE), gpus=([], "vulkaninfo is not installed"))
        self.assertEqual(code, check_shots.EXIT_FAILED)
        self.assertIn("nothing can be recorded here, vulkaninfo is not installed", said)

    def test_record_refuses_a_scenario_that_does_not_exist(self) -> None:
        code, said = self.run_main(["--record", "no-such-scenario"], Shooter(SOURCE))
        self.assertEqual(code, check_shots.EXIT_UNKNOWN_SET)


class MachineTests(unittest.TestCase):
    def test_vulkaninfo_names_every_device(self) -> None:
        def run(*_args, **_kwargs):
            return subprocess.CompletedProcess([], 0, SUMMARY, "")

        self.assertEqual(check_shots.machine_gpus(run), (["Intel(R) UHD Graphics (TGL GT1)", LAPTOP], ""))

    def test_no_vulkaninfo_is_a_reason_and_no_names(self) -> None:
        def run(*_args, **_kwargs):
            raise FileNotFoundError("vulkaninfo")

        names, why = check_shots.machine_gpus(run)
        self.assertEqual(names, [])
        self.assertIn("not installed", why)

    def test_a_silent_vulkaninfo_names_nothing(self) -> None:
        def run(*_args, **_kwargs):
            return subprocess.CompletedProcess([], 1, "", "no driver")

        self.assertEqual(check_shots.machine_gpus(run), ([], "vulkaninfo named no device (exit 1)"))

    def test_the_device_line_gives_the_name_after_the_vendor(self) -> None:
        log = "Godot Engine\nVulkan 1.4.351 - Forward+ - Using Device #0: NVIDIA - NVIDIA GeForce RTX 3070 Laptop GPU\n"
        self.assertEqual(check_shots.device_in_log(log), LAPTOP)
        self.assertEqual(check_shots.device_in_log("nothing about a device"), "")


    def test_xrandr_gives_the_primary_output(self) -> None:
        def run(command, **_kwargs):
            return subprocess.CompletedProcess(command, 0, XRANDR, "")

        self.assertEqual(check_shots.machine_display(run), ("1920x1080", ""))

    def test_wlr_randr_is_asked_when_xrandr_is_missing(self) -> None:
        def run(command, **_kwargs):
            if command[0] == "xrandr":
                raise FileNotFoundError("xrandr")
            return subprocess.CompletedProcess(command, 0, WLR_RANDR, "")

        self.assertEqual(check_shots.machine_display(run), ("1600x1200", ""))

    def test_the_kernel_is_read_last_and_a_failure_says_why(self) -> None:
        def run(command, **_kwargs):
            raise FileNotFoundError(command[0])

        with tempfile.TemporaryDirectory() as drm:
            root = Path(drm)
            connectors = (("card1-DP-1", "disconnected", ""), ("card1-HDMI-A-1", "connected", "1280x1024\n1024x768\n"))
            for name, status, modes in connectors:
                (root / name).mkdir()
                (root / name / "status").write_text(status + "\n", encoding="utf-8")
                (root / name / "modes").write_text(modes, encoding="utf-8")
            self.assertEqual(check_shots.machine_display(run, root), ("1280x1024", ""))
            (root / "card1-HDMI-A-1" / "status").write_text("disconnected\n", encoding="utf-8")
            resolution, why = check_shots.machine_display(run, root)
        self.assertEqual(resolution, "")
        self.assertIn("the display could not be found: xrandr is not installed, wlr-randr is not installed", why)

    def test_an_aspect_is_named_as_monitors_are_sold(self) -> None:
        named = (("1280x1024", "5:4"), ("1920x1080", "16:9"), ("1366x768", "16:9"), ("1920x1200", "16:10"))
        for resolution, aspect in named:
            with self.subTest(resolution):
                self.assertEqual(check_shots.aspect_of(resolution), aspect)
        self.assertEqual(check_shots.aspect_of("unknown"), "unknown")

    def test_a_variant_is_named_after_the_card(self) -> None:
        self.assertEqual(check_shots.variant_name(RTX_3090), "rtx-3090")
        self.assertEqual(check_shots.variant_name(LAPTOP), "rtx-3070-laptop")


class CommittedSetTests(unittest.TestCase):
    """Every folder under `tests/shots/` is a set the gate line can read."""

    def test_every_variant_names_its_gpu_and_has_a_scenario(self) -> None:
        folders = [path for path in check_shots.RECORDS.iterdir() if path.is_dir()]
        self.assertGreaterEqual(len(folders), 11)
        for folder in folders:
            with self.subTest(folder.name):
                self.assertTrue((check_shots.SCENARIOS / f"{folder.name}.json").is_file())
                self.assertEqual(check_shots.pictures_in(folder), [], "pictures stand outside a variant")
                variants = check_shots.variants_of(folder)
                self.assertTrue(variants)
                for record in variants:
                    self.assertEqual(record.problem, "", record.name)
                    self.assertEqual(record.variant, check_shots.variant_name(record.gpu))

    def test_the_gate_lists_carry_the_line_and_this_suite(self) -> None:
        if not (PROJECT.parent / "docs").is_dir():
            self.skipTest("a public copy has no docs folder, and its AGENTS.md is not the gate page")
        for page in (PROJECT.parent / "AGENTS.md", PROJECT.parent / "docs" / "guides" / "TESTING.md"):
            with self.subTest(page.name):
                if not page.exists():
                    self.skipTest("a copy of the source carries no %s" % page.name)
                text = page.read_text(encoding="utf-8")
                self.assertTrue("python scripts/check_shots.py" in text, f"{page} has no check_shots.py line")
                self.assertTrue("scripts.test_check_shots" in text, f"{page} does not run this suite")


if __name__ == "__main__":
    unittest.main()
