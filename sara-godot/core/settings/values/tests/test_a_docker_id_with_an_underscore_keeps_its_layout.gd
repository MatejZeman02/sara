## A docker whose id holds an underscore keeps its stored visibilities and
## options across a reload of the profile.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The profile stores both as `category_element`, and the reader split the key
## at its first underscore, so `b2_probe_docker` came back as `b2` and the
## docker read its defaults on every launch.
extends "res://tests/test_framework.gd"

const DOCKER := "b2_probe_docker"
const OPTION := "max_lines"


func after_each() -> void:
    SaSettings.unregister_layout_category(DOCKER)
    SaSettings.unregister_docker_option(DOCKER, OPTION)
    for section: String in ["profile_visibility", "profile_docker_option"]:
        if not SaSettings.config.has_section(section):
            continue
        for key: String in SaSettings.config.get_section_keys(section):
            if key.begins_with("b2_"):
                SaSettings.config.erase_section_key(section, key)
    SaSettings.save_settings()
    SaSettings.load_settings()


func test_a_hidden_element_stays_hidden_after_a_reload() -> void:
    assert_true(SaSettings.register_layout_category(DOCKER, "Probe", ["Drag Handle", "Resizer"]), "it registers")
    SaSettings.set_element_visible(DOCKER, "Resizer", false)
    SaSettings.load_settings()
    assert_false(SaSettings.get_element_visible(DOCKER, "Resizer"), "what the profile stored, not the default")
    assert_true(SaSettings.get_element_visible(DOCKER, "Drag Handle"), "and the other one keeps its default")


func test_an_option_keeps_its_value_after_a_reload() -> void:
    SaSettings.register_docker_option(
        DOCKER, OPTION, {"title": "Lines", "kind": SaSettingsLayout.OPTION_COUNT, "min": 1, "max": 9, "default": 1}
    )
    SaSettings.set_docker_option(DOCKER, OPTION, 4)
    SaSettings.load_settings()
    assert_eq(SaSettings.get_docker_option(DOCKER, OPTION), 4, "what the profile stored, not the default")


func test_a_docker_registered_after_the_read_finds_its_values() -> void:
    SaSettings.set_element_visible(DOCKER, "Resizer", false)
    SaSettings.load_settings()
    SaSettings.register_layout_category(DOCKER, "Probe", ["Drag Handle", "Resizer"])
    assert_false(SaSettings.get_element_visible(DOCKER, "Resizer"), "filed under the whole id once it is known")
