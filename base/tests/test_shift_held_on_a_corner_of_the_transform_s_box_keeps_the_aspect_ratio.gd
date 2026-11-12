## Shift held on a corner of the transform's box keeps the
## aspect ratio.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Shift keeps the ratio under the transform tool. A box of 200 by 100 has its bottom right corner
## dragged by 60 across
## and 10 down, with Shift and without, Shift pressed and let go mid-drag, the
## corner taken past the opposite one, and Shift on an edge handle, which
## keeps the ratio as a corner does. The picture is
## `scenarios/shift-held-on-a-corner-of-the-transform-s-box-keeps-the-aspect-ratio.json`.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true
const Fixtures = preload("res://tests/fixtures.gd")
const StateTransformScript = preload("res://modules/sara-base-modules/base/transform/state_transform.gd")

const BOX := Rect2i(300, 300, 200, 100)
const CORNER := Vector2(500, 400)
const TRAVEL := Vector2(60, 10)


func _tool() -> Array:
    var surface := Fixtures.make_surface(Vector2i(1024, 1024))
    var machine := Fixtures.make_bound_machine(surface)
    var document := surface.get_document()
    document.active_layer.get_or_create_chunk(Vector2i(1, 1))
    document.selection.select_rect(BOX)
    machine.set_active_tool(&"transform")
    return [surface, machine, machine.active_tool]


func _press(tool: StateTransformScript, surface: SaSurface, at: Vector2, shift: bool) -> void:
    surface.view.mouse_position = at
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = true
    event.shift_pressed = shift
    tool.handle_input(event)


func _move(tool: StateTransformScript, surface: SaSurface, to: Vector2, shift: bool) -> void:
    surface.view.mouse_position = to
    var event := InputEventMouseMotion.new()
    event.shift_pressed = shift
    tool.handle_input(event)


func _shift_key(tool: StateTransformScript, pressed: bool) -> void:
    var event := InputEventKey.new()
    event.keycode = KEY_SHIFT
    event.pressed = pressed
    tool.handle_input(event)


## The box's width over its height, read off the quad the tool draws.
func _ratio(tool: StateTransformScript) -> float:
    var quad: PackedVector2Array = tool.pending_quad()
    return (quad[1] - quad[0]).length() / (quad[3] - quad[0]).length()


func test_a_corner_with_shift_scales_both_axes_by_one_factor() -> void:
    var parts := _tool()
    var surface: SaSurface = parts[0]
    var tool: StateTransformScript = parts[2]
    assert_eq(tool.target_box(), BOX, "The box is the 200 by 100 the layer was lifted by")
    _press(tool, surface, CORNER, true)
    _move(tool, surface, CORNER + TRAVEL, true)
    var held: Transform2D = tool.matrix
    assert_true(tool.is_moving(), "The drag lifted the layer")
    assert_almost_eq(held.x.x, held.y.y, 1e-5, "The two scales are one, %.4f and %.4f" % [held.x.x, held.y.y])
    assert_almost_eq(held.x.x, 1.26, 1e-4, "the factor of the pointer's travel along the diagonal")
    assert_almost_eq(_ratio(tool), 2.0, 1e-4, "and the box stands at two to one")
    Fixtures.teardown(parts[0], parts[1])

    var free := _tool()
    var free_surface: SaSurface = free[0]
    var free_tool: StateTransformScript = free[2]
    _press(free_tool, free_surface, CORNER, false)
    _move(free_tool, free_surface, CORNER + TRAVEL, false)
    var loose: Transform2D = free_tool.matrix
    assert_almost_eq(loose.x.x, 1.3, 1e-4, "Without Shift the width follows the pointer")
    assert_almost_eq(loose.y.y, 1.1, 1e-4, "and the height on its own")
    assert_true(absf(_ratio(free_tool) - 2.0) > 0.1, "so the ratio is gone, %.3f" % _ratio(free_tool))
    Fixtures.teardown(free[0], free[1])


func test_shift_pressed_and_let_go_mid_drag_holds_and_frees_the_ratio() -> void:
    var parts := _tool()
    var surface: SaSurface = parts[0]
    var tool: StateTransformScript = parts[2]
    _press(tool, surface, CORNER, false)
    _move(tool, surface, CORNER + TRAVEL, false)
    assert_true(absf(_ratio(tool) - 2.0) > 0.1, "A plain drag stretches the box")
    _shift_key(tool, true)
    assert_almost_eq(_ratio(tool), 2.0, 1e-4, "Shift pressed with the hand still snaps it to two to one")
    _move(tool, surface, CORNER + Vector2(90, -20), true)
    assert_almost_eq(tool.matrix.x.x, tool.matrix.y.y, 1e-5, "and every motion after keeps one factor")
    assert_almost_eq(_ratio(tool), 2.0, 1e-4, "and the ratio")
    _move(tool, surface, CORNER + Vector2(90, -20), false)
    assert_true(absf(_ratio(tool) - 2.0) > 0.1, "Shift let go frees the axes, %.3f" % _ratio(tool))
    _shift_key(tool, true)
    _shift_key(tool, false)
    assert_true(absf(_ratio(tool) - 2.0) > 0.1, "and so does its key let go with the hand still")
    Fixtures.teardown(parts[0], parts[1])


func test_a_corner_dragged_past_the_opposite_one_keeps_the_ratio_flipped() -> void:
    var parts := _tool()
    var surface: SaSurface = parts[0]
    var tool: StateTransformScript = parts[2]
    _press(tool, surface, CORNER, true)
    _move(tool, surface, Vector2(200, 260), true)
    var flipped: Transform2D = tool.matrix
    assert_true(flipped.x.x < 0.0, "The box is flipped across, %.4f" % flipped.x.x)
    assert_almost_eq(flipped.x.x, flipped.y.y, 1e-5, "and down by the same factor, sign and all")
    assert_almost_eq(_ratio(tool), 2.0, 1e-4, "so its ratio is kept")
    Fixtures.teardown(parts[0], parts[1])


func test_shift_on_an_edge_handle_keeps_the_ratio_too() -> void:
    var parts := _tool()
    var surface: SaSurface = parts[0]
    var tool: StateTransformScript = parts[2]
    _press(tool, surface, Vector2(500, 350), true)
    _move(tool, surface, Vector2(560, 390), true)
    assert_almost_eq(tool.move_skew(), 0.0, 1e-5, "The right edge no longer leans the box under Shift")
    assert_almost_eq(_ratio(tool), 2.0, 1e-4, "it keeps two to one as a corner does")
    Fixtures.teardown(parts[0], parts[1])
