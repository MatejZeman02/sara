## A choice on the bar reads its value whole or moves to the
## overflow.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The stabiliser's mode read "Aver…" at 1920 by 1080 in Full, and the
## preset "P…" and the blend mode "Normal (…" at 1280 by 1024 at a font size of
## 1.3 in Default, each clipping its text. The bar has every
## button on its rows ask for its whole text, and the cut sends one that has no
## room for it to the overflow.
##
## The bar hangs from a `Node` in a viewport the size of the window, the way it
## hangs from `Main`. Everything is asked in one frame,
## since a test that awaits drops every assertion after the await, so
## the containers are sorted by hand where the engine would sort them a frame
## later. The running app's proof at both sizes is
## `scenarios/a-choice-on-the-bar-reads-its-value-whole-or-moves-to-the-overflow.json`.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## The bar's controls come from the tools' descriptors, which need a device.
const REQUIRES_GPU := true

const FULL := Vector2i(1920, 1080)
const DEFAULT := Vector2i(1280, 1024)

## The scratch profile, absent before each test, so the bar is a fresh one.
static var scratch_profile: String = SaDataRoot.path("test_d103_choice_whole_profile.cfg")

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
    _window.name = "D103Window"
    _window.gui_embed_subwindows = true
    _window.render_target_update_mode = SubViewport.UPDATE_DISABLED
    EventBus.add_child(_window)
    _main = Node.new()
    _main.name = "D103Main"
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


## The reading of one size: every drop-down left on a row at least as
## wide as its text, each row inside its budget, and what was cut in the
## overflow and on no row.
func _every_choice_is_whole(bar: TopMenuBar, dropdowns: Array[String]) -> void:
    var rows := bar.rows
    var seen: Array[String] = []
    for row: int in [1, 2]:
        var container := rows.row_container(row)
        assert_true(
            rows.row_spent(row) <= rows.row_budget(row) + 0.5,
            "Row %d spends %.0f of %.0f" % [row, rows.row_spent(row), rows.row_budget(row)]
        )
        for button in _buttons(container):
            seen.append(String(button.name))
            assert_false(button.clip_text, "%s on row %d asks for its whole text" % [button.name, row])
            assert_true(
                button.size.x >= _text_width(button),
                (
                    '%s on row %d is %.0f wide for "%s", %.0f of text'
                    % [button.name, row, button.size.x, button.text, _text_width(button)]
                )
            )
    var held: Array[String] = []
    for node in rows.overflow.box.get_children():
        held.append(String(node.name))
        for button in _buttons(node, true):
            held.append(String(button.name))
    for named in dropdowns:
        assert_true(
            seen.has(named) or held.has(named), "%s is on a row or in the overflow, rows %s, list %s" % [named, seen, held]
        )
        assert_false(seen.has(named) and held.has(named), "but %s is not in both" % named)


func test_at_1920_by_1080_in_full_the_stabilisers_mode_reads_whole() -> void:
    _take_full()
    var bar := _bar(FULL)
    var mode := bar.rows.elements().get("stabilizer_mode") as SaChoiceButton
    assert_not_null(mode, "Full shows the stabiliser's mode on the bar")
    assert_true(_text_width(mode) > 0.0, "reading %s" % mode.text)
    _every_choice_is_whole(bar, ["StabilizerModeOpt", "BlendModeOpt", "PresetMenu"])
    assert_true(bar.rows.second_options_row.is_ancestor_of(mode), "and it is on the second row, which has room for it")


func test_at_1280_by_1024_at_a_font_size_of_1_3_the_preset_and_the_blend_mode_read_whole() -> void:
    _font_scale(1.3)
    var bar := _bar(DEFAULT)
    _every_choice_is_whole(bar, ["BlendModeOpt", "PresetMenu"])
    var preset := bar.rows.elements().get("Brush Presets") as Control
    assert_not_null(preset, "The bar has its preset group")
    var held := bar.rows.overflow.box.is_ancestor_of(preset)
    assert_true(held or bar.rows.second_options_row.is_ancestor_of(preset), "which is on the second row or in the list")


## A row with less than a drop-down's text sends it to the overflow rather than
## cutting it: the same bar in a window too narrow for the preset and the blend
## mode beside the controls that stay last.
func test_a_row_too_short_for_a_choice_sends_it_to_the_overflow() -> void:
    _font_scale(1.3)
    var bar := _bar(Vector2i(560, 1024))
    _every_choice_is_whole(bar, ["BlendModeOpt", "PresetMenu"])
    assert_true(
        bar.rows.overflow.held().size() > 0, "The list holds what the row had no room for, %s" % [bar.rows.overflow.held()]
    )


## In a docker a drop-down clips as it did, since the bar's rule is the bar's.
func test_a_choice_off_the_bar_still_clips() -> void:
    var choice := SaMake.choice(null, "D103Choice")
    assert_true(choice.clip_text, "A drop-down built for a docker clips its text")
    choice.free()
