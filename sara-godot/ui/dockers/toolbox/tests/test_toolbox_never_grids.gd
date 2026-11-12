## Following the shape answers a row or a column and never a grid.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The claim is about a resize: the tools docker must not switch to a grid when
## resized, as a grid is not wanted. So the sweep below is over widths rather
## than over three hand-picked numbers: every width the docker can be dragged to
## is asked what it lays out, and the grid has to be absent from all of them.
##
## `scenarios/the-toolbox-never-chooses-a-grid.json` grades the same claim on
## the running app, where the count is the five category buttons rather than a
## number this file chose.
extends "res://tests/test_framework.gd"

## One button's logical width, and a docker short enough that the width is the
## only thing left to decide the layout.
const BTN := 32.0
const SHORT := 60.0

var _kept: Dictionary = {}


func before_each() -> void:
    _kept = (SaSettings.layout_docker_options.get(SaToolBoxGrid.CATEGORY, {}) as Dictionary).duplicate()
    SaSettings.layout_docker_options[SaToolBoxGrid.CATEGORY] = {
        SaToolBoxGrid.ORIENTATION: SaToolBoxGrid.FOLLOW_SHAPE,
        SaToolBoxGrid.MAX_LINES: 1,
    }


func after_each() -> void:
    SaSettings.layout_docker_options[SaToolBoxGrid.CATEGORY] = _kept


func test_no_width_at_all_answers_a_grid() -> void:
    # Eleven, which is the case that failed: eleven tools in a 420-wide docker
    # were ten across and one alone underneath, and the fix for that was the
    # even spread that made every middle width a grid.
    var count := 11
    var grids := 0
    var widths := 0
    for width in range(40, 601, 4):
        var columns := SaToolBoxGrid.columns_for(count, float(width), SHORT, BTN)
        widths += 1
        if SaToolBoxGrid.shape_of(columns, count) == "grid":
            grids += 1

    assert_true(widths > 100, "the sweep is over a real range of widths")
    assert_eq(grids, 0, "and not one of them lays out a grid")


func test_a_width_that_affords_the_row_is_the_row_and_one_that_does_not_is_the_column() -> void:
    var count := 11
    # The first width that holds eleven buttons and their padding, and the last
    # that does not, worked out the way the branch does rather than assumed.
    var affords := SaToolBoxGrid.PADDING + BTN * count
    for width in range(40, 601, 4):
        var columns := SaToolBoxGrid.columns_for(count, float(width), SHORT, BTN)
        var shape := SaToolBoxGrid.shape_of(columns, count)
        if float(width) >= affords:
            assert_eq(shape, "row", "%d wide holds all eleven" % width)
            assert_eq(columns, count, "so every button is on the one row")
        else:
            assert_eq(shape, "column", "%d wide holds fewer, so it is the column" % width)
            assert_eq(columns, 1, "one across")


func test_a_docker_taller_than_it_is_wide_is_a_column_however_wide_it_is() -> void:
    # The other half of the rectangle. A width that affords the row is not the
    # row when the painter dragged a tall docker, because the shape they dragged
    # is the answer they asked for.
    assert_eq(SaToolBoxGrid.columns_for(5, 400.0, 900.0, BTN), 1, "tall and wide is still a column")
    assert_eq(SaToolBoxGrid.columns_for(5, 400.0, 400.0, BTN), 1, "and a square is not wider than it is tall")
    assert_eq(SaToolBoxGrid.columns_for(5, 400.0, 399.0, BTN), 5, "one pixel shorter and it is the row")


func test_the_grid_is_still_reachable_from_preferences() -> void:
    # Not what a resize does is not the same as gone. Vertical with a cap of two
    # is the two-column grid, at the same rectangle that follows the shape into
    # a plain row.
    var wide := 400.0
    assert_eq(SaToolBoxGrid.columns_for(5, wide, SHORT, BTN), 5, "the drag says row")

    SaSettings.layout_docker_options[SaToolBoxGrid.CATEGORY] = {
        SaToolBoxGrid.ORIENTATION: SaToolBoxGrid.VERTICAL,
        SaToolBoxGrid.MAX_LINES: 2,
    }

    var columns := SaToolBoxGrid.columns_for(5, wide, SHORT, BTN)
    assert_eq(columns, 2, "and Preferences says two columns")
    assert_eq(SaToolBoxGrid.shape_of(columns, 5), "grid", "which is the grid, still there for whoever wants it")
