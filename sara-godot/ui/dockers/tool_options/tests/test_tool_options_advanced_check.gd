## The Advanced check on the Tool Options docker: above the
## rows, and one switch with Preferences > General's Advanced options row.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **The check and the row, not the rows they show.** Which rows an advanced
## flag hides is answered by `tool_option_controls.gd`, so what
## is stated here is that the two controls write one setting and follow it.
## `scenarios/the-advanced-check-at-hand-on-the-tool-options-docker.json` is
## where a click on the docker's check is shown bringing the rows in.
##
## Nothing here enters the tree, because the runner's suites are not nodes and
## the docker suites before this one build their controls on a bare host. The
## header connects its event at construction for exactly that reason.
extends "res://tests/test_framework.gd"

const ControlWalker := preload("res://harness/controls/sa_control_walker.gd")

var _was: bool = false


func before_each() -> void:
    _was = SaSettings.advanced_options
    SaSettings.advanced_options = false


func after_each() -> void:
    SaSettings.advanced_options = _was


func test_the_docker_puts_the_check_between_its_title_and_its_rows() -> void:
    var docker := ToolOptionsDocker.new()
    var vbox := docker.drag_handle.get_parent()
    var order: Array[String] = []
    for child in vbox.get_children():
        order.append(String(child.name))

    assert_eq(order.find("ToolOptionsHeader"), order.find("DragHandle") + 1, "The header sits under the title bar")
    assert_eq(order.find("Scroll"), order.find("ToolOptionsHeader") + 1, "and above the scroll that holds the rows")
    assert_not_null(docker.header.check, "It holds a check")
    assert_eq(String(docker.header.check.name), ToolOptionsHeader.CHECK_NAME, "under the name a scenario clicks")
    assert_eq(docker.header.check.text, "Advanced", "labelled as a scenario looks for it")
    docker.free()


func test_clicking_the_check_writes_the_setting() -> void:
    var header := ToolOptionsHeader.new()
    header.check.button_pressed = true
    assert_true(SaSettings.advanced_options, "Ticked, the setting is on")
    header.check.button_pressed = false
    assert_false(SaSettings.advanced_options, "and unticked it is off again")
    header.free()


func test_the_check_follows_the_setting_when_something_else_writes_it() -> void:
    var header := ToolOptionsHeader.new()
    SaSettings.advanced_options = true
    assert_true(header.check.button_pressed, "Another writer turned it on and the check followed")
    SaSettings.advanced_options = false
    assert_false(header.check.button_pressed, "and off")
    header.free()


func test_the_preferences_row_and_the_docker_check_are_one_switch() -> void:
    var header := ToolOptionsHeader.new()
    header.check.button_pressed = true
    var page := SaGeneralPage.new()
    var row := page.find_child("AdvancedOptionsCheck", true, false) as CheckButton
    assert_not_null(row, "Preferences, General has its Advanced options check")
    assert_true(row.button_pressed, "and it reads on after the docker's check was ticked")

    row.button_pressed = false
    assert_false(SaSettings.advanced_options, "Unticking the Preferences row turns the setting off")
    assert_false(header.check.button_pressed, "and the docker's check follows it")
    page.free()
    header.free()


func test_the_dump_reads_both_checks_and_the_setting() -> void:
    var host := VBoxContainer.new()
    var header := ToolOptionsHeader.new()
    host.add_child(header)
    header.check.button_pressed = true
    # Built after the tick, the way a painter opens Preferences after clicking
    # the docker's check: the row reads the setting when its page is built.
    host.add_child(SaGeneralPage.new())
    var state := _checks(host)
    assert_true(bool(state["setting"]), "The setting is on")
    assert_eq(state["docker_check"], true, "the docker's check says so")
    assert_eq(state["preferences_check"], true, "and so does the Preferences row")
    host.free()


func test_a_closed_preferences_window_reads_as_no_check_rather_than_as_off() -> void:
    var host := VBoxContainer.new()
    host.add_child(ToolOptionsHeader.new())
    var state := _checks(host)
    assert_true(state["preferences_check"] == null, "No Preferences row built is null, not false")
    assert_eq(state["docker_check"], false, "while the docker's check is there and off")
    host.free()


## What the dump's `advanced_checks` reads, built the way the state report
## builds it, through the walker rather than the header's own hook.
func _checks(host: Node) -> Dictionary:
    return {
        "setting": SaSettings.advanced_options,
        "docker_check": ControlWalker.read(host, ToolOptionsHeader.CHECK_NAME),
        "preferences_check": ControlWalker.read(host, "AdvancedOptionsCheck"),
    }
