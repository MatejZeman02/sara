## Where Sara keeps what a painter makes and what it caches for them: the
## recovery copies, the presets, the colours, the layout, the recordings, the
## previews, the compiled kernels and the painter's own modules.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **One root, and `--settings-dir` moves it**. Every such folder is asked of
## this class rather than spelled as a `user://` constant of its own, so a run
## with the flag reads and writes under `<settings-dir>/data` and never under the
## painter's `user://`. A folder the flag missed would let a scratch run offer to
## recover an autosave of the painter's own session, and its Delete button would
## remove the painter's copy.
##
## **With no flag nothing moves.** The root is `user://`, so an installed Sara
## finds the painter's data where the last build left it. A folder chosen in
## Preferences moves the settings file only, because the painter's data already
## sits in `user://` and a pointer that dragged it along would have to move it.
##
## **The pointer that records such a folder is under the flag too.**
## `SaSettingsFile.set_pointer` writing the painter's `location.cfg` whatever the
## flag said would let a scenario that moves the Files page's folder row send
## the installed Sara to a test folder at its defaults. A run with the flag
## writes and reads `<settings-dir>/location.cfg` instead, and the painter's own
## folder is never touched.
##
## **The flag is read here**, and `SaSettingsFile` asks this for it, because
## the flag is the one fact both need and this class names nothing else. In
## `utils` rather than beside the settings file, because a module keeps files
## of its own, the stamp brush's tips and patterns, and a module sees the door
## only, which is hard rule 6, built-ins through the public door. The one `"user://"` a source file may still spell is
## here, and `tests/test_no_user_path_outside_the_data_root.gd` greps for
## any other.
class_name SaDataRoot
extends RefCounted

## The root of a run without the flag: Godot's own user folder.
const DEFAULT: String = "user://"

## The default run log when the project setting names none and no flag moves the
## data root. Spelled here so `SaTrail.log_path()` spells no `user://` of its own.
const ENGINE_LOG: String = "user://logs/godot.log"

## The folder under Android's shared Documents that Sara's log and tester notes
## go in, `Documents/Sara`.
##
## **Why not `user://` there.** On Android `user://` is the app's private
## folder, which a file manager does not open, and the friend testing a build
## on a tablet has no `adb` to pull a file out of it. An app may make a folder
## of its own under the shared Documents and write the files it makes there
## without asking for a storage permission, from Android 11 on.
const SHARED_FOLDER: String = "Sara"


## `Documents/Sara` on Android's shared storage, or "" on any other platform,
## where `user://` and the home folder are already where a painter looks.
static func shared() -> String:
    if OS.get_name() != "Android":
        return ""
    return shared_under(OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS))


## `Sara` under *documents*, or "" when the platform named no Documents
## folder. Apart from [method shared] so a suite can read it off a desktop.
static func shared_under(documents: String) -> String:
    if documents.is_empty():
        return ""
    return documents.path_join(SHARED_FOLDER)


## The run log when the project setting names none: the flag's folder when
## there is one, `Documents/Sara/godot.log` on Android, and the engine's own
## `user://logs/godot.log` otherwise.
static func default_log() -> String:
    if moved():
        return log_path()
    return log_under(shared())


## `godot.log` under *shared*, or the engine's own log when *shared* is "".
static func log_under(shared_folder: String) -> String:
    if shared_folder.is_empty():
        return ENGINE_LOG
    return shared_folder.path_join("godot.log")


## The run log for this run: `user://logs/godot.log` when there is no flag, and
## `<settings-dir>/data/logs/godot.log` when `--settings-dir` moves the root.
static func log_path() -> String:
    return path("logs/godot.log")


## The flag that moves the settings file and the data root.
const FLAG: String = "--settings-dir"

## The folder under the flag's directory that stands for `user://`. A folder of
## its own rather than the flag's directory itself, so the settings file, its
## backups and the shortcut profiles beside it never share a listing with a
## preset folder.
const UNDER_FLAG: String = "data"


## The folder `--settings-dir` names on this process's command line, or ""
## when the run has no flag. Written with forward slashes, as Godot writes a
## path it hands back: `run_tests.ps1` passes `D:\project\...`, and a folder made
## under it came back as `D:\project/...` and never matched the one asked for.
static func flag() -> String:
    # get_cmdline_args() never carries what follows a "--": Godot keeps that
    # half in get_cmdline_user_args() only, and the offscreen gate and
    # sara_shot.py both launch with the flag after one, alongside --capture.
    # An installed `sara --settings-dir <path>` has no "--" at all, which is
    # why both arrays are checked rather than just one.
    var found := flag_in(OS.get_cmdline_args())
    if found.is_empty():
        found = flag_in(OS.get_cmdline_user_args())
    return found.replace("\\", "/")


## Reads `--settings-dir <path>` or `--settings-dir=<path>` out of a raw
## argument list, ahead of Godot's own parsing, so it works whether or not the
## flag follows a `--`. Kept apart from [method flag] so the parsing can be
## tested against a synthetic array rather than the process's real command
## line, which under the offscreen gate already carries a real flag.
static func flag_in(args: PackedStringArray) -> String:
    for i in args.size():
        var arg: String = args[i]
        if arg.begins_with(FLAG + "="):
            return arg.substr((FLAG + "=").length())
        if arg == FLAG and i + 1 < args.size():
            return args[i + 1]
    return ""


## The root itself, `user://` or `<settings-dir>/data`.
static func folder() -> String:
    var from_flag := flag()
    if from_flag.is_empty():
        return DEFAULT
    return absolute(from_flag).path_join(UNDER_FLAG)


## *folder* as an absolute path, a relative one being read from the process's
## working folder. A store writes only under an absolute root, because a
## relative one lands in the project folder of a test run, so a painter's
## `--settings-dir=notes` has to become one before anything is written.
static func absolute(folder_path: String) -> String:
    if folder_path.is_absolute_path():
        return folder_path
    var here := DirAccess.open(".")
    if here == null:
        return folder_path
    return here.get_current_dir().path_join(folder_path).simplify_path()


## `relative` under the root: `path("autosave")` is `user://autosave` in a
## painter's run and `<settings-dir>/data/autosave` in a scratch one.
static func path(relative: String) -> String:
    return folder().path_join(relative)


## True when the run keeps its data under a flag's folder rather than under
## the painter's `user://`.
static func moved() -> bool:
    return folder() != DEFAULT
