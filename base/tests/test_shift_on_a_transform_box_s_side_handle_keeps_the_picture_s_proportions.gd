## Shift on a transform box's side handle keeps the picture's proportions.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Holding Shift keeps the fixed aspect ratio on a middle point as on a corner
## one. Under Normal a side handle with Shift scales both axes by the dragged
## axis's factor about the box's middle line, Ctrl on it shears, as Photoshop's
## skew chord does, and a plain drag stretches the one axis. The picture is
## `scenarios/shift-on-a-transform-box-s-side-handle-keeps-the-picture-s-proportions.json`.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true
const Fixtures = preload("res://tests/fixtures.gd")
const StateTransformScript = preload("res://modules/sara-base-modules/base/transform/state_transform.gd")

const BOX := Rect2i(300, 300, 200, 100)
const RIGHT_SIDE := Vector2(500, 350)
const BOTTOM_SIDE := Vector2(400, 400)


func _tool() -> Array:
    var surface := Fixtures.make_surface(Vector2i(1024, 1024))
    var machine := Fixtures.make_bound_machine(surface)
    var document := surface.get_document()
    document.active_layer.get_or_create_chunk(Vector2i(1, 1))
    document.selection.select_rect(BOX)
    machine.set_active_tool(&"transform")
    return [surface, machine, machine.active_tool]


## A press at *from* with the modifiers named and a motion to *to* carrying
## the same, left held, and the box the tool draws after it.
func _drag(parts: Array, from: Vector2, to: Vector2, shift: bool, ctrl: bool) -> Rect2:
    var surface: SaSurface = parts[0]
    var tool: StateTransformScript = parts[2]
    surface.view.mouse_position = from
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    press.shift_pressed = shift
    press.ctrl_pressed = ctrl
    tool.handle_input(press)
    surface.view.mouse_position = to
    var motion := InputEventMouseMotion.new()
    motion.shift_pressed = shift
    motion.ctrl_pressed = ctrl
    tool.handle_input(motion)
    var quad: PackedVector2Array = tool.pending_quad()
    var box := Rect2(quad[0], Vector2.ZERO)
    for corner: Vector2 in quad:
        box = box.expand(corner)
    return box


func _assert_box(box: Rect2, wanted: Rect2, what: String) -> void:
    assert_almost_eq(box.position.x, wanted.position.x, 1e-3, "%s, left at %.3f" % [what, box.position.x])
    assert_almost_eq(box.position.y, wanted.position.y, 1e-3, "%s, top at %.3f" % [what, box.position.y])
    assert_almost_eq(box.size.x, wanted.size.x, 1e-3, "%s, %.3f wide" % [what, box.size.x])
    assert_almost_eq(box.size.y, wanted.size.y, 1e-3, "%s, %.3f high" % [what, box.size.y])


func test_shift_on_the_right_side_scales_both_axes_about_the_middle_line() -> void:
    var parts := _tool()
    var tool: StateTransformScript = parts[2]
    assert_eq(tool.target_box(), BOX, "The box is the 200 by 100 the layer was lifted by")
    var box := _drag(parts, RIGHT_SIDE, RIGHT_SIDE + Vector2(100, 0), true, false)
    _assert_box(box, Rect2(300, 275, 300, 150), "Shift and the right side 100 to the right")
    assert_almost_eq(box.get_center().y, 350.0, 1e-3, "and the vertical middle is where it was")
    assert_almost_eq(tool.matrix.x.x, tool.matrix.y.y, 1e-5, "one factor on both axes")
    assert_almost_eq(tool.move_skew(), 0.0, 1e-5, "and no lean")
    Fixtures.teardown(parts[0], parts[1])


## The other axis follows the dragged one only, so a pointer that wanders
## across the side's line on the way changes nothing.
func test_shift_reads_the_dragged_axis_only() -> void:
    var parts := _tool()
    var box := _drag(parts, RIGHT_SIDE, RIGHT_SIDE + Vector2(100, 40), true, false)
    _assert_box(box, Rect2(300, 275, 300, 150), "Shift and the right side 100 across and 40 down")
    Fixtures.teardown(parts[0], parts[1])


func test_shift_on_the_bottom_side_scales_the_width_about_the_middle_column() -> void:
    var parts := _tool()
    var box := _drag(parts, BOTTOM_SIDE, BOTTOM_SIDE + Vector2(0, 50), true, false)
    _assert_box(box, Rect2(250, 300, 300, 150), "Shift and the bottom side 50 down")
    Fixtures.teardown(parts[0], parts[1])


## A side dragged past the opposite one flips both axes with the one factor,
## as a corner's Shift does.
func test_shift_past_the_opposite_side_keeps_the_ratio_flipped() -> void:
    var parts := _tool()
    var tool: StateTransformScript = parts[2]
    var box := _drag(parts, RIGHT_SIDE, Vector2(200, 350), true, false)
    _assert_box(box, Rect2(200, 325, 100, 50), "Shift and the right side past the left")
    assert_almost_eq(tool.matrix.x.x, -0.5, 1e-5, "flipped across")
    assert_almost_eq(tool.matrix.y.y, -0.5, 1e-5, "and down by the same factor")
    Fixtures.teardown(parts[0], parts[1])


func test_ctrl_on_the_right_side_shears() -> void:
    var parts := _tool()
    var tool: StateTransformScript = parts[2]
    _drag(parts, RIGHT_SIDE, RIGHT_SIDE + Vector2(0, 40), false, true)
    assert_true(absf(tool.move_skew()) > 0.01, "Ctrl and the right side lean the box, %.4f" % tool.move_skew())
    var quad: PackedVector2Array = tool.pending_quad()
    assert_almost_eq(quad[0].x, 300.0, 1e-3, "its left side held")
    assert_almost_eq(quad[3].x, 300.0, 1e-3, "both of its corners")
    Fixtures.teardown(parts[0], parts[1])


func test_neither_modifier_stretches_the_one_axis() -> void:
    var parts := _tool()
    var tool: StateTransformScript = parts[2]
    var box := _drag(parts, RIGHT_SIDE, RIGHT_SIDE + Vector2(100, 0), false, false)
    _assert_box(box, Rect2(300, 300, 300, 100), "The right side 100 to the right")
    assert_almost_eq(tool.move_skew(), 0.0, 1e-5, "with no lean")
    Fixtures.teardown(parts[0], parts[1])


## Shift on a side under Perspective still moves the side alone, which is
## that mode's own reading of the modifier.
func test_perspective_keeps_its_shift() -> void:
    var parts := _tool()
    var tool: StateTransformScript = parts[2]
    tool.transform_mode = StateTransformScript.Mode.PERSPECTIVE
    var box := _drag(parts, RIGHT_SIDE, RIGHT_SIDE + Vector2(100, 0), true, false)
    _assert_box(box, Rect2(300, 300, 300, 100), "Perspective, Shift and the right side")
    Fixtures.teardown(parts[0], parts[1])


## Ctrl is the shear's key over the box, so a quick tool a profile puts on
## Ctrl, the Krita profile's Eyedropper, does not take the hand from the box.
func test_the_transform_reads_ctrl_itself() -> void:
    var parts := _tool()
    var machine: ToolMachine = parts[1]
    var descriptor: SaToolDescriptor = machine.get_descriptor(&"transform")
    assert_true(SaToolDescriptor.reads_key(descriptor, KEY_CTRL), "The transform reads Ctrl on its own press")
    Fixtures.teardown(parts[0], parts[1])
