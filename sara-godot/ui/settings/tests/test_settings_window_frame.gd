## The Preferences window's own chrome: the size it opens at, and what the
## maximize and minimize buttons do to it.
##
## Preferences opens bigger on re-appear and carries both buttons. A scenario proves the buttons on the running app, and
## this pins the geometry, which a screenshot can only show one value of.
extends "res://tests/test_framework.gd"

## It opens a real window, and only a run with a RenderingDevice has one.
const REQUIRES_GPU := true

## What the window opened at at first: too short for the category list, which
## ran out of room at Minimap, and for a page that opened already scrolled.
const OLD_LOGICAL_SIZE := Vector2i(720, 520)


## A Preferences window in the tree, embedded, with a host to free it by.
##
## Embedding is forced, exactly as `test_windows_open.gd` forces it: without it
## `add_child` maps a real OS window and the run blocks until the watchdog. And
## the parent is an autoload rather than the root, because a node that is itself
## mid-`_ready` rejects `add_child` and leaves the child orphaned.
func _open_window() -> Array:
    var tree := Engine.get_main_loop() as SceneTree
    if tree == null:
        return []
    var was_embedding: bool = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true

    var host := Node.new()
    host.name = "SettingsFrameTestHost"
    EventBus.add_child(host)

    var window := SaSettingsWindow.new()
    host.add_child(window)
    window.show()
    return [window, host, was_embedding]


## Freed here and now rather than queued: a Window is its parent's exclusive
## child until it is gone, and a queued free leaves the next test opening a
## second exclusive child of the same root, which the engine refuses out loud.
func _close_window(opened: Array) -> void:
    if opened.is_empty():
        return
    var window := opened[0] as Window
    if is_instance_valid(window):
        window.hide()
    var host := opened[1] as Node
    host.free()
    var tree := Engine.get_main_loop() as SceneTree
    if tree != null:
        tree.root.gui_embed_subwindows = bool(opened[2])


func test_it_opens_big_enough_for_the_list_and_a_page() -> void:
    var window := SaSettingsWindow.new()
    assert_true(
        (
            SaSettingsWindow.DEFAULT_LOGICAL_SIZE.x > OLD_LOGICAL_SIZE.x
            and SaSettingsWindow.DEFAULT_LOGICAL_SIZE.y > OLD_LOGICAL_SIZE.y
        ),
        "Preferences opens bigger than the 720 by 520 it once opened at"
    )
    assert_eq(window.logical_size, SaSettingsWindow.DEFAULT_LOGICAL_SIZE, "and the dialog is built at that size")

    # The list has scrolled inside its own pane, so a window shorter
    # than it no longer clips the last entries. The size is still checked
    # against the whole list, because a Preferences that opens with a scrollbar
    # already showing is the state the frame exists to avoid.
    var rows := window.menu_list.get_child_count()
    var list_height := rows * (SaUI.px(28) + SaUI.px(4)) + 2 * SaUI.px(8)
    assert_true(
        SaSettingsWindow.DEFAULT_LOGICAL_SIZE.y >= list_height + SaUI.px(SaUI.BASE_DRAG_H),
        "all %d categories fit under the title bar, not just the first few" % rows
    )
    window.free()


func test_the_title_bar_carries_both_buttons_left_of_close() -> void:
    var opened := _open_window()
    if opened.is_empty():
        return
    var window := opened[0] as SaSettingsWindow

    assert_not_null(window.frame.minimize_button, "Preferences has a minimize button")
    assert_not_null(window.frame.maximize_button, "and a maximize button")
    var row := window.close_button.get_parent()
    assert_eq(
        [
            row.get_children().find(window.frame.minimize_button),
            row.get_children().find(window.frame.maximize_button),
            row.get_children().find(window.close_button)
        ],
        [row.get_child_count() - 3, row.get_child_count() - 2, row.get_child_count() - 1],
        "minimize, maximize, close, the order GNOME and Windows both draw"
    )
    _close_window(opened)


func test_maximize_fills_the_host_and_comes_back() -> void:
    var opened := _open_window()
    if opened.is_empty():
        return
    var window := opened[0] as SaSettingsWindow
    var before := window.size

    window.frame.toggle_maximized()
    assert_true(SaDockerMaximise.is_maximised(window), "the button maximizes")
    assert_eq(window.size, SaDockerMaximise.host_rect(window).size, "and the window fills the host the chord fills")
    assert_eq(window.position, SaDockerMaximise.host_rect(window).position, "from the host's own origin")

    window.frame.toggle_maximized()
    assert_false(SaDockerMaximise.is_maximised(window), "pressing it again restores")
    assert_eq(window.size, before, "to the size it had")
    _close_window(opened)


## Minimize rolls the window up to its title bar. A taskbar minimize is not
## available to it: an embedded subwindow's `get_window_id()` is the host's, so
## the mode would take the whole of Sara down with it.
func test_minimize_rolls_the_window_up_and_back() -> void:
    var opened := _open_window()
    if opened.is_empty():
        return
    var window := opened[0] as SaSettingsWindow
    var before := window.size

    window.frame.toggle_collapsed()
    assert_eq(window.frame.mode, SaSettingsFrame.Mode.COLLAPSED, "the button rolls it up")
    assert_eq(window.size.y, window.frame.bar_height(), "to the title bar's own height")
    assert_eq(window.size.x, before.x, "keeping its width")
    assert_false(window.content.visible, "with the page hidden rather than squashed")
    assert_false(window.resizer.visible, "and nothing to drag by the corner")

    window.frame.toggle_collapsed()
    assert_eq(window.size, before, "pressing it again gives the window back")
    assert_true(window.content.visible, "with its page")
    _close_window(opened)


## The remembered rectangle is taken on the way out of normal only, so the two
## buttons in either order still land on the size the person had.
func test_a_rolled_up_maximized_window_restores_to_neither() -> void:
    var opened := _open_window()
    if opened.is_empty():
        return
    var window := opened[0] as SaSettingsWindow
    var before := window.size

    window.frame.toggle_maximized()
    window.frame.toggle_collapsed()
    assert_eq(window.size.y, window.frame.bar_height(), "rolled up while maximized")
    window.frame.toggle_collapsed()
    assert_eq(window.size, before, "and back to the size before either button")
    _close_window(opened)


func test_it_comes_back_as_a_window_after_being_rolled_up() -> void:
    var opened := _open_window()
    if opened.is_empty():
        return
    var window := opened[0] as SaSettingsWindow

    window.frame.toggle_collapsed()
    window.hide()
    window.show()
    assert_eq(window.frame.mode, SaSettingsFrame.Mode.NORMAL, "reopening gives a window, not a title bar")
    assert_true(window.content.visible, "with its page in it")
    _close_window(opened)


## A scale change re-derives the geometry from the logical size, which is
## neither mode's geometry, so both modes end with it rather than going stale.
func test_a_scale_change_ends_both_modes() -> void:
    var opened := _open_window()
    if opened.is_empty():
        return
    var window := opened[0] as SaSettingsWindow

    window.frame.toggle_collapsed()
    window.apply_window_scale()
    assert_eq(window.frame.mode, SaSettingsFrame.Mode.NORMAL, "a rolled-up window is a window again")
    assert_true(window.content.visible, "showing its page")

    window.frame.toggle_maximized()
    window.apply_window_scale()
    assert_false(SaDockerMaximise.is_maximised(window), "and a maximized one is back to normal")
    _close_window(opened)


## The default is chosen for a page rather than for a screen, so it comes down
## to whatever it actually opens in.
func test_the_window_is_fitted_to_a_host_that_is_smaller() -> void:
    var opened := _open_window()
    if opened.is_empty():
        return
    var window := opened[0] as SaSettingsWindow
    var host := window.frame.host_rect()
    if host.size.x <= 0 or host.size.y <= 0:
        _close_window(opened)
        return
    var margin := SaSettingsFrame.HOST_MARGIN
    assert_true(window.size.x <= host.size.x - margin or window.size.x == window.min_size.x, "it fits across")
    assert_true(window.size.y <= host.size.y - margin or window.size.y == window.min_size.y, "and down")
    _close_window(opened)


## Ctrl+comma is a toggle, so the same chord that opens Preferences
## closes it. The chord reaches this through `MainDialogs.open_preferences`,
## which asks the window, so the decision is pinned here.
func test_the_chord_closes_preferences_as_well_as_opening_it() -> void:
    var window := SaSettingsWindow.new()
    assert_false(window.is_open(), "A window nobody has opened is not open")

    var opened := _open_window()
    if opened.is_empty():
        window.free()
        return
    var live := opened[0] as SaSettingsWindow
    assert_true(live.is_open(), "Showing it opens it")
    live.toggle()
    assert_false(live.is_open(), "and the chord closes it again")
    live.toggle()
    assert_true(live.is_open(), "and opens it a second time")

    _close_window(opened)
    window.free()


## A window rolled up to its title bar is open, not closed. That state is
## a smaller Preferences, so a chord that read it as closed would open a
## window already on screen.
func test_a_rolled_up_window_counts_as_open() -> void:
    var opened := _open_window()
    if opened.is_empty():
        return
    var window := opened[0] as SaSettingsWindow
    window.frame.set_mode(SaSettingsFrame.Mode.COLLAPSED)
    assert_eq(window.frame.mode, SaSettingsFrame.Mode.COLLAPSED, "Rolled up")
    assert_true(window.is_open(), "and still open")
    window.toggle()
    assert_false(window.is_open(), "The chord closes it from there rather than reopening it")

    _close_window(opened)


## A page named in the request always opens, whatever the window was doing.
## Help > Keyboard Shortcuts asks for a page, not for a flip.
func test_a_request_that_names_a_page_never_closes() -> void:
    var opened := _open_window()
    if opened.is_empty():
        return
    var window := opened[0] as SaSettingsWindow
    window.toggle("Keyboard shortcuts")
    assert_true(window.is_open(), "Asking for a page on an open window leaves it open")
    window.toggle()
    window.toggle("Keyboard shortcuts")
    assert_true(window.is_open(), "and opens a closed one")

    _close_window(opened)
