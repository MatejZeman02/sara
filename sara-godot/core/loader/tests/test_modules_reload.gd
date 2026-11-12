## Modules > Reload: a module in the user's folder is put down,
## read from disk again and registered, without a restart.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **Each case stages its own module in a folder of its own**, under
## `user://test_r1_reload/modules`, because Godot keys a script by its path and
## updates it in place: a case that left a script broken would hand the next
## case the broken one under the same path. The `modules` in the path is what
## files a kernel under the module's folder name, the owner rule of the shader
## index.
extends "res://tests/test_framework.gd"

## Loads the packaged modules and compiles kernels.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

static var scratch_root: String = SaDataRoot.path("test_r1_reload/modules")

const TOOL_ID := &"r1_probe"
const DOCKER_ID := &"R1ProbeDocker"

## The module. Its tool's name comes from the script beside it, so an edit to
## that script is what a reload has to read, which a cache mode on `module.gd`
## alone does not.
const MODULE := """extends SaModule

const Names = preload("names.gd")
const Fixtures = preload("res://tests/fixtures.gd")


func get_id() -> StringName:
    return &"%s"


func get_name() -> String:
    return "R1 Fixture"


func register(ctx: SaContext) -> void:
    var tool := SaToolDescriptor.create(&"r1_probe", Fixtures.FakeTool)
    tool.display_name = Names.title()
    ctx.register_tool(tool)
    ctx.register_docker(&"R1ProbeDocker", "R1 Probe", _make_docker)


func _make_docker() -> Window:
    return Window.new()
"""

const NAMES := """extends RefCounted


static func title() -> String:
    return "%s"
"""

const BROKEN_MODULE := """extends SaModule

func get_id() -> StringName:
    return &"r1-broken" +
"""

const KERNEL := """kernel r1_probe

image canvas

def r1_probe():
    ivec2 at = ivec2(global_id.xy)
    image_store(canvas, at, vec4(%s, 0.0, 0.0, 1.0))
"""

## What the case staged, taken out of the compiler's lists afterwards so no
## later reload of every kernel reads a file this suite deleted.
var _kernel_paths: Array[String] = []

## The surface the context lists, emptied at the end so the loader's context,
## which outlives the case, holds no easel.
var _surfaces: Array = []


func after_each() -> void:
    ModuleLoader.unload_all()
    ModuleLoader.user_modules_root = SaDataRoot.path(ModuleLoader.USER_MODULES_FOLDER)
    for file_path in _kernel_paths:
        GlobalShaderCompiler.index.compute_shader_file_paths.erase(file_path)
        GlobalShaderCompiler.index.shaders_by_key.erase(GlobalShaderCompiler.index.shader_key(file_path))
    _kernel_paths.clear()
    _surfaces.clear()
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


func _stage(module_id: String, title: String) -> String:
    var dir := scratch_root.path_join(module_id)
    _write(dir.path_join("module.gd"), MODULE % module_id)
    _write(dir.path_join("names.gd"), NAMES % title)
    return dir


func _load(surface: SaSurface = null) -> SaRegistries:
    if surface != null:
        _surfaces.append(surface)
    var registries := SaRegistries.new()
    var listed := _surfaces
    registries.build_context(func() -> Variant: return null, func() -> Array: return listed)
    ModuleLoader.user_modules_root = scratch_root
    ModuleLoader.verbose = false
    ModuleLoader.load_and_register_modules(registries.context)
    ModuleLoader.verbose = true
    return registries


func _reload() -> Dictionary:
    ModuleLoader.verbose = false
    var record := ModuleLoader.reload_user_modules()
    ModuleLoader.verbose = true
    return record


## The Done clause's first case: the edit is registered, the first load's docker
## Window is out of the tree, and the module is loaded once.
func test_an_edited_module_registers_its_new_code() -> void:
    var dir := _stage("r1-edit", "Before")
    var registries := _load()
    assert_eq(registries.tools.get_descriptor(TOOL_ID).display_name, "Before", "The first load registered the tool")

    # What the host does with a registered docker, done by hand because a suite
    # may not put a Window in the tree.
    var host := Node.new()
    var docker := Node.new()
    docker.name = String(DOCKER_ID)
    host.add_child(docker)
    registries.ui.set_docker_node(DOCKER_ID, docker)
    var loaded_before := ModuleLoader.loaded_modules.size()

    _write(dir.path_join("names.gd"), NAMES % "After")
    var record := _reload()

    assert_eq(Array(record["reloaded"]), [&"r1-edit"], "The reload names the module it read again")
    assert_eq(registries.tools.get_descriptor(TOOL_ID).display_name, "After", "and the tool carries the edited name")
    assert_null(docker.get_parent(), "The first load's docker is out of the tree")
    assert_null(host.get_node_or_null(String(DOCKER_ID)), "so its name is free for the second registration's Window")
    assert_true(registries.ui.has_docker(DOCKER_ID), "which the module registered again")
    assert_eq(ModuleLoader.loaded_modules.size(), loaded_before, "The module is loaded once, not twice")
    assert_true(ModuleLoader.is_loaded(&"sara-base-modules"), "and a packaged module stayed as it was")
    host.free()


## A surface on the module's tool is moved off it for the reload and put back on
## the tool the reload registered under the same id.
func test_the_painters_tool_is_put_back() -> void:
    _stage("r1-tool", "Before")
    var surface := Fixtures.make_surface(Vector2i(256, 256))
    var registries := _load(surface)
    var machine := ToolMachine.new()
    machine.name = "ToolMachine"
    machine._ready()
    machine.bind(surface, registries.tools, registries.roles)
    machine.set_active_tool(TOOL_ID)
    var before: ToolState = machine.active_tool

    _reload()

    assert_eq(machine.active_tool_name, TOOL_ID, "The surface is back on the module's tool")
    assert_true(machine.active_tool != before, "as the instance the second registration made")
    Fixtures.teardown(surface, machine)


## The second case: a module ships a kernel under `user://`, the load compiles
## it, and after an edit the reload hands it to `reload_changed`, which answers
## it under `rebuilt`.
func test_a_modules_kernel_is_compiled_and_rebuilt() -> void:
    var dir := _stage("r1-kernel", "Kernel")
    var kernel := dir.path_join("shaders").path_join("r1_probe.gmacs")
    _write(kernel, KERNEL % "0.25")
    _kernel_paths.append(kernel)
    _load()
    var key := GlobalShaderCompiler.index.shader_key(kernel)
    assert_eq(key, "r1-kernel/r1_probe", "The kernel is filed under the module's folder")
    var first: Dictionary = ModuleLoader.kernel_results.get(&"r1-kernel", {})
    assert_eq(Array(first.get("rebuilt", [])), [key], "and the load compiled it, which nothing did for user:// before")
    assert_true(GlobalShaderCompiler.index.compute_shader_file_paths.has(kernel), "and the scan's list now holds it")

    _write(kernel, KERNEL % "0.75")
    # The time a compile records is whole seconds, and this case edits inside
    # the second it compiled in, so it moves the time the way the next second
    # would, as `test_reload_shaders.gd` does.
    GlobalShaderCompiler.source.shader_mtimes[kernel] = 1
    var record := _reload()

    var again: Dictionary = record["kernels"].get(&"r1-kernel", {})
    assert_eq(Array(again.get("rebuilt", [])), [key], "The reload answers the edited kernel under rebuilt")
    assert_true(Dictionary(again.get("failed", {})).is_empty(), "and nothing failed")


## The third case: a `module.gd` that does not parse leaves the module down and
## filed with its reason, rather than the old code claiming it reloaded.
func test_a_module_that_does_not_parse_is_left_down_with_a_reason() -> void:
    var dir := _stage("r1-broken", "Broken")
    var registries := _load()
    assert_true(ModuleLoader.is_loaded(&"r1-broken"), "The module loaded to begin with")

    _write(dir.path_join("module.gd"), BROKEN_MODULE)
    # The parse error is the engine's own line, and the gate reads any script
    # error as a failed run, so it is kept off the console for this one load.
    Engine.print_error_messages = false
    var record := _reload()
    Engine.print_error_messages = true

    assert_false(ModuleLoader.is_loaded(&"r1-broken"), "It is down")
    assert_false(registries.tools.has(TOOL_ID), "and its tool went with it")
    assert_true(
        String(ModuleLoader.failed_modules.get(&"r1-broken", "")).contains("did not parse"), "It is filed with the reason"
    )
    assert_true(Dictionary(record["failed"]).has(&"r1-broken"), "and the reload's record says so")
