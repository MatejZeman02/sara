## The foreground and background pair is large enough to hit with a pen, and
## its marks stand clear of the menus.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The swatches were small and the swap arrow close to the menu
## bar. The pair on the top bar's second row now has each square, the strip of
## the back square that shows, the swap mark and the reset mark at least
## `SaColorPair.TARGET` logical pixels on a side, and the Colour docker, the
## other place the pair is shown, is held to the same number.
##
## **UI scales 1 and 2.** `SaUI.px` is the identity and the window's content
## scale is what doubles a size, so at scale 2 every target is twice the
## physical pixels and the bar sits in a host half as wide in logical pixels. A
## 1920 panel at scale 2 is the 960 wide host below, and the pair must fit and
## keep clear of the menus in both. The bar hangs from a `Node` in a viewport,
## the way `test_every_menu_title_can_be_reached_at_a_host_640_wide.gd` hangs
## it, and everything is asked in one frame.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const SaColorPickerScript = preload("res://ui/dockers/color/sa_color_picker.gd")

## The bar's controls come from the tools' descriptors, which need a device.
const REQUIRES_GPU := true

## A 1920 by 1080 panel in logical pixels at each scale.
const PANEL := Vector2(1920, 1080)

static var scratch_profile: String = SaDataRoot.path("test_colour_pair_profile.cfg")

var _saved_path: String
var _saved_row: bool
var _saved_override: float
var _saved_user: float
var _surface: SaSurface
var _machine: ToolMachine
var _window: SubViewport
var _main: Node


func before_each() -> void:
    _saved_path = SaSettings.settings_path
    _saved_row = SaSettings.second_row
    _saved_override = SaUI.os_scale_override
    _saved_user = SaUI.user_scale
    SaSettings.settings_path = ProjectSettings.globalize_path(scratch_profile)
    _remove_profile()
    SaSettings.load_settings()
    _surface = Fixtures.make_surface()
    _machine = Fixtures.make_bound_machine(_surface)
    _machine.set_active_tool(&"brush")
    _window = SubViewport.new()
    _window.name = "Window"
    _window.gui_embed_subwindows = true
    _window.render_target_update_mode = SubViewport.UPDATE_DISABLED
    EventBus.add_child(_window)
    _main = Node.new()
    _main.name = "Main"
    _window.add_child(_main)


func after_each() -> void:
    _window.free()
    Fixtures.teardown(_surface, _machine)
    _remove_profile()
    SaSettings.settings_path = _saved_path
    SaSettings.load_settings()
    SaSettings.second_row = _saved_row
    SaUI.os_scale_override = _saved_override
    SaUI.user_scale = _saved_user


func _remove_profile() -> void:
    for suffix: String in ["", ".bak", ".broken"]:
        var path := ProjectSettings.globalize_path(scratch_profile) + suffix
        if FileAccess.file_exists(path):
            DirAccess.remove_absolute(path)


## The bar at UI scale *ui_scale*, in a host as wide in logical pixels as the
## panel is at that scale, laid out.
func _bar(ui_scale: float) -> TopMenuBar:
    SaUI.os_scale_override = 1.0
    SaUI.user_scale = ui_scale
    _window.size = Vector2i(PANEL / ui_scale)
    var options := ToolOptionsBar.new()
    options.target_tool_machine = _machine
    options._ready()
    var bar := TopMenuBar.new()
    bar.add_tool_options(options)
    _main.add_child(bar)
    bar.offset_bottom = bar.get_combined_minimum_size().y
    for box: Container in [bar, bar.rows, bar.rows.main_row, bar.rows.second_row]:
        box.notification(Container.NOTIFICATION_SORT_CHILDREN)
    return bar


## *local*, a rectangle in the pair's own coordinates, in the window's.
func _global(pair: SaColorPair, local: Rect2) -> Rect2:
    return Rect2(pair.get_global_transform() * local.position, local.size)


func _pair_is_large_and_clear_at(ui_scale: float) -> void:
    var bar := _bar(ui_scale)
    var pair := bar.rows.color_pair
    assert_true(bar.rows.second_row.visible, "A fresh profile shows the second row the pair is on")
    assert_eq(SaUI.scale(), ui_scale, "The run is at scale %s" % ui_scale)

    var target := float(DockerUtils.px(SaColorPair.TARGET))
    var front := pair.foreground_rect()
    var back := pair.background_rect()
    var strip := Rect2(Vector2(front.end.x, back.position.y), Vector2(back.end.x - front.end.x, back.size.y))
    var marks := {
        "foreground square": front,
        "background square": back,
        "strip of the back square that shows": strip,
        "swap mark": pair.swap_rect(),
        "reset mark": pair.reset_rect(),
    }
    var menus := bar.rows.main_row.get_global_rect()
    for mark: String in marks:
        var rect: Rect2 = marks[mark]
        assert_true(
            rect.size.x >= target and rect.size.y >= target,
            (
                "At scale %s the %s is %s, at least %d on a side, %d physical pixels"
                % [ui_scale, mark, rect.size, SaColorPair.TARGET, int(target * ui_scale)]
            )
        )
        assert_true(Rect2(Vector2.ZERO, pair.size).encloses(rect), "and inside the pair's own box, %s in %s" % [rect, pair.size])
        var placed := _global(pair, rect)
        assert_false(placed.intersects(menus), "and clear of the menu row, %s against %s" % [placed, menus])
        assert_true(
            placed.position.y >= menus.end.y + float(DockerUtils.px(SaColorPair.PAD)),
            "with at least the padding between them, %s under %s" % [placed.position.y, menus.end.y]
        )

    assert_true(pair.swaps_at(pair.swap_rect().get_center()), "The swap mark swaps")
    assert_true(pair.swaps_at(strip.get_center()), "and so does the back square's strip")
    assert_false(pair.swaps_at(front.get_center()), "the front square does nothing")
    assert_true(pair.resets_at(pair.reset_rect().get_center()), "and the reset mark resets")
    assert_false(pair.resets_at(pair.swap_rect().get_center()), "each a target of its own")
    assert_false(pair.swap_rect().intersects(pair.reset_rect()), "with no overlap between the marks")


func test_at_scale_1_each_target_of_the_pair_is_large_and_clear_of_the_menus() -> void:
    _pair_is_large_and_clear_at(1.0)


func test_at_scale_2_each_target_of_the_pair_is_large_and_clear_of_the_menus() -> void:
    _pair_is_large_and_clear_at(2.0)


## A press on each mark asks for its own change, and the bar turns the ask
## into the store's swap and reset.
func test_a_press_on_each_mark_reaches_the_store() -> void:
    var was := [SaColors.foreground, SaColors.background]
    SaColors.foreground = Color.RED
    SaColors.background = Color.BLUE
    var bar := _bar(1.0)
    var pair := bar.rows.color_pair
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    press.position = pair.swap_rect().get_center()
    pair._gui_input(press)
    assert_eq(SaColors.foreground, Color.BLUE, "A press on the swap mark swaps")
    assert_eq(SaColors.background, Color.RED, "both colours")

    var reset := InputEventMouseButton.new()
    reset.button_index = MOUSE_BUTTON_LEFT
    reset.pressed = true
    reset.position = pair.reset_rect().get_center()
    pair._gui_input(reset)
    assert_eq(SaColors.foreground, SaColors.DEFAULT_FOREGROUND, "A press on the reset mark gives black")
    assert_eq(SaColors.background, SaColors.DEFAULT_BACKGROUND, "over white")
    assert_eq(pair.foreground, SaColors.DEFAULT_FOREGROUND, "and the pair shows it")
    SaColors.foreground = was[0]
    SaColors.background = was[1]


## The other place the pair is shown, the Colour docker, gives its swatches
## and its swap and reset buttons the same smallest side.
func test_the_colour_docker_shows_the_pair_at_the_same_size() -> void:
    var picker := SaColorPickerScript.new()
    var host := Control.new()
    host.add_child(picker)
    var target := float(DockerUtils.px(SaColorPair.TARGET))
    for control: Control in [picker.swap_button, picker.reset_button]:
        var least := control.get_combined_minimum_size()
        assert_true(
            least.x >= target and least.y >= target,
            "%s asks for %s, at least %d a side" % [control.name, least, SaColorPair.TARGET]
        )
    var row := picker.foreground_swatch.get_parent() as Control
    assert_true(row.get_combined_minimum_size().y >= target, "The swatches' row is at least %d high" % SaColorPair.TARGET)
    host.free()
