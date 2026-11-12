## SaModule: what a third party gets by overriding nothing.
##
## The guiding rule is that a built-in registers through the same API a third
## party would use, so the base class defaults are a shipped contract rather
## than placeholders. The loader consumes every one of them directly, which is
## why a default returning null instead of an empty value is a crash in the
## loader rather than a quiet nothing.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## Registering against a real context builds registries.
const REQUIRES_GPU := true


func after_each() -> void:
    ModuleLoader.unload_all()
    ModuleLoader.failed_modules.clear()


# --- The defaults the loader reads ----------------------------------------------------


## The loader iterates this without checking it. A null default would fail
## inside the dependency walk, naming the loader rather than the module.
func test_a_module_declares_no_dependencies_by_default() -> void:
    var deps := SaModule.new().get_dependencies()

    assert_not_null(deps, "An empty list, never null")
    assert_true(deps.is_empty(), "and nothing is required")


## The loader falls back to the folder name when the id is empty, which is what
## lets a module ship without writing get_id() at all.
func test_the_default_id_is_empty_so_the_folder_name_wins() -> void:
    assert_true(String(SaModule.new().get_id()).is_empty(), "Empty is the signal to use the directory name")


## The gate is `module.get_api_version() > SaContext.API_VERSION`. A module that
## does not declare a version must pass it, or overriding nothing would be
## refused for needing a newer API than the build it is running in.
func test_a_module_that_declares_no_api_version_is_not_refused() -> void:
    var module := SaModule.new()

    assert_eq(module.get_api_version(), SaContext.API_VERSION, "It claims exactly this build")
    assert_false(module.get_api_version() > SaContext.API_VERSION, "so the loader's gate lets it through")


func test_the_defaults_are_describable_rather_than_blank() -> void:
    var module := SaModule.new()

    assert_false(module.get_name().is_empty(), "The Modules menu shows a name, so there has to be one")
    assert_false(module.get_version().is_empty(), "and a version rather than an empty cell")


# --- Lifecycle ------------------------------------------------------------------------


## A module overriding neither register nor unregister has to survive both,
## because the loader calls them unconditionally.
func test_a_module_overriding_nothing_registers_and_unregisters() -> void:
    var registries := SaRegistries.new()
    registries.build_context(func() -> Variant: return null, func() -> Array: return [])
    var module := SaModule.new()
    var scoped := registries.context.for_module(&"does-nothing")

    module.context = scoped
    module.register(scoped)
    module.unregister(scoped)

    assert_true(module.context == scoped, "The loader sets the context, and nothing here clears it")


## The loader assigns `context` before register() so unregister() can find its
## own registrations without the module storing one. A module that never touches
## it must still start from null, or an unloaded module keeps a live context
## alive after it is gone.
func test_the_context_starts_empty_and_is_cleared_on_unload() -> void:
    var module := Fixtures.FakeModule.new()
    module.module_id = &"lifecycle-probe"
    assert_null(module.context, "Nothing before the loader gets to it")

    var registries := SaRegistries.new()
    registries.build_context(func() -> Variant: return null, func() -> Array: return [])
    var scoped := registries.context.for_module(module.module_id)
    module.context = scoped
    ModuleLoader.loaded_modules[module.module_id] = module

    ModuleLoader.unload_module(module.module_id)

    assert_null(module.context, "and nothing afterwards, so the context is not kept alive by a dead module")
    assert_eq(module.unregister_count, 1, "Unloading calls unregister exactly once")


## Unloading something that was never loaded is what a failed load leads to, so
## it has to be a no-op rather than a null dereference.
func test_unloading_a_module_that_never_loaded_is_harmless() -> void:
    ModuleLoader.unload_module(&"was-never-here")

    assert_false(ModuleLoader.is_loaded(&"was-never-here"), "Still not loaded, and no error raised")
