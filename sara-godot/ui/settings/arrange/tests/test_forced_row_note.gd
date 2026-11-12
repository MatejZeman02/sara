## Preferences says when the second row is on against the switch.
##
## The bar keeps the second row whenever one row would not hold the
## controls, and it kept it silently: at 1920 the first row wants 1163 logical
## pixels of the 1030 it has, so a painter who turned the switch off got two
## rows anyway. `second_row_forced_by` read 133 in the state dump and the only
## surface carrying the switch said nothing, which reads as a broken setting.
##
## The assembled page is `scenarios/second-row-switch-says-nothing.json`,
## whose readout goes from two row widths to two row widths and the sentence and
## back as the switch moves. What is here is the rule the sentence follows.
extends "res://tests/test_framework.gd"


func _page() -> SaTopBarPage:
    return SaTopBarPage.new()


func test_nothing_is_said_while_the_switch_is_on() -> void:
    var was := SaSettings.second_row
    SaSettings.second_row = true
    var page := _page()
    assert_eq(page.forced_second_row_note(133.0), "", "A switch that is on is not being overridden")
    page.free()
    SaSettings.second_row = was


func test_nothing_is_said_when_one_row_fits() -> void:
    var was := SaSettings.second_row
    SaSettings.second_row = false
    var page := _page()
    assert_eq(page.forced_second_row_note(0.0), "", "A switch that is off and honoured says nothing either")
    page.free()
    SaSettings.second_row = was


## The case the filing is about, and the number is the bar's own rather than
## anything this page works out.
func test_the_overrun_is_said_with_its_number() -> void:
    var was := SaSettings.second_row
    SaSettings.second_row = false
    var page := _page()
    var note := page.forced_second_row_note(133.0)
    assert_true(note.contains("133"), "The sentence carries the pixels it is short by: %s" % note)
    assert_true(note.contains("second row"), "and says what happened because of them")
    page.free()
    SaSettings.second_row = was


## A negative reading is not an overrun, and `TopMenuBar` resets the field to 0.0
## on every layout, so this is the shape of the guard rather than a case anybody
## has seen.
func test_a_reading_of_nothing_says_nothing() -> void:
    var was := SaSettings.second_row
    SaSettings.second_row = false
    var page := _page()
    assert_eq(page.forced_second_row_note(-12.0), "", "Nothing is said about a row that did not overrun")
    page.free()
    SaSettings.second_row = was
