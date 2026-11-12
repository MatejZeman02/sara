## A scene layer under a live transform hands its scene the
## point the painter pressed.
##
## The ask: `at`, and `radius` for a stroke, "reach the scene in the scene's own
## pixels: the inverse of the layer's live transform applied to the document
## point when the layer has one, and the document point as now when it has
## none." Each case builds a scene layer of the scene fixture through the module
## door, makes it the active layer, gives it a live transform that moves and
## turns it, or none, and drives the machine with a press, a drag and a release.
## The root keeps what it was handed, and the suite reads each point against
## the inverse of the map applied to the document point, within a hundredth of
## a pixel. One point of the drag lies where the map puts it outside the scene,
## and is handed all the same.
##
## The transform is put on the layer by hand, as the crop tool's suite puts
## one. The Transform tool puts it, and its own suite reads the press
## after the tool's drags. The press reads the map whoever put it there.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const SceneFixture = preload("res://tests/fixtures/modules/scene-fixture/module.gd")

## The press, the drag's motions and the release, in document pixels. The last
## motion is where the map below takes it back past the scene's left edge.
const POINTS: Array[Vector2] = [Vector2(100, 60), Vector2(140, 90), Vector2(180, 140), Vector2(2, 10)]
const PRESSURES: Array[float] = [0.3, 0.5, 0.7, 0.9]
## The map: a move of 40 by 25 and a turn of 30 degrees about the canvas's
## middle, and a scale of 1.5 for the stroke's radius.
const OFFSET := Vector2(40.0, 25.0)
const DEGREES := 30.0
const PIVOT := Vector2(128.0, 128.0)
const SCALE := 1.5
## How near a handed point must lie to the one the inverse makes.
const TOLERANCE := 0.01

var _surface: SaSurface = null
var _doc: SaDocument = null
var _machine: ToolMachine = null
var _registries: SaRegistries = null
var _layer: SaLayer = null


func before_each() -> void:
    SaScenePress.drop()
    _surface = Fixtures.make_surface(Vector2i(256, 256))
    _doc = _surface.easel.document
    _machine = Fixtures.make_bound_machine(_surface)
    _registries = Fixtures.make_registries(_surface)
    var module := SceneFixture.new()
    module.register(_registries.context.for_module(module.get_id()))


func after_each() -> void:
    if _layer != null and _layer.live_transform != null:
        (_layer.live_transform as SaLiveTransform).release()
        _layer.live_transform = null
    SaScenePress.drop()
    Fixtures.teardown(_surface, _machine)
    _surface = null
    _doc = null
    _machine = null
    _registries = null
    _layer = null


## A layer of *type* above Layer 1, the active one, drawn through *map* when it
## is not null, and its scene's root.
func _scene_root(type: StringName, map: Variant) -> Node:
    _layer = SaLayerOps.new(_doc).add(type, _registries.layer_types)
    assert_true(_layer.is_scene() and _doc.active_layer == _layer, "The fixture's scene layer is the active layer")
    if map != null:
        _layer.live_transform = SaLiveTransform.new(map)
    var stage := _layer.get_node_or_null(SaSceneLayer.NODE_NAME) as SaSceneLayer
    assert_not_null(stage, "and carries its viewport")
    return stage.root if stage != null else null


func _move(at: Vector2, pressure: float, down: bool) -> void:
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


## The hover the pen's driver sends, the press at the first point, a motion to
## each of the rest and the release where the last one was.
func _press_drag_release() -> void:
    _move(POINTS[0], PRESSURES[0], false)
    _button(POINTS[0], true)
    for index in range(1, POINTS.size()):
        _move(POINTS[index], PRESSURES[index], true)
    _button(POINTS.back(), false)


## Where *map* shows paint at *point*, taken back into the layer's own pixels,
## worked here from the matrix rather than through the class under test.
func _inverse(map: Basis, point: Vector2) -> Vector2:
    var back := map.inverse() * Vector3(point.x, point.y, 1.0)
    return Vector2(back.x, back.y) / back.z


## The document points the root should be handed, press, drags and release, in
## the scene's pixels under *map*, or as they are for null.
func _expected(map: Variant) -> Array[Vector2]:
    var points: Array[Vector2] = []
    for point: Vector2 in POINTS:
        points.append(point if map == null else _inverse(map, point))
    points.append(points.back())
    return points


func _read(heard: Array, expected: Array[Vector2], what: String) -> void:
    assert_eq(heard.size(), expected.size(), "The root is handed the press, %d motions and the release" % (POINTS.size() - 1))
    if heard.size() != expected.size():
        return
    for index in expected.size():
        var at: Vector2 = (heard[index] as Dictionary)["at"]
        assert_true(
            at.distance_to(expected[index]) <= TOLERANCE,
            "Point %d is handed at %s, %s, and was %s" % [index, expected[index], what, at]
        )
    assert_eq((heard[0] as Dictionary)["phase"], SaScenePress.PRESS, "The first is the press")
    assert_eq((heard.back() as Dictionary)["phase"], SaScenePress.RELEASE, "and the last the release")


func test_a_moved_and_turned_layer_hands_its_scene_the_inverse_of_the_map_at_each_point() -> void:
    var map := SaLiveTransform.composed(OFFSET, DEGREES, Vector2.ONE, PIVOT)
    var root := _scene_root(SceneFixture.TYPE, map)
    _press_drag_release()
    var expected := _expected(map)
    _read(root.get("heard"), expected, "the document point taken back through the map")
    var scene := Rect2(Vector2.ZERO, Vector2(_doc.canvas_size))
    assert_true(scene.has_point(expected[0]), "The press lands inside the scene, at %s" % expected[0])
    var outside: Vector2 = expected[POINTS.size() - 1]
    assert_true(outside.x < 0.0, "the drag's last motion leaves it, at %s, and is handed all the same" % outside)
    assert_eq((root.get("heard") as Array).back()["at"], outside, "and the release ends the drag there, outside")
    assert_true(expected[0].distance_to(POINTS[0]) > 1.0, "and the map moved the press off its document pixel")


func test_a_layer_with_no_live_transform_hands_its_scene_the_document_points() -> void:
    var root := _scene_root(SceneFixture.TYPE, null)
    _press_drag_release()
    _read(root.get("heard"), _expected(null), "its document pixel unchanged")


func test_a_stroke_on_a_scaled_and_turned_layer_takes_its_points_and_its_radius_back_through_the_map() -> void:
    _machine.set_active_tool(&"brush")
    var settings: Object = _machine.active_tool.get(&"settings")
    settings.set(&"radius", 12.0 / 256.0)
    var radius: float = _machine.active_tool.get_cursor_radius()
    var map := SaLiveTransform.composed(OFFSET, DEGREES, Vector2(SCALE, SCALE), PIVOT)
    var root := _scene_root(SceneFixture.LINES_TYPE, map)
    _press_drag_release()
    var heard: Array = root.get("heard")
    _read(heard, _expected(map), "the stroke's point taken back through the map")
    for point: Dictionary in heard:
        assert_eq(point["method"], SaScenePress.STROKE_METHOD, "Each point is handed as a stroke")
        assert_almost_eq(float(point["radius"]), radius / SCALE, TOLERANCE, "with the brush's ring in the scene's pixels")
