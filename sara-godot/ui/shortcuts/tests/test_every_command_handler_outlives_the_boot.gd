## No command's handler dies once the boot lets go of its locals.
##
## A Callable does not keep its object alive, so a handler bound to an object
## nothing else holds goes invalid the moment the registering code returns. The
## File menu's rows were once lost that way. This suite builds the
## command registry in the order `Main._bootstrap_modules` does, keeps only what
## Main keeps, which is the registries, the shortcut router and the note mode
## node, and lets the modules stay in `ModuleLoader` the way the app leaves
## them. Every command whose handler could be called when it was registered
## must still be callable then.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true


## Notes, as each command comes in, whether its handler could be called then,
## so a handler that was never valid is told apart from one that died.
class RecordingRegistry:
    extends SaCommandRegistry

    var valid_when_registered: Dictionary = {}  # StringName -> bool

    func register(descriptor: SaCommandDescriptor, module_id: StringName = &"") -> bool:
        if descriptor != null:
            valid_when_registered[descriptor.id] = descriptor.handler.is_valid()
        return super.register(descriptor, module_id)


func after_each() -> void:
    ModuleLoader.unload_all()


## What Main holds after its boot, and nothing else: every other object the
## registrations built goes when this returns, as it goes in the app.
func _boot(host: Node) -> Dictionary:
    var registries := SaRegistries.new()
    registries.commands = RecordingRegistry.new()
    registries.build_context(func() -> Variant: return null, func() -> Array: return [])
    registries.register_builtins()
    SaAppCommands.register_all(
        registries,
        func(_docker_id: StringName) -> void: pass,
        func() -> Variant: return null,
        func(_docker_id: StringName) -> void: pass
    )
    ModuleLoader.load_and_register_modules(registries.context)
    var router := ShortcutRouter.new()
    router.bind_commands(registries.commands, registries.view_transforms)
    var mode := SaNoteMode.new()
    host.add_child(mode)
    SaNoteMode.register_command(registries.commands, mode)
    return {"registries": registries, "router": router}


## The ids of every command whose handler was callable when it came in and is
## not callable now.
func _died(registry: RecordingRegistry) -> Array[StringName]:
    var dead: Array[StringName] = []
    for id: StringName in registry.list_ids():
        if registry.valid_when_registered.get(id, false) and not registry.get_descriptor(id).handler.is_valid():
            dead.append(id)
    return dead


func test_no_handler_dies_once_the_boot_lets_go_of_its_locals() -> void:
    var host := Node.new()
    var kept := _boot(host)
    var registry: RecordingRegistry = kept["registries"].commands

    assert_true(registry.list_ids().size() > 100, "the boot registered the app's commands")
    for id: StringName in [&"file_new", &"file_open", &"brush_toggle_eraser", &"layer_clip_to_below", &"edit_preferences"]:
        assert_true(registry.has(id), "%s is among them" % id)
    var never: Array[StringName] = []
    for id: StringName in registry.list_ids():
        if not registry.valid_when_registered.get(id, false):
            never.append(id)
    assert_eq(never, [] as Array[StringName], "every one came in with a handler it could call")
    assert_eq(_died(registry), [] as Array[StringName], "and not one handler died with an object nobody kept")

    kept["router"].free()
    host.free()


## The filters' commands are lambdas made inside a context scoped to their
## module, and the brush's eraser toggle is bound to a context of its own that
## only the handler holds. Both are read here by name, so a change to either
## that lets its object go is caught by the command it broke.
func test_a_filter_command_and_the_eraser_toggle_survive_their_scoped_contexts() -> void:
    var host := Node.new()
    var kept := _boot(host)
    var registry: RecordingRegistry = kept["registries"].commands

    var filter_ids: Array[StringName] = []
    for id: StringName in registry.list_ids():
        if registry.get_descriptor(id).category == &"filter":
            filter_ids.append(id)
    assert_true(filter_ids.size() > 5, "the base module registered its filters")
    for id in filter_ids:
        assert_true(registry.get_descriptor(id).handler.is_valid(), "filter command %s can still be called" % id)
    assert_true(
        registry.get_descriptor(&"brush_toggle_eraser").handler.is_valid(),
        "and so can the eraser toggle, bound to a context only it holds"
    )

    kept["router"].free()
    host.free()
