#!/usr/bin/env python3
"""Open a live capture session on Sara and talk to it, one step at a time.

Sara started with `--agent-socket <path>` runs a scenario step posted to its
door and answers what the step did, so a scenario file and a conversation are
the same thing read from two places. The client speaks HTTP/1.1 to the door on
one connection for the whole session, each step a `POST /step` with the token
in `Authorization: Bearer`, the token read from the file the door writes
beside its socket.

    scripts/sara_door.py --state                     # one dump, then quit
    scripts/sara_door.py --scenario scenarios/x.json # a file, step by step
    scripts/sara_door.py --step '{"zoom": 2.0}'      # one step, repeatable

And the other way round: the session it drove falls out of it as a scenario
file, replayed and compared before it is installed under `scenarios/`.

    scripts/sara_door.py --step '{"zoom": 2.0}' --step '{"state": "s"}' \
        --write-scenario zoomed-in

As a library, which is what the suites and a notebook use:

    from sara_door import SaraDoor
    with SaraDoor() as door:
        answer = door.send({"state": "s"})
        print(answer["state"]["document"])

The socket path lives under XDG_RUNTIME_DIR and is kept short on purpose: a
Unix socket path is bounded by `sun_path` at 108 bytes, and a scratch directory
under a long temp path is already past that, which fails the listen with nothing
but a return value to say so.

**Two ways in.** Where Python has no `AF_UNIX`, which is
Windows, the session goes over TCP instead: Sara is started with
`--agent-port-file`, listens on 127.0.0.1 alone on a port the system picks,
and writes the port and a token to that file. The client reads it, connects to
loopback and sends the token in every request, and a request without it is
answered 401 and its connection closed. `--tcp`, or `SaraDoor(transport="tcp")`, forces
that way on Linux, which is how the suites prove it without a Windows machine.

**An installed build.** `--build <path>`, or `SARA_BIN` in the
environment, names an exported Sara, the `.exe` a painter has, and the session
drives that rather than a checkout. The launch passes no `--path` and builds no
class cache, the run gets a scratch `--settings-dir` so the painter's own
settings are never touched, and the run log is read from the build's own user
data folder on that platform, `%APPDATA%\\Godot\\app_userdata\\Sara\\logs` on
Windows. On Linux the build still runs under the nested weston, and elsewhere,
where there is none, its window opens on the desktop.

    SARA_BIN=~/sara/sara.x86_64 scripts/sara_door.py --state

**Attach.** A Sara whose door listens says where in one known
file in its user folder, `door.json`, and `SaraDoor.attach()` reads it and
connects to that Sara rather than launching one. It launches nothing, claims no
proof folder, prepares no scratch settings, and on close hangs up without
`quit`, so the Sara on the painter's screen stays open for the next client.

    scripts/sara_door.py --attach --state
"""

from __future__ import annotations

import argparse
import json
import os
import queue
import socket
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import harness_platform  # noqa: E402
import proof_claim  # noqa: E402
import sara_replay  # noqa: E402
import sara_shot  # noqa: E402  (the path has to be set first)
import sara_wake  # noqa: E402
from sara_door_link import LOOPBACK, REPLY_TIMEOUT_S, DoorError, DoorLink  # noqa: E402
from sara_findings import Findings  # noqa: E402

PROJECT_DIR = Path(__file__).resolve().parent.parent
DEFAULT_OUT = PROJECT_DIR / "scratch" / "door"

## How long to wait for the app to come up and listen. Shader compilation and
## the compositor mapping the window are most of it.
START_TIMEOUT_S = 90
## What the executor says when it does not know a step kind, the one place a
## step that did nothing says so, because `ok` is true for every well-formed
## request and `sara_shot.py` prints no warnings. Without it a scenario that
## did nothing reads as a pass.
UNRECOGNIZED_STEP = "SaCapture: unrecognised step"
## The two ways in, as `SaraDoor(transport=...)` names them.
UNIX = "unix"
TCP = "tcp"
## The environment variable that names an exported Sara to drive instead of the
## checkout, read when no `build` is passed.
SARA_BIN = "SARA_BIN"
## Where a build's scratch settings live, one folder per user the way a
## checkout has one under `scratch/`, so `keep_settings` has something to keep.
BUILD_SCRATCH = Path(tempfile.gettempdir()) / "sara-door-build"
## What `project.godot` calls the app, which names its user data folder.
APP_NAME = "Sara"
## The file in a Sara's user folder that says where its door listens.
## `SaAgentDoor.KNOWN_FILE` is the same name.
KNOWN_FILE = "door.json"
## What an attach failure tells the person, because the cure is the same whether
## the file is missing or names a Sara that has gone.
START_WITH_DOOR = "start Sara with its door, `--agent-door` after the `--` or the launcher that says so"


def default_transport() -> str:
    """A Unix socket wherever Python can open one, and TCP where it cannot."""
    return UNIX if hasattr(socket, "AF_UNIX") else TCP


def resolve_build(build: Path | str | None = None) -> Path | None:
    """The exported Sara a session drives, or `None` for the checkout.

    *build* when it is given, and otherwise `SARA_BIN`, so a library caller and
    the command line name one the same way and a configuration can set it once.
    """
    chosen = build or os.environ.get(SARA_BIN)
    return Path(chosen).expanduser().resolve() if chosen else None


def build_user_dir(platform: str | None = None) -> Path:
    """What `user://` is for an exported Sara on this platform.

    Godot's own rule for a project with no custom user folder: under
    `%APPDATA%` on Windows, `Application Support` on macOS, and the XDG data
    home elsewhere, each followed by `Godot/app_userdata/Sara`. Read from the
    environment at the moment of asking, which is the one the build inherits.
    """
    platform = platform or sys.platform
    if platform.startswith("win"):
        base = Path(os.environ.get("APPDATA") or Path.home() / "AppData" / "Roaming") / "Godot"
    elif platform == "darwin":
        base = Path.home() / "Library" / "Application Support" / "Godot"
    else:
        base = Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local" / "share") / "godot"
    return base / "app_userdata" / APP_NAME


def known_file_path(platform: str | None = None) -> Path:
    """Where a Sara with no `--settings-dir` says where its door listens.

    `door.json` in the user folder `build_user_dir` names, which a checkout run
    shares with an exported build because the project sets no folder of its own.
    """
    return build_user_dir(platform) / KNOWN_FILE


def read_known_file(path: Path) -> dict:
    """What the known file says: `{"socket": str, "token": str}` or
    `{"port": int, "token": str}`, each with the `pid` of the Sara that wrote
    it. The token goes in every HTTP request on either way in.

    Raises `DoorError` naming the cure when there is no such file or it says
    neither, because both mean no Sara has said it listens.
    """
    try:
        written = json.loads(Path(path).read_text(encoding="utf-8"))
    except FileNotFoundError:
        raise DoorError(f"no Sara says it listens, {path} is not there: {START_WITH_DOOR}") from None
    except (OSError, ValueError) as unreadable:
        raise DoorError(f"{path} could not be read ({unreadable}): {START_WITH_DOOR}") from None
    if isinstance(written, dict) and written.get("token"):
        if isinstance(written.get("socket"), str) and written["socket"]:
            return written
        if isinstance(written.get("port"), int):
            return written
    raise DoorError(f"{path} names neither a socket nor a port, with a token: {START_WITH_DOOR}")


def log_dir_for(build: Path | None) -> Path:
    """Where a session's run log is written, which is its user folder's `logs`.

    The checkout's is the isolated one under `scratch/`, the `XDG_DATA_HOME`
    `sara_shot` gives every offscreen run. A build's is its own, because
    nothing about a build a painter installed puts its user data under a
    checkout.
    """
    if build is not None:
        return build_user_dir() / "logs"
    return sara_shot.ShotProfile(PROJECT_DIR).user_dir / "logs"


## The Info docker's section that names the binary, and the docker itself, whose
## narrowest width follows that section's widest row.
PROVENANCE_SECTION = "Build"
INFO_DOCKER = "Info"


def without_provenance(dump: dict | None) -> dict | None:
    """The dump with what says which binary wrote it taken out.

    A session on a build is replayed on the checkout, and the two are different
    binaries on purpose. `sara_replay` already allows the `build` key, but the
    Info docker says it again in its Build section, `unknown` for a build with
    no stamp and `e189917, development build` for the checkout, and that row is the
    docker's widest, so its `min_size` in `docker_grips` moves with it. Those
    two are the whole difference between a build session and its replay.
    Only for a build session: two runs of one checkout agree on both.
    """
    if not isinstance(dump, dict):
        return dump
    out = dict(dump)
    if isinstance(out.get("info_docker"), list):
        out["info_docker"] = [s for s in out["info_docker"] if s.get("section") != PROVENANCE_SECTION]
    if isinstance(out.get("docker_grips"), list):
        out["docker_grips"] = [
            {k: v for k, v in grip.items() if k != "min_size"} if grip.get("docker") == INFO_DOCKER else grip
            for grip in out["docker_grips"]
        ]
    return out


def has_checkout() -> bool:
    """Whether the project these scripts came with is beside them, which is
    what a scenario file is written into and replayed against."""
    return (PROJECT_DIR / "project.godot").is_file()


class SaraDoor:
    """A running Sara with a socket open, and the client end of it."""

    def __init__(
        self,
        out_dir: Path | None = None,
        watch: bool = False,
        socket_path: str | None = None,
        idle_timeout: float | None = None,
        extra_args: list[str] | None = None,
        keep_settings: bool = False,
        transport: str | None = None,
        build: Path | str | None = None,
    ) -> None:
        ## The exported Sara this session drives, or `None` for the checkout.
        ## Settled here and never again, so the log folder the findings read
        ## and the binary the launch runs are the same answer.
        self.build = resolve_build(build)
        self.out_dir = Path(out_dir or DEFAULT_OUT).resolve()
        self.watch = watch
        ## Whether the isolated profile survives the session, the way
        ## `sara_shot.py --keep-settings` keeps it. Off by default so a
        ## conversation opens on the same defaults a scenario file opens on.
        ## A `watch` session never touches it: that one runs on the person's
        ## own settings.
        self.keep_settings = keep_settings
        ## Which way in, `UNIX` or `TCP`. A socket path belongs
        ## to the first and a port file to the second, and each is made up
        ## whichever is used so that `close` can remove either without asking.
        self.transport = transport or default_transport()
        if self.transport not in (UNIX, TCP):
            raise DoorError(f"no way in called {self.transport!r}, only {UNIX!r} and {TCP!r}")
        self.socket_path = socket_path or self._default_socket_path()
        self.port_file = self._default_port_file()
        self.idle_timeout = idle_timeout
        self.extra_args = list(extra_args or [])
        self.proc: subprocess.Popen | None = None
        self.weston: subprocess.Popen | None = None
        ## What stops `weston` once Sara's quit parks in the engine.
        self.wake: sara_wake.ExitWake | None = None
        ## The HTTP connection to the door, one for the whole session, or
        ## `None` before the connect and after the close.
        self.link: DoorLink | None = None
        self._lines: "queue.Queue[str]" = queue.Queue()
        self._reader: threading.Thread | None = None
        ## The `printed` list of the answer before, which the next request's
        ## first drain extends with what reached the pipe after that answer
        ## did. `None` before the first answer and on an attached session,
        ## which has no pipe.
        self._late_home: list[str] | None = None
        ## Verdict lines the door answered with that the pipe had not carried
        ## yet, so the answer took them from the door's own list. The pipe's
        ## copy is dropped when it turns up, rather than joining the recording
        ## twice.
        self._owed: list[str] = []
        ## The known file this session attached through, or `None` for a
        ## session that launched its Sara. Set by `attach` alone.
        self.known_file: Path | None = None
        ## The six deterministic checks, run on every answer so that the
        ## command line and a library caller both get them without asking.
        self.findings = Findings(log_dir=self.log_dir())
        ## Every request this session made, as sent and in order, with whether
        ## the app said it worked. This is the scenario file, one step per
        ## entry, and `scenario_steps` is what decides which of them go in it.
        ## A `state` step's entry also carries the dump it answered with, which
        ## is what a written file is checked against.
        self.requests: list[dict] = []

    @classmethod
    def attach(cls, known_file: Path | str | None = None) -> "SaraDoor":
        """A session on the Sara already running, found through its known file.

        Launches nothing. Over the socket the file names where Python has
        `AF_UNIX`, and over the port and its token otherwise. The first request
        says `attach`, which is how the door learns that this client going away
        must not close the Sara it found. A file left by a Sara that crashed
        names a door nobody answers on, and the connect that fails says to start
        Sara with its door.
        """
        door = cls()
        door.known_file = Path(known_file) if known_file is not None else known_file_path()
        door.findings = Findings(log_dir=door.known_file.parent / "logs")
        written = read_known_file(door.known_file)
        if "socket" in written and not hasattr(socket, "AF_UNIX"):
            raise DoorError(f"{door.known_file} names a Unix socket, which this Python cannot open")
        try:
            if "socket" in written:
                door.transport = UNIX
                door.socket_path = written["socket"]
                door.link = DoorLink.unix(door.socket_path, str(written["token"])).open()
            else:
                door.transport = TCP
                door.link = DoorLink.tcp(written["port"], str(written["token"])).open()
            answer = door.link.post({"attach": True})
        except (OSError, DoorError) as failed:
            if door.link is not None:
                door.link.close()
                door.link = None
            raise DoorError(
                f"{door.known_file} names a door nobody answers on, left by a Sara that has gone ({failed}): "
                f"{START_WITH_DOOR}"
            ) from None
        if not answer.get("attached"):
            door.close()
            raise DoorError(f"the door did not take the attach: {answer}")
        door.findings.start()
        return door

    @property
    def attached(self) -> bool:
        """Whether this session found its Sara rather than launching it."""
        return self.known_file is not None

    def ping(self) -> dict:
        """Resets the door's idle clock and nothing else, answered at once.

        Neither recorded nor checked, because it is not a step of the painting.
        """
        if self.link is None:
            raise DoorError("the session is not open")
        return self.link.post({"ping": True})

    def log_dir(self) -> Path:
        """Where this session writes its run log: the isolated one under
        `scratch/` for the checkout, the build's own for a build, and the
        `logs/` beside the known file for an attached Sara, which is under the
        `--settings-dir` folder when that Sara was started with one."""
        if self.known_file is not None:
            return self.known_file.parent / "logs"
        return log_dir_for(self.build)

    @property
    def offscreen(self) -> bool:
        """Whether the run goes under the nested weston rather than onto the
        desktop. A checkout always does unless `watch`, as it always has. A
        build does on Linux, and elsewhere has no nested compositor to go
        under, so its window opens where the person can see it."""
        if self.watch:
            return False
        return self.build is None or sys.platform.startswith("linux")

    @property
    def on_the_painters_own(self) -> bool:
        """Whether the run reads the person's own settings folder, their pen's
        curve and ceiling with it, which only a checkout's `watch` session
        does. Nothing is copied into that folder, and `_settings_dir` hands the
        app none, so the session writes nothing of the harness's there."""
        return self.watch and self.build is None

    @staticmethod
    def _default_socket_path() -> str:
        """Short, and under a directory only this user can write.

        `sun_path` holds 107 bytes and the harness runs from directories far
        longer than that, so the path is never derived from the checkout.
        """
        runtime = os.environ.get("XDG_RUNTIME_DIR") or "/tmp"
        return str(Path(runtime) / f"sara-door-{os.getpid()}.sock")

    @staticmethod
    def _default_port_file() -> Path:
        """Under a folder only this user reads, because the file holds the token.

        `XDG_RUNTIME_DIR` where there is one, and otherwise the user's own
        temporary folder, which on Windows is under the profile.
        """
        runtime = os.environ.get("XDG_RUNTIME_DIR") or tempfile.gettempdir()
        return Path(runtime) / f"sara-door-{os.getpid()}.port"

    def __enter__(self) -> "SaraDoor":
        if not self.attached:
            self.open()
        return self

    def __exit__(self, *_exc: object) -> None:
        self.close()

    def open(self) -> None:
        """Launches Sara and connects to its door, or raises with nothing left
        running, because a `with` whose `__enter__` raises never reaches
        `__exit__` and would leave a Sara that never listened behind it."""
        try:
            self.launch()
            self._connect()
            self.findings.start()  # after the connect, so the startup log is not the first step's window
        except BaseException:
            if self.link is None and self.proc is not None:
                # Nobody to ask to quit, so no reason to wait for it to.
                self.proc.terminate()
            self.close()
            raise

    def launch(self) -> None:
        """Starts Sara and its compositor without connecting, `door_start.py`'s half."""
        if self.on_the_painters_own:
            # First, so nobody reads a stroke's width as the harness's: the
            # scratch profile's pen table is the harness's, and this session
            # presses through the painter's instead.
            print("  pen      the painter's own pressure curve and ceiling, not the harness's")
        if self.transport == UNIX and len(self.socket_path.encode()) > 107:
            raise DoorError(
                f"the socket path is {len(self.socket_path.encode())} bytes and a Unix socket holds 107: {self.socket_path}"
            )
        Path(self.socket_path).unlink(missing_ok=True)
        self.token_file.unlink(missing_ok=True)
        # Sara removes a stale one too, but only once it runs, and a port read
        # from the last session's file in between is a port nobody answers on.
        self.port_file.unlink(missing_ok=True)
        # The door writes into the same proof folders a scenario does, so it
        # asks the same question first. It never clears one, so the worst
        # it can do is overwrite a file of the same name, but a session that is
        # not holding a folder has no business writing there either.
        try:
            proof_claim.hold(self.out_dir)
        except proof_claim.Refused as refusal:
            raise DoorError(refusal.report()) from refusal
        self.out_dir.mkdir(parents=True, exist_ok=True)

        env = dict(os.environ)
        env.pop("GDK_BACKEND", None)
        # Before the compositor, so a build that is not there fails with its
        # name rather than after a weston started for nothing, and so the class
        # cache is built with the plain environment.
        launch = self._launch_line(env)
        if self.offscreen:
            data_home = env.get("XDG_DATA_HOME")
            self.weston = sara_shot.start_offscreen_compositor(env)
            if self.weston is None:
                raise DoorError("no offscreen compositor, and --watch was not asked for")
            if self.build is not None:
                # The compositor starter points `user://` at the checkout's
                # scratch, which is right for a checkout. A build keeps the
                # folder it would have anyway, which `log_dir` reads.
                env.pop("XDG_DATA_HOME", None)
                if data_home is not None:
                    env["XDG_DATA_HOME"] = data_home
        cmd = launch + [
            "--",
            self._way_in_argument(),
            f"--capture-out={self.out_dir}",
        ]
        if self.idle_timeout is not None:
            cmd.append(f"--agent-idle={self.idle_timeout}")
        settings_dir = self._settings_dir()
        if settings_dir is not None:
            cmd.append(f"--settings-dir={settings_dir}")
        cmd.extend(self.extra_args)

        # `printed` comes from the child's pipe and not its log file: Godot's
        # file logger wrote a step's own `print` frames late and the engine's
        # errors in bulk later still, and the pipe carries all three as they
        # happen. The door's own log reading stays for other clients. preexec_fn
        # before the reader thread starts, the one order PR_SET_PDEATHSIG is safe
        # in (harness_platform.die_with_parent), None on Windows.
        self.proc = subprocess.Popen(
            cmd,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            encoding="utf-8",
            bufsize=1,
            preexec_fn=harness_platform.child_setup(),  # noqa: PLW1509
        )
        self.wake = sara_wake.ExitWake.for_door(self.proc, self.weston)
        self._reader = threading.Thread(target=self._pump, daemon=True)
        self._reader.start()

    def _launch_line(self, env: dict) -> list[str]:
        """What runs, up to the `--` that ends Godot's own flags.

        A checkout is Godot with `--path` on the project, after the class cache
        is made current. A build is the build: it carries its own packed
        project and its own cache, so it takes neither.
        """
        driver = ["--display-driver", "wayland"] if self.offscreen else []
        if self.build is not None:
            if not self.build.is_file():
                raise DoorError(f"no Sara at {self.build}, which --build or {SARA_BIN} names")
            return [str(self.build), *driver]
        godot = os.environ.get("GODOT_BIN") or sara_shot.find_godot()
        # The door has the same gap as the scenario runner, for the same reason:
        # two runners, one `.godot/`, and only `run_tests.sh` keeping the class
        # cache current. One line rather than a copy of the rule, because this
        # module already imports `sara_shot` for `find_godot`.
        sara_shot.ensure_class_cache(godot, env)
        # The engine's log in the checkout's scratch, a watched session's too,
        # the file `log_dir` names, so no door session rotates away a
        # painter's log.
        log = sara_shot.ShotProfile(PROJECT_DIR).log_to(env)
        return [godot, *log, "--path", str(PROJECT_DIR), *driver]

    def _settings_dir(self) -> Path | None:
        """The `--settings-dir` the run is given, or `None` for the person's own.

        The same call `sara_shot.py --scenario` makes, rather than a second copy
        of the rule, because a copy would drift and the first thing to drift
        would be which of the two runs starts clean. The directory is emptied
        rather than reused, so a conversation opens on the defaults and not on
        whatever the run before it wrote back on exit. A checkout's `watch`
        session runs on the person's own settings. A build never does, because
        the settings it would otherwise open on are a painter's.
        """
        if self.build is not None:
            return sara_shot.ShotProfile(BUILD_SCRATCH).prepare_settings(self.keep_settings)
        if self.on_the_painters_own:
            return None
        return sara_shot.ShotProfile(sara_shot.PROJECT_DIR).prepare(self.keep_settings)

    def _pump(self) -> None:
        """Every line the app writes, as it writes it."""
        assert self.proc is not None and self.proc.stdout is not None
        for line in self.proc.stdout:
            self._lines.put(line.rstrip("\n"))
            if self.wake is not None:
                self.wake.hear(line)

    def _drain(self) -> list[str]:
        """What the app has written since the last time this was asked."""
        out: list[str] = []
        while True:
            try:
                out.append(self._lines.get_nowait())
            except queue.Empty:
                return out

    def _settled(self, lines: list[str]) -> list[str]:
        """*lines* without the owed verdict lines they carry, each dropped once.

        What is still owed after this is forgotten: a line the pipe never
        carried in the same words is not waited for past one more request.
        """
        owed, self._owed = self._owed, []
        out: list[str] = []
        for line in lines:
            if line in owed:
                owed.remove(line)
                continue
            out.append(line)
        return out

    def _way_in_argument(self) -> str:
        """The argument that opens the door the way `transport` names."""
        if self.transport == TCP:
            return f"--agent-port-file={self.port_file}"
        return f"--agent-socket={self.socket_path}"

    def _connect(self) -> None:
        deadline = time.time() + START_TIMEOUT_S
        where = self.port_file if self.transport == TCP else self.socket_path
        while time.time() < deadline:
            if self.proc is not None and self.proc.poll() is not None:
                raise DoorError(f"Sara exited with {self.proc.returncode} before {where} appeared")
            try:
                self.link = self._connect_tcp() if self.transport == TCP else self._connect_unix()
            except (OSError, ValueError):
                self.link = None
            if self.link is not None:
                return
            time.sleep(0.2)
        raise DoorError(f"Sara never listened at {where} within {START_TIMEOUT_S}s")

    @property
    def token_file(self) -> Path:
        """The file beside the Unix socket that holds its token, which the door
        writes once it listens there."""
        return Path(self.socket_path + ".json")

    def _connect_unix(self) -> DoorLink | None:
        """The socket and the token its file beside it holds, once both are there.

        The token file is renamed into place whole, as the port file is, so a
        `ValueError` from one that does not parse is waited out like a missing one.
        """
        if not Path(self.socket_path).exists() or not self.token_file.exists():
            return None
        written = json.loads(self.token_file.read_text(encoding="utf-8"))
        if not isinstance(written, dict) or not written.get("token"):
            raise ValueError(f"{self.token_file} holds no token")
        return DoorLink.unix(self.socket_path, str(written["token"])).open()

    def _connect_tcp(self) -> DoorLink | None:
        """Loopback, the port the file names, and its token in every request.

        The file is renamed into place whole, so a file that is there parses.
        A `ValueError` from one that does not is waited out like a missing one.
        """
        if not self.port_file.exists():
            return None
        written = read_port_file(self.port_file)
        return DoorLink.tcp(written["port"], written["token"]).open()

    def send(self, step: dict, dump: bool = False) -> dict:
        """One step in, one answer out, with the state dump only when *dump* is set.

        The door answers a step in its verdict lines, a view line and the errors
        and warnings it raised, and carries the dump only when a request sets
        `dump`. This client asks for it only where somebody reads it, so a
        caller that reads the dump names it with
        `dump=True`. Three of the findings compare one dump with the one before,
        so a caller that reads the findings of a run of steps asks on each of
        them, and without it the findings read what the log said and nothing
        else. A `state` step always asks, because this client reads that dump
        itself: the recording keeps it, and a saved scenario is replayed
        against it.
        """
        return self._exchange([step], dump, batch=False)[0]

    def send_batch(self, steps: list[dict], dump: bool = False) -> list[dict]:
        """The steps as one request, answered in order, each answer as `send`
        makes it.

        The door runs them one after another and answers them together, so a
        step it refuses ends the batch with that step's answer last, and the
        list is shorter than *steps*. The pipe is read once, after the batch:
        each answer but the last has its own verdict lines as its `printed`,
        and the last has whatever else the pipe carried besides.
        """
        return self._exchange(list(steps), dump, batch=True)

    def _exchange(self, steps: list[dict], dump: bool, batch: bool) -> list[dict]:
        """Posts *steps*, one object or an array of them, and makes each answer
        what a caller reads: its `printed`, its findings and its recording."""
        if self.link is None:
            raise DoorError("the session is not open")
        # What the pipe carries now was printed before this request went out,
        # so it belongs to the step before. The reader thread and the socket
        # are two paths, and a line still in the first when the answer came
        # through the second lands here. It joins that answer's recording
        # rather than being dropped.
        late = self._settled(self._drain())
        if self._late_home is not None:
            self._late_home.extend(late)
        requests = []
        for step in steps:
            request = dict(step)
            if dump or "state" in step:
                request["dump"] = True
            requests.append(request)
        said = self.link.post(requests if batch else requests[0])
        answers = said if isinstance(said, list) else [said]
        # The pipe is a superset of what the door read out of the log, so it
        # replaces it rather than being merged with it. An attached session
        # has no pipe, and keeps what the door read, or its verdict lines when
        # the request asked for no dump.
        #
        # A step's own verdict lines are in the answer either way. Without the
        # dump the door answers before the pipe has caught up, a lag the time
        # spent building a dump covers, so a verdict line the pipe has not
        # carried yet is taken from the door's list and is owed.
        if self.attached:
            for answer in answers:
                answer.setdefault("printed", list(answer.get("verdicts", [])))
        else:
            pipe = self._settled(self._drain())
            owed: list[str] = []
            for answer in answers[:-1]:
                answer["printed"] = list(answer.get("verdicts", []))
                for line in answer["printed"]:
                    if line in pipe:
                        pipe.remove(line)
                    else:
                        owed.append(line)
            if answers:
                last = [line for line in answers[-1].get("verdicts", []) if line not in pipe]
                answers[-1]["printed"] = pipe + last
                owed.extend(last)
            self._owed = owed
        for step, answer in zip(steps, answers):
            self._record(step, answer)
        return answers

    def _record(self, step: dict, answer: dict) -> None:
        """Runs the findings on *answer* and keeps the step in the recording."""
        bare = {k: v for k, v in step.items() if k not in ("id", "settle", "dump")}
        answer["findings"] = self.findings.check(bare, answer, printed=answer["printed"])
        acted = bool(answer.get("ok", True)) and not any(UNRECOGNIZED_STEP in line for line in answer["printed"])
        entry = {"step": bare, "ok": acted, "printed": answer["printed"]}
        if not self.attached:
            self._late_home = answer["printed"]
        if "state" in bare:
            entry["state"] = answer.get("state")
        self.requests.append(entry)

    def mark_restart(self) -> None:
        """A new process starts here, so nothing recorded before it can be part
        of one scenario file.

        The mark is kept rather than the list cleared, so a caller that carries
        a recording across a restart still has the session whole and only the
        file is cut. `restarted` in `test_door_scenario.py` is that caller, a
        quit and a start as the door guide's restart is.
        """
        self.requests.append({"step": {}, "ok": True, "restart": True})

    ## Steps that replace the document, so what came before them is not part of
    ## reproducing what came after. The same window a finding names.
    DOCUMENT_STEPS = ("load", "document", "import")

    ## The door's own control words, which are not steps and which the executor
    ## never sees. `id` and `settle` are already gone by the time a request is
    ## recorded, so this is the third one.
    CONTROL_STEPS = ("quit", "ping")

    def scenario_steps(self, whole: bool = False) -> list[dict]:
        """The session as a scenario: the requests, in order, minus what cannot
        be replayed.

        Four things come out. The door's own control words, `id` and `settle`
        already gone at the point a request is recorded and `quit` here. A step
        the app said it did not run, because a scenario that reproduces a
        failure to dispatch reproduces nothing. Everything up to and including the last
        restart, because those steps went to a process that has quit and one
        scenario file is one process. And by default everything before the last
        document step, because a file that opens with the tail of another
        document's session is a file that fails on the next machine.

        `state`, `shot` and `wait` all stay. The first two are what a scenario
        asserts with, and a scenario that settles differently from the session
        it came from is a different scenario.
        """
        kept = list(self.requests)
        for i in range(len(kept) - 1, -1, -1):
            if kept[i].get("restart"):
                kept = kept[i + 1 :]
                break
        kept = [entry for entry in kept if entry["ok"] and entry["step"] and not self._is_control(entry["step"])]
        if not whole:
            for i in range(len(kept) - 1, -1, -1):
                if any(key in self.DOCUMENT_STEPS for key in kept[i]["step"]):
                    kept = kept[i:]
                    break
        return [entry["step"] for entry in kept]

    def _is_control(self, step: dict) -> bool:
        return any(key in self.CONTROL_STEPS for key in step)

    def recorded_state(self, name: str) -> dict | None:
        """The dump the session's `state` step of that name answered with."""
        for entry in reversed(self.requests):
            if entry.get("step", {}).get("state") == name:
                return entry.get("state")
        return None

    def write_scenario(self, path: Path, whole: bool = False) -> list[dict]:
        """Writes the session's steps to *path* and answers what it wrote.

        One step per line, which is how every committed scenario is written and
        how a diff of one stays readable.
        """
        steps = self.scenario_steps(whole=whole)
        path = Path(path)
        path.parent.mkdir(parents=True, exist_ok=True)
        body = ",\n".join("  " + json.dumps(step) for step in steps)
        path.write_text("[\n" + body + "\n]\n", encoding="utf-8")
        return steps

    def save_scenario(
        self, name: str, whole: bool = False, verify: bool = True, directory: Path | None = None
    ) -> dict:
        """The session as a committable scenario under `scenarios/<name>.json`.

        The file is written to `scratch/door-scenarios/` first and only moved
        into place once a replay of it reaches the dump the session reached,
        under `sara_replay`'s comparison. A file that does not replay stays in
        the scratch directory with the differences named, because a scenario
        that fails on the next machine is worse than none: the agent that
        committed it has proved nothing and does not know it.

        A session with no `state` step cannot be compared against anything, so
        the file lands with `verified` false and the reason said out loud rather
        than a check being claimed that did not run.

        **Every dump the session wrote is compared, not the last.** A scenario
        whose middle steps prove the thing and whose last step undoes it would
        be verified by the half that shows nothing: where the last step is an
        undo the last dump is the starting document either way, and a run that
        drew no crop rectangle at all would install as verified. Each
        difference carries the name of the state it came from.

        **Without a checkout**, a session driving a build from
        scripts that have no project beside them, there is no `scenarios/` to
        install into and nothing to replay against. The file is written beside
        the run log instead, and the answer says so and names where it would
        have gone, so the agent carries it into a checkout rather than
        believing it landed.
        """
        steps = self.scenario_steps(whole=whole)
        if not steps:
            raise DoorError("the session holds no replayable step, so there is no scenario to write")
        stem = Path(name).stem
        if not has_checkout():
            beside = self.log_dir() / f"{stem}.json"
            self.write_scenario(beside, whole=whole)
            return {
                "path": str(beside),
                "would_write": f"sara-godot/scenarios/{stem}.json",
                "steps": steps,
                "verified": False,
                "why": (
                    f"there is no checkout beside these scripts, so the file went beside the run log rather than "
                    f"into sara-godot/scenarios/{stem}.json, and nothing replayed it"
                ),
                "differences": [],
            }
        staged = PROJECT_DIR / "scratch" / "door-scenarios" / f"{stem}.json"
        self.write_scenario(staged, whole=whole)
        target = Path(directory or (PROJECT_DIR / "scenarios")) / f"{stem}.json"

        answer = {"path": str(target), "steps": steps, "verified": False, "why": "", "differences": []}
        names = sara_replay.state_names(steps)
        if not verify:
            answer["why"] = "the caller asked for no replay, so nothing checks that this file reaches the same state"
        elif not names:
            answer["why"] = "the session made no state step, so a replay has no dump to be compared with"
        else:
            live = {name: self.recorded_state(name) for name in names}
            out_dir = PROJECT_DIR / "scratch" / "door-scenarios" / f"{stem}-replay"
            try:
                replayed = sara_replay.replay_states(staged, out_dir)
            except Exception as failed:  # a replay that did not run is not a replay that agreed
                answer["why"] = f"the replay could not run: {failed}"
                answer["path"] = str(staged)
                return answer
            if self.build is not None:
                replayed = {key: without_provenance(dump) for key, dump in replayed.items()}
                live = {key: without_provenance(dump) for key, dump in live.items()}
            answer["differences"] = sara_replay.differences_at_each_state(replayed, live)
            answer["verified"] = not answer["differences"]
            if not answer["verified"]:
                answer["why"] = "the file does not reach every state the session reached, so it was not installed"
                answer["path"] = str(staged)
                return answer
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(staged.read_text(encoding="utf-8"), encoding="utf-8")
        return answer

    def close(self) -> None:
        """Asks the session to quit, then makes sure it did. An attached one is
        hung up on instead, and its Sara goes on for the next client."""
        if self.attached:
            if self.link is not None:
                self.link.close()
                self.link = None
            return
        if self.link is not None:
            try:
                self.link.post({"quit": True})
            except (OSError, DoorError):
                pass
            self.link.close()
            self.link = None
        if self.proc is not None:
            try:
                self.proc.wait(timeout=15)
            except subprocess.TimeoutExpired:
                self.proc.terminate()
            if self.proc.stdout is not None:
                self.proc.stdout.close()
            self.proc = None
        if self._reader is not None:
            self._reader.join(timeout=5)
            self._reader = None
        if self.weston is not None:
            self.weston.terminate()
            try:
                self.weston.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.weston.kill()
            self.weston = None
        Path(self.socket_path).unlink(missing_ok=True)
        self.token_file.unlink(missing_ok=True)
        self.port_file.unlink(missing_ok=True)


def read_port_file(path: Path) -> dict:
    """The port and token the TCP way in wrote, as `{"port": int, "token": str}`.

    Raises `ValueError` for a file that is not that, so a caller waiting for the
    file treats a bad one the way it treats a missing one.
    """
    written = json.loads(Path(path).read_text(encoding="utf-8"))
    if not isinstance(written, dict) or not isinstance(written.get("port"), int) or not written.get("token"):
        raise ValueError(f"{path} does not name a port and a token")
    return {"port": written["port"], "token": str(written["token"])}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--scenario", type=Path, help="a scenario file, sent one step at a time")
    parser.add_argument("--step", action="append", default=[], help="one step as JSON, repeatable")
    parser.add_argument("--state", action="store_true", help="ask for a dump and print it")
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT, help=f"output directory (default: {DEFAULT_OUT})")
    parser.add_argument("--watch", action="store_true", help="show the window on your desktop")
    parser.add_argument(
        "--keep-settings", action="store_true", help="open on the profile the last session left, rather than on defaults"
    )
    parser.add_argument("--full", action="store_true", help="print the whole answer rather than a summary")
    parser.add_argument(
        "--tcp", action="store_true", help="the loopback port and token rather than a Unix socket, as on Windows"
    )
    parser.add_argument(
        "--build", type=Path, help=f"an exported Sara to drive rather than the checkout (or set {SARA_BIN})"
    )
    parser.add_argument(
        "--attach", action="store_true", help="the Sara already running, found through its known file"
    )
    parser.add_argument("--write-scenario", metavar="NAME", help="write the session to scenarios/NAME.json at the end")
    parser.add_argument(
        "--whole-session", action="store_true", help="write every step, not only those since the last document"
    )
    parser.add_argument("--no-verify", action="store_true", help="install the written scenario without replaying it")
    args = parser.parse_args()

    steps: list[dict] = []
    if args.scenario is not None:
        steps.extend(json.loads(args.scenario.read_text(encoding="utf-8")))
    steps.extend(json.loads(one) for one in args.step)
    if args.state or not steps:
        steps.append({"state": "door"})

    transport = TCP if args.tcp else None
    if args.attach:
        opened = SaraDoor.attach()
    else:
        opened = SaraDoor(
            out_dir=args.out, watch=args.watch, keep_settings=args.keep_settings, transport=transport, build=args.build
        )
    with opened as door:
        for i, step in enumerate(steps):
            answer = door.send({"id": i, **step}, dump=True)
            if args.full:
                print(json.dumps(answer, indent=2))
                continue
            state = answer.get("state") or {}
            canvas = (state.get("canvases") or [{}])[0]
            print(
                f"  {json.dumps(step)[:60]:62s} "
                f"steps={state.get('history', {}).get('steps')} "
                f"zoom={canvas.get('zoom')} shot={answer.get('shot')}"
            )
            for line in answer.get("printed", []):
                if "SaCapture" in line or "SCRIPT ERROR" in line:
                    print(f"      {line}")
            for finding in answer.get("findings", []):
                print(f"      [{finding['kind']}] {finding['says']}")
        if args.write_scenario:
            saved = door.save_scenario(args.write_scenario, whole=args.whole_session, verify=not args.no_verify)
            print(f"\n  wrote {saved['path']}, {len(saved['steps'])} steps, verified={saved['verified']}")
            if saved["why"]:
                print(f"  {saved['why']}")
            for line in saved["differences"]:
                print(f"    {line}")
            if not saved["verified"] and saved["differences"]:
                return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
