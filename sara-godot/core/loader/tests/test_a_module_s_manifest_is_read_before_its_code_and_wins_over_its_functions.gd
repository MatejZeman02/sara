## A module's manifest is read before its code and wins over its functions.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The fixture root holds a module described by a `manifest.cfg` alone, one by
## its functions alone, one by both, one by neither, one whose manifest asks
## for a dependency newer than the one that loaded, one whose dependencies are
## new enough, and one whose manifest names no semantic version. A loader of the
## suite's own reads it as its packaged root, so the app's modules are never
## put down or read again.
extends "res://tests/test_framework.gd"

const LOADER := preload("res://core/loader/module_loader.gd")
const ROOT := "res://tests/fixtures/module-manifests/modules"
const CODE_RAN := &"code_ran"

var _loader: Node = null
var _registries: SaRegistries = null
var _formerly: String = ""


func before_each() -> void:
    Engine.remove_meta(CODE_RAN)
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
    Engine.remove_meta(CODE_RAN)
    if _formerly.is_empty():
        OS.unset_environment(LOADER.PACKAGED_ROOT_VARIABLE)
    else:
        OS.set_environment(LOADER.PACKAGED_ROOT_VARIABLE, _formerly)


func test_a_module_with_a_manifest_alone_is_what_the_manifest_says() -> void:
    assert_true(_loader.is_loaded(&"with_manifest"), "the manifest's id is the module's")
    var manifest: SaModuleManifest = _loader.manifest_of(&"with_manifest")
    assert_true(manifest.has_file, "the folder's manifest was read")
    assert_eq(manifest.name, "With a Manifest", "its name")
    assert_eq(manifest.version, "2.1.0", "its version")
    assert_eq(manifest.description, "Says everything in its manifest.", "its sentence")
    assert_eq(Array(manifest.authors), ["A Student"], "its authors")
    assert_eq(manifest.license, "GPL-3.0-or-later", "its licence")
    assert_eq(manifest.website, "https://example.org/probe", "its website")
    assert_eq(Array(manifest.tags), ["fixture"], "its tags")


func test_a_manifest_wins_over_the_functions_and_a_function_fills_what_it_leaves_out() -> void:
    assert_true(_loader.is_loaded(&"both"), "the manifest's id wins over get_id()")
    assert_false(_loader.is_loaded(&"from_code"), "and the function's id is no module")
    var manifest: SaModuleManifest = _loader.manifest_of(&"both")
    assert_eq(manifest.version, "3.0.0-beta.2", "the manifest's version wins over get_version()")
    assert_eq(manifest.name, "Both, Named in Code", "the name the manifest leaves out is the function's")
    assert_eq(_loader.module_names[&"both"], "Both, Named in Code", "and the loader lists it under that name")


func test_a_module_with_functions_only_is_what_its_functions_say() -> void:
    assert_true(_loader.is_loaded(&"functions_only"), "a module with no manifest loads as it did")
    var manifest: SaModuleManifest = _loader.manifest_of(&"functions_only")
    assert_false(manifest.has_file, "it has no manifest")
    assert_eq(manifest.version, "1.2.3", "its version is its function's")
    assert_eq(manifest.name, "Functions Only", "and so is its name")


func test_a_module_with_neither_has_its_folder_s_name_and_no_version() -> void:
    assert_true(_loader.is_loaded(&"neither"), "a module with neither takes its folder's name as its id")
    assert_eq(_loader.manifest_of(&"neither").version, "0.0.0", "and 0.0.0 as its version")


func test_a_dependency_too_old_refuses_the_module_with_one_line_saying_which_and_why() -> void:
    assert_false(_loader.is_loaded(&"too_old"), "a module whose dependency is too old does not load")
    assert_eq(
        _loader.failed_modules.get(&"too_old", ""),
        "unsatisfied dependencies: functions_only 1.2.3 is older than the 2.0.0 it needs",
        "and its one line names the dependency, the version that loaded and the one it needs"
    )


func test_dependencies_new_enough_let_the_module_load() -> void:
    assert_true(_loader.is_loaded(&"new_enough"), "a dependency at the version asked or newer, or any, will do")


func test_a_manifest_is_read_before_any_of_the_module_s_code_runs() -> void:
    assert_eq(
        _loader.failed_modules.get(&"unreadable_version", ""),
        "the version in its manifest.cfg, 1.0, is not a semantic version",
        "a manifest whose version is no semantic version refuses its module"
    )
    assert_false(Engine.has_meta(CODE_RAN), "before the module's script was ever made")


func test_semantic_versions_are_ordered_as_the_rule_orders_them() -> void:
    assert_eq(SaModuleManifest.compare("1.2.3", "1.10.0"), -1, "numbers compare as numbers")
    assert_eq(SaModuleManifest.compare("2.0.0-beta.2", "2.0.0"), -1, "a pre-release is older than its release")
    assert_eq(SaModuleManifest.compare("2.0.0-beta.11", "2.0.0-beta.2"), 1, "numeric pre-release parts compare as numbers")
    assert_eq(SaModuleManifest.compare("1.0.0+build.5", "1.0.0"), 0, "build metadata takes no part")
    for wrong: String in ["1.0", "01.0.0", "1.0.0-", "a.b.c", ""]:
        assert_false(SaModuleManifest.is_semver(wrong), "%s is no semantic version" % wrong)
