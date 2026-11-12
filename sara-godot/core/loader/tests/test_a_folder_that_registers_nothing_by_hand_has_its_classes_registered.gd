## A module that registers nothing by hand has what its folder holds registered
## for it.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A painter asked for Blender's `auto_load`. The fixture root holds three
## folders: one with no `module.gd`, two filters and a tool, one whose
## `module.gd` leaves `register()` alone, and one that registers one of its two
## filters by hand. A loader of the suite's own reads the root as its packaged
## one, so the app's own modules are never put down or read again, and no
## kernel is compiled.
extends "res://tests/test_framework.gd"

const LOADER := preload("res://core/loader/module_loader.gd")
const ROOT := "res://tests/fixtures/modules-registering-by-hand/modules"
const NO_MODULE := &"no_module"
const DEFAULT_REGISTER := &"default_register"
const BY_HAND := &"by_hand"

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


func _filter_key(module_id: StringName, script_name: String) -> StringName:
    var filter: SaFilter = load(ROOT.path_join(String(module_id).replace("_", "-")).path_join(script_name)).new()
    return SaFilterRegistry.key_for(module_id, filter)


func test_a_folder_with_no_module_gd_loads_under_its_folders_name() -> void:
    assert_true(_loader.is_loaded(NO_MODULE), "the folder is a module, its hyphens read as underscores")
    var named: String = _loader.module_names.get(NO_MODULE, "")
    assert_eq(named, "No Module", "and the Modules menu names it after the folder, as capitalize() spells it")


func test_its_two_filters_and_its_tool_are_registered() -> void:
    var filters := _registries.filters
    assert_true(filters.has(_filter_key(NO_MODULE, "tint.gd")), "the first filter")
    assert_true(filters.has(_filter_key(NO_MODULE, "shade.gd")), "the second filter")
    assert_true(_registries.tools.has(&"tool"), "and the tool")
    assert_eq(_registries.tools.get_descriptor(&"tool").owner_module, NO_MODULE, "each attributed to the folder's module")


func test_a_module_gd_that_leaves_register_alone_has_its_folder_registered() -> void:
    assert_true(_loader.is_loaded(DEFAULT_REGISTER), "the module loads")
    assert_true(_registries.filters.has(_filter_key(DEFAULT_REGISTER, "glow.gd")), "and its filter is registered for it")


func test_a_module_that_registers_by_hand_registers_only_what_it_names() -> void:
    assert_true(_loader.is_loaded(BY_HAND), "the module loads")
    assert_true(_registries.filters.has(_filter_key(BY_HAND, "kept.gd")), "the filter its register() names")
    assert_false(_registries.filters.has(_filter_key(BY_HAND, "left.gd")), "and not the one it left out")


func test_a_script_the_door_does_not_register_is_left_alone() -> void:
    var state := load(ROOT.path_join("no-module/state.gd")) as Script
    assert_false(SaModule.FolderRegistration.registrable(state), "a tool state is the tool's helper")
    var tool := load(ROOT.path_join("no-module/tool.gd")) as Script
    assert_true(SaModule.FolderRegistration.registrable(tool), "a descriptor that writes itself is registered")
