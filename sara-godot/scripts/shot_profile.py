"""The profile an offscreen capture reads and writes, and what of it a run
inherits from the last one.

Sara keeps a painter's state in two places. The settings file and the docker
layout live under `SaSettings.get_settings_dir()`, the config home, and
everything Godot calls `user://`, the colour store, the brush presets, the
patterns, the autosave and an installed module, lives under the data home. An
offscreen run points both at `scratch/xdg/` so a capture never touches the
person's own, and this class is what empties them so a capture that looks
like a fresh profile is one.

Both halves are one class because they are one question, what a run starts
from, and a runner that answers it twice will answer it once again wrong the
next time a file moves between the homes. Each half was found by the same
accident: a scenario that added a swatch opened on it three runs running,
because `SaColors` writes `user://colors.cfg` on every commit and a runner
that clears the config home alone clears nothing of it.
"""

from __future__ import annotations

import contextlib
import os
import re
import shutil
import time
from pathlib import Path

try:
    import fcntl
except ImportError:  # Windows has no flock, and a run there takes the shared profile as before
    fcntl = None


class ShotProfile:
    """One checkout's capture profile: where it is and how a run prepares it."""

    # What stays in `user://` between captures: the GPU's compiled shaders and
    # pipelines and the dialect's translations, which are the run's work and not
    # the painter's, and which a first capture on a cold cache can take long
    # enough to time out on.
    USER_CACHES = ("shader_cache", "spirv_cache", "glsl_cache", "vulkan")

    # The folder under the settings directory that `--settings-dir` makes the
    # data root (`SaDataRoot.UNDER_FLAG`). Clearing the settings empties it
    # like `user://` and spares the same caches, or every capture compiles its
    # SPIR-V cold, the cache living there.
    DATA_ROOT = "data"

    # The pen a harness run presses with, fitted so a stroke step's pressure
    # reads as an agent expects (`harness/drivers/sa_harness_pen.gd`). Beside this
    # script's checkout rather than under `project_dir`, because a build's
    # scratch profile has no harness folder of its own and its session presses
    # with the same pen.
    PEN_TABLE = Path(__file__).resolve().parent.parent / "harness" / "drivers" / "pen_pressure_curve.txt"

    # The name `SaTablet.CURVE_FILE` gives the table beside the settings file.
    CURVE_FILE = "pressure_curve.txt"
    # `SaSettingsFile.SETTINGS_FILE`, the file `switch_on` writes.
    SETTINGS_FILE = "settings.cfg"

    # The environment variable that names a numbered profile of its own, so a
    # run that holds one is the only writer of `scratch/xdg-<name>`. Unset, a
    # run takes `scratch/xdg`, the one the door and a hand-run capture share.
    NAME_ENV = "SARA_SHOT_PROFILE"

    # How many profiles `lease` hands out at once. The machine's gate slots
    # (`gate_slot`, three by default) cap the Godots on the card, so this many
    # is enough for every stream a checkout can run.
    LEASES = 8

    def __init__(self, project_dir: Path) -> None:
        self.project_dir = Path(project_dir)

    @property
    def xdg_dir(self) -> Path:
        """The folder under `scratch/` that holds both homes, `xdg` or the
        numbered `xdg-<name>` of a lease."""
        name = os.environ.get(self.NAME_ENV, "")
        return self.project_dir / "scratch" / (f"xdg-{name}" if name else "xdg")

    @property
    def settings_dir(self) -> Path:
        """Where the settings file and the docker layout go, the `--settings-dir`
        the app is handed."""
        return self.xdg_dir / "config" / "sara"

    @property
    def data_home(self) -> Path:
        """The `XDG_DATA_HOME` the run is given, under which Godot puts `user://`."""
        return self.xdg_dir / "data"

    @contextlib.contextmanager
    def lease(self):
        """A profile no other run of this checkout is using, named in
        `NAME_ENV` for as long as the block runs.

        Two streams of captures in one checkout shared `scratch/xdg`: one run's
        `prepare` emptied the folder under another that was still writing its
        settings, so a scenario that raised the UI scale at its end left that
        scale in the profile a neighbour was starting on, and a scenario was
        drawn at scale 2 against a record at scale 1. Each run takes the first
        numbered profile whose lock is free, so the profile stays one per
        stream with its shader caches warm, and no two runs ever share one.
        Where there is no `fcntl`, the block runs on the shared profile.
        """
        previous = os.environ.get(self.NAME_ENV)
        handle = None
        if fcntl is not None:
            locks = self.project_dir / "scratch" / "xdg-leases"
            locks.mkdir(parents=True, exist_ok=True)
            handle = self._take(locks)
            os.environ[self.NAME_ENV] = f"run{handle.name.rsplit('-', 1)[1]}"
        try:
            yield self
        finally:
            if previous is None:
                os.environ.pop(self.NAME_ENV, None)
            else:
                os.environ[self.NAME_ENV] = previous
            if handle is not None:
                handle.close()

    def _take(self, locks: Path):
        """The open lock file of the first free numbered profile, waiting for one
        when every one is held."""
        while True:
            for number in range(1, self.LEASES + 1):
                handle = open(locks / f"profile-{number}", "w", encoding="utf-8")  # noqa: SIM115
                try:
                    fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
                except OSError:
                    handle.close()
                    continue
                return handle
            time.sleep(2)

    @property
    def log_file(self) -> Path:
        """The engine's log a capture or a door session writes, passed as
        `--log-file` with `SARA_LOG_FILE` beside it.

        The `--watch` run's log comes here as well, rather than into the
        painter's own `user://logs`, where it would rotate away the log a
        freeze of theirs had left. `--log-file` turns the engine's rotation
        off, so each run overwrites this one file.
        """
        return self.user_dir / "logs" / "godot.log"

    def prepare_log(self) -> Path:
        """`log_file`, with its folder made, for a launcher about to pass it."""
        self.log_file.parent.mkdir(parents=True, exist_ok=True)
        return self.log_file

    def log_to(self, env: dict) -> list:
        """The engine flags that send a run's log to `log_file`, with
        `SARA_LOG_FILE` set in *env* beside them for `SaTrail.log_path()`.
        They go straight after the binary, since past the `--` the engine
        would never see them."""
        env["SARA_LOG_FILE"] = str(self.prepare_log())
        return ["--log-file", env["SARA_LOG_FILE"]]

    @property
    def user_dir(self) -> Path:
        """What `user://` resolves to for this run."""
        return self.data_home / "godot" / "app_userdata" / "Sara"

    def prepare_rescan(self) -> Path:
        """The settings directory the editor's class cache pass is handed.

        The editor runs the `@tool` settings autoload, which saves the settings
        file it finds, so the pass gets a scratch one of its own rather than the
        person's `~/.config/sara`.
        """
        directory = self.project_dir / "scratch" / "xdg-rescan" / "config" / "sara"
        directory.mkdir(parents=True, exist_ok=True)
        return directory

    def prepare(self, keep: bool) -> Path:
        """Both halves, and the settings directory the command line needs."""
        settings = self.prepare_settings(keep)
        self.prepare_user(keep)
        return settings

    def prepare_settings(self, keep: bool) -> Path:
        """The settings profile, emptied first unless *keep*.

        The app writes `docker_layout.cfg` and the settings file back on exit,
        so a scenario run without this opens on whatever the last one left, and
        a pair of captures taken to compare two trees can be comparing two
        layouts instead. The whole directory goes rather than the layout alone, because
        the settings file is the same trap one file over. One per checkout and
        not one per run, so a `prefs` step is still readable afterwards.
        """
        directory = self.settings_dir
        if not keep:
            self._empty(directory, (self.DATA_ROOT,))
            self._empty(directory / self.DATA_ROOT, self.USER_CACHES)
        directory.mkdir(parents=True, exist_ok=True)
        print("  settings " + ("kept from the last capture" if keep else "cleared, defaults for this run"))
        if not keep:
            self.give_pen(directory)
        return directory

    def give_pen(self, directory: Path) -> None:
        """The harness's pressure table copied into *directory*, where the app
        reads a painter's at startup, so every brush the run makes is stamped
        with it.

        Only into a cleared profile. A kept one keeps whatever the last run
        left, a `pressure_curve` step's table included, which is what keeping
        means. The ceiling is not copied: the harness's is the default a scratch
        profile starts on, and the settings file is its only home.
        """
        shutil.copyfile(self.PEN_TABLE, directory / self.CURVE_FILE)
        print("  pen      the harness's own pressure table, harness/drivers/pen_pressure_curve.txt")

    def prepare_user(self, keep: bool) -> Path:
        """`user://`, emptied of painter state unless *keep*.

        Everything but the GPU caches goes: `colors.cfg`, `brush_presets`,
        `patterns`, `preset_history.cfg`, `autosave`, `modules`, the logs. The
        caches stay because they are compiled work and a cold one costs the first
        capture its compile budget. One per checkout, like the settings.
        """
        directory = self.user_dir
        if not keep:
            self._empty(directory, self.USER_CACHES)
        directory.mkdir(parents=True, exist_ok=True)
        print("  user://  " + ("kept from the last capture" if keep else "cleared of the last capture's colours, presets and autosave"))
        return directory

    def switch_on(self, directory: Path, ids: "list[str]") -> None:
        """A settings file in the cleared *directory* with the modules a build
        ships switched off, less *ids*, as Preferences > Modules writes it.

        The loader reads the setting once at the start, so a `prefs` step comes
        too late for a module that is off by default, and a scenario that opens
        Kaleidoscope reported that no filter dialog opened. The list and the
        settings version are read from the GDScript that owns them, so the file
        is the one this build would write and loads with no migration.
        """
        if not ids:
            return
        off_source = (self.project_dir / "core" / "settings" / "values" / "sa_off_by_default.gd").read_text(encoding="utf-8")
        listed = re.search(r"const IDS: Array\[String\] = \[(.*?)\n\]", off_source, re.S)
        off_by_default = re.findall(r'^\s*"([^"]+)",', listed.group(1), re.M) if listed else []
        migrations = (self.project_dir / "core" / "settings" / "sa_settings_migrations.gd").read_text(encoding="utf-8")
        version = re.search(r"const SETTINGS_VERSION: int = (\d+)", migrations).group(1)
        off = ", ".join(f'"{module}"' for module in off_by_default if module not in ids)
        (directory / self.SETTINGS_FILE).write_text(
            f"[meta]\n\nversion={version}\n\n[modules]\n\noff=[{off}]\n", encoding="utf-8"
        )
        print(f"  modules  switched on for this run: {', '.join(ids)}")

    @staticmethod
    def _empty(directory: Path, spared: tuple[str, ...]) -> None:
        """Remove what *directory* holds except the entries named in *spared*."""
        if not directory.exists():
            return
        for entry in directory.iterdir():
            if entry.name in spared:
                continue
            if entry.is_dir() and not entry.is_symlink():
                shutil.rmtree(entry)
            else:
                entry.unlink()
