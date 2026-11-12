## Ctrl+T on a group transforms every layer in it together.
##
## A group holds no chunks, so the box is the union of every layer inside, nested
## groups included. Enter puts each layer down as one
## step, and one undo puts all of them back. A locked layer inside refuses the
## whole transform by name, an adjustment layer inside is left as it is, a
## smart layer keeps its map live, the group's mask moves with the paint, and
## a selection moves only what it covers in each layer.
##
## The pictures are `scenarios/ctrl-t-on-a-group-transforms-every-layer-in-it-together.json`.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true
const Fixtures = preload("res://tests/fixtures.gd")
const StateTransformScript = preload("res://modules/sara-base-modules/base/transform/state_transform.gd")
const GroupScript = preload("res://modules/sara-base-modules/base/transform/group/sa_transform_group.gd")

const CANVAS := Vector2i(1024, 1024)
const PAINT := Color(0.8, 0.3, 0.1, 1.0)
## One stroke on each of the three layers, the third inside the nested group.
const FIRST := Rect2i(100, 100, 120, 80)
const SECOND := Rect2i(400, 140, 100, 100)
const THIRD := Rect2i(200, 400, 150, 60)
## How far the body drag moves the box.
const BY := Vector2i(64, 32)

var _surface: SaSurface = null
var _machine: ToolMachine = null
var _document: SaDocument = null
var _tool: StateTransformScript = null
var _first: SaLayer = null
var _second: SaLayer = null
var _third: SaLayer = null
var _inner: SaLayer = null
var _group: SaLayer = null


## Two painted layers in a group and a third in a group inside it, the outer
## group active and the transform tool on.
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
    _inner = ops.group_layers([_third])
    _group = ops.group_layers([_first, _second, _inner])
    _document.set_active_layer(_group)
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
    _inner = null
    _group = null
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


func test_the_box_stands_round_every_layer_inside_the_group_nested_included() -> void:
    var union := FIRST.merge(SECOND).merge(THIRD)
    assert_eq(_tool.target_box(), union, "the box is the union of the three strokes")
    assert_eq(_tool.pending_quad().size(), 4, "the box has its four corners on screen")


func test_a_move_lands_every_stroke_at_its_new_place_and_one_undo_puts_all_three_back() -> void:
    var steps := _document.history.step_count()
    var union := FIRST.merge(SECOND).merge(THIRD)
    _drag(Vector2(_middle(FIRST)), Vector2(_middle(FIRST) + BY))
    assert_true(_tool.is_moving(), "the drag opened a session on the group")
    _enter()
    assert_eq(_document.history.step_count(), steps + 1, "the three layers moved as one history step")
    for layer: SaLayer in [_first, _second, _third]:
        assert_null(SaLiveTransform.of(layer), "%s is baked and left ordinary" % layer.name)
    for pair: Array in [[_first, FIRST], [_second, SECOND], [_third, THIRD]]:
        var layer: SaLayer = pair[0]
        var rect: Rect2i = pair[1]
        assert_almost_eq(_alpha_at(layer, _middle(rect) + BY), 1.0, 0.01, "%s's stroke is at its new place" % layer.name)
        assert_almost_eq(_alpha_at(layer, rect.position + Vector2i(2, 2)), 0.0, 0.01, "%s's old corner is empty" % layer.name)
    assert_eq(_tool.target_box(), Rect2i(union.position + BY, union.size), "the box follows the strokes")
    _document.undo()
    for pair: Array in [[_first, FIRST], [_second, SECOND], [_third, THIRD]]:
        var layer: SaLayer = pair[0]
        var rect: Rect2i = pair[1]
        assert_almost_eq(_alpha_at(layer, rect.position + Vector2i(2, 2)), 1.0, 0.01, "%s is back after one undo" % layer.name)
        assert_almost_eq(_alpha_at(layer, rect.end + BY - Vector2i(2, 2)), 0.0, 0.01, "%s left its new place" % layer.name)
        assert_null(SaLiveTransform.of(layer), "%s carries no transform after the undo" % layer.name)


func test_a_scale_from_a_corner_handle_scales_every_layer_about_the_same_far_corner() -> void:
    var union := FIRST.merge(SECOND).merge(THIRD)
    _drag(Vector2(union.end), Vector2(union.position + union.size * 2))
    _enter()
    # The far corner stays, so a point at offset d from it lands at 2d.
    for pair: Array in [[_first, FIRST], [_second, SECOND], [_third, THIRD]]:
        var layer: SaLayer = pair[0]
        var rect: Rect2i = pair[1]
        var landed := union.position + (_middle(rect) - union.position) * 2
        assert_almost_eq(_alpha_at(layer, landed), 1.0, 0.01, "%s's middle lands twice as far from the corner" % layer.name)


func test_a_locked_layer_inside_refuses_the_whole_transform_by_name() -> void:
    _second.is_locked = true
    var steps := _document.history.step_count()
    _drag(Vector2(_middle(FIRST)), Vector2(_middle(FIRST) + BY))
    _enter()
    assert_false(_tool.is_moving(), "no session opened")
    assert_eq(_document.history.step_count(), steps, "nothing was written")
    assert_almost_eq(_alpha_at(_first, _middle(FIRST)), 1.0, 0.01, "the first layer did not move either")
    var said := " ".join(SaProblems.pending_refusals)
    assert_true(said.contains("'Second' is locked"), "the refusal names the locked layer: %s" % said)


func test_an_adjustment_layer_inside_is_left_as_it_is() -> void:
    var ops := SaLayerOps.new(_document)
    _document.set_active_layer(_second)
    var adjustment := ops.add()
    adjustment.name = "Adjustment"
    adjustment.input = SaLayerTypeDescriptor.INPUT_BELOW
    adjustment.group = _group
    adjustment.get_or_create_chunk(Vector2i(3, 3)).clear(PAINT)
    _document.set_active_layer(_group)
    _document.history.reset()
    assert_eq(_tool.target_box(), FIRST.merge(SECOND).merge(THIRD), "the adjustment widens no box")
    _drag(Vector2(_middle(FIRST)), Vector2(_middle(FIRST) + BY))
    _enter()
    assert_null(SaLiveTransform.of(adjustment), "the adjustment layer carries no transform")
    assert_eq(adjustment.chunks.keys(), [Vector2i(3, 3)], "the adjustment layer keeps the chunk it had")
    assert_almost_eq(_alpha_at(_first, _middle(FIRST) + BY), 1.0, 0.01, "the paint beside it moved")


func test_a_smart_layer_inside_keeps_its_map_live() -> void:
    SaLiveTransform.put(_document, _second, Basis.IDENTITY)
    _document.history.reset()
    _drag(Vector2(_middle(FIRST)), Vector2(_middle(FIRST) + BY))
    _enter()
    var live := SaLiveTransform.of(_second)
    assert_not_null(live, "the smart layer keeps a live transform")
    var off := live.map_point(Vector2(10, 10)).distance_to(Vector2(10, 10) + Vector2(BY))
    assert_almost_eq(off, 0.0, 0.01, "its map moved by the drag")
    assert_almost_eq(_alpha_at(_second, _middle(SECOND)), 1.0, 0.01, "its paint stays where it was painted")


func test_the_group_s_mask_moves_with_the_group() -> void:
    var mask := _group.add_mask()
    mask.get_or_create(Vector2i.ZERO).clear(Color(0.0, 0.0, 0.0, 0.0))
    _drag(Vector2(_middle(FIRST)), Vector2(_middle(FIRST) + Vector2i(256, 0)))
    _enter()
    assert_true(mask.grid_positions().has(Vector2i(1, 0)), "the hidden chunk is now one chunk over")
    var moved := mask.coverage(Vector2i(1, 0))
    assert_not_null(moved, "the mask hides something one chunk over")
    var data := GlobalShaderCompiler.get_rd().texture_get_data(moved.rid, 0)
    assert_almost_eq(data.to_float32_array()[128 * 256 + 128], 0.0, 0.01, "the middle of the chunk over is hidden")
    var left := mask.coverage(Vector2i.ZERO)
    if left != null:
        var back := GlobalShaderCompiler.get_rd().texture_get_data(left.rid, 0).to_float32_array()
        assert_almost_eq(back[128 * 256 + 128], 1.0, 0.01, "where the hidden chunk was shows again")
    _document.undo()
    assert_false(mask.grid_positions().has(Vector2i(1, 0)), "one undo puts the mask back too")


func test_a_selection_moves_only_what_it_covers_in_each_layer() -> void:
    # Covering the left half of the first stroke and the left half of the third.
    var picked := Rect2i(FIRST.position.x, FIRST.position.y, 60, THIRD.end.y - FIRST.position.y)
    _document.selection.select_rect(picked)
    assert_eq(_tool.target_box(), picked, "the box is the selection's, as for a layer")
    _drag(Vector2(_middle(picked)), Vector2(_middle(picked) + BY))
    _enter()
    var inside := FIRST.position + Vector2i(10, 10)
    var outside := FIRST.position + Vector2i(100, 10)
    assert_almost_eq(_alpha_at(_first, inside + BY), 1.0, 0.01, "the covered part of the first stroke moved")
    assert_almost_eq(_alpha_at(_first, inside), 0.0, 0.01, "and left its hole")
    assert_almost_eq(_alpha_at(_first, outside), 1.0, 0.01, "the part outside stayed")
    var third_in := THIRD.position + Vector2i(10, 10)
    assert_almost_eq(_alpha_at(_third, third_in + BY), 1.0, 0.01, "the covered part of the nested stroke moved")
    assert_almost_eq(_alpha_at(_second, _middle(SECOND)), 1.0, 0.01, "the uncovered layer stayed")
    assert_eq(_document.selection.bounds.position, picked.position + BY, "the selection went with the pixels once")
    _document.undo()
    assert_almost_eq(_alpha_at(_first, inside), 1.0, 0.01, "one undo puts the first stroke back")
    assert_almost_eq(_alpha_at(_third, third_in), 1.0, 0.01, "and the nested one")


## The coverage *mask* holds at the document pixel *at*, its rest where it holds
## no chunk there, which is what a reader of the mask sees.
static func _mask_at(mask: SaMask, at: Vector2i) -> float:
    var texel := Rect2i(at, Vector2i.ONE)
    for grid_pos: Vector2i in SaChunkWalk.positions_in(texel):
        var texture := mask.texture_for(grid_pos)
        if texture == null:
            return mask.rest
        var local := SaChunkWalk.local_rect(grid_pos, texel, SaChunk.SIZE).position
        var data := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0).to_float32_array()
        return data[local.y * SaChunk.SIZE + local.x]
    return mask.rest


func test_a_turned_group_s_mask_shows_in_the_corners_the_turn_left_empty() -> void:
    var mask := _group.add_mask()
    mask.get_or_create(Vector2i.ZERO).clear(Color(0.0, 0.0, 0.0, 0.0))
    # Straight at the carry, because the handles turn the box by a drag just
    # outside a corner and what is asked here is the turn itself: the landed box
    # of a turned square has corners no texel of the square reaches.
    var landing: Array = [Transform2D(0.4, Vector2.ZERO), PackedFloat32Array(), SaResampleKernel.Filter.BILINEAR, Rect2i()]
    GroupScript.MaskCarry.carry(_document, mask, landing, SaTransformSelection.Kernels.new())
    assert_almost_eq(_mask_at(mask, Vector2i(68, 168)), 0.0, 0.02, "the middle of the hidden chunk turned with the group")
    assert_almost_eq(_mask_at(mask, Vector2i(-99, 2)), 1.0, 0.02, "and a corner the turn left empty shows, at the mask's rest")
