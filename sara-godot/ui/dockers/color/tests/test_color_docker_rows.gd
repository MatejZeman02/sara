## Every row the Colour Picker docker is told to draw is a row somebody can
## reach.
##
## The docker shows RGB sliders and ok-hsv sliders. A report found them missing,
## but both rows were added, both read
## `visible` true, and the shipped docker was ninety-nine logical pixels too
## short to hold them, so four of the six sliders were laid out below its own
## bottom edge. `sa_color_picker.gd`'s own header records the same
## wall being hit with Godot's ColorPicker, which is why this file exists rather than a
## bigger number and a hope.
extends "res://tests/test_framework.gd"

const ColorDockerScript = preload("res://ui/dockers/color/color_docker.gd")

## The shipped starting layout, which is what a fresh profile is handed and what
## a painter with an old profile had a stale copy of.
const SHIPPED_LAYOUT := "res://docker_layout_default.cfg"


## The two rows, by the names Preferences and the profile use. They
## shipped switched on, but RGB
## sliders are of little use beside the picker shape. So both ship
## off, and both stay rows of the element list, which is where a painter who
## wants them turns them on.
func test_both_slider_rows_ship_in_the_list_switched_off() -> void:
    var order: Array = SaSettingsLayout.DEFAULT_ORDERS["ColorPicker"]
    for element: String in [SaPickerSliders.ELEMENT_RGB, SaPickerSliders.ELEMENT_OKHSV]:
        assert_true(order.has(element), "%s is in the docker's default order" % element)
        assert_true(SaSettingsLayout.DEFAULT_HIDDEN["ColorPicker"].has(element), "%s is hidden by default" % element)


## The shipped layout and the docker's own default are one number in two files,
## and they drifted: the docker said 310 and the file said 364, and neither was
## enough. Pinned so the next row added to the picker fails here rather than in
## somebody's screenshot.
func test_the_shipped_layout_matches_the_dockers_own_default() -> void:
    var cfg := ConfigFile.new()
    assert_eq(cfg.load(SHIPPED_LAYOUT), OK, "the shipped layout loads")
    var shipped: Vector2i = cfg.get_value("ColorDocker", "size", Vector2i.ZERO)
    assert_eq(shipped, ColorDockerScript.DEFAULT_SIZE, "the shipped size is the docker's own default")


## The docker ends above where the Layers docker begins, which is what makes
## 393 the height rather than a rounder number. A shipped layout whose two
## right-hand dockers overlap is a layout nobody chose.
func test_the_right_hand_column_does_not_overlap() -> void:
    var cfg := ConfigFile.new()
    assert_eq(cfg.load(SHIPPED_LAYOUT), OK, "the shipped layout loads")
    var picker_top: int = cfg.get_value("ColorDocker", "position", Vector2i.ZERO).y
    var picker_height: int = cfg.get_value("ColorDocker", "size", Vector2i.ZERO).y
    var layers_top: int = cfg.get_value("LayersDocker", "position", Vector2i.ZERO).y
    assert_true(picker_top + picker_height <= layers_top, "the picker stops at or above the Layers docker's top edge")


## A docker dragged shorter than its rows still reaches them. This is the half
## that answers a painter whose profile carries a geometry saved
## before the rows existed and which no change to a shipped default can reach.
func test_the_rows_sit_in_a_scroll() -> void:
    var host := Control.new()
    var docker := ColorDockerScript.new()
    docker.name = "ColorDocker"
    host.add_child(docker)
    docker._ready()

    var found: ScrollContainer = null
    var node: Node = docker.color_picker.get_parent()
    while node != null and found == null:
        found = node as ScrollContainer
        node = node.get_parent()
    assert_true(found != null, "the picker's rows are inside a ScrollContainer")
    assert_eq(
        found.horizontal_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED, "and only downwards, because the rows are full width"
    )

    host.free()
