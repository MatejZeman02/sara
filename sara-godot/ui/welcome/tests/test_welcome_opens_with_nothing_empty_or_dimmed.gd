## Welcome opens with nothing empty or dimmed. An empty Recent
## pane says what fills it and carries one "Recent", the tab's, rather than a
## second heading under it. The scale slider on Quick settings shows its value
## the way the Workspace page does. A tab that is not the chosen one is drawn in
## the body's text colour, app-wide, because a dimmed control reads as disabled.
##
## The panes are built and never added to a tree, the reason
## `test_welcome_window.gd` gives, and driven the way `test_quick_settings_pane.gd`
## drives them.
extends "res://tests/test_framework.gd"

var _saved_recent: Array = []
var _saved_scale: float = 1.0


func before_each() -> void:
    _saved_scale = SaSettings.ui_scale
    _saved_recent = SaSettings.recent_files()
    for path: String in _saved_recent:
        SaSettings.remove_recent_file(str(path))


func after_each() -> void:
    SaSettings.ui_scale = _saved_scale
    for i in range(_saved_recent.size() - 1, -1, -1):
        SaSettings.add_recent_file(str(_saved_recent[i]))


func _texts(root: Node) -> Array[String]:
    var found: Array[String] = []
    for node in root.find_children("*", "Label", true, false):
        found.append((node as Label).text)
    return found


func test_an_empty_recent_pane_says_what_fills_it() -> void:
    var pane := WelcomeRecentPane.new()
    var grid := pane.find_child("RecentCards", true, false) as WelcomeRecentGrid
    assert_not_null(grid, "the pane holds its grid of cards")
    if grid != null:
        assert_eq(grid.cards.size(), 0, "a profile with nothing recent draws no card")
        assert_true(grid.empty_line.visible, "and shows the empty line in their place")
        var hint := grid.empty_line.find_child("RecentEmptyHint", true, false) as Label
        assert_true(hint != null and hint.text.contains("open or save"), "which says what fills the list")
        assert_false(grid.is_ancestor_of(grid.empty_line), "beside the cards rather than in a cell of theirs")
    assert_eq(_texts(pane).count("Recent"), 0, "the pane repeats no 'Recent' of its own, the tab's name is the one")
    pane.free()


func test_the_empty_line_goes_when_a_document_is_recent() -> void:
    var pane := WelcomeRecentPane.new()
    var grid := pane.find_child("RecentCards", true, false) as WelcomeRecentGrid
    var path := SaDataRoot.path("u5-a-recent-document.sad")
    SaSettings.add_recent_file(path)
    grid.rebuild()
    assert_eq(grid.cards.size(), 1, "one recent path draws one card")
    assert_false(grid.empty_line.visible, "and the empty line is gone")
    assert_eq(grid.grids[0].columns, 4, "with the cards four to a row again")
    SaSettings.remove_recent_file(path)
    pane.free()


## The welcome window holds the pane under a tab named "Recent", so the one
## label in the window that says it is the tab.
func test_the_window_says_recent_once() -> void:
    var tabs := TabContainer.new()
    var pane := WelcomeRecentPane.new()
    tabs.add_child(pane)
    assert_eq(tabs.get_tab_title(0), "Recent", "the tab is named Recent")
    assert_eq(_texts(tabs).count("Recent"), 0, "and no label under it says so again")
    tabs.free()


func test_the_scale_readout_follows_the_slider() -> void:
    SaSettings.ui_scale = 1.0
    var pane := WelcomeQuickSettingsPane.new()
    assert_eq(pane.scale_readout.text, "100%", "the row opens on the value, the Workspace page's wording")
    pane.scale_slider.set_value_no_signal(1.4)
    pane.scale_slider.value_changed.emit(1.4)
    assert_eq(pane.scale_readout.text, "140%", "and the readout follows the slider")
    SaSettings.ui_scale = 0.75
    pane.refresh()
    assert_eq(pane.scale_readout.text, "75%", "and a refresh reads the stored value back into it")
    pane.free()


## Built on the shared theme inside the tree, because a detached Control answers
## `ThemeDB`'s defaults, the trap `test_theme_defaults.gd` names.
func test_an_unselected_tab_is_drawn_in_the_bodys_colour() -> void:
    var saved := [SaUI.shared_theme, SaTheme.palette_id]
    SaTheme.use_named("default")
    SaUI.init_global_theme(null)
    var host := Control.new()
    host.name = "U5TabHost"
    host.theme = SaUI.shared_theme
    EventBus.add_child(host)
    var tabs := TabContainer.new()
    host.add_child(tabs)
    var bar := TabBar.new()
    host.add_child(bar)
    var body := Label.new()
    host.add_child(body)
    var text := body.get_theme_color("font_color")
    assert_eq(text, SaTheme.palette.text_primary, "the body is drawn in the palette's text colour")
    assert_eq(tabs.get_theme_color("font_unselected_color"), text, "an unselected tab of a TabContainer is the body's")
    assert_eq(bar.get_theme_color("font_unselected_color"), text, "and of a TabBar")
    assert_eq(bar.get_theme_color("icon_unselected_color"), text, "and so is its icon")
    assert_true(
        tabs.get_theme_stylebox("tab_selected") != tabs.get_theme_stylebox("tab_unselected"),
        "the chosen tab is still marked, by its box"
    )
    host.free()
    SaTheme.use_named(String(saved[1]))
    SaUI.shared_theme = saved[0] as Theme
