## Modules > Reload Modules reads a user module the way a start does.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## copied the box blur into the user folder, reloaded it, and the console
## logged `Could not resolve super class path "res://tests/test_framework.gd"`
## for each script in the copy's `tests` folder. The zip ships no `res://tests/`,
## so a test script there has no base class to resolve. The module loaded all the
## same, and the next start read the folder with no error, because a start loads
## `module.gd` and what it preloads and nothing else. The reload read every
## script under the folder from disk again, the tests among them.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

static var scratch_root: String = SaDataRoot.path("test_d3_reload/modules")
const MODULE_ID := &"d3_probe"

const MODULE := """extends SaModule

const Names = preload("names.gd")


func get_id() -> StringName:
    return &"d3_probe"


func get_name() -> String:
    return Names.title()


func register(_ctx: SaContext) -> void:
    pass
"""

const NAMES := """extends RefCounted


static func title() -> String:
    return "%s"
"""

## A test script whose base class the zip does not ship, which nothing in the
## module preloads.
const STRAY_TEST := """extends "res://tests/no_such_base_class.gd"

func test_nothing() -> void:
    pass
"""

var _registries: SaRegistries


func before_each() -> void:
    _stage("d3-copy", "Before")
    _registries = SaRegistries.new()
    _registries.build_context(func() -> Variant: return null, func() -> Array: return [])
    ModuleLoader.user_modules_root = scratch_root
    ModuleLoader.verbose = false
    ModuleLoader.load_and_register_modules(_registries.context)
    ModuleLoader.verbose = true


func after_each() -> void:
    ModuleLoader.unload_all()
    ModuleLoader.user_modules_root = SaDataRoot.path(ModuleLoader.USER_MODULES_FOLDER)
    _registries = null
    _remove(ProjectSettings.globalize_path(scratch_root.get_base_dir()))


func _stage(folder: String, title: String) -> String:
    var dir := scratch_root.path_join(folder)
    _write(dir.path_join("module.gd"), MODULE)
    _write(dir.path_join("names.gd"), NAMES % title)
    return dir


func _write(path: String, text: String) -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_string(text)
    file.close()


func _remove(absolute: String) -> void:
    if not DirAccess.dir_exists_absolute(absolute):
        return
    for sub in DirAccess.get_directories_at(absolute):
        _remove(absolute.path_join(sub))
    for file_name in DirAccess.get_files_at(absolute):
        DirAccess.remove_absolute(absolute.path_join(file_name))
    DirAccess.remove_absolute(absolute)


## Reloads with the engine's own errors counted, and answers the record and the
## errors logged while the reload ran.
func _reload_counting_errors() -> Dictionary:
    var errors := SaErrorCatcher.new()
    ModuleLoader.verbose = false
    OS.add_logger(errors)
    var record := ModuleLoader.reload_user_modules()
    OS.remove_logger(errors)
    ModuleLoader.verbose = true
    return {"record": record, "errors": errors.described(SaErrorCatcher.RAISED)}


func test_a_test_script_the_module_never_preloads_is_not_read_by_the_reload() -> void:
    var dir := scratch_root.path_join("d3-copy")
    _write(dir.path_join("tests").path_join("test_probe.gd"), STRAY_TEST)
    _write(dir.path_join("tests").path_join("deeper").path_join("test_deeper.gd"), STRAY_TEST)

    var reloaded := _reload_counting_errors()

    assert_eq(reloaded["errors"], PackedStringArray(), "The reload logs no engine error for the tests folder")
    assert_true(Array(reloaded["record"]["reloaded"]).has(MODULE_ID), "and the module is among the ones it read again")
    assert_true(Dictionary(reloaded["record"]["failed"]).is_empty(), "with nothing refused")
    assert_true(ModuleLoader.is_loaded(MODULE_ID), "The module is loaded")


func test_a_script_the_module_preloads_is_still_read_again() -> void:
    var dir := scratch_root.path_join("d3-copy")
    _write(dir.path_join("tests").path_join("test_probe.gd"), STRAY_TEST)
    _write(dir.path_join("names.gd"), NAMES % "After")

    var reloaded := _reload_counting_errors()

    assert_eq(reloaded["errors"], PackedStringArray(), "The reload logs no engine error")
    var module: SaModule = ModuleLoader.loaded_modules[MODULE_ID]
    assert_eq(module.get_name(), "After", "and the edit to a script module.gd preloads is what the reload registered")


func test_a_folder_a_start_would_not_read_is_no_more_read_when_it_is_named_something_else() -> void:
    var dir := scratch_root.path_join("d3-copy")
    _write(dir.path_join("spec").path_join("stray.gd"), STRAY_TEST)

    var reloaded := _reload_counting_errors()

    assert_eq(reloaded["errors"], PackedStringArray(), "A stray script in any folder is left alone, not only `tests`")
    assert_true(ModuleLoader.is_loaded(MODULE_ID), "and the module is loaded")
