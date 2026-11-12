## The copies and caches Sara makes without being asked do not grow for as long
## as it is used, and what a painter made is never touched.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A painter who installs Sara must not find its data folder growing run after
## run and version after version. A file cannot be given an old time from
## script, so each case hands the rule a clock a year on instead of an old file.
extends "res://tests/test_framework.gd"

const YEAR: int = 365 * 86400

var _root: String = ""


func before_each() -> void:
    _root = SaDataRoot.path("test_data_tidy_%d" % OS.get_process_id())
    DirAccess.make_dir_recursive_absolute(_root)


func after_each() -> void:
    SaDataTidy._remove_tree(_root)


func _write(relative: String) -> void:
    var path := _root.path_join(relative)
    DirAccess.make_dir_recursive_absolute(path.get_base_dir())
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_string("x")
    file.close()


func _now() -> int:
    return int(Time.get_unix_time_from_system())


func test_a_kernel_no_build_writes_any_more_goes_with_its_empty_folder() -> void:
    _write("kernels/old_wrapped.gmacs")
    _write("kernels/modules/gone/old_wrapped.gmacs")
    var dropped := SaDataTidy.files_older_than(_root.path_join("kernels"), SaDataTidy.KERNEL_DAYS, _now() + YEAR, true)
    assert_eq(dropped, 2, "Both files are older than the days a kernel may wait")
    assert_false(FileAccess.file_exists(_root.path_join("kernels/old_wrapped.gmacs")), "the one at the top is gone")
    assert_false(DirAccess.dir_exists_absolute(_root.path_join("kernels/modules")), "and the folder it left empty")
    assert_true(DirAccess.dir_exists_absolute(_root.path_join("kernels")), "the folder itself stays")


func test_a_file_a_run_wrote_lately_stays() -> void:
    _write("kernels/new_wrapped.gmacs")
    _write("kernels/modules/live/new_wrapped.gmacs")
    var soon := _now() + 86400
    var dropped := SaDataTidy.files_older_than(_root.path_join("kernels"), SaDataTidy.KERNEL_DAYS, soon, true)
    assert_eq(dropped, 0, "Nothing ages out in a day")
    assert_true(FileAccess.file_exists(_root.path_join("kernels/modules/live/new_wrapped.gmacs")), "so the module's kernel stays")


func test_a_folder_that_does_not_exist_has_nothing_to_drop() -> void:
    assert_eq(SaDataTidy.files_older_than(_root.path_join("none"), 1, _now() + YEAR, true), 0, "No file, no error")
    assert_eq(SaDataTidy.newest_folders(_root.path_join("none"), 2), 0, "and no folder either")


func test_the_shader_cache_keeps_the_newest_versions_of_each_shader() -> void:
    for shader: String in ["CopyShaderRD", "BlitShaderRD"]:
        for version: String in ["a", "b", "c", "d"]:
            _write("shader_cache/%s/%s/%s.vulkan.cache" % [shader, version, version])
    _write("shader_cache/LoneShaderRD/only/only.vulkan.cache")
    var dropped := SaDataTidy.newest_folders(_root.path_join("shader_cache"), 2)
    assert_eq(dropped, 4, "Two of four versions go for each of two shaders")
    for shader: String in ["CopyShaderRD", "BlitShaderRD"]:
        var left := Array(DirAccess.get_directories_at(_root.path_join("shader_cache").path_join(shader)))
        assert_eq(left.size(), 2, "%s keeps two versions" % shader)
    var lone := _root.path_join("shader_cache/LoneShaderRD/only/only.vulkan.cache")
    assert_true(FileAccess.file_exists(lone), "A shader with one is left whole")


func test_the_tidy_names_no_folder_a_painter_fills_with_their_own_work() -> void:
    var source := FileAccess.get_file_as_string("res://core/app/sa_data_tidy.gd")
    for owned: String in ["brush_presets", "patterns", "brush_tips", "filter", "templates", "notes", "timelapse", "modules"]:
        assert_false(source.contains('path("%s")' % owned), "%s is the painter's, and is not tidied" % owned)
    assert_true(source.contains("path(RECOVERY_FOLDER)"), "while the crash copies are")


func test_each_folder_is_the_one_its_writer_uses() -> void:
    assert_eq(SaDataTidy.RECOVERY_FOLDER, SaAutosave.RECOVERY_FOLDER, "The crash copies")
    assert_eq(SaDataTidy.PASTE_FOLDER, ReferencePaste.FOLDER, "The pasted references")
    assert_eq(SaDataTidy.KERNEL_FOLDER, SaBrushFieldRegistry.GENERATED_FOLDER, "The generated kernels")
    assert_true(
        FileAccess.get_file_as_string("res://core/custom-shader/compiler/sa_pixel_function.gd").contains(
            'const GENERATED_FOLDER: String = "%s"' % SaDataTidy.KERNEL_FOLDER
        ),
        "from the pixel function too"
    )
    var save := FileAccess.get_file_as_string("res://core/sad-file/sa_sad_save.gd")
    assert_true(save.contains('const POURED := "%s"' % SaDataTidy.POURED_FOLDER), "and the poured saves")
