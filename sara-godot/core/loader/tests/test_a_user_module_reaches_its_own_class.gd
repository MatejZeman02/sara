## A painter's copy of the kaleidoscope under the modules folder builds its own
## filter, and an edit to it is what the reload registers.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Copying the kaleidoscope into `user://modules`, changed its id and edited
## its title. Both showcase modules named their filter by a `class_name`, which a
## script outside `res://` never enters the global cache under, so the copy's
## `module.gd` built the shipped class, the menu read "Kaleidoscope" on both
## rows, and Modules > Reload failed to parse the copy's filter because its name
## hid the shipped one. The modules now preload the file beside them, and the
## loader refuses a folder from outside the build that declares a class name.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

static var scratch_root: String = SaDataRoot.path("test_d25_copy/modules")
const COPY_ID := &"my_kaleidoscope"
const NAMED_ID := &"named_kaleidoscope"
const SHIPPED := "res://modules/sara-base-modules/kaleidoscope"

var _registries: SaRegistries


func before_each() -> void:
    _stage("my_kaleidoscope", COPY_ID, "Kaleidoscope, the painter's copy", false)
    _registries = SaRegistries.new()
    _registries.build_context(func() -> Variant: return null, func() -> Array: return [])
    ModuleLoader.user_modules_root = scratch_root
    ModuleLoader.verbose = false
    # Nothing is switched off, so the shipped kaleidoscope loads whatever the
    # profile on this machine says.
    ModuleLoader.load_and_register_modules(_registries.context, [])
    ModuleLoader.verbose = true


func after_each() -> void:
    ModuleLoader.unload_all()
    ModuleLoader.user_modules_root = SaDataRoot.path(ModuleLoader.USER_MODULES_FOLDER)
    for key: StringName in [COPY_ID, NAMED_ID]:
        ModuleLoader.origins.erase(key)
        ModuleLoader.module_dirs.erase(key)
        ModuleLoader.failed_modules.erase(key)
    _registries = null
    _remove(ProjectSettings.globalize_path(scratch_root.get_base_dir()))


## Writes a copy of the shipped module under the test root, with its id and its
## filter's title changed, and the filter's `class_name` put back on request.
func _stage(folder: String, module_id: StringName, title: String, named: bool) -> void:
    var dir := scratch_root.path_join(folder)
    var module := FileAccess.get_file_as_string(SHIPPED.path_join("module.gd"))
    _write(dir.path_join("module.gd"), module.replace('&"kaleidoscope"', '&"%s"' % module_id))
    var filter := FileAccess.get_file_as_string(SHIPPED.path_join("kaleidoscope.gd"))
    var shipped_title := 'func title() -> String:\n    return "Kaleidoscope"'
    filter = filter.replace(shipped_title, 'func title() -> String:\n    return "%s"' % title)
    if named:
        filter = filter.replace("extends SaFilter\n", "class_name Kaleidoscope\nextends SaFilter\n")
    _write(dir.path_join("kaleidoscope.gd"), filter)


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


func _title_of(module_id: StringName) -> String:
    var filter := _registries.filters.get_filter(StringName("%s.kaleidoscope" % module_id))
    return filter.title() if filter != null else ""


func test_the_shipped_modules_declare_no_class_name() -> void:
    for path: String in [SHIPPED.path_join("kaleidoscope.gd"), "res://modules/sara-base-modules/base/usual/box_blur_filter.gd"]:
        var script := load(path) as Script
        assert_eq(String(script.get_global_name()), "", "%s is reached by preload, not by a global name" % path)


func test_the_copy_builds_its_own_filter_at_the_boot() -> void:
    assert_true(ModuleLoader.is_loaded(COPY_ID), "The copy loads under its own id")
    assert_eq(_title_of(COPY_ID), "Kaleidoscope, the painter's copy", "and registers its own filter")
    assert_eq(_title_of(&"kaleidoscope"), "Kaleidoscope", "while the shipped one keeps its own")


func test_an_edit_to_the_copy_is_what_the_reload_registers() -> void:
    _stage("my_kaleidoscope", COPY_ID, "Kaleidoscope, edited", false)
    ModuleLoader.verbose = false
    var record := ModuleLoader.reload_user_modules()
    ModuleLoader.verbose = true
    assert_true(Array(record["reloaded"]).has(COPY_ID), "The reload reads the copy again")
    assert_false(Dictionary(record["failed"]).has(COPY_ID), "and nothing refuses it")
    assert_eq(_title_of(COPY_ID), "Kaleidoscope, edited", "The registry holds the edited filter")
    assert_eq(_title_of(&"kaleidoscope"), "Kaleidoscope", "and the shipped one is untouched")


func test_a_copy_that_declares_a_class_name_is_refused_with_a_sentence() -> void:
    _stage("named_kaleidoscope", NAMED_ID, "Kaleidoscope, named", true)
    ModuleLoader.verbose = false
    var record := ModuleLoader.reload_user_modules()
    ModuleLoader.verbose = true
    var reason := String(ModuleLoader.failed_modules.get(NAMED_ID, ""))
    assert_true(reason.contains("class_name Kaleidoscope"), "The refusal names the class: %s" % reason)
    assert_true(reason.contains("preload"), "and says what to write instead")
    assert_true(Dictionary(record["failed"]).has(NAMED_ID), "The reload's record carries it")
    assert_false(ModuleLoader.is_loaded(NAMED_ID), "The named copy is not loaded")
    assert_true(ModuleLoader.is_loaded(COPY_ID), "while the copy beside it still is")
    assert_eq(_title_of(&"kaleidoscope"), "Kaleidoscope", "and the shipped filter is still the shipped one")
