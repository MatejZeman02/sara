## On a tablet with no keyboard no menu row draws its chord and no tooltip ends
## in "(E)", because a painter there cannot press those keys.
##
## The platform is taken as Android through `SaKeyLabels`' two overrides, once
## with no keyboard and once with one, and the desktop is the overrides cleared.
## The Edit menu is read off a bar bound the way main binds it, and the erase
## toggle's tooltip goes through `SaTooltip`'s hook the way the engine's own
## tooltip label does, hung on an autoload for the reason
## `test_tooltip_wraps.gd` gives.
extends "res://tests/test_framework.gd"

const STAMP_MODULE := "res://modules/sara-base-modules/stamp-brush/module.gd"


func after_each() -> void:
    SaKeyLabels.os_name_override = ""
    SaKeyLabels.keyboard_override = -1
    SaKeyLabels.keyboard_typed = false


func _tablet(keyboard: bool) -> void:
    SaKeyLabels.os_name_override = "Android"
    SaKeyLabels.keyboard_override = 1 if keyboard else 0


func test_the_edit_menu_draws_no_key_on_a_tablet_without_a_keyboard() -> void:
    _tablet(false)
    var bar := _bound_bar()
    var hints := _hints(bar.menus["Edit"])
    assert_true(hints.size() > 5, "the Edit menu has its rows, %d of them" % hints.size())
    for row: String in hints:
        assert_eq(hints[row], "", "row %s draws no key" % row)
    bar.free()


func test_the_edit_menu_draws_its_keys_with_a_keyboard_attached() -> void:
    _tablet(true)
    var bar := _bound_bar()
    var hints := _hints(bar.menus["Edit"])
    assert_eq(hints.get(String(SaMenu.key(SaEditMenu.ID_UNDO)), ""), "Ctrl+Z", "Undo draws its chord")
    assert_eq(hints.get(String(SaMenu.key(SaEditMenu.ID_REDO)), ""), "Ctrl+Shift+Z", "and Redo")
    bar.free()


func test_the_desktop_is_asked_nothing() -> void:
    SaKeyLabels.os_name_override = "Linux"
    SaKeyLabels.keyboard_override = 0
    assert_true(SaKeyLabels.shown(), "a desktop names its keys whatever the keyboard figure says")
    var bar := _bound_bar()
    var hints := _hints(bar.menus["Edit"])
    assert_eq(hints.get(String(SaMenu.key(SaEditMenu.ID_UNDO)), ""), "Ctrl+Z", "and Undo draws its chord")
    bar.free()


func test_the_erase_toggle_s_tooltip_names_no_key_on_a_tablet_without_a_keyboard() -> void:
    _tablet(false)
    var label := _shown_tooltip(_erase_tooltip())
    assert_eq(label.text, "Erase with the brush", "the tooltip is the sentence alone")
    label.free()


func test_the_erase_toggle_s_tooltip_names_its_key_with_a_keyboard_attached() -> void:
    _tablet(true)
    var label := _shown_tooltip(_erase_tooltip())
    assert_eq(label.text, "Erase with the brush (E)", "the tooltip ends in its key, as on the desktop")
    label.free()


## A parenthesis that is no chord the input map answers stays, so a word in
## brackets is never taken for a key.
func test_only_a_bound_chord_is_taken_out() -> void:
    _tablet(false)
    assert_eq(SaKeyLabels.without_keys("Lightness (Oklab)"), "Lightness (Oklab)", "a word in brackets stays")
    assert_eq(SaKeyLabels.without_keys("Swap the two colours (X)"), "Swap the two colours", "a bound key goes")
    assert_eq(SaKeyLabels.without_keys("Brush (B). Paints."), "Brush. Paints.", "and the sentence after it stays")


func _erase_tooltip() -> String:
    var stamp: Script = load(STAMP_MODULE)
    for spec: SaOptionSpec in stamp.brush_options():
        if spec.key == &"eraser_toggled":
            return spec.tooltip
    return ""


## A label built as the engine builds a tooltip's, entering the tree.
func _shown_tooltip(text: String) -> Label:
    SaTooltip.install(Engine.get_main_loop() as SceneTree)
    var label := Label.new()
    label.theme_type_variation = &"TooltipLabel"
    label.text = text
    EventBus.add_child(label)
    return label


func _bound_bar() -> TopMenuBar:
    var bar := TopMenuBar.new()
    bar._ready()
    bar.bind_commands(SaTestFixtures.make_menu_registries().commands)
    return bar


func _hints(popup: SaChoicePopup) -> Dictionary:
    var out := {}
    for entry: Dictionary in popup.row_report():
        out[String(entry.get("id", ""))] = String(entry.get("hint", ""))
    return out
