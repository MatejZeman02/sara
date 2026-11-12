## Select Opaque: a layer's alpha made the selection, in a `SaSelection.Mode`.
## What a Ctrl click on a layer's thumbnail runs, by the name
## Krita gives it, and what Photoshop does on the same click.
##
## Beside the selection and not in the layers docker, because the docker is one
## caller and the operation is the selection's business. It walks only the
## chunks the layer holds, copies each one's alpha into a fresh mask chunk by
## `select_opaque.gmacs`, and merges the chunks by mode through
## `SaSelection.merge_region`, the way `SaColorRange` merges a range. A chunk the
## layer does not hold is transparent there and so selects nothing, which
## replace and intersect read as unselected and add and subtract leave alone.
##
## One history step, through `SaSelection.change`, which holds the whole
## selection either side and so gives back whether one was active: a painter
## who had nothing selected undoes into everything selected again.
##
## The layer's pixels only. Its mask, its opacity and its filters are not read,
## which is what both programs do: the click asks where the layer holds paint.
class_name SaSelectOpaque
extends RefCounted

## The history step's name, Krita's.
const TITLE := "Select Opaque"

const BINDING_MASK: int = 0
const BINDING_COLOR: int = 1

var _document: SaDocument
var _compute: SaCompute = null


func _init(document: SaDocument) -> void:
    _document = document


## Whether *layer* is one this operation takes: a layer that stores pixels. A
## group composites its members and holds no pixels of its own to read, so it
## is left to the press it always had.
static func takes(layer: SaLayer) -> bool:
    return layer != null and not layer.is_group and not layer.schema.is_empty()


## Makes *layer*'s alpha the selection in *mode* and records one step. Answers
## whether the selection changed: a layer with no paint, a group, and a
## subtract from a selection that holds everything change nothing and record
## nothing.
func select(layer: SaLayer, mode: int) -> bool:
    var selection := _document.selection if _document != null else null
    if selection == null or not takes(layer) or layer.chunks.is_empty():
        return false
    if mode == SaSelection.Mode.SUBTRACT and not selection.active:
        # Everything is selected and nothing holds it, so there is nothing to
        # take the alpha out of, which is what the colour range does too.
        return false
    var region := coverage(layer)
    if region.is_empty():
        return false
    selection.change(TITLE, selection.merge_region.bind(region, mode))
    return true


## *layer*'s alpha as a fresh mask chunk per chunk the layer holds, keyed by
## grid position, and nothing for a chunk it does not.
func coverage(layer: SaLayer) -> Dictionary[Vector2i, SaChunk]:
    var out: Dictionary[Vector2i, SaChunk] = {}
    if not takes(layer):
        return out
    layer.resolve_pending()
    var format: int = layer.schema[0].format
    if _compute == null:
        _compute = SaCompute.new("select_opaque")
    # The colour image's depth rather than the mask's, which the kernel names
    # as r32f itself, the colour range's arrangement.
    _compute.use_storage_format(format)
    var canvas := Rect2i(Vector2i.ZERO, _document.canvas_size)
    for grid_pos: Vector2i in layer.chunks:
        var source := layer.get_field(grid_pos)
        if source == null or source.format != format:
            continue
        var chunk := _document.selection.make_chunk()
        var target := chunk.field(SaSelection.FIELD)
        if target == null:
            continue
        var side := target.size.x
        var local := SaChunkWalk.local_rect(grid_pos, canvas, side)
        if local.size.x <= 0 or local.size.y <= 0:
            continue
        var scale := float(source.size.x) / float(side)
        _compute.set_texture(BINDING_MASK, target.rid)
        _compute.set_texture(BINDING_COLOR, source.rid)
        _compute.set_push_constant_float_array(PackedFloat32Array([float(local.end.x), float(local.end.y), scale, 0.0]))
        _compute.dispatch_kernel("select_opaque", SaCompute.groups_for(local.end.x), SaCompute.groups_for(local.end.y), 1)
        out[grid_pos] = chunk
    return out
