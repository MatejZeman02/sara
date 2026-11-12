## Sara's borderless main window, once windowed, has an edge
## at each side and corner that a press resizes from, none while maximised, and
## a restore lands on a rectangle smaller than the screen and on the window's
## own screen.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The geometry is asked of `SaTopBarWindowFrame`'s statics with no window
## moved, since a suite never moves the window it runs in. The run on a real
## compositor, with a hand on a seat, is
## a scenario under `scenarios/`.
extends "res://tests/test_framework.gd"

const WINDOW := Vector2(1280, 800)
const Frame := preload("res://ui/top_bar/top_bar_window_frame.gd")


func test_each_side_and_corner_has_its_edge_on_a_windowed_window() -> void:
    var far := WINDOW - Vector2(2, 2)
    var points := {
        DisplayServer.WINDOW_EDGE_TOP_LEFT: Vector2(1, 1),
        DisplayServer.WINDOW_EDGE_TOP: Vector2(640, 1),
        DisplayServer.WINDOW_EDGE_TOP_RIGHT: Vector2(far.x, 1),
        DisplayServer.WINDOW_EDGE_LEFT: Vector2(1, 400),
        DisplayServer.WINDOW_EDGE_RIGHT: Vector2(far.x, 400),
        DisplayServer.WINDOW_EDGE_BOTTOM_LEFT: Vector2(1, far.y),
        DisplayServer.WINDOW_EDGE_BOTTOM: Vector2(640, far.y),
        DisplayServer.WINDOW_EDGE_BOTTOM_RIGHT: far,
    }
    for edge: int in points:
        assert_eq(Frame.edge_at(points[edge], WINDOW, false), edge, "a press at %s is edge %d" % [points[edge], edge])
    # A corner's run along each side is a corner too, not the side beside it.
    assert_eq(
        Frame.edge_at(Vector2(10, 1), WINDOW, false), DisplayServer.WINDOW_EDGE_TOP_LEFT, "the top left corner runs along the top"
    )
    assert_eq(
        Frame.edge_at(Vector2(far.x, far.y - 10), WINDOW, false),
        DisplayServer.WINDOW_EDGE_BOTTOM_RIGHT,
        "and the bottom right one up the right side"
    )


func test_only_the_outermost_pixels_are_an_edge() -> void:
    var inside := Frame.REACH + 1.0
    assert_eq(Frame.edge_at(Vector2(640, 400), WINDOW, false), Frame.NO_EDGE, "the middle is no edge")
    assert_eq(
        Frame.edge_at(Vector2(inside, 400), WINDOW, false), Frame.NO_EDGE, "a point past the reach on the left is the canvas's"
    )
    assert_eq(
        Frame.edge_at(Vector2(inside, inside), WINDOW, false), Frame.NO_EDGE, "and so is the inner part of a corner's square"
    )
    assert_eq(
        Frame.edge_at(Vector2(WINDOW.x - inside, WINDOW.y - inside), WINDOW, false),
        Frame.NO_EDGE,
        "and of the bottom right one, where a stroke at the canvas's corner begins"
    )


func test_a_maximised_window_has_no_edge() -> void:
    for point: Vector2 in [Vector2(1, 1), Vector2(640, 1), Vector2(1, 400), WINDOW - Vector2(1, 1), Vector2(640, WINDOW.y - 1)]:
        assert_eq(Frame.edge_at(point, WINDOW, true), Frame.NO_EDGE, "a maximised window resizes from nowhere, %s" % point)


func test_the_laid_strips_take_what_edge_at_names() -> void:
    var bar := Control.new()
    var frame := Frame.new(bar, false)
    EventBus.add_child(frame)
    var strips := Frame.strip_rects(frame.get_viewport().get_visible_rect().size)
    for strip in frame.get_children():
        var control := strip as Control
        var edge := int(String(control.name).trim_prefix("Edge"))
        assert_eq(control.get_rect(), strips[edge], "strip %d lies where the geometry says" % edge)
        assert_eq(control.mouse_default_cursor_shape, Frame.CURSORS[edge], "and shows its edge's cursor")
    assert_eq(frame.get_child_count(), 8, "four sides and four corners")
    frame.free()
    bar.free()


func test_a_first_restore_is_smaller_than_the_screen_and_on_the_windows_screen() -> void:
    var usable: Array[Rect2i] = [Rect2i(0, 0, 1920, 1040), Rect2i(1920, -200, 2560, 1400)]
    for screen in usable.size():
        var rect := Frame.restore_rect({}, usable, screen)
        var on := usable[screen]
        assert_true(rect.size.x < on.size.x and rect.size.y < on.size.y, "screen %d: %s is smaller than %s" % [screen, rect, on])
        assert_true(on.encloses(rect), "and lies on that screen")
        assert_eq(rect.get_center(), on.get_center(), "centred on it")


func test_a_kept_rectangle_is_used_again_unless_its_screen_is_gone() -> void:
    var two: Array[Rect2i] = [Rect2i(0, 0, 1920, 1040), Rect2i(1920, 0, 2560, 1400)]
    var kept := {"maximized": false, "rect": Rect2i(2100, 120, 1400, 900), "screen": 1}
    assert_eq(Frame.restore_rect(kept, two, 0), kept["rect"], "the kept rectangle on the second screen comes back there")
    var one: Array[Rect2i] = [Rect2i(0, 0, 1920, 1040)]
    var back := Frame.restore_rect(kept, one, 0)
    assert_true(one[0].encloses(back) and back.size.x < 1920, "with that screen gone it is centred on the one left, %s" % back)


func test_a_resize_on_windows_keeps_the_far_side_and_the_least_size() -> void:
    var rect := Rect2i(100, 100, 1200, 800)
    var least := Vector2i(960, 600)
    assert_eq(
        Frame.resized(rect, DisplayServer.WINDOW_EDGE_RIGHT, Vector2i(150, 40), least),
        Rect2i(100, 100, 1350, 800),
        "the right edge grows by the drag"
    )
    assert_eq(
        Frame.resized(rect, DisplayServer.WINDOW_EDGE_BOTTOM_RIGHT, Vector2i(150, 40), least),
        Rect2i(100, 100, 1350, 840),
        "the bottom right corner grows both ways"
    )
    assert_eq(
        Frame.resized(rect, DisplayServer.WINDOW_EDGE_TOP_LEFT, Vector2i(500, 500), least),
        Rect2i(340, 300, 960, 600),
        "the top left corner stops at the least size with the bottom right where it was"
    )


func test_a_window_never_closed_reads_as_maximised() -> void:
    assert_true(Frame.same({}, {"maximized": true, "rect": Rect2i(), "screen": -1}), "an empty profile is a maximised window")
    assert_false(Frame.same({}, {"maximized": false, "rect": Rect2i(0, 0, 900, 700), "screen": 0}), "and not a windowed one")


func test_a_press_on_the_bar_is_empty_only_where_it_holds_no_control() -> void:
    var bar := Control.new()
    bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
    bar.size = Vector2(1280, 40)
    # A plain row rather than a container, laid by hand, since a suite that
    # awaits a frame drops every assertion after the await.
    var row := Control.new()
    row.mouse_filter = Control.MOUSE_FILTER_PASS
    row.size = bar.size
    bar.add_child(row)
    var button := Button.new()
    button.size = Vector2(80, 40)
    row.add_child(button)
    var frame := Frame.new(bar, false)
    bar.add_child(frame)
    EventBus.add_child(bar)
    assert_false(frame.empty_at(button.get_global_rect().get_center()), "a press on a button is the button's")
    assert_true(frame.empty_at(Vector2(900, 20)), "a press on the row past it is the bar's empty part")
    assert_false(frame.empty_at(Vector2(900, 60)), "and one below the bar is not the bar's at all")
    bar.free()
