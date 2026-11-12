## The Polygonal Lasso tool: the lasso with a point a click.
##
## A tool of its own beside the Lasso, as Photoshop and Krita have it. The
## clicks, the double-click, the click
## back on the first point, Enter, Escape, the mode, Shift and Alt, the
## Anti-aliasing and the Feather are the lasso's own code, and so are their
## option keys, so the two tools show one setting for each.
extends "res://modules/sara-base-modules/base/tools/state_lasso.gd"


func _init() -> void:
    polygon = true
