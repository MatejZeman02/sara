## The About window opens inside a screen 1024 pixels high, and inside one 720
## high, with its buttons in reach.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## On a 1280 by 1024 screen About opened
## at (360, 312), 560 by 748, so its bottom edge was at y 1060 and the GitHub
## link, Copy Details and Close lay below the screen until the window was dragged
## up by its title. Two things were wrong and this holds both.
##
## `SaDialogWindow.fit_opening_size` read the window's size *after* it had written
## the new floor, and a window answers a new `min_size` by growing to it on the
## spot, so it saw no growth and did not take half of it back off the position
## `popup_centered` had given. Every dialog that grows on its first frame opened
## low by half its growth. And no code held a dialog inside its host at all, so a
## host shorter than the dialog left the buttons under the edge whatever the
## position was: About's report is now a scroll view, and the fit gives it the
## height the host has left.
##
## The screen is a `SubViewport` of the size asked for, with subwindows embedded
## in it, because an embedded window measures itself against its host viewport
## and the test root's own size is whatever the runner started with. The layout is
## driven by hand, for the reason `test_a_dialog_opens_to_show_its_own_buttons`
## gives: a test cannot await the frame the app fits on, so every container is
## sorted outside in before the fit reads a wrapping label's height and again
## before the buttons are read.
extends "res://tests/test_framework.gd"

## The two screens the fault was met on, and one so short that the report has to scroll
## whatever font the run draws it in.
const TALL := Vector2i(1280, 1024)
const SHORT := Vector2i(1280, 720)
const TINY := Vector2i(1280, 400)

## A screen with room to spare below the window, so the host clamp has nothing to
## move and the shift the fit makes is the only thing that can.
const ROOMY := Vector2i(1280, 2000)

var _kept_scale: float = 1.0
var _kept_embedding: bool = true
var _host: Node = null


func before_each() -> void:
    _kept_scale = SaUI.user_scale
    SaUI.user_scale = 1.0
    var tree := Engine.get_main_loop() as SceneTree
    _kept_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "AboutFitTestHost"
    EventBus.add_child(_host)


func after_each() -> void:
    SaUI.user_scale = _kept_scale
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = _kept_embedding
    if _host != null and is_instance_valid(_host):
        _host.free()
    _host = null


func test_about_lies_inside_a_screen_1024_high() -> void:
    var window := _opened_in(TALL)
    _assert_inside(window, TALL)
    _assert_buttons_in_reach(window, TALL)
    # The window opens at the height of the whole report, and the scroll asks only for
    # its floor, so the scroll's laid out height is what shows the report whole.
    var report := _scroll_of(window)
    assert_true(
        report.size.y >= _child_minimum(report),
        "The whole report is shown, so its scroll is the %d its text needs and not %d" % [_child_minimum(report), report.size.y]
    )


func test_about_lies_inside_a_screen_720_high() -> void:
    var window := _opened_in(SHORT)
    _assert_inside(window, SHORT)
    _assert_buttons_in_reach(window, SHORT)


func test_about_lies_inside_a_screen_too_short_for_its_report_and_scrolls() -> void:
    var window := _opened_in(TINY)
    _assert_inside(window, TINY)
    _assert_buttons_in_reach(window, TINY)
    var report := _scroll_of(window)
    var asked := report.custom_minimum_size.y
    var text := _child_minimum(report)
    assert_true(
        asked < text,
        "The report is taller than the room, so it scrolls: the scroll asks for %d against %d of text" % [asked, text]
    )
    assert_true(report.size.y < text, "The scroll is laid out shorter than its text, %d against %d" % [report.size.y, text])


## With the fold open the body is the tall part again, and the window still lies
## inside the screen with its buttons in reach, on a screen that holds it and on
## one that does not, where the body scrolls.
func test_about_with_its_fold_open_lies_inside_a_screen_720_high() -> void:
    var window := _opened_in(SHORT, true)
    _assert_inside(window, SHORT)
    _assert_buttons_in_reach(window, SHORT)
    assert_false(window.fold.folded, "The fold is open, so the licences are in the body")


func test_about_with_its_fold_open_scrolls_in_a_screen_too_short_for_it() -> void:
    var window := _opened_in(TINY, true)
    _assert_inside(window, TINY)
    _assert_buttons_in_reach(window, TINY)
    var report := _scroll_of(window)
    assert_true(report.size.y < _child_minimum(report), "The body is taller than the room, so it scrolls")


## A painter who opens the fold on a window that is already up gets the room for
## it where the screen has it: the fold's change asks for a fit a frame later,
## and the fit grows the window and keeps it inside the screen.
func test_opening_the_fold_on_a_window_that_is_up_grows_it_inside_the_screen() -> void:
    var window := _opened_in(TALL)
    var folded_height := window.size.y
    window.fold.folded = false
    _sort_children(window.content)
    window.fit_opening_size()
    _sort_children(window.content)
    assert_true(window.size.y > folded_height, "The window grew from %d to %d for the open fold" % [folded_height, window.size.y])
    _assert_inside(window, TALL)
    _assert_buttons_in_reach(window, TALL)


## The position half on its own: the growth the fit makes is taken off the
## position, so the window is not left where a shorter one was centred. The
## fold is open, because folded About fits the room it opens in and grows by
## nothing.
func test_the_growth_of_the_first_fit_moves_the_window_up() -> void:
    var screen := _screen(ROOMY)
    var window := SaAboutDialog.new()
    window.fold.folded = false
    screen.add_child(window)
    window.refresh()
    window.popup_centered()
    var centred := window.position
    _sort_children(window.content)
    window.fit_opening_size()
    var opened := SaUI.window_size_for(window, Vector2i(560, 400))
    assert_true(window.size.y > opened.y, "The fit grew the window past its opening height")
    assert_true(window.position.y < centred.y, "The window moved up from %d to %d when it grew" % [centred.y, window.position.y])


## A dialog with no scrolling body is never made smaller, and is still kept on
## its host: pushed past the bottom edge it comes back to it.
func test_a_dialog_pushed_past_the_edge_is_brought_back() -> void:
    var screen := _screen(TALL)
    var window := SaAboutDialog.new()
    screen.add_child(window)
    window.refresh()
    window.popup_centered()
    _sort_children(window.content)
    window.position = Vector2i(900, 900)
    window.fit_opening_size()
    assert_true(
        Rect2i(Vector2i.ZERO, TALL).encloses(Rect2i(window.position, window.size)),
        "The window at %s, %s big, lies inside the screen" % [window.position, window.size]
    )


## About in a screen of *size*, opened the way the menu opens it, and fitted,
## with its fold open when *unfolded* says so.
func _opened_in(size: Vector2i, unfolded: bool = false) -> SaAboutDialog:
    var screen := _screen(size)
    var window := SaAboutDialog.new()
    window.fold.folded = not unfolded
    screen.add_child(window)
    window.refresh()
    window.popup_centered()
    _sort_children(window.content)
    window.fit_opening_size()
    _sort_children(window.content)
    return window


func _screen(size: Vector2i) -> SubViewport:
    var screen := SubViewport.new()
    screen.size = size
    screen.gui_embed_subwindows = true
    _host.add_child(screen)
    return screen


func _assert_inside(window: SaAboutDialog, screen: Vector2i) -> void:
    assert_true(window.is_embedded(), "The window is embedded in the test screen, so it is measured against it")
    var rect := Rect2i(window.position, window.size)
    assert_true(Rect2i(Vector2i.ZERO, screen).encloses(rect), "About at %s is not inside a screen of %s" % [rect, screen])


func _assert_buttons_in_reach(window: SaAboutDialog, screen: Vector2i) -> void:
    var frame := Rect2(Vector2.ZERO, Vector2(window.size))
    for button_name: String in ["RepositoryLink", "CopyButton", "CloseButton"]:
        var button := window.content.find_child(button_name, true, false) as BaseButton
        assert_true(button != null, "%s is in About" % button_name)
        if button == null:
            continue
        var rect := button.get_global_rect()
        assert_true(frame.encloses(rect), "%s at %s lies inside the window %s" % [button_name, rect, frame])
        var on_screen := Rect2(Vector2(window.position) + rect.position, rect.size)
        assert_true(
            Rect2(Vector2.ZERO, Vector2(screen)).encloses(on_screen),
            "%s at %s lies inside the screen %s" % [button_name, on_screen, screen]
        )


func _scroll_of(window: SaAboutDialog) -> ScrollContainer:
    assert_true(window.scrolling_body != null, "About declares the scroll its report sits in")
    return window.scrolling_body


func _child_minimum(scroll: ScrollContainer) -> int:
    return ceili((scroll.get_child(0) as Control).get_combined_minimum_size().y)


func _sort_children(node: Node) -> void:
    if node == null:
        return
    for child: Node in node.get_children():
        if child is Container:
            (child as Container).notification(Container.NOTIFICATION_SORT_CHILDREN)
        _sort_children(child)
