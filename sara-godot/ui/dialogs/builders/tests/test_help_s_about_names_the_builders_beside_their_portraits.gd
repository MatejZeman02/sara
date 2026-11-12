## Help's About names the builders beside their portraits.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## About shows four portraits in a fold of its own, "Built by", folded like the
## licences, with a line under the four that links nothing.
##
## The window is built and never added to a tree, for the reason
## `test_welcome_window.gd` gives: a `Window` in a suite hangs the whole run. So
## the fold as a painter sees it is held by
## `scenarios/help-s-about-names-the-builders-beside-their-portraits.json`
## on the running app, and this suite holds the line and the four.
extends "res://tests/test_framework.gd"

## The four, in the order the fold shows them.
const NAMES := ["mads", "astrid", "cira", "bogo"]
## The group each stands for, as its line names it.
const GROUPS := {"mads": "Opus", "astrid": "Sonnet", "cira": "DeepSeek", "bogo": "Gemini"}
## The day each portrait was cut from.
const DAYS := {"mads": "Day 4", "astrid": "Day 5", "cira": "Day 6", "bogo": "Day 6"}
## The longest side a portrait may have, in pixels.
const LONGEST := 256


func test_built_by_is_a_fold_of_its_own_folded_when_the_window_opens() -> void:
    var dialog := SaAboutDialog.new()
    var fold := dialog.find_child("BuiltBy", true, false) as FoldableContainer
    assert_not_null(fold, "About has a fold named BuiltBy")
    if fold != null:
        assert_eq(fold.title, "Built by", "titled Built by")
        assert_true(fold.folded, "and folded when the window opens, like the licences")
        assert_true(fold == dialog.built_by, "the dialog names it")
        var licences := dialog.fold
        assert_true(licences.get_parent() == fold.get_parent(), "it stands in the body beside the licences")
        assert_true(fold.get_index() > licences.get_index(), "under them, so opening it moves nothing above it")
        assert_true(dialog.scrolling_body.is_ancestor_of(fold), "and scrolls with the body")
    dialog.free()


## The fold's four names, read off the labels the window draws.
func test_the_fold_names_the_four_builders_in_the_order_they_were_painted() -> void:
    var dialog := SaAboutDialog.new()
    assert_eq(_names(dialog.built_by), NAMES, "the fold names mads, astrid, cira and bogo, in that order")
    dialog.free()


## Each line says which group of builders the portrait stands for and where the
## portrait is from.
func test_each_builder_has_a_line_naming_its_group_and_the_sessions() -> void:
    var fold := SaBuiltByFold.new()
    for builder_name: String in NAMES:
        var row := fold.find_child("Builder_" + builder_name, true, false)
        assert_not_null(row, "%s has a row in the fold" % builder_name)
        if row == null:
            continue
        var line := row.find_child("Line", true, false) as Label
        var group := String(GROUPS[builder_name])
        assert_true(
            line.text.contains("the %s clones" % group), "%s stands for the %s clones: %s" % [builder_name, group, line.text]
        )
        assert_true(
            line.text.contains(DAYS[builder_name]), "%s's line names %s: %s" % [builder_name, DAYS[builder_name], line.text]
        )
        assert_true(line.text.contains("painting sessions"), "%s's line says its portrait is from the sessions" % builder_name)
        assert_eq(line.autowrap_mode, TextServer.AUTOWRAP_WORD_SMART, "and wraps")
        assert_true(fold.lines.has(line), "and is one the window asks for its height again")
    fold.free()


## Every portrait is a picture in the tree with the import file the tree's other
## pictures have, small, and the very picture the window draws.
func test_each_portrait_is_a_small_picture_in_the_tree() -> void:
    var fold := SaBuiltByFold.new()
    for builder_name: String in NAMES:
        var path := SaBuiltByFold.portrait_path(builder_name)
        assert_true(FileAccess.file_exists(path), "%s's portrait is in the tree at %s" % [builder_name, path])
        assert_true(FileAccess.file_exists(path + ".import"), "with its import file")
        assert_true(ResourceLoader.exists(path), "and Godot loads it")
        var image := Image.load_from_file(ProjectSettings.globalize_path(path))
        assert_not_null(image, "%s's portrait reads as a picture" % builder_name)
        if image != null:
            var longest := maxi(image.get_width(), image.get_height())
            assert_true(longest <= LONGEST, "%s's portrait is %d on its long side, at most %d" % [builder_name, longest, LONGEST])
        var row := fold.find_child("Builder_" + builder_name, true, false)
        var portrait := row.find_child("Portrait", true, false) as TextureRect if row != null else null
        assert_not_null(portrait, "%s's row draws a portrait" % builder_name)
        if portrait == null:
            continue
        assert_not_null(portrait.texture, "%s's portrait loaded" % builder_name)
        if portrait.texture != null:
            assert_eq(portrait.texture.resource_path, path, "and it is the picture in the tree")
        assert_true(portrait.get_index() == 0, "beside the name, on its left")
    fold.free()


## The line under the four says whom they stand for, whole, and the fold has
## no link.
func test_the_line_under_the_four_reads_whole_with_no_link() -> void:
    var dialog := SaAboutDialog.new()
    var fold := dialog.built_by
    var closing := fold.find_child("EveryClone", true, false) as Label
    assert_not_null(closing, "a line stands under the four")
    if closing != null:
        var rows := fold.find_children("Builder_*", "HBoxContainer", true, false)
        assert_true(closing.get_index() > rows[rows.size() - 1].get_index(), "under the last of them")
        assert_eq(closing.text, "These four stand for every clone that built Sara.", "and says they stand for every clone")
    assert_true(fold.find_children("*", "LinkButton", true, false).is_empty(), "the fold has no link")
    assert_false("journal_link" in fold, "and keeps none to wire")
    assert_false(dialog.has_method("open_journal"), "and About opens no journal")
    assert_eq(_names(fold), NAMES, "the four still stand in it")
    dialog.free()


## Copy Details stays the build's report. The window shows the builders and the
## report a bug carries does not.
func test_copy_details_does_not_carry_the_portraits() -> void:
    var text := SaAboutDialog.report_text()
    assert_eq(text, SaAboutDialog.facts_text() + "\n" + SaAboutDialog.REPOSITORY_URL, "the report is the facts and the address")
    assert_false(text.contains("Built by"), "and no fold of builders")
    for builder_name: String in NAMES:
        assert_false(text.contains(SaBuiltByFold.portrait_path(builder_name)), "and no portrait of %s" % builder_name)


func _names(fold: SaBuiltByFold) -> Array:
    var names := []
    for row: Node in fold.find_children("Builder_*", "HBoxContainer", true, false):
        names.append((row.find_child("Name", true, false) as Label).text)
    return names
