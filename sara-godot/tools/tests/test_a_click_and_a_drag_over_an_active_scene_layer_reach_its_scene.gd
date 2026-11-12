## A click and a drag over an active scene layer reach its scene.
##
## The spec asks that "input reaches the scene when its layer is active and the
## pan tool is not, through the same tool state machine". Each case builds a
## scene layer of the scene fixture's Marks type through the module door, makes
## it the active layer, and drives the machine with the events the canvas hands
## it, then reads what the scene's root was handed: the press's document pixel
## and the pen's pressure, the drag between, and nothing at all while the pan or
## the zoom is the tool in hand. A root that defines no `sara_pointer` is handed
## nothing, and the brush is refused on its layer as before. One case runs a
## frame in the app's own order, input, then `_process`, then the draw, and
## reads the press's mark in the layer's chunk after it.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const SceneFixture = preload("res://tests/fixtures/modules/scene-fixture/module.gd")
const Marks = preload("res://tests/fixtures/modules/scene-fixture/marks_scene.gd")

## Where the click lands, in document pixels, and the pen's pressure at it.
const AT := Vector2(100.0, 60.0)
const PRESSURE := 0.6
## Where a drag from [constant AT] goes, and the pressures of its two motions.
const TO := Vector2(180.0, 140.0)
const DRAG_PRESSURES: Array[float] = [0.3, 0.7]

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
func _scene_root(type: StringName = SceneFixture.TYPE) -> Node:
    var layer := SaLayerOps.new(_doc).add(type, _registries.layer_types)
    assert_true(layer.is_scene() and _doc.active_layer == layer, "The fixture's scene layer is the active layer")
    var stage := layer.get_node_or_null(SaSceneLayer.NODE_NAME) as SaSceneLayer
    assert_not_null(stage, "and carries its viewport")
    return stage.root if stage != null else null


## A motion at *at*, with the left button down when *down*.
func _move(at: Vector2, pressure: float, down: bool = false) -> void:
    _surface.view.mouse_position = at
    var event := InputEventMouseMotion.new()
    event.position = at
    event.global_position = at
    event.pressure = pressure
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


func _key(keycode: Key, pressed: bool) -> void:
    var event := InputEventKey.new()
    event.keycode = keycode
    event.physical_keycode = keycode
    event.pressed = pressed
    _machine.handle_input(event)


## A pen's click: the hover the driver sends with the touch's pressure, the
## press and the release, all at *at*.
func _click(at: Vector2, pressure: float) -> void:
    _move(at, pressure)
    _button(at, true)
    _button(at, false)


func _phases(root: Node) -> Array[StringName]:
    var phases: Array[StringName] = []
    for entry: Dictionary in root.get("heard"):
        phases.append(entry["phase"])
    return phases


func test_a_press_and_a_release_reach_the_root_with_the_pixel_and_the_pressure() -> void:
    var root := _scene_root()
    _click(AT, PRESSURE)

    assert_eq(_phases(root), [&"press", &"release"] as Array[StringName], "The root is handed the press and the release")
    assert_eq(root.get("pressed_at"), AT, "The root holds the document pixel pressed")
    assert_almost_eq(float(root.get("pressed_with")), PRESSURE, 0.0001, "and the pen's pressure there")
    var release: Dictionary = (root.get("heard") as Array)[1]
    assert_eq(release["at"], AT, "The release is where the pen let go")
    assert_true(_refused.is_empty(), "The brush never hears the press, so nothing is refused")
    assert_false(bool(_machine.active_tool.get("is_drawing")), "and no stroke is open")


func test_a_press_s_mark_reaches_the_layer_once_a_frame_has_drawn_it() -> void:
    # A viewport draws only inside the tree, and the teardown frees the easel.
    EventBus.add_child(_surface.easel)
    _scene_root()
    var stage := _doc.active_layer.get_node(SaSceneLayer.NODE_NAME) as SaSceneLayer
    RenderingServer.force_draw(false)
    stage.step()
    var reach: float = Marks.RADIUS + Marks.RADIUS_PER_PRESSURE * PRESSURE
    var inside := Vector2i(AT) + Vector2i(int(reach) - 4, 0)
    var outside := Vector2i(AT) + Vector2i(int(reach) + 4, 0)
    var ground := _texel(inside)
    assert_true(ground.a > 0.99 and ground.r < 0.3, "The first frame copies the dark ground under the press")

    # A frame's input comes before every node's `_process`, and the draw after
    # both, so the step between the click and the draw sees no drawn mark.
    _click(AT, PRESSURE)
    stage.step()
    RenderingServer.force_draw(false)
    stage.step()
    var mark := _texel(Vector2i(AT))
    assert_true(mark.r > 0.9 and mark.b < 0.3, "The layer holds the mark where the pen pressed")
    assert_almost_eq(_texel(inside).g, mark.g, 0.001, "out to the pressure's radius")
    assert_almost_eq(_texel(outside).b, ground.b, 0.001, "and the ground past it")


## The layer's colour at *at*, in its one chunk.
func _texel(at: Vector2i) -> Color:
    var texture := _doc.active_layer.get_field(Vector2i.ZERO)
    if texture == null:
        return Color(0.0, 0.0, 0.0, 0.0)
    var data: PackedByteArray = GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var offset := (at.y * texture.size.x + at.x) * 16
    var red := data.decode_float(offset)
    var green := data.decode_float(offset + 4)
    return Color(red, green, data.decode_float(offset + 8), data.decode_float(offset + 12))


func test_the_drag_between_reaches_it_with_each_motion_s_pressure() -> void:
    var root := _scene_root()
    _move(AT, PRESSURE)
    _button(AT, true)
    _move(AT.lerp(TO, 0.5), DRAG_PRESSURES[0], true)
    _move(TO, DRAG_PRESSURES[1], true)
    _button(TO, false)

    var heard: Array = root.get("heard")
    assert_eq(_phases(root), [&"press", &"drag", &"drag", &"release"] as Array[StringName], "A drag reaches the root between")
    assert_eq(heard[1]["at"], AT.lerp(TO, 0.5), "each motion at its document pixel")
    assert_almost_eq(float(heard[1]["pressure"]), DRAG_PRESSURES[0], 0.0001, "with its own pressure")
    assert_almost_eq(float(heard[2]["pressure"]), DRAG_PRESSURES[1], 0.0001, "the second as well")
    assert_eq(heard[3]["at"], TO, "and the release ends it where the drag did")
    assert_almost_eq(float(heard[3]["pressure"]), DRAG_PRESSURES[1], 0.0001, "with the last pressure the drag had")


func test_a_mouse_press_is_handed_full_pressure() -> void:
    var root := _scene_root()
    _move(AT, 0.0)
    _button(AT, true)
    _move(TO, 0.0, true)
    _button(TO, false)

    var heard: Array = root.get("heard")
    assert_almost_eq(float(heard[0]["pressure"]), 1.0, 0.0001, "A press no motion gave a pressure is a mouse's, 1")
    assert_almost_eq(float(heard[1]["pressure"]), 1.0, 0.0001, "and so is its drag")


func test_a_pan_or_zoom_press_sent_the_same_way_reaches_nothing() -> void:
    var root := _scene_root()
    _machine.set_active_tool(&"pan")
    _click(AT, PRESSURE)
    assert_true((root.get("heard") as Array).is_empty(), "With the pan in hand the scene hears nothing")

    _machine.set_active_tool(&"zoom")
    _click(AT, PRESSURE)
    assert_true((root.get("heard") as Array).is_empty(), "nor with the zoom")

    _machine.set_active_tool(&"brush")
    _click(AT, PRESSURE)
    assert_eq(_phases(root), [&"press", &"release"] as Array[StringName], "and the brush in hand again hands it the next click")


func test_a_held_space_makes_the_pan_the_tool_and_the_scene_hears_nothing() -> void:
    var root := _scene_root()
    _key(KEY_SPACE, true)
    assert_eq(_machine.active_tool_name, &"pan", "A held Space is the pan, through the machine's own quick tools")
    _click(AT, PRESSURE)
    assert_true((root.get("heard") as Array).is_empty(), "and its press reaches no scene")

    _key(KEY_SPACE, false)
    assert_eq(_machine.active_tool_name, &"brush", "Space let go is the brush again")
    _click(AT, PRESSURE)
    assert_eq(_phases(root), [&"press", &"release"] as Array[StringName], "whose click the scene hears")


func test_a_scene_layer_not_active_hears_nothing() -> void:
    var root := _scene_root()
    _doc.set_active_layer(_doc.get_node("Layer 1") as SaLayer)
    _click(AT, PRESSURE)
    assert_true((root.get("heard") as Array).is_empty(), "A scene whose layer is not the active one hears nothing")


func test_a_root_without_the_method_gets_nothing_and_its_layer_refuses_the_brush() -> void:
    var root := _scene_root(SceneFixture.STILL_TYPE)
    assert_false(root.has_method(SaScenePress.METHOD), "The still scene defines no sara_pointer")
    _click(AT, PRESSURE)
    assert_eq(_refused.size(), 1, "The brush hears the press and is refused, as before")
    assert_true(_doc.active_layer.chunks.is_empty(), "and nothing lands on the layer")
