## A folder under the user's modules named like a packaged module is refused,
## and stays refused, without touching the packaged one.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Copying the kaleidoscope's folder into `user://modules` as it was. The
## refusal was filed, and behind it the folder's origin and path had already
## been written under the packaged module's id, so the boot listed the packaged
## kaleidoscope as the user's, compiled the copy's kernel beside the packaged
## one, and Modules > Reload put the packaged module down and loaded the copy in
## its place. The staged copy here carries a kernel of its own name, so a
## compile of it shows in the compiler's list rather than as a clash.
extends "res://tests/test_framework.gd"

## Loads the packaged modules and compiles kernels.
const REQUIRES_GPU := true

static var scratch_root: String = SaDataRoot.path("test_d24_clash/modules")
const PACKAGED_ID := &"kaleidoscope"
const REFUSED_ID := &"kaleidoscope (user)"

const MODULE := """extends SaModule


func get_id() -> StringName:
    return &"kaleidoscope"


func get_name() -> String:
    return "Kaleidoscope, the painter's copy"


func register(_ctx: SaContext) -> void:
    pass
"""

const KERNEL := """kernel d24_probe

image canvas

def d24_probe():
    ivec2 at = ivec2(global_id.xy)
    image_store(canvas, at, vec4(0.5, 0.0, 0.0, 1.0))
"""

var _kernel_path := scratch_root.path_join("kaleidoscope").path_join("d24_probe.gmacs")


func before_each() -> void:
    var dir := scratch_root.path_join("kaleidoscope")
    _write(dir.path_join("module.gd"), MODULE)
    _write(_kernel_path, KERNEL)
    var registries := SaRegistries.new()
    registries.build_context(func() -> Variant: return null, func() -> Array: return [])
    ModuleLoader.user_modules_root = scratch_root
    ModuleLoader.verbose = false
    # Nothing is switched off, so the shipped kaleidoscope loads whatever the
    # profile on this machine says.
    ModuleLoader.load_and_register_modules(registries.context, [])
    ModuleLoader.verbose = true


func after_each() -> void:
    ModuleLoader.unload_all()
    ModuleLoader.user_modules_root = SaDataRoot.path(ModuleLoader.USER_MODULES_FOLDER)
    # A compile of the copy is the bug, and a later reload of every kernel must
    # not read a file this suite deleted, so the lists are cleaned either way.
    GlobalShaderCompiler.index.compute_shader_file_paths.erase(_kernel_path)
    GlobalShaderCompiler.index.shaders_by_key.erase(GlobalShaderCompiler.index.shader_key(_kernel_path))
    ModuleLoader.origins.erase(REFUSED_ID)
    ModuleLoader.module_dirs.erase(REFUSED_ID)
    ModuleLoader.failed_modules.erase(REFUSED_ID)
    _remove(ProjectSettings.globalize_path(scratch_root.get_base_dir()))


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


## What both the boot and the reload have to leave: the packaged module loaded
## and filed as packaged from its own folder, the copy refused under its key.
func _assert_the_packaged_module_won(when: String) -> void:
    assert_true(ModuleLoader.is_loaded(PACKAGED_ID), "%s the packaged kaleidoscope is loaded" % when)
    assert_eq(
        ModuleLoader.loaded_modules[PACKAGED_ID].get_name(), "Kaleidoscope", "%s as the packaged module, not the copy" % when
    )
    assert_eq(ModuleLoader.origins.get(PACKAGED_ID), "packaged", "%s and filed as packaged" % when)
    assert_eq(
        ModuleLoader.module_dirs.get(PACKAGED_ID), "res://modules/sara-base-modules/kaleidoscope", "%s from its own folder" % when
    )
    assert_false(ModuleLoader.failed_modules.has(PACKAGED_ID), "%s with no refusal under its id" % when)
    assert_true(
        String(ModuleLoader.failed_modules.get(REFUSED_ID, "")).contains("duplicate module id"),
        "%s the copy is refused under a key of its own" % when
    )
    assert_eq(ModuleLoader.origins.get(REFUSED_ID), "user", "%s and filed as the user's" % when)
    assert_eq(
        ModuleLoader.module_dirs.get(REFUSED_ID),
        scratch_root.path_join("kaleidoscope"),
        "%s against the folder it came from" % when
    )
    assert_false(ModuleLoader.kernel_results.has(PACKAGED_ID), "%s nothing compiled a user folder for that id" % when)
    assert_false(
        GlobalShaderCompiler.index.compute_shader_file_paths.has(_kernel_path),
        "%s and the refused copy's kernel was never compiled" % when
    )


func test_the_boot_leaves_the_packaged_module_in_place() -> void:
    _assert_the_packaged_module_won("After the boot")


func test_the_reload_keeps_the_packaged_module_and_the_refusal() -> void:
    var packaged: SaModule = ModuleLoader.loaded_modules[PACKAGED_ID]
    ModuleLoader.verbose = false
    var record := ModuleLoader.reload_user_modules()
    ModuleLoader.verbose = true

    _assert_the_packaged_module_won("After the reload")
    assert_true(ModuleLoader.loaded_modules[PACKAGED_ID] == packaged, "The packaged module was never put down")
    assert_false(Array(record["reloaded"]).has(PACKAGED_ID), "The reload does not claim to have read it again")
    assert_true(Dictionary(record["failed"]).has(REFUSED_ID), "and its record names the refusal it asked again")
