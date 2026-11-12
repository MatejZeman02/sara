## A new brush's default spacing is small enough that round dabs overlap into a
## smooth line and do not read as a string of beads.
##
## At 0.18 of the diameter a hard round dab leaves a visible scallop along its
## stroke edge, so the default is a twentieth of the diameter, and both
## settings classes that declare it agree.
extends "res://tests/test_framework.gd"

const SettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")
const ToolSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/tools/brush_settings.gd")

## The widest default that still keeps a round dab's edge smooth.
const MAX_SPACING: float = 0.1


func test_the_stamp_settings_default_to_a_close_spacing() -> void:
    var settings: Variant = SettingsScript.new()
    assert_true(settings.spacing <= MAX_SPACING, "The stamp default is %.2f, at most %.2f" % [settings.spacing, MAX_SPACING])
    assert_true(settings.spacing > 0.0, "and the default is not zero")


func test_the_tool_settings_default_to_the_same_spacing() -> void:
    var tool_settings: Variant = ToolSettingsScript.new()
    var stamp: Variant = SettingsScript.new()
    assert_eq(tool_settings.spacing, stamp.spacing, "The tool's default spacing is the stamp's")
