## The margin the preset chooser's search row and filter row stand in when a
## host pins them above the scroll that holds the presets.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A painter scrolled down a long list of presets had to scroll back up to
## change the filter, so a host that scrolls the chooser hands the chooser its
## column and the two rows are built in this margin there, above the scroll,
## and only the presets move.
##
## **The rows sit as close to the first cells as they did inside the scroll.**
## Pinned, the rows and the grid are parted by the host column's separation and
## the margin at the top of the scrolled content, both wider than the chooser's
## own gap, and the docker would have grown by the difference and shown less of
## its second row of presets. So the bottom margin is the chooser's gap less
## those two, a negative number, and the rows end below this margin's rect and
## inside the column's separation, where nothing else is drawn. Taken again at
## each theme pass, because the separation is the theme's and scales with it.
class_name SaBrushPresetPinnedHeader
extends MarginContainer

## The gap the chooser keeps between its rows, in logical units.
var _gap: int = 0


## Joins *column* at its end, so a host calls this before its scroll joins it.
## *gap* is the chooser's gap between its rows.
func _init(column: Container, gap: int) -> void:
    name = "ChooserHeader"
    _gap = gap
    for side: String in ["margin_left", "margin_right", "margin_top"]:
        add_theme_constant_override(side, SaUI.px(SaUI.BASE_MARGIN))
    column.add_child(self)


func _notification(what: int) -> void:
    if what != NOTIFICATION_THEME_CHANGED and what != NOTIFICATION_ENTER_TREE:
        return
    var column := get_parent_control()
    var parted := column.get_theme_constant(&"separation") if column != null else 0
    var bottom := SaUI.px(_gap) - parted - SaUI.px(SaUI.BASE_MARGIN)
    # An override sends this notification again, so a value already held is left.
    if get_theme_constant(&"margin_bottom") != bottom:
        add_theme_constant_override("margin_bottom", bottom)
