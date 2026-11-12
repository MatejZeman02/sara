## A tool that paints refuses a
## generated layer.
##
## A generated layer stores no pixels and is drawn by its generator, so a pass
## writing its chunks changes nothing the painter sees and leaves an undo step
## that undoes nothing. Each test runs one tool on a generated active layer and
## finds no history step and no chunk on it, then runs the same tool on a
## plain layer and finds it lands there, so the refusal is the guard's and not
## a tool that never ran.
extends "res://tests/test_framework.gd"

## Chunks are real textures, so this needs a RenderingDevice.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const SaPatchScript = preload("res://modules/sara-base-modules/base/patch/sa_patch.gd")

## A box inside the one chunk of the canvas, for the patch and the transform.
const BOX := Rect2i(96, 96, 64, 64)

var _surface: SaSurface = null
var _machine: ToolMachine = null


func before_each() -> void:
    _surface = Fixtures.make_surface(Vector2i(256, 256))
    _machine = Fixtures.make_bound_machine(_surface)


func after_each() -> void:
    Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null


func _doc() -> SaDocument:
    return _surface.get_document()


func _steps() -> int:
    return _doc().undo_redo.get_history_count()


## A new active layer that names a generator, the way the paper and the
## background are made.
func _generated() -> SaLayer:
    var layer := SaLayerOps.new(_doc()).add()
    layer.generator = "background"
    layer.generator_params = {"color": Color(0.5, 0.5, 0.5, 1.0)}
    _doc().active_layer = layer
    return layer


## A new active plain layer, filled grey when *filled*, so the patch and the
## transform have paint to work on.
func _plain(filled: bool) -> SaLayer:
    var layer := SaLayerOps.new(_doc()).add()
    _doc().active_layer = layer
    if filled:
        _doc().fill_layer(Color(0.4, 0.5, 0.6, 1.0), layer)
    return layer


func _assert_refused(layer: SaLayer, steps_before: int, what: String) -> void:
    assert_eq(_steps(), steps_before, "%s on a generated layer records no step" % what)
    assert_eq(layer.chunks.size(), 0, "and leaves no chunk on it")


func _fill() -> int:
    _machine.set_active_tool(&"bucket_fill")
    return int(_machine.active_tool.fill_at(Vector2i(128, 128)))


func _patch(layer: SaLayer) -> int:
    _doc().selection.select_rect(BOX)
    return SaPatchScript.new().patch(_doc(), layer)


func _transform(layer: SaLayer) -> bool:
    _doc().selection.select_rect(BOX)
    var geometry := SaTransform.new(_doc())
    if not geometry.lift(layer, BOX):
        return false
    geometry.preview_affine(Vector2i(20, 10), Vector2.ONE, 0.0)
    geometry.tick()
    return geometry.commit()


func _button(pressed: bool) -> void:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    _machine.active_tool.handle_input(event)


## A press, two motions and the lift through the brush state.
func _stroke() -> void:
    _machine.set_active_tool(&"brush")
    _surface.view.mouse_position = Vector2(40, 40)
    _button(true)
    for at: Vector2 in [Vector2(90, 70), Vector2(150, 110)]:
        var motion := InputEventMouseMotion.new()
        motion.pressure = 0.6
        _surface.view.mouse_position = at
        _machine.active_tool.handle_input(motion)
    _button(false)


func test_the_core_answer() -> void:
    var layer := _generated()
    assert_true(layer.refuses_paint(), "A generated layer refuses paint")
    assert_false(layer.is_locked, "and is not locked, so the docker draws no padlock")
    var plain := _plain(false)
    assert_false(plain.refuses_paint(), "A plain layer takes paint")
    plain.is_locked = true
    assert_true(plain.refuses_paint(), "and refuses it once locked")


func test_the_bucket_fill_refuses() -> void:
    var layer := _generated()
    var before := _steps()
    assert_eq(_fill(), 0, "The fill writes nothing")
    _assert_refused(layer, before, "A fill")

    var plain := _plain(false)
    before = _steps()
    assert_true(_fill() > 0, "The fill lands on a plain layer")
    assert_eq(_steps(), before + 1, "as one step")
    assert_true(plain.chunks.size() > 0, "and leaves chunks")


func test_the_patch_refuses() -> void:
    var layer := _generated()
    var before := _steps()
    assert_eq(_patch(layer), 0, "The patch writes nothing")
    _assert_refused(layer, before, "A patch")

    var plain := _plain(true)
    before = _steps()
    assert_true(_patch(plain) > 0, "The patch lands on a plain layer")
    assert_eq(_steps(), before + 1, "as one step")


func test_the_transform_refuses() -> void:
    var layer := _generated()
    var before := _steps()
    assert_false(_transform(layer), "The transform lifts nothing")
    _assert_refused(layer, before, "A transform")

    var plain := _plain(true)
    before = _steps()
    assert_true(_transform(plain), "The transform lands on a plain layer")
    assert_eq(_steps(), before + 1, "as one step")


func test_the_brush_refuses() -> void:
    var layer := _generated()
    var before := _steps()
    _stroke()
    _assert_refused(layer, before, "A brush stroke")

    var plain := _plain(false)
    before = _steps()
    _stroke()
    assert_eq(_steps(), before + 1, "A stroke on a plain layer lands as one step")
    assert_true(plain.chunks.size() > 0, "and leaves chunks")
