## The patch tool's circle answers the bracket keys and a shift-drag, as a
## brush's size does.
##
## The circle changes by more than its slider. The tool keeps its size as its
## own value in pixels, [method ToolState.own_size], and the gestures find it
## through that door, so nothing under `ui/` or `tools/` names the patch tool.
extends "res://tests/test_framework.gd"

## Builds a surface with a real easel.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

const StatePatchScript = preload("res://modules/sara-base-modules/base/patch/state_patch.gd")


## A bracket key as a keyboard sends it.
func _bracket(keycode: Key) -> InputEventKey:
    var event := InputEventKey.new()
    event.keycode = keycode
    event.physical_keycode = keycode
    event.pressed = true
    return event


## What `SaShortcutRouter._handle_brush` does with a key, step for step.
func _press_key(machine: ToolMachine, keycode: Key) -> void:
    var step := SaShortcutKeys.brush_size_direction(_bracket(keycode))
    var delta := SaShortcutKeys.brush_size_step(SaShortcutKeys.current_brush_radius(machine), step)
    SaShortcutKeys.nudge_brush_radius(machine, delta)


func _button(at: Vector2, pressed: bool, shift: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    event.shift_pressed = shift
    event.position = at
    event.global_position = at
    return event


func _motion(at: Vector2) -> InputEventMouseMotion:
    var event := InputEventMouseMotion.new()
    event.position = at
    event.global_position = at
    return event


func test_the_brackets_grow_and_shrink_the_circle() -> void:
    var surface := Fixtures.make_surface()
    var machine := Fixtures.make_bound_machine(surface)
    machine.set_active_tool(&"patch")
    var patch: StatePatchScript = machine.get_tool(&"patch")
    var before := patch.region_size
    assert_almost_eq(SaShortcutKeys.current_brush_radius(machine), before, 0.0001, "The keys read the circle's width")

    _press_key(machine, KEY_BRACKETRIGHT)
    var grown := before * (1.0 + SaShortcutKeys.BRUSH_SIZE_RATIO)
    assert_almost_eq(patch.region_size, grown, 0.0001, "] widens the circle by the proportion a brush grows by")

    _press_key(machine, KEY_BRACKETLEFT)
    assert_almost_eq(patch.region_size, grown * (1.0 - SaShortcutKeys.BRUSH_SIZE_RATIO), 0.0001, "and [ narrows it the same way")

    for _i: int in 200:
        _press_key(machine, KEY_BRACKETLEFT)
    assert_almost_eq(patch.region_size, StatePatchScript.SIZE_MIN, 0.0001, "Held down, [ stops where the Size row does")

    Fixtures.teardown(surface, machine)


func test_a_shift_drag_resizes_the_circle_without_painting() -> void:
    var surface := Fixtures.make_surface()
    var machine := Fixtures.make_bound_machine(surface)
    machine.set_active_tool(&"patch")
    surface.view.zoom = 2.0
    var patch: StatePatchScript = machine.get_tool(&"patch")
    var before := patch.region_size

    machine.handle_input(_button(Vector2(100.0, 100.0), true, true))
    machine.handle_input(_motion(Vector2(130.0, 100.0)))
    # The ring is drawn at half the width, so thirty screen pixels at 2x move
    # the edge fifteen document pixels and the width thirty.
    assert_almost_eq(patch.region_size, before + 30.0, 0.0001, "The circle's edge follows the hand at any zoom")
    assert_true(patch.preview_shape().is_empty(), "and the press that started it painted no region")

    machine.handle_input(_motion(Vector2(100000.0, 100.0)))
    assert_almost_eq(patch.region_size, StatePatchScript.SIZE_MAX, 0.0001, "A long drag stops at the Size row's top")

    machine.handle_input(_button(Vector2(100000.0, 100.0), false, false))
    var resized := patch.region_size
    machine.handle_input(_motion(Vector2(50.0, 100.0)))
    assert_almost_eq(patch.region_size, resized, 0.0001, "Motion after the release resizes nothing")

    Fixtures.teardown(surface, machine)
