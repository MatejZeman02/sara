## A tool switch with the pen down, by a pick or by a held Space or Alt,
## keeps the noise brush's stroke drawn so far as one undo step, its stroke
## buffer empty.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## [ToolMachine] puts the brush down with its `reset` whenever the tool in hand
## changes, and that reset dropped the dabs of the open stroke: the history
## gained nothing and the stroke's chunk stayed in the buffer. The brush is put
## in a bound machine's hand as the module registers it, an engine of the
## Brush, and everything goes through [method ToolMachine.handle_input].
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true
const Fixtures = preload("res://tests/fixtures.gd")
const StateNoiseBrushScript = preload("res://modules/sara-noise-brush-engine/state_noise_brush.gd")
const NoiseBrushSettingsScript = preload("res://modules/sara-noise-brush-engine/noise_brush_settings.gd")
const NOISE := &"noise_brush"
const AT := Vector2(100.0, 100.0)

var _surface: SaSurface = null
var _doc: SaDocument = null
var _machine: ToolMachine = null


func before_each() -> void:
    _surface = Fixtures.make_surface(Vector2i(256, 256))
    _doc = _surface.easel.document
    var registry := Fixtures.make_tool_registry()
    var noise := SaToolDescriptor.create(NOISE, StateNoiseBrushScript)
    noise.is_painting = true
    noise.preset_engine = NoiseBrushSettingsScript.PRESET_ENGINE
    registry.register_brush_engine(noise)
    _machine = ToolMachine.new(DisplayServer.get_name() == "Wayland")
    _machine.name = "ToolMachine"
    _machine._ready()
    _machine.bind(_surface, registry)
    # The document's first noise stroke adds its height channel as a step of
    # its own, so one stroke away from the one measured adds it first.
    _stroke_from(Vector2(40.0, 200.0))
    _button(false)


## Opens a black noise stroke at *from* and draws it forty pixels right.
func _stroke_from(from: Vector2) -> void:
    _machine.set_active_tool(NOISE)
    assert_eq(_machine.active_tool_name, NOISE, "the noise brush is in hand")
    var brush := _machine.active_tool
    brush.settings.color = Color.BLACK
    _surface.view.mouse_position = from
    _button(true)
    for i in range(1, 9):
        _move_to(from + Vector2(5.0 * i, 0.0))


func after_each() -> void:
    Fixtures.teardown(_surface, _machine)


func _button(pressed: bool) -> void:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    _machine.handle_input(event)


## A mouse's motion, at full pressure, as the pen's would be.
func _move_to(at: Vector2) -> void:
    _surface.view.mouse_position = at
    var event := InputEventMouseMotion.new()
    event.position = at
    event.pressure = 1.0
    event.button_mask = MOUSE_BUTTON_MASK_LEFT
    _machine.handle_input(event)


func _key(key: Key, pressed: bool) -> void:
    var event := InputEventKey.new()
    event.physical_keycode = key
    event.keycode = key
    event.pressed = pressed
    _machine.handle_input(event)


func _steps() -> int:
    return _doc.undo_redo.get_history_count()


## How far black paint darkened the ground at *at*, as a share of the ground.
func _alpha_at(at: Vector2) -> float:
    _surface.easel.request_full_composite()
    _surface.easel.process_pending_composite()
    var image: Image = SaExport.get_easel_image_float(_surface.easel)
    var ground: float = image.get_pixel(4, 250).r
    return (ground - image.get_pixelv(Vector2i(at)).r) / maxf(ground, 1e-4)


## The stroke cut by *cut* keeps its paint, gains one step and leaves nothing
## in the stroke buffer, and one undo takes it away.
func _assert_kept(cut: Callable, label: String) -> void:
    var before := _steps()
    _stroke_from(AT)
    var drawn := _alpha_at(AT + Vector2(20.0, 0.0))
    cut.call()
    _move_to(AT + Vector2(60.0, 0.0))
    _button(false)
    var kept := _alpha_at(AT + Vector2(20.0, 0.0))
    assert_true(kept > 0.1, "%s: the stroke drawn so far stays, alpha %.3f" % [label, kept])
    assert_true(kept >= drawn - 0.02, "%s: as dark as it was drawn, %.3f against %.3f" % [label, kept, drawn])
    assert_eq(_steps() - before, 1, "%s: the cut stroke is one step" % label)
    assert_true(_doc.stroke_layer.chunks.is_empty(), "%s: nothing is left in the stroke buffer" % label)
    assert_true(_doc.undo(), "%s: the step undoes" % label)
    var undone := _alpha_at(AT + Vector2(20.0, 0.0))
    assert_true(undone < 0.02, "%s: one undo takes the stroke away, alpha %.3f" % [label, undone])


func test_a_switch_to_the_eyedropper_keeps_the_stroke() -> void:
    _assert_kept(func() -> void: _machine.set_active_tool(&"eyedropper"), "a switch to the Eyedropper")


func test_a_switch_to_pan_keeps_the_stroke() -> void:
    _assert_kept(func() -> void: _machine.set_active_tool(&"pan"), "a switch to Pan")


func test_a_held_space_keeps_the_stroke() -> void:
    _assert_kept(
        func() -> void:
            _key(KEY_SPACE, true)
            _key(KEY_SPACE, false),
        "a held Space"
    )


func test_a_held_alt_keeps_the_stroke() -> void:
    _assert_kept(
        func() -> void:
            _key(KEY_ALT, true)
            _key(KEY_ALT, false),
        "a held Alt"
    )


func test_a_switch_with_no_stroke_open_adds_no_step() -> void:
    _machine.set_active_tool(NOISE)
    var before := _steps()
    _machine.set_active_tool(&"eyedropper")
    _machine.set_active_tool(NOISE)
    _key(KEY_SPACE, true)
    _key(KEY_SPACE, false)
    _key(KEY_ALT, true)
    _key(KEY_ALT, false)
    assert_eq(_steps() - before, 0, "a switch with the pen up adds no step")


func test_a_stroke_released_before_the_switch_adds_one_step() -> void:
    var before := _steps()
    _stroke_from(AT)
    _button(false)
    _machine.set_active_tool(&"eyedropper")
    assert_eq(_steps() - before, 1, "a stroke let go before the switch is still exactly one step")
    assert_true(_alpha_at(AT + Vector2(20.0, 0.0)) > 0.1, "and its paint stays")
    assert_true(_doc.stroke_layer.chunks.is_empty(), "and nothing is left in the stroke buffer")
