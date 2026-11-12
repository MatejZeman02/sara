"""One clipboard offer on the nested compositor, put there by the real
`wl-copy`.

A painter copies a picture in a browser and presses Ctrl+V in Sara, and under
Wayland the picture reaches Sara through the clipboard program `wl-paste`
(`core/image/sa_desktop_picture.gd`). That road measured with stand-in
programs on `PATH` is a road never run, so this holds a file on the nested
weston that `sara_shot.py` starts with the real `wl-copy`, the program a
browser's Copy is replaced by, and keeps it there until the run ends.

**The type is chosen, because a file manager copies no picture.** A browser
offers `image/png` and that is the default. Nautilus offers a `text/uri-list`
of addresses, an `x-special/gnome-copied-files` whose first line is `copy`,
and a plain text of the bare paths, and Sara reads all three. Each run holds
one of them, named by `--desktop-clipboard-type`, and the bytes come from the
file the run names whatever the type is.

**The nested compositor needs a seat.** `wl-copy` refuses a compositor that
offers none, with "The compositor does not seem to implement seat", and weston's
headless backend offers one only when it is started with `--fake-seat`. Every
nested compositor gets the flag (`sara_shot.SEAT_FLAG`), so a run that asks for
a clipboard needs nothing of its own.

**Its own socket, never the desktop's.** The program is handed the nested
socket's whole path as `WAYLAND_DISPLAY`, so it cannot find another by name and
a run on a desktop never puts a picture on the painter's own clipboard.
"""

from __future__ import annotations

import shutil
import subprocess
import time
from pathlib import Path

from harness_platform import die_with_parent

PROGRAM = "wl-copy"
READER = "wl-paste"
MIME_TYPE = "image/png"

# How long the nested compositor is given to show the picture as its selection,
# and how long between two looks.
OFFER_WAIT_S = 10.0
OFFER_POLL_S = 0.2


class Refused(Exception):
    """The clipboard could not be held, with the sentence that says why."""


class DesktopClipboard:
    """One file held on one Wayland socket by `wl-copy`, from `start` until `stop`."""

    def __init__(self, png: Path, socket: Path, mime: str = MIME_TYPE) -> None:
        self.png = Path(png)
        self.socket = Path(socket)
        self.mime = mime
        self.holder: "subprocess.Popen | None" = None

    @staticmethod
    def missing() -> "str | None":
        """The sentence for a machine without the two programs, or None."""
        gone = [name for name in (PROGRAM, READER) if shutil.which(name) is None]
        if not gone:
            return None
        return f"{' and '.join(gone)} not found on PATH. Install the wl-clipboard package."

    @staticmethod
    def socket_in(env: dict) -> Path:
        """The whole path of the socket *env* names, where a bare name is looked
        for under `XDG_RUNTIME_DIR` the way libwayland looks."""
        name = Path(env.get("WAYLAND_DISPLAY", ""))
        return name if name.is_absolute() else Path(env.get("XDG_RUNTIME_DIR", "/tmp")) / name

    def command(self) -> "list[str]":
        """In the foreground, so the run owns the process it has to stop. Without
        the flag `wl-copy` forks and the holder is a process nobody started."""
        return [PROGRAM, "--foreground", "--type", self.mime]

    def environment(self, env: dict) -> dict:
        """*env* with the compositor the program talks to being this one's socket."""
        own = dict(env)
        own.pop("WAYLAND_SOCKET", None)
        own["WAYLAND_DISPLAY"] = str(self.socket)
        return own

    def offered(self, env: dict) -> bool:
        """Whether the socket's selection offers the type, asked of `wl-paste`."""
        asked = subprocess.run(
            [READER, "--list-types"],
            env=self.environment(env),
            capture_output=True,
            encoding="utf-8",
            check=False,
            timeout=OFFER_WAIT_S,
        )
        return asked.returncode == 0 and self.mime in asked.stdout.split()

    def start(self, env: dict) -> None:
        """Holds the file's bytes, and returns once the compositor offers them."""
        if not self.png.is_file():
            raise Refused(f"{self.png} is not a file, so there is nothing to put on the clipboard.")
        if not self.socket.is_socket():
            raise Refused(f"{self.socket} is not a compositor's socket, so the clipboard has no seat to live on.")
        with self.png.open("rb") as source:
            self.holder = subprocess.Popen(
                self.command(),
                stdin=source,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.PIPE,
                env=self.environment(env),
                preexec_fn=die_with_parent,  # noqa: PLW1509
            )
        deadline = time.monotonic() + OFFER_WAIT_S
        while time.monotonic() < deadline:
            if self.holder.poll() is not None:
                said = (self.holder.stderr.read() if self.holder.stderr else b"").decode("utf-8", "replace").strip()
                code = self.holder.returncode
                self.stop()
                raise Refused(f"{PROGRAM} exited with {code}: {said or 'no message'}")
            if self.offered(env):
                return
            time.sleep(OFFER_POLL_S)
        self.stop()
        raise Refused(f"{PROGRAM} ran for {OFFER_WAIT_S:.0f}s and {self.socket} never offered {self.mime}.")

    def stop(self) -> None:
        """Lets go of the clipboard. The process is the one `start` made."""
        holder, self.holder = self.holder, None
        if holder is None:
            return
        if holder.poll() is None:
            holder.terminate()
            try:
                holder.wait(timeout=5)
            except subprocess.TimeoutExpired:
                holder.kill()
                holder.wait()
        if holder.stderr:
            holder.stderr.close()

