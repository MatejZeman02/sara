## A preset whose script lives in a module this build lacks is skipped, and
## the presets beside it still load.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A profile written by an older build can hold presets of a module the release
## does not carry. Loading one printed an engine error for each resource it
## named, so the store looks at the `.tres` header first. The file is left on
## disk, since the module may come back. No window and no GPU.
extends "res://tests/test_framework.gd"

const SettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")
const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")

static var scratch_dir: String = SaDataRoot.path("test_preset_missing_module")


func before_each() -> void:
    ScratchFolder.clear(scratch_dir)


func after_each() -> void:
    ScratchFolder.clear(scratch_dir)


func _store() -> SaPresetStore:
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    return store


func _orphan(file_name: String) -> String:
    var path := scratch_dir.path_join(file_name)
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_string(
        (
            '[gd_resource type="Resource" script_class="GoneSettings" load_steps=2 format=3]\n\n'
            + '[ext_resource type="Script" path="res://modules/no-such-module/gone_settings.gd" id="1_gone"]\n\n'
            + '[resource]\nscript = ExtResource("1_gone")\n'
        )
    )
    file = null
    return path


func test_a_preset_naming_a_missing_script_loads_as_skipped_and_stays_on_disk() -> void:
    var store := _store()
    var brush: Resource = SettingsScript.new()
    store.save_preset("Kept", brush)
    var orphan := _orphan("Glaze Wash.tres")
    assert_null(store.load_preset("Glaze Wash"), "A preset of a missing module loads as null")
    assert_null(store.load_preset("Glaze Wash"), "and a second ask is the same answer")
    assert_true(FileAccess.file_exists(orphan), "its file is left on disk")
    assert_not_null(store.load_preset("Kept"), "while the preset beside it still loads")
    var named := SaPresetMissingModule.first_missing_resource(orphan)
    assert_eq(named, "res://modules/no-such-module/gone_settings.gd", "and the missing path is named")
