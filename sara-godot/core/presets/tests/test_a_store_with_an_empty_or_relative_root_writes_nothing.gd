## A store whose `dir` is empty or relative writes nothing, and a relative
## `--settings-dir` is made absolute before a store reads it.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## An empty `dir` is the process's working folder, which under a test run is the
## project folder. A suite that left one there once wrote every stock preset,
## the bundle records and the tag marker into the source tree. The store now
## refuses, with a `push_error`, so the one ERROR line this suite makes in the
## run log is the refusal itself. No window and no GPU.
extends "res://tests/test_framework.gd"

const SettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")

const PROBE: String = "sa_relative_root_probe"


func _store(root: String) -> SaPresetStore:
    var store := SaPresetStore.new()
    store.dir = root
    return store


func test_a_relative_root_saves_nothing_and_makes_no_folder() -> void:
    var store := _store(PROBE)
    assert_eq(store.save_preset("Pencil", SettingsScript.new()), "", "the save is refused")
    assert_false(DirAccess.dir_exists_absolute(PROBE), "and no folder is made in the working folder")


func test_an_empty_root_saves_nothing() -> void:
    var store := _store("")
    assert_eq(store.save_preset("Pencil", SettingsScript.new()), "", "the save is refused")
    assert_false(FileAccess.file_exists("Pencil.tres"), "and no file lands in the working folder")


func test_a_relative_root_installs_no_shipped_preset() -> void:
    var store := _store(PROBE)
    var recipes: Script = load("res://modules/sara-base-modules/stamp-brush/presets/sa_shipped_presets.gd")
    assert_eq(store.install_shipped(SettingsScript.new(), recipes), 0, "nothing is written")
    assert_false(DirAccess.dir_exists_absolute(PROBE), "and no folder is made")


func test_a_user_root_is_still_written() -> void:
    var root := SaDataRoot.path("test_a_user_root_is_written")
    var store := _store(root)
    assert_true(not store.save_preset("Pencil", SettingsScript.new()).is_empty(), "an absolute root saves")
    store.delete_preset("Pencil")
    DirAccess.remove_absolute(root)


func test_a_relative_settings_folder_becomes_an_absolute_one() -> void:
    assert_true(SaDataRoot.absolute("notes").is_absolute_path(), "a relative folder is read from the working folder")
    assert_eq(SaDataRoot.absolute("/tmp/x"), "/tmp/x", "an absolute one is left as it is")
    assert_eq(SaDataRoot.absolute("user://x"), "user://x", "so is a user:// one")
