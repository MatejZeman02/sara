## A search for a docker just made finds its line.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A `prefs_search` for "Mine" just after Make must not leave the
## pane at its top rather than at Mine's line. The search's index was built at
## the search before, for Fork, and kept, so it had no Mine: Layouts and dockers
## left the list, "Nothing matches" covered the page, and the line the mark
## found stood in a pane that was hidden and never scrolled.
##
## A docker of your own is a layout category like any docker, and its line is
## drawn by the page's own `redraw`, which is what Make has the page do. So the
## suite registers a category with a word no page carries, has the open page
## draw it, and searches for the word. The page stays, the line is marked, and
## the pane's scroll puts the line inside it.
##
## The search scrolls two frames after it marks, for the reason
## `SaSettingsSearch._scroll_to` gives, and a suite cannot await a frame. So the
## suite does what those frames do: it lays the window out by hand, sorting
## every container, and then scrolls the pane to the marked line as
## `_scroll_to` does, and reads the scroll and where the line then stands. The scenario
## `a-search-for-a-docker-just-made-finds-its-line.json` reads the app's own
## scroll in the running app.
extends "res://tests/test_framework.gd"

## It opens a real window, and only a run with a RenderingDevice has one.
const REQUIRES_GPU := true

## A docker's category no page has a line for, past any id a library hands out.
const LINED := "composed_9443"

## Its title, a word no page carries, so a match is this line's.
const TITLE := "Zanzibar"

## The page the line is on.
const PAGE := SaDockersPage.TITLE


func after_each() -> void:
    SaSettings.unregister_layout_category(LINED)


## A Preferences window in the tree, embedded, with a host to free it by, the
## way `test_preferences_search.gd` opens one and for its two reasons.
func _open_window() -> Array:
    var tree := Engine.get_main_loop() as SceneTree
    if tree == null:
        return []
    var was_embedding: bool = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    var host := Node.new()
    host.name = "SearchTestHost"
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


## Layouts and dockers open, a search for Fork made so the index is built, and
## then the docker registered and its line drawn on the open page, the order
## a scenario takes. The page on screen, or null.
func _line_drawn_after_the_index(window: SaSettingsWindow) -> SaDockersPage:
    assert_true(window.show_page(PAGE), "Layouts and dockers opens")
    window.search.apply("fork")
    assert_true(window.search.index.has(PAGE), "the search for Fork built the index")
    assert_false(_carries(window.search.index[PAGE], TITLE), "and its entry has no %s, which is not drawn yet" % TITLE)
    SaSettings.register_layout_category(LINED, TITLE, ["Drag Handle", "Resizer"])
    var page := window.content_container.get_node_or_null(NodePath(String(SaSettingsPage.NODE_NAME))) as SaDockersPage
    assert_not_null(page, "Layouts and dockers is the page on screen")
    if page != null:
        page.redraw()
    assert_not_null(_line(window), "the page drew the new line")
    return page


func _line(window: SaSettingsWindow) -> Control:
    return SaSettingsSearch.row_line(window.content_scroll, SaDockersPage.line_key(LINED))


func _carries(words: PackedStringArray, word: String) -> bool:
    for one: String in words:
        if SaSettingsSearch.matches(one, word.to_lower()):
            return true
    return false


## Every container under *node* sorted now, four times over, because a label
## that wraps knows its height only once its width is set, and two passes left
## the page still 1,600 units from where the third and fourth put it.
func _lay_out(node: Node) -> void:
    for _pass in 4:
        _sort_under(node)


func _sort_under(node: Node) -> void:
    if node is Container:
        (node as Container).notification(Container.NOTIFICATION_SORT_CHILDREN)
    for child: Node in node.get_children():
        _sort_under(child)


## Where *line*'s top stands below the pane's top, in the pane's own units.
func _below_pane_top(window: SaSettingsWindow, line: Control) -> float:
    return line.global_position.y - window.content_scroll.global_position.y


func test_a_line_drawn_after_the_index_is_found_marked_and_scrolled_to() -> void:
    var opened := _open_window()
    if opened.is_empty():
        return
    var window := opened[0] as SaSettingsWindow
    _line_drawn_after_the_index(window)
    var line := _line(window)

    window.search.apply(TITLE)
    var report: Dictionary = window.search.report()
    assert_true(PackedStringArray(report["categories"]).has(PAGE), "the search keeps Layouts and dockers in the list")
    assert_false(window.nothing_matches.visible, "and puts no Nothing matches over the page")
    assert_true(window.content_container.visible, "so the page stays on screen")
    assert_eq(window.search.highlighted, line, "The mark is on the new line")
    assert_eq(String(report["highlighted_row"]), TITLE, "which the report names")

    _lay_out(window)
    var pane := window.content_scroll.size.y
    var before := _below_pane_top(window, line)
    assert_true(before > pane, "The line starts below the fold, %d under a pane %d tall" % [before, pane])
    window.content_scroll.ensure_control_visible(line)
    var scrolled := window.content_scroll.scroll_vertical
    # The pane moves what it holds when it sorts, so the scroll is read after one.
    _lay_out(window)
    var after := _below_pane_top(window, line)
    assert_true(scrolled > 0, "The pane scrolls down to it, to %d" % scrolled)
    var inside := after >= 0.0 and after + line.size.y <= pane
    assert_true(inside, "and the whole line is in the pane, its top at %d of %d" % [after, pane])
    assert_true(bool(window.search.report()["highlighted_in_view"]), "which the report says too")

    _close_window(opened)


## The page left after the line was drawn and before any search: the search
## from another page still finds the line, because the page that left is built
## again for the index rather than read from what the Fork search kept.
func test_a_line_drawn_before_the_page_was_left_is_found_from_another_page() -> void:
    var opened := _open_window()
    if opened.is_empty():
        return
    var window := opened[0] as SaSettingsWindow
    _line_drawn_after_the_index(window)
    window.search.apply("")
    assert_true(window.show_page("Performance"), "Performance opens")

    window.search.apply(TITLE)
    var report: Dictionary = window.search.report()
    assert_eq(PackedStringArray(report["categories"]), PackedStringArray([PAGE]), "Layouts and dockers alone carries the word")
    assert_eq(window.search.first_page(), PAGE, "and Enter opens it")
    window.search.field.text_submitted.emit(window.search.field.text)
    assert_eq(window.search.highlighted, _line(window), "where the new line is marked")

    _close_window(opened)


## The other way round: a line the open page took away is no longer found,
## where the Fork search's entry would still have had it.
func test_a_line_taken_away_is_not_found() -> void:
    var opened := _open_window()
    if opened.is_empty():
        return
    var window := opened[0] as SaSettingsWindow
    var page := _line_drawn_after_the_index(window)
    window.search.apply(TITLE)
    assert_true(_carries(window.search.index[PAGE], TITLE), "the search read the line off the page")

    SaSettings.unregister_layout_category(LINED)
    if page != null:
        page.redraw()
    assert_null(_line(window), "the page drew its lines again without it")
    window.search.apply(TITLE)
    assert_true(PackedStringArray(window.search.report()["categories"]).is_empty(), "and the search finds the word nowhere")
    assert_true(window.nothing_matches.visible, "which the page area says")

    _close_window(opened)
