## A curve's first and last points move like any other.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## With a real pen the start and end points of the brush editor's pressure curve
## could not be edited, and any curve should have them adjustable. Every curve graph is `SaCurveEditor`, so the editor is fed the
## events a window would give it, detached, with no GPU and no window.
extends "res://tests/test_framework.gd"


func _editor() -> SaCurveEditor:
    var editor := SaCurveEditor.new()
    editor.size = editor.custom_minimum_size
    editor.set_points(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.5, 0.7), Vector2(1.0, 1.0)]))
    return editor


func _at(editor: SaCurveEditor, point: Vector2) -> Vector2:
    return Vector2(point.x * editor.size.x, (1.0 - point.y) * editor.size.y)


func _press(editor: SaCurveEditor, at: Vector2) -> void:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = true
    event.position = at
    editor._gui_input(event)


func _move(editor: SaCurveEditor, at: Vector2) -> void:
    var event := InputEventMouseMotion.new()
    event.position = at
    editor._gui_input(event)


func _release(editor: SaCurveEditor, at: Vector2) -> void:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = false
    event.position = at
    editor._gui_input(event)


func _drag(editor: SaCurveEditor, from: Vector2, to: Vector2) -> void:
    _press(editor, _at(editor, from))
    _move(editor, _at(editor, to))
    _release(editor, _at(editor, to))


func test_a_press_on_the_very_corner_grabs_the_end_and_adds_nothing() -> void:
    var editor := _editor()

    _press(editor, Vector2(0.0, editor.size.y))
    assert_eq(editor.points.size(), 3, "a press on the bottom left corner adds no point")
    assert_eq(editor._dragging, 0, "and grabs the first point")
    _release(editor, Vector2(0.0, editor.size.y))

    _press(editor, Vector2(editor.size.x, 0.0))
    assert_eq(editor.points.size(), 3, "a press on the top right corner adds no point")
    assert_eq(editor._dragging, 2, "and grabs the last point")
    editor.free()


func test_a_corner_press_grabs_an_end_whose_y_has_moved() -> void:
    var editor := _editor()
    editor.set_points(PackedVector2Array([Vector2(0.0, 0.6), Vector2(0.5, 0.7), Vector2(1.0, 0.4)]))

    _press(editor, Vector2(0.0, editor.size.y))
    assert_eq(editor.points.size(), 3, "the bottom left corner adds no point beside the raised end")
    assert_eq(editor._dragging, 0, "it grabs the first point on that edge")
    _release(editor, Vector2(0.0, editor.size.y))

    _press(editor, Vector2(editor.size.x, 0.0))
    assert_eq(editor.points.size(), 3, "nor does the top right corner beside the lowered end")
    assert_eq(editor._dragging, 2, "it grabs the last point")
    editor.free()


func test_the_first_point_dragged_inward_stays_where_it_is_let_go() -> void:
    var editor := _editor()

    _drag(editor, Vector2(0.0, 0.0), Vector2(0.3, 0.2))

    assert_eq(editor.points.size(), 3, "no point added or lost")
    assert_almost_eq(editor.points[0].x, 0.3, 0.01, "the first point moved in x")
    assert_almost_eq(editor.points[0].y, 0.2, 0.01, "and in y")
    var lookup := editor.samples(256)
    assert_almost_eq(lookup[0], editor.points[0].y, 1e-4, "below the first point's x the curve holds its y")
    assert_almost_eq(lookup[51], editor.points[0].y, 1e-4, "up to that x")
    editor.free()


func test_the_last_point_dragged_inward_stays_where_it_is_let_go() -> void:
    var editor := _editor()

    _drag(editor, Vector2(1.0, 1.0), Vector2(0.8, 0.9))

    assert_almost_eq(editor.points[2].x, 0.8, 0.01, "the last point moved in x")
    assert_almost_eq(editor.points[2].y, 0.9, 0.01, "and in y")
    var lookup := editor.samples(256)
    assert_almost_eq(lookup[255], editor.points[2].y, 1e-4, "above the last point's x the curve holds its y")
    editor.set_points(editor.points)
    assert_almost_eq(editor.points[2].x, 0.8, 0.01, "and handing the points back in keeps the end's x")
    editor.free()


func test_an_end_stops_short_of_its_neighbour() -> void:
    var editor := _editor()

    _drag(editor, Vector2(0.0, 0.0), Vector2(0.9, 0.1))

    assert_true(editor.points[0].x < editor.points[1].x, "the first point never passes the second")
    assert_eq(editor.points.size(), 3, "and is not dropped")
    editor.free()


func test_an_end_dragged_off_the_graph_stays_on_its_edge() -> void:
    var editor := _editor()

    _press(editor, _at(editor, Vector2(0.0, 0.0)))
    _move(editor, Vector2(-200.0, editor.size.y + 200.0))

    assert_eq(editor.points.size(), 3, "an end is never dropped")
    assert_eq(editor.points[0], Vector2(0.0, 0.0), "it stops on the corner")
    editor.free()
