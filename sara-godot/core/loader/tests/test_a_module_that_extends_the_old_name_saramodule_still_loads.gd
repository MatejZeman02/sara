## A module that extends the old name `SaraModule` still loads.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The base class is `SaModule` now, and `SaraModule` stays as a class that
## extends it, for a module written outside the tree. The fixture root holds
## one such module, read by a loader of the suite's own as its packaged root,
## so the app's own modules are never put down or read again.
extends "res://tests/test_framework.gd"

const LOADER := preload("res://core/loader/module_loader.gd")
const ROOT := "res://tests/fixtures/old-name-module/modules"
const OLD_NAME := &"old_name"

var _loader: Node = null
var _registries: SaRegistries = null
var _formerly: String = ""


func before_each() -> void:
    _formerly = OS.get_environment(LOADER.PACKAGED_ROOT_VARIABLE)
    OS.set_environment(LOADER.PACKAGED_ROOT_VARIABLE, ROOT)
    _registries = SaRegistries.new()
    _registries.build_context(func() -> Variant: return null, func() -> Array: return [])
    _loader = LOADER.new()
    _loader.verbose = false
    # An empty user root of the suite's own, so the painter's modules stay out.
    _loader.user_modules_root = ROOT.path_join("none")
    _loader.load_and_register_modules(_registries.context, [])


func after_each() -> void:
    _loader.unload_all()
    _loader.free()
    if _formerly.is_empty():
        OS.unset_environment(LOADER.PACKAGED_ROOT_VARIABLE)
    else:
        OS.set_environment(LOADER.PACKAGED_ROOT_VARIABLE, _formerly)


func test_the_old_name_is_the_new_class() -> void:
    var old := SaraModule.new()
    assert_true(old is SaModule, "a SaraModule is a SaModule, so the loader takes it as one")


func test_a_module_that_extends_saramodule_loads_and_registers() -> void:
    assert_true(_loader.is_loaded(OLD_NAME), "the module written against the old name loads")
    var filter: SaFilter = load(ROOT.path_join("old-name/kept.gd")).new()
    var key := SaFilterRegistry.key_for(OLD_NAME, filter)
    assert_true(_registries.filters.has(key), "and the filter its register() names is registered")
