## What a confirmed tool writes into an ordinary layer's chunks, where a smart
## layer keeps a live transform: a transform bakes when it is confirmed unless
## the layer is smart.
##
## A layer is smart when it carries a live transform (`SaLiveTransform.of`),
## and every other layer is ordinary. The Transform tool's lift already
## resamples an ordinary layer at Enter, so what is here is the Crop tool's
## Enter: the crop the session showed through a live transform with no map is
## written in, the paint outside the box dropped, and the layer is left with no
## transform, as one history step. A smart layer keeps its live crop, which
## `SaLiveTransform.commit` writes.
##
## An ordinary layer that carries a relief has its crop written straight into
## its chunks at Enter, `crop_in_place`: every chunk wholly outside the box is
## dropped and every one the box's edge crosses is copied with each of its
## fields, the height field included, blanked outside. The dim the box draws is
## the preview. A crop written in place rather than drawn live suits a relief,
## because a copy blanked outside the box moves no texel at all.
##
## The step is a swap of chunks alone. The layer has no transform before the
## step and none after it, so the undo puts the chunks back and nothing else,
## which is not what Convert to Ordinary Layer's step does: that one puts the transform
## back with them, `SaLiveTransform.toggled`.
class_name SaTransformBake
extends RefCounted


## Writes the crop *layer* shows through its live transform into its chunks
## and takes the transform off, as one history step named *step*, and answers
## whether it did. *layer* must have had no transform when the session opened.
## False, with the crop still shown, where no device can resample, so the
## caller writes the live step instead.
static func crop_in(document: SaDocument, layer: SaLayer, step: String) -> bool:
    if document == null or layer == null or SaLiveTransform.of(layer) == null:
        return false
    if GlobalShaderCompiler.get_rd() == null:
        return false
    var state: Dictionary[Vector2i, Variant] = {}
    SaLiveTransform.bake_into(document, layer, state)
    document.modified = true
    if document.history != null:
        document.history.commit(step, document.swap_pixels.bind(layer, state), state)
    return true


## Whether the Crop tool crops *layer* of *document* in its chunks at Enter,
## with no live crop shown first: an ordinary layer that carries a relief and
## that nothing but the relief keeps from a live transform. The Crop tool
## reaches this as `SaLiveTransform.IN_CHUNKS`. A smart layer that carries
## a relief keeps its crop live, as any smart layer does.
static func crops_in_place(document: SaDocument, layer: SaLayer) -> bool:
    if layer == null or SaLiveTransform.of(layer) != null or not layer.carries_height():
        return false
    return SaLiveTransform.refusal(document, layer, Basis.IDENTITY).is_empty()


## Crops *layer* to *box*, in document pixels, by writing into its chunks with
## no live transform, as one history step named *step*, and answers whether a
## chunk changed. For a layer [method crops_in_place] says yes to, which is
## drawn where it was painted, so the box is in its own pixels. Each chunk it touches is replaced by a copy and kept in the
## step whole, the way the bake keeps them, so the undo gives every byte back.
static func crop_in_place(document: SaDocument, layer: SaLayer, box: Rect2i, step := SaLiveTransform.CROP_STEP) -> bool:
    if document == null or not box.has_area() or not crops_in_place(document, layer):
        return false
    if GlobalShaderCompiler.get_rd() == null:
        return false
    var blanker := Blanker.new()
    var state: Dictionary[Vector2i, Variant] = {}
    var side := SaLayer.CHUNK_SIZE
    for grid_pos: Vector2i in SaTyped.positions(layer.chunks):
        var chunk: SaChunk = layer.chunks.get(grid_pos, null)
        if chunk == null:
            continue
        var cell := Rect2i(grid_pos * side, Vector2i(side, side))
        var inside := cell.intersection(box)
        if inside == cell:
            continue
        state[grid_pos] = chunk
        if not inside.has_area():
            layer.set_chunk(grid_pos, null)
            continue
        var copy := chunk.duplicate_chunk()
        var scale := float(copy.pixel_size()) / float(side)
        blanker.outside(copy, SaCrop.texels(inside.position - cell.position, scale), SaCrop.texels(inside.size, scale))
        layer.set_chunk(grid_pos, copy)
    if state.is_empty():
        return false
    document.modified = true
    document.invalidate_chunks(state.keys())
    document.update_caches()
    document.document_changed.emit()
    if document.history != null:
        document.history.commit(step, document.swap_pixels.bind(layer, state), state)
    return true


## Sets every field of a chunk to its blank outside one rectangle of it, with
## the `blank` kernel, four strips at most, so the pass is over the box's edge
## and never the whole chunk (hard rule 2).
class Blanker:
    extends RefCounted

    var _compute := SaCompute.new("blank")

    ## Blanks *chunk* outside the rectangle at *from* of *size*, in its own texels.
    func outside(chunk: SaChunk, from: Vector2i, size: Vector2i) -> void:
        var edge := chunk.pixel_size()
        var end := from + size
        var strips: Array[Rect2i] = [
            Rect2i(0, 0, edge, from.y),
            Rect2i(0, end.y, edge, edge - end.y),
            Rect2i(0, from.y, from.x, size.y),
            Rect2i(end.x, from.y, edge - end.x, size.y),
        ]
        for field_id: StringName in chunk.fields:
            var target: SaTexture = chunk.fields[field_id]
            if target == null or not target.rid.is_valid():
                continue
            # The field's own blank, as the crop's overhang takes it: zero is no
            # paint for colour and height alike, and the chunk knows any other.
            var value: Color = chunk.blanks.get(field_id, SaFieldSpec.NO_PAINT)
            for strip: Rect2i in strips:
                if strip.has_area():
                    _blank(target, strip, value)

    func _blank(target: SaTexture, local: Rect2i, value: Color) -> void:
        _compute.use_storage_format(target.format)
        _compute.set_texture(0, target.rid)
        var where := local.position
        var push := PackedFloat32Array([value.r, value.g, value.b, value.a])
        push.append_array(PackedFloat32Array([where.x, where.y, local.size.x, local.size.y]))
        _compute.set_push_constant_float_array(push)
        _compute.dispatch_kernel("blank_region", SaCompute.groups_for(local.size.x), SaCompute.groups_for(local.size.y), 1)
