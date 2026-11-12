## A Shift click's line snaps to steps of 15 degrees while Ctrl is held too.
##
## The line ran wherever the click landed, so a level horizon or an exact 45
## degrees had to be aimed by hand. With Ctrl down as well, the click's point is
## turned about the line's start to the nearest multiple of 15 degrees at the
## same length. Each case paints a stroke that lets go at (100, 100), Shift
## clicks, and reads where the gesture kept the line's end and the layer's
## texels along it.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

## Where the first stroke lets go, which is the line's start.
const START := Vector2(100.0, 100.0)

var _surface: SaSurface = null
var _doc: SaDocument = null
var _machine: ToolMachine = null


func before_each() -> void:
    _surface = Fixtures.make_surface(Vector2i(512, 512))
    _doc = _surface.easel.document
    _machine = Fixtures.make_bound_machine(_surface)
    _machine.set_active_tool(&"brush")
    _machine.active_tool.is_tablet = false
    _machine.active_tool.settings.radius = 3.0 / 512.0


func after_each() -> void:
    Fixtures.teardown(_surface, _machine)
    _surface = null
    _doc = null
    _machine = null


func _button(at: Vector2, pressed: bool, shift: bool = false, ctrl: bool = false) -> void:
    _surface.view.mouse_position = at
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    event.shift_pressed = shift
    event.ctrl_pressed = ctrl
    event.position = at
    event.global_position = at
    _machine.handle_input(event)


func _move(at: Vector2) -> void:
    _surface.view.mouse_position = at
    var event := InputEventMouseMotion.new()
    event.position = at
    event.global_position = at
    event.button_mask = MOUSE_BUTTON_MASK_LEFT
    _machine.handle_input(event)


## A short stroke from the left that lets go at [constant START].
func _stroke() -> void:
    var from := START - Vector2(0.0, 20.0)
    _button(from, true)
    for i in range(1, 5):
        _move(from.lerp(START, i / 4.0))
    _button(START, false)


func _click(at: Vector2, ctrl: bool) -> void:
    _button(at, true, true, ctrl)
    _button(at, false, true, ctrl)


## Where the gesture kept the line's end, the next line's start.
func _end() -> Vector2:
    var end: SaShiftPress.End = _machine._shift._ends.get(&"brush")
    return end.at if end != null else Vector2(-1.0, -1.0)


static func _alpha(layer: SaLayer, at: Vector2) -> float:
    var pixel := Vector2i(at)
    var grid := Vector2i(floori(float(pixel.x) / layer.CHUNK_SIZE), floori(float(pixel.y) / layer.CHUNK_SIZE))
    var chunk: SaChunk = layer.chunks.get(grid)
    if chunk == null:
        return 0.0
    var texture := chunk.albedo()
    @warning_ignore("integer_division")
    var local := (pixel - grid * layer.CHUNK_SIZE) * chunk.pixel_size() / layer.CHUNK_SIZE
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return SaFieldSpec.decode_texel(bytes, texture.format, local.y * texture.size.x + local.x).a


func test_a_ctrl_shift_click_off_the_level_draws_a_level_line_of_the_same_length() -> void:
    _stroke()
    var click := Vector2(300.0, 120.0)
    _click(click, true)
    var length := click.distance_to(START)
    var end := _end()
    assert_true(end.is_equal_approx(START + Vector2(length, 0.0)), "The line ends at 0 degrees, %s" % end)
    assert_almost_eq(end.distance_to(START), length, 0.001, "at the click's distance")
    var layer := _doc.active_layer
    assert_true(_alpha(layer, Vector2(250.0, 100.0)) > 0.5, "The line is painted along the level")
    assert_eq(_alpha(layer, Vector2(250.0, 115.0)), 0.0, "and not towards the click")


func test_a_ctrl_shift_click_near_the_diagonal_draws_45_degrees() -> void:
    _stroke()
    var click := Vector2(200.0, 190.0)
    _click(click, true)
    var length := click.distance_to(START)
    var end := _end()
    var angle := rad_to_deg((end - START).angle())
    assert_almost_eq(angle, 45.0, 0.001, "The line runs at 45 degrees")
    assert_almost_eq(end.distance_to(START), length, 0.001, "at the click's distance")
    assert_true(_alpha(_doc.active_layer, Vector2(170.0, 170.0)) > 0.5, "and is painted on the diagonal")


func test_a_plain_shift_click_draws_the_line_unsnapped() -> void:
    _stroke()
    var click := Vector2(300.0, 120.0)
    _click(click, false)
    assert_true(_end().is_equal_approx(click), "The line ends at the click, %s" % _end())
    var layer := _doc.active_layer
    assert_true(_alpha(layer, Vector2(250.0, 115.0)) > 0.5, "and is painted towards it")
    assert_eq(_alpha(layer, Vector2(250.0, 100.0)), 0.0, "and not along the level")


func test_the_step_is_the_view_s_rotate_step_of_15_degrees() -> void:
    assert_eq(SaShiftPress.ANGLE_STEP, SaView.ROTATION_STEP, "One step for the line and the canvas's turn")
    assert_almost_eq(rad_to_deg(SaShiftPress.ANGLE_STEP), 15.0, 0.0001, "of 15 degrees")
