## Every operation on the layer stack is a history step, and a delete is one
## the painter can take back.
##
## Deleting a layer used to be `queue_free`, permanent and silent, and so was
## every other change to the stack: only the three pixel writes registered
## with the history. A mis-clicked delete is exactly the loss the feature audit
## found, and the answer was that a delete with no way back is
## unacceptable whatever it costs.
extends "res://tests/test_framework.gd"

## Chunk snapshots and composites are real textures, so this needs a RenderingDevice.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

## Every document here shares the skeleton's own blend modes, so a merge can
## ask for Multiply and get it rather than the Normal a bare compositor falls
## back to.
var _registries: SaRegistries = null

## Whether the eye was an undo step when the test began.
var _eye_was: bool


## What one chunk snapshot of *doc* weighs in the history: a whole tile at the
## document's own texel depth, asked of the document rather than assumed to be
## sixteen bytes (hard rule 3, sparse chunks).
func _chunk_bytes(doc: SaDocument) -> int:
    return SaChunk.SIZE * SaChunk.SIZE * int(SaFieldSpec.BYTES_PER_TEXEL[doc.color_space.texel_format()])


func before_each() -> void:
    _eye_was = SaSettings.visibility_in_history
    SaSettings.visibility_in_history = false
    _registries = Fixtures.make_registries()


func after_each() -> void:
    SaSettings.visibility_in_history = _eye_was
    _registries = null


func _document() -> Array:
    var easel := SaEasel.create_default(Vector2i(256, 256))
    easel.compositor.set_registry(_registries.blend_modes)
    return [easel, easel.document]


func _texel(layer: SaLayer) -> Color:
    var texture := layer.get_field(Vector2i(0, 0))
    @warning_ignore("static_called_on_instance")
    var image := SaExport.get_texture_image_float(texture)
    return image.get_pixel(0, 0)


func _names(doc: SaDocument) -> Array:
    var names: Array = []
    for layer in SaLayerOps.new(doc).layers():
        names.append(str(layer.name))
    return names


func test_delete_then_undo_brings_the_pixels_back() -> void:
    var pair := _document()
    var easel: SaEasel = pair[0]
    var doc: SaDocument = pair[1]
    var layer := doc.active_layer
    doc.fill_layer(Color(0.2, 0.6, 0.9, 1.0), layer)
    var painted := _texel(layer)
    var paint_bytes := doc.history.total_bytes()

    assert_true(SaLayerOps.new(doc).remove(layer), "The layer is deleted")
    assert_eq(SaLayerOps.new(doc).layers().size(), 1, "and gone from the stack")
    assert_true(is_instance_valid(layer), "but alive inside its history step")
    assert_null(layer.get_parent(), "out of the document")
    assert_eq(doc.history.total_layer_bytes(), _chunk_bytes(doc), "charged to the layer pool")
    assert_eq(doc.history.total_bytes(), paint_bytes, "and not a byte to the paint pool")

    assert_true(doc.undo(), "Undo takes it back")
    assert_eq(SaLayerOps.new(doc).layers().size(), 2, "The stack has two layers again")
    assert_eq(doc.active_layer, layer, "the deleted one is active again")
    assert_almost_eq(_texel(layer).r, painted.r, 1e-6, "and its pixels are exactly what was painted")

    assert_true(doc.redo(), "Redo deletes it again")
    assert_eq(SaLayerOps.new(doc).layers().size(), 1, "and the stack agrees")
    easel.free()


## The pool is the cap. When it overflows the oldest delete goes,
## and with it the layer it kept, which is the only time a deleted layer is
## ever freed.
func test_an_evicted_delete_frees_its_layer() -> void:
    var pair := _document()
    var easel: SaEasel = pair[0]
    var doc: SaDocument = pair[1]
    # Pinned, because the eviction this provokes is deliberate and the corner
    # line added for a painter who did not provoke one is noise in a suite.
    doc.history.pin_budget = true
    doc.history.layer_budget_bytes = _chunk_bytes(doc)
    # A fresh layer holds no chunks, so each is painted first, or
    # there would be nothing for the pool to weigh.
    var first := SaLayerOps.new(doc).add()
    doc.fill_layer(Color(1.0, 0.0, 0.0, 1.0), first)
    var second := SaLayerOps.new(doc).add()
    doc.fill_layer(Color(0.0, 1.0, 0.0, 1.0), second)

    SaLayerOps.new(doc).remove(first)
    assert_true(is_instance_valid(first), "One delete fits the pool")
    SaLayerOps.new(doc).remove(second)
    assert_false(is_instance_valid(first), "A second one pushes the first out, and the first layer is freed with it")
    assert_true(is_instance_valid(second), "while the newest delete is always kept")
    assert_true(doc.history.total_layer_bytes() <= _chunk_bytes(doc), "and the pool stays inside its cap")
    easel.free()


## A painter's condition: every operation through an instance
## that is dropped at once, and every step still undoes and redoes, because the
## step's Callable is what holds the instance.
func test_a_dropped_instance_still_undoes_and_redoes() -> void:
    var pair := _document()
    var easel: SaEasel = pair[0]
    var doc: SaDocument = pair[1]
    var fresh := _names(doc)
    var first := SaLayerOps.new(doc).add()
    doc.fill_layer(Color(1.0, 0.0, 0.0, 1.0), first)
    var copy := SaLayerOps.new(doc).duplicate(first)
    SaLayerOps.new(doc).group_layers([first, copy])
    assert_true(SaLayerOps.new(doc).merge_down(copy), "The copy merges into the layer under it")
    assert_true(SaLayerOps.new(doc).remove(first), "and that layer comes out")
    var after := _names(doc)
    var steps := doc.history.step_count()
    for i in steps:
        doc.undo()
    assert_eq(_names(doc), fresh, "Every step undone is the fresh document")
    for i in steps:
        doc.redo()
    assert_eq(_names(doc), after, "and every step redone is the stack it was")
    easel.free()


## The step a merge down registers, made by an instance nobody else holds.
## A function of its own, so the instance is gone from every local by the time
## the caller looks (a local set to `x = null` can leave the free for later).
func _merge_through_a_dropped_instance(doc: SaDocument, layer: SaLayer) -> WeakRef:
    var ops := SaLayerOps.new(doc)
    ops.merge_down(layer)
    return weakref(ops)


## The same sequence with the history too small for it. The step keeps the
## instance that made it alive and no longer, and an evicted step frees the
## layer its keeper held out of the document.
func test_an_evicted_step_frees_its_instance_and_its_layer() -> void:
    var pair := _document()
    var easel: SaEasel = pair[0]
    var doc: SaDocument = pair[1]
    doc.history.pin_budget = true
    doc.history.layer_budget_bytes = _chunk_bytes(doc)
    var first := SaLayerOps.new(doc).add()
    doc.fill_layer(Color(1.0, 0.0, 0.0, 1.0), first)
    var copy := SaLayerOps.new(doc).duplicate(first)
    SaLayerOps.new(doc).group_layers([first, copy])
    var held := _merge_through_a_dropped_instance(doc, copy)
    assert_true(held.get_ref() != null, "The merge's step holds the instance that made it")
    assert_true(is_instance_valid(copy), "and the merged layer lives on in that step")
    # One chunk fills the layer pool, so the delete pushes the merge out, and
    # everything older goes with it because the two pools share one list.
    assert_true(SaLayerOps.new(doc).remove(first), "A delete that does not fit beside the merge")
    assert_eq(doc.history.step_count(), 1, "evicts every step before it")
    assert_true(held.get_ref() == null, "The evicted step let its instance go")
    assert_false(is_instance_valid(copy), "and the layer its keeper held is freed")
    assert_true(is_instance_valid(first), "while the newest delete keeps its own")
    easel.free()


## A delete is charged to its own pool, so it can never cost a stroke.
func test_a_delete_never_evicts_painting_history() -> void:
    var pair := _document()
    var easel: SaEasel = pair[0]
    var doc: SaDocument = pair[1]
    # Pinned, because the budget follows the document and this test is
    # about the two pools rather than about the depth on top of them.
    doc.history.pin_budget = true
    doc.history.budget_bytes = _chunk_bytes(doc) * 2
    # On the background, which holds its chunk: a first fill of a chunkless
    # layer has nothing to snapshot and weighs nothing.
    var background: SaLayer = SaLayerOps.new(doc).layers()[0]
    doc.fill_layer(Color(0.1, 0.1, 0.1, 1.0), background)
    doc.fill_layer(Color(0.2, 0.2, 0.2, 1.0), background)
    assert_eq(doc.history.step_count(), 2, "Two fills fill the paint budget")

    SaLayerOps.new(doc).add()
    SaLayerOps.new(doc).remove(doc.active_layer)
    assert_eq(doc.history.step_count(), 4, "An add and a delete join them")
    assert_eq(doc.history.total_bytes(), _chunk_bytes(doc) * 2, "and both fills are still held")
    easel.free()


func test_a_move_is_undoable() -> void:
    var pair := _document()
    var easel: SaEasel = pair[0]
    var doc: SaDocument = pair[1]
    assert_eq(_names(doc), ["Background", "Layer 1"], "Bottom first")

    assert_true(SaLayerOps.new(doc).move(doc.active_layer, -1), "Layer 1 moves down")
    assert_eq(_names(doc), ["Layer 1", "Background"], "under the background")
    assert_false(SaLayerOps.new(doc).move(doc.active_layer, -1), "and no further")

    doc.undo()
    assert_eq(_names(doc), ["Background", "Layer 1"], "Undo puts it back")
    doc.redo()
    assert_eq(_names(doc), ["Layer 1", "Background"], "and redo moves it again")
    easel.free()


## A painter's addition: merging a Multiply layer down means the result is the
## product, not the upper layer pasted over the lower with Normal.
func test_merge_down_honours_the_blend_mode() -> void:
    var pair := _document()
    var easel: SaEasel = pair[0]
    var doc: SaDocument = pair[1]
    var background: SaLayer = SaLayerOps.new(doc).layers()[0]
    var upper := doc.active_layer
    doc.fill_layer(Color(0.5, 0.5, 0.5, 1.0), upper)
    SaLayerOps.new(doc).set_blend_mode(upper, SaLayer.BLEND_MODE.MULTIPLY)
    assert_almost_eq(_texel(background).r, 0.5, 1e-6, "The background is mid grey")

    assert_true(SaLayerOps.new(doc).merge_down(upper), "Merge down")
    assert_eq(SaLayerOps.new(doc).layers().size(), 1, "One layer left")
    assert_eq(doc.active_layer, background, "the one that received the merge")
    assert_almost_eq(_texel(background).r, 0.25, 1e-4, "and it holds the product, 0.5 times 0.5")

    assert_true(doc.undo(), "Undo")
    assert_eq(SaLayerOps.new(doc).layers().size(), 2, "brings the merged layer back")
    assert_eq(doc.active_layer, upper, "as the active one")
    assert_almost_eq(_texel(background).r, 0.5, 1e-6, "with the background as it was")
    assert_almost_eq(_texel(upper).r, 0.5, 1e-6, "and the upper layer's pixels intact")
    easel.free()


func test_a_hidden_layer_merges_as_nothing() -> void:
    var pair := _document()
    var easel: SaEasel = pair[0]
    var doc: SaDocument = pair[1]
    var background: SaLayer = SaLayerOps.new(doc).layers()[0]
    var upper := doc.active_layer
    doc.fill_layer(Color(1.0, 0.0, 0.0, 1.0), upper)
    SaLayerOps.new(doc).set_visible(upper, false)

    assert_true(SaLayerOps.new(doc).merge_down(upper), "A hidden layer can still be merged")
    assert_eq(SaLayerOps.new(doc).layers().size(), 1, "and it is gone")
    assert_almost_eq(_texel(background).r, 0.5, 1e-6, "having contributed nothing, the way Krita has it")
    easel.free()


func test_flatten_is_one_step() -> void:
    var pair := _document()
    var easel: SaEasel = pair[0]
    var doc: SaDocument = pair[1]
    var bottom: SaLayer = SaLayerOps.new(doc).layers()[0]
    doc.fill_layer(Color(0.0, 1.0, 0.0, 1.0), doc.active_layer)
    var top := SaLayerOps.new(doc).add()
    doc.fill_layer(Color(0.0, 0.0, 1.0, 0.5), top)
    var before := _names(doc)
    var steps := doc.history.step_count()

    assert_true(SaLayerOps.new(doc).flatten(), "Flatten")
    assert_eq(_names(doc), ["Background"], "leaves the bottom layer")
    assert_eq(doc.history.step_count(), steps + 1, "as one step")
    var flat := _texel(bottom)
    assert_almost_eq(flat.g, 0.5, 1e-4, "holding both layers composited in order")
    assert_almost_eq(flat.b, 0.5, 1e-4, "the half-covered blue over the green")

    doc.undo()
    assert_eq(_names(doc), before, "and one undo restores the whole stack in order")
    assert_almost_eq(_texel(bottom).r, 0.5, 1e-6, "with the bottom's own pixels")
    easel.free()


## A slider announces every pixel it travels. One drag is one change.
func test_an_opacity_drag_is_one_step() -> void:
    var pair := _document()
    var easel: SaEasel = pair[0]
    var doc: SaDocument = pair[1]
    var layer := doc.active_layer
    var steps := doc.history.step_count()
    for value: float in [0.9, 0.8, 0.7, 0.6]:
        SaLayerOps.new(doc).set_opacity(layer, value)
    assert_eq(doc.history.step_count(), steps + 1, "Four slider values, one step")
    assert_eq(doc.undo_redo.get_history_count(), doc.history.step_count(), "and the tally agrees with UndoRedo")

    doc.undo()
    assert_almost_eq(layer.opacity, 1.0, 1e-6, "Undo goes back to before the drag")
    doc.redo()
    assert_almost_eq(layer.opacity, 0.6, 1e-6, "and redo to where it ended")
    easel.free()


func test_every_property_change_is_undoable() -> void:
    SaSettings.visibility_in_history = true
    var pair := _document()
    var easel: SaEasel = pair[0]
    var doc: SaDocument = pair[1]
    var layer := doc.active_layer

    SaLayerOps.new(doc).set_visible(layer, false)
    SaLayerOps.new(doc).set_blend_mode(layer, SaLayer.BLEND_MODE.SCREEN)
    SaLayerOps.new(doc).set_locked(layer, true)
    SaLayerOps.new(doc).set_alpha_locked(layer, true)
    assert_eq(doc.history.step_count(), 4, "Four changes, four steps")

    for i in 4:
        doc.undo()
    assert_true(layer.visible, "Visibility came back")
    assert_eq(str(layer.blend_mode), "normal", "and the blend mode")
    assert_false(layer.is_locked, "and the lock")
    assert_false(layer.alpha_locked, "and the alpha lock")
    easel.free()


## The one operation that snapshots every chunk of every layer twice used to be
## the one operation outside the budget, registered on UndoRedo directly, which
## desynchronised the byte tally for every later commit.
func test_a_conversion_is_on_the_budget() -> void:
    var pair := _document()
    var easel: SaEasel = pair[0]
    var doc: SaDocument = pair[1]
    doc.fill_layer(Color(0.4, 0.6, 0.8, 1.0), doc.active_layer)
    var held := doc.history.total_bytes()

    assert_true(SaColorConversion.new(doc).convert_to(SaColorSpace.acescg()), "Convert")
    # Two layers of one chunk each, held twice: the pixels before and after.
    assert_eq(doc.history.total_bytes(), held + _chunk_bytes(doc) * 4, "charged with both snapshots of every chunk")
    assert_eq(doc.history.step_count(), doc.undo_redo.get_history_count(), "and the tally matches UndoRedo")

    assert_true(SaColorConversion.new(doc).assign(SaColorSpace.srgb()), "Assign")
    assert_eq(doc.history.step_count(), doc.undo_redo.get_history_count(), "is a step the tally knows about too")
    easel.free()


func test_the_tally_survives_a_mixed_session() -> void:
    var pair := _document()
    var easel: SaEasel = pair[0]
    var doc: SaDocument = pair[1]
    SaLayerOps.new(doc).add()
    doc.fill_layer(Color(0.3, 0.3, 0.3, 1.0))
    SaLayerOps.new(doc).move(doc.active_layer, -1)
    SaLayerOps.new(doc).set_opacity(doc.active_layer, 0.5)
    SaLayerOps.new(doc).duplicate(doc.active_layer)
    SaLayerOps.new(doc).remove(doc.active_layer)
    doc.undo()
    doc.undo()
    SaLayerOps.new(doc).merge_down(doc.active_layer)
    assert_eq(doc.history.step_count(), doc.undo_redo.get_history_count(), "Whatever the mix, the two lists agree")
    assert_false(doc.undo_redo.has_redo(), "and the redo stack was dropped by the new step")
    easel.free()


## The dirty set is built by walking the layers that are still there, so
## the grid positions a removed layer covered and nobody else does have to be
## marked before it goes. The note this comes from painted one layer, added an
## empty one above it and deleted the painted one, and the canvas went on
## compositing paint that was no longer in the document.
func test_a_delete_marks_what_the_layer_covered() -> void:
    var pair := _document()
    var easel: SaEasel = pair[0]
    var doc: SaDocument = pair[1]
    var painted: SaLayer = SaLayerOps.new(doc).layers()[0]
    # Active, because that is the case the old code could not save itself in:
    # taking a layer out that nothing was pointing at left the walk stale for
    # one more refresh, and the stale walk marked the right chunks by accident.
    doc.set_active_layer(painted)
    doc.consume_dirty_chunks()

    assert_true(SaLayerOps.new(doc).remove(painted), "The one layer holding chunks is deleted")
    for layer in SaLayerOps.new(doc).layers():
        assert_true(layer.chunks.is_empty(), "Nothing left in the stack holds a chunk")
    var dirty := doc.consume_dirty_chunks()
    assert_true(dirty.has(Vector2i(0, 0)), "so only the delete can have marked the chunk it covered")
    easel.free()


## The other half. A document always has a layer, so deleting the only
## one empties it rather than answering nothing at all.
func test_deleting_the_last_layer_clears_it() -> void:
    var pair := _document()
    var easel: SaEasel = pair[0]
    var doc: SaDocument = pair[1]
    assert_true(SaLayerOps.new(doc).remove(SaLayerOps.new(doc).layers()[1]), "The empty layer goes")
    var last: SaLayer = SaLayerOps.new(doc).layers()[0]
    assert_false(last.chunks.is_empty(), "and the one left holds the grey it was filled with")
    var grey := _texel(last)

    assert_true(SaLayerOps.new(doc).remove(last), "Deleting the last layer is accepted")
    assert_eq(SaLayerOps.new(doc).layers().size(), 1, "the row stays")
    assert_eq(SaLayerOps.new(doc).layers()[0], last, "and it is the same layer")
    assert_true(last.chunks.is_empty(), "with every chunk released")

    assert_true(doc.undo(), "Undo brings the paint back")
    assert_almost_eq(_texel(last).r, grey.r, 1e-6, "exactly as it was")
    assert_eq(SaLayerOps.new(doc).layers().size(), 1, "and the stack never changed size")
    easel.free()
