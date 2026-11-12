## The least height of the Tool Options docker's rows: the first rows it is
## showing, so a layout that cuts the docker to its floor still shows them.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The rows sit in a scroll, which asks for no height of its own, so without
## this the docker's floor is its title, the Advanced check and the foot line.
## The default layout's fit gives up height from the lowest docker of a column
## first, each down to its floor, and would cut a brush's Tool Options to a
## scroll no row tall, every row still visible to a check and none on screen.
##
## **Its own class rather than lines in `tool_options_docker.gd`**, because it
## owns one number, the height the scroll may not go
## under, and the docker owns which rows there are and what they say. Reached
## by path rather than by `class_name`, for the reason `docker_column_scroll.gd`
## gives.
@tool
extends RefCounted

## How many of the shown rows the floor holds. Four is the brush's dab,
## Hardness, Flow and the two pressure switches, and the most the shipped
## column holds at 1.25 on a 1080 screen. Measured with five, Brush Presets
## went to its own floor and the column was still 29 units over its room, so
## the Reference docker was pushed up over Tool Options' foot.
const ROWS: int = 4

## The scroll whose minimum height this writes.
var _scroll: ScrollContainer

## The column of rows inside the scroll, read top to bottom.
var _rows_box: VBoxContainer


func _init(scroll: ScrollContainer, rows_box: VBoxContainer) -> void:
    _scroll = scroll
    _rows_box = rows_box
    # A theme pass changes a row's height, and the floor is measured in rows.
    rows_box.minimum_size_changed.connect(hold)


## Puts the scroll's least height at the first `ROWS` rows shown, which is
## lower for a tool with fewer rows and nothing for a tool with none.
func hold() -> void:
    _scroll.custom_minimum_size.y = height()


## The first `ROWS` rows shown, with the gaps between them and the margin
## around them, in the logical units the docker's column measures in.
func height() -> float:
    var held := 0.0
    var counted := 0
    for child in _rows_box.get_children():
        var row := child as Control
        if row == null or not row.visible:
            continue
        held += side_by_side_height(row)
        counted += 1
        if counted == ROWS:
            break
    if counted == 0:
        return 0.0
    held += _rows_box.get_theme_constant(&"separation") * (counted - 1)
    var margin := _rows_box.get_parent() as MarginContainer
    if margin != null:
        held += margin.get_theme_constant(&"margin_top") + margin.get_theme_constant(&"margin_bottom")
    return held


## *row*'s height with its label beside its control. A row narrower than both
## stacks them, and a docker hidden at boot lays its rows out at no width at
## all, so a floor read then was 379 units where the shown docker's is 274, and
## the layout store's settle kept the 379 as the docker's height.
static func side_by_side_height(row: Control) -> float:
    if not row is ToolOptionsRow:
        return row.get_combined_minimum_size().y
    var tallest := 0.0
    for child in row.get_children():
        var part := child as Control
        if part != null and part.visible:
            tallest = maxf(tallest, part.get_combined_minimum_size().y)
    return tallest
