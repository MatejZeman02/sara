## The two stroke faults seen once on Windows.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Fault 6: the first mouse stroke after a launch drew its first dab, then
## nothing for about 125 px, then the rest. A fresh stamp brush takes the
## pointer for a pen, and until eleven plain motions had said otherwise every
## motion of a mouse at pressure 0 laid a dab at no opacity. A pressed motion
## with nothing a pen reports now waits while no pen has been seen, and once the
## streak says mouse the stroke is laid from its press at full pressure, which holds those motions so a pen's
## first stroke opens as its next.
##
## Fault 5: a pen stroke drew a line from the pen's spot towards Windows'
## cursor. A press that came while the cursor policy knew no pen was read from
## the display server's pointer, which under Windows Ink is where the mouse was
## left. The press is now where the pointer is until the next motion.
extends "res://tests/test_framework.gd"

## The brush needs a RenderingDevice, and the window a display.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

## Where the stroke starts, how far each motion carries it, and how many there
## are: 150 px, longer than the gap that was seen.
const FROM := Vector2(40.0, 60.0)
const STEP := Vector2(6.0, 0.0)
const MOTIONS := 25

const PEN_PRESS := Vector2(642.5, 118.25)

var _host: Node = null


func before_each() -> void:
    SaCursorPolicy.forget_pointer_device()
    _host = Node.new()
    _host.name = "TwoStrokeFaultsTestHost"
    EventBus.add_child(_host)


func after_each() -> void:
    SaCursorPolicy.forget_pointer_device()
    if _host != null:
        _host.free()
        _host = null


func _motion(pressure: float, tilt: Vector2 = Vector2.ZERO, at: Vector2 = Vector2.ZERO) -> InputEventMouseMotion:
    var motion := InputEventMouseMotion.new()
    motion.pressure = pressure
    motion.tilt = tilt
    motion.position = at
    return motion


func _button(pressed: bool, at: Vector2 = Vector2.ZERO) -> InputEventMouseButton:
    var button := InputEventMouseButton.new()
    button.button_index = MOUSE_BUTTON_LEFT
    button.pressed = pressed
    button.position = at
    return button


func _fresh_brush(machine: ToolMachine) -> Object:
    machine.set_active_tool(&"brush")
    var brush: Object = machine.active_tool
    brush.settings.opacity_by_pressure = true
    # A small tip, so the stroke is many dabs and a gap would be many of them.
    brush.settings.radius = 4.0 / 256.0
    return brush


func test_the_first_mouse_stroke_after_a_launch_is_whole() -> void:
    var surface := Fixtures.make_surface(Vector2i(256, 256))
    var machine := Fixtures.make_bound_machine(surface)
    var brush := _fresh_brush(machine)
    assert_true(brush.is_tablet, "A fresh brush takes the pointer for a pen, the branch this is about")
    # The gap was dabs at no opacity rather than no dabs, and the dump keeps a
    # handful of a stroke's, so the newest dab is read after every motion.
    surface.view.mouse_position = FROM
    brush.handle_input(_button(true))
    var reached := FROM.x
    for i in range(1, MOTIONS + 1):
        surface.view.mouse_position = FROM + STEP * i
        brush.handle_input(_motion(0.0))
        var newest: SaDabParams = brush.last_dab
        # The stamp brush's streak is the cursor policy's, ten plain motions.
        if i <= SaCursorPolicy.MOUSE_MOTION_STREAK:
            assert_null(newest, "Motion %d waits until the pointer shows what it is" % i)
            continue
        assert_not_null(newest, "Motion %d has a dab behind it" % i)
        assert_true(newest.opacity > 0.9, "The newest dab after motion %d is at full pressure, %f" % [i, newest.opacity])
        assert_true(newest.position.x >= reached, "and no further back than the last, %s" % newest.position)
        reached = newest.position.x
    assert_false(brush.is_tablet, "Eleven pressed motions with no pressure and no tilt are the mouse")
    assert_eq(brush.sampled_dabs[0].position, FROM, "The first dab is the press's")
    brush.handle_input(_button(false))
    assert_true(brush.stroke_info.dab_index > MOTIONS, "The stroke laid its dabs, %d" % brush.stroke_info.dab_index)
    # The walk trails the pointer by one report, so its end is the motion before.
    var walked := (FROM + STEP * (MOTIONS - 2)).x
    assert_true(reached >= walked, "and they reach the end of the walk, %.1f" % reached)
    Fixtures.teardown(surface, machine)


## The rule must not take a pen for a mouse: a pen the brush has seen keeps a
## pressed 0, its lightest touch, at no opacity.
func test_a_pen_the_brush_has_seen_keeps_a_pressed_zero() -> void:
    var surface := Fixtures.make_surface(Vector2i(256, 256))
    var machine := Fixtures.make_bound_machine(surface)
    var brush := _fresh_brush(machine)
    surface.view.mouse_position = FROM
    brush.handle_input(_motion(0.0, Vector2(0.1, 0.0)))
    brush.handle_input(_button(true))
    # Fewer than the streak, which hands a pen that has gone quiet back to the
    # mouse whether it is pressed or not.
    for i in range(1, 6):
        surface.view.mouse_position = FROM + STEP * i
        brush.handle_input(_motion(0.0))
        assert_true(brush.is_tablet, "A leaning hover proved the pen, and its pressed 0 on motion %d is still the pen" % i)
    brush.handle_input(_button(false))
    Fixtures.teardown(surface, machine)


func _window() -> Window:
    var window := Window.new()
    window.borderless = true
    window.size = Vector2i(1280, 720)
    _host.add_child(window)
    window.show()
    return window


## A pen's press with no hover before it, after the mouse had the pointer, is
## read where the pen came down and not where the display server's pointer is.
func test_a_press_with_no_hover_is_where_it_landed() -> void:
    var window := _window()
    for i in SaCursorPolicy.MOUSE_MOTION_STREAK + 1:
        SaCursorPolicy.note_pointer_device(_motion(0.0, Vector2.ZERO, Vector2(5.0, 5.0)), window)
    assert_false(SaCursorPolicy.pointer_is_tablet, "The mouse moved last")
    var godots := SaCursorPolicy.pointer_in(window)
    assert_false(godots == PEN_PRESS, "The display server's pointer is somewhere else")

    SaCursorPolicy.note_pointer_device(_button(true, PEN_PRESS), window)
    assert_eq(SaCursorPolicy.pointer_in(window), PEN_PRESS, "The press is read where it landed")
    var inside := Control.new()
    inside.position = Vector2(100.0, 50.0)
    window.add_child(inside)
    assert_eq(SaCursorPolicy.pointer_in(inside), PEN_PRESS - inside.position, "and so is a control the stroke starts on")

    var drawn := PEN_PRESS + STEP
    SaCursorPolicy.note_pointer_device(_motion(0.3, Vector2.ZERO, drawn), window)
    assert_eq(SaCursorPolicy.pointer_in(window), drawn, "The pen's first motion carries it on from there")


## A mouse's press is kept only until the mouse moves, so the next motion reads
## the display server again as it always did.
func test_a_mouse_moves_on_from_its_press() -> void:
    var window := _window()
    var godots := SaCursorPolicy.pointer_in(window)
    SaCursorPolicy.note_pointer_device(_button(true, PEN_PRESS), window)
    assert_eq(SaCursorPolicy.pointer_in(window), PEN_PRESS, "The press, until a motion")
    SaCursorPolicy.note_pointer_device(_motion(0.0), window)
    assert_eq(SaCursorPolicy.pointer_in(window), godots, "and Godot's answer after one")
    SaCursorPolicy.note_pointer_device(_button(false, PEN_PRESS), window)
    assert_eq(SaCursorPolicy.pointer_in(window), godots, "A release with no pen keeps nothing")
