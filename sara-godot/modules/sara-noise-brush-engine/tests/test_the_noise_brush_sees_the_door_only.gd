## The noise brush sees the door only.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The module is meant to be one a third party could have written, so every
## script and kernel in it is read for a path into the base modules, the
## stamp's among them, and the suite fails on the first. The check is one
## function over text, so the second case plants a path and watches it caught,
## which is what tells a suite that passes from a suite that reads nothing.
extends "res://tests/test_framework.gd"

const MODULE_DIR: String = "res://modules/sara-noise-brush-engine"

## What a reach past the door looks like in a script or a kernel: the base
## modules' folder by any path, or the stamp's kernel by its shader name, which
## the compiler finds anywhere under `modules/` without a path at all.
const FORBIDDEN: Array[String] = ["sara-base-modules", "import dab\n", 'SaCompute.new("dab")']


## Every file under *dir* whose extension is one the module's code is in,
## the suites included, since a suite that preloads the stamp would load it.
func _sources(dir: String) -> PackedStringArray:
    var out := PackedStringArray()
    for file in DirAccess.get_files_at(dir):
        if file.get_extension() in ["gd", "gmacs"]:
            out.append(dir.path_join(file))
    for sub in DirAccess.get_directories_at(dir):
        if not sub.begins_with("."):
            out.append_array(_sources(dir.path_join(sub)))
    return out


## Each reach past the door in *text*, as `path: needle`. This file names the
## needles it looks for, so it is the one file whose own text is not read.
static func reaches(path: String, text: String) -> PackedStringArray:
    var out := PackedStringArray()
    for needle in FORBIDDEN:
        if text.contains(needle):
            out.append("%s: %s" % [path, needle.strip_edges()])
    return out


func test_no_script_or_kernel_reaches_past_the_door() -> void:
    var own := (get_script() as Script).resource_path
    var files := _sources(MODULE_DIR)
    var found := PackedStringArray()
    var read := 0
    for path in files:
        if path == own:
            continue
        found.append_array(reaches(path, FileAccess.get_file_as_string(path)))
        read += 1
    assert_true(read >= 4, "The module, its state, its settings and its kernel were read, %d files" % read)
    assert_true(found.is_empty(), "Nothing in the noise module names the base modules: %s" % ", ".join(found))


func test_a_planted_path_into_the_stamp_is_caught() -> void:
    var planted := 'const Stamp = preload("res://modules/%s/stamp-brush/tools/state_brush.gd")\n' % "sara-base-modules"
    assert_eq(reaches("planted.gd", planted).size(), 1, "A preload of the stamp's state is a reach past the door")
    var kernel := "kernel noise_dab\n\nimport dab\nimport brush_tip\n"
    assert_eq(reaches("planted.gmacs", kernel).size(), 1, "and so is an import of the stamp's kernel")
    var clean := "kernel noise_dab\n\nimport brush_paint_modes\nimport brush_tip\n"
    assert_true(reaches("clean.gmacs", clean).is_empty(), "while the door's libraries are not")


func test_the_kernel_imports_the_brush_library() -> void:
    var text := FileAccess.get_file_as_string(MODULE_DIR.path_join("noise_dab.gmacs"))
    assert_true(text.contains("import brush_tip"), "The kernel includes the door's tip library")
    assert_true(text.contains("import brush_paint_modes"), "and its paint modes, for wash")
