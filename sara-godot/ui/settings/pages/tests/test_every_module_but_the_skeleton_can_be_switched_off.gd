## A module the painter switches off on Preferences > Modules is left out of the
## next start, a module that needs it is listed as off with the reason, the
## skeleton cannot be switched off, and a document naming a module that is off
## opens and says so in its problems.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The pair is staged in a scratch user folder with the packaged root pointed at
## an empty one, so only the two fixture modules and the skeleton are in play.
## The switched-off list is handed to the loader rather than written to the
## setting, so the painter's profile is never touched.
extends "res://tests/test_framework.gd"

## Builds a document, which allocates on the device.
const REQUIRES_GPU := true

static var scratch_root: String = SaDataRoot.path("test_probe_switch")

const BASE_ID := &"probe_base"
const DEPENDENT_ID := &"probe_dependent"

const BASE := """extends SaModule


func get_id() -> StringName:
    return &"probe_base"


func get_name() -> String:
    return "Probe Base"


func register(_ctx: SaContext) -> void:
    pass
"""

const DEPENDENT := """extends SaModule


func get_id() -> StringName:
    return &"probe_dependent"


func get_name() -> String:
    return "Probe Dependent"


func get_dependencies() -> PackedStringArray:
    return PackedStringArray(["probe_base"])


func register(_ctx: SaContext) -> void:
    pass
"""

var _packaged_before := ""


func before_each() -> void:
    _write(_user_root().path_join("probe_base/module.gd"), BASE)
    _write(_user_root().path_join("probe_dependent/module.gd"), DEPENDENT)
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_empty_root()))
    _packaged_before = OS.get_environment(ModuleLoader.PACKAGED_ROOT_VARIABLE)
    OS.set_environment(ModuleLoader.PACKAGED_ROOT_VARIABLE, _empty_root())
    ModuleLoader.user_modules_root = _user_root()


func after_each() -> void:
    ModuleLoader.unload_all()
    for module_id: StringName in [BASE_ID, DEPENDENT_ID]:
        ModuleLoader.origins.erase(module_id)
        ModuleLoader.module_dirs.erase(module_id)
        ModuleLoader.module_names.erase(module_id)
        ModuleLoader.failed_modules.erase(module_id)
        ModuleLoader.off_modules.erase(module_id)
    ModuleLoader.user_modules_root = SaDataRoot.path(ModuleLoader.USER_MODULES_FOLDER)
    if _packaged_before.is_empty():
        OS.unset_environment(ModuleLoader.PACKAGED_ROOT_VARIABLE)
    else:
        OS.set_environment(ModuleLoader.PACKAGED_ROOT_VARIABLE, _packaged_before)
    _remove(ProjectSettings.globalize_path(scratch_root))


func _user_root() -> String:
    return scratch_root.path_join("user")


func _empty_root() -> String:
    return scratch_root.path_join("packaged")


## A start with *off* switched off, against a fresh set of registries.
func _start(off: Array) -> void:
    var registries := SaRegistries.new()
    registries.build_context(func() -> Variant: return null, func() -> Array: return [])
    registries.register_builtins()
    ModuleLoader.verbose = false
    ModuleLoader.load_and_register_modules(registries.context, off)
    ModuleLoader.verbose = true


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


func test_with_nothing_switched_off_both_load() -> void:
    _start([])
    assert_true(ModuleLoader.is_loaded(BASE_ID), "The base loads")
    assert_true(ModuleLoader.is_loaded(DEPENDENT_ID), "and so does the module that needs it")
    assert_true(ModuleLoader.off_modules.is_empty(), "and nothing is off")


func test_switching_off_the_base_lists_the_dependent_as_off_with_the_reason() -> void:
    _start([String(BASE_ID)])
    assert_false(ModuleLoader.is_loaded(BASE_ID), "The switched-off base is not registered")
    assert_false(ModuleLoader.is_loaded(DEPENDENT_ID), "nor the module that needs it")
    assert_eq(ModuleLoader.off_modules.get(BASE_ID), SaSwitchedOff.SWITCHED_OFF, "The base is off, switched off")
    assert_eq(
        ModuleLoader.off_modules.get(DEPENDENT_ID), "needs probe_base, which is off", "the dependent is off with the reason"
    )
    assert_false(ModuleLoader.failed_modules.has(BASE_ID), "and neither is filed as a refusal")
    assert_false(ModuleLoader.failed_modules.has(DEPENDENT_ID), "the dependent least of all")
    assert_true(ModuleLoader.asked_off(BASE_ID), "The painter asked the base off")
    assert_false(ModuleLoader.asked_off(DEPENDENT_ID), "and not the dependent, whose switch stays on")
    assert_eq(ModuleLoader.module_names.get(DEPENDENT_ID), "Probe Dependent", "An off module is still named")


func test_the_page_lists_the_dependent_as_off_with_the_reason() -> void:
    _start([String(BASE_ID)])
    var states := {}
    var lines := {}
    for entry: Dictionary in SaModulesPage.entries():
        states[entry["id"]] = entry["state"]
        lines[entry["id"]] = SaModulesPage.line_of(entry)
    assert_eq(states.get("sara-skeleton"), "on", "The skeleton is listed, on")
    assert_eq(states.get(String(BASE_ID)), "off", "the base off")
    assert_eq(states.get(String(DEPENDENT_ID)), "off", "and the dependent off")
    assert_true(String(lines.get(String(DEPENDENT_ID))).contains("needs probe_base, which is off"), "with the reason")
    var page := SaModulesPage.new()
    assert_not_null(page.page.row(&"module_probe_base"), "The base has a switch")
    assert_not_null(page.page.row(&"module_probe_dependent"), "so does the dependent")
    assert_eq(page.page.row(&"module_sara_skeleton").kind, SaPageRow.Kind.CUSTOM, "and the skeleton has a line, never a switch")
    page.free()


func test_the_skeleton_cannot_be_switched_off() -> void:
    _start(["sara-skeleton"])
    assert_true(ModuleLoader.is_loaded(SaSwitchedOff.SKELETON), "The skeleton stays loaded")
    assert_false(ModuleLoader.off_modules.has(SaSwitchedOff.SKELETON), "and is never listed as off")
    assert_true(ModuleLoader.is_loaded(BASE_ID), "and the rest load as before")


func test_switching_the_base_on_again_brings_both_back() -> void:
    _start([String(BASE_ID)])
    ModuleLoader.unload_all()
    _start([])
    assert_true(ModuleLoader.is_loaded(BASE_ID), "The base is back")
    assert_true(ModuleLoader.is_loaded(DEPENDENT_ID), "and so is the dependent")
    assert_false(ModuleLoader.off_modules.has(DEPENDENT_ID), "with nothing left off")


func test_a_document_naming_an_off_module_opens_and_says_so() -> void:
    _start([String(BASE_ID)])
    var document := SaDocument.new()
    document.module_data = {String(DEPENDENT_ID): {"kept": true}}
    document.root_filters.append(SaAttachedFilter.new(&"probe_base.wash"))
    assert_eq(SaSwitchedOff.named_by(document), [DEPENDENT_ID, BASE_ID], "The document names both, by its data and its filter")
    var before := SaProblems.pending_refusals.size()
    SaProblems.announce = false
    EventBus.document_loaded.emit(document)
    SaProblems.announce = true
    var said := SaProblems.pending_refusals.slice(before)
    assert_eq(said.size(), 2, "Opening it says so, once for each module")
    assert_true(said[0].contains("probe_dependent") and said[0].contains("which is off"), "naming the dependent")
    assert_true(said[1].contains("probe_base") and said[1].contains(SaSwitchedOff.SWITCHED_OFF), "and the base")
    assert_eq(document.module_data.keys(), [String(DEPENDENT_ID)], "and the data is kept as it was")
    SaProblems.pending_refusals.resize(before)
    document.free()
