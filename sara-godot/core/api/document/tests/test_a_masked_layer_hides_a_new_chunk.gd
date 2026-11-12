## A layer's mask hides a new chunk where it hid the empty canvas.
##
## A layer's mask is a field of the layer's chunks, so a chunk the layer did
## not hold when the mask was made has no coverage until a stroke allocates it.
## It opened at one, shown, whatever the mask read there before. The mask's rest
## is what the position read, and a new chunk now opens its field at that rest.
## Every texel is read back from VRAM, because a field cleared to the wrong
## value is a plausible picture and not an error.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const PaintKernel = preload("res://tests/fixtures/paint_kernel.gd")

const RED := Color(1.0, 0.0, 0.0, 1.0)

## Inside the chunk the layer holds before the mask, and inside one it does not.
const HELD := Vector2i(100, 100)
const NEW := Vector2i(400, 400)

var _easel: SaEasel = null
var _doc: SaDocument = null
var _layer: SaLayer = null


func before_each() -> void:
    _easel = SaEasel.create_default(Vector2i(512, 512))
    _doc = _easel.document
    _layer = _doc.active_layer
    _stroke(Vector2(HELD))
    _doc.undo_redo.clear_history()


func after_each() -> void:
    _easel.free()
    _easel = null
    _doc = null
    _layer = null


func _grid(at: Vector2i) -> Vector2i:
    var size := SaChunk.SIZE
    @warning_ignore("integer_division")
    return Vector2i(at.x / size, at.y / size)


## The mask field of the layer's chunk at a document pixel, or -1 where the
## layer holds no chunk there. The layer under test unless another is named.
func _field(at: Vector2i, layer: SaLayer = null) -> float:
    var texture := (layer if layer != null else _layer).get_field(_grid(at), SaFieldSpec.MASK)
    if texture == null:
        return -1.0
    var local := at - _grid(at) * SaChunk.SIZE
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return SaFieldSpec.decode_texel(bytes, texture.format, local.y * texture.size.x + local.x).r


## One hard red dab onto the active layer, as one stroke.
func _stroke(pos: Vector2) -> void:
    var compute := PaintKernel.compute()
    var region := Rect2(pos.x - 12.0, pos.y - 12.0, 24.0, 24.0)
    _doc.begin_stroke(1.0, SaLayer.BLEND_MODE.NORMAL)
    var paint := SaPaintContext.for_region(_doc, region, false)
    paint.dispatch_batch(
        compute,
        "paint",
        func(target: SaPaintContext.Target) -> void:
            compute.set_texture(0, target.texture.rid)
            compute.set_push_constant_float_array(
                PaintKernel.pack_params(paint.local_point(target, pos), target.render_offset, RED, 12.0, 1.0, 1.0, 1.0)
            )
    )
    paint.commit_invalidation()
    _doc.commit_stroke()


func test_a_mask_from_a_selection_hides_a_chunk_painted_after_it() -> void:
    assert_eq(_layer.chunks.size(), 1, "the layer holds one chunk")
    assert_false(_layer.chunks.has(_grid(NEW)), "and not the one the second dab lands in")
    _doc.selection.select_rect(Rect2i(Vector2i.ZERO, Vector2i(SaChunk.SIZE, SaChunk.SIZE)))
    assert_true(SaMaskOps.new(_doc).add_from_selection(_layer), "a mask from a selection over the held chunk")
    _doc.selection.deselect()
    assert_almost_eq(_layer.mask.rest, 0.0, 1e-6, "the mask rests at zero outside the selection")
    assert_almost_eq(_field(HELD), 1.0, 1e-6, "the held chunk shows where it was selected")

    _stroke(Vector2(NEW))
    assert_true(_layer.chunks.has(_grid(NEW)), "the dab allocated a chunk")
    assert_almost_eq(_field(NEW), 0.0, 1e-6, "and the new chunk's mask hides it, as the empty canvas was hidden")

    _doc.undo_redo.undo()
    _doc.undo_redo.undo()
    assert_null(_layer.mask, "undo takes the mask away")
    _doc.undo_redo.redo()
    assert_almost_eq(_layer.mask.rest, 0.0, 1e-6, "redo gives the rest of zero back")
    _doc.undo_redo.redo()
    assert_almost_eq(_field(NEW), 0.0, 1e-6, "and the dab redone lands hidden")


func test_an_inverted_mask_hides_a_chunk_painted_after_it() -> void:
    var ops := SaMaskOps.new(_doc)
    assert_true(ops.add(_layer), "a mask that hides nothing")
    assert_almost_eq(_layer.mask.rest, 1.0, 1e-6, "rests at one")
    assert_true(ops.invert(_layer), "the invert runs")
    assert_almost_eq(_layer.mask.rest, 0.0, 1e-6, "and flips the rest with the held chunks")
    assert_almost_eq(_field(HELD), 0.0, 1e-6, "the held chunk is hidden")

    _stroke(Vector2(NEW))
    assert_almost_eq(_field(NEW), 0.0, 1e-6, "and a chunk painted after it is hidden too")

    _doc.undo_redo.undo()
    _doc.undo_redo.undo()
    assert_almost_eq(_layer.mask.rest, 1.0, 1e-6, "undo gives the invert's rest of one back")
    assert_almost_eq(_field(HELD), 1.0, 1e-6, "and the held chunk shown")
    _stroke(Vector2(NEW))
    assert_almost_eq(_field(NEW), 1.0, 1e-6, "so a chunk painted then opens shown")


## A duplicate's mask rests where the original's does, and
## undo and redo of the duplicate keep it there.
func test_a_duplicate_of_a_mask_from_a_selection_hides_a_new_chunk() -> void:
    _doc.selection.select_rect(Rect2i(Vector2i.ZERO, Vector2i(SaChunk.SIZE, SaChunk.SIZE)))
    assert_true(SaMaskOps.new(_doc).add_from_selection(_layer), "a mask from a selection over the held chunk")
    _doc.selection.deselect()
    var copy := SaLayerOps.new(_doc).duplicate(_layer)
    assert_not_null(copy, "the layer duplicates")
    assert_not_null(copy.mask, "with a mask")
    assert_almost_eq(copy.mask.rest, 0.0, 1e-6, "which rests at zero like the original's")
    assert_eq(_doc.active_layer, copy, "the copy is the layer painted on")

    _stroke(Vector2(NEW))
    assert_true(copy.chunks.has(_grid(NEW)), "the dab allocated a chunk on the copy")
    assert_almost_eq(_field(NEW, copy), 0.0, 1e-6, "and the copy's mask hides it, as the original's would")

    _doc.undo_redo.undo()
    _doc.undo_redo.undo()
    assert_false(copy.is_inside_tree(), "undo takes the copy away")
    _doc.undo_redo.redo()
    assert_almost_eq(copy.mask.rest, 0.0, 1e-6, "redo gives the copy back resting at zero")
    _doc.undo_redo.redo()
    assert_almost_eq(_field(NEW, copy), 0.0, 1e-6, "and the dab redone lands hidden")
