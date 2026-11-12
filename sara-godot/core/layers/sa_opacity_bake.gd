## The lower layer's opacity written into its paint before a merge composites
## the uppers into it, so the merged layer reads 100 per cent and shows what
## the rows showed.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Krita and Photoshop keep the lower layer's opacity on a merge, so a 40 per
## cent layer merged with a full one above reads 40 per cent and the upper
## paint shows at 40 per cent too, which is not what the rows showed. Sara
## bakes both and reads 100 per cent, so the merge shows what the rows showed.
## The composite
## kernels take a layer's opacity as a factor on its alpha, `fetch_pixels` in
## `composite_blend_ops.gmacs`, for every mode alike, so the bake is that
## factor written into the alpha and the layer's mode is left as it is: the
## lower layer at full opacity with the scaled alpha draws through its mode
## exactly as it drew at part opacity.
##
## Each allocated chunk is copied, the copy's colour cleared and the old
## colour laid onto it by the Normal kernel at the layer's opacity, which over
## nothing is the colour with its alpha times the opacity. The copy's height is
## cleared and the old height added back by the opacity too, which is how the
## relief weighted it. The copies go into the layer and the old chunks into
## the step's pixel state, so undo puts both back, on the GPU throughout.
class_name SaOpacityBake
extends RefCounted

var _document: SaDocument


func _init(document: SaDocument) -> void:
    _document = document


## Writes *lower*'s opacity into its paint and sets it to 1, recording the
## chunks it replaces in *state* unless an earlier part of the step did, and
## the opacity it had in *shape*, which the merge's toggle swaps back on undo.
## *height* adds the old height back weighted. A layer at full opacity, or a
## group, which `SaLayerRefusals` never lets a merge write into, is left alone.
func bake(
    lower: SaLayer, state: Dictionary[Vector2i, Variant], height: SaHeightOps, shape: Dictionary[StringName, Variant]
) -> void:
    var opacity := lower.opacity
    var compositor := _document.compositor
    if opacity >= 1.0 or lower.is_group or compositor == null:
        return
    var spec := SaFieldSpec.find(lower.schema, SaFieldSpec.HEIGHT)
    var written: Dictionary[Vector2i, SaChunk] = {}
    for grid_pos: Vector2i in lower.chunks:
        var chunk: SaChunk = lower.chunks[grid_pos]
        if chunk == null or chunk.albedo() == null:
            continue
        var copy := chunk.duplicate_chunk()
        copy.albedo().clear(SaFieldSpec.NO_PAINT)
        # A density of one reads the source texel for texel, so a chunk at
        # twice the document's resolution is scaled whole.
        compositor.composite_chunk(
            copy.albedo(),
            chunk.albedo(),
            SaLayer.BLEND_MODE.NORMAL,
            opacity,
            Vector2.ZERO,
            _document.color_space,
            _document.blend_reference_white,
            Rect2i(),
            1.0
        )
        var raised := copy.field(SaFieldSpec.HEIGHT)
        if spec != null and raised != null:
            var flat: Color = copy.blanks.get(SaFieldSpec.HEIGHT, SaFieldSpec.NO_PAINT)
            raised.clear(flat)
            height.add(copy, spec, lower, grid_pos, opacity)
        written[grid_pos] = copy
    for grid_pos: Vector2i in written:
        if not state.has(grid_pos):
            state[grid_pos] = lower.chunks.get(grid_pos, null)
        lower.set_chunk(grid_pos, written[grid_pos])
    shape[&"opacity"] = opacity
    lower.opacity = 1.0
