## A right click on an element of the top bar opens a menu that
## hides it, and its Show row brings it back, with Hide absent on Edit.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The right press is handed to the bar's arranger the way the root
## window hands it on, at the middle of the control, and the rows are sorted by
## hand where the engine would sort them a frame later, since a suite that
## awaits drops what it asserts after the await. The running app's proof is
## `scenarios/the-top-bar-is-arranged-on-the-bar-itself-a-right-click-to-hide-an-element-and-a-held-drag-to-move-it.json`.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## The bar's controls come from the tools' descriptors, which need a machine,
## a surface and therefore a device.
const REQUIRES_GPU := true

## The tool control hidden and shown, one the brush's row always holds.
const CONTROL := "Keep Blend Mode"

static var scratch_profile: String = SaDataRoot.path("test_right_click.cfg")

var _saved_path: String = ""
var _surface: SaSurface = null
var _machine: ToolMachine = null
var _host: Control = null
var _kept_embedding: bool = true


func before_each() -> void:
    _saved_path = SaSettings.settings_path
    SaSettings.settings_path = ProjectSettings.globalize_path(scratch_profile)
    _remove_profile()
    SaSettings.load_settings()


func after_each() -> void:
    if _host != null:
        _host.free()
        _host = null
        (Engine.get_main_loop() as SceneTree).root.gui_embed_subwindows = _kept_embedding
    _remove_profile()
    SaSettings.settings_path = _saved_path
    SaSettings.load_settings()
    Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null


func _remove_profile() -> void:
    for suffix: String in ["", ".bak", ".broken"]:
        var path := ProjectSettings.globalize_path(scratch_profile) + suffix
        if FileAccess.file_exists(path):
            DirAccess.remove_absolute(path)


## A fresh profile's bar with the brush's controls, in the root's tree.
static func bar_in_tree(test: Object) -> TopMenuBar:
    var bar := TopMenuBar.new()
    var options := ToolOptionsBar.new()
    options.target_tool_machine = test.get("_machine")
    options._ready()
    bar.add_tool_options(options)
    bar._ready()
    bar.set_anchor(SIDE_RIGHT, 0.0)
    var host := Control.new()
    host.name = "U99BarHost"
    host.size = Vector2(2560, 400)
    EventBus.add_child(host)
    host.add_child(bar)
    bar.size.x = 2560.0
    bar.apply_layout_settings()
    lay_out(bar)
    test.set("_host", host)
    return bar


## The bar sorted, as the engine would a frame on.
static func lay_out(bar: TopMenuBar) -> void:
    bar.offset_bottom = bar.get_combined_minimum_size().y
    var rows := bar.rows
    var boxes: Array[Container] = [
        bar,
        rows,
        rows.main_row,
        bar.menu_bar.get_parent() as Container,
        bar.menu_bar,
        rows.row_container(1),
        rows.second_row,
        rows.second_options_row
    ]
    for box: Container in boxes:
        box.notification(Container.NOTIFICATION_SORT_CHILDREN)


## A press of *button* at the middle of *control*, with Ctrl held when *ctrl*.
static func press_on(bar: TopMenuBar, control: Control, button: MouseButton, ctrl: bool = false) -> void:
    var press := InputEventMouseButton.new()
    press.button_index = button
    press.pressed = true
    press.ctrl_pressed = ctrl
    press.position = control.get_global_rect().get_center()
    bar.arrange._input(press)


func _make() -> TopMenuBar:
    _surface = Fixtures.make_surface()
    _machine = Fixtures.make_bound_machine(_surface)
    var root := (Engine.get_main_loop() as SceneTree).root
    _kept_embedding = root.gui_embed_subwindows
    root.gui_embed_subwindows = true
    return bar_in_tree(self)


func test_the_right_click_menu_hides_a_tool_control_and_show_brings_it_back() -> void:
    var bar := _make()
    var arrange := bar.arrange
    var control := arrange.control_of(CONTROL)
    assert_not_null(control, "The brush's row has %s" % CONTROL)
    assert_true(control.is_visible_in_tree(), "and it shows on a fresh bar")
    press_on(bar, control, MOUSE_BUTTON_RIGHT)
    assert_eq(arrange.menu.row_ids(), [&"hide", &"move", &"show", &"arrange"], "The menu offers Hide, Move, Show and Arrange")
    assert_false(arrange.hidden_elements().has(CONTROL), "and it is not among the hidden ones")
    assert_true(arrange.menu.press_row(&"hide"), "Hide is pressed")
    assert_false(SaSettings.get_element_visible("TopMenuBar", CONTROL), "The setting has it hidden")
    assert_false(control.visible, "and the bar no longer shows it")
    assert_true(arrange.hidden_elements().has(CONTROL), "and it is among the hidden elements")

    var menu_title: Button = bar.menu_buttons["View"]
    press_on(bar, menu_title, MOUSE_BUTTON_RIGHT)
    assert_false(arrange.menu.is_disabled(&"show"), "Show is on with an element hidden")
    arrange.menu._on_branched(&"show")
    assert_true(arrange.menu.show_list.row_ids().has(StringName(CONTROL)), "and its list holds the hidden control")
    assert_true(arrange.menu.show_list.press_row(StringName(CONTROL)), "which is pressed")
    assert_true(SaSettings.get_element_visible("TopMenuBar", CONTROL), "The setting shows it again")
    assert_true(control.visible, "and so does the bar")
    press_on(bar, menu_title, MOUSE_BUTTON_RIGHT)
    assert_false(arrange.menu.show_list.row_ids().has(StringName(CONTROL)), "and Show no longer lists it")


func test_hide_is_absent_on_edit() -> void:
    var bar := _make()
    press_on(bar, bar.menu_buttons["Edit"], MOUSE_BUTTON_RIGHT)
    assert_false(bar.arrange.menu.row_ids().has(&"hide"), "Edit's menu has no Hide")
    assert_true(bar.arrange.menu.row_ids().has(&"move"), "and Edit still moves")
    SaTopBarArrange.ElementMenu.set_shown("Edit", false)
    assert_true(SaSettings.get_element_visible("TopMenuBar", "Edit"), "and nothing hides it")


func test_a_plain_left_press_is_left_to_the_control() -> void:
    var bar := _make()
    press_on(bar, bar.arrange.control_of(CONTROL), MOUSE_BUTTON_LEFT)
    assert_eq(bar.arrange._armed, "", "A press without Ctrl arms nothing")
    assert_eq(bar.arrange.lifted, "", "and lifts nothing")


## Arrange's request goes out deferred on the bus, so the page it names is
## handed to Preferences here the way `MainDialogs.open_preferences` hands it,
## and lands on the top bar's element list.
func test_arrange_opens_the_elements_page_of_the_top_bar() -> void:
    _make()
    var page := SaSettingsWindow.internal_title_for(SaTopBarArrange.CATEGORY)
    var window := SaSettingsWindow.new()
    _host.add_child(window)
    window.toggle(page, &"")
    var content := window.content_container
    assert_true(content.get_child(content.get_child_count() - 1) is SaTopBarPage, "Arrange opens the top bar's elements")
    window.hide()
