## A lock taken with the pen down ends the stroke at the release.
##
## The guard at the top of `handle_input` returned on a locked target for every
## event, the release included. Lock Layer pressed mid-stroke left the brush
## drawing and never reached `commit_stroke`, so a build-up stroke's pixels
## stayed on the layer with no undo step and a wash stroke's stayed in the
## stroke buffer. The guard now refuses a press only.
##
## Each case presses, drags, locks through the same `SaLayerOps.set_locked` the
## Layer menu's Lock runs, drags on and releases, then reads the history, the
## stroke buffer and the tool.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

const AT := Vector2(100.0, 100.0)

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
    _surface = null
    _doc = null
    _machine = null


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


## Press, drag, lock, drag, release in *mode*, zero for build-up and one for
## wash, and answers the steps the history gained.
func _stroke_locked_midway(mode: int) -> int:
    var brush := _machine.active_tool
    brush.settings.painting_mode = mode
    var steps := _doc.undo_redo.get_history_count()
    _button(true)
    _move_to(AT + Vector2(20.0, 0.0))
    SaLayerOps.new(_doc).set_locked(_doc.active_layer, true)
    assert_true(brush.is_drawing, "the lock came with the pen down")
    _move_to(AT + Vector2(40.0, 0.0))
    _button(false)
    return _doc.undo_redo.get_history_count() - steps


func _check_ended(mode: int, name: String) -> void:
    var gained := _stroke_locked_midway(mode)
    var brush := _machine.active_tool
    assert_false(brush.is_drawing, "%s: the release ended the stroke" % name)
    assert_eq(gained, 2, "%s: the lock and the stroke are a step each" % name)
    assert_true(_doc.stroke_layer.chunks.is_empty(), "%s: nothing is left in the stroke buffer" % name)
    assert_true(_doc.undo(), "%s: the stroke's step undoes" % name)
    assert_true(_doc.active_layer.is_locked, "%s: and the step it undid was the stroke, not the lock" % name)


func test_a_build_up_stroke_ends_at_the_release() -> void:
    _check_ended(0, "build-up")


func test_a_wash_stroke_ends_at_the_release() -> void:
    _check_ended(1, "wash")


## The lock still turns a new stroke away, and says so once, at the press.
func test_a_press_on_the_locked_layer_is_still_refused() -> void:
    SaLayerOps.new(_doc).set_locked(_doc.active_layer, true)
    var said: Array[String] = []
    var ear := func(text: String) -> void: said.append(text)
    EventBus.paint_refused.connect(ear)
    var steps := _doc.undo_redo.get_history_count()
    _button(true)
    _move_to(AT + Vector2(20.0, 0.0))
    _button(false)
    EventBus.paint_refused.disconnect(ear)
    assert_false(_machine.active_tool.is_drawing, "no stroke opened")
    assert_eq(_doc.undo_redo.get_history_count(), steps, "and no step was made")
    assert_eq(said.size(), 1, "the press said why, once")
