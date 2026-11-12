## The view rim stops at the picture's edge rather than running over the drag
## bar.
##
## The orange rim that shows where the 'camera' is looking must not render over
## the Drag bar.
##
## The rim is a polyline through the view's corners, and a view zoomed out far
## enough puts those corners outside the map. Godot clips nothing by default, so
## the line would run up the docker and over the bar. It is not a z-order
## problem: reordering the tree would only move which edge it spills over.
##
## A screenshot proves the state it was taken in and one line of `clip_contents`
## is what makes every other state safe.
extends "res://tests/test_framework.gd"


## The overlay clips its contents, which is the whole of the fix.
func test_the_view_overlay_clips_its_contents_to_the_picture() -> void:
    var docker := MinimapDocker.new()
    var overlay := docker.find_child("ViewOverlay", true, false) as Control
    assert_not_null(overlay, "The docker builds the overlay the rim is drawn on")
    if overlay != null:
        assert_true(overlay.clip_contents, "and it clips its contents, so the rim stops at the picture's edge")
        assert_eq(
            overlay.anchor_right - overlay.anchor_left,
            1.0,
            "over the full width of what it is anchored to, so there is no gap for the rim to escape through"
        )
    docker.free()


## The drag bar is a sibling of the picture rather than a child of it, which is
## why clipping the overlay is enough.
##
## If the bar were inside whatever the overlay clips to, a clip would hide the
## bar as well as the rim, and the fix would have been a different one.
func test_the_drag_bar_is_not_inside_what_the_overlay_clips_to() -> void:
    var docker := MinimapDocker.new()
    var overlay := docker.find_child("ViewOverlay", true, false) as Control
    var bar := docker.find_child("DragHandle", true, false) as Control
    assert_not_null(bar, "The docker has a drag bar")
    if overlay != null and bar != null:
        assert_false(bar.is_ancestor_of(overlay), "and the rim's overlay is not drawn inside it")
        assert_false(overlay.is_ancestor_of(bar), "and the bar is not drawn inside the overlay it would be clipped by")
    docker.free()
