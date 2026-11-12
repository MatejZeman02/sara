"""What the harness asks of Linux, and what each thing does on a machine without it.

Two calls, both Linux's own and both made by every script that starts a Godot.
`gate_slot` holds one of the machine's Godot slots with `flock`, and
`die_with_parent` asks the kernel to end a child when the script that started
it dies. They live here rather than at the top of `sara_shot.py`, whose
`import fcntl` would then run on every import of it, and `sara_door.py`
imports that module for `find_godot`, which is enough to kill a door client on
Windows before it opens anything.

Here each is guarded. Without `fcntl` no slot is taken, which is right:
the slots cap the Godots of the Linux machine the checkouts share, and a Windows
session is one person's. Without Linux there is no `prctl`, and a child is
started with no `preexec_fn` at all, because Python on Windows refuses one:
`child_setup()` is what a `Popen` passes. `sara_shot` imports both names, so a
caller that reached them through it still does.
"""

from __future__ import annotations

import ctypes
import ctypes.util
import os
import signal
import sys
import time
from pathlib import Path
from typing import Callable

try:
    import fcntl
except ImportError:  # pragma: no cover - Windows
    fcntl = None

# `prctl(PR_SET_PDEATHSIG, sig)` asks the kernel to send `sig` to this process
# when its parent goes. The number is Linux's and is stable ABI, so the
# library is opened on Linux alone, and a machine without it gets no handle and
# the explicit terminate on the way out is all there is.
PR_SET_PDEATHSIG = 1
_LIBC = None
if sys.platform.startswith("linux"):
    try:
        _LIBC = ctypes.CDLL(ctypes.util.find_library("c") or "libc.so.6", use_errno=True)
    except OSError:  # pragma: no cover - no libc by any name we can find
        _LIBC = None


def gate_slot():
    """One of the machine's Godot slots, held until the returned file closes,
    or None when the caller already holds one.

    run_tests.sh takes the same slots, SARA_GATE_SLOTS of them under
    SARA_GATE_LOCK_DIR, because a dozen checkouts gating and capturing on one 8 GB
    card at once make the driver refuse allocations, and a capture that fails
    for another checkout's gate is a defect nobody can fix.

    **A slot already held is inherited rather than taken twice.** The gate holds
    one to the end and then runs check_skeleton_boots.py, which runs
    `sara_shot.py`: a caller that needs two slots and takes them one at a time
    deadlocks the moment enough callers do it at once, and with three slots
    three gates are enough to park twenty-four more. At SARA_GATE_SLOTS=1 one
    gate alone on the machine hangs in the skeleton boot.

    The cap is about how many Godots are on the card at once, and a gate runs
    one at a time, the suite and then the skeleton boot. So inheriting the slot
    keeps the promise the cap makes, and None is returned because the caller
    only ever closes what it was given. Where there is no `fcntl` there is no
    slot either, as the module's header says."""
    if os.environ.get("SARA_GATE_SLOT_HELD") or fcntl is None:
        return None
    directory = Path(os.environ.get("SARA_GATE_LOCK_DIR", "/tmp/sara-gate"))
    slots = int(os.environ.get("SARA_GATE_SLOTS", "3"))
    directory.mkdir(parents=True, exist_ok=True)
    waited = 0
    while True:
        for i in range(1, slots + 1):
            handle = open(directory / f"slot-{i}", "w", encoding="utf-8")  # noqa: SIM115
            try:
                fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except OSError:
                handle.close()
                continue
            if waited:
                print(f"  gate slot {i} after {waited}s")
            return handle
        time.sleep(5)
        waited += 5


def die_with_parent() -> None:
    """Ask the kernel to signal this child when its parent goes.

    `SaraDoor.close()` and `sara_shot.py`'s own cleanup both terminate what they
    started, and neither runs when the client is `SIGKILL`ed. The children are
    then reparented to init, and a nested weston keeps its socket in
    `XDG_RUNTIME_DIR` for ever, and such a socket has been found half a day
    after whatever started it died. `PR_SET_PDEATHSIG` is the
    kernel's own answer and needs no cleanup path at all.

    Two things it does not cover, written down rather than rediscovered. It fires
    when the **thread** that forked exits rather than the process, which is right
    for these scripts because every child here is started before any thread is,
    and would be wrong for a threaded caller. And a parent that dies between the
    fork and this call leaves the child unsignalled, a window of microseconds,
    which is why `close()` still terminates weston rather than trusting this
    alone.

    This runs in the child between fork and exec, where nothing that is not
    async-signal-safe may be called. The library is therefore opened at import
    time, above, and what happens here is one syscall through a pointer that
    already exists.
    """
    if _LIBC is not None:
        _LIBC.prctl(PR_SET_PDEATHSIG, signal.SIGTERM, 0, 0, 0)


def child_setup() -> Callable[[], None] | None:
    """What a `Popen` passes as `preexec_fn`: `die_with_parent` on POSIX, and
    nothing on Windows, where Python refuses the argument outright."""
    return die_with_parent if os.name == "posix" else None
