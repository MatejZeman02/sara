## Deleting a preset drops its star, and no other.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The decision, "Deleting a preset drops its star", through the one
## delete a painter has, the docker's Delete button pressing
## `ToolOptionsPresets.delete_loaded_preset`. The rest is
## `test_a_profile_keeps_its_starred_presets` beside the settings. The
## autoload's list is put back after each test.
extends "res://tests/test_framework.gd"

const SettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")

static var scratch_dir: String = SaDataRoot.path("test_p1_deleted_presets")

var _was: Array = []


func before_each() -> void:
    _clear()
    _was = SaSettings.preset_favorites


func after_each() -> void:
    SaSettings.preset_favorites = _was
    _clear()


func _clear() -> void:
    var dir := DirAccess.open(scratch_dir)
    if dir == null:
        return
    for file: String in dir.get_files():
        dir.remove(file)


## A brush saved under *wanted*, answering the name the store gave it.
func _saved(store: SaPresetStore, wanted: String) -> String:
    var brush: Resource = SettingsScript.new()
    brush.set("radius", 0.3)
    return store.save_preset(wanted, brush)


func test_a_delete_drops_that_star_and_no_other() -> void:
    var bar := ToolOptionsPresets.new()
    bar.preset_store.dir = scratch_dir
    var doomed := _saved(bar.preset_store, "Doomed")
    var kept := _saved(bar.preset_store, "Kept")
    SaSettings.preset_favorites = [kept, doomed, "Not In The Store"]
    bar.selected_preset = doomed

    bar.delete_loaded_preset()

    assert_false(bar.preset_store.has_preset(doomed), "The preset is gone")
    var left := SaSettings.preset_favorites
    assert_eq(left, [kept, "Not In The Store"], "with its star, and every other star stays, a name the store lacks included")
    bar.free()


func test_a_delete_of_an_unstarred_preset_leaves_the_stars() -> void:
    var bar := ToolOptionsPresets.new()
    bar.preset_store.dir = scratch_dir
    var plain := _saved(bar.preset_store, "Plain")
    SaSettings.preset_favorites = ["Other"]
    bar.selected_preset = plain
    bar.delete_loaded_preset()
    assert_eq(SaSettings.preset_favorites, ["Other"], "The list is as it was")
    bar.free()
