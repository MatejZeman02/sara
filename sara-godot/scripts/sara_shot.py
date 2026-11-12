#!/usr/bin/env python3
"""Drive Sara and capture what it looks like, plus the numbers behind it.

The QA gate proves logic, not appearance -- it has passed while the UI was twice
its intended size. This runs the real app with a real RenderingDevice, saves
viewport PNGs and a JSON state dump, and prints where they landed.

    scripts/sara_shot.py                          # one shot + one state dump
    scripts/sara_shot.py --scenario probe.json    # a scripted sequence
    scripts/sara_shot.py --state-only             # skip the images
    scripts/sara_shot.py --show                   # print the state dump inline
    scripts/sara_shot.py --desktop-clipboard pic.png   # the real wl-copy holds pic.png
    scripts/sara_shot.py --desktop-clipboard files.txt --desktop-clipboard-type text/uri-list

A scenario is a JSON array of steps, run in order:

    [{"wait": 20}, {"move": [900, 600]}, {"shot": "over-canvas"}, {"state": "s"}]

Steps: wait (frames), move [x, y], press/release ("left"|"right"|"middle", or
{"button": "left", "shift": true}), shot (name), state (name), drag, probe, click,
and layer (add, blend, fill, activate: see harness/scenario/layers/sa_capture_layers.gd).

probe and click do not need the pointer to be anywhere in particular, which
matters because Wayland will not let a client move it. probe asks the live cursor
logic what it would answer at a list of points plus the centre of every embedded
docker; click injects a press-release, optionally with ALT held, and reports what
it did to the active tool. Both print to stdout rather than to a file.

The PNG never contains the OS hardware cursor, because the compositor draws that
one. Whether the pointer is visible is answered by "mouse_mode" in the state
dump. Pointer placement is best effort on Wayland, so check "pointer_warp_works"
before trusting a shot that depends on where the pointer is.
"""

from __future__ import annotations

import argparse
import json
import re
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

import proof_claim
from harness_platform import die_with_parent, gate_slot  # noqa: F401  (the door calls both through here)
import sara_wake
import shot_clipboard
from shot_problems import DISTINCT_PROBLEMS, LEAK_PATTERN, REFUSAL_OPENERS, is_problem, report_problems
from shot_profile import ShotProfile

PROJECT_DIR = Path(__file__).resolve().parent.parent
DEFAULT_OUT = PROJECT_DIR / "scratch" / "captures"

# What the nested compositor renders with when nothing asks for another.
# `gl` reaches a hardware device and `pixman` reaches Mesa's software Vulkan, so
# the two are two different machines rather than two settings of one, and every
# figure read off a run names which of them answered.
DEFAULT_RENDERER = "gl"
# What weston's headless backend is started with to offer a seat, which it
# offers none of without it. Every nested compositor is started with it: see
# `compositor_command` for what a seatless one prints.
SEAT_FLAG = "--fake-seat"
# Long enough to cover shader compilation and the compositor settling the
# window, short enough that a hang is reported rather than waited out.
#
# `SARA_SHOT_TIMEOUT` overrides it, which exists so the timeout branch can be
# reached on purpose: a hang that happens one run in three cannot be summoned,
# and a branch nobody has run on the real app is a branch nobody has proved.
# A bad value falls back rather than failing, because this is a convenience
# and not a setting.
try:
    TIMEOUT_S = int(os.environ.get("SARA_SHOT_TIMEOUT", "120"))
except ValueError:
    TIMEOUT_S = 120

# The last thing `SaCapture._finish` prints before it calls `quit()`. Its
# presence in the child's output is the difference between a scenario that never
# ran and one that ran to its end and could not leave.
DONE_MARKER = sara_wake.CAPTURE_MARKER

# A run whose scenario finished and whose process then failed to exit. Separate
# from 1, which every other failure here returns, because the two need different
# answers: this one's artefacts are on disk and usable, and a caller that treats
# it as "produced nothing" reruns a capture it already has. Measured at three
# hangs in eight runs of `brush-presets-editing` and one in three of `editor-pages`, so
# it is common enough for a caller to care.
EXIT_FINISHED_BUT_HUNG = 2

# A capture whose every stroke failed to reach the GPU. Its own code, because
# the run is otherwise complete: every step ran, every shot and dump was
# written, and the pictures are of a canvas nothing was painted on. Without
# the code a session shoots its scenario, sees 0 and files pictures that prove
# nothing, which is what two strokes landing under a docker look like.
EXIT_NO_STROKE_PAINTED = 3

# What the stroke step prints for a stroke whose press a docker took, which is the
# one stroke outcome that is a mistake in the scenario rather than a tool that
# paints nothing on purpose. `harness/scenario/sa_scenario_stroke.gd` writes both halves.
STROKE_PREFIX = "SaCapture: stroke ("
STROKE_FAILED = " failed: no dab reached the GPU"
STROKE_PAINTED = " GPU dispatches"

NO_GODOT = "Godot not found on PATH. Install it or set GODOT_BIN."


def locate_godot() -> str | None:
    """The first `godot` or `godot4` on PATH, or None. Neither exits nor raises."""
    for candidate in ("godot", "godot4"):
        found = shutil.which(candidate)
        if found:
            return found
    return None


def find_godot() -> str:
    """The Godot a command line runs, and an exit with the reason when there is none."""
    found = locate_godot()
    if found is None:
        sys.exit(NO_GODOT)
    return found


def godot_for_a_suite() -> str:
    """The Godot a suite starts: `GODOT_BIN`, else PATH, else a skip with the reason.

    `find_godot` exits the process, which is right for a command and wrong inside
    `unittest`: the exit is not caught by `setUpClass`, so the whole run ends at
    exit 1 with no case reported, the cases before it and every module named
    after it on the same command included. A `SkipTest` raised from a class setup
    skips that class and lets the rest run.
    """
    found = os.environ.get("GODOT_BIN") or locate_godot()
    if found is None:
        import unittest

        raise unittest.SkipTest(NO_GODOT)
    return found


## The output a nested compositor is given when a scenario asks for no other,
## and the size every record set is taken at unless its scenario says another.
DEFAULT_OUTPUT = (1920, 1080)


def read_steps(scenario: "Path | None") -> "list":
    """A scenario's steps, or an empty list when there is nothing readable.

    Two callers below read the file before the app does, for the two things a
    step cannot say once the app is running: how large the compositor's output
    has to be, and what goes on the command line. A missing or malformed file is
    the app's error to report, not this function's, so it answers with nothing
    and the run goes ahead and fails where a reader will see why.
    """
    if scenario is None:
        return []
    try:
        steps = json.loads(Path(scenario).read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return []
    return steps if isinstance(steps, list) else []


def split_harness_steps(steps: "list") -> "tuple[list, list[str], bool, str]":
    """The steps without the entries the harness answers, and those answers.

    Four are the harness's rather than the app's, `{"args": [...]}`,
    `{"settings": "keep"}`, `{"renderer": "pixman"}` and `{"timeout": 300}`, and
    all four leave the copy the app is handed.

    **A command line exists a step earlier than any step.** The app reads
    `OS.get_cmdline_user_args()` in `Main._open_command_line_document`, at the end of
    the boot, before it has opened the scenario at all, so nothing the app does
    with a step can reach it. Without this entry no scenario reaches that
    function at all, and its three branches, a file that opens, a path with
    nothing behind it and a window with no File menu, are covered by nothing.

    **The entry is read here and taken out again**, rather than passed through.
    `sa_capture.gd` warns on a step it does not know, and a harness argument is
    no step of the app's, so the app is handed a copy of the scenario with the `args`
    entries gone and never sees a step it would complain about.

    The precedent is `output_size_for` right above, and so is the reason: the
    file names what it needs and any harness that runs it supplies that, which
    is what makes a committed scenario a proof another agent can repeat. The
    `--arg` flag is the same argument typed once, for a path this machine has and
    the next one does not, and it lands after the file's own.

    **A scenario names the compositor when the default never finishes it.**
    `start_offscreen_compositor` starts weston with `--renderer=gl`, and under it
    `prefs-minimize` and `prefs-minimize-2` stop once the Preferences window
    rolls up and `the-dockers-menu-follows-the-map` prints `SaCapture: done`
    and never leaves, while all three finish inside a minute under pixman. So the
    file says which it needs, rather than a caller remembering
    `SARA_WESTON_RENDERER`: a scenario that only finishes with an environment
    variable set is half a file.

    `{"timeout": 300}` is the same argument for the clock. It is read
    into the limit by `timeout_for` below rather than returned here, because a
    fifth return value would break every caller that unpacks four, and the
    value is already in the file this function is handed.
    """
    kept: list = []
    app_args: list[str] = []
    keep_settings = False
    renderer = ""
    for step in steps:
        if isinstance(step, dict) and "modules_on" in step:
            continue  # read by `modules_on_for` before the start, like `timeout`
        asked = step.get("args") if isinstance(step, dict) else None
        wanted = step.get("settings") if isinstance(step, dict) else None
        compositor = step.get("renderer") if isinstance(step, dict) else None
        limit = step.get("timeout") if isinstance(step, dict) else None
        if asked is None and wanted is None and compositor is None and limit is None:
            kept.append(step)
            continue
        if asked is not None:
            app_args.extend(str(entry) for entry in (asked if isinstance(asked, list) else [asked]))
        if wanted is not None:
            keep_settings = keep_settings or str(wanted) == "keep"
        if compositor is not None:
            renderer = str(compositor)
    return kept, app_args, keep_settings, renderer


def modules_on_for(scenario: "Path | None") -> "list[str]":
    """The modules a build ships switched off that *scenario* switches on,
    `{"modules_on": ["kaleidoscope"]}`, written into the cleared profile by
    `ShotProfile.switch_on` because the loader reads the setting before any step.
    """
    wanted: list[str] = []
    for step in read_steps(scenario):
        asked = step.get("modules_on") if isinstance(step, dict) else None
        if asked is not None:
            wanted.extend(str(module) for module in (asked if isinstance(asked, list) else [asked]))
    return wanted


def timeout_for(scenario: "Path | None") -> int:
    """How many seconds *scenario* may run for.

    A scenario that legitimately needs longer than `TIMEOUT_S` names its own
    limit, the way `output_size_for` beside this reads the width its window
    needs and the `renderer` entry names the compositor it needs. One does,
    and not because it hangs: `colour-themes` changes the live palette five
    times and each change re-themes every window, which measured at about 28
    seconds a change under the offscreen harness, so the file wants about 166
    seconds on an idle card and the 120 it defaults to on a busy one is not
    enough. Naming the clock is the honest answer where the alternative is
    dropping steps that are the scenario's own proof.

    The largest entry wins, for the reason `output_size_for` gives about
    windows: one run has one clock.
    """
    limit = TIMEOUT_S
    for step in read_steps(scenario):
        asked = step.get("timeout") if isinstance(step, dict) else None
        if asked is not None:
            limit = max(limit, int(asked))
    return limit


def output_size_for(scenario: "Path | None") -> "tuple[int, int]":
    """How large the nested compositor's output has to be for *scenario*.

    A headless weston pins a window to its output, so a `{"window": [w, h]}`
    step can only reach a size the output already has. Reading the file here
    rather than asking for a flag keeps a scenario self-contained: the file
    names the width it needs and any harness that runs it gets that width.

    The largest step wins, because one run has one output and a scenario that
    asks for 2560 and then 1280 wants both to be reachable.
    """
    steps = read_steps(scenario)
    width, height = DEFAULT_OUTPUT
    for step in steps:
        asked = step.get("window") if isinstance(step, dict) else None
        if isinstance(asked, list) and len(asked) >= 2:
            width = max(width, int(asked[0]))
            height = max(height, int(asked[1]))
    return width, height


def resolve_renderer(renderer: str = "") -> str:
    """Which of the two renderers the nested compositor should start with.

    **A name the scenario gave wins over the environment's.** The two renderers
    are two different machines rather than two settings of one, and the three
    scenarios `split_harness_steps` names never finish under the default, so a
    pinned `SARA_WESTON_RENDERER` must not be able to put them back into the
    hang. A scenario with no opinion still reads the variable, which is how a
    run is pinned to a device for a measurement.
    """
    return renderer or os.environ.get("SARA_WESTON_RENDERER") or DEFAULT_RENDERER


def compositor_command(size: "tuple[int, int]", socket: str, renderer: str = "") -> "list[str]":
    """The weston command line, separate from starting it so a suite can read it.

    The renderer is resolved here and nowhere else, so a test of the three-way
    choice needs no compositor and no display.

    **`--fake-seat`, because a desktop always offers a seat.** Without it the
    headless backend offers none, and Godot's
    `WaylandThread::pointer_set_constraint` fails `ERR_FAIL_NULL(ss)` on the
    missing seat each time the mouse mode changes, even to a mode with nothing
    to constrain. Sara hides and shows the pointer as the ring comes and goes,
    so nearly every run's log carries `Parameter "ss" is null`, a line no
    painter's desktop can print. The engine records the mode either way, so the
    dump's `mouse_mode` reads the same, and `check_shots.py` takes shots that
    are byte for byte the same with the seat and without it. What the seat
    changes is that the window holds the keyboard focus a desktop gives it, and
    that a clipboard run (`shot_clipboard.py`) has what `wl-copy` needs.

    **`--idle-time=0`, because nothing ever touches this compositor.** Weston
    counts the time since its last input, five minutes by default, then fades
    out, locks and stops repainting. The harness puts its events into Godot
    rather than into weston, so for weston a session that paints for an hour has
    had no input at all. A Sara that is drawing when the lock comes waits inside
    the NVIDIA driver's present for a Wayland event that never arrives, its main
    thread in `ppoll` under `wl_display_dispatch_queue_timeout`. A door session
    painting soft Airbrush strokes stops answering a few minutes in, whatever
    the seed and whatever the stroke count, and never with the idle timer off.
    """
    command = [
        "weston",
        "--backend=headless",
        "--renderer=" + resolve_renderer(renderer),
        f"--width={size[0]}",
        f"--height={size[1]}",
        f"--socket={socket}",
        "--idle-time=0",
        SEAT_FLAG,
    ]
    return command


def start_offscreen_compositor(
    env: dict, size: "tuple[int, int]" = DEFAULT_OUTPUT, renderer: str = ""
) -> "subprocess.Popen | None":
    """A nested headless Wayland compositor, so the run never takes the screen.

    A capture is a machine check, and there are several per change. A window that
    appears on the monitor and takes the keyboard makes the harness something to
    avoid using. The recipe is the test suite's
    (`SARA_TEST_OFFSCREEN=1 ./run_tests.sh`): weston renders into a headless
    backend against the real GPU, so the screenshots are the real thing.

    Not the same as `--display-driver headless`, which has no rendering device at
    all and so cannot composite anything to photograph.

    *renderer* is the scenario's own request, empty when it has none. Which one
    is used is `resolve_renderer`'s answer and not this function's.
    """
    if shutil.which("weston") is None:
        print("  weston is not installed, so there is nowhere to render out of sight.", file=sys.stderr)
        print("  Install it (dnf install weston), or pass --watch to use your desktop.", file=sys.stderr)
        return None

    socket = f"sara-shot-{os.getpid()}"
    runtime = Path(env.get("XDG_RUNTIME_DIR", "/tmp"))
    chosen = resolve_renderer(renderer)
    proc = subprocess.Popen(
        compositor_command(size, socket, renderer),
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        env=env,
        preexec_fn=die_with_parent,  # noqa: PLW1509
    )
    for _ in range(40):
        if (runtime / socket).is_socket():
            break
        time.sleep(0.25)
    else:
        print("  the offscreen compositor never came up.", file=sys.stderr)
        proc.terminate()
        return None

    env["WAYLAND_DISPLAY"] = socket
    print(f"  offscreen  nested weston on {socket} at {size[0]}x{size[1]}, {chosen}, no window on any monitor")

    # The same isolation run_tests.sh applies: user:// is one directory for
    # every checkout, so an offscreen capture gets its own under scratch/. It
    # also makes a capture reproducible, because it inherits none of the UI
    # scale and docker layout the person running it happens to have saved.
    # --watch keeps the real one on purpose, because that run is for a person.
    data_home = ShotProfile(PROJECT_DIR).data_home
    data_home.mkdir(parents=True, exist_ok=True)
    env["XDG_DATA_HOME"] = str(data_home)
    return proc


def write_run_log(out_dir: Path, cmd: list[str], proc: subprocess.CompletedProcess) -> Path:
    """Everything the app printed, beside the artefacts, every run.

    The terminal gets a summary and the summary is a summary: twenty error lines
    forwarded and the rest dropped, an ordinary `print` among them. Three
    capture steps report only by printing, `probe`, `{"hide": ""}` and `undo`,
    so without the file the proof of a claim about a docker's hide button or
    about how many steps an undo moved cannot be read back from a run at all.
    This covers the lot, at the cost of a file per run.
    """
    path = out_dir / "run.log"
    lines = [
        "# " + " ".join(cmd),
        f"# exit {proc.returncode}",
        "",
        proc.stdout,
    ]
    if proc.stderr:
        lines += ["", "# --- stderr ---", "", proc.stderr]
    path.write_text("\n".join(lines), encoding="utf-8")
    return path


# The class cache the editor writes, and the directories a newer `.gd` is never
# looked for in. Both are `run_tests.sh`'s, read rather than reinvented.
CLASS_CACHE = PROJECT_DIR / ".godot" / "global_script_class_cache.cfg"
CACHE_SKIPS = {".godot", "scratch", ".conda", "build"}


def class_cache_state(cache: Path = CLASS_CACHE, root: Path = PROJECT_DIR) -> str:
    """What the class cache needs before the app is launched.

    `"import"` when there is none, which is a fresh clone or a worktree.
    `"rescan"` when one `.gd` is newer than it, which is a unit that has just
    added a `class_name`. `"current"` otherwise.

    The rule is `run_tests.sh`'s, line for line: the same file, the same four
    pruned directories, and the same "one script newer than the cache is the
    whole test". It stops at the first such script the way `find -print -quit`
    does, because the answer is a yes or a no and the tree has 500 scripts in it.
    """
    if not cache.exists():
        return "import"
    cache_mtime = cache.stat().st_mtime
    for parent, dirs, names in os.walk(root):
        dirs[:] = [d for d in dirs if d not in CACHE_SKIPS]
        for name in names:
            if not name.endswith(".gd"):
                continue
            try:
                if Path(parent, name).stat().st_mtime > cache_mtime:
                    return "rescan"
            except OSError:
                continue
    return "current"


def ensure_class_cache(godot: str, env: dict[str, str] | None = None) -> str:
    """Lets the editor look at the tree when the class cache is behind it.

    A `class_name` added since an editor last looked is not in the cache, and a
    script that uses it fails to *parse*. `run_tests.sh` runs this pass and so
    does this: two runners, one project directory, one `.godot/`, and a runner
    that skipped it would leave the order a unit happened to work in deciding
    whether its scenario ran, on a message that names an identifier rather than
    a stale cache.

    Called from the launch step of both this and `sara_door.py`, which imports
    this module for `find_godot` already. One helper rather than two copies,
    because the two runners share the cache they are both behind.

    Prints what it did, the way `run_tests.sh` prints `rescan`, so a run that
    takes four seconds longer says why.
    """
    state = class_cache_state()
    if state == "import":
        print("  import   no class cache yet, letting the editor import the tree")
    elif state == "rescan":
        print("  rescan   a script is newer than the class cache, letting the editor look")
    else:
        return state
    subprocess.run(
        [godot, "--headless", f"--settings-dir={ShotProfile(PROJECT_DIR).prepare_rescan()}", "--path", str(PROJECT_DIR), "--editor", "--quit"],
        capture_output=True,
        encoding="utf-8",
        env=env,
        check=False,
    )
    return state


def child_command(
    godot: str,
    driver: str,
    capture_flag: str,
    out_dir: "Path",
    settings_dir: "Path | None",
    app_args: "list[str] | None" = None,
) -> "list[str]":
    """The whole command line the app is started with.

    A function rather than a list built inline, because the order in it is a
    claim rather than a formatting choice and a claim is worth a test.

    **Everything the app itself is meant to read goes last**, after the `--` and
    after the harness's own flags. `SaBoot.document_path` walks
    `OS.get_cmdline_user_args()`, which is everything after the `--`, and skips
    anything beginning with a dash, so a path appended at the end is the first
    thing it sees and `--capture=` and its friends go past untouched. Without the
    path a scenario cannot reach that function at all, and its three branches, a
    file that opens, a path with nothing behind it, and a window with no File
    menu, are covered by nothing a run can exercise.

    Where those arguments come from is `split_harness_steps` above: a scenario's
    own `{"args": [...]}` entry first, then anything `--arg` added.
    """
    cmd = [
        godot,
        "--path",
        str(PROJECT_DIR),
        "--display-driver",
        driver,
        "--",
        capture_flag,
        f"--capture-out={out_dir}",
    ]
    if settings_dir is not None:
        cmd.append(f"--settings-dir={settings_dir}")
    cmd.extend(str(extra) for extra in (app_args or []))
    return cmd


def scenario_finished(stdout: str) -> bool:
    """Whether the scenario ran to its last step, from the child's own output.

    `SaCapture._finish` prints `DONE_MARKER` and then calls `get_tree().quit()`,
    so the marker means every step ran and the app asked to leave. A process
    still alive after that is the engine failing to tear down, which is the same
    reading the notes already record for the suite.
    """
    return DONE_MARKER in (stdout or "")


def last_log_line(stdout: str, stderr: str = "") -> str:
    """The last thing the app said, which is what a reader wants first.

    stderr after stdout, because Godot's own errors go there and a run that hung
    while unregistering a module says so on that pipe.
    """
    for text in (stderr, stdout):
        for line in reversed((text or "").splitlines()):
            if line.strip():
                return line.strip()
    return ""


def report_timeout(stdout: str, stderr: str, artefacts: list[Path], log_path: Path, seconds: int) -> int:
    """What a timed-out run is told and what it exits with.

    A timed-out run is one of two things, and a single message for both is wrong
    about one run in three of some scenarios. "Usual cause: a parse error, so
    SaCapture never reached `_process`" sends an agent looking for a parse error
    in a scenario whose artefacts are all on disk and whose log ends in
    `SaCapture: done`, where what happened is that the process failed to leave
    and can sit for hours after the run that started it.

    So the branch asks the output which of the two happened, says so, and
    returns a different code for each. The artefacts are listed either way,
    because a partial run's are evidence too.
    """
    print(f"\n  timed out after {seconds}s -- the app never quit.", file=sys.stderr)
    # On stderr with the message rather than on stdout with a finished run's
    # list, so the whole block arrives on one stream and in order. Two streams
    # into one terminal interleave, which would put the artefacts under the
    # message that names one of them.
    if hung_artefacts_line := "".join(
        f"\n    {path.name:28s} {path.stat().st_size:>9,d} bytes" for path in artefacts
    ):
        print(f"  {len(artefacts)} artefact(s) already written:{hung_artefacts_line}", file=sys.stderr)
    if not scenario_finished(stdout):
        print("  The scenario did not reach its last step, and no `SaCapture: done` is", file=sys.stderr)
        print("  in the output. Usual cause: a parse error, so SaCapture never reached", file=sys.stderr)
        print("  _process. The whole run is in:", file=sys.stderr)
        print(f"    {log_path}", file=sys.stderr)
        return 1

    print("  The scenario finished. `SaCapture: done` is in the output, so every step", file=sys.stderr)
    print("  ran and the app asked to quit and then failed to leave, which is the", file=sys.stderr)
    print("  engine rather than the scenario. The artefacts", file=sys.stderr)
    print("  above are complete, and there is nothing wrong with the scenario to find.", file=sys.stderr)
    if artefacts:
        print(f"    last artefact  {artefacts[-1].name}", file=sys.stderr)
    print(f"    last log line  {last_log_line(stdout, stderr)}", file=sys.stderr)
    print(f"    the whole run  {log_path}", file=sys.stderr)
    return EXIT_FINISHED_BUT_HUNG


def stroke_verdict(stdout: str) -> tuple[int, int, int]:
    """How many strokes the run painted, how many a docker took, and how many it
    had, read off the stroke step's own verdict lines.

    A stroke that did no GPU work without a docker in the way is neither: the pan
    and selection tools draw nothing on purpose, and a scenario that strokes with
    one is not a scenario that failed. So the total can be more than the other two.
    """
    painted = failed = total = 0
    for line in stdout.splitlines():
        if STROKE_PREFIX not in line:
            continue
        total += 1
        if STROKE_FAILED in line:
            failed += 1
        elif STROKE_PAINTED in line:
            painted += 1
    return painted, failed, total


def report_strokes(stdout: str) -> int | None:
    """The exit code a run's strokes call for, and the words that go with it.

    Every stroke a docker took, and none painted, is `EXIT_NO_STROKE_PAINTED`
    with a block on stderr saying so above the problem list. Some taken and some
    painted is a line the caller cannot miss and no change to the code, because
    the pictures are real and the scenario's author may have meant the others.
    No stroke at all, or none taken, is `None`: nothing to say.
    """
    painted, failed, total = stroke_verdict(stdout)
    if failed == 0:
        return None
    if painted == 0:
        print(f"\n  no stroke painted: all {failed} of the run's strokes lost their press to a docker.", file=sys.stderr)
        print("  The shots and dumps are written and show a canvas nothing reached, so they", file=sys.stderr)
        print("  prove nothing. Move the strokes clear of the dockers, or park them.", file=sys.stderr)
        return EXIT_NO_STROKE_PAINTED
    print(f"\n  {failed} of {total} stroke(s) painted nothing: a docker took the press. See the", file=sys.stderr)
    print("  problem lines above for which, before trusting a shot taken after one.", file=sys.stderr)
    return None


def clear_captures(out_dir: Path) -> None:
    """Empty *out_dir* of the last round, keeping the `CLAIM` that owns it.

    A proof folder is cleared by the session that holds it, and the file saying
    so has to outlive the clearing or the next round would find it free.
    """
    for entry in out_dir.iterdir():
        if entry.name == proof_claim.CLAIM_NAME and entry.is_file():
            continue
        if entry.is_dir() and not entry.is_symlink():
            shutil.rmtree(entry)
        else:
            entry.unlink()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--scenario", type=Path, help="JSON file describing the steps to run")
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT, help=f"output directory (default: {DEFAULT_OUT})")
    parser.add_argument("--state-only", action="store_true", help="dump state without saving images")
    parser.add_argument("--show", action="store_true", help="print the state dump to stdout")
    parser.add_argument("--driver", default="wayland", help="display driver (default: wayland)")
    parser.add_argument("--keep", action="store_true", help="keep previous captures instead of clearing the directory")
    parser.add_argument("--keep-settings", action="store_true", help="open on the last capture's profile")
    parser.add_argument(
        "--arg",
        action="append",
        default=[],
        metavar="ARG",
        help="an argument for the app itself, after the `--`, repeatable, on top of the scenario's own",
    )
    parser.add_argument(
        "--watch",
        action="store_true",
        help="show the window on your desktop instead of rendering into a nested headless compositor",
    )
    parser.add_argument(
        "--desktop-clipboard",
        type=Path,
        metavar="FILE",
        help="hold FILE on the nested compositor's clipboard with the real wl-copy until the run ends",
    )
    parser.add_argument(
        "--desktop-clipboard-type",
        default=shot_clipboard.MIME_TYPE,
        metavar="MIME",
        help=f"the type the clipboard offers the file as (default: {shot_clipboard.MIME_TYPE}), for a file manager's copy",
    )
    args = parser.parse_args()

    clipboard = None
    if args.desktop_clipboard is not None:
        # Before anything is held or cleared: an option that cannot be met is
        # refused with nothing touched, and never met by a stand-in.
        if args.watch:
            print("  --desktop-clipboard needs the nested compositor, which --watch does not start.", file=sys.stderr)
            return 1
        unmet = shot_clipboard.DesktopClipboard.missing()
        if unmet:
            print(f"  {unmet}", file=sys.stderr)
            return 1

    out_dir: Path = args.out.resolve()
    # First of all, before the search for Godot and before anything is cleared,
    # because the whole point is that another session's evidence survives the
    # attempt. A refused run has touched nothing at all.
    try:
        proof_claim.hold(out_dir)
    except proof_claim.Refused as refusal:
        print(refusal.report(), file=sys.stderr)
        return proof_claim.REFUSED_EXIT

    godot = os.environ.get("GODOT_BIN") or find_godot()
    if out_dir.exists() and not args.keep:
        clear_captures(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    scenario_path = args.scenario
    temp_scenario = None
    if scenario_path is None and args.state_only:
        temp_scenario = tempfile.NamedTemporaryFile("w", suffix=".json", delete=False, encoding="utf-8")
        json.dump([{"state": "default"}], temp_scenario)
        temp_scenario.close()
        scenario_path = Path(temp_scenario.name)

    # The scenario's own command-line arguments, taken out of the copy the app is
    # given so it never meets a step it does not know. The flag lands
    # after the file's, because a path typed at a terminal is the specific case
    # and the file is the general one.
    app_args = list(args.arg)
    keeps_settings = args.keep_settings
    requested_renderer = ""
    requested_limit = TIMEOUT_S
    modules_on: list[str] = []
    if scenario_path is not None and temp_scenario is None:
        steps, asked, asked_to_keep, requested_renderer = split_harness_steps(read_steps(scenario_path))
        # Read from the file rather than from `split_harness_steps`, which strips
        # the entry and hands back four values. Read here, before the copy below
        # replaces `scenario_path` with one that no longer carries it.
        requested_limit = timeout_for(scenario_path)
        modules_on = modules_on_for(scenario_path)
        keeps_settings = keeps_settings or asked_to_keep
        # Any entry the harness answered means the app must be handed a copy
        # without it, `renderer` and `timeout` included: a step the app does not
        # know is a warning in the log rather than a step it ignores quietly.
        if asked or asked_to_keep or requested_renderer or requested_limit != TIMEOUT_S or modules_on:
            app_args = asked + app_args
            temp_scenario = tempfile.NamedTemporaryFile("w", suffix=".json", delete=False, encoding="utf-8")
            json.dump(steps, temp_scenario)
            temp_scenario.close()
            if asked:
                print(f"  args     {' '.join(asked)}  (from {scenario_path})")
            scenario_path = Path(temp_scenario.name)

    capture_flag = f"--capture={scenario_path}" if scenario_path else "--capture"
    settings_dir = None
    if not args.watch:
        # The settings file and the docker layout live under whatever
        # get_settings_dir() resolves to, and --watch is the desktop run that
        # keeps the real one on purpose. --settings-dir is the flag form of the
        # isolation run_tests.sh applies through XDG_CONFIG_HOME, so a capture
        # never touches ~/.config/sara.
        settings_dir = ShotProfile(PROJECT_DIR).prepare(keeps_settings)
        if not keeps_settings:
            ShotProfile(PROJECT_DIR).switch_on(settings_dir, modules_on)
    cmd = child_command(godot, args.driver, capture_flag, out_dir, settings_dir, app_args)

    # GDK_BACKEND=x11 makes libdecor's GTK plugin fail to init against a Wayland
    # surface, adding two warning lines that read as a regression.
    env = dict(os.environ)
    env.pop("GDK_BACKEND", None)
    # The Welcome picture's light follows the sun where the painter lives, so a
    # shot holds it at noon in Prague unless the caller names an hour or a
    # zone, and a record set of the Welcome window reads the same at any time
    # of day, any date and on any machine, with no overlay drawn. Noon rather
    # than a dawn hour, which moves with the date of the run: the day is listed
    # at ten degrees up on both sides of the sun, so the whole of a Prague day,
    # winter's too, shows one picture.
    env.setdefault("SARA_WELCOME_HOUR", "12")
    env.setdefault("SARA_WELCOME_ZONE", "Europe/Prague")
    env.setdefault("SARA_WELCOME_ROLL", "1")
    # The version under the picture's title, and the picture its minor picks, are
    # in a record set of the window, so a version bump leaves the set matching.
    env.setdefault("SARA_WELCOME_VERSION", "0.19.1")
    # The display follows the system's profile for the monitor by default, and
    # a nested compositor's output can stand where the painter's monitor does,
    # so a shot asks a system with none unless the caller names a profile.
    env.setdefault("SARA_SYSTEM_PROFILE", "none")
    cmd[1:1] = ShotProfile(PROJECT_DIR).log_to(env)

    # Before the compositor, because the editor pass is headless and wants no
    # display, and before the run, because a stale cache is a parse error rather
    # than a slow start.
    ensure_class_cache(godot, env)

    slot = gate_slot()
    weston = None
    if not args.watch:
        if requested_renderer:
            print(f"  renderer {requested_renderer}  (from {args.scenario})")
        if requested_limit != TIMEOUT_S:
            print(f"  timeout  {requested_limit}s  (from {args.scenario})")
        weston = start_offscreen_compositor(env, output_size_for(scenario_path), requested_renderer)
        if weston is None:
            # Before the `try` below, so its cleanup is done here: otherwise
            # the copy of the scenario stays in the temporary folder and the
            # slot stays open.
            if temp_scenario is not None:
                os.unlink(temp_scenario.name)
            if slot is not None:
                slot.close()
            return 1

    print(f"  running  {' '.join(cmd)}")
    # The child writes to files rather than pipes, so the wake can read the
    # marker while the run is going, and a hung run's output is whole on disk
    # when the limit kills it.
    child_io = tempfile.TemporaryDirectory(prefix="sara-shot-")
    out_path = Path(child_io.name) / "stdout"
    err_path = Path(child_io.name) / "stderr"
    wake = None
    try:
        if args.desktop_clipboard is not None:
            clipboard = shot_clipboard.DesktopClipboard(
                args.desktop_clipboard,
                shot_clipboard.DesktopClipboard.socket_in(env),
                args.desktop_clipboard_type,
            )
            try:
                clipboard.start(env)
            except shot_clipboard.Refused as refusal:
                print(f"  {refusal}", file=sys.stderr)
                return 1
            print(f"  clipboard  {shot_clipboard.PROGRAM} holds {args.desktop_clipboard} as {clipboard.mime} on {clipboard.socket.name}")
        with out_path.open("w", encoding="utf-8") as out, err_path.open("w", encoding="utf-8") as err:
            engine = subprocess.Popen(cmd, stdout=out, stderr=err, env=env, preexec_fn=die_with_parent)  # noqa: PLW1509
        if weston is not None:
            wake = sara_wake.ExitWake(engine, weston, DONE_MARKER, sara_wake.exit_grace(), transcript=out_path)
            wake.start()
        try:
            engine.wait(timeout=requested_limit)
            killed = False
        except subprocess.TimeoutExpired:
            engine.kill()
            engine.wait()
            killed = True
        if wake is not None:
            wake.stop()
        proc = subprocess.CompletedProcess(
            cmd,
            1 if killed else engine.returncode,
            out_path.read_text(errors="replace", encoding="utf-8"),
            err_path.read_text(errors="replace", encoding="utf-8"),
        )
        if wake is not None and wake.woken:
            print(f"  woken    the engine hung on exit after `{DONE_MARKER}`, so its compositor was stopped")
            print(f"           and it finished its own shutdown with exit {engine.returncode}")
        if killed:
            # The log is written on this path too, because a hung run's output
            # would otherwise go with the exception and the one file that says
            # which of the two hangs happened is the one this branch owes.
            log_path = write_run_log(out_dir, cmd, proc)
            report_problems(proc, log_path)
            hung_artefacts = (
                [p for p in sorted(out_dir.iterdir()) if p != log_path] if out_dir.exists() else []
            )
            hung = report_timeout(proc.stdout, proc.stderr, hung_artefacts, log_path, requested_limit)
            # A run that finished and then hung is complete, so its strokes are
            # read the same way a clean exit's are, and a canvas nothing reached
            # outranks the engine failing to leave.
            strokes = report_strokes(proc.stdout) if hung == EXIT_FINISHED_BUT_HUNG else None
            return strokes if strokes is not None else hung
    finally:
        if clipboard is not None:
            clipboard.stop()
        child_io.cleanup()
        if temp_scenario is not None:
            os.unlink(temp_scenario.name)
        if weston is not None:
            weston.terminate()
        # None when the slot was inherited from a gate that is still holding it,
        # which is the one thing this must not close.
        if slot is not None:
            slot.close()

    log_path = write_run_log(out_dir, cmd, proc)
    report_problems(proc, log_path)

    artefacts = [p for p in sorted(out_dir.iterdir()) if p != log_path] if out_dir.exists() else []
    if not artefacts:
        print("\n  no artefacts produced. The whole run is in:", file=sys.stderr)
        print(f"    {log_path}\n", file=sys.stderr)
        print(proc.stdout[-3000:], file=sys.stderr)
        print(proc.stderr[-3000:], file=sys.stderr)
        return 1

    print(f"\n  {len(artefacts)} artefact(s) in {out_dir}")
    for path in artefacts:
        print(f"    {path.name:28s} {path.stat().st_size:>9,d} bytes")
    # Named on every run, not only a failing one. Three capture steps report by
    # printing and nothing else, so on a green run this line is the pointer at
    # the only copy of what they said.
    print(f"    {log_path.name:28s} {log_path.stat().st_size:>9,d} bytes, everything the app printed")

    if args.show:
        for path in artefacts:
            if path.suffix == ".json":
                print(f"\n  ---- {path.name} ----")
                print(path.read_text(encoding="utf-8"))

    strokes = report_strokes(proc.stdout)
    if strokes is not None:
        return strokes
    return 0 if proc.returncode == 0 else proc.returncode


if __name__ == "__main__":
    sys.exit(main())
