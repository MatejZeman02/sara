## Layer > Resample to Document Resolution: a double resolution layer brought down to
## the document's resolution, as one undoable step.
##
## **The same mean the canvas shows.** The composite draws a finer chunk into
## the document's picture by the `resample` kernel of `composite.gmacs`, each
## pixel the mean of the texels under it, weighted by alpha so a transparent
## texel's colour does not bleed into its neighbour. The bake dispatches that
## kernel and nothing else, so the layer at 1.0 looks the same at 100% as it did
## at 2.0, and a second copy of the weighting could never drift from the first.
## A bilinear read through `SaResampleKernel` at the block's centre would be
## the plain mean, which is not what the canvas drew wherever alpha varies.
##
## **One chunk at a time and no stitch.** A double resolution chunk holds
## exactly the 256 by 256 document pixels of its grid position, so every
## destination texel reads a block inside its own source chunk. Every field
## goes through, the mask included, which the compositor also averages this way
## before it scales a pixel's alpha by it.
##
## **Written straight into the new chunk.** The kernel writes every texel of
## the region, so the destination needs no clear first, and there is no copy
## out of a scratch whose transfer would have to be ordered against the
## dispatch.
##
## Undo swaps the chunks and the scale together, the way `SaResample` swaps
## the chunks and the size: either alone is a layer that disagrees with itself.
class_name SaLayerBake
extends RefCounted

## What the undo menu and the Layer menu call this.
const ACTION_NAME := "Resample to Document Resolution"

var _document: SaDocument
var _compute: SaCompute = null


func _init(document: SaDocument) -> void:
    _document = document


## Whether *layer* has anything to bake: it stores paint, and finer than the
## document. Quiet, because the Layer menu asks it on every open.
static func can_bake(layer: SaLayer) -> bool:
    return layer != null and not layer.is_group and not layer.is_generated() and layer.resolution_scale > 1.0


## Bakes *layer* to the document's resolution. True when it happened.
func bake(layer: SaLayer) -> bool:
    if _document == null or not can_bake(layer) or GlobalShaderCompiler.get_rd() == null:
        return false
    layer.resolve_pending()
    if _compute == null:
        _compute = SaCompute.new("composite")
    var before: Dictionary[Vector2i, SaChunk] = layer.chunks.duplicate()
    var after: Dictionary[Vector2i, SaChunk] = {}
    for grid_pos: Vector2i in before:
        var chunk: SaChunk = before[grid_pos]
        if chunk != null:
            after[grid_pos] = _baked(chunk)
    var state: Dictionary[StringName, Variant] = {&"scale": layer.resolution_scale, &"chunks": before}
    _apply(layer, 1.0, after)
    if _document.history != null:
        _document.history.commit(ACTION_NAME, _swap.bind(layer, state), {}, _bytes_held(before), [state])
    return true


## A chunk at 1.0 whose every field is *chunk*'s at the document's resolution.
func _baked(chunk: SaChunk) -> SaChunk:
    var baked := SaChunk.new()
    var side := Vector2i(SaChunk.SIZE, SaChunk.SIZE)
    var region := Rect2i(Vector2i.ZERO, side)
    for field_id: StringName in chunk.fields:
        var source: SaTexture = chunk.fields[field_id]
        if source == null or not source.rid.is_valid():
            continue
        var into := SaTexture.new(side, source.format)
        _compute.use_storage_format(source.format)
        _compute.set_texture(0, into.rid)
        _compute.set_texture(1, source.rid)
        var density := SaDocumentTexels.density_of(source)
        _compute.set_push_constant_float_array(SaCompute.pack_composite_params(Vector2.ZERO, 1.0, null, density, 1.0, region))
        _compute.dispatch_kernel("resample", SaCompute.groups_for(side.x), SaCompute.groups_for(side.y), 1)
        baked.fields[field_id] = into
        if chunk.blanks.has(field_id):
            baked.blanks[field_id] = chunk.blanks[field_id]
    return baked


## Puts *scale* and *chunks* on *layer* and tells everything that draws it.
## Emptied and refilled by key, because `SaLayer.chunks` is a typed dictionary
## and refuses a plain one, the silent no-op `SaResample._apply` records.
func _apply(layer: SaLayer, scale: float, chunks: Dictionary[Vector2i, SaChunk]) -> void:
    layer.resolution_scale = scale
    layer.chunks.clear()
    for grid_pos: Vector2i in chunks:
        layer.chunks[grid_pos] = chunks[grid_pos]
    layer.mark_all_unresolved()
    _document.modified = true
    _document.invalidate_all_allocated_chunks()
    _document.document_changed.emit()


## The undo and the redo, which are one exchange run twice.
func _swap(layer: SaLayer, state: Dictionary[StringName, Variant]) -> void:
    var scale: float = state[&"scale"]
    var chunks: Dictionary[Vector2i, SaChunk] = state[&"chunks"]
    state[&"scale"] = layer.resolution_scale
    state[&"chunks"] = layer.chunks.duplicate()
    _apply(layer, scale, chunks)


## What the step holds, in bytes of VRAM.
static func _bytes_held(chunks: Dictionary[Vector2i, SaChunk]) -> int:
    var total := 0
    for grid_pos: Vector2i in chunks:
        var chunk: SaChunk = chunks[grid_pos]
        if chunk != null:
            total += chunk.byte_size()
    return total
