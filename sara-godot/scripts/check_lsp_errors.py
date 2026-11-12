#!/usr/bin/env python3
"""
Connects to Godot's Language Server Protocol (LSP) over TCP sockets
to extract live diagnostics (errors, warnings, hints) for GDScript files.

Three waits, three clocks, rather than one `--timeout` over all three. One
three-second limit for the lot makes the gate's fourth line a coin flip on a
loaded machine:

* the **connect** is retried, because a port `ss` already reports as listening
  can still refuse or reset for a second after the editor opens it, and a
  client that takes the first refusal for an answer says "Please ensure Godot
  Editor is running" about an editor that is running,
* the **handshake** gets a minute of its own. A warm editor takes 2.4 seconds
  to answer `initialize` on an idle machine, so three seconds is not a window,
  it is a margin of six tenths of a second,
* the **diagnostics** wait follows the server rather than the run. Its clock
  restarts on every message, so a slow machine that is still delivering is
  never cut off, and the loop ends the moment the last opened file has been
  answered rather than after a fixed sleep.

The server answers every file it is told to open, clean ones included, so
silence is a fact rather than a shrug: a file left unanswered is named and the
run exits non-zero. Silence read as success is wrong in the dangerous
direction: a window that closes early then reports "No errors or warnings
found" over files it never heard about.

**The answers are read while the files are sent.** The editor answers each
`didOpen` as it comes and stops reading while its own answers wait to be read,
so a client that sends two thousand files before its first read fills both
sockets' buffers and each side waits on the other for good, the editor
spinning at a whole core for as long as anyone lets it.
"""

import asyncio
import json
import os
import sys
import argparse
import re
import socket
import subprocess
from dataclasses import dataclass
from pathlib import Path

import suite_homes


# The five strict warnings, at level 1 in project.godot.
# The server sends no code field, so a warning's name is read from its message,
# "(UNSAFE_CAST): Casting "Variant" to "Vector2" is unsafe.".
STRICT_WARNINGS = (
    "UNTYPED_DECLARATION",
    "UNSAFE_CALL_ARGUMENT",
    "UNSAFE_METHOD_ACCESS",
    "UNSAFE_PROPERTY_ACCESS",
    "UNSAFE_CAST",
)
COUNTED = frozenset()
UNTYPED = frozenset({"UNTYPED_DECLARATION"})
ALL_FIVE = frozenset(STRICT_WARNINGS)
CODE = "code"
SUITES = "suites"


@dataclass(frozen=True)
class ScopeLine:
    """One package of the tree and the strict warnings that fail the run there.

    `paths` are folders relative to sara-godot, space separated. A CODE line
    takes the files outside every `tests` folder and a SUITES line the files
    inside one, and a file belongs to the line of its kind whose path is the
    longest prefix of its own. A strict warning outside `fails` is counted in
    the summary and passes.
    """

    package: str
    paths: str
    kind: str
    fails: frozenset


# The scope table. Every package has a line of its own, each marked COUNTED on
# the day the five went to level 1, and the row that cleans a package flips its
# own line to UNTYPED or ALL_FIVE, so two rows that flip different lines merge
# cleanly. The suites have a line per area group S moves them to. Godot's own
# directory_rules setting includes or excludes every warning of a folder and
# cannot set one warning's level, which is why the scope lives here.
STRICT_SCOPE = (
    ScopeLine("core document half", "core/api core/composite core/layers core/export core/presets core/image core/sad-file core/colors", CODE, ALL_FIVE),
    ScopeLine("core rest", "core", CODE, ALL_FIVE),
    ScopeLine("render", "render", CODE, ALL_FIVE),
    ScopeLine("tools", "tools", CODE, UNTYPED),
    ScopeLine("ui", "ui", CODE, UNTYPED),
    ScopeLine("harness", "harness", CODE, UNTYPED),
    ScopeLine("modules", "modules", CODE, UNTYPED),
    ScopeLine("utils", "utils", CODE, COUNTED),
    ScopeLine("scripts", "scripts", CODE, COUNTED),
    ScopeLine("the rest of the tree", "", CODE, COUNTED),
    ScopeLine("suites of core document half", "core/api core/composite core/layers core/export core/presets core/image core/sad-file core/colors", SUITES, UNTYPED),
    ScopeLine("suites of core rest", "core", SUITES, UNTYPED),
    ScopeLine("suites of dockers and canvas", "ui/dockers ui/widgets ui/brush_editor ui/themes ui/tool_options ui/canvas ui/presets", SUITES, UNTYPED),
    ScopeLine("suites of ui rest", "ui", SUITES, UNTYPED),
    ScopeLine("suites of harness", "harness", SUITES, UNTYPED),
    ScopeLine("suites of render", "render", SUITES, UNTYPED),
    ScopeLine("suites of tools", "tools", SUITES, UNTYPED),
    ScopeLine("suites of utils", "utils", SUITES, UNTYPED),
    ScopeLine("suites of modules", "modules", SUITES, UNTYPED),
    ScopeLine("suites that stay", "tests", SUITES, UNTYPED),
    ScopeLine("suites elsewhere", "", SUITES, COUNTED),
)

_STRICT_NAME = re.compile(r"^\(([A-Z_]+)\):")


def strict_warning_name(message: str) -> str:
    """The strict warning a message carries, or "" for any other message."""
    found = _STRICT_NAME.match(message)
    if found and found.group(1) in STRICT_WARNINGS:
        return found.group(1)
    return ""


_SUITE_HOMES: dict[str, str] = {}


def _suite_homes() -> dict[str, str]:
    """Each suite still waiting for its move, by the path its move gives it.

    A suite `suite_homes.tsv` sends elsewhere belongs to the line of its new
    home from today, so the line of the suites that stay in `tests` holds
    exactly those while the move rows are open, and every new suite there.
    """
    if not _SUITE_HOMES:
        for old, line in suite_homes.read_table().items():
            _SUITE_HOMES[old] = line.destination()
    return _SUITE_HOMES


def scope_line_of(file_path: str, scope=STRICT_SCOPE) -> ScopeLine:
    """The line of the scope table a file, relative to sara-godot, belongs to."""
    parts = [part for part in file_path.replace(os.sep, "/").split("/") if part not in ("", ".")]
    if parts and parts[0] == "sara-godot":
        parts = parts[1:]
    kind = SUITES if "tests" in parts[:-1] else CODE
    rel = "/".join(parts)
    if kind == SUITES:
        rel = _suite_homes().get(rel, rel)
    best = None
    best_length = -1
    for line in scope:
        if line.kind != kind:
            continue
        for path in line.paths.split() or [""]:
            if path and rel != path and not rel.startswith(path + "/"):
                continue
            if len(path) > best_length:
                best, best_length = line, len(path)
    return best


def counted_summary(counted: dict, scope=STRICT_SCOPE) -> str:
    """One line of the strict warnings counted rather than failed, per package."""
    total = sum(sum(codes.values()) for codes in counted.values())
    packages = []
    for line in scope:
        codes = counted.get(line.package)
        if not codes:
            continue
        per_code = ", ".join(
            f"{name.lower()} {codes[name]}" for name in STRICT_WARNINGS if codes.get(name)
        )
        packages.append(f"{line.package} {sum(codes.values())} ({per_code})")
    return f"[LSP Client] Counted, not failing: {total} strict warning(s). " + "; ".join(packages)


SEVERITY_NAMES = {
    1: "ERROR",
    2: "WARNING",
    3: "INFO",
    4: "HINT"
}

# A warm editor answers `initialize` in about 2.4 seconds and every other checkout on the
# machine is importing 780 files at once, so the handshake is given a minute.
DEFAULT_HANDSHAKE_TIMEOUT = 60.0
# Seconds to keep retrying the socket itself. Short, because godot_console.py
# asks the same client for diagnostics when there may be no editor at all and
# should not sit there. check_lsp.sh has just watched the port open, so it
# passes a longer one.
DEFAULT_CONNECT_TIMEOUT = 2.0
# Seconds of complete silence from the server before the diagnostics loop gives
# up. Not a budget for the whole delivery, which took 4.5 seconds for 782 files
# on an idle machine and takes longer under load.
DEFAULT_IDLE_TIMEOUT = 10.0

# The port of the person's own checkout, Godot's default, so an editor they
# already have open on it is found and reused.
MAIN_CHECKOUT_PORT = 6005
# A port the old client also tried after 6005, kept for the main checkout only.
MAIN_CHECKOUT_FALLBACK_PORT = 6008
PROJECT_PATH = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def posix_cksum(data: bytes) -> int:
    """The checksum `cksum` prints, the POSIX CRC over the data and its length."""
    crc = 0
    length = len(data)
    tail = bytearray()
    while length:
        tail.append(length & 0xFF)
        length >>= 8
    for byte in bytes(data) + bytes(tail):
        crc ^= byte << 24
        for _ in range(8):
            crc = ((crc << 1) ^ 0x04C11DB7) if crc & 0x80000000 else (crc << 1)
            crc &= 0xFFFFFFFF
    return crc ^ 0xFFFFFFFF


def _git_dir(project_path: str, which: str) -> str:
    try:
        done = subprocess.run(
            ["git", "-C", project_path, "rev-parse", "--path-format=absolute", which],
            capture_output=True,
            encoding="utf-8",
        )
    except OSError:
        return ""
    return done.stdout.strip() if done.returncode == 0 else ""


def lsp_port(project_path: str = PROJECT_PATH) -> int:
    """The language server port of one checkout, the one place the rule lives.

    The main checkout, whose repository directory is named `sara` and
    is not a linked worktree, uses Godot's default port. Every other checkout,
    a second clone or a worktree, gets a port of its own derived from its
    path, so that two checkouts never read each other's editor. Git offers no
    way to tell a clone from the original, hence the directory name.
    SARA_LSP_PORT overrides. check_lsp.sh asks this function rather than
    keeping a copy of the rule, so the two cannot disagree about which editor a
    checkout talks to.
    """
    override = os.environ.get("SARA_LSP_PORT", "")
    if override:
        return int(override)
    if os.path.basename(os.path.dirname(project_path)) == "sara" and _git_dir(
        project_path, "--git-dir"
    ) == _git_dir(project_path, "--git-common-dir"):
        return MAIN_CHECKOUT_PORT
    return 6100 + posix_cksum(project_path.encode("utf-8")) % 900


def default_ports(project_path: str = PROJECT_PATH) -> list[int]:
    """The ports tried when no --port is given, this checkout's own first."""
    port = lsp_port(project_path)
    if port == MAIN_CHECKOUT_PORT:
        return [port, MAIN_CHECKOUT_FALLBACK_PORT]
    return [port]


def is_listening(port: int, timeout: float = 0.5) -> bool:
    """Whether something accepts a connection on 127.0.0.1 at the port.

    check_lsp.sh asks this through `--listening` rather than reading `ss`,
    which Git Bash does not have: on Windows a script that reads `ss` sees no
    editor and waits out a minute for a port it cannot see. A connect answers
    the same question wherever the gate's Python runs.
    """
    try:
        with socket.create_connection(("127.0.0.1", port), timeout=timeout):
            return True
    except OSError:
        return False


async def read_lsp_message(reader: asyncio.StreamReader):
    headers = {}
    while True:
        line = await reader.readline()
        if not line:
            return None
        line_str = line.decode("ascii", errors="ignore").strip()
        if not line_str:
            break
        if ":" in line_str:
            key, val = line_str.split(":", 1)
            headers[key.strip().lower()] = val.strip()
    
    content_length = int(headers.get("content-length", 0))
    if content_length == 0:
        return None
    
    body = await reader.readexactly(content_length)
    return json.loads(body.decode("utf-8"))


async def send_lsp_message(writer: asyncio.StreamWriter, msg_dict: dict):
    body = json.dumps(msg_dict)
    packet = f"Content-Length: {len(body)}\r\n\r\n{body}"
    writer.write(packet.encode("utf-8"))
    await writer.drain()


async def connect_to_server(ports: list[int], deadline: float):
    """Open a socket to the first port that answers, retrying until the deadline.

    A port that `ss` already reports as listening can still refuse or reset a
    connection while the editor finishes coming up, so a first refusal is no
    proof that no editor is running. With many checkouts running at once it is routine.
    """
    loop = asyncio.get_event_loop()
    while True:
        for port in ports:
            try:
                reader, writer = await asyncio.open_connection("127.0.0.1", port)
                return reader, writer, port
            except (ConnectionRefusedError, ConnectionResetError, OSError):
                continue
        if loop.time() >= deadline:
            return None, None, None
        await asyncio.sleep(0.25)


async def do_handshake(reader, writer, root_dir: str, deadline: float) -> str:
    """Send `initialize` and wait for its answer. "ok", "timeout" or "lost"."""
    loop = asyncio.get_event_loop()
    await send_lsp_message(writer, {
        "jsonrpc": "2.0",
        "id": 1,
        "method": "initialize",
        "params": {
            "processId": os.getpid(),
            "rootUri": f"file://{os.path.abspath(root_dir)}",
            "capabilities": {}
        }
    })

    while True:
        time_left = deadline - loop.time()
        if time_left <= 0:
            return "timeout"
        try:
            resp = await asyncio.wait_for(read_lsp_message(reader), timeout=time_left)
        except asyncio.TimeoutError:
            return "timeout"
        except (ConnectionResetError, asyncio.IncompleteReadError):
            return "lost"
        if resp is None:
            return "lost"
        if resp.get("id") == 1:
            return "ok"


async def collect_diagnostics(reader, pending_uris: set, idle_timeout: float, sent: "asyncio.Event | None" = None) -> dict:
    """Read publishDiagnostics until every opened file has answered.

    The clock follows the server rather than the run: it restarts on every
    message, so delivery that is slow but moving is never cut off, and it only
    runs out when the server has gone completely quiet for `idle_timeout`
    seconds. The loop ends the moment nothing is pending, which on an idle
    machine is sooner than the old fixed window ever was. While `sent` is
    not yet set the client is still sending files, and a quiet server is not
    yet a silent one, so the clock starts again rather than running out.
    """
    loop = asyncio.get_event_loop()
    diagnostics_by_uri = {}
    idle_deadline = loop.time() + idle_timeout
    while pending_uris:
        time_left = idle_deadline - loop.time()
        if time_left <= 0:
            break
        try:
            msg = await asyncio.wait_for(read_lsp_message(reader), timeout=time_left)
        except asyncio.TimeoutError:
            if sent is not None and not sent.is_set():
                idle_deadline = loop.time() + idle_timeout
                continue
            break
        except (ConnectionResetError, asyncio.IncompleteReadError):
            break
        if msg is None:
            break
        idle_deadline = loop.time() + idle_timeout
        if msg.get("method") == "textDocument/publishDiagnostics":
            params = msg.get("params", {})
            uri = params.get("uri")
            if uri in pending_uris:
                diagnostics_by_uri[uri] = params.get("diagnostics", [])
                pending_uris.discard(uri)
    return diagnostics_by_uri


def relative_to(uri: str, root_dir: str) -> str:
    if not uri.startswith("file://"):
        return uri
    file_path = uri[7:]
    try:
        return os.path.relpath(file_path, root_dir)
    except ValueError:
        return file_path


async def run_lsp_client(
    root_dir: str,
    files_to_check: list[str],
    ports: list[int],
    idle_timeout: float,
    connect_timeout: float,
    handshake_timeout: float,
    scope=STRICT_SCOPE,
    show_counted: bool = False,
):
    loop = asyncio.get_event_loop()
    connect_deadline = loop.time() + connect_timeout
    handshake_deadline = loop.time() + handshake_timeout

    reader = writer = None
    while True:
        reader, writer, connected_port = await connect_to_server(ports, connect_deadline)
        if writer is None:
            ports_str = " or ".join(map(str, ports))
            print(f"[LSP Client] Cannot connect to Godot Language Server on port(s): {ports_str}.")
            print("[LSP Client] Please ensure Godot Editor is running and Language Server is enabled.")
            return 1

        print(f"[LSP Client] Connected to Godot Language Server at 127.0.0.1:{connected_port}")
        outcome = await do_handshake(reader, writer, root_dir, handshake_deadline)
        if outcome == "ok":
            break

        writer.close()
        try:
            await writer.wait_closed()
        except (ConnectionResetError, OSError):
            pass
        if outcome == "lost" and loop.time() < connect_deadline:
            # The editor dropped the socket while it was still coming up. One
            # more go, on the same budget the first connect had.
            print("[LSP Client] The server closed the connection during initialization, retrying.")
            continue
        if outcome == "lost":
            print("[LSP Client] The server closed the connection during initialization.")
        else:
            print(
                "[LSP Client] Timed out waiting for server initialization "
                f"after {handshake_timeout:g}s."
            )
        return 1

    await send_lsp_message(writer, {
        "jsonrpc": "2.0",
        "method": "initialized",
        "params": {}
    })

    opened_uris = set()
    to_open = []
    for fpath in files_to_check:
        abs_path = os.path.abspath(fpath)
        uri = f"file://{abs_path}"
        try:
            with open(abs_path, "r", encoding="utf-8") as f:
                content = f.read()
        except OSError as e:
            print(f"[LSP Client] Failed to read {fpath}: {e}")
            continue
        opened_uris.add(uri)
        to_open.append((uri, content))

    # The answers are read while the files are still being sent. The editor
    # answers each file as it reads it, and a client that reads nothing until
    # it has sent every file leaves both socket buffers full, each side waiting
    # on the other to read, with the editor spinning on a core for as long as
    # anyone lets it.
    pending_uris = set(opened_uris)
    sent = asyncio.Event()
    collecting = asyncio.ensure_future(collect_diagnostics(reader, pending_uris, idle_timeout, sent))
    for uri, content in to_open:
        await send_lsp_message(writer, {
            "jsonrpc": "2.0",
            "method": "textDocument/didOpen",
            "params": {
                "textDocument": {
                    "uri": uri,
                    "languageId": "gdscript",
                    "version": 1,
                    "text": content
                }
            }
        })
    sent.set()

    diagnostics_by_uri = await collecting

    writer.close()
    try:
        await writer.wait_closed()
    except (ConnectionResetError, OSError):
        pass

    total_problems = 0
    total_errors = 0
    total_warnings = 0
    counted = {}

    for uri in sorted(opened_uris):
        diags = diagnostics_by_uri.get(uri, [])
        if not diags:
            continue

        file_path = relative_to(uri, root_dir)
        for d in diags:
            sev = d.get("severity", 3)
            strict = strict_warning_name(d.get("message", "")) if sev == 2 else ""
            passes = False
            if strict:
                line_of = scope_line_of(file_path, scope)
                passes = strict not in line_of.fails
            if passes:
                codes = counted.setdefault(line_of.package, {})
                codes[strict] = codes.get(strict, 0) + 1
                if not show_counted:
                    continue
            else:
                total_problems += 1
                if sev == 1:
                    total_errors += 1
                elif sev == 2:
                    total_warnings += 1
            sev_name = "COUNTED" if passes else SEVERITY_NAMES.get(sev, "INFO")

            line = d.get("range", {}).get("start", {}).get("line", 0) + 1
            col = d.get("range", {}).get("start", {}).get("character", 0) + 1
            code = d.get("code", "")
            msg = d.get("message", "")

            code_str = f" [{code}]" if code else ""
            print(f"[{sev_name}]{code_str} {file_path}:{line}:{col}: {msg}")

    # The strict warnings of a package whose line is not flipped yet pass, and
    # are counted on one line so the row that cleans the package can see them.
    if counted:
        print(counted_summary(counted, scope))

    # An unanswered file is not a clean file. The server publishes for every
    # document it is told to open, empty diagnostics included, so a gap here
    # means the run stopped listening before the answer came and the old client
    # would have called those files clean.
    if pending_uris:
        print(
            f"\n[LSP Client] {len(pending_uris)} of {len(opened_uris)} file(s) were never "
            f"answered, after {idle_timeout:g}s of silence. They have not been checked:"
        )
        listed = sorted(relative_to(uri, root_dir) for uri in pending_uris)
        for file_path in listed[:10]:
            print(f"  {file_path}")
        if len(listed) > 10:
            print(f"  ... and {len(listed) - 10} more")
        return max(2 if total_errors > 0 else 1, 1)

    if total_problems == 0:
        print(
            f"[LSP Client] Checked {len(opened_uris)} file(s). No errors or warnings found from Godot LSP"
            + (", beyond the strict warnings counted above." if counted else ".")
        )
        return 0
    print(f"\n[LSP Client] Found {total_errors} error(s) and {total_warnings} warning(s) across {len(opened_uris)} file(s).")
    return 2 if total_errors > 0 else 1


def gd_files_under(paths: list[str]) -> list[str]:
    """Every `.gd` file the paths name or hold, sorted, minus what Godot ignores.

    A folder with a `.gdignore` is not part of the project as far as the editor is
    concerned, its files are never imported and nothing loads them by a `res://`
    path the editor knows, which is how a fixture keeps a script that must not
    parse, a module's test whose base class the zip lacks. The walk leaves the
    folder and everything under it alone for the same reason.
    """
    found: list[str] = []
    for path in paths:
        if os.path.isfile(path) and path.endswith(".gd"):
            found.append(path)
        elif os.path.isdir(path):
            for root, dirs, files in os.walk(path):
                if ".gdignore" in files:
                    dirs.clear()
                    continue
                for name in files:
                    if name.endswith(".gd"):
                        found.append(os.path.join(root, name))
    return sorted(set(found))


def main():
    parser = argparse.ArgumentParser(description="Check GDScript files for errors using Godot LSP.")
    parser.add_argument("paths", nargs="*", default=["."], help="Files or directories to check (default: current directory)")
    parser.add_argument(
        "--port",
        type=int,
        help="Specific port to connect to (default: this checkout's own, as check_lsp.sh picks it)",
    )
    parser.add_argument(
        "--which-port",
        metavar="PROJECT",
        help="Print the language server port of the checkout at PROJECT and exit",
    )
    parser.add_argument(
        "--listening",
        type=int,
        metavar="PORT",
        help="Exit 0 when something accepts a connection on 127.0.0.1 at PORT, 1 when not",
    )
    parser.add_argument(
        "--timeout",
        type=float,
        default=DEFAULT_IDLE_TIMEOUT,
        help=(
            "Seconds of silence from the server before the diagnostics wait gives up. "
            "The clock restarts on every message, so this is an idle timeout and not a "
            f"budget for the whole delivery (default: {DEFAULT_IDLE_TIMEOUT:g})"
        ),
    )
    parser.add_argument(
        "--connect-timeout",
        type=float,
        default=DEFAULT_CONNECT_TIMEOUT,
        help=f"Seconds to keep retrying the socket itself (default: {DEFAULT_CONNECT_TIMEOUT:g})",
    )
    parser.add_argument(
        "--handshake-timeout",
        type=float,
        default=DEFAULT_HANDSHAKE_TIMEOUT,
        help=(
            "Seconds to wait for the initialize response, which a warm editor answers in "
            f"about 2.4 and a loaded one in far more (default: {DEFAULT_HANDSHAKE_TIMEOUT:g})"
        ),
    )
    parser.add_argument(
        "--show-counted",
        action="store_true",
        help=(
            "Print each strict warning the scope table counts rather than fails, "
            "as a row cleaning a package wants to see them"
        ),
    )
    args = parser.parse_args()

    if args.which_port is not None:
        print(lsp_port(args.which_port))
        sys.exit(0)
    if args.listening is not None:
        sys.exit(0 if is_listening(args.listening) else 1)

    ports = [args.port] if args.port else default_ports()

    files_to_check = gd_files_under(args.paths)
    if not files_to_check:
        print("No .gd files found to check.")
        sys.exit(0)

    root_dir = os.getcwd()
    exit_code = asyncio.run(
        run_lsp_client(
            root_dir,
            files_to_check,
            ports,
            args.timeout,
            args.connect_timeout,
            args.handshake_timeout,
            show_counted=args.show_counted,
        )
    )
    sys.exit(exit_code)


if __name__ == "__main__":
    main()
