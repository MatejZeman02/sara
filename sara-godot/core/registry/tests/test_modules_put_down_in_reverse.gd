## Modules are put down in the reverse of the order they came up.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The loader registers a dependency before what depends on it, and puts
## them down in the reverse order, so a dependent's `unregister` ran after its
## dependency had already left. Two fixture modules under
## `res://tests/fixtures/module-dependencies/modules`, the first discovered depending on the
## second, write their ids to one list on the engine as they are put down, and
## each case reads that list.
extends "res://tests/test_framework.gd"

## Loads the packaged modules beside the fixtures, and they compile kernels.
const REQUIRES_GPU := true

const ROOT := "res://tests/fixtures/module-dependencies/modules"
const DEPENDENT := &"d1-a-dependent"
const BASE := &"d1-b-base"
const LIST := &"d1_put_down"

var _registries: SaRegistries
## The modules an earlier suite left loaded, set aside while this one runs.
var _kept: Dictionary = {}


func before_each() -> void:
    # `unload_all` puts down every loaded module, and one an earlier suite
    # left would go with the fixtures, taking the PNG format out of the
    # registry that suite installed and every suite after it reads. So the
    # loader holds only what this suite brings up, and gets the rest back.
    _kept = ModuleLoader.loaded_modules.duplicate()
    ModuleLoader.loaded_modules.clear()
    Engine.set_meta(LIST, [])
    _registries = SaRegistries.new()
    _registries.build_context(func() -> Variant: return null, func() -> Array: return [])
    ModuleLoader.user_modules_root = ROOT
    ModuleLoader.verbose = false
    ModuleLoader.load_and_register_modules(_registries.context)
    ModuleLoader.verbose = true


func after_each() -> void:
    ModuleLoader.unload_all()
    ModuleLoader.user_modules_root = SaDataRoot.path(ModuleLoader.USER_MODULES_FOLDER)
    for key: StringName in [DEPENDENT, BASE]:
        ModuleLoader.origins.erase(key)
        ModuleLoader.module_dirs.erase(key)
        ModuleLoader.failed_modules.erase(key)
        ModuleLoader.kernel_results.erase(key)
    Engine.remove_meta(LIST)
    _registries = null
    ModuleLoader.loaded_modules.merge(_kept)
    _kept = {}


func _put_down() -> Array:
    return Engine.get_meta(LIST) as Array


func test_the_dependency_comes_up_first() -> void:
    var ids: Array = ModuleLoader.loaded_modules.keys()
    assert_true(ids.has(DEPENDENT) and ids.has(BASE), "Both fixtures load")
    assert_true(ids.find(BASE) < ids.find(DEPENDENT), "and the dependency registers before its dependent")


func test_unload_all_puts_the_dependent_down_first() -> void:
    ModuleLoader.unload_all()
    assert_eq(_put_down(), [String(DEPENDENT), String(BASE)], "The dependent leaves before what it depends on")


func test_the_reload_puts_the_dependent_down_first() -> void:
    ModuleLoader.verbose = false
    var record := ModuleLoader.reload_user_modules()
    ModuleLoader.verbose = true
    assert_eq(_put_down(), [String(DEPENDENT), String(BASE)], "The reload puts the dependent down first too")
    var reloaded := Array(record["reloaded"])
    assert_true(reloaded.has(DEPENDENT) and reloaded.has(BASE), "and both come back up")
