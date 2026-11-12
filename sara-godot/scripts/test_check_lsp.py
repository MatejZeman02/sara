"""The three clocks of the LSP client, over a language server that is not Godot.

    cd sara-godot && PYTHONPATH=scripts python3 -m unittest scripts.test_check_lsp

The failure covered is the gate's fourth line reading red on a clean tree, once every
two runs on a loaded machine. One number, `--timeout`, defaulting to three
seconds, covered the socket, the `initialize` handshake and the whole delivery
of diagnostics for 782 files, and a warm editor takes 2.4 seconds to answer the
handshake alone. The three are separate clocks now, and this suite is what says
so without needing an editor: a fake server on a loopback port can be told to
answer late, to dribble, to drop the first connection or to stay silent about
one file, which is what the real one does under load and what no test could ask
of it.

The silent half matters more than the red half. A window that closed early used
to print "No errors or warnings found" over every file it had not heard about,
so the check could pass on a tree with a parse error in it. `test_unanswered_*`
is that case.

Needs no Godot, no GPU and no weston.
"""

from __future__ import annotations

import asyncio
import contextlib
import io
import os
import shutil
import socket
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

import check_lsp_errors as lsp
import shell_script


CLEAN = "extends Node\n"


class FakeLanguageServer:
    """A loopback server that speaks just enough LSP to drive the client.

    Every knob is a face of that failure. `initialize_delay` is the handshake a loaded
    editor answers late, `publish_gap` is delivery that is slow but moving,
    `withhold` is a file the server never answers about, `drop_first`
    is the connection reset the client used to die on with a traceback, and
    `answer_bytes` pads every answer, as a tree full of warnings makes the
    editor's long.
    """

    def __init__(
        self,
        *,
        initialize_delay: float = 0.0,
        publish_gap: float = 0.0,
        withhold: tuple[str, ...] = (),
        diagnostics: dict[str, list] | None = None,
        drop_first: int = 0,
        answer_bytes: int = 0,
    ) -> None:
        self._initialize_delay = initialize_delay
        self._publish_gap = publish_gap
        self._withhold = set(withhold)
        self._diagnostics = diagnostics or {}
        self._drop_first = drop_first
        self._answer_bytes = answer_bytes
        self._server = None
        self.port = 0
        self.connections = 0
        self.opened: list[str] = []

    async def start(self, port: int = 0) -> None:
        self._server = await asyncio.start_server(self._handle, "127.0.0.1", port)
        self.port = self._server.sockets[0].getsockname()[1]

    async def serve_forever(self) -> None:
        async with self._server:
            await self._server.serve_forever()

    async def stop(self) -> None:
        if self._server is None:
            return
        self._server.close()
        # No wait_closed: a handler deliberately asleep past the client's
        # deadline would hold the suite there for as long as it sleeps.

    async def _handle(self, reader, writer) -> None:
        self.connections += 1
        try:
            if self.connections <= self._drop_first:
                return
            while True:
                msg = await lsp.read_lsp_message(reader)
                if msg is None:
                    return
                await self._answer(writer, msg)
        except (ConnectionResetError, asyncio.IncompleteReadError, OSError):
            return
        finally:
            writer.close()

    async def _answer(self, writer, msg: dict) -> None:
        method = msg.get("method")
        if method == "initialize":
            await asyncio.sleep(self._initialize_delay)
            await lsp.send_lsp_message(
                writer,
                {"jsonrpc": "2.0", "id": msg.get("id"), "result": {"capabilities": {}}},
            )
        elif method == "textDocument/didOpen":
            uri = msg["params"]["textDocument"]["uri"]
            self.opened.append(uri)
            name = os.path.basename(uri)
            if self._publish_gap:
                await asyncio.sleep(self._publish_gap)
            if name in self._withhold:
                return
            await lsp.send_lsp_message(
                writer,
                {
                    "jsonrpc": "2.0",
                    "method": "textDocument/publishDiagnostics",
                    "params": {
                        "uri": uri,
                        "diagnostics": self._diagnostics.get(name, []),
                        "padding": "x" * self._answer_bytes,
                    },
                },
            )


def an_error(message: str = "Unterminated string.") -> dict:
    return {
        "severity": 1,
        "message": message,
        "range": {"start": {"line": 4, "character": 12}},
    }


class ClientCase(unittest.IsolatedAsyncioTestCase):
    """A temporary tree of clean .gd files and a fake server in front of it."""

    file_count = 4

    async def asyncSetUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)
        self.files = []
        for i in range(self.file_count):
            path = self.root / f"file_{i}.gd"
            path.write_text(CLEAN, encoding="utf-8")
            self.files.append(str(path))
        self.server: FakeLanguageServer | None = None

    async def asyncTearDown(self) -> None:
        if self.server is not None:
            await self.server.stop()
        self._tmp.cleanup()

    async def serve(self, **kwargs) -> FakeLanguageServer:
        self.server = FakeLanguageServer(**kwargs)
        await self.server.start()
        return self.server

    async def run_client(
        self,
        *,
        port: int | None = None,
        idle_timeout: float = 1.0,
        connect_timeout: float = 1.0,
        handshake_timeout: float = 5.0,
        scope=lsp.STRICT_SCOPE,
    ) -> tuple[int, str]:
        if port is None:
            port = self.server.port
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = await lsp.run_lsp_client(
                str(self.root),
                self.files,
                [port],
                idle_timeout,
                connect_timeout,
                handshake_timeout,
                scope,
            )
        return code, out.getvalue()


class TestCleanTree(ClientCase):
    async def test_a_clean_tree_is_clean(self):
        await self.serve()
        code, out = await self.run_client()
        self.assertEqual(code, 0)
        self.assertIn(f"Checked {self.file_count} file(s)", out)

    async def test_an_error_is_reported_and_fails(self):
        await self.serve(diagnostics={"file_2.gd": [an_error()]})
        code, out = await self.run_client()
        self.assertEqual(code, 2)
        self.assertIn("[ERROR]", out)
        self.assertIn("file_2.gd:5:13", out)


class TestHandshakeClock(ClientCase):
    async def test_a_late_handshake_is_waited_for(self):
        # The whole failure: 0.6s to answer is longer than the diagnostics wait,
        # and under one shared number that was a red gate on a clean tree.
        await self.serve(initialize_delay=0.6)
        code, out = await self.run_client(idle_timeout=0.2, handshake_timeout=5.0)
        self.assertEqual(code, 0)
        self.assertNotIn("Timed out waiting for server initialization", out)

    async def test_a_handshake_that_never_answers_still_gives_up(self):
        await self.serve(initialize_delay=2.0)
        code, out = await self.run_client(handshake_timeout=0.3)
        self.assertEqual(code, 1)
        self.assertIn("Timed out waiting for server initialization", out)

    async def test_a_dropped_connection_is_retried(self):
        server = await self.serve(drop_first=1)
        code, out = await self.run_client(connect_timeout=2.0)
        self.assertEqual(code, 0)
        self.assertGreaterEqual(server.connections, 2)
        self.assertIn("retrying", out)


class TestConnectClock(ClientCase):
    async def test_a_port_that_opens_late_is_waited_for(self):
        # ss reports the port listening a moment before the editor accepts on
        # it, and the old client took the first refusal as no editor at all.
        server = FakeLanguageServer()
        await server.start()
        port = server.port
        await server.stop()
        self.server = None

        async def open_late():
            await asyncio.sleep(0.4)
            self.server = FakeLanguageServer()
            await self.server.start(port)

        later = asyncio.create_task(open_late())
        code, _ = await self.run_client(port=port, connect_timeout=5.0)
        await later
        self.assertEqual(code, 0)

    async def test_nothing_listening_still_says_so(self):
        server = FakeLanguageServer()
        await server.start()
        port = server.port
        await server.stop()
        self.server = None
        code, out = await self.run_client(port=port, connect_timeout=0.2)
        self.assertEqual(code, 1)
        self.assertIn("Please ensure Godot Editor is running", out)


class TestDiagnosticsClock(ClientCase):
    file_count = 10

    async def test_slow_delivery_is_not_cut_off(self):
        # Ten files at 0.15s each is 1.5s of delivery through a 0.9s wait, so a
        # budget for the whole run would cut it off and an idle clock does not.
        # The margin is per gap and not per run, six times what the server
        # takes, because a loaded machine is what this whole unit is about.
        await self.serve(publish_gap=0.15)
        code, out = await self.run_client(idle_timeout=0.9)
        self.assertEqual(code, 0)
        self.assertIn(f"Checked {self.file_count} file(s)", out)

    async def test_unanswered_files_fail_rather_than_read_as_clean(self):
        await self.serve(withhold=("file_3.gd",))
        code, out = await self.run_client(idle_timeout=0.8)
        self.assertNotEqual(code, 0)
        self.assertIn("never answered", out)
        self.assertIn("file_3.gd", out)
        self.assertNotIn("No errors or warnings found", out)

    async def test_an_unanswered_file_beside_an_error_keeps_the_error(self):
        await self.serve(
            withhold=("file_3.gd",), diagnostics={"file_1.gd": [an_error()]}
        )
        code, out = await self.run_client(idle_timeout=0.8)
        self.assertEqual(code, 2)
        self.assertIn("[ERROR]", out)
        self.assertIn("never answered", out)


class TestLongAnswers(ClientCase):
    file_count = 120

    async def asyncSetUp(self) -> None:
        await super().asyncSetUp()
        for path in self.files:
            Path(path).write_text(CLEAN + "#" * 200_000 + "\n", encoding="utf-8")

    async def test_answers_are_read_while_the_files_are_still_being_sent(self):
        # 24 MB each way, past what the two sockets' buffers hold. The server
        # answers every file before it reads the next, as the editor does, so a
        # client that sent every file before reading one waited on it for good.
        await self.serve(answer_bytes=200_000)
        code, out = await asyncio.wait_for(self.run_client(idle_timeout=5.0), timeout=30)
        self.assertEqual(code, 0)
        self.assertIn(f"Checked {self.file_count} file(s)", out)


def a_warning(name: str, message: str = "Casting \"Variant\" to \"Vector2\" is unsafe.") -> dict:
    return {
        "severity": 2,
        "message": f"({name}): {message}",
        "range": {"start": {"line": 2, "character": 4}},
    }


# The table as it will stand once `core`'s document half is typed: its code
# fails an untyped declaration, and everything else still counts.
# The table with the document half flipped and every other line counted,
# whatever the live table has flipped since.
DOCUMENT_TYPED = tuple(
    lsp.ScopeLine(line.package, line.paths, line.kind, lsp.UNTYPED if line.package == "core document half" else lsp.COUNTED)
    for line in lsp.STRICT_SCOPE
)


class TestStrictScope(ClientCase):
    """The five strict warnings fail only where their package is clean."""

    file_count = 0

    async def asyncSetUp(self) -> None:
        await super().asyncSetUp()
        for rel in (
            "core/api/layer_stack.gd",
            "ui/dockers/layers_docker.gd",
            "tests/test_layers.gd",
            "core/pen/sa_pen.gd",
            "render/sa_canvas.gd",
        ):
            path = self.root / rel
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(CLEAN, encoding="utf-8")
            self.files.append(str(path))

    async def test_a_strict_warning_out_of_scope_passes_with_its_count(self):
        await self.serve(
            diagnostics={
                "layers_docker.gd": [a_warning("UNSAFE_CAST"), a_warning("UNSAFE_CAST")],
                "test_layers.gd": [a_warning("UNTYPED_DECLARATION")],
            }
        )
        code, out = await self.run_client(scope=DOCUMENT_TYPED)
        self.assertEqual(code, 0, out)
        self.assertNotIn("[WARNING]", out)
        self.assertIn("Counted, not failing: 3 strict warning(s)", out)
        self.assertIn("ui 2 (unsafe_cast 2)", out)
        self.assertIn("suites that stay 1 (untyped_declaration 1)", out)

    async def test_a_strict_warning_in_scope_fails(self):
        await self.serve(diagnostics={"layer_stack.gd": [a_warning("UNTYPED_DECLARATION")]})
        code, out = await self.run_client(scope=DOCUMENT_TYPED)
        self.assertEqual(code, 1)
        self.assertIn("[WARNING] core/api/layer_stack.gd:3:5: (UNTYPED_DECLARATION)", out)

    async def test_a_flipped_line_still_counts_the_codes_it_does_not_name(self):
        await self.serve(diagnostics={"layer_stack.gd": [a_warning("UNSAFE_CAST")]})
        code, out = await self.run_client(scope=DOCUMENT_TYPED)
        self.assertEqual(code, 0, out)
        self.assertIn("core document half 1 (unsafe_cast 1)", out)

    async def test_the_rest_of_core_and_render_fail_all_five(self):
        # Both lines are flipped, so an unsafe access there fails the run on the
        # table as it stands, while the same warning in `ui` is still counted.
        await self.serve(
            diagnostics={
                "sa_pen.gd": [a_warning("UNSAFE_CALL_ARGUMENT")],
                "sa_canvas.gd": [a_warning("UNSAFE_CAST")],
                "layers_docker.gd": [a_warning("UNSAFE_CAST")],
            }
        )
        code, out = await self.run_client()
        self.assertEqual(code, 1)
        self.assertIn("[WARNING] core/pen/sa_pen.gd:3:5: (UNSAFE_CALL_ARGUMENT)", out)
        self.assertIn("[WARNING] render/sa_canvas.gd:3:5: (UNSAFE_CAST)", out)
        self.assertIn("ui 1 (unsafe_cast 1)", out)

    async def test_an_ordinary_warning_fails_anywhere(self):
        ordinary = a_warning("UNUSED_VARIABLE", "The local variable \"x\" is declared but never used.")
        await self.serve(diagnostics={"layers_docker.gd": [ordinary]})
        code, out = await self.run_client()
        self.assertEqual(code, 1)
        self.assertIn("(UNUSED_VARIABLE)", out)

    async def test_an_error_fails_anywhere(self):
        await self.serve(diagnostics={"test_layers.gd": [an_error()]})
        code, _ = await self.run_client()
        self.assertEqual(code, 2)


class TestScopeTable(unittest.TestCase):
    def test_every_file_finds_the_line_of_its_package(self):
        cases = {
            "core/api/brush/sa_brush.gd": "core document half",
            "./core/sad-file/sa_sad_reader.gd": "core document half",
            "core/pen/sa_pen.gd": "core rest",
            "render/sa_canvas.gd": "render",
            "ui/dockers/layers/sa_layers_docker.gd": "ui",
            "modules/sara-base-modules/base/filters/blur.gd": "modules",
            "tests/test_layers.gd": "suites that stay",
            "tests/fixtures/sa_fake_door.gd": "suites that stay",
            "tests/test_hard_rules.gd": "suites that stay",
            "tests/test_a2_frame_pacer.gd": "suites of render",
            "tests/test_a2_scratchpad_follows_the_width.gd": "suites of dockers and canvas",
            "core/layers/tests/test_layer_stack.gd": "suites of core document half",
            "core/pen/tests/test_pen.gd": "suites of core rest",
            "ui/canvas/tests/test_canvas.gd": "suites of dockers and canvas",
            "ui/menus/tests/test_menus.gd": "suites of ui rest",
            "modules/sara-base-modules/base/tests/test_blur.gd": "suites of modules",
            "sara-godot/harness/sa_capture.gd": "harness",
            "geditor/new_folder.gd": "the rest of the tree",
        }
        for path, package in cases.items():
            with self.subTest(path=path):
                self.assertEqual(lsp.scope_line_of(path).package, package)

    def test_every_package_has_one_line_naming_only_the_five(self):
        packages = [line.package for line in lsp.STRICT_SCOPE]
        self.assertEqual(len(packages), len(set(packages)))
        for line in lsp.STRICT_SCOPE:
            self.assertLessEqual(line.fails, lsp.ALL_FIVE, line.package)

    def test_the_five_are_at_level_one_in_the_project(self):
        project = (Path(lsp.PROJECT_PATH) / "project.godot").read_text(encoding="utf-8")
        for name in lsp.STRICT_WARNINGS:
            self.assertIn(f"gdscript/warnings/{name.lower()}=1", project)

    def test_only_the_five_are_read_from_a_message(self):
        self.assertEqual(lsp.strict_warning_name("(UNSAFE_CAST): Casting."), "UNSAFE_CAST")
        self.assertEqual(lsp.strict_warning_name("(UNUSED_VARIABLE): x."), "")
        self.assertEqual(lsp.strict_warning_name("Unterminated string."), "")


# A fake language server standing where the headless editor goes, so
# check_lsp.sh can be run end to end on a machine with no Godot on it. It takes
# the editor's own arguments and answers on the port it is handed.
STUB = """#!/usr/bin/env python3
import asyncio, sys

sys.path.insert(0, {scripts!r})
import test_check_lsp as suite

port = int(sys.argv[sys.argv.index("--lsp-port") + 1])


async def main():
    server = suite.FakeLanguageServer()
    await server.start(port)
    await server.serve_forever()


asyncio.run(main())
"""


@shell_script.runs_here()
class ShellCase(unittest.TestCase):
    """A scratch tree of clean files, the fake editor and a free port for it."""

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        root = Path(self._tmp.name)
        for i in range(3):
            (root / f"file_{i}.gd").write_text(CLEAN, encoding="utf-8")
        self.root = root
        scripts = str(Path(__file__).resolve().parent)
        self.stub = root / "fake_editor.py"
        self.stub.write_text(STUB.format(scripts=scripts), encoding="utf-8")
        self.stub.chmod(0o755)
        with socket.socket() as s:
            s.bind(("127.0.0.1", 0))
            self.port = s.getsockname()[1]

    def tearDown(self):
        self._tmp.cleanup()

    def run_shell(self, path=None):
        env = dict(os.environ)
        env["SARA_LSP_PORT"] = str(self.port)
        env["GODOT_BIN_OVERRIDE"] = str(self.stub)
        if path is not None:
            env["PATH"] = path
        script = Path(__file__).resolve().parent / "check_lsp.sh"
        return subprocess.run(
            shell_script.command(script),
            cwd=str(self.root),
            env=env,
            capture_output=True,
            encoding="utf-8",
            timeout=120,
        )


class TestTheShellAroundIt(ShellCase):
    """check_lsp.sh itself, over a fake editor, twice in a row.

    Two bugs came out of proving the handshake clock and this covers one of them. The trap that
    waits for the editor lost the exit code, because `set -e` is on and a
    `kill -9` on a process that has already gone is a failed simple command
    inside an EXIT trap: ten clean runs under load reported 782 files checked
    and exited 1. Dropping either `|| true` fails this test.

    The other bug is the wait itself. The trap used to send SIGTERM and return
    at once, so `ss` still reported the dying editor's port as listening and the
    next run attached to a corpse, which took five of ten runs under load and
    alternated exactly. **Removing the wait does not fail this test**, and that
    was checked rather than assumed: the fake editor here dies the instant it is
    signalled, so the window the real one leaves open does not exist. Nothing
    short of a loaded machine and a real editor reproduces it, and the reading
    that does is in the unit's folder.
    """

    def test_two_runs_in_a_row_are_both_green(self):
        first = self.run_shell()
        self.assertEqual(first.returncode, 0, first.stdout + first.stderr)
        self.assertIn("Checked 3 file(s)", first.stdout)
        second = self.run_shell()
        self.assertEqual(second.returncode, 0, second.stdout + second.stderr)
        self.assertIn("Checked 3 file(s)", second.stdout)
        # The second run started its own editor rather than finding the first
        # one's still holding the port.
        self.assertIn("starting a headless editor", second.stdout)


# What check_lsp.sh and the fake editor call, and nothing else. Git Bash has
# every one of these and no `ss`, which is the PATH the cases below stand in.
SHELL_TOOLS = ("bash", "dirname", "seq", "sleep", "mkdir", "rm", "env")


class TestAPathWithoutSs(ShellCase):
    """check_lsp.sh finds the editor on a PATH that holds no `ss`.

    `listening()` ran `ss -ltn`, which Git Bash does not have, so on Windows it
    answered no every time: the script started a second editor beside the
    painter's, waited sixty seconds for a port it could not see and reported
    that the editor never opened it. Put `ss` back in `listening()` and both
    cases fail, the first on the line it prints and the second after the wait.
    """

    def setUp(self):
        super().setUp()
        bin_dir = self.root / "bin"
        bin_dir.mkdir()
        for tool in SHELL_TOOLS:
            found = shutil.which(tool)
            self.assertIsNotNone(found, f"{tool} is not on PATH")
            (bin_dir / tool).symlink_to(found)
        # The fake editor's `#!/usr/bin/env python3` and the script's fallback
        # when the checkout has no .conda both want python3 by name.
        (bin_dir / "python3").symlink_to(sys.executable)
        self.path = str(bin_dir)
        self.assertIsNone(shutil.which("ss", path=self.path))
        self.editor = None

    def tearDown(self):
        if self.editor is not None:
            self.editor.kill()
            self.editor.wait()
        super().tearDown()

    def test_an_editor_already_listening_is_found_and_used(self):
        self.editor = subprocess.Popen(
            [sys.executable, str(self.stub), "--lsp-port", str(self.port)],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        deadline = time.monotonic() + 30
        while not lsp.is_listening(self.port):
            self.assertLess(time.monotonic(), deadline, "the fake editor never listened")
            time.sleep(0.1)
        # The override names nothing, so a run that started an editor of its
        # own could not get one and would fail rather than pass by luck.
        self.stub.unlink()
        run = self.run_shell(self.path)
        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
        self.assertIn(f"using the editor already listening on {self.port}", run.stdout)
        self.assertIn("Checked 3 file(s)", run.stdout)

    def test_an_editor_it_starts_is_seen_opening_its_port(self):
        started = time.monotonic()
        run = self.run_shell(self.path)
        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
        self.assertIn("starting a headless editor", run.stdout)
        self.assertIn("Checked 3 file(s)", run.stdout)
        # Seen at once, not after the minute a blind wait runs out.
        self.assertLess(time.monotonic() - started, 30)


class TestTheListeningFlag(unittest.TestCase):
    def test_a_closed_port_is_not_listening(self):
        with socket.socket() as s:
            s.bind(("127.0.0.1", 0))
            port = s.getsockname()[1]
        self.assertFalse(lsp.is_listening(port))

    def test_an_open_port_is_listening(self):
        with socket.socket() as s:
            s.bind(("127.0.0.1", 0))
            s.listen()
            self.assertTrue(lsp.is_listening(s.getsockname()[1]))


class TestDefaults(unittest.TestCase):
    def test_the_handshake_is_the_longest_clock(self):
        self.assertGreater(lsp.DEFAULT_HANDSHAKE_TIMEOUT, lsp.DEFAULT_IDLE_TIMEOUT)
        self.assertGreater(lsp.DEFAULT_IDLE_TIMEOUT, lsp.DEFAULT_CONNECT_TIMEOUT)

    def test_the_shell_hands_the_client_a_longer_connect(self):
        text = (Path(__file__).resolve().parent / "check_lsp.sh").read_text(encoding="utf-8")
        self.assertIn("--connect-timeout 30", text)


if __name__ == "__main__":
    unittest.main()
