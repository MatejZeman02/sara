## The Manual's page list is at least as wide as its widest title, at interface
## scale 1 and 2 and at a larger font, so no title is cut.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Titles once read "Selections and the ...", "Saving and exporti..." and "Shortcuts
## and Pref..." in a list fixed at 210 logical units. The list now measures
## itself. The width a title needs is worked out here from the list's own font
## and theme rather than read back from the list, so the suite holds what the
## painter reads and not what the list believes: the text, the item's
## separation, which the list splits either side of the text, and the panel's
## margins.
extends "res://tests/test_framework.gd"

const SCALES: Array[float] = [1.0, 2.0]

var _kept_scale: float = 1.0
var _kept_font_scale: float = 1.0
var _kept_embedding: bool = true
var _kept_theme: Theme = null
var _host: Node = null


func before_each() -> void:
    _kept_scale = SaUI.user_scale
    _kept_font_scale = SaUI.user_font_scale
    # The window reads Sara's theme, which a run of the suites has not built, and
    # a font change rewrites that theme and nothing else.
    _kept_theme = SaUI.shared_theme
    SaUI.init_global_theme(null)
    var tree := Engine.get_main_loop() as SceneTree
    _kept_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "N110TestHost"
    EventBus.add_child(_host)


func after_each() -> void:
    SaUI.user_scale = _kept_scale
    _font_scale(_kept_font_scale)
    SaUI.shared_theme = _kept_theme
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = _kept_embedding
    if _host != null and is_instance_valid(_host):
        _host.free()
    _host = null


func test_every_title_fits_at_scale_1_and_2() -> void:
    for scale: float in SCALES:
        SaUI.user_scale = scale
        EventBus.ui_scale_changed.emit(SaUI.scale())
        var window := _open()
        _check_titles(window, "at interface scale %s" % scale)
        window.free()


## A larger font reaches the list through the theme pass, which writes a font
## size onto every control it walks. An open dialog is deliberately left out of
## that pass on a font change (`SaDialogWindow._on_ui_font_scale_changed` says
## why), so the pass is run here the way a window built or rescaled after the
## change gets it. The list hears the new size as a theme change and measures
## itself again.
func test_every_title_fits_after_the_font_grows() -> void:
    var window := _open()
    window.page_list.force_update_list_size()
    var before := window.page_list.get_combined_minimum_size().x
    _font_scale(1.5)
    _check_titles(window, "at font size 150 per cent before the theme pass")
    SaUI.apply_ui_theme(window)
    assert_eq(window.page_list.get_theme_font_size("font_size"), SaUI.get_font_size(), "The pass gave the list the new size")
    _check_titles(window, "at font size 150 per cent")
    assert_true(window.page_list.get_combined_minimum_size().x > before, "and the list grew with the font")
    window.free()


func _open() -> SaManualWindow:
    var window := SaManualWindow.new()
    _host.add_child(window)
    window.show_page(0)
    return window


func _check_titles(window: SaManualWindow, said: String) -> void:
    var list := window.page_list
    assert_eq(list.item_count, window.pages.size(), "The list has a row per page %s" % said)
    list.force_update_list_size()
    var font := list.get_theme_font("font")
    var font_size := list.get_theme_font_size("font_size")
    var padding := list.get_theme_constant("h_separation") + list.get_theme_stylebox("panel").get_minimum_size().x
    var width := list.get_combined_minimum_size().x
    for row: int in list.item_count:
        var title := list.get_item_text(row)
        var needed := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + padding
        assert_true(width >= needed, "%s needs %.0f and the list is %.0f wide %s" % [title, needed, width, said])


## Moves the Font size preference the way `SaSettingsApply` announces it.
func _font_scale(font_scale: float) -> void:
    SaUI.user_font_scale = font_scale
    SaUI.refresh_font_sizes()
    EventBus.ui_font_scale_changed.emit(font_scale)
