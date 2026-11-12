## The Transform tool moves, scales and rotates every picked layer together.
##
## The tool reads the picked set, as the Layer menu does, and not the active
## layer alone. The box is the union of what the picked layers show, every handle applies one map to
## each, Enter is one step for the set, a locked or hidden layer among them is
## left out by name while the rest move, and Freehand lands the mesh on each.
##
## The pictures are `scenarios/the-transform-tool-moves-scales-and-rotates-every-picked-layer-together.json`.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true
const Fixtures = preload("res://tests/fixtures.gd")
const StateTransformScript = preload("res://modules/sara-base-modules/base/transform/state_transform.gd")

const CANVAS := Vector2i(1024, 1024)
const PAINT := Color(0.8, 0.3, 0.1, 1.0)
## One stroke on each of the three layers, in three places.
const FIRST := Rect2i(100, 100, 120, 80)
const SECOND := Rect2i(400, 140, 100, 100)
const THIRD := Rect2i(200, 400, 150, 60)
const BY := Vector2i(64, 32)

var _surface: SaSurface = null
var _machine: ToolMachine = null
var _document: SaDocument = null
var _tool: StateTransformScript = null
var _first: SaLayer = null
var _second: SaLayer = null
var _third: SaLayer = null


## Three painted ordinary layers, all three picked, the second active, and the
## transform tool on.
func before_each() -> void:
    _surface = Fixtures.make_surface(CANVAS)
    _machine = Fixtures.make_bound_machine(_surface)
    _document = _surface.get_document()
    var ops := SaLayerOps.new(_document)
    _first = ops.add()
    _first.name = "First"
    _paint(_first, FIRST)
    _second = ops.add()
    _second.name = "Second"
    _paint(_second, SECOND)
    _third = ops.add()
    _third.name = "Third"
    _paint(_third, THIRD)
    _document.set_active_layer(_second)
    _document.picked.pick([_third, _second, _first] as Array[SaLayer])
    _document.history.reset()
    _document.undo_redo.clear_history()
    _machine.set_active_tool(&"transform")
    _tool = _machine.active_tool
    SaProblems.announce = false
    SaProblems.pending_refusals = PackedStringArray()


func after_each() -> void:
    SaProblems.announce = true
    SaProblems.pending_refusals = PackedStringArray()
    Fixtures.teardown(_surface, _machine)
    _tool = null
    _machine = null
    _document = null
    _first = null
    _second = null
    _third = null
    _surface = null


static func _image_format(texture: SaTexture) -> Image.Format:
    return Image.FORMAT_RGBAH if texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT else Image.FORMAT_RGBAF


## *rect*, in document pixels, painted on *layer* through an upload.
func _paint(layer: SaLayer, rect: Rect2i) -> void:
    var device := GlobalShaderCompiler.get_rd()
    for grid_pos: Vector2i in SaChunkWalk.positions_in(rect):
        var chunk := layer.get_or_create_chunk(grid_pos)
        var texture := chunk.albedo()
        var edge := chunk.pixel_size()
        var image := Image.create_from_data(edge, edge, false, _image_format(texture), device.texture_get_data(texture.rid, 0))
        image.fill_rect(SaChunkWalk.local_rect(grid_pos, rect, edge), PAINT)
        device.texture_update(texture.rid, 0, image.get_data())
        layer.mark_unresolved(grid_pos)
    _document.invalidate_chunks(layer.chunks.keys())


## The alpha of *layer*'s own texel at *at*, zero where it has no chunk.
static func _alpha_at(layer: SaLayer, at: Vector2i) -> float:
    var texel := Rect2i(at, Vector2i.ONE)
    for grid_pos: Vector2i in SaChunkWalk.positions_in(texel):
        if not layer.chunks.has(grid_pos):
            return 0.0
        var texture: SaTexture = layer.chunks[grid_pos].albedo()
        var edge: int = layer.chunks[grid_pos].pixel_size()
        var data := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
        var image := Image.create_from_data(edge, edge, false, _image_format(texture), data)
        return image.get_pixelv(SaChunkWalk.local_rect(grid_pos, texel, edge).position).a
    return 0.0


func _button(pressed: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    return event


func _enter() -> void:
    var event := InputEventKey.new()
    event.keycode = KEY_ENTER
    event.physical_keycode = KEY_ENTER
    event.pressed = true
    _tool.handle_input(event)


## A press at *from*, a motion to *to* and a release, then the frame's tick.
func _drag(from: Vector2, to: Vector2) -> void:
    _surface.view.mouse_position = from
    _tool.handle_input(_button(true))
    _surface.view.mouse_position = to
    _tool.handle_input(InputEventMouseMotion.new())
    _tool.handle_input(_button(false))
    _tool.tick(0.0)


## The middle of *rect*, a pixel of the stroke painted over it.
static func _middle(rect: Rect2i) -> Vector2i:
    return rect.position + Vector2i(rect.size.x >> 1, rect.size.y >> 1)


## A pull of the bottom right corner to 1.25 times the box, then a turn of 30
## degrees from just outside the corner the pull left, which is the map the
## tool holds afterwards.
func _scale_and_turn(union: Rect2i) -> Transform2D:
    var pulled := Vector2(union.position) + Vector2(union.size) * 1.25
    _drag(Vector2(union.end), pulled)
    var centre := (Vector2(union.position) + pulled) * 0.5
    var outside := pulled + Vector2(10, 10)
    _drag(outside, centre + (outside - centre).rotated(deg_to_rad(30.0)))
    return _tool.matrix


func test_the_box_stands_round_every_picked_layer() -> void:
    assert_eq(_tool.target_box(), FIRST.merge(SECOND).merge(THIRD), "the box is the union of the three strokes")
    assert_eq(_tool.pending_quad().size(), 4, "the box has its four corners on screen")


func test_a_scale_and_a_turn_move_every_layer_by_one_map_and_one_undo_puts_all_three_back() -> void:
    var steps := _document.history.step_count()
    var map := _scale_and_turn(FIRST.merge(SECOND).merge(THIRD))
    assert_true(_tool.is_moving(), "the two gestures are one session on the set")
    assert_almost_eq(_tool.move_angle(), deg_to_rad(30.0), 0.01, "the box turned by 30 degrees")
    assert_almost_eq(_tool.move_scale().x, 1.25, 0.01, "after a pull to 1.25")
    _enter()
    assert_eq(_document.history.step_count(), steps + 1, "the three layers moved as one history step")
    for pair: Array in [[_first, FIRST], [_second, SECOND], [_third, THIRD]]:
        var layer: SaLayer = pair[0]
        var rect: Rect2i = pair[1]
        assert_null(SaLiveTransform.of(layer), "%s is baked and left ordinary" % layer.name)
        var landed := Vector2i((map * Vector2(_middle(rect))).round())
        assert_almost_eq(_alpha_at(layer, landed), 1.0, 0.01, "%s's middle lands where the one map puts it" % layer.name)
        var near := Vector2i((map * Vector2(rect.position + Vector2i(4, 4))).round())
        assert_almost_eq(_alpha_at(layer, near), 1.0, 0.05, "%s's corner lands there too" % layer.name)
        var off := Vector2i((map * Vector2(rect.position - Vector2i(6, 6))).round())
        assert_almost_eq(_alpha_at(layer, off), 0.0, 0.05, "and nothing lands outside %s" % layer.name)
        assert_almost_eq(_alpha_at(layer, rect.position + Vector2i(2, 2)), 0.0, 0.01, "%s left its old corner" % layer.name)
    _document.undo()
    for pair: Array in [[_first, FIRST], [_second, SECOND], [_third, THIRD]]:
        var layer: SaLayer = pair[0]
        var rect: Rect2i = pair[1]
        assert_almost_eq(_alpha_at(layer, rect.position + Vector2i(2, 2)), 1.0, 0.01, "%s is back after one undo" % layer.name)
        assert_almost_eq(_alpha_at(layer, rect.end - Vector2i(2, 2)), 1.0, 0.01, "%s is whole again" % layer.name)
        var landed := Vector2i((map * Vector2(_middle(rect))).round())
        assert_almost_eq(_alpha_at(layer, landed), 0.0, 0.01, "%s left where it had landed" % layer.name)


func test_a_locked_and_a_hidden_layer_among_the_picked_are_left_out_by_name_and_the_rest_move() -> void:
    _second.is_locked = true
    _third.visible = false
    assert_eq(_tool.target_box(), FIRST, "the box stands round what will move")
    _drag(Vector2(_middle(FIRST)), Vector2(_middle(FIRST) + BY))
    _enter()
    assert_almost_eq(_alpha_at(_first, _middle(FIRST) + BY), 1.0, 0.01, "the first layer moved")
    assert_almost_eq(_alpha_at(_second, _middle(SECOND)), 1.0, 0.01, "the locked layer stayed")
    assert_almost_eq(_alpha_at(_third, _middle(THIRD)), 1.0, 0.01, "the hidden layer stayed")
    var said := " ".join(SaProblems.pending_refusals)
    assert_true(said.contains("'Second' is locked"), "the locked layer is named: %s" % said)
    assert_true(said.contains("'Third' is hidden"), "the hidden layer is named: %s" % said)


func test_freehand_lands_its_mesh_on_every_picked_layer_as_one_step() -> void:
    var union := FIRST.merge(SECOND).merge(THIRD)
    _tool.transform_mode = StateTransformScript.Mode.FREEHAND
    var steps := _document.history.step_count()
    _drag(Vector2(union.position), Vector2(union.position - BY))
    assert_true(_tool.is_moving(), "the point drag opened a session on the set")
    _enter()
    assert_eq(_document.history.step_count(), steps + 1, "the set landed as one step")
    var pulled := FIRST.position - BY + Vector2i(4, 4)
    assert_almost_eq(_alpha_at(_first, pulled), 1.0, 0.05, "the first stroke followed the corner point")
    assert_almost_eq(_alpha_at(_second, SECOND.end - Vector2i(2, 2)), 1.0, 0.05, "the second stroke is still on its layer")
    _document.undo()
    for pair: Array in [[_first, FIRST], [_second, SECOND], [_third, THIRD]]:
        var layer: SaLayer = pair[0]
        var rect: Rect2i = pair[1]
        assert_almost_eq(_alpha_at(layer, rect.position + Vector2i(2, 2)), 1.0, 0.01, "%s is back after one undo" % layer.name)


func test_an_active_layer_outside_the_pick_is_transformed_alone() -> void:
    var ops := SaLayerOps.new(_document)
    var fourth := ops.add()
    _paint(fourth, Rect2i(700, 700, 50, 50))
    _document.set_active_layer(fourth)
    assert_eq(_tool.target_box(), Rect2i(700, 700, 50, 50), "the box is the active layer's alone")
