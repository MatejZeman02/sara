## The Keyboard shortcuts page opened twice builds its rows once.
##
## Building every row again took 331 to 423 ms on each open, so the window keeps
## the page it built, hidden while another page shows, so a second open shows the same rows
## and builds none. A reset or a change of language still drops it, and the
## next open builds it afresh.
extends "res://tests/test_framework.gd"

## It opens a real window, and only a run with a RenderingDevice has one.
const REQUIRES_GPU := true

const SHORTCUTS := "Keyboard shortcuts"


## A Preferences window in the tree, embedded, the way
## `test_preferences_search.gd` opens one and for its reasons.
func _open_window() -> Array:
    var tree := Engine.get_main_loop() as SceneTree
    if tree == null:
        return []
    var was_embedding: bool = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    var host := Node.new()
    host.name = "ShortcutsBuiltOnceTestHost"
    EventBus.add_child(host)
    var window := SaSettingsWindow.new()
    host.add_child(window)
    window.show()
    return [window, host, was_embedding]


func _close_window(opened: Array) -> void:
    if opened.is_empty():
        return
    var window := opened[0] as Window
    if is_instance_valid(window):
        window.hide()
    (opened[1] as Node).free()
    var tree := Engine.get_main_loop() as SceneTree
    if tree != null:
        tree.root.gui_embed_subwindows = bool(opened[2])


## Every shortcuts row host in the window, shown or kept.
func _row_hosts(window: SaSettingsWindow) -> Array[Node]:
    return window.find_children("*", "SaShortcutGroups", true, false)


func test_the_shortcuts_page_opened_twice_builds_its_rows_once() -> void:
    var opened := _open_window()
    if opened.is_empty():
        return
    var window := opened[0] as SaSettingsWindow
    var made := window.kept_pages.made

    assert_true(window.show_page(SHORTCUTS), "the page opens the first time")
    window.kept_pages.finish_arriving()
    var hosts := _row_hosts(window)
    assert_eq(hosts.size(), 1, "one build of the rows")
    var rows := hosts[0] as SaShortcutGroups
    rows.fill_now()
    var groups := rows.get_child_count()
    assert_true(groups > 0, "the rows were built")
    assert_eq(window.kept_pages.made, made + 1, "the window kept the page it built")

    assert_true(window.show_page(SaSettingsWindow.INTERFACE_PAGE), "another page opens between")
    assert_true(window.show_page(SHORTCUTS), "the page opens the second time")
    assert_eq(window.kept_pages.made, made + 1, "the second open built no page")
    hosts = _row_hosts(window)
    assert_eq(hosts.size(), 1, "still one build of the rows")
    assert_true(hosts[0] == rows, "the rows shown are the ones the first open built")
    assert_eq(rows.get_child_count(), groups, "and none was built again")
    assert_true(rows.is_visible_in_tree(), "they are on screen")
    _close_window(opened)


func test_a_reset_drops_the_kept_page_and_the_next_open_builds_it_afresh() -> void:
    var opened := _open_window()
    if opened.is_empty():
        return
    var window := opened[0] as SaSettingsWindow
    assert_true(window.show_page(SHORTCUTS), "the page opens")
    window.kept_pages.finish_arriving()
    var first := _row_hosts(window)
    assert_eq(first.size(), 1, "one build of the rows")
    var made := window.kept_pages.made

    window.rebuild_current_page()
    window.kept_pages.finish_arriving()
    assert_eq(window.kept_pages.made, made + 1, "the rebuild built the page again")
    var live: Array[Node] = []
    for host: Node in _row_hosts(window):
        if not host.is_queued_for_deletion() and host.is_visible_in_tree():
            live.append(host)
    assert_eq(live.size(), 1, "one set of rows on screen")
    assert_true(live[0] != first[0], "and it is the new one")
    _close_window(opened)
