## A tool switch with the pen down, by a pick or by a held Space or Alt,
## keeps the stamp brush's stroke drawn so far as one undo step.
##
## [ToolMachine] puts the brush down with its `reset` whenever the tool in hand
## changes, and that reset threw the open stroke away: the paint the painter had
## seen drawn left the canvas and the history gained nothing. Everything here
## goes through [method ToolMachine.handle_input], as a painter's pen and keys
## do, in build-up and in wash.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true
const Fixtures = preload("res://tests/fixtures.gd")
const AT := Vector2(100.0, 100.0)
const BUILD_UP := SaStampBrushSettings.PaintingMode.BUILD_UP
const WASH := SaStampBrushSettings.PaintingMode.WASH

var _surface: SaSurface = null
var _doc: SaDocument = null
var _machine: ToolMachine = null


func before_each() -> void:
    _surface = Fixtures.make_surface(Vector2i(256, 256))
    _doc = _surface.easel.document
    _machine = Fixtures.make_bound_machine(_surface)
    _surface.view.mouse_position = AT
    _machine.set_active_tool(&"brush")


func after_each() -> void:
    Fixtures.teardown(_surface, _machine)


func _button(pressed: bool) -> void:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    _machine.handle_input(event)


func _move_to(at: Vector2) -> void:
    _surface.view.mouse_position = at
    var event := InputEventMouseMotion.new()
    event.position = at
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


## Opens a black stroke in *mode* and draws it forty pixels right.
func _open_stroke(mode: int) -> void:
    _machine.set_active_tool(&"brush")
    var brush := _machine.active_tool
    brush.settings.color = Color.BLACK
    brush.settings.painting_mode = mode
    _surface.view.mouse_position = AT
    _button(true)
    _move_to(AT + Vector2(20.0, 0.0))
    _move_to(AT + Vector2(40.0, 0.0))


## The stroke cut by *cut* in *mode* keeps its paint, gains one step and
## leaves nothing in the stroke buffer, and one undo takes it away. One stroke
## a test, because a step taken after an undo replaces the redo it would
## otherwise have counted.
func _assert_kept(mode: int, cut: Callable, label: String) -> void:
    var before := _steps()
    _open_stroke(mode)
    cut.call()
    _move_to(AT + Vector2(60.0, 0.0))
    _button(false)
    var what := "%s, %s" % [label, "build-up" if mode == BUILD_UP else "wash"]
    var kept := _alpha_at(AT + Vector2(20.0, 0.0))
    assert_true(kept > 0.3, "%s: the stroke drawn so far stays, alpha %.3f" % [what, kept])
    assert_eq(_steps() - before, 1, "%s: the cut stroke is one step" % what)
    assert_true(_doc.stroke_layer.chunks.is_empty(), "%s: nothing is left in the stroke buffer" % what)
    assert_true(_doc.undo(), "%s: the step undoes" % what)
    var undone := _alpha_at(AT + Vector2(20.0, 0.0))
    assert_true(undone < 0.02, "%s: one undo takes the stroke away, alpha %.3f" % [what, undone])


func _to_eyedropper() -> void:
    _machine.set_active_tool(&"eyedropper")


func _to_pan() -> void:
    _machine.set_active_tool(&"pan")


func _held_space() -> void:
    _key(KEY_SPACE, true)
    _key(KEY_SPACE, false)


func _held_alt() -> void:
    _key(KEY_ALT, true)
    _key(KEY_ALT, false)


func test_a_switch_to_the_eyedropper_keeps_a_build_up_stroke() -> void:
    _assert_kept(BUILD_UP, _to_eyedropper, "a switch to the Eyedropper")


func test_a_switch_to_the_eyedropper_keeps_a_wash_stroke() -> void:
    _assert_kept(WASH, _to_eyedropper, "a switch to the Eyedropper")


func test_a_switch_to_pan_keeps_a_build_up_stroke() -> void:
    _assert_kept(BUILD_UP, _to_pan, "a switch to Pan")


func test_a_switch_to_pan_keeps_a_wash_stroke() -> void:
    _assert_kept(WASH, _to_pan, "a switch to Pan")


func test_a_held_space_keeps_a_build_up_stroke() -> void:
    _assert_kept(BUILD_UP, _held_space, "a held Space")


func test_a_held_space_keeps_a_wash_stroke() -> void:
    _assert_kept(WASH, _held_space, "a held Space")


func test_a_held_alt_keeps_a_build_up_stroke() -> void:
    _assert_kept(BUILD_UP, _held_alt, "a held Alt")


func test_a_held_alt_keeps_a_wash_stroke() -> void:
    _assert_kept(WASH, _held_alt, "a held Alt")


func test_a_switch_with_no_stroke_open_adds_no_step() -> void:
    _machine.active_tool.settings.color = Color.BLACK
    var before := _steps()
    _machine.set_active_tool(&"eyedropper")
    _machine.set_active_tool(&"brush")
    _held_space()
    _held_alt()
    assert_eq(_steps() - before, 0, "a switch with the pen up adds no step")


func _assert_released_first(mode: int) -> void:
    var before := _steps()
    _open_stroke(mode)
    _button(false)
    _machine.set_active_tool(&"eyedropper")
    assert_eq(_steps() - before, 1, "a stroke let go before the switch is still exactly one step")
    assert_true(_alpha_at(AT + Vector2(20.0, 0.0)) > 0.3, "and its paint stays")


func test_a_build_up_stroke_released_before_the_switch_adds_one_step() -> void:
    _assert_released_first(BUILD_UP)


func test_a_wash_stroke_released_before_the_switch_adds_one_step() -> void:
    _assert_released_first(WASH)
