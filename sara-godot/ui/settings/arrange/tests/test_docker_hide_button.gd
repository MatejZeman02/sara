## Preferences > Layouts and dockers > Every docker, the hide-button switch,
## and the setting it writes.
##
## It is not drawn on every docker's page, and a suite holds that no docker's
## list carries it.
## The button itself is proved by `scenarios/docker-hide.json`, because a
## DockerWindow in the tree maps a real OS window and hangs a headless run.
## What is left here is the half a capture cannot see: that the switch writes
## one setting, that a fresh profile has it on, and that the
## Top Menu Bar page keeps its own readout instead.
extends "res://tests/test_framework.gd"

var _saved: bool


func before_each() -> void:
    _saved = SaSettings.docker_hide_button
    SaSettings.docker_hide_button = false


## Restores what this suite found rather than the default, so a run does not
## quietly reset a preference the person has set.
func after_each() -> void:
    SaSettings.docker_hide_button = _saved


## `before_each` sets the switch off so the writes below start from a known
## state, so the default is read from a fresh set of values rather than the page.
func test_a_fresh_profile_has_the_hide_button() -> void:
    var page := SaDockersPage.new()
    var check := _switch(page)
    assert_true(check != null, "Layouts and dockers carries the hide switch")
    var fresh := SaSettingsValues.new()
    assert_true(fresh.docker_hide_button, "and a fresh profile has it on, as the default")
    fresh.free()
    page.free()


func test_the_switch_writes_the_setting() -> void:
    var page := SaDockersPage.new()
    var check := _switch(page)
    check.button_pressed = true
    assert_true(SaSettings.docker_hide_button, "Switching it on writes the setting")
    check.button_pressed = false
    assert_false(SaSettings.docker_hide_button, "and switching it off writes it back")
    page.free()


## The icon is on every docker, so there is one setting behind one switch. A page opened after the setting
## moved elsewhere, a scenario's
## `prefs` or the migration, has to show the value it moved to, or the painter
## is told the icon is off while it is on everywhere.
func test_a_page_opened_later_reads_the_setting() -> void:
    SaSettings.docker_hide_button = true
    var page := SaDockersPage.new()
    assert_true(_switch(page).button_pressed, "The page shows the switch already on")
    page.free()


func test_the_top_bar_page_has_no_hide_switch() -> void:
    var page := SaTopBarPage.new()
    assert_true(_switch(page) == null, "The top bar is not a docker, so it keeps its row-width readout")
    page.free()


func _switch(page: Node) -> CheckButton:
    return page.find_child("HideButtonCheck", true, false) as CheckButton


## The capture surface the scenario reads.
##
## `describe_rows` must not walk the drag list alone, or the one control that is
## not a draggable row is in no state dump and no scenario can click it. The
## switch is a declared row of Layouts and dockers now, so `page_row` reaches it
## by its key and the page's own `describe` carries its sentence.
func test_the_page_reports_the_row_by_its_key() -> void:
    var page := SaDockersPage.new()
    var row := page.page.row(&"hide_button")
    assert_not_null(row, "The row answers to the key a scenario names it by")
    assert_true(row.explanation.contains("closes it"), "with the sentence that says what the button does")
    assert_true(row.control == _switch(page), "and page_row reaches the same switch a hand does")
    page.free()
