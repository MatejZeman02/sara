## With a menu open, the pointer moving onto another title opens
## that title's menu in its place, without a click.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Krita does it: with Filter open, the pointer on Tools opens Tools, as every
## desktop menu bar does.
## An open list is a focused embedded window, so the titles never see the
## pointer, and the bar listens at the root window's input instead.
##
## **The motion is handed to the root window's `window_input`, which is where
## the engine emits it before forwarding it to the list.** The bar hangs from a
## control in the real root with embedding forced, the way
## `test_a_filter_section_opens_beside_the_filter_menu.gd` stands its bar, so the
## lists are real windows that open and close. Everything is asked in one frame,
## since a test that awaits drops every assertion after the await, so
## the rows are sorted by hand where the engine would sort them a frame later.
## The running app's proof is `scenarios/an-open-menu-gives-way-to-the-title-the-pointer-moves-onto.json`.
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


## The bar in the root's tree with its commands, laid out across a host the size
## of the window, whose width is the room the titles have. Not `tree.root`
## itself, which is mid-`_ready` when a suite runs.
func _make_bar() -> TopMenuBar:
    var registries := SaTestFixtures.make_menu_registries()
    _host = Control.new()
    _host.name = "D6BarHost"
    _host.size = Vector2((Engine.get_main_loop() as SceneTree).root.size)
    EventBus.add_child(_host)
    _bar = TopMenuBar.new()
    _host.add_child(_bar)
    _bar.bind_commands(registries.commands)
    _lay_out()
    return _bar


## The bar sorted inside the window, as the engine would a frame on.
func _lay_out() -> void:
    _bar.offset_bottom = _bar.get_combined_minimum_size().y
    for box: Container in [_bar, _bar.rows, _bar.rows.main_row, _bar.menu_bar.get_parent() as Container, _bar.menu_bar]:
        box.notification(Container.NOTIFICATION_SORT_CHILDREN)


## A pointer motion over the middle of *title*, handed to the root window the
## way the engine hands it, in the window's own space.
func _move_onto(title: Control) -> void:
    var root := (Engine.get_main_loop() as SceneTree).root
    var motion := InputEventMouseMotion.new()
    motion.position = root.get_final_transform() * title.get_global_rect().get_center()
    root.window_input.emit(motion)


func _open_names() -> Array:
    var open: Array = []
    for menu_name: String in _bar.menus:
        if (_bar.menus[menu_name] as SaChoicePopup).visible:
            open.append(menu_name)
    return open


func test_with_filter_open_the_pointer_on_tools_opens_tools_and_closes_filter() -> void:
    var bar := _make_bar()
    bar._on_menu_button_pressed("Filter")
    assert_eq(_open_names(), ["Filter"], "Filter is open")

    _move_onto(bar.menu_buttons["Tools"])

    assert_eq(_open_names(), ["Tools"], "Tools is open in its place and Filter is closed")
    var tools: SaChoicePopup = bar.menus["Tools"]
    assert_true(tools.row_ids().size() > 0, "with its rows in it")


func test_with_no_menu_open_the_pointer_on_a_title_opens_nothing() -> void:
    var bar := _make_bar()
    _move_onto(bar.menu_buttons["Tools"])
    assert_eq(_open_names(), [], "No menu opens under a pointer that nothing pressed")
    assert_false(bar.menu_overflow.list.visible, "and nor does the last title's list")


## A menu a press closed is a menu closed, and the pointer that is still on its
## title opens nothing.
func test_after_a_menu_is_closed_the_pointer_on_a_title_opens_nothing() -> void:
    var bar := _make_bar()
    bar._on_menu_button_pressed("Filter")
    bar._on_menu_button_pressed("Filter")
    assert_eq(_open_names(), [], "The second press closed Filter")
    _move_onto(bar.menu_buttons["Filter"])
    assert_eq(_open_names(), [], "and the pointer on its title does not open it again")


## The pointer on the title of the menu that is open is where it already was, and
## it is not the close a press on that title would be.
func test_the_pointer_on_the_open_menus_own_title_leaves_it_open() -> void:
    var bar := _make_bar()
    bar._on_menu_button_pressed("Filter")
    _move_onto(bar.menu_buttons["Filter"])
    _move_onto(bar.menu_buttons["Filter"])
    assert_eq(_open_names(), ["Filter"], "Filter is still open")


## A press is not a motion, so another title pressed is the press's own business.
func test_a_press_handed_to_the_window_is_not_a_hover() -> void:
    var bar := _make_bar()
    bar._on_menu_button_pressed("Filter")
    var root := (Engine.get_main_loop() as SceneTree).root
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    press.position = root.get_final_transform() * (bar.menu_buttons["Tools"] as Button).get_global_rect().get_center()
    root.window_input.emit(press)
    assert_eq(_open_names(), ["Filter"], "The bar leaves the pressing to the title")


## The pointer on a point that is on no title is a pointer on the bar's gap or
## the canvas, and the open menu stays.
func test_the_pointer_off_every_title_leaves_the_open_menu_open() -> void:
    var bar := _make_bar()
    bar._on_menu_button_pressed("Filter")
    var root := (Engine.get_main_loop() as SceneTree).root
    var motion := InputEventMouseMotion.new()
    motion.position = Vector2(root.size.x - 2, root.size.y - 2)
    root.window_input.emit(motion)
    assert_eq(_open_names(), ["Filter"], "Filter stays open")


## The last title, which holds the titles that did not fit, takes the open menu
## the way a title does, and its list opens.
func test_the_pointer_on_the_last_title_opens_its_list_in_the_menus_place() -> void:
    var bar := _make_bar()
    bar.menu_overflow.fit(120.0)
    _lay_out()
    var fold := bar.menu_overflow
    assert_true(fold.visible and fold.folded.size() > 0, "The row folds titles behind the last one: %s" % [fold.folded])
    var title: Button = bar.menu_buttons["File"]
    assert_true(title.visible, "File stays on the row")
    bar._on_menu_button_pressed("File")
    assert_eq(_open_names(), ["File"], "File is open")

    _move_onto(fold)

    assert_true(fold.list.visible, "The last title's list is open")
    assert_eq(_open_names(), [], "and File is closed")

    _move_onto(fold)
    assert_true(fold.list.visible, "The pointer still on that title leaves the list open")

    _move_onto(title)
    assert_false(fold.list.visible, "The pointer back on File closes the list")
    assert_eq(_open_names(), ["File"], "and opens File")


## With no menu open the last title is a title like the rest, and nothing opens.
func test_with_no_menu_open_the_pointer_on_the_last_title_opens_nothing() -> void:
    var bar := _make_bar()
    bar.menu_overflow.fit(120.0)
    _lay_out()
    _move_onto(bar.menu_overflow)
    assert_false(bar.menu_overflow.list.visible, "The list stays shut")
    assert_eq(_open_names(), [], "and no menu opens")


## The bar goes out of the tree and takes its ear off the window with it, so a
## second bar and a freed one never hear the same motion.
func test_a_bar_out_of_the_tree_no_longer_listens() -> void:
    var bar := _make_bar()
    var root := (Engine.get_main_loop() as SceneTree).root
    assert_true(root.window_input.is_connected(bar._on_window_input), "A bar in the tree listens at the root")
    _host.remove_child(bar)
    assert_false(root.window_input.is_connected(bar._on_window_input), "and a bar out of it does not")
    bar.free()
    _bar = null
