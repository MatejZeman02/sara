## The Krita import lives in Preferences, and says what it did.
##
## The Import Krita presets button is in Preferences only, not on the Brush
## Presets docker. A `print()` of the importer's whole report to stdout tells a
## painter who imported a bundle nothing at all, and a page has room to say how
## many arrived and which were refused.
extends "res://tests/test_framework.gd"

const REPORTED_KEYS := [
    "open",
    "focused",
    "position",
    "size",
    "bound",
    "save_disabled",
    "delete_disabled",
    "new_disabled",
    # The line under the grid, which is a fact about the loaded preset rather
    # than a shape, and so is read here rather than argued about from a shot.
    "provenance",
    "chooser",
    # What each action would say and what the last one did say.
    "loaded",
    "bar_button",
    # The tooltip the label no longer carries the preset's name in.
    "bar_tooltip",
    "save_tip",
    "delete_tip",
    "naming",
    "name_text",
    "name_focused",
    "said",
    "actions_in_view",
    # New preset...'s own report.
    "new_dialog",
    # Out on a lend, and the head a lent docker shows.
    "lent",
    "head",
]


## The page is a part of Brushes, under the brush slots.
func test_preferences_offers_the_page() -> void:
    assert_true(SaSettingsWindow.FIXED_PAGES.has("Brushes"), "Preferences lists a Brushes page")
    var window := SaSettingsWindow.new()
    var page := window.build_page("Brushes") as SaSettingsWindow.PageParts
    assert_true(
        page != null and page.part_of(SaBrushPresetsPage) != null, "and building that title gives the page among its parts"
    )
    if page != null:
        page.free()
    window.free()


func test_a_fresh_page_says_nothing_has_been_imported() -> void:
    var page := SaBrushPresetsPage.new()
    assert_eq(page.imported, 0, "Nothing imported yet")
    assert_eq(page.refused, 0, "and nothing refused")
    assert_eq(page.report_lines.size(), 0, "so there are no lines to show")
    var empty := page.find_child("PresetsImportEmpty", true, false) as Label
    assert_not_null(empty, "The page carries the line said before any import")
    if empty != null:
        assert_eq(empty.text, "Nothing imported yet.", "which says so in the painter's words")
    assert_not_null(page.find_child("PresetsImportButton", true, false), "and the import button is here now")
    page.free()


## The button is off the docker.
func test_the_docker_no_longer_carries_the_import() -> void:
    var docker := BrushPresetsDocker.new()
    assert_null(docker.find_child("ChooserImport", true, false), "The docker has no Import button any more")
    assert_not_null(docker.find_child("ChooserSave", true, false), "and still has Save as...")
    assert_not_null(docker.find_child("ChooserDelete", true, false), "and Delete")
    assert_not_null(docker.find_child("ChooserNew", true, false), "and New preset")

    # "with the docker's capture step answering the same keys minus that button".
    # The dump never named the button, so the keys are the same ones, and this
    # asserts that the removal took none of them with it.
    var reported: Array = docker.capture_state().keys()
    reported.sort()
    var wanted := REPORTED_KEYS.duplicate()
    wanted.sort()
    assert_eq(reported, wanted, "and the docker's dump block is the keys it always had")
    docker.free()


func test_the_door_says_so_when_the_page_is_not_open() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    assert_not_null(tree, "This test needs the real scene tree to look in")
    if tree == null:
        return
    var answer := SaBrushPresetsPage.capture_import(tree, {"import": "res://nothing.kpp"})
    assert_true(answer.contains("not open"), "A step with no page open says which door was shut: %s" % answer)
    assert_eq(SaBrushPresetsPage.capture_state(tree.root), {}, "and the dump block is empty rather than invented")
