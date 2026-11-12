## What a reload does to the running app around a module it puts down, and to
## the module's kernels.
##
## `ModuleLoader.unload_module` had only ever run at shutdown, where nothing it
## leaves behind matters. A reload runs it with the app up, and two things were
## left: the Window of a module's docker, which the UI registry forgets without
## freeing, so the second registration would adopt the stale one by name, and
## the tool machine's active tool, whose descriptor is the one that just went.
## This class owns both, and the painter's tool choice between the put down and
## the pick up is its state. The loader orchestrates, this reaches the app only
## through the door, `SaContext`, so `core` names nothing under `ui`.
##
## The kernels are here as well, because a module under `user://` had none
## compiled at all: the shader index is walked once from `res://` and skips the
## app's own `user://` on purpose, so a module there could ship a `.gmacs` and
## never have it built.
class_name SaModuleReload
extends RefCounted

var _context: SaContext = null

## `[tool machine, tool id]` for every surface whose active tool belonged to a
## module being put down, so the pick up can hand the painter's choice back.
var _held_tools: Array = []


func _init(context: SaContext) -> void:
    _context = context


## Moves every surface off a tool *module_id* owns and frees its docker
## windows. Called before `ModuleLoader.unload_module`, while the descriptors
## still say whose each tool is.
func put_down(module_id: StringName) -> void:
    _move_tools_off(module_id)
    _free_dockers(module_id)


## Puts each surface back on the tool it was moved off, when the reload
## registered that id again. A tool the edit renamed away is not guessed at,
## and the surface stays where the put down left it. Then gives every open
## layer its type's hook back, see [method _rebind_layers].
func pick_up() -> void:
    _rebind_layers()
    for held: Array in _held_tools:
        var machine: Object = held[0]
        if not is_instance_valid(machine):
            continue
        var registered := _tools_of(machine)
        if registered.has(held[1]):
            machine.call(&"set_active_tool", held[1])
    _held_tools.clear()


## The load's own path for a layer of a module that was missing:
## `SaLayerTypeRegistry.rebind` over every open document's layers, the call a
## document load makes, from a second caller so the two cannot drift. The
## unload left each layer of the module's types with its fields and no hook,
## and a type registered again takes it back. A type the reload no longer
## registers stays inert, which is the missing module's state and not a loss.
## Every open document composites again, because a layer that stores nothing
## draws from the generator this just gave back or took away.
func _rebind_layers() -> void:
    var types: SaLayerTypeRegistry = _context.layer_types if _context != null else null
    if types == null:
        return
    var layers := _context.open_layers()
    types.rebind(layers)
    for line in types.schema_drift(layers):
        print("[Modules] %s" % line)
    for document in _context.open_documents():
        document.request_cache_update()
        document.document_changed.emit()


## The tool machine is reached through the surface's back-reference, typed as a
## Variant there so `core` does not name it, and asked by name for the same
## reason.
func _move_tools_off(module_id: StringName) -> void:
    if _context == null or _context.tools == null:
        return
    for surface: Variant in _context.list_surfaces():
        if not (surface is SaSurface):
            continue
        var held: SaSurface = surface
        var machine: Object = held.tool_machine
        if machine == null or not is_instance_valid(machine):
            continue
        var active: StringName = machine.get(&"active_tool_name")
        var descriptor := _context.tools.get_descriptor(active)
        if descriptor == null or descriptor.owner_module != module_id:
            continue
        var fallback := _fallback_tool(machine, module_id)
        if String(fallback).is_empty():
            continue
        _held_tools.append([machine, active])
        machine.call(&"set_active_tool", fallback)


## The tools *machine* holds, by id. The machine's own table is untyped and
## lives in `tools`, which core does not name, so it is copied into a typed
## one here rather than failing where it is first assigned. Empty for a
## machine with no table.
static func _tools_of(machine: Object) -> Dictionary[StringName, Variant]:
    var tools: Dictionary[StringName, Variant] = {}
    var table: Variant = machine.get(&"registered_tools")
    if table is Dictionary:
        var found: Dictionary = table
        tools.assign(found)
    return tools


## The first tool the machine offers that *module_id* does not own, which is
## the stamp brush on an ordinary build, since the registry lists it first.
func _fallback_tool(machine: Object, module_id: StringName) -> StringName:
    var registered := _tools_of(machine)
    for descriptor: SaToolDescriptor in _context.tools.list_descriptors():
        if descriptor.owner_module != module_id and registered.has(descriptor.id):
            return descriptor.id
    return &""


## Takes each of the module's docker nodes out of the tree now and frees it
## after the frame. Out of the tree first, because the host looks a docker up by
## name when it builds the registration's Window, and a `queue_free()`d node is
## still its parent's child until the frame ends. Freed by a deferred call
## rather than `queue_free()`, which needs a tree to defer to.
func _free_dockers(module_id: StringName) -> void:
    if _context == null or _context.ui == null:
        return
    for entry: Dictionary[String, Variant] in _context.ui.list_dockers():
        if entry["module"] != module_id:
            continue
        var node: Node = entry["node"]
        if node == null or not is_instance_valid(node):
            continue
        if node is Window:
            (node as Window).hide()
        var parent := node.get_parent()
        if parent != null:
            parent.remove_child(node)
        node.call_deferred(&"free")


## Compiles every kernel under *dir_path*, answering the way
## `GlobalShaderCompiler.reload_changed` does, `{"rebuilt", "failed",
## "unchanged"}`. A file the compiler has never built is compiled outright, and
## one it has is handed to `reload_changed`, which rebuilds it only when its text
## moved. Nothing happens without a device, which is a headless run.
##
## The owner a kernel is filed under is the folder after the nearest `modules`
## in its path, the rule the shader index's `owner_of` keeps for every shader, so a
## module under `user://modules` owns its kernels by its folder's name.
static func compile_kernels(dir_path: String) -> Dictionary[String, Variant]:
    var result: Dictionary[String, Variant] = {"rebuilt": [], "failed": {}, "unchanged": 0}
    if dir_path.is_empty() or GlobalShaderCompiler.rd == null:
        return result
    # Inferred rather than named, because the index is a file inside the
    # compiler's package and only the compiler's facade may be named from here.
    var index := GlobalShaderCompiler.index
    var rebuilt: Array = result["rebuilt"]
    var failed: Dictionary = result["failed"]
    var known: Array = []
    for file_path: String in index.index_directory(dir_path):
        var key: String = index.shader_key(file_path)
        if GlobalShaderCompiler.compute_shader_kernel_names.has(key):
            known.append(file_path)
            continue
        GlobalShaderCompiler.compile_compute_shader(file_path)
        # A file with no kernels is an include, and is neither.
        if not GlobalShaderCompiler.compute_shader_kernel_names.has(key):
            continue
        if GlobalShaderCompiler.compile_errors.has(key):
            failed[key] = GlobalShaderCompiler.compile_errors[key]
        else:
            rebuilt.append(key)
    # Never an empty list, which `reload_changed` reads as every kernel Sara has.
    if not known.is_empty():
        var reloaded: Dictionary[String, Variant] = GlobalShaderCompiler.reload_changed(known)
        var rebuilt_again: Array = reloaded["rebuilt"]
        var failed_again: Dictionary = reloaded["failed"]
        rebuilt.append_array(rebuilt_again)
        failed.merge(failed_again)
        result["unchanged"] = reloaded["unchanged"]
    return result
