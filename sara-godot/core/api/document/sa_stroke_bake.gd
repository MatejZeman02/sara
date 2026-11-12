## A stroke's bake: the buffer folded into the layer it was painted on as one
## history step, and the wash eraser's lowering of the height under it while
## it is painted.
##
## The document holds one and keeps the stroke's buffer, its opacity and its
## transaction, which the composite and the tools read while the stroke runs.
## This class holds the one piece of a stroke nobody else reads, the lowering,
## and the commit that spends everything at the release.
class_name SaStrokeBake
extends RefCounted

## A wash eraser's starts, which lower the height under each region it lands
## on, or null for every other stroke.
var _lowering: SaStrokeHeights = null


## Starts a stroke on *layer* whose buffer composites by *buffer_mode*: only a
## wash eraser, an ERASE buffer, lowers the height under it.
func start(buffer_mode: StringName, layer: SaLayer) -> void:
    _lowering = SaStrokeHeights.new(null, layer) if buffer_mode == SaLayer.BLEND_MODE.ERASE else null


## Lowers the height under *regions* of *document*'s stroke buffer as they are
## marked dirty, when the stroke is a wash eraser's.
func lower_under(document: SaDocument, regions: Dictionary[Vector2i, Rect2i]) -> void:
    if _lowering != null:
        _lowering.lower_under(document.stroke_layer, regions, document.stroke_opacity, document.stroke_transaction.capture_before)


## Bakes *document*'s stroke buffer into its active layer, or a mask stroke
## into its mask's own step, and records the history. *compositor* answers the
## document's compositor, asked only when a buffer is baked, so a mask stroke
## on a document with none still commits.
func commit(document: SaDocument, compositor: Callable, override_opacity: float) -> void:
    var transaction := document.stroke_transaction
    # A stroke on a mask painted straight in and was snapshotted as it went,
    # into whichever store the mask keeps, so its step is the mask's own. Asked
    # before the layers, because a group's mask needs no active layer.
    var mask: SaMask = transaction.closing()
    if mask != null:
        var mask_undo_data: Dictionary[Vector2i, Variant] = transaction.before_chunks.duplicate()
        transaction.reset()
        document.stroke_opacity = 1.0
        if not mask_undo_data.is_empty():
            mask.record_step(document, "Mask Stroke", mask_undo_data)
            document.modified = true
            document.mask_moved(mask, mask_undo_data.keys())
        return

    assert(document.stroke_layer != null, "document.stroke_layer cannot be null during commit")
    assert(document.active_layer != null, "document.active_layer cannot be null during commit")
    if document.stroke_layer == null or document.active_layer == null:
        return

    var step_name := "Erase Stroke" if transaction.erasing else "Brush Stroke"
    if transaction.direct_paint:
        var direct_undo_data: Dictionary[Vector2i, Variant] = transaction.before_chunks.duplicate()
        document.record_pixel_step(step_name, document.active_layer, direct_undo_data)
        var shown := transaction.shown(direct_undo_data.keys(), document.active_layer)
        document.invalidate_chunk_regions(shown, document.active_layer)
        transaction.reset()
        document.stroke_opacity = 1.0
        document.modified = true
        document.document_changed.emit()
        return

    if document.stroke_layer.chunks.is_empty():
        return

    var final_opacity := override_opacity if override_opacity >= 0.0 else document.stroke_opacity
    # Erase and alpha lock only ever change a pixel that already carries paint,
    # so a chunk the active layer does not have is a chunk they would leave
    # empty. Allocating one there would put an all-transparent 256 by 256 tile
    # in a sparse layer for the rest of the session, which is hard rule 3 read
    # backwards: chunks live where paint is.
    var buffer_mode := document.stroke_layer.blend_mode
    var keeps_to_existing: bool = buffer_mode == SaLayer.BLEND_MODE.ERASE or buffer_mode == SaLayer.BLEND_MODE.ALPHA_LOCK

    # Gather Undo state (before modifying the layer)
    var undo_data: Dictionary[Vector2i, Variant] = {}
    for grid_pos: Vector2i in document.stroke_layer.chunks:
        if keeps_to_existing and not document.active_layer.chunks.has(grid_pos):
            continue
        transaction.capture_before(document.active_layer, grid_pos)
        undo_data[grid_pos] = transaction.before_chunks[grid_pos]

    # Bake the stroke
    var stroke_compositor: SaCompositor = compositor.call()

    # Iterate only through the chunks that were drawn on during the stroke. Every
    # pair is gathered first and baked under one compute list, because a list per
    # chunk cost a `compute_list_end()` barrier per chunk and the bake's GPU time
    # followed the chunk count rather than the stroke's length. Each stroke chunk
    # writes its own destination and none reads another's, so one list is safe.
    var pairs: Array = []
    for grid_pos: Vector2i in document.stroke_layer.chunks:
        if keeps_to_existing and not document.active_layer.chunks.has(grid_pos):
            continue
        var stroke_chunk: SaChunk = document.stroke_layer.chunks[grid_pos]

        # Ensure the active layer has a chunk at this exact position (allows drawing out of bounds!)
        var target_chunk := document.active_layer.get_or_create_chunk(grid_pos)
        pairs.append([target_chunk.field(SaPaintedField.of(document.active_layer)), stroke_chunk.albedo()])

    SaGpuTiming.category_begin("commit")
    stroke_compositor.composite_chunk_pairs(pairs, buffer_mode, final_opacity, document.color_space, 1.0, transaction.stroke_seed)
    SaGpuTiming.category_end("commit", {"chunks": pairs.size()})
    # A wash eraser's lowering pass at commit catches a dab no region reported, so its tiles show whole.
    if _lowering != null:
        var capture := transaction.capture_before
        _lowering.lower_under(document.stroke_layer, transaction.painted_regions, final_opacity, capture, true)
        transaction.painted_regions.clear()
    _lowering = null

    # No "after" snapshot. The layer already holds that state, and the swap picks
    # it up on the way past if an undo ever happens.
    #
    # An empty dictionary is only reachable through the branch above, where an
    # eraser swept space the layer has no chunks in and so changed nothing. A
    # history step for that is a row a painter has to undo past to reach a real
    # one, so it is not written. An ordinary stroke always has an entry here,
    # because every chunk it buffered becomes one.
    if not undo_data.is_empty():
        document.record_pixel_step(step_name, document.active_layer, undo_data)

    document.stroke_layer.chunks.clear()
    document.stroke_layer.blend_mode = SaLayer.BLEND_MODE.NORMAL
    document.invalidate_chunk_regions(transaction.shown(undo_data.keys(), document.active_layer), document.active_layer)
    transaction.reset()
    document.stroke_opacity = 1.0
    document.modified = true
    document.document_changed.emit()
