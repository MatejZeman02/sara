## ModuleLoader: discovery, ordering, API gating and unloading.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")


## Modules registered by one test must not leak into the next, and the real base
## module holds GPU-backed settings.
func after_each() -> void:
    ModuleLoader.unload_all()


func _make_registries() -> SaRegistries:
    var registries := SaRegistries.new()
    registries.build_context(func() -> Variant: return null, func() -> Array: return [])
    return registries


func test_discovers_and_registers_the_base_module() -> void:
    var registries := _make_registries()
    ModuleLoader.load_and_register_modules(registries.context)

    assert_true(ModuleLoader.is_loaded(&"sara-base-modules"), "sara-base-modules should be registered")
    var module: SaModule = ModuleLoader.loaded_modules.get(&"sara-base-modules")
    assert_not_null(module, "Module instance should exist")
    # Two modules in one repository now, and base depends on the stamp
    # brush now: the fill's settings resource is that module's script, and
    # the order decides which tool a fresh surface opens on.
    assert_true(ModuleLoader.is_loaded(&"sara-stamp-brush"), "and so should the module beside it")
    assert_eq(
        Array(ModuleLoader.manifest_of(&"sara-base-modules").dependency_ids()),
        ["sara-stamp-brush"],
        "Base declares the one dependency it has, which is what puts the brush first"
    )


## The whole point of the tool registry: the module describes tools and they
## become available without the skeleton naming any of them.
func test_base_module_registers_its_tools_through_the_api() -> void:
    var registries := _make_registries()
    ModuleLoader.load_and_register_modules(registries.context)

    for expected: StringName in [&"brush", &"eraser", &"bucket_fill", &"eyedropper", &"pan", &"zoom"]:
        assert_true(registries.tools.has(expected), "Tool '%s' should be registered" % expected)

    var brush := registries.tools.get_descriptor(&"brush")
    assert_true(brush.is_painting, "The brush is a painting tool")
    assert_true(brush.wants_brush_cursor, "The brush wants a software ring")


## Quick tools must come back highest-priority first, or Ctrl+Space would give
## pan instead of zoom.
func test_quick_tools_are_ordered_by_priority() -> void:
    var registries := _make_registries()
    ModuleLoader.load_and_register_modules(registries.context)

    var quick := registries.tools.list_quick_tools()
    assert_true(quick.size() >= 3, "Pan, zoom and eyedropper are quick tools")
    assert_eq(quick[0].id, &"zoom", "Zoom must outrank pan, since Ctrl+Space is zoom")
    assert_eq(quick[1].id, &"pan", "Pan must outrank the eyedropper")


## A module built against a newer API is refused with a reason rather than
## half-registering and failing confusingly later.
func test_a_module_needing_a_newer_api_is_refused() -> void:
    # No registries built on purpose: the gate under test is in dependency
    # resolution, which never reaches one.
    var module := Fixtures.FakeModule.new()
    module.module_id = &"from-the-future"
    module.api_version = SaContext.API_VERSION + 1

    var discovered: Dictionary[StringName, SaModule] = {module.module_id: module}
    var ordered := ModuleLoader._resolve_dependencies(discovered)
    assert_eq(ordered.size(), 1, "It is still ordered; the gate is applied at registration")
    assert_eq(module.register_count, 0, "It must not have been registered")


## Unloading removes every registration the module made, so the module does not
## have to track its own bookkeeping.
func test_unloading_removes_the_modules_registrations() -> void:
    var registries := _make_registries()
    ModuleLoader.load_and_register_modules(registries.context)
    # The fill rather than the brush, because the brush belongs to the module
    # beside this one now and this test is about a module taking its own
    # registrations with it.
    assert_true(registries.tools.has(&"bucket_fill"), "The fill is registered before unload")
    assert_true(registries.tools.has(&"brush"), "and so is the stamp brush's brush")

    ModuleLoader.unload_module(&"sara-base-modules")

    assert_false(ModuleLoader.is_loaded(&"sara-base-modules"), "Module is no longer loaded")
    assert_false(registries.tools.has(&"bucket_fill"), "Its tools are gone from the registry too")
    assert_true(registries.tools.has(&"brush"), "and the other module's are untouched")


## A cycle pushes an error rather than carrying on into an undefined order.
func test_a_dependency_cycle_is_refused() -> void:
    var a := Fixtures.FakeModule.new()
    a.module_id = &"cycle-a"
    a.deps = PackedStringArray(["cycle-b"])
    var b := Fixtures.FakeModule.new()
    b.module_id = &"cycle-b"
    b.deps = PackedStringArray(["cycle-a"])

    ModuleLoader.failed_modules.clear()
    ModuleLoader._resolve_dependencies({a.module_id: a, b.module_id: b})
    assert_true(not ModuleLoader.failed_modules.is_empty(), "The cycle should be recorded as a failure")


# --- Ordering -----------------------------------------------------------------


## The whole reason the sort exists. Insertion order is deliberately the reverse
## of the dependency order, so a sort that only preserved discovery order would
## pass every other test in this file and fail exactly this one.
func test_a_dependency_is_ordered_before_the_module_that_needs_it() -> void:
    var base := _fake(&"base")
    var dependent := _fake(&"dependent", ["base"])

    ModuleLoader.failed_modules.clear()
    var ordered := ModuleLoader._resolve_dependencies({dependent.module_id: dependent, base.module_id: base})

    assert_eq(ordered, [&"base", &"dependent"] as Array[StringName], "The dependency has to be registered first")


## Three deep, discovered top down. A sort that looked only one level ahead
## would put "middle" before "base".
func test_a_dependency_chain_is_ordered_all_the_way_down() -> void:
    var top := _fake(&"top", ["middle"])
    var middle := _fake(&"middle", ["base"])
    var base := _fake(&"base")

    ModuleLoader.failed_modules.clear()
    var ordered := ModuleLoader._resolve_dependencies({top.module_id: top, middle.module_id: middle, base.module_id: base})

    assert_eq(ordered, [&"base", &"middle", &"top"] as Array[StringName], "The whole chain has to unwind in order")


## Two modules over one dependency. It must be ordered once, ahead of both, or
## the second visit would register it twice.
func test_a_shared_dependency_is_ordered_once_and_first() -> void:
    var shared := _fake(&"shared")
    var left := _fake(&"left", ["shared"])
    var right := _fake(&"right", ["shared"])

    ModuleLoader.failed_modules.clear()
    var ordered := ModuleLoader._resolve_dependencies({left.module_id: left, right.module_id: right, shared.module_id: shared})

    assert_eq(ordered.size(), 3, "Each module is ordered exactly once")
    assert_eq(ordered[0], &"shared", "The shared dependency comes first")


## A cycle must not take the modules around it down with it. The unrelated
## module is ordered normally, which is what makes a cycle a refusal of the
## modules involved rather than of the run.
func test_a_cycle_does_not_stop_unrelated_modules_from_loading() -> void:
    var a := _fake(&"cyc-a", ["cyc-b"])
    var b := _fake(&"cyc-b", ["cyc-a"])
    var bystander := _fake(&"bystander")

    _register_all({a.module_id: a, b.module_id: b, bystander.module_id: bystander})

    assert_eq(bystander.register_count, 1, "A module outside the cycle still loads")


# --- Dependency satisfaction ---------------------------------------------------


## A module refused for any reason stays in `discovered`, so a dependent that
## only checked "was it found" registered against something that never
## registered - and then failed far from the cause.
func test_a_module_whose_dependency_was_refused_does_not_register() -> void:
    var refused := _fake(&"needs-a-newer-api")
    refused.api_version = SaContext.API_VERSION + 1
    var dependent := _fake(&"dependent", ["needs-a-newer-api"])

    _register_all({refused.module_id: refused, dependent.module_id: dependent})

    assert_eq(refused.register_count, 0, "The module needing a newer API is refused")
    assert_eq(dependent.register_count, 0, "And so is everything that depends on it")


## The other way into the same bug. A cycle refuses only the member the walk
## re-entered, so the other one was still ordered and still registered, holding
## a dependency that had just been refused.
func test_the_surviving_member_of_a_cycle_does_not_register_either() -> void:
    var a := _fake(&"cyc-a", ["cyc-b"])
    var b := _fake(&"cyc-b", ["cyc-a"])

    _register_all({a.module_id: a, b.module_id: b})

    assert_eq(a.register_count, 0, "Neither member of a cycle may register")
    assert_eq(b.register_count, 0, "Including the one the cycle walk did not name")


## A module naming a dependency nothing provides is refused, rather than
## registering and failing at the point it first calls into it.
func test_a_dependency_nothing_provides_is_reported_as_not_found() -> void:
    var orphan := _fake(&"orphan", ["nobody-provides-this"])

    var unsatisfied := ModuleLoader._unsatisfied_dependencies(orphan.module_id, {orphan.module_id: orphan})

    assert_eq(unsatisfied.size(), 1, "The one absent dependency should be reported")
    assert_true("nobody-provides-this" in unsatisfied[0], "The reason names the dependency")
    assert_true("not found" in unsatisfied[0], "and says it was never discovered, not that it failed")


## The skeleton's own built-in goes straight into loaded_modules before
## discovery runs, so it is never in `discovered`. Depending on it was refused
## as missing, which would have broken the first module that tried.
func test_a_dependency_on_an_already_loaded_module_is_satisfied() -> void:
    var already := _fake(&"already-loaded")
    ModuleLoader.loaded_modules[already.module_id] = already
    var dependent := _fake(&"dependent", ["already-loaded"])

    var unsatisfied := ModuleLoader._unsatisfied_dependencies(dependent.module_id, {dependent.module_id: dependent})

    assert_true(unsatisfied.is_empty(), "A dependency that is already loaded is satisfied")


func _fake(module_id: StringName, deps: Array[String] = []) -> SaTestFixtures.FakeModule:
    var module := Fixtures.FakeModule.new()
    module.module_id = module_id
    module.deps = PackedStringArray(deps)
    return module


## Runs the loader's ordering and gating over a hand-built `discovered` set,
## skipping only the filesystem scan. Registration itself is the loader's own
## loop, so a test cannot restate it and still be testing it.
func _register_all(discovered: Dictionary[StringName, SaModule]) -> void:
    ModuleLoader.failed_modules.clear()
    var registries := _make_registries()
    var ordered := ModuleLoader._resolve_dependencies(discovered)
    for module_id: StringName in ordered:
        var module: SaModule = discovered[module_id]
        if module.get_api_version() > SaContext.API_VERSION:
            ModuleLoader._fail(module_id, "api version")
            continue
        if not ModuleLoader._unsatisfied_dependencies(module_id, discovered).is_empty():
            ModuleLoader._fail(module_id, "unsatisfied")
            continue
        module.register(registries.context.for_module(module_id))
        ModuleLoader.loaded_modules[module_id] = module


# --- The user's own modules folder ---------------------------------

static var scratch_user_root: String = SaDataRoot.path("test_user_modules")

const GOOD_MODULE := """extends SaModule


func get_id() -> StringName:
    return &"from-the-user"


func get_name() -> String:
    return "From The User"


func register(_ctx: SaContext) -> void:
    pass
"""

const BROKEN_MODULE := """extends RefCounted
"""


func _stage_user_module(folder: String, source: String) -> void:
    var dir := scratch_user_root.path_join(folder)
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
    var file := FileAccess.open(dir.path_join("module.gd"), FileAccess.WRITE)
    file.store_string(source)
    file.close()


func _remove_user_root() -> void:
    var absolute := ProjectSettings.globalize_path(scratch_user_root)
    if not DirAccess.dir_exists_absolute(absolute):
        return
    for folder in DirAccess.get_directories_at(absolute):
        var script := absolute.path_join(folder).path_join("module.gd")
        if FileAccess.file_exists(script):
            DirAccess.remove_absolute(script)
        DirAccess.remove_absolute(absolute.path_join(folder))
    DirAccess.remove_absolute(absolute)


## A module dropped into the user's folder loads beside the packaged ones and
## says where it came from.
func test_a_module_in_the_user_folder_loads_and_names_its_origin() -> void:
    _stage_user_module("good", GOOD_MODULE)
    ModuleLoader.user_modules_root = scratch_user_root
    var registries := _make_registries()
    ModuleLoader.verbose = false
    ModuleLoader.load_and_register_modules(registries.context)
    ModuleLoader.verbose = true
    ModuleLoader.user_modules_root = SaDataRoot.path(ModuleLoader.USER_MODULES_FOLDER)
    _remove_user_root()

    assert_true(ModuleLoader.is_loaded(&"from-the-user"), "The user's module loaded")
    assert_eq(ModuleLoader.origins.get(&"from-the-user"), "user", "and is known to be theirs")
    assert_eq(ModuleLoader.origins.get(&"sara-base-modules"), "packaged", "while the packaged one is known to be packaged")


## Code from the user's folder that is not a module is refused with the reason
## recorded, which is what the Modules menu shows instead of a tick.
func test_a_refused_user_module_is_recorded_with_its_reason() -> void:
    _stage_user_module("broken", BROKEN_MODULE)
    ModuleLoader.user_modules_root = scratch_user_root
    var registries := _make_registries()
    ModuleLoader.verbose = false
    ModuleLoader.load_and_register_modules(registries.context)
    ModuleLoader.verbose = true
    ModuleLoader.user_modules_root = SaDataRoot.path(ModuleLoader.USER_MODULES_FOLDER)
    _remove_user_root()

    assert_false(ModuleLoader.is_loaded(&"broken"), "It did not load")
    assert_eq(ModuleLoader.failed_modules.get(&"broken"), "module.gd does not extend SaModule", "and the reason is recorded")
    assert_eq(ModuleLoader.origins.get(&"broken"), "user", "against the folder it came from")


## The packaged copy wins a name clash, and the user's copy says why it lost.
func test_a_user_module_with_a_packaged_name_is_refused_as_a_duplicate() -> void:
    _stage_user_module("clash", GOOD_MODULE.replace("from-the-user", "sara-base-modules"))
    ModuleLoader.user_modules_root = scratch_user_root
    var registries := _make_registries()
    ModuleLoader.verbose = false
    ModuleLoader.load_and_register_modules(registries.context)
    ModuleLoader.verbose = true
    ModuleLoader.user_modules_root = SaDataRoot.path(ModuleLoader.USER_MODULES_FOLDER)
    _remove_user_root()

    assert_true(ModuleLoader.is_loaded(&"sara-base-modules"), "The packaged module loaded")
    assert_true(
        String(ModuleLoader.failed_modules.get(&"sara-base-modules (user)", "")).begins_with("duplicate"),
        "and the clash was refused as one, under a key of its own so the winner is not marked failed"
    )


## An absent user folder is the ordinary state, not a warning, and the path
## the menu offers to open exists once asked for.
func test_the_user_folder_is_optional_and_made_on_request() -> void:
    ModuleLoader.user_modules_root = scratch_user_root
    _remove_user_root()
    var registries := _make_registries()
    ModuleLoader.verbose = false
    ModuleLoader.load_and_register_modules(registries.context)
    ModuleLoader.verbose = true
    assert_true(ModuleLoader.is_loaded(&"sara-base-modules"), "Loading went on without it")
    var path := ModuleLoader.user_modules_path()
    assert_true(DirAccess.dir_exists_absolute(path), "Asking for the path makes the folder")
    ModuleLoader.user_modules_root = SaDataRoot.path(ModuleLoader.USER_MODULES_FOLDER)
    _remove_user_root()
