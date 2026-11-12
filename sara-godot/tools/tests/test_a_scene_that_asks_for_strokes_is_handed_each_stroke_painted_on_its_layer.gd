## A scene that asks for strokes is handed each stroke painted on
## its layer.
##
## The spec says "a scene may ask for the strokes as input and decide itself
## what a stroke means". Each case builds a scene layer of one of the scene
## fixture's types through the module door, makes it the active layer and
## drives the machine with the events the canvas hands it. A stroke of five
## points with the brush in hand reaches the Lines root, which defines
## `sara_stroke`, at each point with its pressure, the brush's radius and its
## colour, and Sara lays nothing on the layer. The eraser's stroke carries its
## colour at alpha 0. A root that does not take strokes refuses the brush as it
## did, and a tool that is not a brush hands a root that takes both the pointer.
## One case runs frames in the app's order and reads the line the scene drew in
## the layer's chunk.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const SceneFixture = preload("res://tests/fixtures/modules/scene-fixture/module.gd")
const Lines = preload("res://tests/fixtures/modules/scene-fixture/lines_scene.gd")

## The stroke's five points in document pixels, and the pen's pressure at each:
## the first is the hover the press takes, the rest the drag's motions.
const POINTS: Array[Vector2] = [Vector2(40, 80), Vector2(80, 90), Vector2(120, 100), Vector2(160, 110), Vector2(200, 120)]
const PRESSURES: Array[float] = [0.2, 0.4, 0.6, 0.8, 1.0]
## The colour the brush is given, far from the fixture's slate ground.
const INK := Color(0.2, 0.8, 0.3, 1.0)
## The brush's radius as a fraction of the canvas's smaller side, which is how
## its settings keep it: 12 pixels of the suite's 256.
const RADIUS_FRACTION := 12.0 / 256.0

var _surface: SaSurface = null
var _doc: SaDocument = null
var _machine: ToolMachine = null
var _registries: SaRegistries = null
var _refused: Array[String] = []


func before_each() -> void:
    SaScenePress.drop()
    _surface = Fixtures.make_surface(Vector2i(256, 256))
    _doc = _surface.easel.document
    _machine = Fixtures.make_bound_machine(_surface)
    _machine.set_active_tool(&"brush")
    _registries = Fixtures.make_registries(_surface)
    var module := SceneFixture.new()
    module.register(_registries.context.for_module(module.get_id()))
    _refused.clear()
    EventBus.paint_refused.connect(_hear_refusal)


func after_each() -> void:
    if EventBus.paint_refused.is_connected(_hear_refusal):
        EventBus.paint_refused.disconnect(_hear_refusal)
    SaScenePress.drop()
    Fixtures.teardown(_surface, _machine)
    _surface = null
    _doc = null
    _machine = null
    _registries = null


func _hear_refusal(line: String) -> void:
    _refused.append(line)


## A layer of *type* above Layer 1, the active one, and its scene's root.
func _scene_root(type: StringName = SceneFixture.LINES_TYPE) -> Node:
    var layer := SaLayerOps.new(_doc).add(type, _registries.layer_types)
    assert_true(layer.is_scene() and _doc.active_layer == layer, "The fixture's scene layer is the active layer")
    var stage := layer.get_node_or_null(SaSceneLayer.NODE_NAME) as SaSceneLayer
    assert_not_null(stage, "and carries its viewport")
    return stage.root if stage != null else null


## Gives the tool in hand [constant INK] and [constant RADIUS_FRACTION], and
## answers its radius in document pixels, the ring the cursor draws.
func _dress_the_brush() -> float:
    var settings: Object = _machine.active_tool.get(&"settings")
    settings.set(&"color", INK)
    settings.set(&"radius", RADIUS_FRACTION)
    return _machine.active_tool.get_cursor_radius()


## A motion at *at*, with the left button down when *down*, from the pen's
## eraser end when *inverted*.
func _move(at: Vector2, pressure: float, down: bool = false, inverted: bool = false) -> void:
    _surface.view.mouse_position = at
    var event := InputEventMouseMotion.new()
    event.position = at
    event.global_position = at
    event.pressure = pressure
    event.pen_inverted = inverted
    event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
    _machine.handle_input(event)


func _button(at: Vector2, pressed: bool) -> void:
    _surface.view.mouse_position = at
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    event.position = at
    event.global_position = at
    _machine.handle_input(event)


## A pen's stroke through *points* at *pressures*: the hover the driver sends
## with the touch, the press at the first point, a motion to each of the rest
## and the release where the last one was.
func _stroke(points: Array[Vector2], pressures: Array[float], inverted: bool = false) -> void:
    _move(points[0], pressures[0], false, inverted)
    _button(points[0], true)
    for index in range(1, points.size()):
        _move(points[index], pressures[index], true, inverted)
    _button(points.back(), false)


func _heard(root: Node) -> Array:
    return root.get("heard")


func test_a_stroke_of_five_points_reaches_the_root_with_their_pressure_and_the_brush_s_radius() -> void:
    var root := _scene_root()
    var radius := _dress_the_brush()
    assert_almost_eq(radius, 12.0, 0.001, "The brush's ring has a radius of 12 document pixels")
    var steps := _doc.history.step_count()
    _stroke(POINTS, PRESSURES)

    var heard := _heard(root)
    assert_eq(heard.size(), 6, "The root is handed the press, four motions and the release")
    for index in POINTS.size():
        var point: Dictionary = heard[index]
        var phase: StringName = SaScenePress.PRESS if index == 0 else SaScenePress.DRAG
        assert_eq(point["method"], SaScenePress.STROKE_METHOD, "Point %d is handed as a stroke" % index)
        assert_eq(point["phase"], phase, "as the %s" % phase)
        assert_eq(point["at"], POINTS[index], "at its document pixel")
        assert_almost_eq(float(point["pressure"]), PRESSURES[index], 0.0001, "with its own pressure")
        assert_almost_eq(float(point["radius"]), radius, 0.0001, "and the brush's radius")
        assert_eq(point["color"], INK, "in the brush's colour")
    var release: Dictionary = heard[5]
    assert_eq(release["phase"], SaScenePress.RELEASE, "The release ends the stroke")
    assert_eq(release["at"], POINTS.back(), "where the pen let go")
    assert_almost_eq(float(release["pressure"]), PRESSURES.back(), 0.0001, "with the last pressure the drag had")
    var strokes: Array = root.get("strokes")
    assert_eq(strokes.size(), 1, "The scene keeps one stroke")

    assert_true(_refused.is_empty(), "The stroke is not refused")
    assert_false(bool(_machine.active_tool.get("is_drawing")), "the brush opened no stroke of its own")
    assert_true(_doc.active_layer.chunks.is_empty(), "Sara laid nothing on the layer, which waits for the scene's copy")
    assert_eq(_doc.history.step_count(), steps, "and wrote no history step after the layer's own")


func test_the_eraser_s_stroke_carries_its_colour_at_alpha_zero() -> void:
    var root := _scene_root()
    _machine.set_active_tool(&"eraser")
    var radius := _dress_the_brush()
    _stroke(POINTS, PRESSURES)
    var heard := _heard(root)
    assert_eq(heard.size(), 6, "The eraser's stroke reaches the root as the brush's does")
    var press: Dictionary = heard[0]
    var color: Color = press["color"]
    assert_almost_eq(color.a, 0.0, 0.0001, "with its colour at alpha 0, what an eraser leaves")
    assert_almost_eq(color.g, INK.g, 0.0001, "and its colour's own channels")
    assert_almost_eq(float(press["radius"]), radius, 0.0001, "at the eraser's radius")

    _machine.set_active_tool(&"brush")
    _dress_the_brush()
    _stroke(POINTS, PRESSURES, true)
    var flipped: Dictionary = _heard(root)[6]
    assert_almost_eq((flipped["color"] as Color).a, 0.0, 0.0001, "The brush on the pen's eraser end erases too")

    _stroke(POINTS, PRESSURES)
    var upright: Dictionary = _heard(root)[12]
    assert_almost_eq((upright["color"] as Color).a, 1.0, 0.0001, "and the pen turned back paints opaque")
    assert_true(_refused.is_empty(), "No stroke is refused")


func test_a_root_that_does_not_take_strokes_refuses_the_brush_as_today() -> void:
    var still := _scene_root(SceneFixture.STILL_TYPE)
    assert_false(still.has_method(SaScenePress.STROKE_METHOD), "The still scene defines no sara_stroke")
    _stroke(POINTS, PRESSURES)
    assert_eq(_refused.size(), 1, "The brush hears the press and is refused, once")
    assert_true(_doc.active_layer.chunks.is_empty(), "and nothing lands on the layer")


func test_a_root_that_takes_only_the_pointer_is_handed_the_brush_s_press_as_the_pointer() -> void:
    var marks := _scene_root(SceneFixture.TYPE)
    assert_false(marks.has_method(SaScenePress.STROKE_METHOD), "The marks scene defines no sara_stroke")
    _stroke(POINTS, PRESSURES)
    var heard := _heard(marks)
    assert_eq(heard.size(), 6, "The brush's press, drag and release reach its sara_pointer, as the pointer suite has it")
    assert_false((heard[0] as Dictionary).has("radius"), "with no radius, since it is the pointer")
    assert_true(_refused.is_empty(), "and nothing is refused")


func test_a_tool_that_is_not_a_brush_hands_a_root_that_takes_both_the_pointer() -> void:
    var root := _scene_root()
    for tool: StringName in [&"eyedropper", &"bucket_fill"]:
        _machine.set_active_tool(tool)
        _stroke(POINTS, PRESSURES)
    var heard := _heard(root)
    assert_eq(heard.size(), 12, "The eyedropper's and the fill's presses reach the root")
    for entry: Dictionary in heard:
        assert_eq(entry["method"], SaScenePress.METHOD, "each as the pointer, since neither is a brush")
    assert_true((root.get("strokes") as Array).is_empty(), "and the scene draws no line for them")

    _machine.set_active_tool(&"pan")
    _stroke(POINTS, PRESSURES)
    assert_eq(_heard(root).size(), 12, "The pan's stroke reaches nothing")


func test_a_shift_press_is_the_machine_s_gesture_and_reaches_no_scene() -> void:
    var root := _scene_root()
    _dress_the_brush()
    _move(POINTS[0], PRESSURES[0])
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    press.shift_pressed = true
    press.position = POINTS[0]
    press.global_position = POINTS[0]
    _machine.handle_input(press)
    _button(POINTS[0], false)
    assert_true(_heard(root).is_empty(), "A Shift click, the brush's straight line, is handed to no scene")


## The layer's colour at *at*, in its one chunk.
func _texel(at: Vector2i) -> Color:
    var texture := _doc.active_layer.get_field(Vector2i.ZERO)
    if texture == null:
        return Color(0.0, 0.0, 0.0, 0.0)
    var data: PackedByteArray = GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var width: int = SaFieldSpec.BYTES_PER_TEXEL[texture.format]
    var offset := (at.y * texture.size.x + at.x) * width
    var red := data.decode_float(offset)
    var green := data.decode_float(offset + 4)
    return Color(red, green, data.decode_float(offset + 8), data.decode_float(offset + 12))


func test_a_stroke_s_line_reaches_the_layer_once_a_frame_has_drawn_it() -> void:
    # A viewport draws only inside the tree, and the teardown frees the easel.
    EventBus.add_child(_surface.easel)
    _scene_root()
    var radius := _dress_the_brush()
    var stage := _doc.active_layer.get_node(SaSceneLayer.NODE_NAME) as SaSceneLayer
    RenderingServer.force_draw(false)
    stage.step()
    var ground := _texel(Vector2i(128, 40))
    assert_true(ground.a > 0.99 and ground.r < 0.3, "The first frame copies the dark ground")

    # A level stroke at full pressure, so the line is the brush's diameter wide.
    var level: Array[Vector2] = [Vector2(40, 128), Vector2(100, 128), Vector2(160, 128), Vector2(220, 128)]
    var full: Array[float] = [1.0, 1.0, 1.0, 1.0]
    _stroke(level, full)
    stage.step()
    RenderingServer.force_draw(false)
    stage.step()
    var half := Lines.width_at(radius, 1.0) * 0.5
    for x: int in [40, 70, 130, 219]:
        var on := _texel(Vector2i(x, 128))
        assert_almost_eq(on.g, INK.g, 0.01, "The layer holds the brush's colour on the stroke at x %d" % x)
        assert_almost_eq(on.r, INK.r, 0.01, "in all of its channels")
    assert_almost_eq(_texel(Vector2i(130, 128 + int(half) - 2)).g, INK.g, 0.01, "out to the brush's radius")
    assert_almost_eq(_texel(Vector2i(130, 128 + int(half) + 3)).b, ground.b, 0.01, "and the ground past it")
    assert_almost_eq(_texel(Vector2i(250, 128)).b, ground.b, 0.01, "and past the stroke's end")
    assert_true(_refused.is_empty(), "No stroke is refused")
