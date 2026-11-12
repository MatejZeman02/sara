## A pane title of the Welcome window stands clear of the border
## of the `Panes` panel by the margin the window keeps round its panes.
##
## Before it, the News and Tips panes opened on a title that sat on the panel's
## border, because the panel's box keeps no margin of its own. The window is
## built and never added to a tree, for the reason `test_welcome_window.gd`
## gives, so its tab container is moved under a plain `Control` on `EventBus`
## and sized, and the rectangles are read from there.
extends "res://tests/test_framework.gd"

const HOST_SIZE := Vector2(640, 420)


## The panel's content rectangle in the tab container's own space: the tab bar
## is above it and the box's margin is inside it.
func _content_rect(tabs: TabContainer) -> Rect2:
    var box := tabs.get_theme_stylebox("panel")
    var top := tabs.get_tab_bar().size.y
    var inset_x := box.content_margin_left + box.content_margin_right
    var inset_y := top + box.content_margin_top + box.content_margin_bottom
    return Rect2(Vector2(box.content_margin_left, top + box.content_margin_top), tabs.size - Vector2(inset_x, inset_y))


func _title_rect(tabs: TabContainer, tab: int, title_name: String) -> Rect2:
    tabs.current_tab = tab
    var title := tabs.get_child(tab).find_child(title_name, true, false) as Control
    assert_not_null(title, "%s is found on tab %d" % [title_name, tab])
    return Rect2(title.global_position - tabs.global_position, title.size)


func test_the_news_and_tips_titles_stand_the_windows_margin_inside_the_panel() -> void:
    var window := SaWelcomeWindow.new()
    var host := Control.new()
    host.name = "B6PanesHost"
    EventBus.add_child(host)
    window.tabs.get_parent().remove_child(window.tabs)
    host.add_child(window.tabs)
    window.tabs.position = Vector2.ZERO
    window.tabs.size = HOST_SIZE
    var pad := float(SaUI.px(SaTheme.PAD))

    var content := _content_rect(window.tabs)
    assert_true(content.position.x >= pad, "the panel's content starts at least the window's margin in from its left border")
    assert_true(content.position.y - window.tabs.get_tab_bar().size.y >= pad, "and from the top of the panel")

    for case: Array in [[1, "PaneTitle"], [2, "TipTitle"]]:
        var rect := _title_rect(window.tabs, case[0], case[1])
        assert_true(rect.position.x >= content.position.x, "%s starts at or past the content's left edge" % case[1])
        assert_true(rect.position.y >= content.position.y, "%s starts at or past the content's top edge" % case[1])
        assert_true(rect.position.x >= pad, "%s is at least the window's margin from the panel's left" % case[1])
        var below_bar := rect.position.y - window.tabs.get_tab_bar().size.y
        assert_true(below_bar >= pad, "%s is at least the window's margin below the tab bar" % case[1])

    host.free()
    window.free()


## Only this window's panel took the margin: the table's box stays the engine's.
func test_another_tab_container_keeps_the_themes_box() -> void:
    var other := TabContainer.new()
    var window := SaWelcomeWindow.new()
    assert_true(
        window.tabs.get_theme_stylebox("panel").content_margin_left > other.get_theme_stylebox("panel").content_margin_left,
        "the Welcome window's panel has more margin than a tab container left to the theme"
    )
    other.free()
    window.free()
