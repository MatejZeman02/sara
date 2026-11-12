## The fifth font in Preferences is the engine's fallback, and
## Godot 4.7.2 draws it as Open Sans SemiBold, so the row says Open Sans. The
## id stays `noto-sans`, because painters' settings files hold it, and a file
## that holds it still loads and picks that face.
extends "res://tests/test_framework.gd"

const AUTOLOAD := "res://core/settings/sa_settings.gd"

## The settings suite's fixture, which holds `font="noto-sans"`.
const FIXTURE := "res://tests/data/every_key_moved.cfg"
static var scratch_path: String = SaDataRoot.path("test_settings.cfg")


func _cleanup() -> void:
    var scratch := ProjectSettings.globalize_path(scratch_path)
    for suffix: String in ["", SaSettingsFile.BACKUP_SUFFIX]:
        DirAccess.remove_absolute(scratch + suffix)


func test_the_fifth_row_names_open_sans_under_the_old_id() -> void:
    var rows := SaFonts.available()
    assert_eq(rows.size(), 5, "five families on offer")
    assert_eq(rows[4]["id"], "noto-sans", "the fifth keeps the id the settings hold")
    var name: String = rows[4]["name"]
    assert_true(name.contains("Open Sans"), "and is named after Open Sans: %s" % name)
    assert_false(name.contains("Noto"), "and not after Noto")


func test_the_engine_face_is_the_one_the_row_names() -> void:
    var face := ThemeDB.fallback_font.get_font_name()
    assert_true(face.begins_with("Open Sans"), "the engine's fallback is Open Sans: %s" % face)
    assert_true(SaFonts.regular("noto-sans") == ThemeDB.fallback_font, "and the row hands it back")


func test_a_settings_file_with_the_old_id_picks_the_engine_face() -> void:
    var fixture := ConfigFile.new()
    assert_eq(fixture.load(FIXTURE), OK, "the fixture parses")
    assert_eq(fixture.get_value("theme", "font"), "noto-sans", "and holds the old id")
    var scratch := ProjectSettings.globalize_path(scratch_path)
    DirAccess.remove_absolute(scratch)
    DirAccess.copy_absolute(ProjectSettings.globalize_path(FIXTURE), scratch)
    var settings: Node = load(AUTOLOAD).new()
    settings.settings_path = scratch
    settings.load_settings()
    var id: String = settings.ui_font
    settings.free()
    assert_eq(id, "noto-sans", "the loaded settings keep it")
    assert_true(SaFonts.regular(id) == ThemeDB.fallback_font, "and it picks the engine's face")
