## The painter's own palettes: a swatch change forks a shipped palette
## into the settings folder, the fork is applied at once and survives a
## reload from disk, and a shipped palette is never written or deleted.
extends "res://tests/test_framework.gd"

var _saved_theme: String = "default"
var _saved_path: String = ""


func before_each() -> void:
    _saved_theme = SaTheme.palette_id
    _saved_path = SaSettings.settings_path
    SaSettings.settings_path = ProjectSettings.globalize_path(SaDataRoot.path("test_custom_themes.cfg"))
    _remove_forks()


func after_each() -> void:
    _remove_forks()
    SaSettings.settings_path = _saved_path
    SaTheme.use_named(_saved_theme)
    DirAccess.remove_absolute(ProjectSettings.globalize_path(SaDataRoot.path("test_custom_themes.cfg")))


## Every fork this suite makes, gone, so the settings folder the gate shares
## with the captures keeps nothing a test wrote. `delete_custom` moves a file
## into `themes/deleted/` rather than removing it, so the folder it
## moves them to is swept as well, by the two stems this suite can write.
func _remove_forks() -> void:
    for id in SaTheme.custom_ids():
        if id.begins_with(SaTheme.CUSTOM_PREFIX + "test-"):
            SaTheme.delete_custom(id)
    var kept := DirAccess.open(SaTheme.deleted_dir())
    if kept == null:
        return
    for file_name in kept.get_files():
        if file_name.begins_with("test-") or file_name.begins_with("sara-green-(custom)"):
            kept.remove(file_name)


func test_a_palette_round_trips_through_its_file() -> void:
    SaTheme.use_named("default")
    var id := SaTheme.fork("Test Round Trip")
    assert_eq(id, "custom:test-round-trip", "The name is the file name")
    assert_true(FileAccess.file_exists(SaTheme.custom_path(id)), "and the file is in the settings folder")
    assert_eq(SaTheme.palette_id, id, "The fork is active")
    assert_true(SaTheme.set_color("accent_primary", Color(0.1, 0.2, 0.9, 1.0)), "A swatch writes into it")

    var reloaded := ResourceLoader.load(SaTheme.custom_path(id), "SaPalette", ResourceLoader.CACHE_MODE_IGNORE) as SaPalette
    assert_not_null(reloaded, "The file loads back as a palette")
    assert_eq(reloaded.display_name, "Test Round Trip", "with its name")
    assert_true(reloaded.accent_primary.is_equal_approx(Color(0.1, 0.2, 0.9, 1.0)), "and the colour that was set")
    assert_true(reloaded.bg_primary.is_equal_approx(load(SaTheme.PALETTES["default"]).bg_primary), "and the rest untouched")

    SaTheme.use_named("default")
    SaTheme.use_named(id)
    assert_true(SaTheme.palette.accent_primary.is_equal_approx(Color(0.1, 0.2, 0.9, 1.0)), "Switching back reads the file")
    var names: Array = []
    for entry: Dictionary in SaTheme.available():
        names.append(entry["id"])
    assert_true(names.has(id), "and the dropdown offers it")


func test_a_shipped_palette_is_never_written_or_deleted() -> void:
    SaTheme.use_named("krita")
    var before: Color = SaTheme.palette.accent_primary
    assert_false(SaTheme.set_color("accent_primary", Color.RED), "A swatch on a shipped palette is refused")
    assert_eq(SaTheme.palette.accent_primary, before, "and nothing changed")
    assert_false(SaTheme.delete_custom("krita"), "A shipped palette cannot be deleted")
    assert_eq(SaTheme.builtin().size(), SaTheme.PALETTES.size(), "and every shipped palette is still offered")


func test_the_page_forks_on_the_first_swatch_and_applies_at_once() -> void:
    SaSettings.theme_name = "default"
    var page := SaColorThemesPage.new()
    page.set_swatch("accent_primary", Color(0.9, 0.1, 0.1, 1.0))
    assert_eq(SaTheme.palette_id, "custom:sara-green-(custom)", "The first swatch forks the shipped palette")
    assert_eq(SaSettings.theme_name, SaTheme.palette_id, "and the setting follows, so a restart keeps it")
    assert_true(SaTheme.palette.accent_primary.is_equal_approx(Color(0.9, 0.1, 0.1, 1.0)), "with the colour applied")
    var style := SaTheme.make_drag_bar_style()
    assert_true(style.bg_color.is_equal_approx(Color(0.9, 0.1, 0.1, 1.0)), "which the bar's drag bars now draw")
    assert_true(page.delete_button.disabled == false, "and Delete is offered")

    page.set_swatch("text_muted", Color.WHITE)
    assert_eq(SaTheme.palette_id, "custom:sara-green-(custom)", "A second swatch edits the same fork")

    # The answer rather than the press, because the press only asks.
    # The question itself, both its answers and where the file lands are
    # `ui/themes/tests/test_a_theme_delete_asks_first_and_keeps_the_file.gd`,
    # which has a tree to open a window in.
    page._on_delete_answered(SaColorThemesPage.DELETE_CONFIRM, SaTheme.palette_id)
    assert_eq(SaTheme.palette_id, "default", "Answering Delete removes it and falls back to the default")
    assert_false(
        FileAccess.file_exists(SaTheme.custom_path("custom:sara-green-(custom)")), "and the palettes folder is rid of it"
    )
    page.free()


func test_the_swatches_are_the_palette_s_own_fields() -> void:
    var keys := SaTheme.color_keys(SaPalette.new())
    assert_true(keys.has("bg_primary"), "A background is a swatch")
    assert_true(keys.has("accent_primary"), "and an accent")
    assert_false(keys.has("display_name"), "and the name is not")
    var page := SaColorThemesPage.new()
    assert_eq(page._swatches.size(), keys.size(), "One swatch per colour field")
    page.free()
