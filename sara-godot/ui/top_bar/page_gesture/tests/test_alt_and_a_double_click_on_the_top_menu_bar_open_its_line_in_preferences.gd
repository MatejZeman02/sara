## ALT and a double click on the top bar open its line in Preferences, the
## gesture a docker's drag handle answers.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The bar stands in the real root with embedding forced, so its menus are real
## windows that open and close. The request is deferred and a suite that awaits drops every
## assertion after the await, so the gesture's answer is read where
## it is decided and the request itself is the scenario's to show, at
## `scenarios/alt-and-a-double-click-on-the-top-menu-bar-open-its-line-in-preferences.json`.
extends "res://tests/test_framework.gd"

## Real windows go in the tree.
const REQUIRES_GPU := true

var _host: Control = null
var _was_embedding: bool = false
var _bar: TopMenuBar = null


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _was_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true


func after_each() -> void:
    if _host != null:
        _host.free()
    _host = null
    _bar = null
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = _was_embedding


func _make_bar() -> TopMenuBar:
    var registries := SaTestFixtures.make_menu_registries()
    _host = Control.new()
    _host.name = "U249BarHost"
    _host.size = Vector2((Engine.get_main_loop() as SceneTree).root.size)
    EventBus.add_child(_host)
    _bar = TopMenuBar.new()
    _host.add_child(_bar)
    _bar.bind_commands(registries.commands)
    _bar.offset_bottom = _bar.get_combined_minimum_size().y
    for box: Container in [_bar, _bar.rows, _bar.rows.main_row, _bar.menu_bar.get_parent() as Container, _bar.menu_bar]:
        box.notification(Container.NOTIFICATION_SORT_CHILDREN)
    return _bar


func _click(pressed: bool, alt: bool, double_click: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    event.alt_pressed = alt
    event.double_click = double_click
    return event


func _open_names() -> Array:
    var open: Array = []
    for menu_name: String in _bar.menus:
        if (_bar.menus[menu_name] as SaChoicePopup).visible:
            open.append(menu_name)
    return open


## The page and line the bar resolves to are Layouts and dockers and the top
## bar's line there, the ones a docker's handle asks for under the bar's key.
func test_the_bar_resolves_to_its_line_on_layouts_and_dockers() -> void:
    assert_eq(SaTopBarPageGesture.page(), SaDockersPage.TITLE, "The bar's page is Layouts and dockers")
    assert_eq(
        SaTopBarPageGesture.line(),
        SaDockersPage.line_key(SaDockersPage.TOP_BAR),
        "The bar's line is the top bar's line on that page"
    )
    assert_false(String(SaTopBarPageGesture.line()).is_empty(), "The bar has a line to land on")


## On the empty part of the bar the double click's second press is the gesture,
## and the release after it is taken as well.
func test_alt_and_a_double_click_on_the_empty_part_asks_for_the_page() -> void:
    var bar := _make_bar()
    var at := bar.page_gesture.empty_point()
    assert_true(bar.get_global_rect().has_point(at), "The empty point is on the bar")
    assert_false(bar.page_gesture.handle_input(_click(true, true, false), at), "The first press is no gesture")
    assert_false(bar.page_gesture.handle_input(_click(false, true, false), at), "Nor its release")
    assert_true(bar.page_gesture.handle_input(_click(true, true, true), at), "The second press asks for the page")
    assert_true(bar.page_gesture.handle_input(_click(false, true, false), at), "Its release is the gesture's too")


## On a menu title the first click opened the menu, and the gesture closes it
## again as it asks for the page.
func test_alt_and_a_double_click_on_a_title_closes_the_menu_the_first_click_opened() -> void:
    var bar := _make_bar()
    var at := (bar.menu_buttons["File"] as Button).get_global_rect().get_center()
    bar._on_menu_button_pressed("File")
    assert_eq(_open_names(), ["File"], "The first click opened File")
    assert_true(bar.page_gesture.handle_input(_click(true, true, true), at), "The second press asks for the page")
    assert_eq(_open_names(), [], "and closed the menu")


## A plain double click asks for no page and leaves the menu to its title.
func test_a_plain_double_click_on_the_bar_asks_for_no_page() -> void:
    var bar := _make_bar()
    var at := (bar.menu_buttons["Edit"] as Button).get_global_rect().get_center()
    bar._on_menu_button_pressed("Edit")
    assert_false(bar.page_gesture.handle_input(_click(true, false, true), at), "No ALT, no page")
    assert_eq(_open_names(), ["Edit"], "The menu is the title's to close, as before")
    assert_false(
        bar.page_gesture.handle_input(_click(true, false, true), bar.page_gesture.empty_point()), "Nor on the empty part"
    )
    assert_false(bar.page_gesture.handle_input(_click(false, false, false), at), "and no release is taken")


## Below the bar the gesture is the canvas's or a docker's, never the bar's.
func test_the_gesture_off_the_bar_is_not_the_bars() -> void:
    var bar := _make_bar()
    var below := Vector2(bar.get_global_rect().get_center().x, bar.get_global_rect().end.y + 40.0)
    assert_false(bar.page_gesture.handle_input(_click(true, true, true), below), "Off the bar, nothing asked for")
