"""The tee of run_tests.sh, with a ceiling on what one run may write.

    timeout ... godot ... 2>&1 | python scripts/run_log_ceiling.py LOG MARK RUNNER MB REPEATS

Every line Godot prints goes to this process's output and to LOG, as `tee` did,
until one of two things passes its limit:

- the bytes written to LOG pass MB megabytes, or
- one script error, the same message at the same place, comes REPEATS times.

Then the engine is stopped, a last line says which limit it was and the count,
and MARK is written with that line, so run_tests.sh fails the run on it rather
than reading the log as an ordinary death. Whatever the engine prints after
that is read and dropped, so it never blocks on a full pipe while it dies.

A gate that loops on a script error can write gigabytes of this log onto a
memory-backed /tmp until the out-of-memory killer takes down whatever runs
beside it, a painter's Sara among them. A loop here ends in seconds with its first lines kept, which say where it began.

RUNNER is the pid of run_tests.sh. The engine is the child of the `timeout` it
started, the same walk the wake in run_tests.sh makes, and only that process is
signalled, never one found by its name.
"""

import os
import re
import signal
import sys
import time

## A script error's first line, and the line under it, indented, that says where it was.
ERROR_HEAD = b"SCRIPT ERROR: "
WHERE_HEAD = b"at: "
## Seconds a TERM is given before the engine is killed outright.
TERM_GRACE = 3.0
## Godot colours its lines, and the key of a repeat is the plain text.
ANSI = re.compile(rb"\x1b\[[0-9;]*m")


def _children(pid):
    """The pids whose parent is *pid*, read from /proc."""
    found = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            with open("/proc/%s/stat" % entry, "rb") as stat:
                fields = stat.read().rsplit(b") ", 1)[1].split()
        except OSError:
            continue
        if int(fields[1]) == pid:
            found.append(int(entry))
    return found


def _command(pid):
    try:
        with open("/proc/%d/comm" % pid, "rb") as comm:
            return comm.read().strip().decode("utf-8", "replace")
    except OSError:
        return ""


def _engine(runner):
    """The engine under the runner's `timeout`, or the `timeout` when it has none."""
    for watch in _children(runner):
        if _command(watch) == "timeout":
            under = _children(watch)
            return under[0] if under else watch
    return None


def _stop(runner):
    pid = _engine(runner)
    if pid is None:
        return
    try:
        os.kill(pid, signal.SIGTERM)
    except OSError:
        return
    until = time.monotonic() + TERM_GRACE
    while time.monotonic() < until:
        try:
            os.kill(pid, 0)
        except OSError:
            return
        time.sleep(0.1)
    try:
        os.kill(pid, signal.SIGKILL)
    except OSError:
        pass


class Ceiling:
    """The two limits, counted line by line."""

    def __init__(self, megabytes, repeats):
        self.most_bytes = int(megabytes) * 1024 * 1024
        self.most_repeats = int(repeats)
        self.written = 0
        self.seen = {}
        self.said = None

    def take(self, line):
        """The line that ends the run when *line* passes a limit, else None."""
        self.written += len(line)
        if self.written > self.most_bytes:
            return (
                "the run's output passed the ceiling of %d MB (SARA_TEST_LOG_CEILING_MB), "
                "so the run was stopped" % (self.most_bytes // (1024 * 1024))
            )
        plain = ANSI.sub(b"", line).rstrip(b"\r\n")
        if plain.startswith(ERROR_HEAD):
            self.said = plain[len(ERROR_HEAD) :]
            return None
        where = plain.lstrip()
        if self.said is not None and where.startswith(WHERE_HEAD):
            key = (self.said, where[len(WHERE_HEAD) :])
            self.said = None
            self.seen[key] = self.seen.get(key, 0) + 1
            if self.seen[key] >= self.most_repeats:
                return (
                    "one script error came %d times (SARA_TEST_REPEATED_ERRORS), so the run "
                    "was stopped as a loop: %s at %s"
                    % (self.seen[key], key[0].decode("utf-8", "replace"), key[1].decode("utf-8", "replace"))
                )
        return None


def main(argv):
    log_path, mark_path, runner, megabytes, repeats = argv[1:6]
    ceiling = Ceiling(megabytes, repeats)
    source = sys.stdin.buffer
    shown = sys.stdout.buffer
    with open(log_path, "wb") as log:
        for line in iter(source.readline, b""):
            stop = ceiling.take(line)
            if stop is not None:
                said = ("\n✗ %s.\n" % stop).encode("utf-8")
                log.write(said)
                log.flush()
                shown.write(said)
                shown.flush()
                with open(mark_path, "w", encoding="utf-8") as mark:
                    mark.write(stop + "\n")
                _stop(int(runner))
                for _ in iter(source.readline, b""):
                    pass
                return 0
            # Flushed a line at a time, because the wake in run_tests.sh reads
            # the log for the result while the engine is still running.
            log.write(line)
            log.flush()
            shown.write(line)
            shown.flush()
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv))
    except BrokenPipeError:
        sys.exit(0)
    except KeyboardInterrupt:
        sys.exit(130)
