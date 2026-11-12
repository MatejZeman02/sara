## The Ellipse Select tool: the marquee with its shape fixed at an ellipse.
##
## Krita gives the ellipse a button of its own and Photoshop a row in the
## marquee's flyout. A shape row on the bar, hidden by default, left a painter
## who pressed the one Marquee with no ellipse anywhere. So each shape is a
## tool, and the drag, the mode, Shift and Alt, the feather and the click that
## deselects are the marquee's own code.
extends "res://modules/sara-base-modules/base/tools/state_marquee.gd"


func _init() -> void:
    shape = ELLIPSE
