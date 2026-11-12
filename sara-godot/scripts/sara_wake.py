#!/usr/bin/env python3
"""The wake that frees an engine parked on its own exit, for every launcher.

Godot 4.7's Wayland events thread can miss the wake its teardown waits for, and
then the quit never ends (godot#123059).
About one quit in twenty under a nested weston hangs so, more on a loaded
machine. The engine's main thread joins an events thread that sits in `poll()`
on the compositor's socket, and stopping the compositor closes that socket, so
the engine finishes its own shutdown in under a second with the whole of its
output.

`sara_shot.py` keeps one for a capture, whose last line is `SaCapture: done`,
and `sara_door.py` keeps one for a door session for as long as the session
lives, whose last line is Sara's own trail line before the engine's teardown.
A door quit Sara makes on its own, the idle close or a `quit` step, is woken
the same way as one a client asked for. `door_start.py`
starts a door session that outlives the command, and the wake with it.
"""

from __future__ import annotations

import os
import signal
import subprocess
import threading
import time
from pathlib import Path

# What a capture prints last before it calls `quit()`, `SaCapture._finish`.
CAPTURE_MARKER = "SaCapture: done"
# What Sara prints last of its own on any quit, `SaTrail`'s line once the root
# has gone, after which only the engine's teardown is left.
DOOR_MARKER = "Sara's own teardown is done"


def cpu_ticks(pid: int) -> "int | None":
    """User plus system CPU time of *pid* in clock ticks, or None once it is gone.

    Split after the last `)`, because the command name before it may hold spaces.
    """
    try:
        fields = Path(f"/proc/{pid}/stat").read_text(encoding="utf-8").rsplit(")", 1)[1].split()
        return int(fields[11]) + int(fields[12])
    except (OSError, IndexError, ValueError):
        return None


def exit_grace() -> float:
    """`SARA_SHOT_EXIT_GRACE`, falling back to two seconds on a bad value."""
    try:
        return float(os.environ.get("SARA_SHOT_EXIT_GRACE", "2"))
    except ValueError:
        return 2.0


class ExitWake(threading.Thread):
    """Frees an engine parked on exit by stopping its compositor, as run_tests.sh does.

    The marker is heard one of two ways: read out of a *transcript* file the
    engine writes its output to, which is a capture's, or handed in line by
    line through `hear`, which is a door's, whose output is a pipe its client
    reads.

    A hang is told from a slow exit by CPU time. An engine still shutting down
    spends some, so a loaded machine delays the wake rather than faking one. One
    that spends none for `grace` seconds after the marker is parked.
    `SARA_SHOT_EXIT_GRACE` sets the grace, two seconds by default. Killing the
    engine instead would cut its output short.
    """

    def __init__(
        self,
        engine: subprocess.Popen,
        compositor: subprocess.Popen,
        marker: str,
        grace: float,
        transcript: Path | None = None,
    ) -> None:
        super().__init__(daemon=True)
        self.engine = engine
        self.compositor = compositor
        self.marker = marker
        self.grace = grace
        self.transcript = transcript
        ## Whether the compositor was stopped to free the engine.
        self.woken = False
        ## The wall clock time the marker was heard at, or None before it.
        self.heard_at: float | None = None
        self.finished = threading.Event()
        self._heard = threading.Event()

    @classmethod
    def for_door(cls, engine: subprocess.Popen, compositor: subprocess.Popen | None) -> "ExitWake | None":
        """A started wake for a door session, or None for one on the desktop.

        It ends on its own once the engine has gone, so a client that closes
        has nothing to stop. The client hands it every line through `hear`.
        """
        if compositor is None:
            return None
        wake = cls(engine, compositor, DOOR_MARKER, exit_grace())
        wake.start()
        return wake

    def hear(self, line: str) -> None:
        """One line of the engine's output, for a wake with no transcript."""
        if not self._heard.is_set() and self.marker in line:
            self.heard_at = time.time()
            self._heard.set()

    def _running(self) -> bool:
        return not self.finished.is_set() and self.engine.poll() is None

    def _said(self) -> bool:
        if self.transcript is not None and not self._heard.is_set():
            self.hear(self.transcript.read_text(errors="replace", encoding="utf-8"))
        return self._heard.is_set()

    def run(self) -> None:
        while self._running():
            if self._said():
                break
            self.finished.wait(0.25)
        last, idle = None, 0.0
        while self._running():
            ticks = cpu_ticks(self.engine.pid)
            idle = idle + 0.5 if ticks is not None and ticks == last else 0.0
            last = ticks
            if idle >= self.grace:
                self.woken = True
                if self.compositor.poll() is None:
                    self.compositor.send_signal(signal.SIGTERM)
                return
            self.finished.wait(0.5)

    def stop(self) -> None:
        """Ends the wake once its engine has gone or its run is over."""
        self.finished.set()
        if self.is_alive():
            self.join()
