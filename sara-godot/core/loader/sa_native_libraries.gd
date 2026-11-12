## The `.gdextension` lists under a modules root and the library each names
## for the platform this Sara runs on, read as Godot reads them.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The loader's own question about a native module, which library Godot did not
## load, answered apart from the loader that reads the GDScript half.
class_name SaNativeLibraries
extends RefCounted


## Every `.gdextension` in a module folder of *root*, in both layouts the
## loader reads modules in.
static func lists(root: String) -> PackedStringArray:
    var found := PackedStringArray()
    for entry in DirAccess.get_directories_at(root):
        if entry.begins_with("."):
            continue
        var entry_path := root.path_join(entry)
        found.append_array(_in(entry_path))
        for sub in DirAccess.get_directories_at(entry_path):
            if not sub.begins_with("."):
                found.append_array(_in(entry_path.path_join(sub)))
    return found


static func _in(dir_path: String) -> PackedStringArray:
    var found := PackedStringArray()
    for file_name in DirAccess.get_files_at(dir_path):
        if file_name.get_extension() == "gdextension":
            found.append(dir_path.path_join(file_name))
    return found


## The library file *list_path* names for this platform, as a path the
## painter can look for, when Godot did not load it. Empty when it loaded or
## when the list has no line for this platform.
static func unloaded(list_path: String) -> String:
    if GDExtensionManager.is_extension_loaded(list_path):
        return ""
    var library := for_this_platform(list_path)
    if library.is_empty():
        return ""
    var beside := list_path.get_base_dir().path_join(library)
    # An export puts the library beside the binary, and Godot looks there
    # when the module's folder holds no copy.
    if OS.has_feature("template") and not FileAccess.file_exists(beside):
        return OS.get_executable_path().get_base_dir().path_join(library.get_file())
    return ProjectSettings.globalize_path(beside)


## The `[libraries]` value whose key's every tag is a feature of this run,
## `linux.x86_64` on a Linux PC, the first that matches as Godot takes it,
## or empty.
static func for_this_platform(list_path: String) -> String:
    var list := ConfigFile.new()
    if list.load(list_path) != OK or not list.has_section("libraries"):
        return ""
    for key in list.get_section_keys("libraries"):
        var matches := true
        for tag in key.split("."):
            matches = matches and OS.has_feature(tag)
        if matches:
            return str(list.get_value("libraries", key))
    return ""
