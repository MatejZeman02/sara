## The shift drag that resizes the brush, and the ring that travels with it.
##
## The painter holds shift, drags sideways to
## grow the brush, and the preview circle followed the hand, so the size they
## chose was shown somewhere other than where their next stroke would start. The
## gesture pins where the application thinks the pointer is for as long as it
## lasts, and the drag's own maths keeps reading the event, so the radius still
## follows the hand.
extends "res://tests/test_framework.gd"

## Builds a surface with a real easel.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

const PRESS_AT := Vector2(400.0, 300.0)


func _button(at: Vector2, pressed: bool, shift: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    event.shift_pressed = shift
    event.position = at
    event.global_position = at
    return event


func _motion(at: Vector2, from: Vector2) -> InputEventMouseMotion:
    var event := InputEventMouseMotion.new()
    event.position = at
    event.global_position = at
    event.relative = at - from
    return event


## The machine has to be in the tree, because the pin names the window it is in.
##
## Under an autoload rather than under the root, for the reason
## `test_windows_open` gives: the runner calls this from its own `_ready`, and a
## parent that is mid-`_ready` rejects `add_child` outright, which leaves the
## node orphaned and makes a working pin look broken.
func _machine_in_tree(surface: SaSurface) -> ToolMachine:
    var machine := Fixtures.make_bound_machine(surface)
    var host := Node.new()
    host.name = "BrushSizeDragHost"
    EventBus.add_child(host)
    host.add_child(machine)
    machine.set_active_tool(&"brush")
    return machine


func _teardown(surface: SaSurface, machine: ToolMachine) -> void:
    SaCursorPolicy.unpin_pointer(machine)
    var host := machine.get_parent()
    Fixtures.teardown(surface, machine)
    if host != null:
        host.free()


func test_the_ring_stays_where_the_press_was_for_the_whole_drag() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    assert_not_null(tree, "This needs the real tree, because the pin names a window")
    if tree == null:
        return
    var surface := Fixtures.make_surface()
    var machine := _machine_in_tree(surface)

    machine.handle_input(_button(PRESS_AT, true, true))
    assert_true(SaCursorPolicy.pointer_is_pinned(), "The press pins the ring")
    assert_eq(SaCursorPolicy.pointer_in_window(tree.root), PRESS_AT, "where the press was")

    var dragged := PRESS_AT + Vector2(40.0, 0.0)
    machine.handle_input(_motion(dragged, PRESS_AT))
    assert_eq(SaCursorPolicy.pointer_in_window(tree.root), PRESS_AT, "and forty pixels of drag do not move it")

    machine.handle_input(_button(dragged, false, false))
    assert_false(SaCursorPolicy.pointer_is_pinned(), "The release frees it")
    _teardown(surface, machine)


## The radius still follows the hand. Pinning the cursor must not pin the thing
## the gesture is for.
func test_the_radius_still_follows_the_hand() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    if tree == null:
        return
    var surface := Fixtures.make_surface()
    var machine := _machine_in_tree(surface)
    var settings: Resource = machine.active_tool.get("settings")
    assert_not_null(settings, "The brush has settings with a radius")
    if settings == null:
        _teardown(surface, machine)
        return
    var before: float = settings.radius

    machine.handle_input(_button(PRESS_AT, true, true))
    machine.handle_input(_motion(PRESS_AT + Vector2(80.0, 0.0), PRESS_AT))
    assert_true(settings.radius > before, "Dragging right grew the brush: %f -> %f" % [before, settings.radius])

    machine.handle_input(_button(PRESS_AT + Vector2(80.0, 0.0), false, false))
    settings.radius = before
    _teardown(surface, machine)


## A press without shift is a stroke, and a stroke must not freeze the cursor.
func test_a_plain_press_pins_nothing() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    if tree == null:
        return
    var surface := Fixtures.make_surface()
    var machine := _machine_in_tree(surface)

    machine.handle_input(_button(PRESS_AT, true, false))
    assert_false(SaCursorPolicy.pointer_is_pinned(), "A plain press leaves the cursor alone")

    machine.handle_input(_button(PRESS_AT, false, false))
    _teardown(surface, machine)


## A pin whose gesture ended without a release, because the window lost focus or
## the tool was swapped, is dropped on the next frame rather than surviving for
## the rest of the session. Its own pin only: the idle machine on the info
## docker's scratchpad must leave the main canvas's gesture alone.
func test_a_stale_pin_is_dropped_within_a_frame() -> void:
    var surface := Fixtures.make_surface()
    var machine := Fixtures.make_bound_machine(surface)
    var window := Window.new()

    SaCursorPolicy.pin_pointer(machine, window, Vector2(10.0, 10.0))
    assert_true(SaCursorPolicy.pointer_is_pinned(), "This machine pinned the cursor")
    machine._process(0.016)
    assert_false(SaCursorPolicy.pointer_is_pinned(), "and is not resizing, so it is gone")

    window.free()
    Fixtures.teardown(surface, machine)
