## The blend chip in Tool Options is as large as the controls
## beside it.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The blend chip must not be drawn smaller than the controls around it. Asking
## for 0.8 of the theme's size gave 12 pixels at the default against the 15 of
## Keep Blend Mode beside it and of the sliders' numbers, while its box was
## already as tall as theirs. It asks for no fraction, and the bar's other drop-down, the stabiliser's mode, is drawn the
## same, so every drop-down on the bar stands at one size. The bar is the one
## main builds, in a viewport 1920 wide at UI scale 1, laid out by hand in one
## frame as the neighbouring suites do, and read in the Default layout and in Full, the
## fullest. The running app's proof is
## `scenarios/the-blend-chip-in-tool-options-is-as-large-as-the-controls-beside-it.json`.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## The bar's controls come from the tools' descriptors, which need a device.
const REQUIRES_GPU := true

const FULL := Vector2i(1920, 1080)
const DEFAULT := Vector2i(1280, 1024)

## The scratch profile, absent before each test, so the bar is a fresh one.
static var scratch_profile: String = SaDataRoot.path("test_blend_chip_profile.cfg")

var _saved_path: String
var _saved_row: bool
var _kept_font_scale: float
var _surface: SaSurface
var _machine: ToolMachine
var _window: SubViewport
var _main: Node


func before_each() -> void:
    _saved_path = SaSettings.settings_path
    _saved_row = SaSettings.second_row
    _kept_font_scale = SaUI.user_font_scale
    SaSettings.settings_path = ProjectSettings.globalize_path(scratch_profile)
    _remove_profile()
    SaSettings.load_settings()
    _surface = Fixtures.make_surface()
    _machine = Fixtures.make_bound_machine(_surface)
    _machine.set_active_tool(&"brush")
    _window = SubViewport.new()
    _window.name = "U787Window"
    _window.gui_embed_subwindows = true
    _window.render_target_update_mode = SubViewport.UPDATE_DISABLED
    EventBus.add_child(_window)
    _main = Node.new()
    _main.name = "U787Main"
    _window.add_child(_main)


func after_each() -> void:
    _window.free()
    Fixtures.teardown(_surface, _machine)
    _font_scale(_kept_font_scale)
    _remove_profile()
    SaSettings.settings_path = _saved_path
    SaSettings.load_settings()
    SaSettings.second_row = _saved_row


func _remove_profile() -> void:
    for suffix: String in ["", ".bak", ".broken"]:
        var path := ProjectSettings.globalize_path(scratch_profile) + suffix
        if FileAccess.file_exists(path):
            DirAccess.remove_absolute(path)


func _font_scale(font_scale: float) -> void:
    SaUI.user_font_scale = font_scale
    SaUI.refresh_font_sizes()
    EventBus.ui_font_scale_changed.emit(font_scale)


## The bar's order and switches of the shipped Full layout, which is what a
## load of it writes into the profile.
func _take_full() -> void:
    var cfg := ConfigFile.new()
    assert_eq(cfg.load("res://layouts/full.cfg"), OK, "Full's layout reads")
    SaSettings.set_layout_order("TopMenuBar", cfg.get_value("_layout_order_", "TopMenuBar"))
    for key: String in cfg.get_section_keys("_layout_visibility_"):
        if key.begins_with("TopMenuBar/"):
            SaSettings.set_element_visible(
                "TopMenuBar", key.trim_prefix("TopMenuBar/"), cfg.get_value("_layout_visibility_", key)
            )


## A bar the way main builds it, across the top of a window *host* large, with
## the theme pass main runs at a change of the font size, and laid out.
func _bar(host: Vector2i) -> TopMenuBar:
    _window.size = host
    var options := ToolOptionsBar.new()
    options.target_tool_machine = _machine
    options._ready()
    var bar := TopMenuBar.new()
    bar.add_tool_options(options)
    _main.add_child(bar)
    var note_mode := SaNoteMode.new()
    bar.add_child(note_mode)
    bar.bind_commands(Fixtures.make_menu_registries(note_mode).commands)
    DockerUtils.apply_ui_theme(bar)
    bar.rows.refit()
    bar.offset_bottom = bar.get_combined_minimum_size().y
    _sort(bar)
    return bar


## Every container under *node* sorted, from the top down, so each control has
## the width its row gives it. A list is a window of its own and left alone.
func _sort(node: Node) -> void:
    if node is Container:
        node.notification(Container.NOTIFICATION_SORT_CHILDREN)
    for child in node.get_children():
        if not child is Window:
            _sort(child)


## The buttons with text under *node*, a list's rows left out. Only the ones on
## screen unless *closed*, which reads the overflow's list while it is shut.
func _buttons(node: Node, closed: bool = false, out: Array[Button] = []) -> Array[Button]:
    if node is Button and not (node as Button).text.is_empty() and (closed or (node as Control).is_visible_in_tree()):
        out.append(node as Button)
    for child in node.get_children():
        if not child is Window:
            _buttons(child, closed, out)
    return out


## The width *button*'s text takes in its own font and size.
func _text_width(button: Button) -> float:
    var font := button.get_theme_font(&"font")
    return font.get_string_size(button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, button.get_theme_font_size(&"font_size")).x


## The text and the drawn box of *control* against *other*'s, after the bar's
## layout. The minimum each asks for is not compared, because a toggle's style
## has thinner margins than a drop-down's and the row draws both at its height.
func _level_with(control: Control, other: Control, what: String) -> void:
    assert_eq(
        control.get_theme_font_size(&"font_size"),
        other.get_theme_font_size(&"font_size"),
        "The blend chip's text is the size of %s's" % what
    )
    assert_eq(control.size.y, other.size.y, "and is drawn as tall as %s" % what)


## Every button left on a row reads its whole text, each row spends no more
## than its budget, and each of *on_a_row* stands on a row rather than in the
## overflow.
func _nothing_clipped(bar: TopMenuBar, on_a_row: Array[String]) -> void:
    var rows := bar.rows
    var seen: Array[String] = []
    for row: int in [1, 2]:
        assert_true(
            rows.row_spent(row) <= rows.row_budget(row) + 0.5,
            "Row %d spends %.0f of %.0f" % [row, rows.row_spent(row), rows.row_budget(row)]
        )
        for button in _buttons(rows.row_container(row)):
            seen.append(String(button.name))
            assert_true(
                button.size.x >= _text_width(button),
                '%s on row %d is %.0f wide for "%s"' % [button.name, row, button.size.x, button.text]
            )
    for named: String in on_a_row:
        assert_true(seen.has(named), "%s stands on a row, %s" % [named, seen])


func _chip(bar: TopMenuBar) -> BlendModeButton:
    var chip := bar.rows.elements().get(String(ToolOptionsBar.BLEND_KEY)) as BlendModeButton
    if chip == null:
        chip = bar.find_child("BlendModeOpt", true, false) as BlendModeButton
    assert_not_null(chip, "The bar has the blend chip")
    return chip


func test_at_1920_in_default_the_chip_is_level_with_keep_and_the_sliders() -> void:
    var bar := _bar(FULL)
    var chip := _chip(bar)
    assert_eq(chip.get_theme_font_size(&"font_size"), SaUI.get_font_size(), "The chip is drawn at the theme's size")
    _level_with(chip, bar.find_child("KeepBlendChk", true, false) as Control, "Keep Blend Mode")
    var opacity := bar.find_child("OpacitySlider", true, false) as Control
    assert_not_null(opacity, "The brush's bar has its opacity slider")
    assert_eq(
        chip.get_theme_font_size(&"font_size"),
        opacity.get_theme_font_size(&"font_size"),
        "and at the size the opacity slider writes its number"
    )
    assert_eq(chip.size.y, opacity.size.y, "and as tall as the slider's slot")
    _nothing_clipped(bar, ["BlendModeOpt", "KeepBlendChk"])
    assert_eq(bar.rows.overflow.held().size(), 0, "and the overflow holds nothing, %s" % [bar.rows.overflow.held()])


## Full fills the second row past 1920 and sent Keep Blend Mode, the rotation's
## reset, the mirrors, Undo and Redo to the overflow before the chip grew, and
## sends the same six after, since the chip's floor of `MIN_WIDTH` already held
## its label at the theme's size.
func test_at_1920_in_full_every_drop_down_on_the_bar_is_the_chip_s_size() -> void:
    _take_full()
    var bar := _bar(FULL)
    var chip := _chip(bar)
    var mode := bar.rows.elements().get("stabilizer_mode") as SaChoiceButton
    assert_not_null(mode, "Full shows the stabiliser's mode on the bar")
    _level_with(chip, mode, "the stabiliser's mode")
    _nothing_clipped(bar, ["BlendModeOpt", "StabilizerModeOpt"])
