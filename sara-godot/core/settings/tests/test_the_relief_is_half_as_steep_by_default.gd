## The relief is drawn half as steep by default.
##
## A painter's note: "all the impasto stuff is too strong on a default
## settings." The height a stroke lays stays in the millimetres it was set in,
## and what softens is the view's scale on the slope, Preferences › Display ›
## Relief strength, 4 before and 2 now. A profile still holding the old 4 reads
## 2 once, by the version-19 step of `SaSettingsMigrations`, and a strength a
## painter chose stays.
##
## What the four strengths look like on the default noise brush's stroke, one
## pass and twenty, is the record of
## `scenarios/the-relief-is-half-as-steep-by-default.json`.
extends "res://tests/test_framework.gd"

static var scratch_path: String = SaDataRoot.path("test_relief_default_scratch.cfg")

## The version a profile written the day before the step names.
const BEFORE_THE_STEP: int = 18

var _saved_strength: float


func before_each() -> void:
    _saved_strength = SaSettings.relief_strength


## Restores what this suite found, so a run leaves the person's profile alone.
func after_each() -> void:
    SaSettings.relief_strength = _saved_strength


func test_a_new_profile_draws_the_relief_at_two() -> void:
    var values := SaSettingsValues.new()
    assert_almost_eq(values.relief_strength, 2.0, 0.0001, "A profile that never named the key draws the relief at 2")
    values.free()


func test_a_stored_four_reads_two_after_its_migration() -> void:
    var old := _profile_holding(4.0)
    SaSettingsMigrations.apply(old, BEFORE_THE_STEP)
    assert_almost_eq(float(old.get_value("ui", "relief_strength")), 2.0, 0.0001, "The old default of 4 reads 2")
    assert_eq(old.get_value("meta", "version"), SaSettingsMigrations.SETTINGS_VERSION, "and is stamped with this build")


func test_a_stored_six_stays() -> void:
    var chosen := _profile_holding(6.0)
    SaSettingsMigrations.apply(chosen, BEFORE_THE_STEP)
    assert_almost_eq(float(chosen.get_value("ui", "relief_strength")), 6.0, 0.0001, "A strength a painter chose stays")


## A profile edited by hand can hold the whole number, which `ConfigFile`
## reads back as an int.
func test_a_whole_four_written_by_hand_moves_too() -> void:
    var old := ConfigFile.new()
    old.set_value("meta", "version", BEFORE_THE_STEP)
    old.set_value("ui", "relief_strength", 4)
    SaSettingsMigrations.apply(old, BEFORE_THE_STEP)
    assert_almost_eq(float(old.get_value("ui", "relief_strength")), 2.0, 0.0001, "A 4 written without its point reads 2")


func test_a_profile_that_never_named_it_gains_no_key() -> void:
    var old := ConfigFile.new()
    old.set_value("meta", "version", BEFORE_THE_STEP)
    SaSettingsMigrations.apply(old, BEFORE_THE_STEP)
    assert_false(old.has_section_key("ui", "relief_strength"), "Nothing is written, so the read finds the default")


## Through the whole load, so the read after the migration is the one proved,
## both ways: a version-18 profile at 4 loads at 2, and a 4 chosen since, stored
## under this build's version, loads at 4.
func test_a_profile_on_disk_loads_as_the_step_says() -> void:
    assert_almost_eq(_loaded(_profile_holding(4.0)), 2.0, 0.0001, "A version-18 profile at 4 loads at 2")
    var chosen := _profile_holding(4.0)
    chosen.set_value("meta", "version", SaSettingsMigrations.SETTINGS_VERSION)
    assert_almost_eq(_loaded(chosen), 4.0, 0.0001, "and a 4 chosen under this build stays 4")


func _profile_holding(strength: float) -> ConfigFile:
    var config := ConfigFile.new()
    config.set_value("meta", "version", BEFORE_THE_STEP)
    config.set_value("ui", "relief_strength", strength)
    return config


## The strength *config* loads at, read from a scratch file through
## `SaSettings.load_settings`, and then the runner's own file read again, so
## every other value the scratch profile loaded is the runner's once more.
func _loaded(config: ConfigFile) -> float:
    var path := ProjectSettings.globalize_path(scratch_path)
    var saved_path: String = SaSettings.settings_path
    config.save(path)
    SaSettings.settings_path = path
    SaSettings.load_settings()
    var strength: float = SaSettings.relief_strength
    SaSettings.settings_path = saved_path
    SaSettings.load_settings()
    DirAccess.remove_absolute(path)
    return strength
