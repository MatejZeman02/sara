## The News pane asks a tester to send their notes.
##
## The release notes want a line in the welcome window's News pane asking
## for the notes the recorder writes, and the feedback request has to
## name where to send them. The address is `SaHelpMenu.REPORT_URL`, which is
## what the menu's own Report row opens, so this suite holds that the paragraph
## carries it and that the button beside the paragraph opens that same constant.
##
## The pane is built and never added to a tree, for the reason
## `test_welcome_window.gd` gives: a `Window` in a suite hangs the whole run.
##
## The one press is the reason the pane has a seam. The button's handler calls
## `WelcomeNewsPane.opener`, which is `OS.shell_open` in everything but a suite,
## because pressing it for real would put a browser on the desktop of whoever is
## running the gate. The suite replaces it, reads the address, and puts the
## engine call back.
extends "res://tests/test_framework.gd"

## Every address the pane's button opened while a test was running.
var _opened: Array[String] = []

## The opener the app had before this suite replaced it, put back in `after_each`
## so a later suite presses the real seam.
var _engine_opener: Callable = Callable()


func before_each() -> void:
    _opened = []
    _engine_opener = WelcomeNewsPane.opener
    WelcomeNewsPane.opener = func(url: String) -> void: _opened.append(url)


func after_each() -> void:
    WelcomeNewsPane.opener = _engine_opener


## The app's value, before anything here replaces it, is the engine's own call.
func test_the_seam_is_the_engine_call_until_a_suite_says_otherwise() -> void:
    assert_true(_engine_opener == OS.shell_open, "the app opens a browser, and only a suite swaps this out")


## The paragraph says what the recorder is, which row opens it, where the zip
## lands and where to send it.
func test_the_paragraph_names_the_recorder_the_export_and_the_address() -> void:
    var pane := WelcomeNewsPane.new()
    var text := _paragraph_text(pane)
    assert_true(text.contains("Take a Note"), "the paragraph names the row that opens the recorder: %s" % text)
    assert_true(text.contains("Export"), "and the button that writes the zip")
    assert_true(text.contains(SaHelpMenu.REPORT_URL), "and the address the menu's own Report row opens")
    pane.free()


## The button is the menu's own words and the menu's own address, so the pane
## and Help cannot come to name two places.
func test_the_button_opens_the_menus_own_report_address() -> void:
    var pane := WelcomeNewsPane.new()
    var button := _report_button(pane)
    assert_not_null(button, "the feedback request has its button")
    assert_eq(button.text, "Report a Problem", "named the way the Help menu's row is")
    if button != null:
        button.pressed.emit()
    assert_eq(_opened, [SaHelpMenu.REPORT_URL], "and one press opens that address, not another")
    pane.free()


## Pinned above the file rather than drawn as a section, so a painter meets the
## ask whatever version the settings say was last seen and the oldest release
## note does not scroll it away.
func test_the_ask_is_pinned_above_the_column_that_scrolls() -> void:
    var pane := WelcomeNewsPane.new()
    var block := pane.find_child(WelcomeNewsPane.ASK_BLOCK, true, false)
    var scroll := pane.find_child("NewsScroll", true, false)
    assert_not_null(block, "the pane builds the feedback request")
    assert_not_null(scroll, "and keeps the sections' scroll")
    if block == null or scroll == null:
        pane.free()
        return
    assert_true(block.get_parent() == pane, "the feedback request is a child of the pane and not of the scrolling column")
    assert_false(scroll.is_ancestor_of(block), "so nothing in the column carries it away")
    assert_true(block.get_index() < scroll.get_index(), "and it stands above the sections")
    pane.free()


## The console line a scenario reads quotes the feedback request rather than counting it: the
## sentences naming the two controls are the claim, and a dump that said only
## "present" would pass for any paragraph at all.
func test_the_capture_line_carries_the_paragraph() -> void:
    var pane := WelcomeNewsPane.new()
    var line := pane.capture_line()
    assert_true(line.contains("Take a Note"), "the dump quotes the paragraph: %s" % line)
    assert_true(line.contains(SaHelpMenu.REPORT_URL), "and carries the address it names")
    assert_true(line.contains("Report a Problem"), "and the button's own words")
    pane.free()


func _paragraph_text(pane: WelcomeNewsPane) -> String:
    var label := pane.find_child(WelcomeNewsPane.ASK_PARAGRAPH, true, false) as Label
    assert_not_null(label, "the pane builds the feedback request's paragraph")
    return label.text if label != null else ""


func _report_button(pane: WelcomeNewsPane) -> Button:
    return pane.find_child(WelcomeNewsPane.ASK_BUTTON, true, false) as Button
