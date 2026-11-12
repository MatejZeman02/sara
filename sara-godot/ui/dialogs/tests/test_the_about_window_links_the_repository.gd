## The About window's address is a link that opens the repository.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The address was once the last line of the report, one plain label, which
## could be read and copied with Copy Details but not opened. It is now a
## link under the report, and the report the Copy button carries still ends with
## the address as text.
##
## The one press is the reason the window has a seam. The link calls
## `SaAboutDialog.opener`, which is `OS.shell_open` in everything but a suite,
## because pressing it for real would put a browser on the desktop of whoever is
## running the gate. The suite replaces it, reads the address it was handed, and
## puts the engine call back.
##
## The window is built and never added to a tree, for the reason
## `test_welcome_window.gd` gives: a `Window` in a suite hangs the whole run. Its
## place on a short screen is held by `test_the_about_window_fits_a_screen`.
extends "res://tests/test_framework.gd"

## Every address the link opened while a test was running.
var _opened: Array[String] = []

## The opener the app had before this suite replaced it, put back in `after_each`
## so a later suite presses the real seam.
var _engine_opener: Callable = Callable()


func before_each() -> void:
    _opened = []
    _engine_opener = SaAboutDialog.opener
    SaAboutDialog.opener = func(url: String) -> void: _opened.append(url)


func after_each() -> void:
    SaAboutDialog.opener = _engine_opener


## The app's value, before anything here replaces it, is the engine's own call.
func test_the_seam_is_the_engine_call_until_a_suite_says_otherwise() -> void:
    assert_true(_engine_opener == OS.shell_open, "the app opens a browser, and only a suite swaps this out")


## The link is in the window, is a link and reads the repository's address.
func test_about_carries_a_link_that_reads_the_repository_address() -> void:
    var dialog := SaAboutDialog.new()
    dialog.refresh()
    var link := dialog.find_child("RepositoryLink", true, false) as LinkButton
    assert_not_null(link, "About has a link to the repository")
    if link != null:
        assert_eq(link.text, SaAboutDialog.REPOSITORY_URL, "and it reads the address itself, so a painter sees where it goes")
        assert_true(link == dialog.repository_link, "and the dialog names it the way it names its Copy button")
    dialog.free()


## One press hands the address to the opener, once, and nothing else.
func test_pressing_the_link_opens_the_repository() -> void:
    var dialog := SaAboutDialog.new()
    dialog.refresh()
    var link := dialog.find_child("RepositoryLink", true, false) as LinkButton
    assert_not_null(link, "About has a link to the repository")
    if link != null:
        link.pressed.emit()
    assert_eq(_opened, [SaAboutDialog.REPOSITORY_URL], "one press opens the repository's address, not another")
    dialog.free()


## Copy Details is what a bug report carries, and the address is still in it,
## as its last line and as text.
func test_the_copied_report_still_ends_with_the_address() -> void:
    var text := SaAboutDialog.report_text()
    var last_line := text.get_slice("\n", text.count("\n"))
    assert_true(text.ends_with(SaAboutDialog.REPOSITORY_URL), "the report ends with the address: %s" % last_line)
    assert_eq(last_line, SaAboutDialog.REPOSITORY_URL, "on a line of its own")
    assert_eq(text, SaAboutDialog.facts_text() + "\n" + SaAboutDialog.REPOSITORY_URL, "after every fact the report carries")


## The address is drawn once. The details on screen stop before it and the link
## under them is the line that carries it.
func test_the_address_is_shown_once_and_as_the_link() -> void:
    var dialog := SaAboutDialog.new()
    dialog.refresh()
    var label := dialog.find_child("Details", true, false) as Label
    assert_not_null(label, "The details are on screen")
    if label != null:
        assert_false(label.text.contains(SaAboutDialog.REPOSITORY_URL), "the address is not a line of the details as well")
        assert_eq(label.text, SaAboutDialog.details_text(), "the details are the machine's facts")
    dialog.free()


## Outside the scroll, so a screen too short for the body still shows the
## link, and under it.
func test_the_link_stands_under_the_report_and_outside_its_scroll() -> void:
    var dialog := SaAboutDialog.new()
    var link := dialog.repository_link
    var scroll := dialog.scrolling_body
    assert_not_null(link, "About has a link to the repository")
    assert_not_null(scroll, "and a scroll for its body")
    if link != null and scroll != null:
        assert_false(scroll.is_ancestor_of(link), "the body scrolls and the link does not")
        assert_true(link.get_parent() == scroll.get_parent(), "and the two stand in one column")
        assert_true(link.get_index() > scroll.get_index(), "with the link under the report")
    dialog.free()
