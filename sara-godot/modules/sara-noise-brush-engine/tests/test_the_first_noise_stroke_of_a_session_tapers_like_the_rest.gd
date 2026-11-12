## The first noise stroke of a session tapers like the rest.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A pen pressed from no pressure reports what a mouse does, no pressure and no
## tilt, until its pressure rises. The brush took a pointer it had not yet seen
## report a pen's reading for a mouse, so the first stroke of a door session,
## which no hover reaches the brush in, laid its press and its first motion at a
## mouse's full pressure and opened at full width. A pointer that is neither yet
## now waits: its press as a pen's does, its plain motions until a pen's reading
## lays them at the none they reported, or a run of them, or the lift, lays them
## as a mouse's. `scripts/test_the_first_noise_stroke_of_a_door_session_tapers_like_the_rest.py`
## holds the widths in a real door session, and this the pressures every point
## is laid at, with no Sara.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const NoiseBrushScript = preload("res://modules/sara-noise-brush-engine/state_noise_brush.gd")

## Where a stroke starts and how far each motion carries it.
const FROM := Vector2(40.0, 40.0)
const STEP := Vector2(6.0, 0.0)
## A ramp's pressures, from none to a full press.
const RAMP: Array[float] = [0.0, 0.25, 0.5, 0.75, 1.0]


## The noise brush with every point's pressure written down.
class NoiseRecorder:
    extends "res://modules/sara-noise-brush-engine/state_noise_brush.gd"

    var pressures: Array[float] = []

    func _point(at: Vector2, pressure: float, tilt: Vector2, time_ms: float) -> void:
        pressures.append(pressure)
        super(at, pressure, tilt, time_ms)


func _brush(surface: SaSurface) -> NoiseRecorder:
    var brush := NoiseRecorder.new()
    brush.surface = surface
    brush.stroke_seed = 7
    brush.settings.radius = 8.0 / 256.0
    return brush


func _button(surface: SaSurface, tool: Object, pressed: bool, at: Vector2 = FROM) -> void:
    surface.view.mouse_position = at
    var button := InputEventMouseButton.new()
    button.button_index = MOUSE_BUTTON_LEFT
    button.pressed = pressed
    tool.handle_input(button)


func _motion(surface: SaSurface, tool: Object, at: Vector2, pressure: float) -> void:
    surface.view.mouse_position = at
    var motion := InputEventMouseMotion.new()
    motion.pressure = pressure
    tool.handle_input(motion)


## A stroke pressed at [constant FROM] and moved along x at each of *pressures*,
## with no hover before it, as a door session's first stroke is. Answers the
## pressures its points were laid at.
func _stroke(surface: SaSurface, brush: NoiseRecorder, pressures: Array[float]) -> Array[float]:
    brush.pressures.clear()
    _button(surface, brush, true)
    for i in pressures.size():
        _motion(surface, brush, FROM + STEP * (i + 1), pressures[i])
    _button(surface, brush, false, FROM + STEP * pressures.size())
    return brush.pressures.duplicate()


## *count* plain motions, as a mouse sends.
func _plain(count: int) -> Array[float]:
    var out: Array[float] = []
    out.resize(count)
    out.fill(0.0)
    return out


func test_a_first_stroke_from_no_pressure_opens_at_none_as_the_second_does() -> void:
    var surface := Fixtures.make_surface()
    var brush := _brush(surface)
    var first := _stroke(surface, brush, RAMP)
    assert_true(first.size() > RAMP.size(), "The first stroke laid its points, %d" % first.size())
    assert_almost_eq(first[0], 0.0, 1e-6, "Its press is laid at the none its first motion reported, not at a mouse's one")
    assert_true(brush.is_tablet, "and the rising pressure showed a pen")
    assert_almost_eq(first[first.size() - 1], 1.0, 1e-6, "Its end is the full press")
    var second := _stroke(surface, brush, RAMP)
    assert_eq(second, first, "The same stroke laid second lays every point at the pressure the first did")
    brush = null
    Fixtures.teardown(surface)


func test_a_short_stroke_of_plain_motions_paints_as_a_mouses_at_the_lift() -> void:
    var surface := Fixtures.make_surface()
    var brush := _brush(surface)
    _button(surface, brush, true)
    for i in 3:
        _motion(surface, brush, FROM + STEP * (i + 1), 0.0)
    assert_eq(brush.pressures.size(), 0, "A pointer that has said nothing lays nothing yet")
    _button(surface, brush, false, FROM + STEP * 3)
    assert_true(brush.pressures.size() > 3, "The lift lays the press and the three motions, %d points" % brush.pressures.size())
    for i in brush.pressures.size():
        assert_almost_eq(brush.pressures[i], 1.0, 1e-6, "Point %d is at a mouse's full pressure" % i)
    assert_false(brush.is_tablet, "and the pointer is not taken for a pen")
    brush = null
    Fixtures.teardown(surface)


func test_past_the_run_of_plain_motions_the_pointer_is_a_mouse_from_then_on() -> void:
    var surface := Fixtures.make_surface()
    var brush := _brush(surface)
    _button(surface, brush, true)
    for i in NoiseBrushScript.MOUSE_MOTIONS:
        _motion(surface, brush, FROM + STEP * (i + 1), 0.0)
    assert_eq(brush.pressures.size(), 0, "%d plain motions still wait" % NoiseBrushScript.MOUSE_MOTIONS)
    _motion(surface, brush, FROM + STEP * (NoiseBrushScript.MOUSE_MOTIONS + 1), 0.0)
    var laid := brush.pressures.size()
    assert_true(laid > NoiseBrushScript.MOUSE_MOTIONS, "One more lays them all, %d points" % laid)
    _motion(surface, brush, FROM + STEP * (NoiseBrushScript.MOUSE_MOTIONS + 2), 0.0)
    assert_true(brush.pressures.size() > laid, "and the next plain motion is laid at once")
    for i in brush.pressures.size():
        assert_almost_eq(brush.pressures[i], 1.0, 1e-6, "Point %d is at a mouse's full pressure" % i)
    _button(surface, brush, false, FROM + STEP * (NoiseBrushScript.MOUSE_MOTIONS + 2))
    brush.pressures.clear()
    _button(surface, brush, true)
    assert_eq(brush.pressures, [1.0] as Array[float], "A known mouse's next press is laid at once, at full pressure")
    _button(surface, brush, false)
    brush = null
    Fixtures.teardown(surface)


func test_a_pens_reading_after_a_mouse_takes_the_pointer_back() -> void:
    var surface := Fixtures.make_surface()
    var brush := _brush(surface)
    _stroke(surface, brush, _plain(NoiseBrushScript.MOUSE_MOTIONS + 1))
    assert_false(brush.is_tablet, "A run of plain motions is a mouse's")
    var pen := _stroke(surface, brush, [0.3, 0.3] as Array[float])
    assert_true(brush.is_tablet, "and a pressure takes the pointer for a pen again")
    assert_almost_eq(pen[pen.size() - 1], 0.3, 1e-6, "whose motions are laid at the pressure they reported")
    var after := _stroke(surface, brush, RAMP)
    assert_almost_eq(after[0], 0.0, 1e-6, "The pen's next press waits for its first motion's none")
    brush = null
    Fixtures.teardown(surface)


func test_a_tap_of_a_pointer_not_known_yet_leaves_one_point_at_full_pressure() -> void:
    var surface := Fixtures.make_surface()
    var brush := _brush(surface)
    _button(surface, brush, true)
    assert_eq(brush.pressures.size(), 0, "The press waits for a motion to say what the pointer is")
    _button(surface, brush, false)
    assert_eq(brush.pressures, [1.0] as Array[float], "and the lift lays it, at full pressure since none came")
    brush = null
    Fixtures.teardown(surface)
