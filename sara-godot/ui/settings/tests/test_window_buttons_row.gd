## The window buttons row is where a painter can find it.
##
## The setting needs a Preferences row where an 'auto' option is selected by
## default, found by search. It must not sit under an element list eighteen rows
## deep on a page called Top Menu Bar, unsearchable by the words a painter uses.
## `scenarios/window-buttons-preference.json` measures the search
## before and after. This pins the three things that fix cannot lose.
##
## The rows now sit in the top bar's section of Layouts and dockers, and the bar's element list, behind its
## Elements… button, carries none.
extends "res://tests/test_framework.gd"

const TITLE := "Window button position"
const STYLE_TITLE := "Window button style"


func _page() -> SaDockersPage:
    return SaDockersPage.new()


## The row, found the way the search finds it: by the meta `SaSettingsRows.row`
## stamps on every row it builds.
func _row(page: Control, title: String = TITLE) -> Control:
    for node in page.find_children("*", "HBoxContainer", true, false):
        var row := node as Control
        if row != null and String(row.get_meta(SaSettingsRows.TITLE_META, "")) == title:
            return row
    return null


## The second dropdown: the look, apart from the edge, in the
## same section and searchable by its own words.
func test_the_style_row_sits_beside_the_position_row_with_its_own_words() -> void:
    var page := _page()
    var style_row := _row(page, STYLE_TITLE)
    assert_not_null(style_row, "the page carries the style row")
    assert_true(page.page.row(&"window_button_style") != null, "under its own key")
    var haystack := SaSettingsSearch.row_haystack(style_row)
    for word: String in ["auto", "traffic lights", "icons", "macos"]:
        assert_true(haystack.contains(word), "a search for '%s' reaches the style row: %s" % [word, haystack])
    page.free()


## In the top bar's section of Layouts and dockers, and not on the list's page:
## the bar's list is eighteen rows deep, so a row under it opened off the
## bottom, and a second control on the setting is how the two disagree.
func test_the_row_sits_in_the_top_bar_section_and_not_on_the_list() -> void:
    var page := _page()
    var row := _row(page)
    assert_not_null(row, "the page carries the row")
    assert_true(page.page.row(SaTopBarSection.FIRST_ROW) != null, "under the key a former title lands on")
    var list := SaTopBarPage.new()
    assert_null(_row(list), "and the list's page carries none")
    assert_null(list.find_child("WindowButtonPositionOpt", true, false), "nor its dropdown")
    list.free()
    page.free()


## The words a painter looks for. The search indexes a row by its title and the
## sentence under it, so a sentence that never says macOS cannot be found by
## anyone looking for the Apple arrangement.
func test_the_sentence_carries_the_words_the_note_used() -> void:
    var page := _page()
    var haystack := SaSettingsSearch.row_haystack(_row(page))
    for word: String in ["apple", "macos", "window", "minimise", "maximise", "close"]:
        assert_true(haystack.contains(word), "a search for '%s' reaches the row: %s" % [word, haystack])
    page.free()


## What the dropdown offers is on screen, so it is searchable too. This is the
## general half of the fix and it holds for every page's dropdowns.
func test_a_dropdown_puts_its_own_words_in_the_haystack() -> void:
    var page := _page()
    var haystack := SaSettingsSearch.row_haystack(_row(page))
    for word: String in ["auto", "left", "right"]:
        assert_true(haystack.contains(word), "the dropdown's '%s' is searchable" % word)
    page.free()


## One control, one setting. Two of them writing `window_button_position` is the
## bug this suite guards against, and moving a row is exactly how a second copy appears.
func test_only_one_control_writes_the_setting() -> void:
    var page := _page()
    var found := 0
    for node in page.find_children("*", "Button", true, false):
        if String(node.name) == "WindowButtonPositionOpt" and node is SaChoiceButton:
            found += 1
    assert_eq(found, 1, "the page holds one window button dropdown")
    page.free()


## Auto is what a fresh install is on.
func test_auto_is_the_first_item_and_the_default() -> void:
    var page := _page()
    var option := page.find_child("WindowButtonPositionOpt", true, false) as SaChoiceButton
    assert_not_null(option, "the dropdown is there")
    assert_eq(SaTopBarSection.WINDOW_BUTTON_POSITIONS[0], "auto", "auto is the first position")
    assert_eq(option.choice_labels()[0].to_lower().contains("auto"), true, "and the first item says so")
    page.free()
