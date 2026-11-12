## About leads with the name and the version and folds the licences away.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## About was once mostly a font licence list, with the version on line three,
## every SIL licence named in full with the path of its file, and all of it one
## paragraph at one size and weight. So the heading carries the name and the
## version at the title size, the machine's facts are a muted block under the
## tagline, and the modules and the fonts sit in a fold that is closed when the
## window opens. What a bug report wants is a different thing from what a
## painter reads, so `report_text()` still carries every line with the path of
## every licence file and the window shows none of the paths.
##
## The window is built and never added to a tree, for the reason
## `test_the_about_window_links_the_repository` gives. Where it lies on a short
## screen is held by `test_the_about_window_fits_a_screen`.
extends "res://tests/test_framework.gd"


func test_the_heading_names_sara_and_its_version() -> void:
    var dialog := SaAboutDialog.new()
    dialog.refresh()
    var version := SaBuildInfo.version()
    assert_false(version.is_empty(), "The project has a version to name")
    assert_not_null(dialog.heading, "About has a heading")
    if dialog.heading != null:
        assert_true(dialog.heading.text.contains(version), "The heading contains the version: %s" % dialog.heading.text)
        assert_eq(dialog.heading.text, "Sara " + version, "and is the name and the bare version")
        assert_eq(dialog.heading.get_theme_font_size("font_size"), SaUI.font_size_for(SaUI.fraction_of(22)), "at the title size")
    var column := dialog.heading.get_parent()
    assert_eq(column.get_child(0), dialog.heading, "and it is the first thing in the window")
    assert_eq(column.get_child(1).name, &"Tagline", "with the tagline under it")
    dialog.free()


## The machine's facts are one muted block, not the heading's weight.
func test_the_machines_facts_are_a_muted_block_under_the_tagline() -> void:
    var dialog := SaAboutDialog.new()
    dialog.refresh()
    assert_not_null(dialog.details, "About has a details block")
    if dialog.details != null:
        var text := dialog.details.text
        for fact: String in ["Build: ", "Godot ", "Renderer: ", "Device: ", "Display: ", "OS: "]:
            assert_true(text.contains(fact), "The details carry %s" % fact.strip_edges())
        assert_false(text.contains("Modules"), "and the modules are not among them")
        assert_false(text.contains("Fonts"), "nor the fonts")
        assert_true(dialog.details.has_theme_color_override("font_color"), "and the block is drawn in its own colour")
        var quiet := dialog.details.get_theme_color("font_color")
        assert_true(quiet != dialog.heading.get_theme_color("font_color"), "a quieter one than the heading's")
        assert_true(dialog.scrolling_body.is_ancestor_of(dialog.details), "inside the scroll, where the room is taken from")
    dialog.free()


func test_the_fold_is_closed_when_the_window_opens() -> void:
    var dialog := SaAboutDialog.new()
    dialog.refresh()
    assert_not_null(dialog.fold, "About has a fold")
    if dialog.fold != null:
        assert_true(dialog.fold is FoldableContainer, "built with the engine's own fold")
        assert_true(dialog.fold.folded, "closed on open")
        assert_eq(dialog.fold.title, "Modules and licences", "under the name it is given")
        assert_true(dialog.fold.is_ancestor_of(dialog.find_child("Modules", true, false)), "the modules are in it")
        assert_true(dialog.fold.is_ancestor_of(dialog.find_child("Fonts", true, false)), "and so are the fonts")
    dialog.free()


## A font line names its family, its holder and its licence, and no path.
func test_a_font_line_names_the_family_the_holder_and_the_licence() -> void:
    var dialog := SaAboutDialog.new()
    dialog.refresh()
    var fonts := dialog.find_child("Fonts", true, false) as Label
    assert_not_null(fonts, "The fonts are on screen, in the fold")
    if fonts != null:
        var lines := fonts.text.split("\n")
        var families := 0
        for id: String in SaFonts.FAMILIES:
            var family: Dictionary = SaFonts.FAMILIES[id]
            if String(family["licence"]).is_empty():
                continue
            families += 1
            var found := false
            for line: String in lines:
                if line.begins_with(String(family["name"])):
                    found = true
                    assert_true(line.contains(String(family["copyright"])), "%s names its holder" % family["name"])
                    assert_true(line.contains("SIL Open Font License 1.1"), "and its licence")
                    assert_false(line.contains("/"), "and no path: %s" % line)
            assert_true(found, "%s has a line" % family["name"])
        assert_eq(lines.size() - 1, families, "one line a family under the heading of the block")
    dialog.free()


## No label, button, link or title the window can show says `res://`, the fold's
## contents included whether the fold is open or not, and a tooltip is shown too.
func test_no_shown_text_contains_a_resource_path() -> void:
    var dialog := SaAboutDialog.new()
    dialog.refresh()
    var seen := 0
    for node: Node in _all_nodes(dialog):
        var shown: Array[String] = []
        if node is Label:
            shown.append((node as Label).text)
        if node is BaseButton:
            shown.append((node as BaseButton).text)
        if node is FoldableContainer:
            shown.append((node as FoldableContainer).title)
        if node is Control:
            shown.append((node as Control).tooltip_text)
        for text: String in shown:
            seen += 1
            assert_false(text.contains("res://"), "%s shows a resource path: %s" % [node.name, text])
    assert_true(seen > 8, "the walk met the window's texts, %d of them" % seen)
    dialog.free()


## The report is what changed hands to a bug tracker, so it keeps all of it,
## the path of every licence file too.
func test_the_report_still_carries_the_paths() -> void:
    var report := SaAboutDialog.report_text()
    assert_true(report.contains("res://"), "The copied report names the licence files")
    for id: String in SaFonts.FAMILIES:
        var licence := String(SaFonts.FAMILIES[id]["licence"])
        if not licence.is_empty():
            assert_true(report.contains(licence), "and %s" % licence)
    assert_true(report.begins_with("Sara v" + SaBuildInfo.version()), "its first line is still the version")
    assert_true(report.ends_with(SaAboutDialog.REPOSITORY_URL), "and its last is still the address")


## The paths are only the family lines' tail, so the two forms of the line
## differ by it and by nothing else.
func test_the_two_forms_of_a_font_line_differ_by_the_path_alone() -> void:
    var with_path := SaFonts.licence_lines()
    var without := SaFonts.licence_lines(false)
    assert_eq(with_path.size(), without.size(), "the same families are named")
    for i in with_path.size():
        assert_true(with_path[i].begins_with(without[i]), "%s is the line without its path" % without[i])
        assert_eq(with_path[i].trim_prefix(without[i]).substr(0, 2), " (", "and the path follows in a bracket")


## The buttons keep the way the dialogs' rows read, Copy Details and then Close,
## which is the default and the last.
func test_the_buttons_read_copy_details_then_close() -> void:
    var dialog := SaAboutDialog.new()
    var row := dialog.find_child("Buttons", true, false) as HBoxContainer
    assert_not_null(row, "About has its buttons in the row the dialogs share")
    if row != null:
        assert_eq(row.get_child_count(), 2, "two of them")
        assert_eq((row.get_child(0) as Button).text, "Copy Details", "Copy Details first")
        assert_eq((row.get_child(1) as Button).text, "Close", "and Close last")
        assert_true(dialog.default_button == row.get_child(1), "Close is the one Enter presses")
        assert_eq(row.alignment, BoxContainer.ALIGNMENT_END, "at the end of the row")
    dialog.free()


func _all_nodes(root: Node) -> Array[Node]:
    var out: Array[Node] = [root]
    for child: Node in root.get_children():
        out.append_array(_all_nodes(child))
    return out
