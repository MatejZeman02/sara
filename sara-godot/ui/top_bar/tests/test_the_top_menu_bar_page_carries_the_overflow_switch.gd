## The Top Menu Bar page carries the overflow's switch.
##
## The sentinel keeps its own switch, the second row, and the overflow has one
## beside it. The overflow is the default.
## This suite reads the page's row the way the search and a painter reach it, flips it, and asserts the bar's option follows
## and is written to the profile.
extends "res://tests/test_framework.gd"

static var scratch_profile: String = SaDataRoot.path("test_r1_overflow_page.cfg")

var _saved_path: String = ""


func before_each() -> void:
    _saved_path = SaSettings.settings_path
    SaSettings.settings_path = ProjectSettings.globalize_path(scratch_profile)
    _remove_profile()
    SaSettings.load_settings()
    SaTopBarOverflow.register_option()


func after_each() -> void:
    _remove_profile()
    SaSettings.settings_path = _saved_path
    SaSettings.load_settings()


func _remove_profile() -> void:
    for suffix: String in ["", ".bak", ".broken"]:
        var path := ProjectSettings.globalize_path(scratch_profile) + suffix
        if FileAccess.file_exists(path):
            DirAccess.remove_absolute(path)


func _check(page: Control) -> CheckButton:
    return page.find_child("OverflowCheck", true, false) as CheckButton


func _row(page: Control) -> Control:
    for node in page.find_children("*", "HBoxContainer", true, false):
        var row := node as Control
        if row != null and String(row.get_meta(SaSettingsRows.TITLE_META, "")) == "Overflow":
            return row
    return null


func _flip(check: CheckButton, on: bool) -> void:
    check.button_pressed = on
    check.toggled.emit(on)


## On for a new profile, and the page says so.
func test_the_switch_reads_on_by_default() -> void:
    var page := SaTopBarPage.new()
    var check := _check(page)
    assert_not_null(check, "the page carries the overflow's switch")
    assert_true(SaTopBarOverflow.enabled(), "a new profile overflows")
    assert_true(check.button_pressed, "and the switch reads on")
    page.free()


## Off and on again through the switch, and the bar's option and the profile
## follow each time.
func test_the_switch_writes_the_bar_option() -> void:
    var page := SaTopBarPage.new()
    var check := _check(page)
    _flip(check, false)
    assert_false(SaTopBarOverflow.enabled(), "off, the bar scrolls instead")
    assert_eq(SaSettings.get_docker_option("TopMenuBar", TopMenuBar.OVERFLOW_OPTION), false, "the stored option is off")
    var stored := ConfigFile.new()
    assert_eq(stored.load(SaSettings.settings_path), OK, "the switch wrote the profile")
    _flip(check, true)
    assert_true(SaTopBarOverflow.enabled(), "on again, the bar overflows")
    page.free()


## A page opened after the option was turned off reads it as off, which is the
## binding reading rather than the default.
func test_a_fresh_page_reads_the_stored_option() -> void:
    SaSettings.set_docker_option("TopMenuBar", TopMenuBar.OVERFLOW_OPTION, false)
    var page := SaTopBarPage.new()
    assert_false(_check(page).button_pressed, "the switch reads off")
    page.free()


## Found by the words a painter would type, the row's title and its sentence.
func test_the_search_reaches_the_switch() -> void:
    var page := SaTopBarPage.new()
    var row := _row(page)
    assert_not_null(row, "the switch is a titled row")
    var haystack := SaSettingsSearch.row_haystack(row)
    for word: String in ["overflow", "fit", "scroll"]:
        assert_true(haystack.contains(word), "a search for '%s' reaches the switch: %s" % [word, haystack])
    page.free()
