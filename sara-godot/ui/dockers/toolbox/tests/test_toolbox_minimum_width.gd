## The toolbox is no wider than its buttons at its narrowest.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The vertical toolbox docker's minimum width must not be thick. The floor was `BASE_TOOL_BTN + 2 * 2 + 6`, fifty
## logical units for a forty-unit button, and the 6 was one guess standing for
## the scroll's bar, the window's background and the corner grip at once. It
## bought ten units of dead band beside every icon, a fifth of the column.
##
## What replaces it is the button and its two margins and nothing else, because
## the other three turn out to cost nothing: the background is a `Panel` drawn
## behind a full-rect column rather than an inset, the grip sits over the corner,
## and the scroll declines to show a bar at all when showing one would take the
## column under its own minimum. So the floor is arithmetic over what stands in
## the column, and it is checked here against what the column asks for, because
## `DockerWindow.enforce_column_minimum` raises the window to that and a declared
## floor under it is a number nothing honours.
##
## `scenarios/the-toolbox-is-no-wider-than-its-buttons.json` is the same on
## the running app, at the default Font size and at the largest, and its fourth
## shot is the column still scrolling at that width with no bar taking any of it.
extends "res://tests/test_framework.gd"

## One button and the margin either side of it, the two things that actually
## stand in a one-column toolbox.
const BTN := 40
const MARGIN := 2

## What the floor once carried on top of them.
const OLD_SLACK := 6


## A docker built the way `test_docker_columns` builds one: under a plain
## Node, so `_init` runs and `_ready` does not, and no Window is ever displayed.
func _under_a_host(docker: Window) -> Node:
    var host := Node.new()
    host.add_child(docker)
    return host


func _scroll_of(docker: Window) -> ScrollContainer:
    return docker.get_node_or_null("Control/VBoxContainer/Scroll") as ScrollContainer


## The number `_init` declares, read off the window rather than off the source.
func test_the_declared_floor_is_a_button_and_its_margins() -> void:
    var docker := ToolBoxDocker.new()
    var host := _under_a_host(docker)

    assert_eq(
        int(docker.logical_min_size.x),
        BTN + MARGIN * 2,
        "the toolbox declares a button plus its two margins and no guessed slack"
    )
    assert_eq(
        BTN + MARGIN * 2 + OLD_SLACK - int(docker.logical_min_size.x),
        OLD_SLACK,
        "which is the six that made it narrower than the fifty it was"
    )

    host.free()


## The floor is still a floor. A declared minimum under what the column lays out
## at is worse than one that is too wide: the case is the docker drawing its column
## over its own right edge, and everything past the edge is clipped and gone.
func test_the_declared_floor_holds_the_column_it_is_the_floor_of() -> void:
    var docker := ToolBoxDocker.new()
    var host := _under_a_host(docker)

    var column: Container = docker.call("content_column")
    assert_not_null(column, "the toolbox has a content column to be floored against")
    var wanted := int(column.get_combined_minimum_size().x)
    assert_true(
        wanted <= int(docker.logical_min_size.x),
        "the column wants %d and the docker declares %d" % [wanted, int(docker.logical_min_size.x)]
    )

    host.free()


## The three things the 6 stood for, each asked whether it takes any width.
##
## The background first: it is a sibling of the column under `Control`, both at
## `PRESET_FULL_RECT`, so it is painted behind the buttons rather than around
## them and there is no inset to pay for.
func test_the_docker_background_is_behind_the_column_and_not_around_it() -> void:
    var docker := ToolBoxDocker.new()
    var host := _under_a_host(docker)

    var panel := docker.get_node_or_null("Control/DockerBackground") as Control
    var column := docker.get_node_or_null("Control/VBoxContainer") as Control
    assert_not_null(panel, "the docker paints a background panel")
    assert_not_null(column, "and the column is its sibling, not its child")
    assert_eq(panel.anchor_right, 1.0, "the panel spans the window")
    assert_eq(column.anchor_right, 1.0, "and so does the column, over the top of it")

    host.free()


## And the scroll, which is the one that looked to blame. Its minimum
## carries the column's width and not the bar's, so a scroll adds nothing to
## what the docker has to be however its bar happens to stand.
##
## The bar's own visibility is not asserted, and deliberately: a docker under a
## plain Node is never displayed and never laid out, so every scroll in this
## host has a bar showing over a zero-sized viewport. What the width depends on
## is the minimum, and the minimum is the same either way. The running app's
## fourth shot is where the bar is answered, scrolling a 44-wide column with
## nothing taken off the buttons.
func test_a_scroll_adds_nothing_to_the_columns_width() -> void:
    var docker := ToolBoxDocker.new()
    var host := _under_a_host(docker)

    var scroll := _scroll_of(docker)
    assert_not_null(scroll, "the toolbox column is inside a scroll")
    assert_not_null(scroll.get_v_scroll_bar(), "and that scroll has a vertical bar")

    var margin := scroll.get_node_or_null("MarginContainer") as Control
    assert_not_null(margin, "the margin is the scroll's own child")
    assert_eq(
        int(scroll.get_combined_minimum_size().x),
        int(margin.get_combined_minimum_size().x),
        "so the scroll asks for exactly what the margin under it asks for"
    )

    host.free()


## The margin is the only thing between the button and the window, so the number
## in `_init` is read back off the container rather than trusted twice.
func test_the_margin_either_side_is_the_two_the_floor_counts() -> void:
    var docker := ToolBoxDocker.new()
    var host := _under_a_host(docker)

    var margin := docker.get_node_or_null("Control/VBoxContainer/Scroll/MarginContainer") as MarginContainer
    assert_not_null(margin, "the grid sits in a margin")
    assert_eq(margin.get_theme_constant("margin_left"), MARGIN, "the left margin is the one the floor counts")
    assert_eq(margin.get_theme_constant("margin_right"), MARGIN, "and so is the right")

    host.free()
