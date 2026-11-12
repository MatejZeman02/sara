## The first stroke of a session lays what the next one would.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A pen pressed from no pressure reports a plain motion or two before its
## first reading, and a fresh brush that had seen no pen took the first of them
## for a mouse's. The press and that motion went down at 1, so a brush whose size
## follows the pressure opened its first stroke with a lobe the strokes after it
## did not have. The brush now holds those motions until the pointer shows what
## it is, and these hold that the first stroke opens as the second does, that a
## mouse still paints at 1, and that a mouse drag lifted before the brush could
## tell lays its motions all the same.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

## The pressures of Day 8's stroke as the pen reported them, two plain motions
## and then the pen's own readings.
const PRESSURES: Array[float] = [0.0, 0.0, 0.215, 0.33, 0.42, 0.5, 0.55, 0.5, 0.4, 0.25]
const STEP := Vector2(6.0, 0.0)

var _surface: SaSurface = null
var _machine: ToolMachine = null
var _brush: Object = null


func before_each() -> void:
    _surface = Fixtures.make_surface(Vector2i(256, 256))
    _machine = Fixtures.make_bound_machine(_surface)
    _machine.set_active_tool(&"brush")
    _brush = _machine.active_tool
    _brush.settings.size_by_pressure = true
    _brush.settings.radius = 8.0 / 256.0


func after_each() -> void:
    Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null
    _brush = null


func _button(pressed: bool) -> void:
    var button := InputEventMouseButton.new()
    button.button_index = MOUSE_BUTTON_LEFT
    button.pressed = pressed
    _brush.handle_input(button)


func _motion(at: Vector2, pressure: float) -> void:
    var motion := InputEventMouseMotion.new()
    motion.pressure = pressure
    _surface.view.mouse_position = at
    _brush.handle_input(motion)


## A hover, a press and one motion for each pressure, from *from*, and what the
## stroke laid: its first dab, its dab count and the most pressure it took.
func _stroke(from: Vector2, pressures: Array[float]) -> Dictionary:
    _motion(from, 0.0)
    _button(true)
    for i in pressures.size():
        _motion(from + STEP * (i + 1), pressures[i])
    _button(false)
    return {
        "first": _brush.sampled_dabs[0],
        "dabs": _brush.stroke_info.dab_index,
        "most": _brush.stroke_info.max_pressure,
    }


func test_the_first_pen_stroke_opens_as_the_second_does() -> void:
    assert_true(_brush.is_tablet, "A fresh brush takes the pointer for a pen")
    var first := _stroke(Vector2(40, 60), PRESSURES)
    var second := _stroke(Vector2(40, 160), PRESSURES)
    assert_true(_brush.is_tablet, "Two pen strokes leave the brush on the pen")
    var opened: SaDabParams = first["first"]
    var then: SaDabParams = second["first"]
    var widths := [opened.size, then.size]
    assert_almost_eq(opened.size, then.size, 1e-6, "The first stroke's first dab is %f wide, the second's %f" % widths)
    assert_almost_eq(opened.opacity, then.opacity, 1e-6, "and as dense as the second's")
    assert_eq(first["dabs"], second["dabs"], "The two strokes lay as many dabs")
    assert_almost_eq(first["most"], second["most"], 1e-6, "and neither went to a mouse's 1, %f" % first["most"])
    assert_eq(opened.position, Vector2(40, 60), "The first dab is the press's")


func test_a_mouse_still_paints_at_full_pressure() -> void:
    var plain: Array[float] = []
    plain.resize(SaPenOrMouse.MOUSE_STREAK + 5)
    plain.fill(0.0)
    var drag := _stroke(Vector2(40, 60), plain)
    assert_false(_brush.is_tablet, "A drag with no pressure past the streak is the mouse")
    assert_almost_eq(drag["most"], 1.0, 1e-6, "and it paints at 1")
    var opened: SaDabParams = drag["first"]
    assert_eq(opened.position, Vector2(40, 60), "from its press")
    assert_true(drag["dabs"] > plain.size(), "along the whole drag, %d dabs" % drag["dabs"])


func test_a_mouse_drag_lifted_before_the_brush_could_tell_is_laid() -> void:
    var plain: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0]
    var drag := _stroke(Vector2(40, 60), plain)
    assert_true(_brush.is_tablet, "Five plain motions do not tell a pen from a mouse")
    assert_almost_eq(drag["most"], 1.0, 1e-6, "so the lift lays them as a mouse's, at 1")
    assert_true(drag["dabs"] > plain.size(), "and all of them, %d dabs" % drag["dabs"])
    var opened: SaDabParams = drag["first"]
    assert_eq(opened.position, Vector2(40, 60), "from the press")
