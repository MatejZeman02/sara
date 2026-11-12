## The brush paints the mask.
##
## A dab goes through `SaPaintContext` onto the mask the document names as its
## `mask_target`, the way the quick mask paints the selection, and a stroke on
## it is one history step. Both stores a mask keeps are driven, the field of a
## layer's chunks and the chunks of its own that a group's and a filter's mask
## hold, because the second is the door a later mask kind inherits. Every texel is read back:
## a dab bound to the wrong texture returns a plausible picture, not an error.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const PaintKernel = preload("res://tests/fixtures/paint_kernel.gd")

## Black coverage, which hides what the mask covers.
const HIDE := Color(0.0, 0.0, 0.0, 1.0)
const RED := Color(1.0, 0.0, 0.0, 1.0)

## Where the dab lands, inside the first chunk.
const AT := Vector2i(100, 100)

var _easel: SaEasel = null
var _doc: SaDocument = null


func before_each() -> void:
    _easel = SaEasel.create_default(Vector2i(512, 512))
    _doc = _easel.document


func after_each() -> void:
    _easel.free()
    _easel = null
    _doc = null


func _texel(texture: SaTexture, at: Vector2i) -> Color:
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return SaFieldSpec.decode_texel(bytes, texture.format, at.y * texture.size.x + at.x)


## The coverage *mask* holds at a document pixel, one where it holds nothing.
func _coverage(mask: SaMask, at: Vector2i) -> float:
    @warning_ignore("integer_division")
    var grid := Vector2i(at.x / SaChunk.SIZE, at.y / SaChunk.SIZE)
    var texture := mask.texture_for(grid)
    if texture == null:
        return 1.0
    return _texel(texture, at - grid * SaChunk.SIZE).r


## One hard dab of *color* through the paint context, whatever it targets.
func _dab(pos: Vector2, radius: float, color: Color) -> SaPaintContext:
    var compute := PaintKernel.compute()
    var region := Rect2(pos.x - radius, pos.y - radius, radius * 2.0, radius * 2.0)
    var paint := SaPaintContext.for_region(_doc, region, false)
    paint.dispatch_batch(
        compute,
        "paint",
        func(target: SaPaintContext.Target) -> void:
            compute.set_texture(0, target.texture.rid)
            compute.set_push_constant_float_array(
                PaintKernel.pack_params(paint.local_point(target, pos), target.render_offset, color, radius, 1.0, 1.0, 1.0)
            )
    )
    paint.commit_invalidation()
    return paint


## A whole stroke of one dab, opened and committed the way the brush does.
func _stroke(pos: Vector2, radius: float, color: Color) -> SaPaintContext:
    _doc.begin_stroke(1.0, SaLayer.BLEND_MODE.NORMAL)
    var paint := _dab(pos, radius, color)
    _doc.commit_stroke()
    return paint


## The read before, after and after the undo, and one step between them.
func _assert_one_step(mask: SaMask, what: String) -> void:
    _doc.mask_target = mask
    var steps := _doc.history.step_count()
    assert_almost_eq(_coverage(mask, AT), 1.0, 1e-6, "%s shows whole before the stroke" % what)

    var paint := _stroke(Vector2(AT), 12.0, HIDE)
    assert_true(paint.paints_coverage, "%s is painted as coverage" % what)
    assert_eq(paint.targets.size(), 1, "%s takes one chunk" % what)
    assert_almost_eq(_coverage(mask, AT), 0.0, 1e-6, "%s hides where the stroke went" % what)
    assert_almost_eq(_coverage(mask, AT + Vector2i(40, 0)), 1.0, 1e-6, "%s and nowhere else" % what)
    assert_eq(_doc.history.step_count(), steps + 1, "%s is one history step" % what)

    assert_true(_doc.undo(), "%s undoes" % what)
    assert_almost_eq(_coverage(mask, AT), 1.0, 1e-6, "%s shows whole again after one undo" % what)
    assert_true(_doc.redo(), "%s redoes" % what)
    assert_almost_eq(_coverage(mask, AT), 0.0, 1e-6, "%s hides again after the redo" % what)


func test_a_stroke_on_a_layers_mask_is_one_step() -> void:
    var layer := _doc.active_layer
    _assert_one_step(layer.add_mask(), "a layer's mask")


func test_a_stroke_on_a_layers_mask_leaves_its_colour_alone() -> void:
    var layer := _doc.active_layer
    layer.fill(RED)
    _doc.mask_target = layer.add_mask()
    _stroke(Vector2(AT), 12.0, HIDE)
    var albedo := layer.get_field(Vector2i.ZERO)
    assert_almost_eq(_texel(albedo, AT).r, 1.0, 1e-6, "the colour under the mask is still red")
    assert_almost_eq(_texel(albedo, AT).a, 1.0, 1e-6, "and still opaque")
    assert_eq(_doc.stroke_layer.chunks.size(), 0, "no stroke buffer was used")


func test_a_stroke_on_an_own_mask_is_one_step() -> void:
    _assert_one_step(SaMask.own(), "an own mask")


## The undo of a stroke that allocated the own mask's chunk takes the chunk
## away again, so the mask holds nothing where nothing was painted.
func test_undoing_the_first_stroke_on_an_own_mask_frees_its_chunk() -> void:
    var mask := SaMask.own()
    _doc.mask_target = mask
    _stroke(Vector2(AT), 12.0, HIDE)
    assert_eq(mask.grid_positions().size(), 1, "the stroke allocated one chunk")
    _doc.undo()
    assert_eq(mask.grid_positions().size(), 0, "and the undo took it away")


## A layer's mask is part of the picture, so the selection holds it. The quick
## mask is the selection itself, so the same dab there is not held.
func test_a_dab_on_a_mask_outside_the_selection_changes_nothing() -> void:
    var mask := _doc.active_layer.add_mask()
    _doc.selection.select_rect(Rect2i(300, 300, 100, 100))
    _doc.mask_target = mask
    var paint := _stroke(Vector2(AT), 12.0, HIDE)
    assert_true(paint.is_empty(), "a chunk the selection leaves out is not a target")
    assert_almost_eq(_coverage(mask, AT), 1.0, 1e-6, "so the mask still shows whole there")

    _doc.selection.editing = true
    var quick := _dab(Vector2(AT), 12.0, Color(1.0, 1.0, 1.0, 1.0))
    assert_true(quick.paints_coverage, "the quick mask is coverage too")
    assert_false(quick.is_empty(), "and it paints outside the selection, because it is the selection")
    assert_almost_eq(_texel(_doc.selection.texture_for(Vector2i.ZERO), AT).r, 1.0, 1e-6, "which now selects the dab")
    assert_almost_eq(_coverage(mask, AT), 1.0, 1e-6, "while the layer's mask is left alone")


## The quick mask wins over a mask target while it is on, and is still
## nobody's history.
func test_the_quick_mask_is_still_nobodys_history() -> void:
    _doc.mask_target = _doc.active_layer.add_mask()
    _doc.selection.editing = true
    var steps := _doc.history.step_count()
    _stroke(Vector2(AT), 12.0, Color(1.0, 1.0, 1.0, 1.0))
    assert_eq(_doc.history.step_count(), steps, "a stroke on the quick mask writes no step")
    assert_almost_eq(_coverage(_doc.mask_target, AT), 1.0, 1e-6, "and does not reach the layer's mask")


func test_the_ordinary_target_is_not_coverage() -> void:
    var paint := _dab(Vector2(AT), 12.0, RED)
    assert_false(paint.paints_coverage, "a dab with no mask target paints colour")


func test_the_mask_target_announces_itself() -> void:
    var heard: Array = []
    _doc.mask_target_changed.connect(func(announced: SaMask) -> void: heard.append(announced))
    var mask := _doc.active_layer.add_mask()
    _doc.mask_target = mask
    _doc.mask_target = null
    assert_eq(heard, [mask, null], "every assignment is announced, from the setter")
