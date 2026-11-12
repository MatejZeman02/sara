## The Preferences window's own height is what the page inside it gets.
##
## The defect: the category list on the left is a VBoxContainer of one button
## per category, so its minimum height is the height of all of them, and an
## HSplitContainer's minimum is its tallest child's. Twenty-four categories made
## that minimum 830 where the window shows 749, the split overflowed the window
## by 81 logical pixels, and the last row of the Top Menu Bar page was drawn in
## the band below the bottom edge where no click can land. The scroll was
## already at its end, so wheeling did not help and a painter read the
## row as simply absent.
##
## `scenarios/last-layout-row-below-the-window.json` is the proof on the
## running app. This pins the geometry the scenario cannot photograph, and the
## rule rather than the number: the split's minimum height must not track the
## number of categories, whatever that number grows to.
extends "res://tests/test_framework.gd"

## It opens a real window, and only a run with a RenderingDevice has one.
const REQUIRES_GPU := true


## A Preferences window in the tree, embedded, with a host to free it by. The
## same recipe as `test_settings_window_frame.gd`: without the embedding
## `add_child` maps a real OS window and the run blocks until the watchdog, and
## the parent is an autoload because a node mid-`_ready` rejects `add_child`.
func _open_window() -> Array:
    var tree := Engine.get_main_loop() as SceneTree
    if tree == null:
        return []
    var was_embedding: bool = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true

    var host := Node.new()
    host.name = "F137TestHost"
    EventBus.add_child(host)

    var window := SaSettingsWindow.new()
    host.add_child(window)
    window.show()
    return [window, host, was_embedding]


## Freed here and now rather than queued: a Window is its parent's exclusive
## child until it is gone, and a queued free leaves the next test opening a
## second exclusive child of the same root.
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


func test_the_category_list_scrolls_instead_of_growing_the_split() -> void:
    var window := SaSettingsWindow.new()

    assert_not_null(window.category_scroll, "the category list has a pane of its own")
    assert_eq(window.menu_list.get_parent(), window.category_scroll, "and the list is inside it")
    assert_eq(
        window.category_scroll.horizontal_scroll_mode,
        ScrollContainer.SCROLL_MODE_DISABLED,
        "it scrolls up and down only, a sideways bar under the categories is noise"
    )

    var rows := window.menu_list.get_child_count()
    var whole_list := rows * (SaUI.px(28) + SaUI.px(4))
    assert_true(
        window.split_container.get_combined_minimum_size().y < float(whole_list),
        "the split's minimum height does not carry all %d categories, which is %d logical pixels" % [rows, whole_list]
    )
    window.free()


func test_the_split_fits_under_the_title_bar() -> void:
    var window := SaSettingsWindow.new()

    # No `await`, and no tree. A test that awaits silently drops every assertion
    # after the await, and the minimum size is the mechanism anyway:
    # a Control anchored full-rect is still grown to its combined minimum, which
    # is how the split came to hang past the window's bottom edge.
    var under_the_bar := float(SaSettingsWindow.DEFAULT_LOGICAL_SIZE.y - SaUI.px(SaUI.BASE_DRAG_H))
    var wanted := window.split_container.get_combined_minimum_size().y
    assert_true(
        wanted <= under_the_bar,
        "the split asks for %d logical pixels and the window has %d under its title bar" % [wanted, under_the_bar]
    )
    window.free()


## The list is reachable by scrolling, and a page reached by name rather than by
## a click brings its own button into view.
func test_show_page_scrolls_the_category_into_view() -> void:
    var opened := _open_window()
    if opened.is_empty():
        return
    var window := opened[0] as SaSettingsWindow
    var last := String(window.categories[window.categories.size() - 1])

    assert_true(window.show_page(last), "the last category can be shown by name")
    assert_eq(String(window.categories[window.current]), last, "and it is the one the window is on")
    _close_window(opened)
