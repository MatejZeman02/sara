## A layout preset saved under a name the file system cannot carry is current
## under the name its row is listed by.
##
## `save_as` writes the file under the validated name and `current` must answer
## that name, not the typed one, so "Studio: night" listed as "Studio_ night"
## has its tick in the Window menu, and forgetting the listed name does not
## leave `current` naming a preset that no longer exists.
extends "res://tests/test_framework.gd"

static var scratch_root: String = SaDataRoot.path("test_b4_layout_presets")


func after_each() -> void:
    for folder: String in [scratch_root.path_join("layouts"), scratch_root]:
        for file_name: String in DirAccess.get_files_at(folder):
            DirAccess.remove_absolute(folder.path_join(file_name))
        DirAccess.remove_absolute(folder)


func test_the_current_name_is_the_listed_one_and_forgetting_it_clears_it() -> void:
    DirAccess.make_dir_recursive_absolute(scratch_root)
    var presets := SaDockerLayoutPresets.new(scratch_root.path_join("docker_layout.cfg"))
    assert_true(presets.save_as("Studio: night"), "The preset is written")
    var listed := "Studio: night".validate_filename()
    assert_true(presets.list().has(listed), "and listed under the name its file has")
    assert_eq(presets.current(), listed, "which is the name it is current under")
    assert_true(presets.forget(listed), "Forgetting the listed name removes it")
    assert_eq(presets.current(), SaDockerLayoutPresets.DEFAULT_PRESET, "and current no longer names it")
