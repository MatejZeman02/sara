"""How a Python suite starts a shell script, on Linux and on Windows.

Windows does not read a `#!` line, so a suite that hands a script's path to
`subprocess` as the command fails with `WinError 193` before the script runs.
`command()` puts `bash` first there and nothing first anywhere else, and
`stand_in()` and `startable()` write a stand-in tool that a shell script and
a Python script can start on both.
A suite whose script needs what Git Bash lacks says so through `runs_here()`,
and so does one on a machine with no `bash` at all.
"""

from __future__ import annotations

import shutil
import sys
import unittest
from pathlib import Path


def on_windows() -> bool:
    return sys.platform == "win32"


def command(script: Path | str, *args: str) -> list[str]:
    """The argument list that starts `script` with `args` on this platform."""
    if on_windows():
        return ["bash", str(script), *args]
    return [str(script), *args]


def why_not(*lacks: str) -> str | None:
    """Why a suite cannot start its script here, or None when it can.

    `lacks` names what the script needs and Git Bash does not carry, `flock`,
    `/proc` or weston, and only matters on Windows.
    """
    if on_windows() and lacks:
        return "the script needs %s, which Git Bash on Windows lacks" % ", ".join(lacks)
    if shutil.which("bash") is None:
        return "no bash on PATH to start the script with"
    return None


def runs_here(*lacks: str):
    """A skip for a case or a class whose script cannot start here, with the reason."""
    reason = why_not(*lacks)
    return unittest.skipIf(reason is not None, reason or "")


def stand_in(path: Path, body: str) -> Path:
    """Write `body` as an executable bash stand-in at `path`, and hand it back.

    Its lines end in a bare newline on every platform, because bash reads the
    carriage return Windows' text mode would add as part of each command. A
    shell script starts it through its `#!` line on either platform.
    """
    path.write_text("#!/usr/bin/env bash\n" + body, encoding="utf-8", newline="\n")
    path.chmod(0o755)
    return path


def startable(path: Path) -> Path:
    """What a Python script starts for the stand-in at `path`.

    The stand-in itself everywhere but Windows, and there a `.cmd` beside it
    that runs it through bash, which `subprocess` can start where it cannot
    start a file by its `#!` line.
    """
    if not on_windows():
        return path
    wrapper = path.with_name(path.name + ".cmd")
    wrapper.write_text('@bash "%s" %%*\r\n' % path.as_posix(), encoding="utf-8", newline="")
    return wrapper
