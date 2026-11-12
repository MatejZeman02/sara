## The brush editor learns the name of a preset another surface saved, when the
## preset is the brush it is editing.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## This holds the half a machine can hold: the session takes a name the store
## was given by another surface. The store is
## written here directly, which is what the top bar's Save As does, and the
## session is asked. The window's half, that it listens and redraws, is the
## scenario's, because a `Window` in a headless run hangs.
extends "res://tests/test_framework.gd"

const SettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")

static var scratch_dir: String = SaDataRoot.path("test_d19_presets")


func after_each() -> void:
    var dir := DirAccess.open(scratch_dir)
    if dir == null:
        return
    for file: String in dir.get_files():
        dir.remove(file)


func _store() -> SaPresetStore:
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    return store


## The bar saved the live brush under a name, and the session takes that name
## and reads as saved, which is what the editor's dashboard then says.
func test_the_session_takes_a_name_the_store_was_given_for_this_brush() -> void:
    var store := _store()
    var live: Resource = SettingsScript.new()
    live.set("radius", 0.3)
    var stored := store.save_preset("from the bar", live)
    assert_false(stored.is_empty(), "the store took the brush")

    var session := SaBrushEditorSession.adopting(live, store, stored)

    assert_not_null(session, "the session takes the name")
    if session != null:
        assert_eq(session.preset_name, stored, "under the name the store gave it")
        assert_false(session.is_dirty(), "and the live brush matches it")
        assert_eq(session.dirty_text(), SaBrushEditorSession.CLEAN_TEXT, "so the dashboard says Saved")


## Something else was stored, an import or another brush, and the session does
## not pretend the painter is on it.
func test_the_session_refuses_a_name_whose_preset_is_another_brush() -> void:
    var store := _store()
    var other: Resource = SettingsScript.new()
    other.set("radius", 0.05)
    var stored := store.save_preset("someone else's brush", other)
    var live: Resource = SettingsScript.new()
    live.set("radius", 0.3)

    assert_null(SaBrushEditorSession.adopting(live, store, stored), "a preset that is not the live brush is not adopted")


## The guards: nothing to compare against, nothing adopted.
func test_no_store_or_no_name_adopts_nothing() -> void:
    var live: Resource = SettingsScript.new()
    assert_null(SaBrushEditorSession.adopting(live, null, "anything"), "no store")
    assert_null(SaBrushEditorSession.adopting(live, _store(), ""), "no name")
    assert_null(SaBrushEditorSession.adopting(null, _store(), "anything"), "no brush")
