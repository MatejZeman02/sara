#!/usr/bin/env python3
"""Start a door Sara under a nested weston that goes on after this command ends.

An agent that paints over `curl` wants a Sara that listens in the background,
and a launcher written for that waits for Sara and stops weston once Sara has
exited. One quit in twenty under a nested weston never ends (godot#123059, the
Wayland events thread), and such a launcher then waits for ever. This one
keeps `sara_wake.ExitWake` on the session for its whole life, so a quit the
door makes on its own, at the idle timeout or a `quit` step, ends with the
process and its compositor gone.

    python scripts/door_start.py --idle 3600            # the checkout
    python scripts/door_start.py --build ~/sara/sara.x86_64 --idle 3600
    python scripts/door_start.py --socket "$SOCK" -- --some-flag

It prints the socket, once Sara listens there, and the keeper's process,
which stopping stops the session as well. The keeper is the same command with
`--serve`, started in a session of its own: it launches Sara through
`SaraDoor.launch`, the launch `sara_door.py` makes, without connecting, so the
door is free for the first `curl`. Its log, `door-start.log` in `--out`, ends
with when Sara's last line came, how it ended and whether the wake was needed.
Linux only, since a nested weston is.
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from sara_door import DEFAULT_OUT, START_TIMEOUT_S, DoorError, SaraDoor  # noqa: E402

## The keeper's log, in the session's out folder.
LOG_NAME = "door-start.log"
## The keeper's lines a reader takes apart, the suites above all.
STARTED = "sara-pid"
HEARD = "teardown-heard-at"
ENDED = "ended-at"


def default_socket() -> str:
    """The socket the guides name, short and under the user's runtime folder."""
    return str(Path(os.environ.get("XDG_RUNTIME_DIR") or "/tmp") / "sara-door.sock")


def arguments(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--socket", default=default_socket(), help="the Unix socket the door listens on")
    parser.add_argument("--idle", type=float, default=3600.0, help="seconds with no request before the door closes")
    parser.add_argument("--build", type=Path, help="an exported Sara rather than the checkout (or set SARA_BIN)")
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT, help="where shots and the keeper's log go")
    parser.add_argument("--keep-settings", action="store_true", help="open on the profile the last session left")
    parser.add_argument("--serve", action="store_true", help=argparse.SUPPRESS)
    parser.add_argument("extra", nargs="*", help="further flags for Sara, after a `--`")
    return parser.parse_args(argv)


def serve(args: argparse.Namespace) -> int:
    """The keeper: Sara launched, waited for, and its compositor stopped after."""
    door = SaraDoor(
        out_dir=args.out,
        socket_path=args.socket,
        idle_timeout=args.idle,
        extra_args=args.extra,
        keep_settings=args.keep_settings,
        build=args.build,
    )
    try:
        door.launch()
    except DoorError as error:
        print(f"  {error}", flush=True)
        door.close()
        return 1
    assert door.proc is not None and door.weston is not None
    wake = door.wake
    print(f"{STARTED} {door.proc.pid} weston-pid {door.weston.pid}", flush=True)
    code = door.proc.wait()
    ended = time.time()
    door.close()
    if wake is not None:
        print(f"{HEARD} {wake.heard_at if wake.heard_at is not None else 'never'}", flush=True)
        if wake.woken:
            print("  woken    the engine parked on its quit, so its compositor was stopped (GODOT-BUGS.md)", flush=True)
    print(f"{ENDED} {ended:.3f} exit {code}", flush=True)
    return 0


def start(args: argparse.Namespace, argv: list[str]) -> int:
    """Starts the keeper detached, and returns once the door listens."""
    if not sys.platform.startswith("linux"):
        print("  a nested weston is Linux's alone, so start Sara with its door as DOOR.md says", file=sys.stderr)
        return 1
    token = Path(args.socket + ".json")
    token.unlink(missing_ok=True)
    args.out.mkdir(parents=True, exist_ok=True)
    log = args.out.resolve() / LOG_NAME
    with log.open("w", encoding="utf-8") as sink:
        keeper = subprocess.Popen(
            [sys.executable, str(Path(__file__).resolve()), "--serve", *argv],
            stdin=subprocess.DEVNULL,
            stdout=sink,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )
    deadline = time.monotonic() + START_TIMEOUT_S
    while not token.exists():
        if keeper.poll() is not None or time.monotonic() > deadline:
            print(f"  Sara never listened at {args.socket}, the keeper's log is {log}", file=sys.stderr)
            print(log.read_text(encoding="utf-8", errors="replace")[-2000:], file=sys.stderr)
            return 1
        time.sleep(0.2)
    print(f"  door     {args.socket}, its token in {token}")
    print(f"  keeper   pid {keeper.pid}, which ends the session when stopped, its log {log}")
    return 0


def main(argv: list[str] | None = None) -> int:
    given = list(sys.argv[1:] if argv is None else argv)
    args = arguments(given)
    if args.serve:
        return serve(args)
    return start(args, given)


if __name__ == "__main__":
    sys.exit(main())
