## The two dockers whose content column wanted more height than their window,
## and the scroll that is now between the two.
##
## `DockerWindow` has a `column_min_height` and left the enforcement out on
## purpose: flooring the window at it takes the Recorder from 270 tall to 665 and
## the Toolbox from 88 to 280, which is a change to what a painter sees rather
## than a repair. So the column is scrolled instead, and what these assert is that
## the scroll is there, that it is vertical only, and that the window's own
## minimum no longer has to grow to hold the column.
##
## What it looks like on the running app is `scenarios/docker-grip-corner.json`
## and `scenarios/docker-column-overflows.json`, whose `under_the_grip` is
## empty for all ten dockers at both sizes.
extends "res://tests/test_framework.gd"


## A docker built the way `test_tool_options_docker` builds one: under a plain
## Node, so `_init` runs and `_ready` does not, and no Window is ever displayed.
func _under_a_host(docker: Window) -> Node:
    var host := Node.new()
    host.add_child(docker)
    return host


func _scroll_of(docker: Window) -> ScrollContainer:
    return docker.get_node_or_null("Control/VBoxContainer/Scroll") as ScrollContainer


func test_the_toolbox_scrolls_its_grid_rather_than_clipping_it() -> void:
    var docker := ToolBoxDocker.new()
    var host := _under_a_host(docker)

    var scroll := _scroll_of(docker)
    assert_not_null(scroll, "The toolbox puts its grid in a ScrollContainer")
    assert_eq(
        scroll.horizontal_scroll_mode,
        ScrollContainer.SCROLL_MODE_DISABLED,
        "vertical only, the grid already reflowing with the docker's width"
    )
    assert_not_null(scroll.get_node_or_null("MarginContainer"), "and the margin and grid moved inside it")

    host.free()


func test_the_recorder_scrolls_its_column_rather_than_clipping_it() -> void:
    var docker := RecorderDocker.new()
    var host := _under_a_host(docker)

    var scroll := _scroll_of(docker)
    assert_not_null(scroll, "The recorder puts its rows in a ScrollContainer")
    assert_eq(
        scroll.horizontal_scroll_mode,
        ScrollContainer.SCROLL_MODE_DISABLED,
        "vertical only: a sideways scroll on a stack of full-width rows loses one rather than reaching it"
    )
    assert_not_null(scroll.get_node_or_null("MarginContainer"), "and the margin and column moved inside it")

    host.free()


## `content_column()` is `drag_handle.get_parent()`, and the drag bar did not
## move, so the column the width is floored against is the same one it was.
func test_the_column_the_width_is_floored_against_is_unchanged() -> void:
    for docker: Window in [ToolBoxDocker.new(), RecorderDocker.new()]:
        var host := _under_a_host(docker)
        var column: Container = docker.call("content_column")
        assert_not_null(column, "%s still has a content column" % docker.name)
        assert_eq(String(column.name), "VBoxContainer", "and it is the box the drag bar is in, not the scroll")
        host.free()


## The scroll is what takes the column's height out of the window's minimum, and
## a `ScrollContainer` still passes a disabled axis's minimum up, so the width that is
## floored is still floored. Asserted as the shape rather than as a number,
## because the numbers move with the theme and the font.
func test_the_toolboxs_layout_pass_still_finds_its_margin() -> void:
    var docker := ToolBoxDocker.new()
    var host := _under_a_host(docker)

    var margin := docker.get_node_or_null("Control/VBoxContainer/Scroll/MarginContainer")

    assert_not_null(margin, "apply_layout_settings reads this path, so a moved margin is a docker that lays out nothing")
    assert_not_null(margin.get_node_or_null("GridContainer"), "and the grid is under it")

    host.free()
