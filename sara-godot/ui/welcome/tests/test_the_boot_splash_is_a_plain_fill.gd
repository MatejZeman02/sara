## The boot splash is a plain fill with no image, so a painter
## sees one picture from the start of Sara to the Welcome window, and not the
## icon on black and then the painting.
##
## Read from the file and not from `ProjectSettings`, which answers a default
## for a key the file does not carry and so cannot tell an image removed from one
## never set.
extends "res://tests/test_framework.gd"

const PROJECT_FILE := "res://project.godot"


func _application() -> ConfigFile:
    var config := ConfigFile.new()
    assert_eq(config.load(PROJECT_FILE), OK, "project.godot loads")
    return config


func test_the_project_names_no_boot_splash_image() -> void:
    var config := _application()
    assert_false(config.has_section_key("application", "boot_splash/image"), "no image is named for the splash")
    assert_false(bool(config.get_value("application", "boot_splash/show_image", true)), "and the engine is told to show none")


func test_the_fill_is_the_default_themes_window_colour() -> void:
    var config := _application()
    var fill: Color = config.get_value("application", "boot_splash/bg_color", Color.BLACK)
    var window_colour := SaPalette.new().bg_primary
    assert_almost_eq(fill.r, window_colour.r, 0.001, "red is the window's")
    assert_almost_eq(fill.g, window_colour.g, 0.001, "green is the window's")
    assert_almost_eq(fill.b, window_colour.b, 0.001, "and blue")
    assert_almost_eq(fill.a, 1.0, 0.001, "and it is opaque")
