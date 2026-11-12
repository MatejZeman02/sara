## The brush editor's Save As keeps the original preset, and its Rename still
## renames.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Both buttons open one name field and its Return must not go to the session's
## rename whichever had opened it, or Save As on Pencil would write the new
## preset and delete `Pencil.tres`. Driven here the way a hand drives it, the button's
## `pressed` and then the field's `text_submitted`, on a bar built without its
## window, and read back from the store's names.
##
## No window and no GPU: the bar is a `Node` with its controls, and the settings
## are a stamp brush's resource on its own. The starred list is an autoload,
## put back after each test.
extends "res://tests/test_framework.gd"

const SettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")

static var scratch_dir: String = SaDataRoot.path("test_s1_save_as")

var _was: Array = []
var _bar: SaBrushEditorPresetBar = null
var _holders: Array[Control] = []


func before_each() -> void:
    _clear()
    _was = SaSettings.preset_favorites


func after_each() -> void:
    SaSettings.preset_favorites = _was
    if _bar != null:
        _bar.free()
        _bar = null
    for holder in _holders:
        holder.free()
    _holders.clear()
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


## A brush with *spacing*, saved under *wanted*, and the name the store gave it.
func _saved(store: SaPresetStore, wanted: String, spacing: float) -> String:
    var brush: Resource = SettingsScript.new()
    brush.set("spacing", spacing)
    return store.save_preset(wanted, brush)


## The bar with its name controls and its row of buttons, bound to *settings*
## and *store* on *loaded*, the way the window builds and binds it.
func _bound_bar(settings: Resource, store: SaPresetStore, loaded: String) -> SaBrushEditorPresetBar:
    _bar = SaBrushEditorPresetBar.new()
    var strip := HBoxContainer.new()
    var row := HBoxContainer.new()
    _holders.append_array([strip, row])
    _bar.build_name_controls(strip)
    _bar.build_buttons(row, func() -> void: pass)
    _bar.bind(settings, store, loaded)
    return _bar


## Presses *button* and types *text* into the field it opens, with Return.
func _press_and_type(button: Button, text: String) -> void:
    button.pressed.emit()
    _bar.preset_name_edit.text_submitted.emit(text)


## Every line the corner notice was handed while *action* ran.
func _said(action: Callable) -> Array[String]:
    var said: Array[String] = []
    var ear := func(text: String) -> void: said.append(text)
    EventBus.corner_notice.connect(ear)
    action.call()
    EventBus.corner_notice.disconnect(ear)
    return said


## Every `[name, saved]` pair the store announced on the bus while *action* ran.
func _announced(action: Callable) -> Array:
    var heard: Array = []
    var ear := func(preset_name: String, saved: bool) -> void: heard.append([preset_name, saved])
    EventBus.preset_store_changed.connect(ear)
    action.call()
    EventBus.preset_store_changed.disconnect(ear)
    return heard


func _spacing_of(store: SaPresetStore, preset_name: String) -> float:
    var stored := store.load_preset(preset_name)
    return float(stored.get("spacing")) if stored != null else -1.0


func test_save_as_writes_a_second_preset_and_keeps_the_first() -> void:
    var store := _store()
    var pencil := _saved(store, "Pencil", 0.1)
    var settings := store.load_preset(pencil)
    var bar := _bound_bar(settings, store, pencil)
    settings.set("spacing", 0.4)
    bar.sync_dirty()
    assert_eq(bar.dirty_label.text, SaBrushEditorSession.DIRTY_TEXT, "A moved Spacing reads as unsaved")

    bar.save_as_button.pressed.emit()
    assert_true(bar.preset_name_edit.visible, "Save As opens the name field")
    assert_eq(bar.preset_name_edit.text, "", "empty, because the copy wants a new name")
    var heard := _announced(func() -> void: bar.preset_name_edit.text_submitted.emit("Pencil Two"))

    assert_true(store.has_preset(pencil), "The original is still in the store")
    assert_true(store.has_preset("Pencil Two"), "beside the copy")
    assert_almost_eq(_spacing_of(store, pencil), 0.1, 0.0001, "and the original holds what it held")
    assert_almost_eq(_spacing_of(store, "Pencil Two"), 0.4, 0.0001, "while the copy holds the moved Spacing")
    assert_eq(bar.session.preset_name, "Pencil Two", "The editor is on the copy")
    assert_eq(bar.preset_label.text, "Pencil Two", "and its name says so")
    assert_eq(bar.dirty_label.text, SaBrushEditorSession.CLEAN_TEXT, "which reads Saved")
    assert_false(bar.preset_name_edit.visible, "and the field is put away")
    assert_eq(heard, [["Pencil Two", true]], "The bus hears one preset written and none removed")


func test_save_as_leaves_the_star_on_the_original() -> void:
    var store := _store()
    var pencil := _saved(store, "Starred", 0.1)
    SaSettings.preset_favorites = ["First", pencil]
    var bar := _bound_bar(store.load_preset(pencil), store, pencil)
    _press_and_type(bar.save_as_button, "Starred Copy")
    assert_eq(SaSettings.preset_favorites, ["First", pencil], "The star stays where it was, on the original")


func test_rename_still_removes_the_old_name_and_moves_its_star() -> void:
    var store := _store()
    var pencil := _saved(store, "Pencil", 0.1)
    var bar := _bound_bar(store.load_preset(pencil), store, pencil)
    _press_and_type(bar.save_as_button, "Pencil Two")
    SaSettings.preset_favorites = ["Pencil Two"]

    bar.rename_button.pressed.emit()
    assert_eq(bar.preset_name_edit.text, "Pencil Two", "Rename prefills the loaded name")
    var heard := _announced(func() -> void: bar.preset_name_edit.text_submitted.emit("Pencil Three"))

    assert_false(store.has_preset("Pencil Two"), "The renamed preset's old name is gone")
    assert_true(store.has_preset("Pencil Three"), "and its new one is there")
    assert_true(store.has_preset(pencil), "while the preset the copy came from is untouched")
    assert_eq(SaSettings.preset_favorites, ["Pencil Three"], "The star moved with the rename")
    assert_eq(bar.session.preset_name, "Pencil Three", "and the editor is on the new name")
    assert_eq(heard, [["Pencil Two", false], ["Pencil Three", true]], "The bus hears the old name go and the new one come")


## Rename opened the field and was let go of, then Save As opened it again. The
## Return belongs to the button that opened the field last.
func test_save_as_after_an_abandoned_rename_is_a_copy() -> void:
    var store := _store()
    var pencil := _saved(store, "Pencil", 0.1)
    var bar := _bound_bar(store.load_preset(pencil), store, pencil)
    bar.rename_button.pressed.emit()
    _press_and_type(bar.save_as_button, "Pencil Copy")
    assert_true(store.has_preset(pencil), "The original stays")
    assert_true(store.has_preset("Pencil Copy"), "beside the copy")


func test_save_as_under_the_loaded_name_is_a_plain_save() -> void:
    var store := _store()
    var pencil := _saved(store, "Pencil", 0.1)
    var settings := store.load_preset(pencil)
    var bar := _bound_bar(settings, store, pencil)
    settings.set("spacing", 0.3)
    var lines := _said(func() -> void: _press_and_type(bar.save_as_button, "Pencil"))

    assert_eq(store.list_names(), PackedStringArray([pencil]), "One preset, no copy")
    assert_almost_eq(_spacing_of(store, pencil), 0.3, 0.0001, "written over with the settings as they are")
    assert_eq(bar.dirty_label.text, SaBrushEditorSession.CLEAN_TEXT, "and reading Saved")
    assert_eq(lines.size(), 0, "A Save replaces nothing worth a notice")


func test_save_as_under_another_preset_s_name_saves_over_it_and_says_so() -> void:
    var store := _store()
    var pencil := _saved(store, "Pencil", 0.1)
    var paint := _saved(store, "Paint", 0.2)
    var settings := store.load_preset(pencil)
    var bar := _bound_bar(settings, store, pencil)
    settings.set("spacing", 0.5)
    var lines := _said(func() -> void: _press_and_type(bar.save_as_button, paint))

    assert_true(store.has_preset(pencil), "The original stays")
    assert_almost_eq(_spacing_of(store, pencil), 0.1, 0.0001, "as it was")
    assert_almost_eq(_spacing_of(store, paint), 0.5, 0.0001, "and the other preset is written over, as the store does")
    assert_eq(lines.size(), 1, "One line in the corner")
    assert_true(lines.size() == 1 and lines[0].contains(paint), "naming the preset that was replaced")
    assert_eq(bar.session.preset_name, paint, "and the editor is on it")


func test_save_as_with_no_preset_loaded_names_the_brush() -> void:
    var store := _store()
    var settings: Resource = SettingsScript.new()
    var bar := _bound_bar(settings, store, "")
    assert_true(bar.rename_button.disabled, "Rename is dimmed with nothing to rename")
    _press_and_type(bar.save_as_button, "Fresh")
    assert_eq(store.list_names(), PackedStringArray(["Fresh"]), "The brush is stored")
    assert_eq(bar.session.preset_name, "Fresh", "and the editor is on it")
    assert_false(bar.rename_button.disabled, "with Rename live")
