## The search window's draw-ahead never runs in the frame a
## menu opened in.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The hidden list once drew the empty query's rows, 31 to
## 33 ms, in the frame Image, Layer or View opened in. Here the list closes on
## a typed query, which wants the empty query's rows drawn again, a menu of the
## bar opens before a frame has passed, and while it is up and on the frame
## after it went no row is drawn. Then the list idles, the rows come in over
## frames with the measuring on a frame after the last row, and Search
## Commands opens on the rows drawn ahead rather than drawing them.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

var _registries: SaRegistries = null
var _host: Node = null
var _bar: TopMenuBar = null
var _window: SaSearchWindow = null
var _was_embedding := false


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _was_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "U700SearchHost"
    EventBus.add_child(_host)
    EventBus.move_child(_host, 0)
    _registries = Fixtures.make_menu_registries()
    _bar = TopMenuBar.new()
    _host.add_child(_bar)
    _bar.bind_commands(_registries.commands)
    _window = SaSearchWindow.new(SaSearchIndex.new(_registries.context), _bar)
    _host.add_child(_window)


func after_each() -> void:
    _host.free()
    _host = null
    _window = null
    _bar = null
    _registries = null
    (Engine.get_main_loop() as SceneTree).root.gui_embed_subwindows = _was_embedding


## A menu up holds the draw-ahead, and so does the frame after it went, then
## the idle list draws the rows and an opening keeps them.
func test_a_menu_s_frame_draws_no_rows_and_the_idle_list_has_them_made() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _window.open()
    _window.filter("zzzz")
    var typed := _window.row_ids()
    _window.hide()
    assert_true(_window.drawn_stale(), "A close on a typed query leaves the empty query's rows to be drawn")
    var menu := _a_menu()
    assert_true(menu != null, "The bar has a menu to open")
    if menu == null:
        return
    menu.show()
    assert_true(SaSearchDrawAhead.menu_up(_window), "and the open menu is seen as up")
    for frame in 4:
        await tree.process_frame
        assert_false(_window.draw_ahead.is_drawing(), "Frame %d with the menu up starts no draw-ahead" % frame)
        assert_eq(_window.row_ids(), typed, "and draws no row in frame %d" % frame)
    menu.hide()
    await tree.process_frame
    assert_eq(_window.row_ids(), typed, "The frame after the menu went draws no row either")

    var frames := 0
    var measured_after_rows := false
    while _window.drawn_stale() and frames < 200:
        await tree.process_frame
        frames += 1
        var page := mini(SaSearchWindow.PAGE, _window.shown.size())
        if _window._drawn >= page and _window.drawn_stale():
            measured_after_rows = true
    assert_false(_window.drawn_stale(), "The idle list draws the empty query's rows, in %d frames" % frames)
    assert_true(measured_after_rows, "and measures them on a frame after the last row")
    assert_false(_window.draw_ahead.is_drawing(), "and the draw-ahead is over")
    var first := _window.row_of(_window.row_ids()[0])

    _window.open()
    assert_true(_window.row_of(_window.row_ids()[0]) == first, "Search Commands opens on the rows drawn ahead, not drawn anew")
    assert_eq(_window._drawn, mini(SaSearchWindow.PAGE, _window.shown.size()), "with the first page drawn")


## An opening while a page is half drawn draws its own whole and the half is
## dropped.
func test_an_opening_over_a_half_drawn_page_draws_its_own() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _window.open()
    _window.filter("zzzz")
    _window.hide()
    _window.draw_ahead.want()
    var frames := 0
    while not _window.draw_ahead.is_drawing() and frames < 50:
        await tree.process_frame
        frames += 1
    assert_true(_window.draw_ahead.is_drawing(), "The idle list starts a page")
    _window.open()
    assert_false(_window.draw_ahead.is_drawing(), "An opening drops the half page")
    assert_false(_window.drawn_stale(), "and shows the empty query's rows drawn whole")
    assert_eq(_window._drawn, mini(SaSearchWindow.PAGE, _window.shown.size()), "a page of them")


func _a_menu() -> Window:
    for menu_name: String in _bar.menus:
        var menu := _bar.menus[menu_name] as Window
        if menu != null:
            return menu
    return null
