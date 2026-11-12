## The resize grip: half the size it was, and anchored at the corner
## opposite it.
##
## Half the size, so a button at a docker's bottom right corner, the Layers
## docker's own More button among them, is pressable even at the docker's
## smallest size. What the grip's own square no longer covers is proved on the
## running app by `scenarios/smaller-resizer.json`, whose dump reads
## `under_the_grip` empty and the press landing on `LayerActionsMenu`.
## `test_layer_actions.gd`'s `test_the_column_is_inset_by_the_grip` already
## proves `reserve_grip_corner` reads the reservation off the resizer's own
## live size, so what a headless test can add here is the number itself.
##
## Anchored, because a grip grown about the centre lets a drag down
## lift the top over the menu bar. The grip is driven here the way a hand
## drives it, through its own input handler, on a window that is not in the
## tree, so no host clamps it and the anchor is all there is to see.
## `scenarios/resizing-a-docker-by-its-grip-keeps-its-top-edge.json` is the
## same on the running app, and `test_a_docker_grip_keeps_its_top_edge.gd`
## has the arithmetic and the clamps.
extends "res://tests/test_framework.gd"


func test_the_grip_is_half_its_old_size() -> void:
    var resizer := DockerResizer.new()
    assert_almost_eq(resizer.custom_minimum_size.x, 12.0, 1e-6, "half of the 24 the grip once declared")
    assert_almost_eq(resizer.side, 12.0, 1e-6, "both axes of the square that takes a press")
    var band := "with the clear band above it in the height the column clears"
    assert_almost_eq(resizer.custom_minimum_size.y, 12.0 + DockerResizer.GAP, 1e-6, band)
    resizer.size = resizer.custom_minimum_size
    assert_true(resizer._has_point(Vector2(6, resizer.size.y - 1)), "a press in the square takes the grip")
    assert_false(resizer._has_point(Vector2(6, DockerResizer.GAP - 1)), "and a press in the band above it does not")
    resizer.free()


func test_a_grip_dragged_down_and_right_keeps_the_window_s_top_left() -> void:
    var window := Window.new()
    window.min_size = Vector2i(80, 60)
    window.position = Vector2i(420, 200)
    window.size = Vector2i(300, 400)
    var resizer := DockerResizer.new(window)

    resizer.capture_drag(Vector2(720, 600), Vector2(50, 30))
    assert_eq(window.position, Vector2i(420, 200), "The top-left corner stays where it was")
    assert_eq(window.size, Vector2i(350, 430), "and the size took the drag once, not twice")

    resizer.capture_drag(Vector2(770, 630), Vector2(-120, -90))
    assert_eq(window.position, Vector2i(420, 200), "A drag back up and left keeps it too")
    assert_eq(window.size, Vector2i(230, 340), "and only the bottom and the right edges came in")

    resizer.capture_drag(Vector2(650, 540), Vector2(-600, -600))
    assert_eq(window.size, Vector2i(80, 60), "The floor stops the shrink")
    assert_eq(window.position, Vector2i(420, 200), "without the docker walking towards the pointer")
    resizer.free()
    window.free()
