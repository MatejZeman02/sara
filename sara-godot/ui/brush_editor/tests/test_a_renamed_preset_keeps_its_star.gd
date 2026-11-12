## A renamed preset keeps its star, under its new name.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The stars are keyed by preset name and the brush editor's Rename is a write
## under the new name and a delete of the old one, so a star that did not follow
## would be dropped by the rename. Driven through `SaBrushEditorSession.write_named`,
## which the Rename calls. The profile's side is
## `test_a_profile_keeps_its_starred_presets` beside the settings. The
## autoload's list is put back after each test.
extends "res://tests/test_framework.gd"

const SettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")

static var scratch_dir: String = SaDataRoot.path("test_p1_renamed_presets")

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


func _store() -> SaPresetStore:
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    return store


## A brush saved under *wanted*, answering the name the store gave it.
func _saved(store: SaPresetStore, wanted: String) -> String:
    var brush: Resource = SettingsScript.new()
    brush.set("radius", 0.3)
    return store.save_preset(wanted, brush)


func test_a_rename_moves_the_star_in_its_place() -> void:
    var store := _store()
    var first := _saved(store, "First")
    var old := _saved(store, "Old Name")
    SaSettings.preset_favorites = [first, old, "Last"]
    var session := SaBrushEditorSession.new(store.load_preset(old), store, old)

    var stored := session.write_named("New Name")

    assert_false(stored.is_empty(), "The rename is written")
    assert_false(store.has_preset(old), "and the old name is gone")
    assert_eq(SaSettings.preset_favorites, [first, stored, "Last"], "The star follows the new name, in the old one's place")


func test_a_rename_of_an_unstarred_preset_stars_nothing() -> void:
    var store := _store()
    var old := _saved(store, "Plain")
    SaSettings.preset_favorites = ["Other"]
    var session := SaBrushEditorSession.new(store.load_preset(old), store, old)
    session.write_named("Plain Renamed")
    assert_eq(SaSettings.preset_favorites, ["Other"], "The list is as it was")
