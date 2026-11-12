#!/usr/bin/env python3
"""Take every scenario that has record pictures again, and read it against them.

    python3 scripts/check_shots.py                 # every scenario under tests/shots
    python3 scripts/check_shots.py adjust-inside-a-selection the-chord-and-the-leave
    python3 scripts/check_shots.py --record        # record what this machine lacks
    python3 scripts/check_shots.py --record adjust-inside-a-selection
    python3 scripts/check_shots.py --record --all  # retake every one for this machine

`shot_diff.py` reads a fresh shot against its record, and without a gate line
that takes one a change moving a docker by two pixels passes every check. This
is that line: for each scenario folder under
`tests/shots/` it runs `sara_shot.py` on the scenario of the same name, hands
every pair to `shot_diff.check`, and prints one line a scenario, with the path
of each difference picture when one fails.

**A scenario's pictures are kept once per GPU**, in a variant folder,
`tests/shots/<scenario>/<variant>/` named after the GPU, whose `record.json`
names it. Another GPU draws a text edge a level differently, and a tolerance
wide enough for every card lets through the two-pixel change the check exists
for. So a scenario runs only against the variant whose
GPU this machine has, and every other variant gets a short skip line. The
display is not part of the key: `sara_shot.py` draws offscreen in a headless
weston at the scenario's own size, with the interface scale and the layout
pinned, so the monitor never changes a picture. `record.json` still notes the
display a variant was taken beside, for the reader. The machine is asked
first, through `vulkaninfo`, so a machine that cannot pass never spends half a
minute a set finding out, and the run log is asked afterwards, because the
device Godot chose is the one that drew the frame.

**A scenario with no variant for this machine's GPU is a request**, a
`REQUEST` line naming the command that records one, and not a failure: Windows
and the workflow can never record, and a missing picture is work for a person
rather than a fault in the tree. A machine whose GPU cannot be named skips
instead, saying why, since a request it could never fulfil helps nobody.

**`--record` takes a variant for this machine.** It runs the scenario twice,
reads the two runs against each other first, and copies one in only when they
agree, because a scenario that does not repeat must never own a record. A shot
the scenario's variants list under `leaves_out` is left out of the new one too.

**A scenario that does not repeat is skipped by name**, with `"repeats": false`
and a `"why"` in its `record.json`, and never by a wider tolerance.

Exit 0 when every scenario passed, was skipped or was requested, 1 when one
failed or a recording was refused, 2 when a scenario named on the command line
does not exist.
"""

from __future__ import annotations

import argparse
import json
import math
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

import shot_diff
from sara_shot import EXIT_FINISHED_BUT_HUNG
from shot_profile import ShotProfile

PROJECT_DIR = Path(__file__).resolve().parent.parent
RECORDS = PROJECT_DIR / "tests" / "shots"
SCENARIOS = PROJECT_DIR / "scenarios"
# Under `scratch/`, which git ignores, and not under `/tmp`, so the pictures a
# failing run leaves are where the next session of the same clone finds them.
DEFAULT_OUT = PROJECT_DIR / "scratch" / "shot-gate"
SARA_SHOT = Path(__file__).resolve().parent / "sara_shot.py"
DRM = Path("/sys/class/drm")

# The file in each variant folder that says where the pictures came from.
MANIFEST = "record.json"
# What a display or an aspect is called when it could not be read.
UNKNOWN = "unknown"

# What the engine prints once it has picked a Vulkan device, as
# `Using Device #0: NVIDIA - NVIDIA GeForce RTX 3070 Laptop GPU`. The name is
# the part after the vendor, and it is the same string `vulkaninfo` reports.
DEVICE_LINE = re.compile(r"Using Device #\d+: .*? - (.+?)\s*$", re.MULTILINE)
VULKAN_NAME = re.compile(r"^\s*deviceName\s*=\s*(.+?)\s*$", re.MULTILINE)
XRANDR_OUTPUT = re.compile(r"^\S+ connected (primary )?(\d+)x(\d+)\+", re.MULTILINE)
WLR_CURRENT = re.compile(r"^\s+(\d+)x(\d+) px\b.*\bcurrent\b", re.MULTILINE)
RESOLUTION = re.compile(r"^(\d+)x(\d+)$")
# The software rasteriser `vulkaninfo` lists beside a real card. It is never
# the machine a record names, so a request does not offer it.
SOFTWARE = ("llvmpipe", "lavapipe", "SwiftShader")
# Ratios a monitor is sold by. A resolution near one is named by it, since
# 1366 by 768 reduces to 683:384 and 2560 by 1080 to 64:27.
COMMON_ASPECTS = ((16, 9), (16, 10), (4, 3), (5, 4), (3, 2), (21, 9), (32, 9))
# Words every NVIDIA name carries, left out of a variant folder's name.
NAME_NOISE = {"nvidia", "geforce", "gpu", "r", "tm"}

EXIT_PASSED = 0
EXIT_FAILED = 1
EXIT_UNKNOWN_SET = 2


def aspect_of(resolution: str) -> str:
    """The aspect ratio of a `1280x1024` resolution, as `5:4`, or `unknown`."""
    found = RESOLUTION.match(resolution)
    if not found:
        return UNKNOWN
    width, height = int(found.group(1)), int(found.group(2))
    if not width or not height:
        return UNKNOWN
    ratio = width / height
    near = min(COMMON_ASPECTS, key=lambda pair: abs(pair[0] / pair[1] - ratio))
    if abs(near[0] / near[1] - ratio) / ratio < 0.03:
        return f"{near[0]}:{near[1]}"
    divisor = math.gcd(width, height)
    return f"{width // divisor}:{height // divisor}"


def variant_name(gpu: str) -> str:
    """The folder a GPU's pictures live in, as `rtx-3090`."""
    words = [word for word in re.findall(r"[a-z0-9]+", gpu.lower()) if word not in NAME_NOISE]
    return "-".join(words) or "gpu"


class Machine:
    """This machine as a variant is matched against: its GPUs, and its display for the record."""

    def __init__(self, gpus: "list[str]", why_no_gpu: str, resolution: str, why_no_display: str) -> None:
        self.gpus = gpus
        self.why_no_gpu = why_no_gpu
        self.resolution = resolution
        self.why_no_display = why_no_display

    def unnamed(self) -> str:
        """Why this machine cannot be matched, empty when it can."""
        if not self.gpus:
            return self.why_no_gpu or "this machine names no GPU"
        return ""

    def gpu_label(self) -> str:
        """The GPU a request names: the real cards, without the software one."""
        real = [gpu for gpu in self.gpus if not any(word in gpu for word in SOFTWARE)]
        return " or ".join(real or self.gpus)



class Record:
    """What a variant folder's `record.json` says, read and checked once.

    `problem` is the reason the manifest cannot be used, empty when it can. A
    variant with no manifest fails rather than runs, because a variant that
    names no GPU is one every machine would read as its own. The display is
    read for the reader only and may be missing.
    """

    def __init__(self, folder: Path) -> None:
        self.folder = folder
        self.scenario = folder.parent.name
        self.variant = folder.name
        self.name = f"{self.scenario}/{self.variant}"
        self.gpu = ""
        self.resolution = ""
        self.repeats = True
        self.why = ""
        self.leaves_out: "list[str]" = []
        self.problem = ""
        path = folder / MANIFEST
        if not path.is_file():
            self.problem = f"has no {MANIFEST}, so it names no GPU"
            return
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as error:
            self.problem = f"{MANIFEST} is not JSON: {error}"
            return
        if not isinstance(data, dict) or not isinstance(data.get("gpu"), str) or not data["gpu"].strip():
            self.problem = f'{MANIFEST} names no GPU, it wants "gpu": "<the device name>"'
            return
        self.gpu = data["gpu"].strip()
        display = data.get("display")
        resolution = display.get("resolution") if isinstance(display, dict) else None
        self.resolution = resolution if isinstance(resolution, str) and resolution else UNKNOWN
        self.repeats = data.get("repeats", True) is not False
        self.why = str(data.get("why", "")).strip()
        self.leaves_out = [str(name) for name in data.get("leaves_out", [])]
        if not self.repeats and not self.why:
            self.problem = f'{MANIFEST} says the scenario does not repeat and not why, it wants "why"'

    def matches(self, machine: Machine) -> bool:
        """Whether this machine has the GPU the pictures were taken on."""
        return self.gpu in machine.gpus


class Outcome:
    """One line's answer: `state` is ok, skip, other, REQUEST or FAIL, `lines` what to print.

    `other` is a variant of another machine, printed as a short skip line and
    counted apart from the scenarios.
    """

    def __init__(self, state: str, name: str, said: str, detail: "list[str] | None" = None) -> None:
        self.state = state
        self.name = name
        label = "skip" if state == "other" else state
        self.lines = [f"  {label:7s} {name}  {said}"] + [f"          {line}" for line in detail or []]


def machine_gpus(run=subprocess.run) -> "tuple[list[str], str]":
    """The Vulkan device names this machine has, and why the list is empty if it is."""
    try:
        done = run(["vulkaninfo", "--summary"], capture_output=True, encoding="utf-8", timeout=60, check=False)
    except FileNotFoundError:
        return [], "vulkaninfo is not installed, so this machine's GPU cannot be named"
    except (OSError, subprocess.TimeoutExpired) as error:
        return [], f"vulkaninfo did not answer: {error}"
    names = VULKAN_NAME.findall(done.stdout or "")
    if not names:
        return [], f"vulkaninfo named no device (exit {done.returncode})"
    return names, ""


def _ask(run, command: "list[str]") -> "tuple[str, str]":
    """What *command* printed, or empty and why."""
    try:
        done = run(command, capture_output=True, encoding="utf-8", timeout=20, check=False)
    except FileNotFoundError:
        return "", f"{command[0]} is not installed"
    except (OSError, subprocess.TimeoutExpired) as error:
        return "", f"{command[0]} did not answer: {error}"
    if done.returncode != 0:
        return "", f"{command[0]} exited {done.returncode}"
    return done.stdout or "", ""


def machine_display(run=subprocess.run, drm: Path = DRM) -> "tuple[str, str]":
    """The primary display's resolution as `1280x1024`, and why it is empty if it is.

    A recording notes it in `record.json` for the reader, and nothing matches
    on it, since the shots are drawn offscreen at the scenario's own size.

    `xrandr` is asked first, for the output it calls primary, then any connected
    one. Under Wayland it answers through Xwayland, which reports the monitor's
    current mode. `wlr-randr` is next, for a wlroots compositor with no
    Xwayland, and last the kernel's own list of modes for the first connected
    connector, whose first line is the monitor's preferred mode.
    """
    why = []
    said, failed = _ask(run, ["xrandr", "--query"])
    found = XRANDR_OUTPUT.findall(said)
    if found:
        primary = [entry for entry in found if entry[0]] or found
        return f"{primary[0][1]}x{primary[0][2]}", ""
    why.append(failed or "xrandr named no connected output")
    said, failed = _ask(run, ["wlr-randr"])
    current = WLR_CURRENT.search(said)
    if current:
        return f"{current.group(1)}x{current.group(2)}", ""
    why.append(failed or "wlr-randr named no current mode")
    try:
        connectors = sorted(drm.glob("card*-*"))
    except OSError:
        connectors = []
    for connector in connectors:
        try:
            if (connector / "status").read_text(encoding="utf-8").strip() != "connected":
                continue
            first = (connector / "modes").read_text(encoding="utf-8").split()
        except OSError:
            continue
        if first and RESOLUTION.match(first[0]):
            return first[0], ""
    why.append(f"no connected connector with a mode under {drm}")
    return "", "the display could not be found: " + ", ".join(why)


def device_in_log(text: str) -> str:
    """The device the engine drew with, from its run log, or empty when it never said."""
    found = DEVICE_LINE.findall(text)
    return found[-1] if found else ""


def shoot(scenario: Path, out: Path) -> "tuple[int, str]":
    """Run `sara_shot.py` and return its exit code and the tail of what it printed."""
    # A profile of its own for the run, so a gate run in two streams reads each
    # scenario from a profile that no other scenario is writing (`ShotProfile.lease`).
    with ShotProfile(PROJECT_DIR).lease():
        done = subprocess.run(
            [sys.executable, str(SARA_SHOT), "--scenario", str(scenario), "--out", str(out)],
            capture_output=True,
            encoding="utf-8",
            check=False,
        )
    said = (done.stdout or "") + (done.stderr or "")
    return done.returncode, "\n".join(said.strip().splitlines()[-6:])


def head_commit() -> str:
    """The checkout's commit, which a new variant's `taken` names."""
    done = subprocess.run(
        ["git", "-C", str(PROJECT_DIR), "rev-parse", "--short=9", "HEAD"],
        capture_output=True,
        encoding="utf-8",
        check=False,
    )
    return done.stdout.strip() or UNKNOWN


def pictures_in(folder: Path) -> "list[str]":
    """The shots a folder holds, by name, without the difference pictures."""
    return sorted(path.name for path in folder.glob("*.png") if not path.name.endswith(shot_diff.DIFF_SUFFIX))


def drawn_with(out: Path) -> str:
    log = out / "run.log"
    return device_in_log(log.read_text(errors="replace", encoding="utf-8")) if log.is_file() else ""


def check_set(record: Record, out: Path, gpus: "list[str]", why_none: str, shooter=shoot) -> Outcome:
    """Everything one variant gets: the refusals, the run and the comparison."""
    if record.problem:
        return Outcome("FAIL", record.name, record.problem)
    if not record.repeats:
        return Outcome("skip", record.name, f"does not repeat: {record.why}")
    if record.gpu not in gpus:
        has = why_none or "this machine has " + ", ".join(gpus)
        return Outcome("skip", record.name, f"recorded on {record.gpu}, and {has}")
    scenario = SCENARIOS / f"{record.scenario}.json"
    if not scenario.is_file():
        return Outcome("FAIL", record.name, f"has no scenario at {scenario.relative_to(PROJECT_DIR)}")
    started = time.monotonic()
    code, tail = shooter(scenario, out)
    seconds = time.monotonic() - started
    # A run that finished and then hung on exit left every picture on disk, and
    # the hang is the engine's Wayland teardown and not the app, so the set is
    # read and the line says it happened. Failing it made this line red twice in
    # eleven sets on its first gate after a merge, with nothing wrong on screen.
    hung = code == EXIT_FINISHED_BUT_HUNG
    if code != 0 and not hung:
        said = f"sara_shot.py exited {code}, the run log is {out / 'run.log'}"
        return Outcome("FAIL", record.name, said, tail.splitlines())
    drew = drawn_with(out)
    if drew and drew != record.gpu:
        return Outcome("skip", record.name, f"recorded on {record.gpu}, and the engine drew with {drew}")
    try:
        found = shot_diff.pairs(out, record.folder)
    except shot_diff.ShotDiffError as refusal:
        return Outcome("FAIL", record.name, str(refusal))
    failed, detail = compare(found)
    if failed:
        return Outcome("FAIL", record.name, f"{failed} of {len(found)} shot(s) over the tolerance", detail)
    after = ", the engine hung on exit after the last step" if hung else ""
    return Outcome("ok", record.name, f"{len(found)} shot(s) match, {seconds:.0f} s{after}")


def compare(found: "list[tuple[Path, Path]]") -> "tuple[int, list[str]]":
    """How many pairs differ past the tolerance, and the lines that say where."""
    failed = 0
    detail = []
    for taken, kept in found:
        try:
            passed, line = shot_diff.check(taken, kept, shot_diff.TOLERANCE, 0)
        except shot_diff.ShotDiffError as refusal:
            passed, line = False, f"  FAIL  {taken.name}  {refusal}"
        if not passed:
            failed += 1
            detail.extend(part.strip() for part in line.splitlines())
    return failed, detail


def variants_of(folder: Path) -> "list[Record]":
    return [Record(path) for path in sorted(folder.iterdir()) if path.is_dir()]


def request(scenario: str, machine: Machine) -> Outcome:
    said = (
        f"no pictures for {machine.gpu_label()}, "
        f"record them with: python scripts/check_shots.py --record {scenario}"
    )
    return Outcome("REQUEST", scenario, said)


def check_scenario(folder: Path, out: Path, machine: Machine, shooter=shoot) -> "list[Outcome]":
    """Every line one scenario folder gets: its own, then a skip per other machine's variant."""
    variants = variants_of(folder)
    if not variants:
        if pictures_in(folder) or (folder / MANIFEST).is_file():
            said = "holds its pictures itself, move them into a variant folder named after the GPU and display"
            return [Outcome("FAIL", folder.name, said)]
        if machine.unnamed():
            return [Outcome("FAIL", folder.name, "holds no variant")]
        return [request(folder.name, machine)]
    broken = [Outcome("FAIL", record.name, record.problem) for record in variants if record.problem]
    usable = [record for record in variants if not record.problem]
    unnamed = machine.unnamed()
    if unnamed:
        return broken + [Outcome("skip", folder.name, f"{len(usable)} variant(s), and {unnamed}")]
    matching = [record for record in usable if record.matches(machine)]
    others = [
        Outcome("other", record.name, f"for {record.gpu}")
        for record in usable
        if record not in matching
    ]
    if len(matching) > 1:
        names = ", ".join(record.variant for record in matching)
        return broken + [Outcome("FAIL", folder.name, f"two variants name this machine's GPU: {names}")] + others
    if not matching:
        return broken + [request(folder.name, machine)] + others
    return broken + [check_set(matching[0], out / folder.name, machine.gpus, "", shooter)] + others


def record_scenario(name: str, records: Path, out: Path, machine: Machine, shooter=shoot, taken=head_commit) -> Outcome:
    """Run a scenario twice and keep one run as this machine's variant if the two agree."""
    scenario = SCENARIOS / f"{name}.json"
    if not scenario.is_file():
        return Outcome("FAIL", name, f"has no scenario at {scenario}")
    runs = [out / name / "record-1", out / name / "record-2"]
    for run in runs:
        code, tail = shooter(scenario, run)
        if code not in (0, EXIT_FINISHED_BUT_HUNG):
            said = f"sara_shot.py exited {code}, the run log is {run / 'run.log'}"
            return Outcome("FAIL", name, said, tail.splitlines())
    drew = [drawn_with(run) for run in runs]
    if drew[0] != drew[1]:
        named = [device or "no device named" for device in drew]
        return Outcome("FAIL", name, f"the two runs drew with {named[0]} and {named[1]}")
    real = [gpu for gpu in machine.gpus if not any(word in gpu for word in SOFTWARE)]
    gpu = drew[0] or (real[0] if len(real) == 1 else "")
    if not gpu:
        return Outcome("FAIL", name, f"the run log names no device and the machine has {', '.join(machine.gpus)}")
    folder = records / name
    existing = variants_of(folder) if folder.is_dir() else []
    left_out = sorted({shot for record in existing for shot in record.leaves_out})
    shots = [shot for shot in pictures_in(runs[0]) if shot not in left_out]
    if not shots:
        return Outcome("FAIL", name, "the scenario took no shot to record")
    if [shot for shot in pictures_in(runs[1]) if shot not in left_out] != shots:
        return Outcome("FAIL", name, "the two runs took different shots")
    failed, detail = compare([(runs[1] / shot, runs[0] / shot) for shot in shots])
    if failed:
        said = (
            f"refused, the two runs disagree on {failed} of {len(shots)} shot(s), "
            "and a scenario that does not repeat must not own a record"
        )
        return Outcome("FAIL", name, said, detail)
    same = [record for record in existing if not record.problem and record.gpu == gpu]
    target = same[0].folder if same else folder / variant_name(gpu)
    target.mkdir(parents=True, exist_ok=True)
    for old in pictures_in(target):
        (target / old).unlink()
    for shot in shots:
        shutil.copy(runs[0] / shot, target / shot)
    manifest: dict = {"gpu": gpu}
    if machine.resolution:
        manifest["display"] = {"resolution": machine.resolution, "aspect": aspect_of(machine.resolution)}
    manifest.update({"taken": taken(), "repeats": True})
    if left_out:
        manifest["leaves_out"] = left_out
    (target / MANIFEST).write_text(json.dumps(manifest, indent=4) + "\n", encoding="utf-8")
    return Outcome("ok", f"{name}/{target.name}", f"recorded {len(shots)} shot(s), the two runs agree")


def scenario_folders(root: Path) -> "list[Path]":
    return sorted(path for path in root.iterdir() if path.is_dir())


def recording(args, machine: Machine, shooter, taken) -> int:
    """What `--record` does, and its exit code."""
    unnamed = machine.unnamed()
    if unnamed:
        print(f"  nothing can be recorded here, {unnamed}", file=sys.stderr)
        return EXIT_FAILED
    folders = scenario_folders(args.records)
    if args.sets:
        unknown = [name for name in args.sets if not (SCENARIOS / f"{name}.json").is_file()]
        if unknown:
            print(f"  no scenario called {', '.join(unknown)} under {SCENARIOS}", file=sys.stderr)
            return EXIT_UNKNOWN_SET
        names = list(args.sets)
    elif args.all:
        names = [folder.name for folder in folders]
    else:
        names = [folder.name for folder in folders if not any(r.matches(machine) for r in variants_of(folder))]
    counts = {"ok": 0, "FAIL": 0}
    for name in names:
        outcome = record_scenario(name, args.records, args.out, machine, shooter, taken)
        counts[outcome.state] += 1
        print("\n".join(outcome.lines), file=sys.stderr if outcome.state == "FAIL" else sys.stdout, flush=True)
    label = machine.gpu_label()
    print(f"  {len(names)} scenario(s) to record for {label}: {counts['ok']} recorded, {counts['FAIL']} refused")
    return EXIT_FAILED if counts["FAIL"] else EXIT_PASSED


def main(
    argv: "list[str] | None" = None,
    shooter=shoot,
    gpus_of=machine_gpus,
    display_of=machine_display,
    taken=head_commit,
) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("sets", nargs="*", help="scenarios to read or record, by folder name (default: all of them)")
    parser.add_argument("--records", type=Path, default=RECORDS, help=f"the scenario folders (default: {RECORDS})")
    parser.add_argument(
        "--out", type=Path, default=DEFAULT_OUT, help=f"where the fresh shots go (default: {DEFAULT_OUT})"
    )
    parser.add_argument(
        "--record",
        action="store_true",
        help="record this machine's variant, of the scenarios named or of those that lack one",
    )
    parser.add_argument("--all", action="store_true", help="with --record, retake every scenario for this machine")
    args = parser.parse_args(argv)

    gpus, why_no_gpu = gpus_of()
    resolution, why_no_display = display_of()
    machine = Machine(gpus, why_no_gpu, resolution, why_no_display)
    if args.record:
        return recording(args, machine, shooter, taken)

    folders = scenario_folders(args.records)
    if args.sets:
        known = {folder.name: folder for folder in folders}
        unknown = [name for name in args.sets if name not in known]
        if unknown:
            print(f"  no record set called {', '.join(unknown)} under {args.records}", file=sys.stderr)
            return EXIT_UNKNOWN_SET
        folders = [known[name] for name in args.sets]
    counts = {"ok": 0, "skip": 0, "other": 0, "REQUEST": 0, "FAIL": 0}
    for folder in folders:
        for outcome in check_scenario(folder, args.out, machine, shooter):
            counts[outcome.state] += 1
            print("\n".join(outcome.lines), file=sys.stderr if outcome.state == "FAIL" else sys.stdout, flush=True)
    print(
        f"  {len(folders)} scenario(s): {counts['ok']} matched, {counts['skip']} skipped, "
        f"{counts['REQUEST']} requested, {counts['FAIL']} failed, "
        f"{counts['other']} variant(s) of other machines not read"
    )
    return EXIT_FAILED if counts["FAIL"] else EXIT_PASSED


if __name__ == "__main__":
    raise SystemExit(main())
