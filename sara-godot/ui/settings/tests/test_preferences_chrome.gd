## Preferences takes a margin and its groups' headings.
##
## Two things about one window's chrome. The list is divided by a heading over
## each of its three groups of ten pages, the way a section's heading is drawn
## over its rows on a page. The page column keeps a gutter from the window's
## edges, since 10 logical units at this width reads as none.
##
## **The walkers read `category_buttons`, not the list's children.** The list
## holds a heading per group among its buttons, so an index into it is no index
## into `categories`. This suite counts the buttons against the categories and
## reads each heading's place in the list above its group's first button.
extends "res://tests/test_framework.gd"

## The window goes into the tree, because `visibility_changed` is not emitted
## off it and the headings answer the search. Only a run with a RenderingDevice
## has a tree with a root to embed into.
const REQUIRES_GPU := true

## A word only the Files page carries, in the rows a painter saves by. It
## leaves the last group showing with nothing above it, which is the state a
## heading must draw no gap in.
const ONLY_IN_THE_LAST_GROUP := "autosave"

## Two shipped palettes whose muted text differs, Sara Green and Krita Grey,
## the pair the palette tests use.
const FIRST := "default"
const SECOND := "krita"


## A Preferences window in the tree, embedded, with a host to free it by.
##
## Copied from `test_preferences_search.gd`, including both of its reasons:
## without the embedding `add_child` maps a real OS window and the run blocks
## until the watchdog, and the parent is an autoload because a node mid-`_ready`
## rejects `add_child` and leaves the child orphaned.
func _open_window() -> Array:
    var tree := Engine.get_main_loop() as SceneTree
    if tree == null:
        return []
    var was_embedding: bool = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true

    var host := Node.new()
    host.name = "PreferencesChromeTestHost"
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
    var host := opened[1] as Node
    host.free()
    var tree := Engine.get_main_loop() as SceneTree
    if tree != null:
        tree.root.gui_embed_subwindows = bool(opened[2])


## The heading of the group the button at *at* belongs to.
func _heading_of(window: SaSettingsWindow, at: int) -> Label:
    return window.group_headings.get(window.category_groups[at]) as Label


func test_a_heading_sits_over_each_group() -> void:
    var opened := _open_window()
    if opened.is_empty():
        return
    var window := opened[0] as SaSettingsWindow

    assert_eq(window.category_buttons.size(), window.categories.size(), "one button per category")
    assert_eq(
        window.menu_list.get_child_count(),
        window.categories.size() + window.group_headings.size(),
        "and a heading per group beside them, nothing else"
    )
    assert_eq(window.group_headings.keys(), SaUIRegistry.SETTINGS_GROUPS, "the three groups in the order the door lists them")
    for i in window.categories.size():
        var first := i == 0 or window.category_groups[i - 1] != window.category_groups[i]
        if not first:
            continue
        var heading := _heading_of(window, i)
        assert_eq(
            heading.get_index(),
            window.category_buttons[i].get_index() - 1,
            "'%s' sits straight above '%s', the first of its group" % [heading.text, window.categories[i]]
        )
        assert_eq(heading.mouse_filter, Control.MOUSE_FILTER_IGNORE, "and is never pressed")
    assert_eq(
        String(window.categories[0]), SaSettingsWindow.INTERFACE_PAGE, "Interface opens the list and the window opens on it"
    )
    _close_window(opened)


func test_each_heading_after_the_first_opens_a_gap_wider_than_a_button_gap() -> void:
    var opened := _open_window()
    if opened.is_empty():
        return
    var window := opened[0] as SaSettingsWindow

    var first := true
    for group: StringName in window.group_headings:
        var heading := window.group_headings[group]
        var gap := 0 if first else SaUI.px(SaSettingsWindow.GROUP_GAP)
        assert_eq(
            int(heading.custom_minimum_size.y),
            SaUI.px(SaSettingsWindow.BUTTON_HEIGHT) + gap,
            "'%s' is a button tall%s" % [heading.text, "" if first else ", and a gap more"]
        )
        first = false
    assert_true(
        SaSettingsWindow.GROUP_GAP > SaSettingsWindow.LIST_SEPARATION * 2,
        "and the gap is more than two button gaps, which is what makes it read as a division"
    )
    _close_window(opened)


func test_a_filtered_list_draws_no_heading_over_nothing() -> void:
    var opened := _open_window()
    if opened.is_empty():
        return
    var window := opened[0] as SaSettingsWindow
    for heading: Label in window.group_headings.values():
        assert_true(heading.visible, "'%s' shows while the whole list does" % heading.text)

    window.search.apply(ONLY_IN_THE_LAST_GROUP)
    var last := window.group_headings[SaUIRegistry.SETTINGS_GROUPS[-1]]
    assert_true(last.visible, "'%s' is a word a page of the last group carries" % ONLY_IN_THE_LAST_GROUP)
    for i in window.categories.size():
        var heading := _heading_of(window, i)
        if window.category_buttons[i].visible:
            assert_true(heading.visible, "'%s' heads '%s', which the search left" % [heading.text, window.categories[i]])
    for group: StringName in window.group_headings:
        var heading := window.group_headings[group]
        if group != SaUIRegistry.SETTINGS_GROUPS[-1]:
            assert_false(heading.visible, "'%s' goes with the last of its buttons" % heading.text)
    assert_eq(
        int(last.custom_minimum_size.y),
        SaUI.px(SaSettingsWindow.BUTTON_HEIGHT),
        "and the first heading in view keeps no gap, so the filtered list has no hole at its top"
    )

    window.search.apply("")
    for heading: Label in window.group_headings.values():
        assert_true(heading.visible, "clearing the search puts '%s' back" % heading.text)
    _close_window(opened)


## A colour copied off the
## palette keeps the palette it was copied from. A heading's colour is bound to
## the palette, so a switch with the list built repaints it.
func test_the_headings_follow_a_palette_switch() -> void:
    var was := SaTheme.palette_id
    SaTheme.use_named(FIRST)
    var opened := _open_window()
    if opened.is_empty():
        SaTheme.use_named(was)
        return
    var window := opened[0] as SaSettingsWindow
    var heading := window.group_headings[SaUIRegistry.SETTINGS_GROUPS[0]]
    var before := heading.get_theme_color("font_color")
    assert_eq(before, SaTheme.palette.text_muted, "the heading is the muted text on %s" % FIRST)

    SaTheme.use_named(SECOND)
    assert_eq(heading.get_theme_color("font_color"), SaTheme.palette.text_muted, "and on %s after the switch" % SECOND)
    assert_true(heading.get_theme_color("font_color") != before, "which moved, so the two are not one colour")
    _close_window(opened)
    SaTheme.use_named(was)


func test_the_page_column_keeps_a_gutter_from_the_window_edge() -> void:
    var opened := _open_window()
    if opened.is_empty():
        return
    var window := opened[0] as SaSettingsWindow

    var margin := window.content_scroll.get_child(0) as MarginContainer
    assert_not_null(margin, "the page column sits in a MarginContainer")
    for side: String in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
        assert_eq(
            margin.get_theme_constant(side),
            SaUI.px(SaSettingsWindow.CONTENT_MARGIN),
            "the gutter is the same on %s as on every other side" % side
        )
    assert_true(
        SaSettingsWindow.CONTENT_MARGIN > window.content_container.get_theme_constant("separation"),
        "and it is wider than the gap the column keeps between two of its own rows, which is what reads as a gutter"
    )
    _close_window(opened)
