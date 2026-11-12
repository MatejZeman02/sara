## Saving, Importing, Exporting and Reset left the Workspace
## page for a Files page of their own, under General, where a newcomer looks
## for them.
##
## Each moved row is read by its title on the page it went to and looked for in
## vain on the one it left, and the search index is asked for each title, so a
## row that moved and lost its search entry fails here rather than in a
## painter's hands.
##
## Reset is at the foot
## of the sidebar, where it asks first.
## `ui/settings/tests/test_reset_all_preferences_asks_first_and_sits_at_the_foot_of_the_sidebar.gd`
## reads it there and reads Files without it.
extends "res://tests/test_framework.gd"

## `{section: [row titles]}`, the three sections as they stood on Workspace
## that are still on Files.
const MOVED := {
    "Saving": ["Previous versions kept", "Autosave every", "Autosave writes the working file"],
    "Importing": ["Fit a dropped or pasted picture"],
    "Exporting": ["Author"],
}

## What each moved row still writes, by title, so the move kept the binding.
const SETTINGS := {
    "Previous versions kept": &"sad_versions",
    "Autosave every": &"autosave_interval_minutes",
    "Autosave writes the working file": &"autosave_to_working_file",
    "Fit a dropped or pasted picture": &"import_fit",
    "Author": &"export_author",
}


func _titles(page: SaSettingsPage) -> Dictionary:
    var out := {}
    for block: SaPageSection in page.page.sections:
        var labels := PackedStringArray()
        for row: SaPageRow in block.rows:
            labels.append(row.label)
        out[block.title] = labels
    return out


func _row_titled(page: SaSettingsPage, title: String) -> SaPageRow:
    for row: SaPageRow in page.page.rows():
        if row.label == title:
            return row
    return null


## The settings folder came from General and is Files' last section.
func test_every_moved_row_is_on_the_files_page_under_its_old_section() -> void:
    var page := SaFilesPage.new()
    var titles := _titles(page)
    assert_eq(titles.keys(), MOVED.keys() + ["Settings folder"], "Files holds the four sections in order, %s" % [titles.keys()])
    for section: String in MOVED:
        for title: String in MOVED[section]:
            assert_true(PackedStringArray(titles.get(section, [])).has(title), "%s is under %s on Files" % [title, section])
    page.free()


func test_no_moved_row_is_left_on_workspace() -> void:
    var page := SaWorkspacePage.new()
    var titles := _titles(page)
    assert_eq(
        titles.keys(),
        ["Start from", "Size and font"],
        (
            "Workspace keeps I'm coming from and the interface's size, "
            + "the layouts, the shared rows and the embedding having gone "
            + "to Layouts and dockers, %s" % [titles.keys()]
        )
    )
    for section: String in MOVED:
        for title: String in MOVED[section]:
            assert_null(_row_titled(page, title), "and %s is not on it" % title)
    page.free()


func test_each_moved_row_still_writes_its_setting() -> void:
    var page := SaFilesPage.new()
    for title: String in SETTINGS:
        var row := _row_titled(page, title)
        assert_not_null(row, "%s is on Files" % title)
        if row != null:
            assert_eq(row.property, NodePath(String(SETTINGS[title])), "%s writes %s" % [title, SETTINGS[title]])
    page.free()


## Files leads the group about the files and the machine,
## where it sat under General before.
func test_files_leads_files_and_system_in_the_sidebar() -> void:
    var at := SaSettingsWindow.FIXED_PAGES.find("Files")
    assert_true(at > 0, "Files is a built-in page")
    assert_eq(String(SaSettingsWindow.FIXED_PAGES[at - 1]), "Canvas and colour", "the first after the painting group")
    assert_eq(String(SaSettingsWindow.FIXED_PAGES[at + 1]), "Performance", "and above Performance")


func test_the_search_finds_each_moved_row_on_files_and_not_on_workspace() -> void:
    var window := SaSettingsWindow.new()
    window.search.build_index()
    for section: String in MOVED:
        for title: String in MOVED[section]:
            var needle := title.to_lower()
            var on_files := false
            for words: String in window.search.index.get("Files", PackedStringArray()):
                on_files = on_files or words.contains(needle)
            assert_true(on_files, "a search for '%s' finds Files" % title)
    for title: String in ["Previous versions kept", "Autosave every", "Fit a dropped or pasted picture"]:
        var needle := title.to_lower()
        var on_workspace := false
        # The Workspace page is a part of Interface.
        for words: String in window.search.index.get(SaSettingsWindow.INTERFACE_PAGE, PackedStringArray()):
            on_workspace = on_workspace or words.contains(needle)
        assert_false(on_workspace, "and not Interface, which holds what was Workspace")
    window.free()
