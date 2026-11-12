## A reloaded module's layers and the menus built once: a layer
## of a module's type takes the missing module's path while the module is down
## and resolves again once it is back.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The fixture module registers one layer type that stores nothing and borrows
## the skeleton's background kernel with a red of its own, so what the layer
## draws is read straight off the easel's output: red while the module is up,
## the grey under it while it is down. It also registers a resolve hook, a
## method of the module, which is the Callable into unloaded code the ask is
## about. Staged under `user://` like the reload suite, a folder per case, because
## Godot keys a script by its path and updates it in place.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

static var scratch_root: String = SaDataRoot.path("test_r2_reload/modules")

const TYPE_ID := &"r2_tint"
const TOOL_ID := &"r2_probe"

## The module. `%s` is its id, then the extra fields its type declares, so a
## case can stage the same type with a schema that moved.
const MODULE := """extends SaModule

const Fixtures = preload("res://tests/fixtures.gd")


func get_id() -> StringName:
    return &"%s"


func get_name() -> String:
    return "Reload Fixture"


func register(ctx: SaContext) -> void:
    var schema := SaFieldSpec.default_schema()
    %s
    var descriptor := SaLayerTypeDescriptor.create(&"r2_tint", schema)
    descriptor.display_name = "Reload Tint"
    descriptor.generator = "background"
    descriptor.generator_defaults = {"color": Color(1.0, 0.0, 0.0, 1.0)}
    descriptor.resolve = _resolve
    ctx.register_layer_type(descriptor)
    var tool := SaToolDescriptor.create(&"r2_probe", Fixtures.FakeTool)
    tool.display_name = "Reload Probe"
    ctx.register_tool(tool)


func _resolve(_layer: SaLayer, _grid_pos: Vector2i, _chunk: SaChunk) -> void:
    pass
"""

const NO_EXTRA := "pass"
const EXTRA_FIELD := 'schema.append(SaFieldSpec.create(&"height", RenderingDevice.DATA_FORMAT_R32_SFLOAT, false))'

var _surfaces: Array = []


func after_each() -> void:
    ModuleLoader.unload_all()
    ModuleLoader.user_modules_root = SaDataRoot.path(ModuleLoader.USER_MODULES_FOLDER)
    for surface: SaSurface in _surfaces:
        Fixtures.teardown(surface)
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


func _stage(module_id: String, extra: String = NO_EXTRA) -> void:
    _write(scratch_root.path_join(module_id).path_join("module.gd"), MODULE % [module_id, extra])


## The loader over a surface whose document the context lists, with the
## skeleton's blend modes the compositor draws with.
func _load() -> SaRegistries:
    var surface := Fixtures.make_surface(Vector2i(256, 256))
    _surfaces.append(surface)
    var registries := SaRegistries.new()
    var listed := _surfaces
    registries.build_context(func() -> SaEasel: return surface.easel, func() -> Array: return listed)
    registries.register_builtins()
    surface.easel.compositor.set_registry(registries.blend_modes)
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


## A layer of the fixture's type, added above the active layer, which is the
## top of a default document.
func _tint_layer(registries: SaRegistries) -> SaLayer:
    var document: SaDocument = (_surfaces[0] as SaSurface).get_document()
    var layer := SaLayerOps.new(document).add(TYPE_ID, registries.layer_types)
    layer.name = "Tint"
    document.update_caches()
    return layer


## The centre texel of the composited document.
func _drawn() -> Color:
    var easel: SaEasel = (_surfaces[0] as SaSurface).easel
    easel.document.update_caches()
    easel.request_full_composite()
    easel.process_pending_composite()
    var data: PackedByteArray = GlobalShaderCompiler.get_rd().texture_get_data(easel.output.rid, 0)
    var at := (128 * easel.output.size.x + 128) * 16
    return Color(data.decode_float(at), data.decode_float(at + 4), data.decode_float(at + 8), data.decode_float(at + 12))


func _field_ids(layer: SaLayer) -> Array[StringName]:
    var ids: Array[StringName] = []
    for spec in layer.schema:
        ids.append(spec.id)
    return ids


## The Done clause's first case: down, the layer keeps its fields, its schema
## and its type id and has no hook, and draws nothing of its own. Back, it
## resolves and draws what it drew before.
func test_a_layer_of_an_unloaded_type_goes_inert_and_resolves_after_the_load() -> void:
    _stage("r2-tint")
    var registries := _load()
    var layer := _tint_layer(registries)
    var params := layer.generator_params.duplicate()
    var fields := _field_ids(layer)
    assert_true(layer.resolve_hook.is_valid(), "The layer resolves while its module is up")
    var before := _drawn()
    assert_almost_eq(before.r, 1.0, 0.001, "and draws the module's red")
    assert_almost_eq(before.g, 0.0, 0.001, "and nothing of the grey under it")

    ModuleLoader.unload_module(&"r2-tint", registries.context.open_layers())

    assert_false(registries.layer_types.has(TYPE_ID), "The type is gone with its module")
    assert_eq(layer.layer_type, TYPE_ID, "The layer keeps its type id")
    assert_eq(_field_ids(layer), fields, "and its schema")
    assert_eq(layer.generator_params, params, "and its parameters")
    assert_false(layer.resolve_hook.is_valid(), "and has no hook into the code that went")
    assert_eq(layer.generator, "", "nor a generator")
    var down := _drawn()
    assert_true(down.g > 0.1, "Down, it draws nothing, and the grey under it shows: %s" % down)

    _reload()

    assert_true(registries.layer_types.has(TYPE_ID), "The reload registers the type again")
    assert_true(layer.resolve_hook.is_valid(), "and the layer resolves again")
    assert_eq(layer.generator, "background", "with its generator back")
    var after := _drawn()
    assert_almost_eq(after.r, before.r, 0.001, "It draws what it drew before")
    assert_almost_eq(after.g, before.g, 0.001, "channel by channel")


## A reload of a module that is up goes through both halves in one call, and the
## hook the layer ends with is the new module's and not the old one's.
func test_a_reload_hands_the_layer_the_new_modules_hook() -> void:
    _stage("r2-hook")
    var registries := _load()
    var layer := _tint_layer(registries)
    var first: Object = layer.resolve_hook.get_object()

    var record := _reload()

    assert_true(record["reloaded"].has(&"r2-hook"), "The module reloaded: %s" % record)
    assert_true(layer.resolve_hook.is_valid(), "The layer resolves after the reload")
    assert_true(layer.resolve_hook.get_object() != first, "through the module the reload made")
    assert_almost_eq(_drawn().r, 1.0, 0.001, "and draws its red")


## A type reloaded with another schema keeps the chunks the old one allocated,
## and the registry names the drift the reload prints.
func test_a_moved_schema_is_kept_and_named() -> void:
    _stage("r2-drift")
    var registries := _load()
    var layer := _tint_layer(registries)
    assert_true(registries.layer_types.schema_drift([layer]).is_empty(), "No drift before the edit")

    _stage("r2-drift", EXTRA_FIELD)
    _reload()

    assert_eq(_field_ids(layer), [&"albedo"] as Array[StringName], "The layer keeps the schema it was made with")
    var drift := registries.layer_types.schema_drift([layer])
    assert_eq(drift.size(), 1, "and the registry names the one layer whose type moved")
    assert_true(drift[0].contains("Restart"), "saying what the painter does about it: %s" % str(drift))


## The second Done case: the Tools menu holds the fixture's tool after a reload
## with nothing but the open the bar makes. The menu is filled on every open,
## which is why nothing new listens here.
func test_the_tools_menu_holds_the_reloaded_tool() -> void:
    _stage("r2-menu")
    var registries := _load()
    var surface: SaSurface = _surfaces[0]
    var machine := ToolMachine.new()
    machine.name = "ToolMachine"
    machine._ready()
    machine.bind(surface, registries.tools, registries.roles)
    var bar := TopMenuBar.new()
    bar._ready()
    var menu := bar.menu("Tools") as SaToolsMenu
    menu.machine = machine

    _reload()
    menu.populate()

    var labels := {}
    for row: Dictionary in menu.popup.row_report():
        labels[String(row["label"])] = true
    assert_true(labels.has("Reload Probe"), "The reloaded tool has a row: %s" % str(labels.keys()))
    menu = null
    bar.free()
    machine.registered_tools.clear()
    machine.active_tool = null
    machine.surface = null
    machine.registry = null
    surface.tool_machine = null
    machine.free()
