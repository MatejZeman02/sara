## The picker's Type row, which is a per-docker option on the Preferences page
## and no longer a control in the docker.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The picker Type is an option inside the preferences, not on the docker
## itself, which is two claims: the docker has no such control, and the page
## does. The first is an absence and no shot can show one, so both are here, and
## `scenarios/picker-type-row-to-preferences.json` shows the shape changing
## from the page on the running app.
extends "res://tests/test_framework.gd"

const SaColorPickerScript = preload("res://ui/dockers/color/sa_color_picker.gd")

var _kept: String = "wheel"


func before_each() -> void:
    _kept = SaSettings.color_picker_shape


func after_each() -> void:
    SaSettings.color_picker_shape = _kept


func test_the_docker_builds_no_type_control_and_no_row_for_one() -> void:
    var picker := SaColorPickerScript.new()
    var dummy := Control.new()
    dummy.add_child(picker)

    assert_null(picker.find_child("PickerTypeRow", true, false), "no Type row in the docker")
    assert_null(picker.find_child("PickerType", true, false), "and no dropdown inside one")
    assert_false("shape_picker" in picker, "and the member that held it is gone")
    assert_false(SaSettingsLayout.DEFAULT_ORDERS["ColorPicker"].has("Picker Type"), "nor a row in the element list")
    dummy.free()


func test_the_page_offers_it_as_a_per_docker_option() -> void:
    var picker := SaColorPickerScript.new()
    var dummy := Control.new()
    dummy.add_child(picker)
    picker._ready()

    var keys: Array[String] = []
    for spec: Dictionary in SaSettings.docker_options("ColorPicker"):
        keys.append(String(spec.get("key", "")))

    assert_true(keys.has("shape"), "the Colour Picker page carries a shape option")
    dummy.free()


## The one thing a second store would have broken. `color_picker_shape` was
## already the setting behind the docker's dropdown and four committed scenarios
## write it through `{"prefs": {...}}`, so the option reads and writes that
## rather than keeping a copy in `profile_docker_option`.
func test_the_option_is_the_setting_rather_than_a_copy_of_it() -> void:
    var picker := SaColorPickerScript.new()
    var dummy := Control.new()
    dummy.add_child(picker)
    picker._ready()

    SaSettings.set_docker_option("ColorPicker", "shape", "triangle")
    assert_eq(SaSettings.color_picker_shape, "triangle", "writing the option writes the setting")

    SaSettings.color_picker_shape = "okhsl"
    assert_eq(SaSettings.get_docker_option("ColorPicker", "shape"), "okhsl", "and reading it reads the setting back")
    assert_false(
        (SaSettings.layout_docker_options.get("ColorPicker", {}) as Dictionary).has("shape"),
        "with nothing stored beside it, or there would be two answers to one question"
    )
    dummy.free()


func test_the_page_row_shows_the_four_shapes_by_their_labels() -> void:
    var picker := SaColorPickerScript.new()
    var dummy := Control.new()
    dummy.add_child(picker)
    picker._ready()
    var page := SaLayoutPage.new("ColorPicker", SaLayoutPage.OPTIONS)

    var row := page.below_control("Type") as SaChoiceButton

    assert_not_null(row, "the page draws a Type row")
    assert_eq(row.choice_labels().size(), SaPickerShape.KIND_KEYS.size(), "with one entry per shape")
    assert_eq(row.choice_labels()[0], SaPickerShape.KIND_LABELS[0], "under the names the shape declares")
    page.free()
    dummy.free()


func test_choosing_on_the_page_changes_the_shape_the_docker_is_in() -> void:
    var picker := SaColorPickerScript.new()
    var dummy := Control.new()
    dummy.add_child(picker)
    picker._ready()
    var page := SaLayoutPage.new("ColorPicker", SaLayoutPage.OPTIONS)

    page.drive_gesture(null, Vector2.ZERO, {"option": "shape", "value": "triangle"})

    assert_eq(SaSettings.color_picker_shape, "triangle", "the setting moved")
    assert_eq(picker.shape.kind_key(), "triangle", "and the docker is in that shape")
    page.free()
    dummy.free()


## Version 13 takes the row out of a stored order, or Preferences would offer a
## switch for a control the docker no longer builds, which is the shape of a stale stored order.
func test_a_stored_order_that_lists_the_row_is_migrated() -> void:
    var config := ConfigFile.new()
    config.set_value("meta", "version", 12)
    config.set_value("profile_order", "ColorPicker", ["Drag Handle", "Resizer", "HSV Wheel", "Picker Type", "Hex Input"])
    config.set_value("profile_visibility", "ColorPicker_Picker Type", false)

    SaSettingsMigrations.apply(config, 12)

    var order: Array = config.get_value("profile_order", "ColorPicker", [])
    assert_false(order.has("Picker Type"), "the row is out of the stored order")
    assert_true(order.has("Hex Input"), "and everything else is where it was")
    assert_false(
        config.has_section_key("profile_visibility", "ColorPicker_Picker Type"),
        "with no visibility key left naming a control nobody can see"
    )
