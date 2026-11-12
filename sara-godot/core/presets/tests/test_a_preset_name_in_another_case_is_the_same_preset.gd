## A preset name in another case is the same preset, and a
## rename that changes only case keeps the preset.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## On Windows and macOS "pencil" saved beside "Pencil" writes over
## `Pencil.tres`, and a rename from one to the other wrote the file and then
## deleted it. The store folds case on every platform, so Linux, where this
## suite runs, answers as those two would. No window and no GPU.
extends "res://tests/test_framework.gd"

const SettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")
const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")

static var scratch_dir: String = SaDataRoot.path("test_preset_case_folded")


func before_each() -> void:
    ScratchFolder.clear(scratch_dir)


func after_each() -> void:
    ScratchFolder.clear(scratch_dir)


func _store() -> SaPresetStore:
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    return store


func _saved(store: SaPresetStore, wanted: String, spacing: float) -> String:
    var brush: Resource = SettingsScript.new()
    brush.set("spacing", spacing)
    return store.save_preset(wanted, brush)


func test_a_name_in_another_case_is_taken_by_the_stored_preset() -> void:
    var store := _store()
    _saved(store, "Pencil", 0.3)
    assert_eq(store.taken_as("pencil"), "Pencil", '"pencil" is taken, by the stored "Pencil"')
    assert_eq(store.taken_as("  PENCIL "), "Pencil", "and so is any case of it, sanitised as a save sanitises")
    assert_eq(store.taken_as("Pen"), "", "while another name is free")
    assert_eq(store.taken_as(""), "", "and an empty one names nothing")


func test_a_rename_that_changes_only_case_keeps_one_preset_with_its_settings() -> void:
    var store := _store()
    _saved(store, "Pencil", 0.3)
    var before := store.load_preset("Pencil")
    var moved := SaPresetNames.move_case(store, "Pencil", "pencil")
    assert_eq(moved, "pencil", "The rename answers the new name")
    assert_eq(store.list_names(), PackedStringArray(["pencil"]), 'One preset in the store, named "pencil"')
    var after := store.load_preset("pencil")
    assert_not_null(after, "which loads")
    assert_almost_eq(float(after.get("spacing")), float(before.get("spacing")), 0.0001, "with its settings unchanged")
    assert_eq(after.get_meta(SaPresetMeta.ENGINE_META, &""), before.get_meta(SaPresetMeta.ENGINE_META, &""), "its engine too")
    var leftovers := Array(DirAccess.get_files_at(scratch_dir)).filter(
        func(file: String) -> bool: return file.ends_with(SaPresetNames.PASSING_SUFFIX)
    )
    assert_eq(leftovers.size(), 0, "and no passing file is left behind")


func test_a_rename_to_another_name_is_not_a_case_move() -> void:
    var store := _store()
    _saved(store, "Pencil", 0.3)
    assert_eq(SaPresetNames.move_case(store, "Pencil", "Pen"), "", "A move of case only, never a rename to another name")
    assert_eq(SaPresetNames.move_case(store, "Pencil", "Pencil"), "", "nor to the same name")
    assert_eq(store.list_names(), PackedStringArray(["Pencil"]), "and the store is as it was")
