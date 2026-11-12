## A column of tool buttons is as wide as a button, not as wide as the docker.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Taking the grid off the drag which left every middle width laying out a
## column, which made this visible: the grid and its buttons are
## `SIZE_EXPAND_FILL` from `_init`, so a dump of a 150 by 110 docker
## reads five buttons drawn 138 by 40. The stretch was always there, only the
## amount was small while a middle width still gridded.
##
## Two claims, and they pull in opposite directions, so both are graded here. A
## column keeps its buttons at a button's width. **A row and a grid keep
## dividing the width they are given**, which a shot of the scenario shows is
## what a row should do, so the fix is not "stop expanding" but "expand for two
## of the three shapes".
##
## `scenarios/a-one-column-toolbox-stretches-its-buttons.json` grades the
## drawn width on the running app at three docker widths, where the count is
## the five category buttons rather than a number this file chose.
extends "res://tests/test_framework.gd"

## One button's logical width, `SaUI.BASE_TOOL_BTN`, and a docker short enough
## that the width is the only thing left to decide the shape.
const BTN := 40.0
const SHORT := 60.0

## Five, the number of category buttons a full module load draws.
const COUNT := 5

var _kept: Dictionary = {}
var _host: MarginContainer = null


func before_each() -> void:
    _kept = (SaSettings.layout_docker_options.get(SaToolBoxGrid.CATEGORY, {}) as Dictionary).duplicate()
    SaSettings.layout_docker_options[SaToolBoxGrid.CATEGORY] = {
        SaToolBoxGrid.ORIENTATION: SaToolBoxGrid.FOLLOW_SHAPE,
        SaToolBoxGrid.MAX_LINES: 1,
    }


func after_each() -> void:
    SaSettings.layout_docker_options[SaToolBoxGrid.CATEGORY] = _kept
    if _host != null and is_instance_valid(_host):
        _host.free()
    _host = null


## The three shapes `shape_of` can name, asked directly rather than through a
## rectangle, so a later change to `columns_for` cannot quietly drop one.
func test_a_column_does_not_fill_the_width_and_a_row_and_a_grid_do() -> void:
    assert_eq(SaToolBoxGrid.shape_of(1, COUNT), "column", "one column of five is the column")
    assert_false(SaToolBoxGrid.buttons_fill_width(1, COUNT), "and it keeps its buttons' own width")

    assert_eq(SaToolBoxGrid.shape_of(COUNT, COUNT), "row", "five columns of five is the row")
    assert_true(SaToolBoxGrid.buttons_fill_width(COUNT, COUNT), "and a row divides the width it is given")

    assert_eq(SaToolBoxGrid.shape_of(2, COUNT), "grid", "two columns of five is the grid")
    assert_true(SaToolBoxGrid.buttons_fill_width(2, COUNT), "and so does a grid")

    # The lone button. `shape_of` calls it a column, because a row of one is a
    # word nobody uses, and it is the case the defect is worst in: one button
    # stretched across a 400-wide docker is one icon and 360 units of nothing.
    assert_eq(SaToolBoxGrid.shape_of(1, 1), "column", "a single button is a column")
    assert_false(SaToolBoxGrid.buttons_fill_width(1, 1), "and keeps a button's width")


## The sweep, asked the other question. Every width the docker can be
## dragged to is laid out and the answer has to agree with the shape at that
## width, so the two rules can never disagree about the same rectangle.
func test_every_width_agrees_with_the_shape_it_lays_out() -> void:
    var columns_widths := 0
    var filled := 0
    var kept := 0
    for width in range(40, 601, 4):
        var columns := SaToolBoxGrid.columns_for(COUNT, float(width), SHORT, BTN)
        var shape := SaToolBoxGrid.shape_of(columns, COUNT)
        var fills := SaToolBoxGrid.buttons_fill_width(columns, COUNT)
        columns_widths += 1
        if shape == "column":
            kept += 1
            assert_false(fills, "a column at %d keeps its buttons' width" % width)
        else:
            filled += 1
            assert_true(fills, "a %s at %d divides the width" % [shape, width])

    assert_true(columns_widths > 100, "the sweep is over a real range of widths")
    assert_true(kept > 0, "some of those widths are the column the defect was in")
    assert_true(filled > 0, "and some are the row that has to keep filling")


## What `apply_button_width` actually writes, over a grid this test built. The
## flags are the whole fix, so they are read back rather than assumed from the
## predicate above.
func test_the_column_shrinks_the_buttons_and_the_grid_and_the_row_expands_both() -> void:
    var built := _build(150.0)
    var grid: GridContainer = built["grid"]
    var buttons: Dictionary = built["buttons"]

    SaToolBoxGrid.apply_button_width(grid, buttons, 1, COUNT)
    assert_eq(grid.size_flags_horizontal, Control.SIZE_SHRINK_CENTER, "a column narrows the grid with its buttons")
    for category: Variant in buttons:
        var btn: Button = buttons[category]
        assert_eq(btn.size_flags_horizontal, Control.SIZE_SHRINK_CENTER, "and every button keeps its own width")

    SaToolBoxGrid.apply_button_width(grid, buttons, COUNT, COUNT)
    assert_eq(grid.size_flags_horizontal, Control.SIZE_EXPAND_FILL, "a row hands the width back to the grid")
    for category: Variant in buttons:
        var btn: Button = buttons[category]
        assert_eq(btn.size_flags_horizontal, Control.SIZE_EXPAND_FILL, "and every button divides it again")


## The empty state. `visible_button_count` counts the "No tools" label, so the
## docker with no module loaded asks this for a column of one, and an
## autowrapping label's minimum width is a single pixel: a narrowed grid would
## draw the sentence as a sliver.
func test_a_grid_with_no_button_in_it_still_fills_the_docker() -> void:
    var built := _build(150.0)
    var grid: GridContainer = built["grid"]

    SaToolBoxGrid.apply_button_width(grid, {}, 1, 1)
    assert_eq(grid.size_flags_horizontal, Control.SIZE_EXPAND_FILL, "there is no button to narrow the grid to")


## And the drawn rectangle, which is the thing under test. Laid out in
## the real tree inside a `MarginContainer`, because that is what the docker
## puts the grid in and `Container.fit_child_in_rect` is where a size flag
## turns into a width.
func test_a_column_is_drawn_at_a_buttons_width_at_every_docker_width() -> void:
    for width: float in [60.0, 150.0, 400.0]:
        var built := _build(width)
        var grid: GridContainer = built["grid"]
        var buttons: Dictionary = built["buttons"]
        SaToolBoxGrid.apply_button_width(grid, buttons, 1, COUNT)
        _lay_out(built)

        for category: Variant in buttons:
            var btn: Button = buttons[category]
            assert_almost_eq(btn.size.x, BTN, 1.0, "a button in a %d-wide docker is %f wide" % [width, btn.size.x])
        after_each()
        before_each()


## A `MarginContainer` holding a one-column `GridContainer` of five buttons, the
## docker's own arrangement, sized to *width* and in the tree so a sort can run.
func _build(width: float) -> Dictionary:
    _host = MarginContainer.new()
    _host.name = "D1ToolboxWidthHost"
    for side: String in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
        _host.add_theme_constant_override(side, 0)
    EventBus.add_child(_host)
    _host.size = Vector2(width, 110.0)

    var grid := GridContainer.new()
    grid.name = "GridContainer"
    grid.columns = 1
    grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _host.add_child(grid)

    var buttons: Dictionary = {}
    for i in COUNT:
        var btn := Button.new()
        btn.name = "Btn%d" % i
        btn.custom_minimum_size = Vector2(BTN, BTN)
        btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
        grid.add_child(btn)
        buttons[StringName("c%d" % i)] = btn
    return {"grid": grid, "buttons": buttons}


## Runs both sorts by hand. A test function cannot await a frame, and a
## `queue_sort` is answered on the next one, so the notification the sort
## listens for is sent straight to the two containers, outside in.
func _lay_out(built: Dictionary) -> void:
    _host.notification(Container.NOTIFICATION_SORT_CHILDREN)
    (built["grid"] as GridContainer).notification(Container.NOTIFICATION_SORT_CHILDREN)
