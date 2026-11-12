## Preferences takes its four text sizes from the theme font, largest first,
## and a section with no title draws neither heading nor rule.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Every size moves with the Font size preference, and New Document and the
## filter dialogs show no empty heading and rule. What
## is read here is the size each label carries, since a dialog never runs the
## theme pass and the override is what it draws at.
extends "res://tests/test_framework.gd"

## The Interface page, whose General part has sections, rows and explanations,
## and which needs no RenderingDevice. General is a part of Interface.
const PAGE := SaSettingsWindow.INTERFACE_PAGE

var _kept_font_scale: float = 1.0


func before_each() -> void:
    _kept_font_scale = SaUI.user_font_scale


func after_each() -> void:
    SaUI.user_font_scale = _kept_font_scale
    SaUI.refresh_font_sizes()


## The four sizes on the open page, in the order they are meant to run.
func _sizes(window: SaSettingsWindow) -> Array[int]:
    var content := window.content_container
    var title := content.find_child("PageTitle", false, false) as Label
    var heading := content.find_child("Heading", true, false) as Label
    var row_title := content.find_child("Title", true, false) as Label
    var hint := content.find_child("Hint", true, false) as Label
    for label: Label in [title, heading, row_title, hint]:
        assert_not_null(label, "The page has a title, a heading, a row title and an explanation")
    if title == null or heading == null or row_title == null or hint == null:
        return []
    return [
        title.get_theme_font_size("font_size"),
        row_title.get_theme_font_size("font_size"),
        heading.get_theme_font_size("font_size"),
        hint.get_theme_font_size("font_size"),
    ]


func _largest_first(sizes: Array[int], at: String) -> void:
    assert_eq(sizes.size(), 4, "Four sizes read at %s" % at)
    for index in range(1, sizes.size()):
        assert_true(
            sizes[index - 1] > sizes[index], "At %s title, row title, heading, hint run largest first, got %s" % [at, sizes]
        )


func test_the_four_sizes_run_largest_first_at_the_default_and_the_largest() -> void:
    var window := SaSettingsWindow.new()
    SaUI.user_font_scale = 1.0
    assert_true(window.show_page(PAGE), "The %s page opens" % PAGE)
    var at_default := _sizes(window)
    _largest_first(at_default, "the default Font size")
    if at_default.size() == 4:
        assert_eq(at_default[1], SaUI.get_font_size(), "and a row's title is the theme font's own size")

    SaUI.user_font_scale = SaUI.MAX_FONT_SCALE
    assert_true(window.show_page(PAGE), "The page opens again at the largest Font size")
    var at_largest := _sizes(window)
    _largest_first(at_largest, "the largest Font size")
    if at_default.size() == 4 and at_largest.size() == 4:
        for index in 4:
            var grew := at_largest[index] > at_default[index]
            assert_true(grew, "Each of the four grows with the preference, got %s then %s" % [at_default, at_largest])
    window.free()


## The page is not built again while the painter drags Font size, so the
## window sizes what it shows where it stands.
func test_an_open_page_follows_the_font_size() -> void:
    var window := SaSettingsWindow.new()
    SaUI.user_font_scale = 1.0
    window.show_page(PAGE)
    var before := _sizes(window)
    SaUI.user_font_scale = SaUI.MAX_FONT_SCALE
    window._on_ui_font_scale_changed(SaUI.MAX_FONT_SCALE)
    var after := _sizes(window)
    _largest_first(after, "the largest Font size, unbuilt")
    if before.size() == 4 and after.size() == 4:
        assert_true(after[3] > before[3], "The open page's explanations grew, %s to %s" % [before[3], after[3]])
        assert_true(after[0] > before[0], "and its title did, %s to %s" % [before[0], after[0]])
    window.free()


func test_an_empty_title_draws_no_heading_and_no_rule() -> void:
    var page := VBoxContainer.new()
    var rows := SaSettingsRows.section(page, "")
    var block := rows.get_parent()
    assert_null(block.find_child("Heading", false, false), "An empty-titled section has no heading")
    assert_eq(block.find_children("*", "HSeparator", false, false).size(), 0, "and no rule")
    assert_eq(block.get_child_count(), 1, "only its rows")

    var named := SaSettingsRows.section(page, "Canvas").get_parent()
    assert_not_null(named.find_child("Heading", false, false), "A titled one still has its heading")
    assert_eq(named.find_children("*", "HSeparator", false, false).size(), 1, "and its rule")
    page.free()


## New Document asks for a section with no name, and opened on a bare rule.
func test_new_document_opens_on_no_rule() -> void:
    var dialog := NewDocumentDialog.new()
    assert_eq(dialog.find_children("Heading", "Label", true, false).size(), 0, "New Document draws no empty heading")
    assert_eq(dialog.find_children("Rule", "", true, false).size(), 0, "and no rule over its first row")
    dialog.free()
