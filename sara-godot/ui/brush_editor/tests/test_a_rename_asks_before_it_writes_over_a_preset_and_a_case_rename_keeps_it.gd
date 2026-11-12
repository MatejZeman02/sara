## The brush editor's Rename asks before it writes over
## another preset, and a rename that changes only case keeps the preset.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Rename onto another preset's name wrote over it and then deleted the preset
## renamed from, with no question. Rename of "Pencil" to "pencil" wrote the new
## name and deleted the old, and on a folder that ignores case the delete took
## the file just written. Driven as `test_save_as_keeps_the_original.gd`
## drives the bar, its button's `pressed` and the field's `text_submitted`, on a
## bar built without its window. No GPU.
extends "res://tests/test_framework.gd"

const SettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")
const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")

static var scratch_dir: String = SaDataRoot.path("test_editor_rename_asks")

var _was: Array = []
var _bar: SaBrushEditorPresetBar = null
var _holders: Array[Control] = []


func before_each() -> void:
    ScratchFolder.clear(scratch_dir)
    _was = SaSettings.preset_favorites


func after_each() -> void:
    SaSettings.preset_favorites = _was
    if _bar != null:
        _bar.free()
        _bar = null
    for holder in _holders:
        holder.free()
    _holders.clear()
    ScratchFolder.clear(scratch_dir)


func _store() -> SaPresetStore:
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    return store


func _saved(store: SaPresetStore, wanted: String, spacing: float) -> String:
    var brush: Resource = SettingsScript.new()
    brush.set("spacing", spacing)
    return store.save_preset(wanted, brush)


func _bound_bar(settings: Resource, store: SaPresetStore, loaded: String) -> SaBrushEditorPresetBar:
    _bar = SaBrushEditorPresetBar.new()
    var strip := HBoxContainer.new()
    var row := HBoxContainer.new()
    _holders.append_array([strip, row])
    _bar.build_name_controls(strip)
    _bar.build_buttons(row, func() -> void: pass)
    _bar.bind(settings, store, loaded)
    return _bar


func _rename_to(text: String) -> void:
    _bar.rename_button.pressed.emit()
    _bar.preset_name_edit.text_submitted.emit(text)


func _question() -> SaMessage:
    for child in _bar.get_children():
        if child is SaMessage and child.visible and not child.is_queued_for_deletion():
            return child as SaMessage
    return null


func _press(question: SaMessage, label: String) -> void:
    for button in question.buttons:
        if button.text == label:
            button.pressed.emit()
            return
    assert_true(false, "The question has a %s button" % label)


func _spacing_of(store: SaPresetStore, preset_name: String) -> float:
    var stored := store.load_preset(preset_name)
    return float(stored.get("spacing")) if stored != null else -1.0


func test_a_rename_onto_another_preset_asks_and_cancel_writes_and_deletes_nothing() -> void:
    var store := _store()
    var pencil := _saved(store, "Editor Pencil", 0.1)
    var paint := _saved(store, "Editor Paint", 0.2)
    var settings := store.load_preset(pencil)
    _bound_bar(settings, store, pencil)
    settings.set("spacing", 0.6)
    _rename_to(paint)
    var question := _question()
    assert_not_null(question, "Rename onto another preset's name puts a question up")
    if question == null:
        return
    assert_true(question.text_label.text.contains(paint), "naming the preset that would be replaced")
    _press(question, "Cancel")
    assert_eq(store.list_names(), PackedStringArray([paint, pencil]), "Cancel deletes nothing")
    assert_almost_eq(_spacing_of(store, pencil), 0.1, 0.0001, "and writes nothing over the preset renamed from")
    assert_almost_eq(_spacing_of(store, paint), 0.2, 0.0001, "or over the other")
    assert_eq(_bar.session.preset_name, pencil, "and the editor stays on its preset")


func test_a_rename_onto_another_preset_answered_replace_writes_over_it() -> void:
    var store := _store()
    var pencil := _saved(store, "Editor Pencil", 0.1)
    var paint := _saved(store, "Editor Paint", 0.2)
    var settings := store.load_preset(pencil)
    _bound_bar(settings, store, pencil)
    settings.set("spacing", 0.6)
    _rename_to("editor paint")
    var question := _question()
    assert_not_null(question, "Another preset's name in another case asks too")
    if question == null:
        return
    _press(question, "Replace")
    assert_eq(store.list_names(), PackedStringArray([paint]), "Replace leaves one preset, under its stored name")
    assert_almost_eq(_spacing_of(store, paint), 0.6, 0.0001, "holding the renamed brush")
    assert_eq(_bar.session.preset_name, paint, "and the editor is on it")


func test_a_rename_that_changes_only_case_keeps_the_preset_after_a_fresh_read() -> void:
    var store := _store()
    var pencil := _saved(store, "Pencil", 0.1)
    SaSettings.preset_favorites = [pencil]
    _bound_bar(store.load_preset(pencil), store, pencil)
    _rename_to("pencil")
    assert_null(_question(), "A rename of the preset's own name asks nothing")
    var fresh := _store()
    var names := fresh.list_names()
    assert_eq(names, PackedStringArray(["pencil"]), "The store read again from disk holds the preset, named pencil")
    assert_almost_eq(_spacing_of(fresh, "pencil"), 0.1, 0.0001, "with its settings")
    assert_eq(_bar.session.preset_name, "pencil", "The editor is on the new name")
    assert_eq(SaSettings.preset_favorites, ["pencil"], "and the star moved with it")
