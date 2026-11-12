## About names every loaded module with its version and the commit it was
## built from.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Every module of the tree carries a `manifest.cfg` with its real version, and
## the fold of About shows each one a line, as the loader's console line does.
## The skeleton's manifest is the project's own, at Sara's version.
extends "res://tests/test_framework.gd"

const LOADER := preload("res://core/loader/module_loader.gd")
const SKELETON := preload("res://core/loader/skeleton_module.gd")

## The modules the suite filed in the running loader, taken out again after.
var _filed: Array[StringName] = []
var _discovered: Dictionary[StringName, SaModule] = {}


## The suites run with no module loaded, so the tree's own are discovered by a
## loader of the suite's own, which reads every manifest and registers nothing,
## and filed in the running one for About to read, as a boot would.
func before_each() -> void:
    var loader: Node = LOADER.new()
    loader.verbose = false
    loader.user_modules_root = "res://tests/fixtures/module-manifests/none"
    _discovered = loader._discover_modules()
    for module_id: StringName in _discovered:
        if ModuleLoader.loaded_modules.has(module_id):
            continue
        ModuleLoader.loaded_modules[module_id] = _discovered[module_id]
        ModuleLoader.manifests[module_id] = loader.manifests[module_id]
        _filed.append(module_id)
    loader.free()


func after_each() -> void:
    for module_id in _filed:
        ModuleLoader.loaded_modules.erase(module_id)
        ModuleLoader.manifests.erase(module_id)
    _filed.clear()
    _discovered.clear()


func test_every_module_of_the_tree_has_a_manifest_and_about_names_its_version() -> void:
    var dialog := SaAboutDialog.new()
    dialog.refresh()
    var shown: String = (dialog.find_child("Modules", true, false) as Label).text
    assert_true(shown.begins_with(tr("Modules")), "the block is headed Modules: %s" % shown.left(40))
    assert_true(_discovered.has(&"sara-base-modules"), "the tree's modules were found")
    for module_id: StringName in _discovered:
        var manifest: SaModuleManifest = ModuleLoader.manifest_of(module_id)
        assert_true(manifest.has_file, "%s carries a %s" % [module_id, SaModuleManifest.FILE])
        assert_true(SaModuleManifest.is_semver(manifest.version), "%s has a semantic version" % module_id)
        var line := manifest.version_and_commit()
        assert_true(shown.contains(line), "About names %s at %s" % [module_id, line])
    dialog.free()


## The skeleton's folder is the project, so its manifest is `res://manifest.cfg`,
## and its version is the one `project.godot` gives Sara.
func test_the_skeleton_s_manifest_is_at_sara_s_version() -> void:
    var manifest := SaModuleManifest.of_module(SKELETON.new())
    assert_true(manifest.has_file, "the skeleton reads res://manifest.cfg")
    assert_eq(manifest.id, &"sara-skeleton", "under its id")
    var project := str(ProjectSettings.get_setting("application/config/version", ""))
    assert_eq(manifest.version, project, "and stands at Sara's own version")
    var checkout := ProjectSettings.globalize_path("res://").path_join("..")
    if manifest.commit.is_empty() and SaBuildInfo.checkout_commit(checkout).is_empty():
        skip("this tree has no .git beside it and no build stamp, so Sara's own commit is not known")
        return
    assert_false(manifest.commit.is_empty(), "built from the commit Sara was: %s" % manifest.commit)
