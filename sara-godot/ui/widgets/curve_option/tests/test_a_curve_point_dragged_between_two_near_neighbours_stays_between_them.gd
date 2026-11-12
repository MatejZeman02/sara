## A curve point dragged between two near neighbours stays between them.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A point is kept short of each neighbour in x so the curve stays a function
## of its input. With a fixed margin, neighbours closer than twice it gave a
## lower bound above the upper one and the point landed past a neighbour. The
## editor is fed the events a window would give it, detached, with no GPU.
extends "res://tests/test_framework.gd"


func _editor(wanted: PackedVector2Array) -> SaCurveEditor:
    var editor := SaCurveEditor.new()
    editor.size = editor.custom_minimum_size
    editor.set_points(wanted)
    return editor


func _at(editor: SaCurveEditor, point: Vector2) -> Vector2:
    return Vector2(point.x * editor.size.x, (1.0 - point.y) * editor.size.y)


func _button(editor: SaCurveEditor, point: Vector2, pressed: bool) -> void:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    event.position = _at(editor, point)
    editor._gui_input(event)


func _move(editor: SaCurveEditor, point: Vector2) -> void:
    var event := InputEventMouseMotion.new()
    event.position = _at(editor, point)
    editor._gui_input(event)


func _assert_between(editor: SaCurveEditor, index: int, motion: String) -> void:
    var left := editor.points[index - 1].x
    var right := editor.points[index + 1].x
    var x := editor.points[index].x
    assert_true(
        left < x and x < right, "after %s the point's x %.6f is between its neighbours' %.6f and %.6f" % [motion, x, left, right]
    )


func test_a_point_between_neighbours_closer_than_the_margin_stays_between_them() -> void:
    var editor := _editor(
        PackedVector2Array(
            [
                Vector2(0.0, 0.0),
                Vector2(0.5, 0.2),
                Vector2(0.5004, 0.5),
                Vector2(0.5008, 0.8),
                Vector2(1.0, 1.0),
            ]
        )
    )
    _button(editor, Vector2(0.5004, 0.5), true)
    assert_eq(editor._dragging, 2, "the press grabs the middle of the three close points")
    var motions: Array[String] = ["the drag to the right", "the drag to the left", "the drag back"]
    var targets: Array[Vector2] = [Vector2(0.95, 0.5), Vector2(0.05, 0.5), Vector2(0.5004, 0.6)]
    for i in range(motions.size()):
        _move(editor, targets[i])
        assert_eq(editor.points.size(), 5, "%s keeps every point" % motions[i])
        _assert_between(editor, 2, motions[i])
    _button(editor, Vector2(0.5004, 0.6), false)
    editor.free()


func test_a_point_dragged_between_neighbours_on_the_same_x_stays_on_it() -> void:
    var editor := _editor(
        PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.5, 0.2), Vector2(0.5, 0.5), Vector2(0.5, 0.8), Vector2(1.0, 1.0)])
    )
    _button(editor, Vector2(0.5, 0.5), true)
    _move(editor, Vector2(0.9, 0.5))
    assert_almost_eq(editor.points[2].x, 0.5, 1e-6, "a point with no room in x stays where its neighbours are")
    _move(editor, Vector2(0.1, 0.5))
    assert_almost_eq(editor.points[2].x, 0.5, 1e-6, "on either side")
    _button(editor, Vector2(0.1, 0.5), false)
    editor.free()


func test_a_point_added_between_near_neighbours_lands_between_them() -> void:
    var editor := _editor(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.5, 0.2), Vector2(0.5008, 0.8), Vector2(1.0, 1.0)]))
    _button(editor, Vector2(0.5004, 0.5), true)
    assert_eq(editor.points.size(), 5, "a press away from every point adds one")
    assert_eq(editor._dragging, 2, "between the two near points")
    _assert_between(editor, 2, "the press")
    _button(editor, Vector2(0.5004, 0.5), false)
    editor.free()


func test_a_drag_between_far_neighbours_still_stops_the_margin_short_of_each() -> void:
    var editor := _editor(
        PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.3, 0.3), Vector2(0.5, 0.5), Vector2(0.7, 0.7), Vector2(1.0, 1.0)])
    )
    _button(editor, Vector2(0.5, 0.5), true)
    _move(editor, Vector2(0.95, 0.5))
    assert_almost_eq(editor.points[2].x, 0.7 - 1e-3, 1e-6, "a drag right stops 1e-3 short of the right neighbour")
    _move(editor, Vector2(0.05, 0.5))
    assert_almost_eq(editor.points[2].x, 0.3 + 1e-3, 1e-6, "a drag left stops 1e-3 short of the left neighbour")
    _button(editor, Vector2(0.05, 0.5), false)
    editor.free()
