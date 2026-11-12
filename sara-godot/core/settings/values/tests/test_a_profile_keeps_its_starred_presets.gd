## The profile keeps the presets the painter starred.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The store half of the note's "some star or heart that you can always click".
## The stars live in the profile beside the blend favourites, keyed by preset
## name, and a preset file carries none. The profile is read through a file
## object and a values node of the suite's own, as the brush slots' suite does.
## The delete dropping a star is `test_a_deleted_preset_takes_its_star` beside
## the presets and the rename moving one is `test_a_renamed_preset_keeps_its_star`
## beside the brush editor's session, because both name a class of `ui`.
extends "res://tests/test_framework.gd"

const SettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")

static var scratch_path: String = SaDataRoot.path("test_p1_starred_presets.cfg")
static var scratch_dir: String = SaDataRoot.path("test_p1_presets")

var _was: Array = []


func before_each() -> void:
    _clear()
    _was = SaSettings.preset_favorites
    SaSettings.preset_favorites = []


func after_each() -> void:
    SaSettings.preset_favorites = _was
    _clear()


func _clear() -> void:
    var path := ProjectSettings.globalize_path(scratch_path)
    for suffix: String in ["", ".bak", ".tmp", ".broken"]:
        DirAccess.remove_absolute(path + suffix)
    var dir := DirAccess.open(scratch_dir)
    if dir == null:
        return
    for file: String in dir.get_files():
        dir.remove(file)


## A file object on the suite's scratch profile.
func _file() -> SaSettingsFile:
    var file := SaSettingsFile.new()
    file.settings_path = ProjectSettings.globalize_path(scratch_path)
    return file


## The profile a load of the scratch file gives, a first launch's when there is
## none yet.
func _loaded(file: SaSettingsFile) -> SaSettingsValues:
    var values := SaSettingsValues.new()
    file.load_from_disk(values)
    return values


func _store() -> SaPresetStore:
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    return store


## A brush saved under *wanted*, answering the name the store gave it.
func _saved(store: SaPresetStore, wanted: String) -> String:
    var brush: Resource = SettingsScript.new()
    brush.set("radius", 0.3)
    return store.save_preset(wanted, brush)


func test_a_fresh_profile_has_no_stars() -> void:
    var values := _loaded(_file())
    assert_eq(values.preset_favorites, [], "A first launch stars nothing")
    var place := SaSettingsValues.place_of(&"preset_favorites")
    assert_eq(place, ["tools", "preset_favorites"], "and the list sits with the other preset preferences")
    values.free()


func test_a_star_survives_a_save_and_a_load() -> void:
    var file := _file()
    var values := _loaded(file)
    values.changed.connect(func(property: StringName) -> void: file.write(property, values.stored(String(property))))
    values.toggle_preset_favorite("Paint")
    values.toggle_preset_favorite("Charcoal")
    values.free()

    var again := _loaded(_file())
    assert_eq(again.preset_favorites, ["Paint", "Charcoal"], "The stars read back from the profile, in the order starred")
    again.free()


func test_a_toggle_adds_and_removes_in_the_order_starred() -> void:
    var values := SaSettingsValues.new()
    var heard: Array = []
    values.preset_favorites_changed.connect(func() -> void: heard.append(values.preset_favorites.duplicate()))
    assert_true(values.toggle_preset_favorite("Sketch"), "A first click stars")
    assert_true(values.toggle_preset_favorite("Paint"), "and a second preset")
    assert_true(values.toggle_preset_favorite("Wash"), "and a third")
    assert_eq(values.preset_favorites, ["Sketch", "Paint", "Wash"], "in the order starred, not by name")
    assert_false(values.toggle_preset_favorite("Paint"), "A second click unstars")
    assert_eq(values.preset_favorites, ["Sketch", "Wash"], "and the others keep their order")
    assert_eq(heard.size(), 4, "Every toggle says so on the list's own signal")
    values.free()


func test_a_starred_preset_writes_no_star_into_its_file() -> void:
    var store := _store()
    SaSettings.preset_favorites = ["Starred"]
    var stored := _saved(store, "Starred")
    SaSettings.preset_favorites = [stored]
    _saved(store, stored)
    var files := DirAccess.get_files_at(scratch_dir)
    assert_false(files.is_empty(), "The preset is on disk")
    for file: String in files:
        var text := FileAccess.get_file_as_string(scratch_dir.path_join(file))
        assert_false(text.containsn("favorit"), "%s carries no favourites" % file)


func test_the_rule_renames_and_drops_without_touching_the_rest() -> void:
    var list := ["a", "b", "c"]
    assert_eq(SaSettingsFavorites.renamed(list, "b", "z"), ["a", "z", "c"], "A rename keeps the place")
    assert_eq(SaSettingsFavorites.renamed(list, "q", "z"), list, "A name not starred leaves the list")
    assert_eq(SaSettingsFavorites.renamed(list, "a", "c"), ["c", "b"], "A rename onto a starred name keeps it once")
    assert_eq(SaSettingsFavorites.dropped(list, "b"), ["a", "c"], "A drop takes one name")
    assert_eq(list, ["a", "b", "c"], "and no call edits the list it was given")
