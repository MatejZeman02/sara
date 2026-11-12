## The tool bar's Save As asks before it writes over another
## preset.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A painter loaded preset A, opened Save As, typed the name of preset B and
## pressed Enter, and B's recipe was replaced by A's settings with no question.
## Driven here through the name field's `text_submitted`, the Return a hand
## gives it, on a bar built without its window, and the question read off the
## bar's children and answered by its buttons. No GPU: the settings are a stamp
## brush's resource on its own.
extends "res://tests/test_framework.gd"

const SettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")
const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")

static var scratch_dir: String = SaDataRoot.path("test_bar_save_as_asks")

var _bar: ToolOptionsPresets = null
var _settings: Resource = null


func before_each() -> void:
    ScratchFolder.clear(scratch_dir)
    _bar = ToolOptionsPresets.new()
    _bar.preset_store.dir = scratch_dir
    _settings = SettingsScript.new()
    _bar.settings_source = func() -> Resource: return _settings


func after_each() -> void:
    _bar.free()
    _bar = null
    ScratchFolder.clear(scratch_dir)


func _saved(wanted: String, spacing: float) -> String:
    var brush: Resource = SettingsScript.new()
    brush.set("spacing", spacing)
    return _bar.preset_store.save_preset(wanted, brush)


func _spacing_of(preset_name: String) -> float:
    var stored := _bar.preset_store.load_preset(preset_name)
    return float(stored.get("spacing")) if stored != null else -1.0


## Loads A, moves its spacing to 0.7 in hand, and types *typed* into Save As.
func _save_as_from_a(typed: String) -> void:
    _bar.preset_store.apply_preset("Bar A", _settings)
    _bar.selected_preset = "Bar A"
    _settings.set("spacing", 0.7)
    _bar.preset_name_edit.text_submitted.emit(typed)


## The question the bar put up, or null.
func _question() -> SaMessage:
    for child in _bar.get_children():
        if child is SaMessage and child.visible and not child.is_queued_for_deletion():
            return child as SaMessage
    return null


## Presses the question's button that reads *label*.
func _press(question: SaMessage, label: String) -> void:
    for button in question.buttons:
        if button.text == label:
            button.pressed.emit()
            return
    assert_true(false, "The question has a %s button" % label)


func test_save_as_under_another_preset_s_name_asks_and_cancel_keeps_both() -> void:
    _saved("Bar A", 0.1)
    _saved("Bar B", 0.2)
    _save_as_from_a("Bar B")
    var question := _question()
    assert_not_null(question, "Save As under B's name puts a question up")
    if question == null:
        return
    assert_true(question.text_label.text.contains("Bar B"), "naming the preset that would be replaced")
    assert_almost_eq(_spacing_of("Bar B"), 0.2, 0.0001, "and B is unchanged while it stands")
    assert_eq(question.buttons[SaPresetReplace.CANCEL].text, "Cancel", "Cancel is one answer")
    assert_eq(question._default_index, SaPresetReplace.CANCEL, "and the default one, which Enter answers")
    _press(question, "Cancel")
    assert_almost_eq(_spacing_of("Bar B"), 0.2, 0.0001, "Cancel leaves B as it was")
    assert_almost_eq(_spacing_of("Bar A"), 0.1, 0.0001, "and A as it was")
    assert_eq(_bar.preset_store.list_names(), PackedStringArray(["Bar A", "Bar B"]), "with no third preset")


func test_replace_writes_over_that_preset_and_nothing_else() -> void:
    _saved("Bar A", 0.1)
    _saved("Bar B", 0.2)
    _saved("Bar C", 0.3)
    _save_as_from_a("Bar B")
    var question := _question()
    assert_not_null(question, "The question is up")
    if question == null:
        return
    _press(question, "Replace")
    assert_almost_eq(_spacing_of("Bar B"), 0.7, 0.0001, "Replace writes the brush in hand over B")
    assert_almost_eq(_spacing_of("Bar A"), 0.1, 0.0001, "and leaves A")
    assert_almost_eq(_spacing_of("Bar C"), 0.3, 0.0001, "and C")
    assert_eq(_bar.preset_store.list_names(), PackedStringArray(["Bar A", "Bar B", "Bar C"]), "with no preset added")


func test_a_name_in_another_case_asks_and_replace_lands_on_the_stored_name() -> void:
    _saved("Bar A", 0.1)
    _saved("Bar B", 0.2)
    _save_as_from_a("bar b")
    var question := _question()
    assert_not_null(question, "B's name in another case is B, and asks")
    if question == null:
        return
    assert_true(question.text_label.text.contains("Bar B"), "naming B as it is stored")
    _press(question, "Replace")
    assert_eq(_bar.preset_store.list_names(), PackedStringArray(["Bar A", "Bar B"]), "No second file differing in case")
    assert_almost_eq(_spacing_of("Bar B"), 0.7, 0.0001, "and B holds the brush in hand")


func test_the_loaded_preset_s_own_name_asks_nothing() -> void:
    _saved("Bar A", 0.1)
    _saved("Bar B", 0.2)
    _save_as_from_a("Bar A")
    assert_null(_question(), "A's own name is a plain Save")
    assert_almost_eq(_spacing_of("Bar A"), 0.7, 0.0001, "written over A")
    _save_as_from_a("bar a")
    assert_null(_question(), "and so is A's name in another case")
    assert_eq(_bar.preset_store.list_names(), PackedStringArray(["Bar A", "Bar B"]), "landing on A's own file")


func test_a_free_name_asks_nothing() -> void:
    _saved("Bar A", 0.1)
    _save_as_from_a("Bar Fresh")
    assert_null(_question(), "A name no preset holds asks nothing")
    assert_true(_bar.preset_store.has_preset("Bar Fresh"), "and is written")
