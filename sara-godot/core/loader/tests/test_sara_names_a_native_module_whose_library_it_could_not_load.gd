## A native module whose `.gdextension` names a library for this platform that
## did not load is said once, naming the module and the file, and one whose list
## has no line for this platform says nothing.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## An installed Sara ran for weeks without JPEG XL, because the install left
## the library behind and only the console said so. The stand-in here is a
## folder with a list and no library, which Godot never loaded.
extends "res://tests/test_framework.gd"

static var scratch_root: String = SaDataRoot.path("test_u337/modules")
const FOLDER := "native-probe"
const LIBRARY := "bin/libnative-probe.%s.so"

var _faults: PackedStringArray = []


func before_each() -> void:
    _faults.clear()
    SaProblems.pending = PackedStringArray()
    SaProblems.announce = false
    SaProblems.attach_sink(
        func(line: String, kind: SaProblems.Kind) -> void:
            if kind == SaProblems.Kind.FAULT:
                _faults.append(line)
    )


func after_each() -> void:
    SaProblems.detach_sink()
    SaProblems.announce = true
    ModuleLoader.missing_libraries.clear()
    _remove(ProjectSettings.globalize_path(scratch_root.get_base_dir()))


func test_a_line_for_this_platform_whose_library_is_not_there_is_one_problem() -> void:
    _write_list(["linux.x86_64", "windows.x86_64", "macos"])
    ModuleLoader.name_missing_libraries(scratch_root)
    assert_eq(_faults.size(), 1, "one problem for the one module")
    var line := _faults[0] if not _faults.is_empty() else ""
    assert_true(line.contains(FOLDER), "the problem names the module: %s" % line)
    var looked_for := str(ModuleLoader.missing_libraries.get(FOLDER, ""))
    assert_true(looked_for.contains("libnative-probe."), "the loader keeps the file it looked for: %s" % looked_for)
    assert_true(line.contains(looked_for), "the problem names the file: %s" % line)


func test_a_list_with_no_line_for_this_platform_says_nothing() -> void:
    _write_list(["android.arm64"])
    ModuleLoader.name_missing_libraries(scratch_root)
    assert_eq(_faults.size(), 0, "a platform never built for is a choice, not a fault: %s" % ", ".join(_faults))
    assert_true(ModuleLoader.missing_libraries.is_empty(), "nothing is filed")


func test_a_module_beside_its_list_is_named_by_its_own_name() -> void:
    _write_list(["linux.x86_64", "windows.x86_64", "macos"])
    var dir := scratch_root.path_join(FOLDER)
    ModuleLoader.module_dirs[&"native_probe"] = dir
    ModuleLoader.module_names[&"native_probe"] = "Native Probe"
    ModuleLoader.name_missing_libraries(scratch_root)
    ModuleLoader.module_dirs.erase(&"native_probe")
    ModuleLoader.module_names.erase(&"native_probe")
    assert_eq(_faults.size(), 1, "one problem")
    assert_true(ModuleLoader.missing_libraries.has("Native Probe"), "filed under the module's name")


## A list in the shape the build writes, one line per key in *keys*.
func _write_list(keys: Array) -> void:
    var text := '[configuration]\n\nentry_symbol = "native_probe_init"\ncompatibility_minimum = "4.7"\n\n[libraries]\n\n'
    for key: String in keys:
        text += '%s = "%s"\n' % [key, LIBRARY % key]
    var path := scratch_root.path_join(FOLDER).path_join("native_probe.gdextension")
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
