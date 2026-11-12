## What Save As does with a name one of the shipped palettes already wears.
##
## A shipped `.tres` lives in the resource tree and a fork under the settings
## folder, so the two never collide on disk and `SaTheme.fork` would write a
## second "Sara Green" straight into the dropdown beside the first. It numbers
## instead, and a name of the painter's own is still written over, which is
## how a palette of theirs is updated.
##
## The number itself is pinned by the scenario rather than here. This suite runs
## against whatever settings folder the run has, which on a desktop run is the
## painter's real one, so the exact "2" is only true when nothing there already
## wears it. The shape is true either way, and
## `scenarios/colour-themes.json` reads the names out of an isolated folder.
extends "res://tests/test_framework.gd"

const SHIPPED_NAME := "Sara Green"

var _saved_theme: String = "default"
var _before: Array[String] = []


func before_each() -> void:
    _saved_theme = SaTheme.palette_id
    _before = SaTheme.custom_ids()
    SaTheme.use_named("default")


## Only the files this suite wrote, so a palette the folder already held is
## never removed by a test run.
func after_each() -> void:
    for id: String in SaTheme.custom_ids():
        if not _before.has(id):
            SaTheme.delete_custom(id)
    SaTheme.use_named(_saved_theme)


func _folded_names() -> Array[String]:
    var out: Array[String] = []
    for entry: Dictionary in SaTheme.available():
        out.append(String(entry["name"]).strip_edges().to_lower())
    return out


func test_a_shipped_name_is_numbered_rather_than_doubled() -> void:
    var id := SaTheme.fork(SHIPPED_NAME)

    assert_true(id != "custom:sara-green", "The fork does not take the shipped palette's own slug")
    assert_true(
        SaTheme.palette.display_name.begins_with(SHIPPED_NAME + " "),
        "It is called '%s' and a number, not '%s'" % [SHIPPED_NAME, SHIPPED_NAME]
    )
    var suffix := SaTheme.palette.display_name.trim_prefix(SHIPPED_NAME + " ")
    assert_true(suffix.is_valid_int() and suffix.to_int() >= 2, "and the number counts from two, not from one")

    var names := _folded_names()
    assert_eq(names.count(SHIPPED_NAME.to_lower()), 1, "The shipped palette is still the only plain '%s'" % SHIPPED_NAME)
    assert_true(names.has(SaTheme.palette.display_name.to_lower()), "and the fork is offered beside it")


func test_a_second_save_as_under_the_same_shipped_name_counts_on() -> void:
    var first := SaTheme.fork(SHIPPED_NAME)
    var first_name := SaTheme.palette.display_name
    var second := SaTheme.fork(SHIPPED_NAME)

    assert_true(second != first, "The second Save As writes a second file")
    assert_true(
        (
            SaTheme.palette.display_name.trim_prefix(SHIPPED_NAME + " ").to_int()
            > first_name.trim_prefix(SHIPPED_NAME + " ").to_int()
        ),
        "with the next number up"
    )
    var names := _folded_names()
    assert_true(names.has(first_name.to_lower()), "The first fork is still there")
    assert_true(names.has(SaTheme.palette.display_name.to_lower()), "and the second is beside it")


## The case a painter types is not the case the file is named from, so a shipped
## name in any case has to be numbered: "sara green" and "Sara Green" are one
## slug, and letting the lower-case one through would overwrite the other fork.
func test_the_match_against_a_shipped_name_ignores_case_and_space() -> void:
    assert_true(SaTheme.free_name("  sara green  ") != "  sara green  ", "Space and case do not get a name past the check")
    assert_true(SaTheme.free_name("SARA GREEN").begins_with("SARA GREEN "), "and the painter's own capitals are kept")
    assert_eq(SaTheme.free_name("Not A Shipped Palette"), "Not A Shipped Palette", "A name nobody ships is left alone")


func test_save_as_onto_your_own_palette_still_overwrites_it() -> void:
    var id := SaTheme.fork("Test Overwrite Me")
    assert_eq(id, "custom:test-overwrite-me", "The first Save As names the file")
    SaTheme.set_color("accent_primary", Color(0.9, 0.1, 0.2, 1.0))

    var again := SaTheme.fork("Test Overwrite Me")
    assert_eq(again, id, "Save As under the same name of your own writes the same file")
    var names := _folded_names()
    assert_eq(names.count("test overwrite me"), 1, "so the dropdown holds one of it, not two")

    var reloaded := ResourceLoader.load(SaTheme.custom_path(id), "SaPalette", ResourceLoader.CACHE_MODE_IGNORE) as SaPalette
    assert_not_null(reloaded, "and the file is still readable")
    assert_true(reloaded.accent_primary.is_equal_approx(Color(0.9, 0.1, 0.2, 1.0)), "carrying what was on screen")
