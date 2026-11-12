## A left press that comes while a stroke is open ends that stroke and starts
## another.
##
## A release can be lost, as when Alt+Tab or a window that takes the input
## comes up with the pen down, and the pen then touches down somewhere else.
## A brush that began a stroke over the open one would make both one undo
## step, and through the machine under Wayland a line was drawn from where the
## pen left to where it came down. The press now ends the open stroke where the
## pen last was, as a release would, and nothing is laid between the two
## places. The machine hands the press on to the brush as it came, under
## Wayland as well, so the brush is where the press is read.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

const FIRST := Vector2(60.0, 60.0)
const SECOND := Vector2(60.0, 180.0)
const TOUCH := 0.8
const TILT := Vector2(0.2, 0.1)

## How the second press comes: after the pen's hover in the air with the
## touch's pressure on a motion before it, with no motion since the first
## stroke's last, or as a mouse's with no motion since, which is how a scripted
## run sends it and where a joined line shows.
enum Shape { HOVER, PEN_PRESS, MOUSE_PRESS }

const SHAPES: Array[String] = ["after a hover", "with no motion between", "from a mouse"]

var _surface: SaSurface = null
var _doc: SaDocument = null
var _machine: ToolMachine = null


func before_each() -> void:
    _surface = Fixtures.make_surface(Vector2i(256, 256))
    _doc = _surface.easel.document
    _machine = Fixtures.make_bound_machine(_surface, true)
    _surface.view.mouse_position = FIRST
    _machine.set_active_tool(&"brush")
    _machine.active_tool.settings.color = Color.BLACK


func after_each() -> void:
    SaCursorPolicy.forget_pointer_device()
    Fixtures.teardown(_surface, _machine)
    _surface = null
    _doc = null
    _machine = null


## Straight to the brush: at the second press the first stroke is already a
## step with its paint, after the release there are two, and one undo takes
## the second stroke alone.
func test_a_second_press_straight_on_the_brush_is_a_second_step() -> void:
    var brush := _machine.active_tool
    var steps := _steps()
    _surface.view.mouse_position = FIRST
    brush.handle_input(_button(true, FIRST, MOUSE_BUTTON_MASK_LEFT))
    for x: int in range(4, 64, 4):
        brush.handle_input(_motion(FIRST + Vector2(x, 0.0), TOUCH, MOUSE_BUTTON_MASK_LEFT))
    _surface.view.mouse_position = SECOND
    brush.handle_input(_button(true, SECOND, MOUSE_BUTTON_MASK_LEFT))
    assert_eq(_steps(), steps + 1, "At the second press the first stroke is one step already")
    assert_true(_alpha_at(FIRST + Vector2(30.0, 0.0)) > 0.3, "with its paint at the first place")
    for x: int in range(4, 64, 4):
        brush.handle_input(_motion(SECOND + Vector2(x, 0.0), TOUCH, MOUSE_BUTTON_MASK_LEFT))
    brush.handle_input(_button(false, SECOND + Vector2(60.0, 0.0), 0))
    assert_false(brush.is_drawing, "The release ends the second stroke")
    assert_eq(_steps(), steps + 2, "and the two strokes are two steps")
    assert_true(_alpha_at(SECOND + Vector2(30.0, 0.0)) > 0.3, "The second stroke is on the canvas")
    assert_true(_doc.undo(), "One undo runs")
    assert_true(_alpha_at(SECOND + Vector2(30.0, 0.0)) < 0.01, "and takes the second stroke away")
    assert_true(_alpha_at(FIRST + Vector2(30.0, 0.0)) > 0.3, "and leaves the first")


func test_a_lost_release_through_the_machine_lays_nothing_between_in_build_up() -> void:
    for shape: Shape in [Shape.HOVER, Shape.PEN_PRESS]:
        _through_the_machine(SaStampBrushSettings.PaintingMode.BUILD_UP, shape, "build-up " + SHAPES[shape])


func test_a_lost_release_through_the_machine_lays_nothing_between_in_wash() -> void:
    for shape: Shape in [Shape.HOVER, Shape.PEN_PRESS]:
        _through_the_machine(SaStampBrushSettings.PaintingMode.WASH, shape, "wash " + SHAPES[shape])


## The mouse's each on a brush of its own, because a brush that has seen the
## pen reads a mouse's first motions as the pen's for a while.
func test_a_lost_mouse_release_through_the_machine_lays_nothing_between_in_build_up() -> void:
    _through_the_machine(SaStampBrushSettings.PaintingMode.BUILD_UP, Shape.MOUSE_PRESS, "build-up " + SHAPES[Shape.MOUSE_PRESS])


func test_a_lost_mouse_release_through_the_machine_lays_nothing_between_in_wash() -> void:
    _through_the_machine(SaStampBrushSettings.PaintingMode.WASH, Shape.MOUSE_PRESS, "wash " + SHAPES[Shape.MOUSE_PRESS])


## A pen touch under Wayland, whose pressure comes on a motion before the
## press, or a mouse's drag, its release lost, and a second press at the second
## place in the *shape* given.
func _through_the_machine(mode: int, shape: Shape, name: String) -> void:
    _surface.easel.document.clear_layer()
    var brush := _machine.active_tool
    brush.settings.painting_mode = mode
    var steps := _steps()
    var pen := shape != Shape.MOUSE_PRESS
    var touch := TOUCH if pen else 0.0
    if pen:
        _feed(_motion(FIRST, 0.0, 0))
        _feed(_motion(FIRST, touch, MOUSE_BUTTON_MASK_LEFT))
    _surface.view.mouse_position = FIRST
    _feed(_button(true, FIRST if pen else Vector2.ZERO, MOUSE_BUTTON_MASK_LEFT if pen else 0))
    var step := 4 if pen else 30
    for x: int in range(step, 64, step):
        _feed(_motion(FIRST + Vector2(x, 0.0), touch, MOUSE_BUTTON_MASK_LEFT, pen))
    # The release never comes. The pen lifts and hovers down to the second place.
    var end := FIRST + Vector2(60.0, 0.0)
    if shape == Shape.HOVER:
        for y: int in range(0, 124, 8):
            _feed(_motion(end + Vector2(0.0, y), 0.0, 0))
        _feed(_motion(SECOND, 0.0, 0))
        _feed(_motion(SECOND, TOUCH, MOUSE_BUTTON_MASK_LEFT))
    _surface.view.mouse_position = SECOND
    _feed(_button(true, SECOND if pen else Vector2.ZERO, MOUSE_BUTTON_MASK_LEFT if pen else 0))
    for x: int in range(step, 64, step):
        _feed(_motion(SECOND + Vector2(x, 0.0), touch, MOUSE_BUTTON_MASK_LEFT, pen))
    _feed(_button(false, SECOND + Vector2(60.0, 0.0), 0))
    assert_false(brush.is_drawing, "%s: the release ends the second stroke" % name)
    assert_eq(_steps(), steps + 2, "%s: the two touches are two steps" % name)
    assert_true(_alpha_at(FIRST + Vector2(30.0, 0.0)) > 0.3, "%s: the first stroke is on the canvas" % name)
    assert_true(_alpha_at(SECOND + Vector2(30.0, 0.0)) > 0.3, "%s: and the second" % name)
    # Halfway along the line a joined stroke drew, from where the first stroke
    # ended to the second stroke's first motion.
    var between := _alpha_at(end.lerp(SECOND + Vector2(step, 0.0), 0.5))
    assert_true(between < 0.001, "%s: nothing is laid between the two places, read %.3f" % [name, between])


# --- Helpers --------------------------------------------------------------------


func _feed(event: InputEvent) -> void:
    _machine.handle_input(event)


func _steps() -> int:
    return _doc.undo_redo.get_history_count()


## A motion at *at*, where the fake view puts the pointer too, a pen's with
## its tilt when *pen* and a mouse's otherwise.
func _motion(at: Vector2, pressure: float, mask: int, pen: bool = true) -> InputEventMouseMotion:
    _surface.view.mouse_position = at
    var event := InputEventMouseMotion.new()
    event.position = at
    event.global_position = at
    event.pressure = pressure
    event.tilt = TILT if pen else Vector2.ZERO
    event.button_mask = mask
    if pen:
        SaCursorPolicy.note_pointer_device(event)
    return event


func _button(pressed: bool, at: Vector2, mask: int) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    event.position = at
    event.global_position = at
    event.button_mask = mask
    return event


## How far black paint darkened the ground at *at*, as a share of it.
func _alpha_at(at: Vector2) -> float:
    _surface.easel.request_full_composite()
    _surface.easel.process_pending_composite()
    var image: Image = SaExport.get_easel_image_float(_surface.easel)
    var ground: float = image.get_pixel(250, 4).r
    return (ground - image.get_pixelv(Vector2i(at)).r) / maxf(ground, 1e-4)
