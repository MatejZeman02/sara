## A Curves point goes with a right-click, and with Delete once it is pressed.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A point goes with a right click or Delete, beside dragging it off the
## graph. The editor is fed the events a window would give it, detached, so no
## GPU and no window is needed. Delete is accepted whether or not a point goes,
## which is what keeps it from reaching the key that clears the layer.
extends "res://tests/test_framework.gd"


func _editor() -> SaCurveEditor:
    var editor := SaCurveEditor.new()
    editor.size = editor.custom_minimum_size
    editor.set_points(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.5, 0.7), Vector2(1.0, 1.0)]))
    return editor


## Where *point* is on *editor*, in its own units. Its size is whatever its
## minimum lets it be, so it is read rather than assumed.
func _at(editor: SaCurveEditor, point: Vector2) -> Vector2:
    return Vector2(point.x * editor.size.x, (1.0 - point.y) * editor.size.y)


func _click(editor: SaCurveEditor, button: int, at: Vector2, pressed: bool = true) -> void:
    var event := InputEventMouseButton.new()
    event.button_index = button as MouseButton
    event.pressed = pressed
    event.position = at
    editor._gui_input(event)


func _delete(editor: SaCurveEditor) -> void:
    var event := InputEventKey.new()
    event.keycode = KEY_DELETE
    event.pressed = true
    editor._gui_input(event)


func test_a_right_click_removes_an_inner_point() -> void:
    var editor := _editor()

    _click(editor, MOUSE_BUTTON_RIGHT, _at(editor, Vector2(0.5, 0.7)))

    assert_eq(editor.points.size(), 2, "the inner point is gone")
    assert_eq(editor.points[0], Vector2(0.0, 0.0), "and the first end is as it was")
    assert_eq(editor.points[1], Vector2(1.0, 1.0), "and the last")
    editor.free()


func test_a_right_click_keeps_both_ends_and_adds_nothing() -> void:
    var editor := _editor()

    _click(editor, MOUSE_BUTTON_RIGHT, _at(editor, Vector2(0.0, 0.0)))
    _click(editor, MOUSE_BUTTON_RIGHT, _at(editor, Vector2(1.0, 1.0)))
    _click(editor, MOUSE_BUTTON_RIGHT, _at(editor, Vector2(0.25, 0.9)))

    assert_eq(editor.points.size(), 3, "the ends stay and a right-click over nothing adds no point")
    editor.free()


func test_a_pressed_point_goes_on_delete() -> void:
    var editor := _editor()
    _click(editor, MOUSE_BUTTON_LEFT, _at(editor, Vector2(0.5, 0.7)))
    _click(editor, MOUSE_BUTTON_LEFT, _at(editor, Vector2(0.5, 0.7)), false)

    _delete(editor)

    assert_eq(editor.points.size(), 2, "the point pressed last is gone though the button is up")
    editor.free()


func test_a_point_just_added_is_the_one_delete_removes() -> void:
    var editor := _editor()
    _click(editor, MOUSE_BUTTON_LEFT, _at(editor, Vector2(0.25, 0.4)))
    _click(editor, MOUSE_BUTTON_LEFT, _at(editor, Vector2(0.25, 0.4)), false)
    assert_eq(editor.points.size(), 4, "a press over nothing adds a point")

    _delete(editor)

    assert_eq(editor.points.size(), 3, "and Delete takes that one away")
    assert_almost_eq(editor.points[1].x, 0.5, 1e-6, "leaving the one that was there")
    editor.free()


func test_delete_keeps_both_ends() -> void:
    var editor := _editor()

    _click(editor, MOUSE_BUTTON_LEFT, _at(editor, Vector2(0.0, 0.0)))
    _click(editor, MOUSE_BUTTON_LEFT, _at(editor, Vector2(0.0, 0.0)), false)
    _delete(editor)
    _click(editor, MOUSE_BUTTON_LEFT, _at(editor, Vector2(1.0, 1.0)))
    _click(editor, MOUSE_BUTTON_LEFT, _at(editor, Vector2(1.0, 1.0)), false)
    _delete(editor)

    assert_eq(editor.points.size(), 3, "neither end goes")
    editor.free()


func test_a_removed_point_is_not_removed_twice() -> void:
    var editor := _editor()
    editor.set_points(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.3, 0.4), Vector2(0.6, 0.7), Vector2(1.0, 1.0)]))
    _click(editor, MOUSE_BUTTON_LEFT, _at(editor, Vector2(0.3, 0.4)))
    _click(editor, MOUSE_BUTTON_LEFT, _at(editor, Vector2(0.3, 0.4)), false)

    _delete(editor)
    _delete(editor)

    assert_eq(editor.points.size(), 3, "a second Delete finds nothing picked and removes nothing")
    editor.free()


func test_delete_without_a_point_picked_changes_nothing() -> void:
    var editor := _editor()

    _delete(editor)

    assert_eq(editor.points.size(), 3, "all three points stay")
    editor.free()


func test_a_removal_says_the_curve_changed() -> void:
    var editor := _editor()
    var changes := [0]
    editor.curve_changed.connect(func() -> void: changes[0] += 1)

    _click(editor, MOUSE_BUTTON_RIGHT, _at(editor, Vector2(0.5, 0.7)))

    assert_eq(changes[0], 1, "once")
    editor.free()
