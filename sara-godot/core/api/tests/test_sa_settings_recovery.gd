## A profile that fails to parse is kept, not overwritten.
##
## `ConfigFile.load` fails the same way for a missing file and a truncated one,
## and the recovery branch wrote defaults straight over both before the window
## appeared. Now a save keeps the previous file as a backup, an unreadable
## profile is moved aside as `.broken`, the backup is tried, and the painter is
## told either way.
extends "res://tests/test_framework.gd"

static var scratch_path: String = SaDataRoot.path("test_settings_recovery.cfg")

var _saved_path: String = ""


func before_each() -> void:
    SaProblems.announce = false
    SaProblems.detach_sink()
    SaProblems.pending = PackedStringArray()
    _saved_path = SaSettings.settings_path
    SaSettings.settings_path = ProjectSettings.globalize_path(scratch_path)
    _remove_all()


func after_each() -> void:
    _remove_all()
    SaSettings.settings_path = _saved_path
    SaSettings.load_settings()
    SaProblems.pending = PackedStringArray()
    SaProblems.announce = true


func _remove_all() -> void:
    for suffix: String in ["", SaSettings.BACKUP_SUFFIX, SaSettings.BROKEN_SUFFIX, ".tmp"]:
        var path := ProjectSettings.globalize_path(scratch_path) + suffix
        if FileAccess.file_exists(path):
            DirAccess.remove_absolute(path)


func _exists(suffix: String) -> bool:
    return FileAccess.file_exists(ProjectSettings.globalize_path(scratch_path) + suffix)


func _write_garbage() -> void:
    var file := FileAccess.open(ProjectSettings.globalize_path(scratch_path), FileAccess.WRITE)
    file.store_string("[ui]\ntonemap_knee = {")
    file.close()


func test_a_save_keeps_the_previous_file_as_the_backup() -> void:
    SaSettings.load_settings()
    assert_true(_exists(""), "A missing profile is written with defaults")
    # Each setter saves on its own, so these are two saves.
    SaSettings.tonemap_knee = 0.25
    SaSettings.tonemap_knee = 0.3

    var backup := ConfigFile.new()
    assert_eq(backup.load(ProjectSettings.globalize_path(scratch_path) + SaSettings.BACKUP_SUFFIX), OK, "The backup parses")
    assert_almost_eq(backup.get_value("ui", "tonemap_knee", 0.0), 0.25, 0.0001, "and is the file the last save replaced")
    var current := ConfigFile.new()
    current.load(ProjectSettings.globalize_path(scratch_path))
    assert_almost_eq(current.get_value("ui", "tonemap_knee", 0.0), 0.3, 0.0001, "while the profile itself is current")
    assert_false(_exists(".tmp"), "and no temporary is left behind")


func test_a_truncated_profile_is_kept_aside_and_the_backup_restored() -> void:
    SaSettings.load_settings()
    SaSettings.tonemap_knee = 0.25
    SaSettings.save_settings()
    SaSettings.save_settings()
    _write_garbage()

    SaSettings.load_settings()
    assert_almost_eq(SaSettings.tonemap_knee, 0.25, 0.0001, "The backup's values are in use")
    assert_true(_exists(SaSettings.BROKEN_SUFFIX), "The unreadable file is kept")
    var kept := FileAccess.get_file_as_string(ProjectSettings.globalize_path(scratch_path) + SaSettings.BROKEN_SUFFIX)
    assert_true(kept.ends_with("{"), "as it was, so what broke it can be seen")
    assert_true(_exists(""), "and the profile is written back from the backup")
    assert_eq(SaProblems.pending.size(), 1, "The painter is told")
    assert_true(SaProblems.pending[0].contains("restored"), "that the previous version is what they have")


func test_a_truncated_profile_with_no_backup_falls_back_to_defaults() -> void:
    _write_garbage()
    SaSettings.load_settings()
    assert_almost_eq(SaSettings.ui_scale, 1.0, 0.0001, "Defaults are in use")
    assert_true(_exists(SaSettings.BROKEN_SUFFIX), "The unreadable file is kept")
    assert_true(_exists(""), "and a fresh profile is written")
    assert_eq(SaProblems.pending.size(), 1, "The painter is told")
    assert_true(SaProblems.pending[0].contains("Defaults"), "that they are on defaults, and where their file went")


func test_a_missing_profile_is_not_a_problem() -> void:
    SaSettings.load_settings()
    assert_true(SaProblems.pending.is_empty(), "A first launch has nothing to report")
    assert_false(_exists(SaSettings.BROKEN_SUFFIX), "and nothing to keep aside")
