## One step of the fold composited into a cache chunk, the way the canvas
## composites it: a clipping base through its group, a generated layer, an
## adjustment over the chunk as its backdrop, and a layer through its filters
## and mask. `SaLayerFold` decides which steps a cache holds and where, and
## this draws them, step by step over every chunk.
class_name SaFoldStep
extends RefCounted

var _compositor: SaCompositor
var _color_space: SaColorSpace
var _blend_reference_white: float


func _init(compositor: SaCompositor, document: SaDocument) -> void:
    _compositor = compositor
    _color_space = document.color_space
    _blend_reference_white = document.blend_reference_white


## Composites the steps of *folded* from *from* up to *to* into *cache* at
## *spots*, over what its chunks hold.
##
## Step by step over every chunk rather than chunk by chunk over every step, so
## a step's plain chunks go in one compute list. One list for each step in each
## chunk is hundreds of lists for every click on a row of a deep stack. Each
## chunk still takes the steps in order, since a
## step's list ends before the next step's begins, and so does a fold over
## frames that takes them a few at a time.
func steps(cache: SaLayer, folded: Array[Dictionary], spots: Array[Vector2i], from: int, to: int) -> void:
    var dests: Array[SaTexture] = []
    for grid_pos in spots:
        dests.append(cache.chunks[grid_pos].albedo())
    for step in range(from, to):
        var atom := folded[step]
        var pairs: Array = []
        for i in spots.size():
            step_into(dests[i], atom, spots[i], pairs)
        _compositor.composite_chunk_pairs(
            pairs, SaLayerStack.mode_of(atom), SaLayerStack.opacity_of(atom), _color_space, _blend_reference_white
        )


## Composites one step of a fold into *dest*, the cache's chunk at *grid_pos*.
func chunk_step(dest: SaChunk, atom: Dictionary, grid_pos: Vector2i) -> void:
    step_into(dest.albedo(), atom, grid_pos)


## Composites one step of a fold into *target*, a whole chunk at *grid_pos*,
## a clipping base's through its group. Given *pairs*, a step that shows its
## own chunk as it is adds the pair there for the step's one list instead. What
## the chain, a mask or a finer density makes of a chunk is a scratch the next
## chunk's call writes again, so that is composited at once, as is a clipping
## base, a generated layer and an adjustment.
func step_into(target: SaTexture, atom: Dictionary, grid_pos: Vector2i, pairs: Variant = null) -> void:
    var layer: SaLayer = atom[SaLayerStack.LAYER]
    var space := _color_space
    var blend_white := _blend_reference_white
    var clipped := SaLayerStack.clipped_of(atom)
    if not clipped.is_empty():
        var lay_base := func(into: SaTexture) -> void: step_into(into, SaLayerStack.base_step(atom), grid_pos)
        var lay_clipped := func(plate: SaTexture) -> void:
            for step: Dictionary in clipped:
                step_into(plate, step, grid_pos)
        var mode := SaLayerStack.mode_of(atom)
        var opacity := SaLayerStack.opacity_of(atom)
        _compositor.clip_group.composite(
            _compositor, target, Vector2.ZERO, SaDocument.WHOLE_CHUNK, mode, opacity, space, blend_white, lay_base, lay_clipped
        )
        return
    if layer.is_generated():
        # Inside an isolated group a background reaches only where the group's
        # other layers have chunks, because that is where the group's cache is.
        # At the top level it never folds.
        _compositor.composite_generated_chunk(
            target,
            layer,
            SaLayerStack.mode_of(atom),
            SaLayerStack.opacity_of(atom),
            grid_pos,
            Vector2.ZERO,
            SaDocument.WHOLE_CHUNK,
            space,
            blend_white
        )
        return
    if layer.is_adjustment():
        # The cache chunk holds its run's composite so far, which is the
        # backdrop: the fold placed it so.
        var mode := SaLayerStack.mode_of(atom)
        var opacity := SaLayerStack.opacity_of(atom)
        _compositor.adjustment.adjust(_compositor, target, layer, mode, opacity, grid_pos, Vector2.ZERO, SaDocument.WHOLE_CHUNK)
        return
    # The compositor reads albedo and only albedo. Whether that field was
    # painted or resolved from other fields is the layer's business.
    # The node's filters first, then its mask: what it shows, then where.
    var node := SaLayerStack.node_of(atom, layer)
    # Null where the step holds no chunk and its filters carry nothing in.
    var field := layer.get_field(grid_pos)
    var albedo := _compositor.shown(node, layer, field, grid_pos, SaDocument.WHOLE_CHUNK, layer)
    if albedo == null:
        return
    if pairs != null and albedo == field and albedo.format == target.format:
        var listed: Array = pairs
        listed.append([target, albedo])
        return
    _compositor.composite_chunk(
        target, albedo, SaLayerStack.mode_of(atom), SaLayerStack.opacity_of(atom), Vector2.ZERO, space, blend_white
    )
