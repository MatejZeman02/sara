## Feather, Border and Colour Range name their value at the text size of every
## other dialog.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Feather and Border carried a
## thin slider with no label, so "5 px" is five pixels of what, and for Border
## outside or inside the edge, and Colour Range's "Fuzziness: 40" looked small
## beside toggles at full size. Gaussian Blur's Radius is the size to match.
##
## The text size was measured first, with a Font size of 1, 1.5 and 2, and the
## three windows drew their sliders at one size at all three: the small text of
## the shots was the slider with nothing in front of the number, not a smaller
## font. So the size is held here as a guard and the label is what changed.
## The running app is
## `scenarios/the-selection-dialogs-name-their-value-at-full-size.json`.
extends "res://tests/test_framework.gd"

const Teardown := preload("res://tests/fixtures/teardown.gd")
const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true

const OWNER := &"sara-base-modules"

const FONT_SCALES: Array[float] = [1.0, 1.5, 2.0]

var _host: Node = null
var _kept_embedding: bool = true
var _kept_font_scale: float = 1.0

var _easel: SaEasel = null
var _canvas: SaCanvas = null
var _registry: SaFilterRegistry = null
var _blur_window: SaFilterDialogWindow = null


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _kept_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _kept_font_scale = SaUI.user_font_scale
    _host = Node.new()
    _host.name = "N104TestHost"
    EventBus.add_child(_host)


func after_each() -> void:
    _font_scale(_kept_font_scale)
    Teardown.free_nodes([_blur_window, _canvas, _easel])
    _blur_window = null
    _canvas = null
    _easel = null
    _registry = null
    if _host != null and is_instance_valid(_host):
        _host.free()
    _host = null
    (Engine.get_main_loop() as SceneTree).root.gui_embed_subwindows = _kept_embedding


## Moves the Font size preference the way `SaSettingsApply` announces it.
func _font_scale(font_scale: float) -> void:
    SaUI.user_font_scale = font_scale
    SaUI.refresh_font_sizes()
    EventBus.ui_font_scale_changed.emit(font_scale)


func _radius_dialog(label: String) -> SaRadiusDialog:
    var dialog := SaRadiusDialog.new()
    _host.add_child(dialog)
    dialog.configure(label, 5)
    return dialog


func _radius_slider(dialog: SaRadiusDialog) -> FactorSlider:
    return dialog.find_child("RadiusSlider", true, false) as FactorSlider


func _colour_range(for_selection: bool) -> SaColorRangeDialog:
    var dialog := SaColorRangeDialog.new()
    _host.add_child(dialog)
    dialog.for_selection = for_selection
    dialog.build_page(Color.RED, 40.0, true, 0)
    return dialog


## Gaussian Blur's Radius, in the one window that serves every filter.
func _blur_slider() -> FactorSlider:
    _easel = Bench.easel(Vector2i(256, 256))
    _canvas = SaCanvas.new()
    _canvas.easel = _easel
    _registry = SaFilterRegistry.new()
    var blur := SaGaussianBlurFilter.new()
    _registry.register(blur, OWNER)
    _easel.compositor.filter_chain.registry = _registry
    _blur_window = SaFilterDialogWindow.new()
    _blur_window.target_canvas = _canvas
    _blur_window.watch(_registry)
    _host.add_child(_blur_window)
    _blur_window.open_filter(SaFilterRegistry.key_for(OWNER, blur))
    return _blur_window.dialog.rows()[0].control as FactorSlider


func test_the_feather_slider_says_what_it_sets() -> void:
    var feather := _radius_dialog("Feather")
    var slider := _radius_slider(feather)
    assert_true(slider.prefix.begins_with("Feather: "), "the slider's text begins 'Feather: ', got '%s'" % slider.prefix)
    assert_eq(slider._label.text, "Feather: 5 px", "so it reads the word, the number and the unit")


func test_the_border_slider_says_what_it_sets() -> void:
    var border := _radius_dialog("Border")
    var slider := _radius_slider(border)
    assert_eq(slider._label.text, "Border: 5 px", "Border reads 'Border: 5 px'")


## One instance serves each of the two menu rows for good, and the radius it was
## given last is the one it reopens at, so the word moves with the title.
func test_one_dialog_retitled_changes_its_word() -> void:
    var dialog := _radius_dialog("Feather")
    dialog.configure("Border", 8)
    assert_eq(_radius_slider(dialog)._label.text, "Border: 8 px", "the slider takes the new word and the new radius")
    assert_eq(dialog.title, "Border", "as the title does")


func test_borders_hint_says_the_band_is_drawn_across_the_edge() -> void:
    var border := _radius_dialog("Border")
    var hint := border.find_child("HintLabel", true, false) as Label
    assert_not_null(hint, "the dialog has a hint line")
    if hint == null:
        return
    assert_true(hint.visible, "and it is shown")
    assert_true(hint.text.contains("across the edge"), "Border's says the band is drawn across the edge: '%s'" % hint.text)
    var both_ways := hint.text.contains("inside it") and hint.text.contains("outside")
    assert_true(both_ways, "and that it reaches inside and outside: '%s'" % hint.text)
    var muted := hint.get_theme_color("font_color")
    assert_eq(muted, SaTheme.palette.text_muted, "in the muted colour every other hint is in")
    assert_eq(hint.autowrap_mode, TextServer.AUTOWRAP_WORD_SMART, "wrapping to the window's width")


func test_feathers_hint_is_not_borders() -> void:
    var dialog := _radius_dialog("Feather")
    var hint := dialog.find_child("HintLabel", true, false) as Label
    var feather_hint := hint.text
    dialog.configure("Border", 5)
    assert_true(hint.text != feather_hint, "Feather's hint and Border's are two sentences")
    dialog.configure("Feather", 5)
    assert_eq(hint.text, feather_hint, "and Feather's comes back when the dialog is asked for Feather")


func test_a_dialog_with_no_hint_of_its_word_hides_the_line() -> void:
    var dialog := _radius_dialog("Radius")
    var hint := dialog.find_child("HintLabel", true, false) as Label
    assert_false(hint.visible, "a word with no hint leaves no empty line")


func test_colour_ranges_slider_says_fuzziness() -> void:
    var dialog := _colour_range(true)
    var slider := dialog._fuzziness_row.control as FactorSlider
    assert_eq(slider._label.text, "Fuzziness: 40", "Colour Range reads 'Fuzziness: 40' inside its slider")


## The measure, held at three Font sizes: the two windows
## draw their slider text at Gaussian Blur's size, and at the theme font's.
func test_the_three_sliders_are_drawn_at_gaussian_blurs_text_size() -> void:
    var blur := _blur_slider()
    var feather := _radius_slider(_radius_dialog("Feather"))
    var border := _radius_slider(_radius_dialog("Border"))
    var selection := _colour_range(true)._fuzziness_row.control as FactorSlider
    var mask := _colour_range(false)._fuzziness_row.control as FactorSlider
    assert_not_null(blur, "Gaussian Blur has a slider to match")
    if blur == null:
        return
    for font_scale: float in FONT_SCALES:
        _font_scale(font_scale)
        var said := "at a Font size of %s" % font_scale
        assert_eq(blur.text_size(), SaUI.get_font_size(), "Gaussian Blur's is the theme font's size %s" % said)
        assert_eq(feather.text_size(), blur.text_size(), "Feather's equals Gaussian Blur's %s" % said)
        assert_eq(border.text_size(), blur.text_size(), "Border's equals Gaussian Blur's %s" % said)
        assert_eq(selection.text_size(), blur.text_size(), "Colour Range's equals Gaussian Blur's %s" % said)
        assert_eq(mask.text_size(), blur.text_size(), "and so does the mask's Colour Range %s" % said)
        assert_eq(feather.text_height(), blur.text_height(), "Feather's box is as tall as Gaussian Blur's %s" % said)
        assert_eq(selection.text_height(), blur.text_height(), "and Colour Range's %s" % said)
