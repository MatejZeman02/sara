"""The gate's style line, over tools that are not gdtoolkit.

    cd sara-godot && PYTHONPATH=scripts python3 -m unittest scripts.test_check_style

The failure covered is a gate that went red with nothing printed. The lint
line was a bare `.conda/bin/gdlint` over the whole tree, and a bare command has
exactly one channel: a non-zero exit. Killed by SIGTERM it answers 143 and says
nothing, killed by the OOM killer it answers 137 and says nothing, and given
one bad name it answers 1 and names the rule. A reader of the gate cannot tell
the three apart, so a machine under load reads as a dirty tree.

`check_style.sh` is where the difference now lives, and this suite is what says
so without needing gdtoolkit: a fake `gdformat` and a fake `gdlint` on a
temporary path can be told to pass, to fail, to die by a signal or not to exist
at all, which is what the real ones do under load and what no test could ask of
them.

The last case is the other half of the filing. The gate block is copied into
five files, and the fix is only a fix in the ones that carry it, so the suite
reads all five and fails when one drifts.

Needs no Godot, no GPU and no gdtoolkit.
"""

from __future__ import annotations

import os
import shutil
import signal
import subprocess
import tempfile
import time
import unittest
from pathlib import Path

import shell_script


SARA_GODOT = Path(__file__).resolve().parent.parent
REPO_ROOT = SARA_GODOT.parent
CHECK_STYLE = SARA_GODOT / "scripts" / "check_style.sh"

# Every file that quotes the gate for someone to run. The filing's argument for
# one script rather than two commands is that these five drift, so they are
# named here rather than globbed: a new copy should fail this suite until
# somebody decides it is a copy.
GATE_COPIES = (
    "AGENTS.md",
    "docs/agents/BRIEF.md",
    "docs/agents/UNATTENDED.md",
    "docs/guides/TESTING.md",
    ".claude/agents/qa-gate.md",
)


def fake_tool(path: Path, body: str) -> None:
    """Write an executable shell stub where a gdtoolkit binary would be."""
    shell_script.stand_in(path, body)


PASS = 'echo "$(basename "$0") ok"\nexit 0\n'
COMPLAIN = 'echo "$(basename "$0") found a problem" >&2\nexit 1\n'
DIE_TERM = "kill -TERM $$\n"
DIE_KILL = "kill -KILL $$\n"
DIE_ODD = "exit 250\n"
ECHO_ARGS = 'printf "%s\\n" "$@"\nexit 0\n'


@shell_script.runs_here()
class CheckStyleCase(unittest.TestCase):
    """A run of check_style.sh with the two tools under this test's control."""

    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.bin_dir = Path(self._tmp.name)
        self.addCleanup(self._tmp.cleanup)
        fake_tool(self.bin_dir / "gdformat", PASS)
        fake_tool(self.bin_dir / "gdlint", PASS)

    def run_check(self, *paths: str, timeout: float = 60.0) -> subprocess.CompletedProcess:
        env = dict(os.environ, GDTOOLKIT_BIN_DIR=str(self.bin_dir))
        return subprocess.run(
            shell_script.command(CHECK_STYLE, *paths),
            cwd=SARA_GODOT,
            env=env,
            capture_output=True,
            encoding="utf-8",
            timeout=timeout,
        )


class TestAVerdict(CheckStyleCase):
    """0 and 1 are the two answers about the tree, and they still work."""

    def test_both_tools_happy_is_zero(self) -> None:
        done = self.run_check("core/api/document/sa_document.gd")
        self.assertEqual(done.returncode, 0, done.stderr)

    def test_a_complaint_from_gdformat_is_one(self) -> None:
        fake_tool(self.bin_dir / "gdformat", COMPLAIN)
        done = self.run_check("core/api/document/sa_document.gd")
        self.assertEqual(done.returncode, 1, done.stderr)
        self.assertIn("gdformat exited 1", done.stderr)

    def test_a_complaint_from_gdlint_is_one(self) -> None:
        fake_tool(self.bin_dir / "gdlint", COMPLAIN)
        done = self.run_check("core/api/document/sa_document.gd")
        self.assertEqual(done.returncode, 1, done.stderr)
        self.assertIn("gdlint exited 1", done.stderr)

    def test_what_the_tool_said_is_kept(self) -> None:
        fake_tool(self.bin_dir / "gdlint", COMPLAIN)
        done = self.run_check("core/api/document/sa_document.gd")
        self.assertIn("gdlint found a problem", done.stderr)

    def test_both_tools_run_even_when_the_first_complains(self) -> None:
        fake_tool(self.bin_dir / "gdformat", COMPLAIN)
        fake_tool(self.bin_dir / "gdlint", COMPLAIN)
        done = self.run_check("core/api/document/sa_document.gd")
        self.assertIn("gdformat found a problem", done.stderr)
        self.assertIn("gdlint found a problem", done.stderr)


class TestADeath(CheckStyleCase):
    """The case the filing is about: killed is not the same as dirty."""

    def test_a_tool_killed_by_term_is_two(self) -> None:
        fake_tool(self.bin_dir / "gdlint", DIE_TERM)
        done = self.run_check("core/api/document/sa_document.gd")
        self.assertEqual(done.returncode, 2, done.stderr)

    def test_a_tool_killed_by_term_names_the_signal(self) -> None:
        fake_tool(self.bin_dir / "gdlint", DIE_TERM)
        done = self.run_check("core/api/document/sa_document.gd")
        self.assertIn("SIGTERM", done.stderr)
        self.assertIn("143", done.stderr)

    def test_a_tool_killed_by_kill_names_the_signal(self) -> None:
        fake_tool(self.bin_dir / "gdlint", DIE_KILL)
        done = self.run_check("core/api/document/sa_document.gd")
        self.assertEqual(done.returncode, 2, done.stderr)
        self.assertIn("SIGKILL", done.stderr)
        self.assertIn("137", done.stderr)

    def test_a_death_says_nothing_was_decided(self) -> None:
        fake_tool(self.bin_dir / "gdlint", DIE_TERM)
        done = self.run_check("core/api/document/sa_document.gd")
        self.assertIn("Nothing was decided", done.stderr)

    def test_a_high_code_no_signal_claims_is_still_two(self) -> None:
        """250 is above 128 and 122 is no signal, so the number stands in."""
        fake_tool(self.bin_dir / "gdlint", DIE_ODD)
        done = self.run_check("core/api/document/sa_document.gd")
        self.assertEqual(done.returncode, 2, done.stderr)
        self.assertIn("signal 122", done.stderr)

    def test_a_death_outranks_a_verdict(self) -> None:
        """A run that did not check the whole tree is not a green from the rest."""
        fake_tool(self.bin_dir / "gdformat", COMPLAIN)
        fake_tool(self.bin_dir / "gdlint", DIE_TERM)
        done = self.run_check("core/api/document/sa_document.gd")
        self.assertEqual(done.returncode, 2, done.stderr)

    @unittest.skipIf(shell_script.on_windows(), "Windows has no os.killpg to signal the script's process group")
    def test_the_script_killed_itself_says_so(self) -> None:
        """A signal at the process group takes the wrapper too, and it speaks.

        The stub touches a file before it sleeps and the test waits for it,
        because a signal sent the instant after `Popen` returns can arrive
        before bash has read its own `trap` line, and then the shell dies on
        the default action with nothing installed to say so. That race is why
        the traps sit at the top of the script rather than beside the loop, and
        waiting here is what makes this case about the handler instead of about
        who won a microsecond.
        """
        started = self.bin_dir / "started"
        fake_tool(self.bin_dir / "gdformat", f'touch "{started}"\nsleep 30\n')
        env = dict(os.environ, GDTOOLKIT_BIN_DIR=str(self.bin_dir))
        proc = subprocess.Popen(
            shell_script.command(CHECK_STYLE, "core/api/document/sa_document.gd"),
            cwd=SARA_GODOT,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            encoding="utf-8",
            start_new_session=True,
        )
        for _ in range(300):
            if started.exists():
                break
            time.sleep(0.05)
        self.assertTrue(started.exists(), "the fake gdformat never ran")
        # The group and not the process, which is the shape of the real death:
        # a loaded machine signals everything in the gate's group at once, and
        # the wrapper and the tool both get it. It also takes the stub down,
        # so this case does not sit out a thirty second sleep to find out.
        os.killpg(proc.pid, signal.SIGTERM)
        _, err = proc.communicate(timeout=60)
        self.assertEqual(proc.returncode, 2, err)
        self.assertIn("killed by SIGTERM", err)


class TestNoTool(CheckStyleCase):
    """A missing gdtoolkit is a machine problem, so it is a 2 and not a 1."""

    def test_a_missing_tool_is_two(self) -> None:
        (self.bin_dir / "gdlint").unlink()
        done = self.run_check("core/api/document/sa_document.gd")
        self.assertEqual(done.returncode, 2, done.stderr)

    def test_a_missing_tool_says_where_it_looked(self) -> None:
        (self.bin_dir / "gdlint").unlink()
        done = self.run_check("core/api/document/sa_document.gd")
        self.assertIn(str(self.bin_dir), done.stderr)
        self.assertIn("GDTOOLKIT_BIN_DIR", done.stderr)


@shell_script.runs_here()
class TestAWorktreesEnv(unittest.TestCase):
    """A scratch worktree has no `.conda` of its own, so the script borrows.

    Unlike CheckStyleCase's fixture, this needs a real git repository: the
    script finds the main checkout through `git worktree list`, which answers
    nothing over a bare directory of files.
    """

    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        root = Path(self._tmp.name)
        self.main = root / "main"
        self.main.mkdir()
        for args in (
            ["git", "init", "-q"],
            ["git", "config", "user.email", "test@example.com"],
            ["git", "config", "user.name", "Test"],
        ):
            subprocess.run(args, cwd=self.main, check=True)
        script_dir = self.main / "sara-godot" / "scripts"
        script_dir.mkdir(parents=True)
        shutil.copy(CHECK_STYLE, script_dir / "check_style.sh")
        (script_dir / "check_style.sh").chmod(0o755)
        core_dir = self.main / "sara-godot" / "core"
        core_dir.mkdir()
        (core_dir / "sa_document.gd").write_text("# stub\n", encoding="utf-8")
        subprocess.run(["git", "add", "-A"], cwd=self.main, check=True)
        subprocess.run(["git", "commit", "-q", "-m", "init"], cwd=self.main, check=True)
        self.worktree = root / "worktree"
        subprocess.run(
            ["git", "worktree", "add", "-q", str(self.worktree), "-b", "side"],
            cwd=self.main,
            check=True,
        )
        self.main_bin = self.main / "sara-godot" / ".conda" / "bin"
        self.main_bin.mkdir(parents=True)
        fake_tool(self.main_bin / "gdformat", PASS)
        fake_tool(self.main_bin / "gdlint", PASS)
        self.worktree_bin = self.worktree / "sara-godot" / ".conda" / "bin"

    def run_in_worktree(self, env_override: str | None = None) -> subprocess.CompletedProcess:
        env = dict(os.environ)
        if env_override is None:
            env.pop("GDTOOLKIT_BIN_DIR", None)
        else:
            env["GDTOOLKIT_BIN_DIR"] = env_override
        return subprocess.run(
            shell_script.command(
                self.worktree / "sara-godot" / "scripts" / "check_style.sh", "core/api/document/sa_document.gd"
            ),
            cwd=self.worktree / "sara-godot",
            env=env,
            capture_output=True,
            encoding="utf-8",
            timeout=60.0,
        )

    def test_a_worktree_borrows_the_main_checkouts_env(self) -> None:
        done = self.run_in_worktree()
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertIn(str(self.main_bin), done.stderr)
        self.assertIn("this worktree has none", done.stderr)

    def test_with_no_env_anywhere_it_names_both_paths(self) -> None:
        (self.main_bin / "gdformat").unlink()
        done = self.run_in_worktree()
        self.assertEqual(done.returncode, 2, done.stderr)
        self.assertIn(str(self.worktree_bin), done.stderr)
        self.assertIn(str(self.main_bin), done.stderr)

    def test_the_override_searches_nothing(self) -> None:
        override_dir = Path(self._tmp.name) / "override"
        override_dir.mkdir()
        fake_tool(override_dir / "gdformat", PASS)
        fake_tool(override_dir / "gdlint", PASS)
        done = self.run_in_worktree(env_override=str(override_dir))
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertIn(str(override_dir), done.stderr)
        self.assertNotIn(str(self.main_bin), done.stderr)


@shell_script.runs_here()
class TestAVenvsTools(unittest.TestCase):
    """With no override the script finds gdtoolkit in a venv as well.

    A copy of the script in a scratch tree, so that `.conda` and `.venv` are
    this test's to lay out. The tree is no git repository, so nothing can be
    borrowed from a main checkout and what runs is what the lookup found.
    """

    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.project = Path(self._tmp.name) / "sara-godot"
        script_dir = self.project / "scripts"
        script_dir.mkdir(parents=True)
        shutil.copy(CHECK_STYLE, script_dir / "check_style.sh")
        (script_dir / "check_style.sh").chmod(0o755)

    def tools_in(self, relative: str, body: str = PASS) -> Path:
        bin_dir = self.project / relative
        bin_dir.mkdir(parents=True)
        fake_tool(bin_dir / "gdformat", body)
        fake_tool(bin_dir / "gdlint", body)
        return bin_dir

    def run_check(self, extra_path: Path | None = None) -> subprocess.CompletedProcess:
        env = dict(os.environ)
        env.pop("GDTOOLKIT_BIN_DIR", None)
        if extra_path is not None:
            env["PATH"] = f"{extra_path}{os.pathsep}{env['PATH']}"
        return subprocess.run(
            shell_script.command(self.project / "scripts" / "check_style.sh", "core/stub.gd"),
            cwd=self.project,
            env=env,
            capture_output=True,
            encoding="utf-8",
            timeout=60.0,
        )

    def test_the_tools_in_a_windows_venv_run(self) -> None:
        venv = self.tools_in(".venv/Scripts")
        done = self.run_check()
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertIn(f"gdtoolkit env {venv}", done.stderr)
        self.assertIn("gdformat ok", done.stdout)
        self.assertIn("gdlint ok", done.stdout)

    def test_the_tools_in_a_posix_venv_run(self) -> None:
        venv = self.tools_in(".venv/bin")
        done = self.run_check()
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertIn(f"gdtoolkit env {venv}", done.stderr)

    def test_the_conda_env_comes_before_a_venv(self) -> None:
        conda = self.tools_in(".conda/bin")
        self.tools_in(".venv/Scripts", COMPLAIN)
        done = self.run_check()
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertIn(f"gdtoolkit env {conda}", done.stderr)

    def test_a_gdformat_on_path_is_the_last_place_looked(self) -> None:
        on_path = Path(self._tmp.name) / "tools"
        on_path.mkdir()
        fake_tool(on_path / "gdformat", PASS)
        fake_tool(on_path / "gdlint", PASS)
        done = self.run_check(on_path)
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertIn(f"gdtoolkit env {on_path}", done.stderr)
        self.assertIn("gdlint ok", done.stdout)

    def test_a_venv_comes_before_a_gdformat_on_path(self) -> None:
        venv = self.tools_in(".venv/bin")
        on_path = Path(self._tmp.name) / "tools"
        on_path.mkdir()
        fake_tool(on_path / "gdformat", COMPLAIN)
        fake_tool(on_path / "gdlint", COMPLAIN)
        done = self.run_check(on_path)
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertIn(f"gdtoolkit env {venv}", done.stderr)

    def test_with_neither_it_names_the_conda_env(self) -> None:
        done = self.run_check()
        self.assertEqual(done.returncode, 2, done.stderr)
        self.assertIn(str(self.project / ".conda" / "bin" / "gdformat"), done.stderr)


class TestTheFileList(CheckStyleCase):
    """What the script hands the tools, which is the gate's own tree."""

    def test_given_paths_reach_the_tool(self) -> None:
        fake_tool(self.bin_dir / "gdformat", ECHO_ARGS)
        done = self.run_check("core/api/document/sa_document.gd", "core/api/document/sa_layer.gd")
        self.assertIn("core/api/document/sa_document.gd", done.stdout)
        self.assertIn("core/api/document/sa_layer.gd", done.stdout)

    def test_gdformat_is_asked_to_check_and_not_to_write(self) -> None:
        fake_tool(self.bin_dir / "gdformat", ECHO_ARGS)
        done = self.run_check("core/api/document/sa_document.gd")
        self.assertIn("--check", done.stdout)

    def test_write_lets_gdformat_rewrite(self) -> None:
        """--write is the one door for the thing the gate never does."""
        fake_tool(self.bin_dir / "gdformat", ECHO_ARGS)
        done = self.run_check("--write", "core/api/document/sa_document.gd")
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertNotIn("--check", done.stdout)
        self.assertIn("core/api/document/sa_document.gd", done.stdout)

    def test_write_is_not_taken_for_a_path(self) -> None:
        fake_tool(self.bin_dir / "gdformat", ECHO_ARGS)
        done = self.run_check("--write", "core/api/document/sa_document.gd")
        self.assertNotIn("--write", done.stdout)

    def test_no_paths_means_the_whole_tree(self) -> None:
        fake_tool(self.bin_dir / "gdformat", ECHO_ARGS)
        fake_tool(self.bin_dir / "gdlint", PASS)
        done = self.run_check()
        named = [line for line in done.stdout.splitlines() if line.endswith(".gd")]
        self.assertGreater(len(named), 700, "the gate's tree is eight hundred files")
        roots = {line.split("/")[0] for line in named}
        self.assertEqual(
            roots,
            {"core", "render", "tools", "ui", "utils", "tests", "harness", "modules"},
            "the tree the gate checks, no more and no less",
        )

    def test_the_harness_and_the_small_modules_are_checked(self) -> None:
        """These drifted while the tree left them out."""
        fake_tool(self.bin_dir / "gdformat", ECHO_ARGS)
        fake_tool(self.bin_dir / "gdlint", PASS)
        named = set(self.run_check().stdout.splitlines())
        self.assertIn("harness/door/sa_agent_door.gd", named)
        for module in ("kaleidoscope", "midi", "sphere"):
            self.assertIn(f"modules/sara-base-modules/{module}/module.gd", named)
        ## The box blur is one of the base module's blurs.
        self.assertIn("modules/sara-base-modules/base/usual/box_blur_filter.gd", named)

    def test_every_module_that_is_in_the_tree_is_checked_with_this_folders_rules(self) -> None:
        """The modules that are repositories of their own had been left out, and drifted past the line limit."""
        fake_tool(self.bin_dir / "gdformat", ECHO_ARGS)
        fake_tool(self.bin_dir / "gdlint", PASS)
        named = self.run_check().stdout.splitlines()
        modules_dir = SARA_GODOT / "modules"
        for module in sorted(p.name for p in modules_dir.iterdir() if p.is_dir() and any(p.rglob("*.gd"))):
            with self.subTest(module=module):
                self.assertTrue([n for n in named if n.startswith(f"modules/{module}/")], module)


class TestTheGateBlocks(unittest.TestCase):
    """The five copies of the gate, which is why one script beats two commands."""

    def test_every_copy_calls_the_script(self) -> None:
        for name in GATE_COPIES:
            with self.subTest(copy=name):
                if not (REPO_ROOT / name).exists():
                    self.skipTest("a copy of the source carries no %s" % name)
                text = (REPO_ROOT / name).read_text(encoding="utf-8")
                self.assertIn("scripts/check_style.sh", text)

    def test_no_copy_still_quotes_the_bare_tools(self) -> None:
        """A bare command is the failure covered, so none may come back."""
        for name in GATE_COPIES:
            with self.subTest(copy=name):
                if not (REPO_ROOT / name).exists():
                    self.skipTest("a copy of the source carries no %s" % name)
                text = (REPO_ROOT / name).read_text(encoding="utf-8")
                self.assertNotIn(".conda/bin/gdformat", text)
                self.assertNotIn(".conda/bin/gdlint", text)


if __name__ == "__main__":
    unittest.main()
