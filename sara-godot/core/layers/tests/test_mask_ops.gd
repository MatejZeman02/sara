## The mask's seven operations, each one a history step.
##
## Each is run and undone and run again, and a texel of the mask, of the albedo
## or of the selection is read after every direction, because an operation
## bound to the wrong texture returns a plausible picture rather than an error.
## Each asserts it took exactly one step on the undo stack.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const RED := Color(1.0, 0.0, 0.0, 1.0)

## Inside the left half of the canvas, and inside the right half.
const LEFT := Vector2i(100, 300)
const RIGHT := Vector2i(400, 300)
## The left half, which several cases select.
const LEFT_HALF := Rect2i(0, 0, 256, 512)

var _easel: SaEasel = null
var _doc: SaDocument = null
var _layer: SaLayer = null


func before_each() -> void:
    _easel = SaEasel.create_default(Vector2i(512, 512))
    _doc = _easel.document
    _layer = _doc.active_layer
    _layer.fill(RED)
    _doc.undo_redo.clear_history()


func after_each() -> void:
    _easel.free()
    _easel = null
    _doc = null
    _layer = null


func _texel(texture: SaTexture, at: Vector2i) -> Color:
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return SaFieldSpec.decode_texel(bytes, texture.format, at.y * texture.size.x + at.x)


func _grid(at: Vector2i) -> Vector2i:
    @warning_ignore("integer_division")
    return Vector2i(at.x / SaChunk.SIZE, at.y / SaChunk.SIZE)


## The coverage the owner's mask holds at a document pixel, its rest where it
## holds nothing, and -1 for an owner with no mask at all.
func _coverage(owner: SaLayer, at: Vector2i) -> float:
    if owner.mask == null:
        return -1.0
    var texture := owner.mask.texture_for(_grid(at))
    if texture == null:
        return owner.mask.rest
    return _texel(texture, at - _grid(at) * SaChunk.SIZE).r


func _alpha(at: Vector2i) -> float:
    return _texel(_layer.get_field(_grid(at)), at - _grid(at) * SaChunk.SIZE).a


## The selection's coverage at a document pixel: one with none active, zero
## where an active one holds no chunk.
func _selected(at: Vector2i) -> float:
    var texture := _doc.selection.texture_for(_grid(at))
    if texture == null:
        return 0.0
    return _texel(texture, at - _grid(at) * SaChunk.SIZE).r


func _steps() -> int:
    return _doc.undo_redo.get_history_count()


func _ops() -> SaMaskOps:
    return SaMaskOps.new(_doc)


## A mask whose left half shows and right half hides, as one step.
func _half_mask() -> void:
    _doc.selection.select_rect(LEFT_HALF)
    assert_true(_ops().add_from_selection(_layer), "a mask from the left half")
    _doc.selection.deselect()


func test_add_is_one_step_that_undo_takes_back() -> void:
    assert_true(_ops().add(_layer), "the add runs on a layer with no mask")
    assert_eq(_steps(), 1, "as one step")
    assert_almost_eq(_coverage(_layer, LEFT), 1.0, 0.001, "and the new mask hides nothing")
    _doc.undo_redo.undo()
    assert_null(_layer.mask, "undo takes the mask away")
    _doc.undo_redo.redo()
    assert_almost_eq(_coverage(_layer, LEFT), 1.0, 0.001, "and redo brings it back")
    assert_false(_ops().add(_layer), "a second add on a layer that has one does nothing")
    assert_eq(_steps(), 1, "and writes no step")


func test_add_from_selection_carries_the_feather() -> void:
    _doc.selection.select_ellipse(Rect2i(128, 128, 256, 256))
    SaSelectionFilters.feather(_doc.selection, 24, _doc.canvas_size)
    var edge := Vector2i(256, 140)
    var feathered := _selected(edge)
    assert_true(feathered > 0.05 and feathered < 0.95, "the selection is soft at the edge: %s" % feathered)
    assert_true(_ops().add_from_selection(_layer), "the add runs")
    assert_eq(_steps(), 1, "as one step")
    assert_almost_eq(_coverage(_layer, Vector2i(256, 256)), 1.0, 0.001, "the centre shows")
    assert_almost_eq(_coverage(_layer, Vector2i(10, 10)), 0.0, 0.001, "the corner outside is hidden")
    assert_almost_eq(_coverage(_layer, edge), feathered, 0.001, "and the edge carries the feather, texel for texel")
    _doc.undo_redo.undo()
    assert_null(_layer.mask, "undo takes the mask away")
    _doc.undo_redo.redo()
    assert_almost_eq(_coverage(_layer, edge), feathered, 0.001, "and redo brings the feather back")


func test_add_from_no_selection_hides_nothing() -> void:
    assert_true(_ops().add_from_selection(_layer), "with nothing selected everything is")
    assert_almost_eq(_coverage(_layer, LEFT), 1.0, 0.001, "so the mask hides nothing")


func test_delete_and_its_undo() -> void:
    _half_mask()
    assert_true(_ops().remove(_layer), "the delete runs")
    assert_eq(_steps(), 2, "as one step after the add's")
    assert_null(_layer.mask, "the mask is gone")
    assert_almost_eq(_alpha(RIGHT), 1.0, 0.001, "and the paint it hid is untouched")
    _doc.undo_redo.undo()
    assert_almost_eq(_coverage(_layer, RIGHT), 0.0, 0.001, "undo brings back what it hid")
    assert_almost_eq(_coverage(_layer, LEFT), 1.0, 0.001, "and what it showed")
    _doc.undo_redo.redo()
    assert_null(_layer.mask, "and redo takes it away again")


func test_apply_multiplies_the_alpha_and_drops_the_mask() -> void:
    _half_mask()
    assert_true(_ops().apply(_layer), "the apply runs")
    assert_eq(_steps(), 2, "as one step after the add's")
    assert_null(_layer.mask, "the mask is gone")
    assert_almost_eq(_alpha(LEFT), 1.0, 0.001, "the shown half keeps its alpha")
    assert_almost_eq(_alpha(RIGHT), 0.0, 0.001, "and the hidden half's alpha is the product, zero")
    _doc.undo_redo.undo()
    assert_almost_eq(_alpha(RIGHT), 1.0, 0.001, "undo brings the alpha back")
    assert_almost_eq(_coverage(_layer, RIGHT), 0.0, 0.001, "and the mask with it")
    _doc.undo_redo.redo()
    assert_null(_layer.mask, "redo drops the mask")
    assert_almost_eq(_alpha(RIGHT), 0.0, 0.001, "and applies it again")


func test_applying_a_disabled_mask_leaves_the_paint() -> void:
    _half_mask()
    _ops().set_enabled(_layer, false)
    assert_true(_ops().apply(_layer), "the apply runs")
    assert_null(_layer.mask, "the mask is gone")
    assert_almost_eq(_alpha(RIGHT), 1.0, 0.001, "and a mask that was off, reading one, hid nothing for good")


func test_invert_and_its_undo() -> void:
    _half_mask()
    assert_true(_ops().invert(_layer), "the invert runs")
    assert_eq(_steps(), 2, "as one step after the add's")
    assert_almost_eq(_coverage(_layer, LEFT), 0.0, 0.001, "what showed is hidden")
    assert_almost_eq(_coverage(_layer, RIGHT), 1.0, 0.001, "and what was hidden shows")
    _doc.undo_redo.undo()
    assert_almost_eq(_coverage(_layer, LEFT), 1.0, 0.001, "undo puts the left back")
    assert_almost_eq(_coverage(_layer, RIGHT), 0.0, 0.001, "and the right")
    _doc.undo_redo.redo()
    assert_almost_eq(_coverage(_layer, LEFT), 0.0, 0.001, "and redo inverts again")


func test_disable_and_its_undo() -> void:
    _half_mask()
    assert_true(_ops().set_enabled(_layer, false), "the disable runs")
    assert_eq(_steps(), 2, "as one step after the add's")
    assert_false(_layer.mask.enabled, "the mask is off")
    assert_almost_eq(_coverage(_layer, RIGHT), 0.0, 0.001, "and keeps what it hides for when it comes back")
    assert_null(SaCompositor.coverage_at(_layer, _grid(RIGHT)), "so the composite reads it as one")
    _doc.undo_redo.undo()
    assert_true(_layer.mask.enabled, "undo switches it back on")
    _doc.undo_redo.redo()
    assert_false(_layer.mask.enabled, "and redo off")
    assert_true(_ops().run(SaMaskOps.DISABLE, _layer), "the command is a toggle")
    assert_true(_layer.mask.enabled, "and turns it on again")


func test_to_selection_and_its_undo_from_no_selection() -> void:
    _half_mask()
    assert_false(_doc.selection.active, "nothing is selected before")
    assert_true(_ops().to_selection(_layer), "the mask to selection runs")
    assert_eq(_steps(), 2, "as one step after the add's")
    assert_true(_doc.selection.active, "a selection exists")
    assert_almost_eq(_selected(LEFT), 1.0, 0.001, "what the mask shows is selected")
    assert_almost_eq(_selected(RIGHT), 0.0, 0.001, "and what it hides is not")
    assert_eq(_doc.selection.bounds, LEFT_HALF, "and the bounds are the shown half, measured")
    _doc.undo_redo.undo()
    assert_false(_doc.selection.active, "undo gives back no selection, which is everything selected")
    assert_eq(_doc.selection.bounds, Rect2i(), "with the bounds it had")


func test_to_selection_undo_gives_back_the_selection_the_painter_had() -> void:
    _half_mask()
    var had := Rect2i(300, 300, 100, 100)
    _doc.selection.select_rect(had)
    var had_bounds := _doc.selection.bounds
    assert_true(_ops().to_selection(_layer), "the mask to selection runs")
    assert_almost_eq(_selected(Vector2i(350, 350)), 0.0, 0.001, "the old selection is replaced")
    _doc.undo_redo.undo()
    assert_eq(_doc.selection.bounds, had_bounds, "undo gives back its bounds")
    assert_almost_eq(_selected(Vector2i(350, 350)), 1.0, 0.001, "and its texels")
    assert_almost_eq(_selected(LEFT), 0.0, 0.001, "and nothing of the mask")


func test_a_group_takes_a_mask_of_its_own() -> void:
    var group := SaLayerOps.new(_doc).group_active()
    assert_not_null(group, "a group around the layer")
    var before := _steps()
    assert_true(_ops().add(group), "the add runs on a group")
    assert_eq(_steps(), before + 1, "as one step")
    assert_true(group.mask.is_own(), "and the group's mask keeps chunks of its own")
    assert_true(SaLayerStack.isolates(group), "which isolates the pass-through group")
    assert_false(group.isolated, "without writing its flag")
    assert_false(SaMaskOps.can(SaMaskOps.APPLY, group), "a group has no paint to apply a mask into")
    assert_true(_ops().invert(group), "the invert runs on a group")
    assert_almost_eq(_coverage(group, LEFT), 0.0, 0.001, "and reads zero over the canvas, by its rest and with no chunk")
    assert_eq(group.mask.grid_positions().size(), 0, "allocating nothing")
    _doc.undo_redo.undo()
    assert_almost_eq(_coverage(group, LEFT), 1.0, 0.001, "undo takes the invert back")
    _doc.undo_redo.undo()
    assert_null(group.mask, "and the add")
    assert_false(SaLayerStack.isolates(group), "and the group passes through again")


func test_what_can_run_is_what_the_menus_dim_by() -> void:
    for command_id: StringName in SaMaskOps.ALL:
        assert_eq(
            SaMaskOps.can(command_id, _layer),
            command_id in [SaMaskOps.ADD, SaMaskOps.ADD_FROM_SELECTION],
            "%s with no mask" % command_id
        )
    _ops().add(_layer)
    for command_id: StringName in SaMaskOps.ALL:
        assert_eq(
            SaMaskOps.can(command_id, _layer),
            not command_id in [SaMaskOps.ADD, SaMaskOps.ADD_FROM_SELECTION],
            "%s with a mask" % command_id
        )
    assert_false(SaMaskOps.can(SaMaskOps.ADD, null), "and nothing runs on no layer")


func test_deleting_the_painted_mask_takes_the_brush_off_it() -> void:
    _ops().add(_layer)
    _doc.mask_target = _layer.mask
    _ops().remove(_layer)
    assert_null(_doc.mask_target, "the brush paints colour again")
