## What a merge writes into the lower layer: the upper layer's paint
## composited in as the canvas draws it, and the lower layer's own filters and
## mask taken off once their work is in its pixels. Whether it may is
## `SaLayerRefusals`.
##
## `SaLayerOps` owns the step around it, the snapshot, the detach of the upper
## layer and the undo, for Merge Down and for Flatten alike, and asks this
## class for the pixels. It is the part of a merge that touches the layers'
## contents rather than the stack, and an adjustment layer's step into the
## paint below it.
class_name SaMergeFold
extends RefCounted

var _document: SaDocument


func _init(document: SaDocument) -> void:
    _document = document


## Blends *upper* into *lower*, chunk by chunk, snapshotting each of *lower*'s
## chunks into *state* the first time it is touched so one snapshot serves the
## whole step. *height* adds the upper layer's height to the lower's before
## the colour goes on.
func composite_into(lower: SaLayer, upper: SaLayer, state: Dictionary[Vector2i, Variant], height: SaHeightOps) -> void:
    if not upper.visible:
        return
    var compositor := _document.compositor
    if compositor == null:
        return
    if upper.is_adjustment():
        _adjust_into(compositor, lower, upper, state)
        return
    if SaLayerStack.clip_base(_document, upper) == lower:
        _clip_into(compositor, lower, upper, state, height)
        return
    var spec := SaFieldSpec.find(lower.schema, SaFieldSpec.HEIGHT)
    # A layer with a live transform goes in as the canvas draws it, its cache.
    var paint := SaLiveTransform.paint_of(upper)
    for grid_pos: Vector2i in paint.chunks:
        var source: SaChunk = paint.chunks[grid_pos]
        if source == null:
            continue
        if not state.has(grid_pos):
            state[grid_pos] = lower.duplicate_chunk(grid_pos)
        var destination := lower.get_or_create_chunk(grid_pos)
        # The filters, then the mask, then the blend, which is the order and
        # the evaluation the compositor draws the layer with.
        # A double resolution layer comes down to the document's resolution
        # first, as the canvas draws it, so its mask meets it texel for texel.
        var shown := compositor.shown(upper, paint, source.albedo(), grid_pos, Rect2i(), paint)
        height.add(destination, spec, upper, grid_pos, upper.opacity)
        compositor.composite_chunk(
            destination.albedo(),
            shown,
            upper.get_blend_mode_name(),
            upper.opacity,
            Vector2.ZERO,
            _document.color_space,
            _document.blend_reference_white
        )
        lower.mark_unresolved(grid_pos)


## *upper*, clipped to *lower*, written into *lower* the way the two showed as
## one group: *upper* laid by its mode and opacity on *lower*'s own colour, and
## the result kept under *lower*'s alpha, at *lower*'s chunks alone, since past
## them *upper* showed nothing. Merged in by its mode over *lower*'s pixels,
## *upper* would land where *lower* is partly there with that much less
## weight, the pale rim the group composite took away.
func _clip_into(
    compositor: SaCompositor, lower: SaLayer, upper: SaLayer, state: Dictionary[Vector2i, Variant], height: SaHeightOps
) -> void:
    var spec := SaFieldSpec.find(lower.schema, SaFieldSpec.HEIGHT)
    var paint := SaLiveTransform.paint_of(upper)
    var whole := SaDocument.WHOLE_CHUNK
    var space := _document.color_space
    var blend_white := _document.blend_reference_white
    for grid_pos: Vector2i in lower.chunks.keys():
        var source: SaChunk = paint.chunks.get(grid_pos, null)
        if lower.chunks[grid_pos] == null:
            continue
        var shown := compositor.shown(upper, paint, source.albedo() if source != null else null, grid_pos, Rect2i(), paint)
        if shown == null:
            continue
        if not state.has(grid_pos):
            state[grid_pos] = lower.duplicate_chunk(grid_pos)
        var destination := lower.get_or_create_chunk(grid_pos)
        height.add(destination, spec, upper, grid_pos, upper.opacity)
        var albedo := destination.albedo()
        var lay_base := func(into: SaTexture) -> void:
            compositor.composite_chunk(into, albedo, SaLayer.BLEND_MODE.NORMAL, 1.0, Vector2.ZERO, space, blend_white, whole)
        var lay_clipped := func(plate: SaTexture) -> void:
            var mode := upper.get_blend_mode_name()
            compositor.composite_chunk(plate, shown, mode, upper.opacity, Vector2.ZERO, space, blend_white, whole)
        var group := compositor.clip_group.plate(compositor, albedo.format, whole, lay_base, lay_clipped)
        compositor.clear_scratch_batch([[albedo, whole]])
        compositor.composite_chunk(albedo, group, SaLayer.BLEND_MODE.NORMAL, 1.0, Vector2.ZERO, space, blend_white, whole)
        lower.mark_unresolved(grid_pos)


## *upper*, an adjustment layer, written into *lower*'s paint alone, its
## records, mask, mode and opacity, the way Krita and Photoshop merge one
## down: what lies under *lower* loses the adjustment. The step runs over each
## of *lower*'s chunks with the chunk as its backdrop, so the paint keeps its
## own alpha, which is what a clipped adjustment layer does to *lower*, the
## layer it sits on, too. *lower* holds its own filters and mask baked in by
## then.
func _adjust_into(compositor: SaCompositor, lower: SaLayer, upper: SaLayer, state: Dictionary[Vector2i, Variant]) -> void:
    var whole := Rect2i(Vector2i.ZERO, Vector2i(SaLayer.CHUNK_SIZE, SaLayer.CHUNK_SIZE))
    if compositor.adjustment.merge_around(compositor, lower, upper, state):
        return
    for grid_pos: Vector2i in lower.chunks.keys():
        if lower.chunks[grid_pos] == null:
            continue
        if not state.has(grid_pos):
            state[grid_pos] = lower.duplicate_chunk(grid_pos)
        var albedo := lower.get_field(grid_pos)
        compositor.adjustment.adjust(
            compositor, albedo, upper, upper.get_blend_mode_name(), upper.opacity, grid_pos, Vector2.ZERO, whole
        )
        lower.mark_unresolved(grid_pos)


## Takes *lower*'s enabled filters off it, once their work is in its pixels,
## and answers each with the place it held, as `[SaAttachedFilter, int]`,
## highest place last so they go back in order. A record switched off changes
## nothing on screen and stays where it is.
func take_filters(lower: SaLayer) -> Array:
    var baked: Array = []
    for at in lower.filters.size():
        var record := lower.filters[at]
        if record != null and record.enabled:
            baked.append([record, at])
    for slot: Array in baked:
        lower.filters.erase(slot[0])
    return baked


## Takes *lower*'s mask off it once its work is in the pixels, and answers the
## schema that carried it for the step to put back, or nothing when the mask is
## off or is a group's. The live chunks are the copies the bake swapped in, so
## the field goes from them and the originals in the step keep theirs.
func take_mask(lower: SaLayer) -> Dictionary[StringName, Variant]:
    if lower.mask == null or not lower.mask.enabled or lower.mask.is_own():
        return {}
    var kept: Dictionary[StringName, Variant] = {&"schema": lower.schema}
    if _document.mask_target == lower.mask:
        _document.mask_target = null
    lower.drop_mask()
    return kept
