## No source file spells a `user://` path of its own, so every folder Sara keeps
## is asked of `SaDataRoot`, the root `--settings-dir` moves.
##
## A scratch run started with a fresh `--settings-dir` must not offer to
## recover an autosave of the painter's own, nor delete the painter's copy, so
## the flag moves every folder and not only the settings file. Each folder asks
## the root, and this grep keeps another `user://` constant from being written. The behaviour it protects is
## `test_a_scratch_run_writes_under_its_own_root.gd`.
##
## The suites are scanned as well. Their scratch paths
## are not `user://` literals, which `run_tests.sh` moved through
## `XDG_DATA_HOME` on Linux and which on Windows, where that variable means
## nothing to the engine, reached the painter's `%APPDATA%`. A suite builds its
## scratch path with `SaDataRoot.path()`, and the few that mean the engine's own
## user folder on purpose are named in [constant SUITES_THAT_MEAN_THE_USER_FOLDER].
extends "res://tests/test_framework.gd"

## Never descend into these, the list `test_hard_rules.gd` walks with.
const SKIP_DIRS: Array[String] = [".godot", ".conda", ".git", "build", "node_modules", "scratch"]

## The root's own file, which holds `user://` as the root of a run without the
## flag and as the engine's log it cannot move.
const ROOT_FILE: String = "utils/sa_data_root.gd"

## The settings file's platform default falls back to the engine's user folder
## on a machine with no home directory. That is where the settings file lives,
## which the flag already moves, not a data folder. This suite spells
## the call as its needle.
const USER_DATA_DIR_ALLOWED: Array[String] = [
    ROOT_FILE,
    "core/settings/sa_settings_file.gd",
    "tests/test_no_user_path_outside_the_data_root.gd",
]

## The suites whose `user://` is the engine's user folder itself and not a
## scratch path: this one, which spells the needle, the scratch-run suite,
## which lists the painter's folder before and after, and the two that prove
## the shader walk stays out of the real user folder, and the preset store's,
## which only hands `SaDataRoot.absolute` a `user://` string to show it is
## returned as it is and writes nothing there.
const SUITES_THAT_MEAN_THE_USER_FOLDER: Array[String] = [
    "tests/test_no_user_path_outside_the_data_root.gd",
    "core/sad-file/tests/test_a_scratch_run_writes_under_its_own_root.gd",
    "core/custom-shader/compiler/tests/test_shader_namespaces.gd",
    "core/custom-shader/dialect/tests/test_spirv_manifest.gd",
    "core/presets/tests/test_a_store_with_an_empty_or_relative_root_writes_nothing.gd",
]


func test_no_source_spells_a_user_path_but_the_root() -> void:
    var found: Array[String] = []
    for needle: String in ['"user://', "'user://"]:
        var allowed: Array[String] = [ROOT_FILE]
        allowed.append_array(SUITES_THAT_MEAN_THE_USER_FOLDER)
        for path: String in _files_matching(needle, allowed):
            if not found.has(path):
                found.append(path)
    assert_eq(found, [] as Array[String], "every user:// folder is asked of SaDataRoot rather than spelled")


func test_no_source_asks_the_engine_for_its_user_folder_but_two() -> void:
    var found := _files_matching("OS.get_user_data_dir()", USER_DATA_DIR_ALLOWED)
    assert_eq(found, [] as Array[String], "the engine's user folder is the data root's to answer, not a caller's")


## The scan sees the files it means to see: the root itself spells the one
## `user://` it is allowed, so a walk that found nothing would fail here rather
## than pass the two above for the wrong reason.
func test_the_walk_reaches_the_root_and_a_module() -> void:
    var sources := _sources()
    assert_true(sources.has(ROOT_FILE), "the root's own file is walked")
    assert_true(sources.has("modules/sara-base-modules/stamp-brush/pattern/sa_pattern_capture.gd"), "and a module's")
    assert_true(sources.has("core/export/tests/test_export_carries_the_gamut.gd"), "and a suite under tests")
    assert_true(sources.has("modules/sara-base-modules/kaleidoscope/tests/test_kaleidoscope.gd"), "and a suite beside its module")
    for suite: String in SUITES_THAT_MEAN_THE_USER_FOLDER:
        assert_true(sources.has(suite), "a suite named on purpose is still there: %s" % suite)
    assert_true(_code(_read(ROOT_FILE)).contains('"user://'), "and the root is where the one user:// is")


func _files_matching(needle: String, allowed: Array[String]) -> Array[String]:
    var out: Array[String] = []
    for path: String in _sources():
        if allowed.has(path):
            continue
        if _code(_read(path)).contains(needle):
            out.append(path)
    out.sort()
    return out


func _sources() -> Array[String]:
    var out: Array[String] = []
    _walk(ProjectSettings.globalize_path("res://"), "", out)
    out.sort()
    return out


func _walk(dir_path: String, prefix: String, out: Array[String]) -> void:
    var dir := DirAccess.open(dir_path)
    if dir == null:
        return
    dir.list_dir_begin()
    var entry := dir.get_next()
    while not entry.is_empty():
        if dir.current_is_dir():
            if not SKIP_DIRS.has(entry):
                _walk(dir_path.path_join(entry), prefix + entry + "/", out)
        elif entry.get_extension() == "gd":
            out.append(prefix + entry)
        entry = dir.get_next()
    dir.list_dir_end()


## The file with its comment lines removed, since a doc comment that names the
## old path is history rather than a path.
func _code(text: String) -> String:
    var kept: Array[String] = []
    for line in text.split("\n"):
        if not line.strip_edges().begins_with("#"):
            kept.append(line)
    return "\n".join(kept)


func _read(path: String) -> String:
    return FileAccess.get_file_as_string("res://".path_join(path))
