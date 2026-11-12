## Reset to shipped on a docker's Elements… page puts that docker's order and
## hidden elements back as its module registered them, and leaves every other
## docker and every per-docker option alone.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The rule: a Reset to shipped button on each docker's
## Preferences page beside Hide undoes that docker's edits only. The
## categories here are a module's, registered through the door a module uses,
## so the suite proves the reset of what a module registered rather than of the
## skeleton's own defaults, which the scenario
## `reset-to-shipped-on-a-docker-s-elements-page-undoes-that-docker-s-edits-only.json`
## shows on the Colour Picker.
extends "res://tests/test_framework.gd"

const PROBE := "Probe"
const OTHER := "Other"
const OPTION := "lines"
const REGISTERED := ["Drag Handle", "Resizer", "Alpha", "Beta", "Gamma"]


func before_each() -> void:
    SaSettings.register_layout_category(PROBE, "Reset Probe", REGISTERED)
    # An element registered hidden after the category, the way the bar adds a
    # tool's option, so a fresh profile hides it and the reset has to as well.
    SaSettings.register_layout_element(PROBE, "Delta", "Delta", true)
    SaSettings.register_layout_category(OTHER, "Reset Other", REGISTERED)
    SaSettings.register_docker_option(
        PROBE, OPTION, {"title": "Lines", "kind": SaSettingsLayout.OPTION_COUNT, "min": 1, "max": 9, "default": 1}
    )


func after_each() -> void:
    for category: String in [PROBE, OTHER]:
        SaSettings.reset_layout_category(category)
        SaSettings.unregister_layout_category(category)
    SaSettings.unregister_layout_element(PROBE, "Delta")
    SaSettings.unregister_docker_option(PROBE, OPTION)
    var key := PROBE + "_" + OPTION
    if SaSettings.config.has_section_key("profile_docker_option", key):
        SaSettings.config.erase_section_key("profile_docker_option", key)
    SaSettings.layout_docker_options.erase(PROBE)
    SaSettings.save_settings()


## The probe moved and switched, the other category moved too, and an option
## set, which is what the reset has to tell apart.
func _edit_both() -> void:
    SaSettings.set_layout_order(PROBE, ["Drag Handle", "Resizer", "Gamma", "Delta", "Beta", "Alpha"])
    SaSettings.set_element_visible(PROBE, "Alpha", false)
    SaSettings.set_element_visible(PROBE, "Delta", true)
    SaSettings.set_layout_order(OTHER, ["Drag Handle", "Resizer", "Gamma", "Beta", "Alpha"])
    SaSettings.set_element_visible(OTHER, "Beta", false)
    SaSettings.set_docker_option(PROBE, OPTION, 4)


func test_the_reset_puts_back_what_the_module_registered() -> void:
    var fresh := SaSettings.get_layout_order(PROBE)
    assert_eq(fresh, ["Drag Handle", "Resizer", "Alpha", "Beta", "Gamma", "Delta"], "a fresh profile's order")
    _edit_both()
    SaSettings.reset_layout_category(PROBE)
    assert_eq(SaSettings.get_layout_order(PROBE), fresh, "the order is the one the module registered")
    assert_true(SaSettings.get_element_visible(PROBE, "Alpha"), "the element switched off is shown again")
    assert_false(SaSettings.get_element_visible(PROBE, "Delta"), "the one registered hidden is hidden again")
    assert_false(SaSettings.config.has_section_key("profile_order", PROBE), "the profile keeps no order for it")
    assert_false(SaSettings.config.has_section_key("profile_visibility", PROBE + "_Alpha"), "nor a switch")


func test_every_other_docker_and_every_option_stay() -> void:
    _edit_both()
    SaSettings.reset_layout_category(PROBE)
    assert_eq(
        SaSettings.get_layout_order(OTHER),
        ["Drag Handle", "Resizer", "Gamma", "Beta", "Alpha"],
        "the other docker keeps the order it was given"
    )
    assert_false(SaSettings.get_element_visible(OTHER, "Beta"), "and the element it hid")
    assert_eq(SaSettings.get_docker_option(PROBE, OPTION), 4, "the docker's own option keeps its value")


## A reset that lived in memory alone would come back at the next launch.
func test_the_reset_survives_a_reload() -> void:
    _edit_both()
    SaSettings.reset_layout_category(PROBE)
    SaSettings.load_settings()
    assert_eq(SaSettings.get_layout_order(PROBE), ["Drag Handle", "Resizer", "Alpha", "Beta", "Gamma", "Delta"], "read back")
    assert_true(SaSettings.get_element_visible(PROBE, "Alpha"), "with the element shown")
    assert_false(SaSettings.get_element_visible(OTHER, "Beta"), "and the other docker's edit kept")


func test_the_reset_tells_the_dockers() -> void:
    var heard: Array[int] = [0]
    var count := func() -> void: heard[0] += 1
    SaSettings.profile_changed.connect(count)
    SaSettings.reset_layout_category(PROBE)
    SaSettings.profile_changed.disconnect(count)
    assert_eq(heard[0], 1, "one profile_changed, which every docker relays its layout on")


## The button stands at the foot of the list, and pressing it draws the list
## again in the order it put back.
func test_the_page_draws_the_button_and_redraws_the_list() -> void:
    _edit_both()
    var page := SaLayoutPage.new(PROBE)
    var reset := page.page.row(&"reset")
    assert_not_null(reset, "the Elements… page carries Reset to shipped")
    if reset == null:
        page.free()
        return
    assert_eq(page.row_for("Gamma").get_index(), 2, "the list opens in the edited order")
    (reset.control as Button).pressed.emit()
    var order: Array[String] = []
    for element: String in ["Drag Handle", "Resizer", "Alpha", "Beta", "Gamma", "Delta"]:
        order.append("%s %d %s" % [element, page.row_for(element).get_index(), page.row_for(element).check_button.button_pressed])
    assert_eq(
        order,
        ["Drag Handle 0 true", "Resizer 1 true", "Alpha 2 true", "Beta 3 true", "Gamma 4 true", "Delta 5 false"],
        "the list is redrawn as registered, Delta switched off"
    )
    assert_eq(SaSettings.get_layout_order(OTHER)[2], "Gamma", "and the other docker is untouched")
    page.free()


## The top bar's page is no docker's, and a category nothing ships has nothing
## to go back to, which is what a composed docker will be.
func test_no_button_where_nothing_ships_or_no_docker_is() -> void:
    var bar := SaTopBarPage.new()
    assert_null(bar.page.row(&"reset"), "the top bar's page has none")
    bar.free()
    var nothing := SaLayoutPage.new("Unregistered")
    assert_null(nothing.page.row(&"reset"), "nor a page for a category nothing registered")
    nothing.free()
    assert_true(SaSettings.layout_ships("ColorPicker"), "a shipped docker ships")
    assert_true(SaSettings.layout_ships(PROBE), "and so does a module's")
    assert_false(SaSettings.layout_ships("Unregistered"), "and nothing else does")
