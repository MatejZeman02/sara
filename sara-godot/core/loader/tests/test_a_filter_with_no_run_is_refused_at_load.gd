## A module whose filter does not write `run` is refused when it loads, with a
## sentence naming the file and the method.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## `run` was a method of `SaFilter` with an empty body, and `SaFilterApply`
## checked `has_method("run")` before calling it. Every filter passed that check
## by inheriting the empty body, so a filter that forgot `run` loaded, ran
## nothing and was caught only by the report that it showed no result. `run` is
## `@abstract` now, a filter without it does not parse, and the loader reads the
## folder's text first, so the Modules menu says which file and which method.
extends "res://tests/test_framework.gd"

## Loads the packaged modules beside the staged ones, which compiles kernels.
const REQUIRES_GPU := true

const ModuleLoaderScript = preload("res://core/loader/module_loader.gd")

static var scratch_root: String = SaDataRoot.path("test_a10_abstract/modules")
const NO_RUN_ID := &"a10_no_run"
const WITH_RUN_ID := &"a10_with_run"

const MODULE := """extends SaModule

const Filter = preload("%s")


func get_id() -> StringName:
    return &"%s"


func register(ctx: SaContext) -> void:
    ctx.register_filter(Filter.new())
"""

const NO_RUN := """extends SaFilter


func title() -> String:
    return "No run"
"""

const WITH_RUN := """extends SaFilter


func title() -> String:
    return "With run"


func run(ctx: SaFilterContext) -> void:
    ctx.show(null)
"""

## A filter that inherits `run` from a class that writes it, which is not a
## gap.
const INHERITS_RUN := """extends SaPixelFilter


func title() -> String:
    return "Pixel"
"""

## A filter that reaches the base by its path rather than its name.
const BY_PATH := """extends "res://core/api/filter/sa_filter.gd"


func title() -> String:
    return "By path"
"""

var _registries: SaRegistries


func before_each() -> void:
    _stage(NO_RUN_ID, NO_RUN_ID, "no_run.gd", NO_RUN)
    _stage(WITH_RUN_ID, WITH_RUN_ID, "with_run.gd", WITH_RUN)
    _registries = SaRegistries.new()
    _registries.build_context(func() -> Variant: return null, func() -> Array: return [])
    ModuleLoader.user_modules_root = scratch_root
    ModuleLoader.verbose = false
    ModuleLoader.load_and_register_modules(_registries.context)
    ModuleLoader.verbose = true


func after_each() -> void:
    ModuleLoader.unload_all()
    ModuleLoader.user_modules_root = SaDataRoot.path(ModuleLoader.USER_MODULES_FOLDER)
    for key: StringName in [NO_RUN_ID, WITH_RUN_ID]:
        ModuleLoader.origins.erase(key)
        ModuleLoader.module_dirs.erase(key)
        ModuleLoader.failed_modules.erase(key)
    _registries = null
    _remove(ProjectSettings.globalize_path(scratch_root.get_base_dir()))


func _stage(folder: StringName, module_id: StringName, file_name: String, filter: String) -> String:
    var dir := scratch_root.path_join(String(folder))
    _write(dir.path_join("module.gd"), MODULE % [file_name, module_id])
    _write(dir.path_join(file_name), filter)
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


func test_a_filter_with_no_run_is_refused_naming_the_method() -> void:
    var reason := String(ModuleLoader.failed_modules.get(NO_RUN_ID, ""))
    assert_true(reason.contains("run()"), "The refusal names the method: %s" % reason)
    assert_true(reason.contains("no_run.gd"), "and the file that leaves it out")
    assert_true(reason.contains("SaFilter"), "and the class that declares it abstract")
    assert_false(ModuleLoader.is_loaded(NO_RUN_ID), "The module is not loaded")
    assert_false(_registries.filters.has(StringName("%s.no_run" % NO_RUN_ID)), "and its filter never reached the menu")


func test_a_filter_that_writes_run_loads_beside_it() -> void:
    assert_true(ModuleLoader.is_loaded(WITH_RUN_ID), "The module whose filter writes run loads")
    assert_false(ModuleLoader.failed_modules.has(WITH_RUN_ID), "and nothing refuses it")


func test_a_run_inherited_from_a_class_that_writes_it_is_no_gap() -> void:
    var dir := _stage(&"a10_inherits", &"a10_inherits", "pixel.gd", INHERITS_RUN)
    assert_eq(ModuleLoaderScript.UnwrittenAbstracts.refusal(dir), "", "SaPixelFilter writes run, so its filter owes none")


func test_a_base_reached_by_its_path_is_read_as_well() -> void:
    var dir := _stage(&"a10_by_path", &"a10_by_path", "by_path.gd", BY_PATH)
    var reason := ModuleLoaderScript.UnwrittenAbstracts.refusal(dir)
    assert_true(reason.contains("by_path.gd") and reason.contains("run()"), "A quoted base is resolved too: %s" % reason)
