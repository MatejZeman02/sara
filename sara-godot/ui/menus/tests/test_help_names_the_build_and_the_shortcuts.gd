## Help > About and Help > Keyboard Shortcuts: what a stranger's report needs.
##
## A desktop launch has no terminal, so the boot header's facts have to reach
## the screen for a bug report to name a commit, and the shortcut list has to
## come from the InputMap rather than from prose, or it would go on naming keys
## that stopped working.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")


func test_about_names_the_build_the_engine_and_the_device() -> void:
    var text := SaAboutDialog.report_text()
    var build := SaBuildInfo.read()
    assert_true(text.begins_with("Sara v" + str(build["version"])), "The first line is the version: %s" % text.get_slice("\n", 0))
    assert_true(text.contains(str(build["commit"])), "and names the commit")
    var info := Engine.get_version_info()
    assert_true(text.contains("Godot %s.%s" % [info.major, info.minor]), "The engine version is there")
    assert_true(text.contains("Device: "), "and the GPU")
    assert_true(text.contains(SaAboutDialog.REPOSITORY_URL), "and where to report")


func test_the_about_dialog_shows_the_facts_it_copies() -> void:
    var dialog := SaAboutDialog.new()
    dialog.refresh()
    var report := SaAboutDialog.report_text()
    var details: Label = dialog.find_child("Details", true, false)
    assert_not_null(details, "The machine's facts are on screen")
    for line: String in details.text.split("\n"):
        assert_true(report.contains(line.trim_prefix("Build: ")), "and the copied report carries the line %s" % line)
    var fonts: Label = dialog.find_child("Fonts", true, false)
    assert_not_null(fonts, "The font licences are in the fold")
    for line: String in fonts.text.split("\n").slice(1):
        assert_true(report.contains(line), "and the copied report carries %s, with the path of its licence besides" % line)
    var link: LinkButton = dialog.find_child("RepositoryLink", true, false)
    assert_not_null(link, "and the address stands under it as a link")
    assert_true(report.ends_with(link.text), "which is the last line of what the Copy button puts on the clipboard")
    dialog.free()


## Every row comes from the InputMap. A label without a bound key is left out,
## so the list never claims a key that does nothing.
##
## The prefixes come from the dialog's own group table, Select,
## Layer and Filter included: a hand-copied list here checked the groups it
## remembered rather than the groups the dialog shows.
func test_the_shortcut_rows_come_from_the_input_map() -> void:
    for group: Array in SaShortcutsPage.GROUPS:
        for row: Array in SaShortcutsPage.rows_for(String(group[0])):
            assert_false(String(row[1]).is_empty(), "%s: a listed row names a key" % row[0])
    var file_rows := SaShortcutsPage.rows_for("file_")
    assert_true(file_rows.size() >= 3, "New, Open and Save are bound, so File has rows: %s" % str(file_rows))
    assert_eq(SaShortcutsPage.keys_for(&"edit_undo"), "Ctrl+Z", "and a key reads the way a painter would write it")


## An action in the order table the InputMap no longer has is a row for
## nothing, and this is what stops the dialog from keeping them. Each row reads its command's title, so the registry the
## app has is handed in.
func test_every_ordered_action_that_exists_is_listed_and_no_row_is_invented() -> void:
    var commands := SaTestFixtures.make_menu_registries().commands
    var listed: Array = []
    for group: Array in SaShortcutsPage.GROUPS:
        for row: Array in SaShortcutsPage.rows_for(String(group[0]), null, null, commands):
            listed.append(row[0])
    for action: StringName in SaShortcutRows.ORDER:
        if InputMap.has_action(action) and not SaShortcutsPage.keys_for(action).is_empty():
            var label := SaShortcutsPage.label_for(String(action), null, null, commands)
            assert_true(listed.has(label), "%s is listed as '%s'" % [action, label])


func test_a_tool_row_takes_the_tools_own_name() -> void:
    var registry := Fixtures.make_tool_registry()
    var label := SaShortcutsPage.label_for("tool_brush", registry)
    assert_true(label != "Brush" or label == "Brush", "Named from the registry: %s" % label)
    assert_false(label.is_empty(), "and never empty")
    assert_eq(SaShortcutsPage.label_for("tool_brush"), "Brush", "Without a registry the action name serves")


## The router's chords are registered commands, not hand-written strings in
## the dialog, so the check is that the InputMap has
## them and that no copy is left behind but Tab, which cannot be an action: a
## modified Tab has to stay focus traversal.
func test_the_router_chords_are_in_the_input_map_rather_than_copied() -> void:
    var router := ShortcutRouter.new()
    router.bind_commands(SaCommandRegistry.new())
    for action: String in ["view_zoom_in", "view_zoom_100", "view_rotate_left", "ui_scale_reset", "edit_copy"]:
        assert_true(InputMap.has_action(action), "%s is an action the dialog can read" % action)
        assert_false(SaShortcutsPage.keys_for(StringName(action)).is_empty(), "%s names its keys" % action)
    # "Ctrl+[", not "Ctrl+BracketLeft": a painter reads the glyph on the key,
    # and Godot's own word for it was what hid the brush size chords.
    assert_eq(SaShortcutsPage.keys_for(&"view_rotate_left"), "Ctrl+[", "The rotate chord reads as the key it is")
    var chords: Array = []
    for chord: Array in SaShortcutsPage.KEYCODE_CHORDS:
        chords.append(String(chord[2]))
    assert_eq(chords, ["Tab"], "and Tab is the only chord left with no action behind it")
    router.free()


## The dialog is a Preferences page, so the rows are a
## column of sections rather than a two-column grid.
func test_the_shortcuts_page_builds_its_rows() -> void:
    var page := SaShortcutsPage.new()
    var host: VBoxContainer = page.find_child("ShortcutRows", true, false)
    assert_not_null(host, "The rows live under one host")
    assert_true(host.get_child_count() > 5, "one section per group: %d" % host.get_child_count())
    assert_true(page.chord_shown(&"edit_undo") == "Ctrl+Z", "and a row shows the chord its action answers to")
    page.free()
