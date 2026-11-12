## A slider's readout follows the Font size preference in a docker and on the
## top bar.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Slider readouts were drawn at 10 pixels in every docker and
## dialog, next to 20 point labels, and ignored the Font size preference. The
## ten was the top bar's, whose first row had to fit 1920, and it stays
## there. The bar's Size and Opacity were its
## smallest controls, drawn at full size only in the overflow's list, and a
## short row now gives up its rarely used controls rather than shrinking these.
## Everywhere the text is the theme font's size, and the box grows to hold it.
##
## The docker is embedded, the way `test_a_docker_is_held_above_the_main_window.gd`
## embeds its own, because a docker that maps an OS window hangs a headless run.
@tool
extends "res://tests/test_framework.gd"

const SCALES: Array[float] = [1.0, 1.5]


class StubDocker:
    extends DockerWindow

    ## The column a real docker builds: its drag bar first, then its rows,
    ## inside the window's own Control.
    func _init() -> void:
        _init_docker("SliderDocker", "Stub", Vector2i(300, 200))
        var column := VBoxContainer.new()
        column.name = "Column"
        _control_node.add_child(column)
        drag_handle = PanelContainer.new()
        column.add_child(drag_handle)


var _host: Node = null
var _kept_embedding: bool = true
var _kept_font_scale: float = 1.0


func before_each() -> void:
    var root := (Engine.get_main_loop() as SceneTree).root
    _kept_embedding = root.gui_embed_subwindows
    root.gui_embed_subwindows = true
    _kept_font_scale = SaUI.user_font_scale
    _host = Node.new()
    _host.name = "SliderHost"
    EventBus.add_child(_host)


func after_each() -> void:
    if _host != null:
        _host.free()
        _host = null
    _font_scale(_kept_font_scale)
    (Engine.get_main_loop() as SceneTree).root.gui_embed_subwindows = _kept_embedding


## Moves the preference the way `SaSettingsApply` announces it, so a docker
## runs its own theme pass as it does in the app.
func _font_scale(font_scale: float) -> void:
    SaUI.user_font_scale = font_scale
    SaUI.refresh_font_sizes()
    EventBus.ui_font_scale_changed.emit(font_scale)


func _slider(named: String) -> FactorSlider:
    var slider := FactorSlider.new()
    slider.name = named
    slider.prefix = "Opacity: "
    slider.suffix = "%"
    slider.decimal_places = 0
    slider.max_value = 100.0
    slider.value = 50.0
    return slider


func test_a_docker_slider_follows_the_font_size() -> void:
    var docker := StubDocker.new()
    _host.add_child(docker)
    var slider := _slider("DockerSlider")
    var column := docker.content_column()
    assert_not_null(column, "The docker has its content column")
    if column == null:
        return
    column.add_child(slider)
    var sizes: Array[int] = []
    var heights: Array[float] = []
    for font_scale: float in SCALES:
        _font_scale(font_scale)
        assert_eq(slider.text_size(), SaUI.get_font_size(), "At %s the readout is the theme font's size" % font_scale)
        assert_true(
            slider.get_combined_minimum_size().y >= slider.text_height(), "and the box is tall enough for it at %s" % font_scale
        )
        sizes.append(slider.text_size())
        heights.append(slider.get_combined_minimum_size().y)
    assert_true(sizes[1] > sizes[0], "A larger Font size draws the readout larger, got %s" % [sizes])
    assert_true(heights[1] > heights[0], "and the box grows with it, got %s" % [heights])
    assert_true(sizes[0] > 10, "and it is no longer the top bar's old ten")


func test_the_top_bar_follows_the_font_size_too() -> void:
    var bar := TopMenuBar.new()
    _host.add_child(bar)
    var slider := _slider("BarSlider")
    bar.add_child(slider)
    var sizes: Array[int] = []
    for font_scale: float in SCALES:
        _font_scale(font_scale)
        slider.text_width()
        assert_eq(slider.text_size(), SaUI.get_font_size(), "At %s the top bar's readout is the theme font's size" % font_scale)
        sizes.append(slider.text_size())
    assert_true(sizes[1] > sizes[0], "and a larger Font size draws it larger, got %s" % [sizes])


## The bar builds and measures its sliders before it hangs in the tree, and a
## slider measured under the bar there is at the theme font's size as well.
func test_a_slider_built_off_the_tree_is_at_the_theme_size_under_the_bar() -> void:
    var bar := TopMenuBar.new()
    var slider := _slider("DetachedSlider")
    assert_eq(slider.text_size(), SaUI.get_font_size(), "Alone, a slider is at the theme font's size")
    bar.add_child(slider)
    slider.text_width()
    assert_eq(slider.text_size(), SaUI.get_font_size(), "and under the bar, measured, at the same size")
    bar.free()
