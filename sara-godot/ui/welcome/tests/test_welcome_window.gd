## The welcome window: the boot's five answers, the preference
## behind one of them, and the four panes the window builds.
##
## The window is built and never added to a tree, for the reason
## `test_layer_rename_dialog.gd` gives: a `Window` in a suite hangs the whole
## run. Everything here is readable from a detached one, because the panes are
## built in `_init` and the boot decision is a static.
extends "res://tests/test_framework.gd"


## The one yes and the four refusals, as a table: setting, document path, a
## capture run, a test environment, and what the boot should do.
func test_wanted_at_start_refuses_four_ways_and_opens_once() -> void:
    assert_false(SaWelcomeWindow.wanted_at_start(false, "", false, false), "A painter who turned it off does not get it")
    assert_false(SaWelcomeWindow.wanted_at_start(true, "", true, false), "A capture run does not get it, over its own shot")
    assert_false(SaWelcomeWindow.wanted_at_start(true, "", false, true), "A suite does not get it")
    assert_false(
        SaWelcomeWindow.wanted_at_start(true, "/tmp/asked-for.sad", false, false),
        "And a document named on the command line is what that painter asked for"
    )
    assert_true(SaWelcomeWindow.wanted_at_start(true, "", false, false), "A plain start with the setting on gets it")


## The checkbox writes a stored preference, which is why it survives a restart.
func test_welcome_at_start_is_stored_under_the_ui_section() -> void:
    assert_true(SaSettingsKeys.KEYS.has("welcome_at_start"), "the preference has a section and a key")
    assert_eq(SaSettingsKeys.KEYS["welcome_at_start"], ["ui", "welcome_at_start"], "under ui, spelled as the row asks for it")
    var fresh := SaSettingsValues.new()
    assert_true(fresh.welcome_at_start, "and a profile with no key yet gets it on")
    fresh.free()


## The four panes and their order, which is what every other W row waits on.
func test_the_window_opens_with_four_named_panes() -> void:
    var window := SaWelcomeWindow.new()
    assert_not_null(window.tabs, "the window carries a tab container")
    assert_eq(window.tabs.get_tab_count(), 4, "four panes")
    assert_eq(window.tabs.get_tab_title(0), "Recent", "Recent first")
    assert_eq(window.tabs.get_tab_title(1), "News", "News second")
    assert_eq(window.tabs.get_tab_title(2), "Tips", "Tips third")
    assert_eq(window.tabs.get_tab_title(3), "Quick settings", "and Quick settings last")
    assert_eq(SaWelcomeWindow.tab_of(window.tips_pane).get_index(), 2, "the third tab is the window's Tips pane")
    assert_eq(window.logical_size, Vector2i(720, 540 + 240), "at the size the change log needs, under a band 240 tall")
    assert_eq(window.logical_min_size, Vector2i(520, 360 + 174), "and with the floor it names, under a band 174 tall")
    window.free()


## The two containers the New and Open row and the recent grid fill, in the order the Recent pane declares
## them, so neither unit has to read the other's file, under the row of New
## and Open that leads the pane.
func test_the_recent_pane_carries_the_two_containers_in_order() -> void:
    var window := SaWelcomeWindow.new()
    var names: Array[String] = []
    for child in window.recent_pane.get_children():
        names.append(String(child.name))
    var order := ["Actions", "RecoveryRow", "RecentGrid"]
    assert_eq(names, order, "New and Open's row, then the recent grid, under no title of its own")
    window.free()
