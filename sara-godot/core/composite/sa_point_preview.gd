## The point pass previewed on a document's active layer: what the compositor
## reads at composite time while a dialog's Preview box is ticked, and never
## writes to a chunk. Apply then walks the same record as one history step, and
## Cancel drops this.
##
## It names no filter. Sara's own Filter menu and a module's point filter hand it the
## same [SaPointPass], so the compositor holds one feature's kernel no more than
## it holds another's.
##
## Keyed by document because one compositor serves more than one easel, and a
## preview on the painting must not reach the info docker's scratchpad.
class_name SaPointPreview
extends RefCounted

## Document instance id -> the SaPointPass previewed on it.
var _passes: Dictionary[int, SaPointPass] = {}
## Document instance id -> how many times a whole-node pass previewed on it is
## halved while a control drags, absent for the exact pass.
var _halvings: Dictionary[int, int] = {}

## Where the active layer's chunk goes through the kernel before the
## composite reads it. One, reused, so a previewed chunk is a chain like a
## clipped one and goes through `composite_chunk` one at a time.
var _scratch: SaTexture = null
## The selection enlarged to a finer chunk's side, and the frame it was made
## in: made anew each frame, since a selection changes in place.
var _masks := SaFilterDensity.Masks.new()
var _masks_frame: int = -1
## What stands for a chunk the active layer does not hold where a previewed
## neighbourhood pass writes, at the layer's format and side, cleared once by a
## dispatch when it is made and never written after, see [method _ground].
var _stand_in: SaTexture = null
## [method reached] for the pass previewed on the active layer, and the frame,
## pass, layer and count of chunks it was found for. Every position the walk
## visits asks, and a lap over the layer's chunks per position is a lap too many.
var _landed: Dictionary[Vector2i, bool] = {}
var _landed_for: Array = []


## Previews *recorded* on *document*'s active layer from the next composite on.
## The caller marks dirty what [method reached] answered before and answers
## after, this only remembers.
##
## *halved* above 0 is a draft while a control drags: a whole-node pass whose
## kernel takes a `block` is drawn with a fold a square 2^halved texels on a
## side, which at a zoom that shows that square as a pixel or less is the
## screen's resolution. The caller sets it again at 0 once the drag stops, and
## Apply never reads it.
func set_pass(document: SaDocument, recorded: SaPointPass, halved: int = 0) -> void:
    if document == null or recorded == null:
        return
    _passes[document.get_instance_id()] = recorded
    if halved > 0:
        _halvings[document.get_instance_id()] = halved
    else:
        _halvings.erase(document.get_instance_id())


func clear(document: SaDocument) -> void:
    if document != null:
        _passes.erase(document.get_instance_id())
        _halvings.erase(document.get_instance_id())


## How many times the pass previewed on *document* is halved, 0 when it is
## drawn exact or nothing is previewed.
func halvings(document: SaDocument) -> int:
    return _halvings.get(document.get_instance_id(), 0) if document != null else 0


## What is previewed on *document*, or null.
func for_document(document: SaDocument) -> SaPointPass:
    if document == null:
        return null
    return _passes.get(document.get_instance_id(), null)


## *source*, *layer*'s chunk at *grid_pos*, as it shows while a pass is
## previewed on *document*: run through the pass over *region* when *layer* is
## the active layer and the selection reaches the chunk, and as it is
## otherwise. On the layer's own pixels and before its records, which is what
## Apply will rewrite.
##
## The walk draws the active layer through this, and an effect layer reads its
## input through it, so a blur previewed on a photograph reaches the
## kaleidoscope that reads the photograph before Apply, and Cancel, which
## clears the pass, puts the sharp one back.
##
## A null *source*, a position the layer holds no chunk at, is drawn when a
## neighbourhood pass writes there, as [method reached] answers: a wrap's paint
## moved onto empty ground, or a blur's spill past the layer's edge, which Apply
## allocates and writes. It stays null everywhere else.
func drawn(
    compositor: SaCompositor, document: SaDocument, layer: SaLayer, source: SaTexture, grid_pos: Vector2i, region: Rect2i
) -> SaTexture:
    var recorded := for_document(document)
    if recorded == null or layer == null or layer != document.active_layer:
        return source
    var mask := document.selection.texture_for(grid_pos)
    if mask == null:
        return source
    var stood := source if source != null else _ground(compositor, document, layer, recorded, grid_pos)
    if stood == null:
        return null
    var compute := compositor.get_compute(recorded.shader)
    if recorded is SaNeighbourhoodPass:
        var gather := recorded as SaNeighbourhoodPass
        return compositor.filter_chain.previewed(gather, compute, layer, stood, grid_pos, region, mask, halvings(document))
    return chunk(compute, source, mask, region, recorded, grid_pos)


## Every position the pass previewed on *document* draws its active layer at,
## as a set: the chunks the layer holds, and past them where a neighbourhood
## pass writes, the ring a blur's halo spills into and where a pass that reads
## the whole node lands, a wrap's paint moved round the canvas. The held chunks
## alone while nothing is previewed. Through
## [method SaFilterApply.neighbourhood_reach], what Apply allocates and writes,
## so the preview draws where Apply writes, and the walk visits these and a
## dialog redraws them.
func reached(document: SaDocument) -> Dictionary[Vector2i, bool]:
    var layer := document.active_layer if document != null else null
    if layer == null:
        return {}
    var held := SaTyped.positions(layer.chunks)
    var gather := for_document(document) as SaNeighbourhoodPass
    if gather != null:
        for grid_pos: Vector2i in SaFilterApply.neighbourhood_reach(document, layer, gather):
            held[grid_pos] = true
    return held


## What stands for *layer*'s chunk at *grid_pos*, where it holds none, when
## *recorded* is a neighbourhood pass that writes there, and null otherwise: a
## chunk of the layer's format and side that reads as transparent, as the
## position reads to Apply.
##
## A pass with a radius reads it as the chunk its halo is gathered round. A
## whole-node kernel reads only the node gathered once, where this position
## holds nothing either. It is cleared through `clear.gmacs` and not
## `texture_clear`, which is a transfer the pass would not wait for, and
## nothing writes it after. A layer finer than the
## document answers null for a whole-node pass, since Apply refuses one there.
func _ground(
    compositor: SaCompositor, document: SaDocument, layer: SaLayer, recorded: SaPointPass, grid_pos: Vector2i
) -> SaTexture:
    var gather := recorded as SaNeighbourhoodPass
    var side := SaFilterDensity.side_of(layer)
    if gather == null or (gather.whole() and side != SaChunk.SIZE):
        return null
    var key := [Engine.get_process_frames(), gather.get_instance_id(), layer.get_instance_id(), layer.chunks.size()]
    if key != _landed_for:
        _landed = reached(document)
        _landed_for = key
    if not _landed.has(grid_pos):
        return null
    var spec := SaFieldSpec.find(layer.schema, SaFieldSpec.ALBEDO)
    var format := spec.format if spec != null else RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
    if _stand_in == null or _stand_in.format != format or _stand_in.size.x != side:
        _stand_in = SaTexture.new(Vector2i(side, side), format)
        var clearer := compositor.get_compute("clear")
        clearer.use_storage_format(format)
        clearer.set_texture(0, _stand_in.rid)
        clearer.set_push_constant_float_array(PackedFloat32Array([0.0, 0.0, 0.0, 0.0, side, side, 0.0, 0.0]))
        clearer.dispatch_kernel("clear_chunk", SaCompute.groups_for(side), SaCompute.groups_for(side), 1)
    return _stand_in


## *source*'s *region* run through *recorded* on *compute*, masked by *mask*,
## in the scratch. The copy and the dispatches both cover the region alone, so a
## drag over a large document costs its dirty rectangles and nothing more (hard
## rule 2), and the chunk itself is never written.
##
## *region* is in document pixels and *mask* at the document's resolution. A
## chunk finer than that, 512 texels on a layer at 2.0, is run over the
## region's texels with the mask enlarged to its side, so each texel is masked
## by the pixel it lies in, as Apply masks it.
##
## *grid_pos* is the chunk's place in the grid, and the kernel is handed its
## document corner, as Apply hands it, so a pattern computed in document
## pixels runs across a seam instead of repeating per chunk.
func chunk(
    compute: SaCompute, source: SaTexture, mask: SaTexture, region: Rect2i, recorded: SaPointPass, grid_pos: Vector2i
) -> SaTexture:
    if _scratch == null or _scratch.format != source.format or _scratch.size != source.size:
        _scratch = SaTexture.new(source.size, source.format)
    var side := source.size.x
    var covered := region if region.size.x > 0 else Rect2i(Vector2i.ZERO, source.size)
    if side != SaChunk.SIZE:
        covered = Rect2i(SaFilterDensity.in_texels(covered.position, side), SaFilterDensity.in_texels(covered.size, side))
        covered = covered.intersection(Rect2i(Vector2i.ZERO, source.size))
        mask = _at_side(mask, side)
    var from := Vector3(covered.position.x, covered.position.y, 0.0)
    var extent := Vector3(covered.size.x, covered.size.y, 1.0)
    GlobalShaderCompiler.get_rd().texture_copy(source.rid, _scratch.rid, from, from, extent, 0, 0, 0, 0)
    compute.use_storage_format(source.format)
    compute.set_texture(0, _scratch.rid)
    compute.set_texture(SaSelection.BINDING, mask.rid)
    recorded.bind(compute)
    # In the filter context's bounded pieces, four at twice the density.
    SaFilterContext.run_point_in_submits(compute, recorded, covered, grid_pos * SaChunk.SIZE)
    return _scratch


## *mask* enlarged to *side*, once a frame.
func _at_side(mask: SaTexture, side: int) -> SaTexture:
    var frame := Engine.get_process_frames()
    if frame != _masks_frame:
        _masks = SaFilterDensity.Masks.new()
        _masks_frame = frame
    return _masks.at(mask, side)
