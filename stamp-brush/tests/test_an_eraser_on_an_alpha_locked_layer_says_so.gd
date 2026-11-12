## An eraser on an alpha-locked layer is refused at the press
## and says so.
##
## Erasing on a layer with alpha lock on needs a warning, or the press paints
## nothing and says nothing and the eraser reads as broken. Each case paints the
## layer, alpha-locks it, erases through the tool machine with real input
## events, the pen's flipped end, the E toggle and the Eraser tool, and reads
## the line said and a layer that kept its paint. The last case erases the same
## way with the lock off, so the press is shown to have been one that erases.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

const PAINT := Color(0.2, 0.4, 0.6, 1.0)
const AT := Vector2(100.0, 100.0)
const PROBE := Vector2i(110, 100)

var _surface: SaSurface = null
var _doc: SaDocument = null
var _machine: ToolMachine = null
var _said: Array[String] = []


func before_each() -> void:
    _surface = Fixtures.make_surface(Vector2i(256, 256))
    # The blend modes' registry, without which the eraser's mode erases nothing.
    _surface.easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    _doc = _surface.easel.document
    _machine = Fixtures.make_bound_machine(_surface)
    _surface.view.mouse_position = AT
    # A layer of its own over the background, whose eraser lays the
    # background colour rather than taking coverage away.
    var layer := SaLayerOps.new(_doc).add(&"")
    _doc.set_active_layer(layer)
    _doc.fill_layer(PAINT, layer)
    _said.clear()
    EventBus.paint_refused.connect(_hear)


func after_each() -> void:
    if EventBus.paint_refused.is_connected(_hear):
        EventBus.paint_refused.disconnect(_hear)
    Fixtures.teardown(_surface, _machine)
    _surface = null
    _doc = null
    _machine = null


func _hear(line: String) -> void:
    _said.append(line)


## A motion of a pen held at *pressure*, flipped when *inverted*.
func _pen(at: Vector2, inverted: bool, pressure: float) -> void:
    _surface.view.mouse_position = at
    var event := InputEventMouseMotion.new()
    event.position = at
    event.pen_inverted = inverted
    event.pressure = pressure
    event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressure > 0.0 else 0
    _machine.active_tool.handle_input(event)


func _button(pressed: bool) -> void:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    event.position = _surface.view.mouse_position
    _machine.active_tool.handle_input(event)


## A hover, a press and a drag across the probe, then the lift.
func _stroke(inverted: bool) -> void:
    _pen(AT, inverted, 0.0)
    _button(true)
    for step in range(1, 9):
        _pen(AT + Vector2(step * 5.0, 0.0), inverted, 1.0)
    _button(false)


func _alpha() -> float:
    return Bench.texel(_doc.active_layer.get_field(Vector2i.ZERO), PROBE).a


func _check_refused(name: String) -> void:
    var steps := _doc.undo_redo.get_history_count()
    var before := _alpha()
    _stroke(name == "the pen's flipped end")
    assert_false(_machine.active_tool.is_drawing, "%s: no stroke opened" % name)
    assert_eq(_said, [SaContext.ALPHA_LOCKED_ERASE] as Array[String], "%s: the press said the alpha lock once" % name)
    assert_eq(_doc.undo_redo.get_history_count(), steps, "%s: no step was made" % name)
    assert_almost_eq(_alpha(), before, 1.0e-6, "%s: the layer kept its paint" % name)


func test_the_pen_s_flipped_end_is_refused_and_says_so() -> void:
    _machine.set_active_tool(&"brush")
    _doc.active_layer.alpha_locked = true
    _check_refused("the pen's flipped end")


func test_the_eraser_toggle_is_refused_and_says_so() -> void:
    _machine.set_active_tool(&"brush")
    _machine.active_tool.toggle_eraser()
    _doc.active_layer.alpha_locked = true
    _check_refused("the eraser toggle")


func test_the_eraser_tool_is_refused_and_says_so() -> void:
    _machine.set_active_tool(&"eraser")
    _doc.active_layer.alpha_locked = true
    _check_refused("the eraser tool")


## The same strokes with the lock off erase and say nothing, so the refused
## press was a press that would have erased.
func test_the_same_erase_with_alpha_unlocked_erases_in_silence() -> void:
    _machine.set_active_tool(&"eraser")
    var before := _alpha()
    _stroke(false)
    assert_true(_said.is_empty(), "nothing was said: %s" % [_said])
    assert_true(_alpha() < before - 0.1, "the eraser took paint away: %f" % _alpha())


## A paint stroke on the alpha-locked layer still tints, and says nothing.
func test_a_paint_stroke_on_the_alpha_locked_layer_still_tints() -> void:
    _machine.set_active_tool(&"brush")
    _doc.active_layer.alpha_locked = true
    var steps := _doc.undo_redo.get_history_count()
    _stroke(false)
    assert_true(_said.is_empty(), "nothing was said: %s" % [_said])
    assert_eq(_doc.undo_redo.get_history_count(), steps + 1, "the stroke made its step")
