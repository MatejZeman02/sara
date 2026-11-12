## A pen pressed and held still paints, in the stamp brush and the noise brush
## alike.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The press waits for the first motion's pressure, since a press carries none.
## Windows Ink sends no motion while a pen rests, so a pen held still laid
## nothing until it moved or lifted. The press now lays itself once it has
## waited [constant PRESS_WAIT_MS], and not before.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

const FROM := Vector2(40.0, 40.0)


class NoiseRecorder:
    extends "res://modules/sara-noise-brush-engine/state_noise_brush.gd"

    var pressures: Array[float] = []

    func _point(at: Vector2, pressure: float, tilt: Vector2, time_ms: float) -> void:
        pressures.append(pressure)
        super(at, pressure, tilt, time_ms)


func _hover(tool: Object, pressure: float, tilt: Vector2 = Vector2.ZERO) -> void:
    var hover := InputEventMouseMotion.new()
    hover.pressure = pressure
    hover.tilt = tilt
    tool.handle_input(hover)


func _button(tool: Object, pressed: bool) -> void:
    var button := InputEventMouseButton.new()
    button.button_index = MOUSE_BUTTON_LEFT
    button.pressed = pressed
    tool.handle_input(button)


func test_the_stamp_brush_lays_a_held_press_once_it_has_waited() -> void:
    var surface := Fixtures.make_surface(Vector2i(128, 128))
    var machine := Fixtures.make_bound_machine(surface)
    machine.set_active_tool(&"brush")
    var brush: Object = machine.active_tool
    surface.view.mouse_position = FROM
    _hover(brush, 0.0)
    _button(brush, true)
    var pressed: float = SaPenClock.now_ms()
    assert_false(brush.lay_waited_press(pressed + brush.PRESS_WAIT_MS * 0.5), "A press waits a moment for a motion")
    assert_eq(brush.sampled_dabs.size(), 0, "and lays nothing meanwhile")
    assert_true(brush.lay_waited_press(pressed + brush.PRESS_WAIT_MS * 2.0), "A pen held still past the wait")
    assert_eq(brush.sampled_dabs.size(), 1, "lays its press dab")
    assert_eq(brush.sampled_dabs[0].position, FROM, "where it pressed")
    assert_false(brush.lay_waited_press(pressed + brush.PRESS_WAIT_MS * 3.0), "and only once")
    _button(brush, false)
    assert_eq(brush.sampled_dabs.size(), 1, "The lift lays no second press dab")
    Fixtures.teardown(surface, machine)


func test_the_noise_brush_lays_a_held_press_once_it_has_waited() -> void:
    var surface := Fixtures.make_surface()
    var brush := NoiseRecorder.new()
    brush.surface = surface
    brush.stroke_seed = 7
    brush.settings.radius = 8.0 / 256.0
    surface.view.mouse_position = FROM
    # Ink's hover reports a lean, which is how the brush learns it is a pen.
    _hover(brush, 0.0, Vector2(0.1, 0.0))
    _button(brush, true)
    var pressed: float = SaPenClock.now_ms()
    assert_false(brush.lay_waited_press(pressed + brush.PRESS_WAIT_MS * 0.5), "A press waits a moment for a sample")
    assert_eq(brush.pressures.size(), 0, "and lays nothing meanwhile")
    assert_true(brush.lay_waited_press(pressed + brush.PRESS_WAIT_MS * 2.0), "A pen held still past the wait")
    assert_eq(brush.pressures.size(), 1, "lays its press")
    _button(brush, false)
    assert_eq(brush.pressures.size(), 1, "and the lift lays no second press")
    brush = null
    Fixtures.teardown(surface)
