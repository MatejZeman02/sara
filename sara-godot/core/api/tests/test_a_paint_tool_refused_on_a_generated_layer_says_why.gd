## A paint tool refused on a
## generated layer says why.
##
## The five tools that write pixels turn a generated layer
## away and found nowhere to say so, so the pen did nothing and nothing said
## why. Each test runs one tool on a generated active layer and hears the
## sentence `SaContext.refuse_paint` says on the bus, naming the tool's
## gesture, then runs it on a plain layer and hears nothing, so the line is
## the guard's and not one every press says.
extends "res://tests/test_framework.gd"

## Chunks are real textures, so this needs a RenderingDevice.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const SaPatchScript = preload("res://modules/sara-base-modules/base/patch/sa_patch.gd")

## A box inside the one chunk of the canvas, for the patch and the transform.
const BOX := Rect2i(96, 96, 64, 64)

var _surface: SaSurface = null
var _machine: ToolMachine = null
var _heard: PackedStringArray = PackedStringArray()


func before_each() -> void:
    _surface = Fixtures.make_surface(Vector2i(256, 256))
    _machine = Fixtures.make_bound_machine(_surface)
    _heard = PackedStringArray()
    EventBus.paint_refused.connect(_hear)


func after_each() -> void:
    EventBus.paint_refused.disconnect(_hear)
    Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null


func _hear(line: String) -> void:
    _heard.append(line)


func _doc() -> SaDocument:
    return _surface.get_document()


func _generated() -> SaLayer:
    var layer := SaLayerOps.new(_doc()).add()
    layer.generator = "background"
    layer.generator_params = {"color": Color(0.5, 0.5, 0.5, 1.0)}
    _doc().active_layer = layer
    return layer


func _plain(filled: bool) -> SaLayer:
    var layer := SaLayerOps.new(_doc()).add()
    _doc().active_layer = layer
    if filled:
        _doc().fill_layer(Color(0.4, 0.5, 0.6, 1.0), layer)
    return layer


## The one line heard is the generated sentence for *gesture*, then the plain
## layer is tried by *run* and nothing more is heard.
func _assert_says(gesture: String, run: Callable, filled: bool) -> void:
    var layer := _generated()
    run.call(layer)
    assert_eq(_heard.size(), 1, "The %s on a generated layer says one line" % gesture)
    var expected := SaContext.paint_refusal_line(layer, gesture)
    assert_true(expected.contains("generator"), "which names the generator")
    assert_eq(_heard[0] if _heard.size() > 0 else "", expected, "and is the door's sentence for the %s" % gesture)
    _heard = PackedStringArray()
    run.call(_plain(filled))
    assert_eq(_heard.size(), 0, "The %s on a plain layer says nothing" % gesture)


func _fill(_layer: SaLayer) -> void:
    _machine.set_active_tool(&"bucket_fill")
    _machine.active_tool.fill_at(Vector2i(128, 128))


func _patch(layer: SaLayer) -> void:
    _doc().selection.select_rect(BOX)
    SaPatchScript.new().patch(_doc(), layer)


func _transform(layer: SaLayer) -> void:
    _doc().selection.select_rect(BOX)
    var geometry := SaTransform.new(_doc())
    if geometry.lift(layer, BOX):
        geometry.cancel()


func _button(pressed: bool) -> void:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    _machine.active_tool.handle_input(event)


func _stroke(_layer: SaLayer) -> void:
    _machine.set_active_tool(&"brush")
    _surface.view.mouse_position = Vector2(40, 40)
    _button(true)
    var motion := InputEventMouseMotion.new()
    motion.pressure = 0.6
    _surface.view.mouse_position = Vector2(150, 110)
    _machine.active_tool.handle_input(motion)
    _button(false)


func _gradient(_layer: SaLayer) -> void:
    _machine.set_active_tool(&"gradient")
    _surface.view.mouse_position = Vector2(40, 40)
    _button(true)
    _surface.view.mouse_position = Vector2(200, 180)
    _button(false)


func test_the_bucket_fill_says_why() -> void:
    _assert_says("fill", _fill, false)


func test_the_patch_says_why() -> void:
    _assert_says("patch", _patch, true)


func test_the_transform_says_why() -> void:
    _assert_says("transform", _transform, true)


func test_the_brush_says_why() -> void:
    _assert_says("stroke", _stroke, false)


func test_the_gradient_says_why() -> void:
    _assert_says("gradient", _gradient, false)


func test_a_locked_layer_is_named_as_locked() -> void:
    var layer := _plain(false)
    layer.is_locked = true
    assert_true(SaContext.refuse_paint(layer, "fill"), "A locked layer is refused")
    assert_eq(_heard.size(), 1, "and says one line")
    assert_true(_heard[0].contains("locked") if _heard.size() > 0 else false, "which names the lock")
    assert_false(SaContext.refuse_paint(null, "fill"), "No layer is no refusal")
    assert_eq(SaContext.paint_refusal_line(_plain(false), "fill"), "", "and a plain layer has no sentence")
