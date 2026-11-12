## Which file provides which shader, and the walk that finds them.
##
## Everything about a shader as a file on disk: the directory walk, the owner a
## path belongs to, the key a shader is known by, the file an `#include`
## resolves to, and the startup report of what was found. The timestamp scan
## that drives hot reload is the include processor's, which owns the cache the
## scan compares against. Preloaded by path from the compiler rather than
## reached through a `class_name`, because a class name resolves only after the
## editor rescans its class cache.
##
## The index owns what it fills: the two file lists and the two ownership
## dictionaries are declared here, and it is built from nothing. They stood on
## the compiler while this file held the compiler back and worked on them by
## reference, which made the two files one class. The compiler keeps the index
## as its typed member `index`, and a suite asks that.

@tool
extends RefCounted

## The extension a kernel file carries, and every extension the walk collects.
const COMPUTE_SHADER_EXTENSION: String = "gmacs"
const SHADER_EXTENSIONS: Array[String] = ["glsl", "shader", COMPUTE_SHADER_EXTENSION]

## `<owner>/<name>` -> the file that provides it.
##
## Keyed by owner and name rather than by bare filename, because two modules
## shipping `paint.gmacs` would otherwise collide and which one won would be
## directory order. Nothing would say so, and nothing would fail: the second
## module would simply paint with the first one's kernels.
##
## Plain rather than private because `core/custom-shader/compiler/tests/test_shader_namespaces.gd` clears and
## restores it around a case.
var shaders_by_key: Dictionary[String, String] = {}

## Bare name -> the owners that provide it, so an ambiguous reference can name
## them instead of picking one. Plain for the reason the dictionary above is.
var owners_of_name: Dictionary[String, PackedStringArray] = {}

## Every kernel file the walk found, in the order it found them, and the
## standard shader files beside them, which nothing compiles yet.
var compute_shader_file_paths: Array = Array()
var shader_files: Array = Array()

## Collected for report_compilation(), as shader_name -> kernel names, plus the
## include-only files, which have no kernels of their own.
var _compiled_kernels: Dictionary[String, PackedStringArray] = {}
var _compiled_includes: PackedStringArray = PackedStringArray()

## Directories that cannot hold a shader anyone wrote, and are expensive or
## harmful to walk.
##
## `.godot` is the engine's import cache, which holds copies: a duplicate
## `.gmacs` in there would be a second candidate for `find_include_file`'s
## `ends_with` match, and which one wins is directory order. `.conda` is the
## vendored gdtoolkit env, thousands of files deep. The rest are the same set
## `check_docs_links.py` already skips.
const SCAN_SKIP_DIRS: Array[String] = [".godot", ".conda", ".git", "build", "node_modules"]

## The running app's own `user://`, resolved once per walk, or empty when it
## cannot be resolved.
##
## Held rather than asked for per directory, because the walk visits a few
## hundred of them and the answer cannot change inside one run.
var _user_dir: String = ""

## The data root under a `--settings-dir` run, resolved with `_user_dir` and for
## the same reason: the generated kernels and the SPIR-V cache live there when
## the flag moves them. Equal to `_user_dir` in a run without the flag.
var _data_dir: String = ""

## The checkout's own `scratch/`, resolved once per walk, for the same reason.
var _scratch_dir: String = ""

## Who owns a shader that is not inside a module: Sara itself.
const CORE_OWNER: String = "sara"

## The directory a module's own tree hangs under, which is the only thing that
## distinguishes a module's shader from Sara's.
const MODULE_DIR: String = "modules"


## The owner of the shader at *file_path*: the module directory it lives under, or
## `sara` when it lives anywhere else.
func owner_of(file_path: String) -> String:
    var parts := file_path.simplify_path().split("/")
    var at := parts.find(MODULE_DIR)
    if at >= 0 and at + 1 < parts.size():
        return parts[at + 1]
    return CORE_OWNER


## The `<owner>/<name>` a shader file is known by.
func shader_key(file_path: String) -> String:
    return owner_of(file_path) + "/" + get_shader_name(file_path)


## Records *file_path* under its key, refusing a second file with the same one.
##
## Two files with one key is not a collision this can resolve, only report: they
## are the same owner's own duplicate, and whichever loses would be chosen by the
## order the directory walk happened to return.
func index_shader(file_path: String) -> void:
    var key := shader_key(file_path)
    if shaders_by_key.has(key) and shaders_by_key[key] != file_path:
        push_error("GlobalShaderCompiler: '%s' is provided by both %s and %s." % [key, shaders_by_key[key], file_path])
        return
    shaders_by_key[key] = file_path
    var bare := get_shader_name(file_path)
    var owners: PackedStringArray = owners_of_name.get(bare, PackedStringArray())
    var provider := owner_of(file_path)
    if not owners.has(provider):
        owners.append(provider)
    owners_of_name[bare] = owners


## The key a caller's *written_name* means, whether they qualified it or not.
##
## A qualified name is taken as written. A bare one is Sara's own shader when
## Sara has one, which is what keeps every existing call site working, and
## otherwise the single module that provides it. A bare name two modules both
## provide is refused and names them, rather than resolving to whichever the
## directory walk reached first.
func resolve_shader_name(written_name: String) -> String:
    if written_name.contains("/"):
        return written_name
    var owners: PackedStringArray = owners_of_name.get(written_name, PackedStringArray())
    if owners.has(CORE_OWNER) or owners.is_empty():
        return CORE_OWNER + "/" + written_name
    if owners.size() == 1:
        return owners[0] + "/" + written_name
    push_error(
        (
            "GlobalShaderCompiler: '%s' is ambiguous, provided by %s. Qualify it as <owner>/%s."
            % [written_name, ", ".join(owners), written_name]
        )
    )
    return ""


## Whether *dir_path* is the running app's own `user://`.
##
## The walk starts at `res://`, and a `user://` that resolves inside the project
## is a directory of files the app itself wrote rather than files anybody
## authored. `run_tests.sh` points `XDG_DATA_HOME` at
## `sara-godot/scratch/xdg-gate/data`, deliberately, so that two gates in two
## worktrees do not share one settings file and one SPIR-V cache, and the
## consequence nobody had followed through is that `user://` then lands inside
## `res://`. Every `.gmacs` a test wrote there became a shader the next boot
## indexed and compiled, for as long as the file sat on disk: four kernels of
## `test_storage_formats.gd`'s bindings probe were being compiled at every boot
## of the offscreen gate and reported in the boot header, and they turned up in
## a baseline written by a run that never loaded that suite.
##
## Asked as "is this the user directory", rather than answered by adding
## `scratch` to `SCAN_SKIP_DIRS`, because `scratch` is where this runner happens
## to put it. A packaged build, an editor run and a second runner each put it
## somewhere else, and the rule is about what the directory is. The data root a
## `--settings-dir` run writes under is the same kind of directory, so it is
## turned back at too.
func is_user_directory(dir_path: String) -> bool:
    if _user_dir.is_empty():
        _user_dir = _real_path(SaDataRoot.DEFAULT)
        _data_dir = _real_path(SaDataRoot.folder())
    var real := _real_path(dir_path)
    return not real.is_empty() and (real == _user_dir or real == _data_dir)


## Whether *dir_path* is the checkout's own `scratch/`.
##
## The second half of the same question, and the half `is_user_directory()`
## cannot answer: that one asks about *this* run, and a `user://` from an earlier
## one is a different directory, so the guard lets the walk in. `run_tests.sh`
## roots the gate at `scratch/xdg-gate/data` and a plain run of the app in the
## same checkout roots itself at `scratch/xdg/data`, so without this a probe
## kernel a test left in the second is walked and compiled at every boot of the
## first, and fails suites that never wrote it.
##
## Named rather than asked about, unlike `is_user_directory()`, and safe to name
## because `scratch/` is this checkout's own gitignored output rather than a
## place the runner happens to choose: nothing anybody authored is under it. It
## is resolved against `res://`
## rather than matched by name anywhere in the walk, so a module that ships a
## directory of that name keeps its shaders.
##
## The two checks stand together. This one covers every app run before this one,
## and `is_user_directory()` covers a packaged build and a runner whose scratch
## is somewhere else.
func is_scratch_directory(dir_path: String) -> bool:
    if _scratch_dir.is_empty():
        _scratch_dir = _real_path("res://scratch")
    return not _scratch_dir.is_empty() and _real_path(dir_path) == _scratch_dir


## A path as the filesystem knows it, with no trailing separator, so that two
## spellings of one directory compare equal.
func _real_path(path: String) -> String:
    var real := ProjectSettings.globalize_path(path).simplify_path()
    return real.trim_suffix("/")


## Recursively scan the project directory for shader files.
func find_files(dir_name: String) -> void:
    assert(dir_name != "", "Directory name must not be empty")
    var dir := DirAccess.open(dir_name)
    if dir:
        dir.list_dir_begin()
        var file_name := dir.get_next()
        while file_name != "":
            if dir.current_is_dir():
                if file_name in SCAN_SKIP_DIRS:
                    file_name = dir.get_next()
                    continue
                var child := dir_name.path_join(file_name)
                if is_user_directory(child) or is_scratch_directory(child):
                    file_name = dir.get_next()
                    continue
                find_files(child)
            else:
                var ext := file_name.get_extension()
                if ext in SHADER_EXTENSIONS:
                    if ext == COMPUTE_SHADER_EXTENSION:
                        var compute_path := dir_name.path_join(file_name)
                        compute_shader_file_paths.push_back(compute_path)
                        index_shader(compute_path)
                    else:
                        shader_files.push_back(dir_name.path_join(file_name))
            file_name = dir.get_next()


## Every kernel file under *dir_path*, recorded under its owner key and added to
## the list the walk keeps, for a folder the walk from `res://` never reached.
## Answers the files it found, the ones already known included, so a caller can
## recompile exactly those.
##
## The walk skips the app's own `user://` on purpose, so a module under
## `user://modules` shipped a `.gmacs` that nothing ever compiled. This is the
## one door that adds a folder after the walk, and the module loader is its
## caller, with the folder it read the module from.
func index_directory(dir_path: String) -> Array[String]:
    var found: Array[String] = []
    _collect_kernels(dir_path, found)
    for file_path: String in found:
        if not compute_shader_file_paths.has(file_path):
            compute_shader_file_paths.push_back(file_path)
        index_shader(file_path)
    return found


func _collect_kernels(dir_path: String, found: Array[String]) -> void:
    var dir := DirAccess.open(dir_path)
    if dir == null:
        return
    for sub in dir.get_directories():
        if sub.begins_with(".") or sub in SCAN_SKIP_DIRS:
            continue
        _collect_kernels(dir_path.path_join(sub), found)
    for file_name in dir.get_files():
        if file_name.get_extension() == COMPUTE_SHADER_EXTENSION:
            found.append(dir_path.path_join(file_name))


## Extract filename without extension
func get_shader_name(file_path: String) -> String:
    assert(file_path != "", "File path must not be empty")
    return file_path.get_file().split(".")[0]


## Placeholder for standard .glsl vertex/fragment shaders
func compile_shader(_shader_file_path: String) -> void:
    push_error("GlobalShaderCompiler: standard shader compilation is not implemented, ignoring " + _shader_file_path)


## The file providing `#include "<include_name>"` inside *including_file_path*.
##
## An include is resolved from the point of view of whoever wrote it. A module
## asking for `noise` means its own `noise` if it ships one, then Sara's, and only
## then another module's, and two other modules offering it is an error rather
## than a coin toss. Writing `<owner>/noise` says exactly which and skips all of
## that.
##
## Rather than a global `ends_with()` over every discovered path, which would
## make the answer depend on the order the directory walk returns files in.
func find_include_file(include_name: String, including_file_path: String) -> String:
    if include_name.contains("/"):
        var direct: String = shaders_by_key.get(include_name, "")
        if direct.is_empty():
            push_error("GlobalShaderCompiler: no file provides include '" + include_name + "'.")
        return direct

    var owners: PackedStringArray = owners_of_name.get(include_name, PackedStringArray())
    for preferred: String in [owner_of(including_file_path), CORE_OWNER]:
        if owners.has(preferred):
            return shaders_by_key[preferred + "/" + include_name]
    if owners.size() == 1:
        return shaders_by_key[owners[0] + "/" + include_name]
    if owners.size() > 1:
        push_error(
            (
                "GlobalShaderCompiler: include '%s' required by %s is provided by %s. Qualify it as <owner>/%s."
                % [include_name, including_file_path, ", ".join(owners), include_name]
            )
        )
        return ""

    push_error("GlobalShaderCompiler: no file provides include '" + include_name + "'.")
    return ""


## Records a compiled kernel for the summary rather than printing a line each.
##
## Twenty separate "Compiled Kernel: x" lines scroll the useful information off
## the screen. Grouped by shader, a missing kernel is visible at a glance.
func print_kernel_compiled(k_name: String, compute_shader_name: String) -> void:
    if not _compiled_kernels.has(compute_shader_name):
        _compiled_kernels[compute_shader_name] = PackedStringArray()
    _compiled_kernels[compute_shader_name].append(k_name)


## How a shader key is written for a human: Sara's own shaders keep the bare name
## they have always printed under, a module's carries its owner.
func display_name(key: String) -> String:
    return key.trim_prefix(CORE_OWNER + "/")


## Records a shader that declared no kernels as a library, for the report.
func note_include(shader_name: String) -> void:
    _compiled_includes.append(display_name(shader_name))


## Prints what was compiled, grouped by shader file. Called once after the
## initial compilation pass, by the boot header.
##
## The SPIR-V cache prune is the compiler's own, at the end of the pass this
## reports on, rather than here, because a headless run builds no boot header
## and the gate, which writes most of the entries, would prune nothing.
func report_compilation() -> void:
    var kernel_total: int = 0
    for shader_name: String in _compiled_kernels:
        kernel_total += _compiled_kernels[shader_name].size()

    SaConsole.section("SHADERS", "%d files  ·  %d kernels" % [_compiled_kernels.size(), kernel_total])
    var names: Array = _compiled_kernels.keys()
    names.sort()
    for shader_name: String in names:
        # Without the ".gmacs". Every file in shaders/compute/ is one, so the
        # extension is a constant rather than a fact, and it was spending six
        # of the eighteen columns the name has.
        var kernels: PackedStringArray = _compiled_kernels[shader_name]
        SaConsole.row(display_name(shader_name), str(kernels.size()), ", ".join(kernels))
    if not _compiled_includes.is_empty():
        SaConsole.row("libs", str(_compiled_includes.size()), ", ".join(_compiled_includes), SaConsole.DIM)
    SaConsole.blank()
