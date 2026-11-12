## A cache filled past its cap keeps every kernel the current start used.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Sized past the kernels a start compiles, the cache holds every boot kernel
## with room for third-party modules. When older or unread entries push the
## directory past the cap, the prune evicts only unused entries and keeps
## every kernel the running process used.
extends "res://tests/test_framework.gd"

const FAKE_PREFIX := "fake_"


func after_each() -> void:
    var dir := DirAccess.open(SaSpirvCache.cache_dir())
    if dir == null:
        return
    for entry_name: String in dir.get_files():
        if entry_name.begins_with(FAKE_PREFIX):
            dir.remove(entry_name)


func _write(key: String) -> void:
    var file := FileAccess.open(SaSpirvCache.path_for(key), FileAccess.WRITE)
    file.store_buffer(PackedByteArray([1, 2, 3, 4]))


func test_cache_cap_holds_every_boot_kernel_with_room_for_modules() -> void:
    assert_true(SaSpirvCache.CACHE_MAX >= 512, "the cap holds every boot kernel, 282 on a clean boot, with room for modules")


func test_cache_filled_past_cap_keeps_kernels_the_current_start_used() -> void:
    DirAccess.make_dir_recursive_absolute(SaSpirvCache.cache_dir())
    var used_keys: Array[String] = []
    for key: String in SaSpirvCache._used:
        if FileAccess.file_exists(SaSpirvCache.path_for(key)):
            used_keys.append(key)
    assert_true(not used_keys.is_empty(), "the current start has used kernels kept in the cache")

    var needed: int = (SaSpirvCache.CACHE_MAX - SaSpirvCache.count()) + 20
    if needed < 20:
        needed = 20
    for i in needed:
        _write(FAKE_PREFIX + str(i))

    assert_true(SaSpirvCache.count() > SaSpirvCache.CACHE_MAX, "the directory is filled past its cap")

    var dropped := SaSpirvCache.prune()

    assert_true(dropped >= 20, "the prune dropped the unread entries")
    assert_eq(SaSpirvCache.count(), SaSpirvCache.CACHE_MAX, "the directory is back at the cap")

    var missing: Array[String] = []
    for key: String in used_keys:
        if not FileAccess.file_exists(SaSpirvCache.path_for(key)):
            missing.append(key)
    assert_eq(missing, [], "every kernel used by the start is kept in the cache")
