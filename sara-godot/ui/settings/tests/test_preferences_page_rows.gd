## The row report reads the open Preferences page the way the search does
## already, and General's own numbers back it.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice, for the gamut solid on the Colour Spaces page.
const REQUIRES_GPU := true


## Walked up to *root* rather than asked of the node alone, the way
## `test_settings_pages.gd`'s own `_live_controls` does: `queue_free` marks the
## node it was called on and none of its children, and this window is never in
## a tree to reach the frame that frees the outgoing page.
func _live_rows(root: Node) -> Array[Control]:
    var out: Array[Control] = []
    for node in root.find_children("*", "HBoxContainer", true, false):
        var row := node as Control
        if row == null or not row.has_meta(SaSettingsRows.ROW_META):
            continue
        var walk: Node = row
        while walk != root and walk != null and not walk.is_queued_for_deletion():
            walk = walk.get_parent()
        if walk == root:
            out.append(row)
    return out


func test_the_report_matches_the_pages_own_live_rows() -> void:
    var window := SaSettingsWindow.new()
    for title: String in window.categories:
        window.show_page(title)
        var report := SaSettingsRowReport.report(window)
        var lines := _live_rows(window.content_container)
        var entries := report["rows"] as Array
        assert_eq(entries.size(), lines.size(), "'%s': one entry per live row" % title)
        for i in lines.size():
            var words := String((entries[i] as Dictionary)["words"])
            assert_eq(words, SaSettingsSearch.row_haystack(lines[i]), "'%s' row %d: the words are the search's" % [title, i])
        # Asked of the class the title builds and not of a list of titles, which
        # three page units edited on one afternoon and conflicted over each time.
        var built := window.build_page(title)
        var expect_declared := built is SaSettingsPage
        # A page converted in part is no `SaSettingsPage` and realizes an
        # `SaPage` of its own as it is built, which is Display, so the
        # mark the report itself looks for is asked of what was built as well.
        for box in built.find_children("*", "Container", true, false):
            expect_declared = expect_declared or box.has_meta(SaPage.PAGE_META)
        built.free()
        assert_eq(
            bool(report["declared"]),
            expect_declared,
            "'%s': %s" % [title, "built through SaPage" if expect_declared else "no page is built through SaPage yet"]
        )
    window.free()


func test_the_history_row_reads_the_slider() -> void:
    var window := SaSettingsWindow.new()
    window.show_page(SaSettingsWindow.INTERFACE_PAGE)
    var report := SaSettingsRowReport.report(window)
    var found := false
    for entry: Dictionary in report["rows"] as Array:
        if String(entry["title"]) != "Undo steps":
            continue
        found = true
        assert_eq(float(entry["value"]), SaSettings.history_depth, "the row's value is the setting")
        var keys := entry["keys"] as Array
        assert_eq(keys.size(), 1, "one control takes the keyboard")
        if keys.size() == 1:
            assert_eq(String(keys[0]), "HSlider", "and it is the slider")
    assert_true(found, "the row is in the report")
    window.free()


## The undo steps are one row on one page. A second slider on Performance bound
## to the same `history_depth` was listed by the search beside General's, and the
## light mode moved it behind General's back. General is a part of Interface.
func test_the_undo_steps_are_one_row_on_interface() -> void:
    var window := SaSettingsWindow.new()
    var found: Array[String] = []
    for title: String in window.categories:
        window.show_page(title)
        for entry: Dictionary in SaSettingsRowReport.report(window)["rows"] as Array:
            if String(entry["title"]) == "Undo steps":
                found.append(title)
    assert_eq(found, [SaSettingsWindow.INTERFACE_PAGE] as Array[String], "one Undo steps row, on Interface: %s" % [found])
    window.free()
