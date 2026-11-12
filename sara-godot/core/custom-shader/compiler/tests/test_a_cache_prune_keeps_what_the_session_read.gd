## The SPIR-V cache's prune keeps an entry this process read, however old.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A hit reads a file and never writes it, so a kernel every boot loads keeps
## the modification time of the day it was compiled. The prune dropped by age
## alone, and in a full directory the kernels every boot reads were the first
## to go. The painter's cache sat at the cap with a boot using about 150 of its
## 256 entries, and boots kept recompiling a few dozen.
extends "res://tests/test_framework.gd"

const OLD_KEY := "b2_test_read_this_session"
const FAKE_PREFIX := "b2_test_fake_"


func after_each() -> void:
    var dir := DirAccess.open(SaSpirvCache.cache_dir())
    if dir == null:
        return
    for entry_name: String in dir.get_files():
        if entry_name.begins_with("b2_test_"):
            dir.remove(entry_name)


func _write(key: String) -> void:
    var file := FileAccess.open(SaSpirvCache.path_for(key), FileAccess.WRITE)
    file.store_buffer(PackedByteArray([1, 2, 3, 4]))


func test_an_old_entry_read_this_session_outlives_newer_ones() -> void:
    DirAccess.make_dir_recursive_absolute(SaSpirvCache.cache_dir())
    _write(OLD_KEY)
    # Modification times are whole seconds.
    OS.delay_msec(1100)
    assert_not_null(SaSpirvCache.load_spirv(OLD_KEY), "a hit on the old entry")
    # Enough newer entries that age alone drops every entry older than them.
    for i in SaSpirvCache.CACHE_MAX:
        _write(FAKE_PREFIX + str(i))

    var dropped := SaSpirvCache.prune()

    assert_true(dropped > 0, "the directory was over the cap")
    assert_eq(SaSpirvCache.count(), SaSpirvCache.CACHE_MAX, "and is at it again")
    assert_true(FileAccess.file_exists(SaSpirvCache.path_for(OLD_KEY)), "the entry this process read is kept")
