## The kernel written to check a field's own function has a short file name,
## however long the include path it is made from.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The name was the import's whole path with its slashes made underscores, and
## the file sits under the data root, so a deep `--settings-dir` pushed it past
## the 255 bytes a file system holds and the check could not be written.
extends "res://tests/test_framework.gd"


func test_a_deep_include_path_gives_a_short_name() -> void:
    var deep := "sara_fields/" + "a_folder_of_some_length/".repeat(12) + "below_".repeat(60) + "field"
    var name := SaBrushFieldRegistry.check_kernel_name(deep)
    assert_true((name + ".gmacs").to_utf8_buffer().size() < 64, "the file name is short, %d bytes" % name.length())
    assert_true(name.ends_with(SaBrushFieldRegistry.CHECK_SUFFIX), "and still ends in the check suffix: %s" % name)
    var plain := RegEx.create_from_string("^[A-Za-z_][A-Za-z0-9_]*$")
    assert_not_null(plain.search(name), "and is an identifier a kernel can carry: %s" % name)


func test_two_include_paths_never_share_a_name() -> void:
    var one := SaBrushFieldRegistry.check_kernel_name("noise_fields/a/b")
    var two := SaBrushFieldRegistry.check_kernel_name("noise_fields/a_b")
    assert_true(one != two, "paths that only differ in a slash keep their own file")
    assert_eq(one, SaBrushFieldRegistry.check_kernel_name("noise_fields/a/b"), "and one path keeps its name")
