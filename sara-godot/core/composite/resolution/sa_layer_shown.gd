## What a layer shows of one chunk: its node's filters, then its mask, then
## its clip, each through a scratch this holds. A class of its own with the
## scratches it owns, because the compositor holds two of them and picks
## one a walk.
##
## The flat one serves the output and every caller outside a walk, the fold,
## the exports and the bakes. A chunk finer than the document comes down to
## the document's resolution before its mask and its clip, each pixel the mean
## of the texels under it, which is what the output's composite draws anyway.
##
## The fine one serves a walk into a display chunk of `SaDetailView`, where
## nothing comes down: a filtered chunk stays at the density the filter ran at, a
## mask's coverage and a clip base's alpha are read at their own density, and the
## scratch a mask or a clip writes is as fine as the finer of its two inputs. The
## kernels read each input at the texel under the scratch's own, so a coverage at
## 1.0 under a chunk at 2.0 covers a two by two block, the way the display
## magnifies a layer at 1.0.
##
## Each scratch is one, reused, so its answer is composited before the next
## call: a masked or a clipped chunk is a chain, and goes through
## `SaCompositor.composite_chunk` one at a time rather than through a batch.
class_name SaLayerShown
extends RefCounted

## The kernels this opens, named where the opener scan finds them.
const MASK_SHADER := "mask"
const CLIP_SHADER := "clip"

## Whether nothing comes down to the document's resolution, the display
## chunk's walk.
var _fine: bool = false
## The compositor's filter chain, which runs a node's filters.
var _filter_chain: SaFilterChain = null
## `SaCompositor.get_compute`, so the kernels are compiled once for both.
var _compute: Callable
## Where a clipped chunk goes after its mask and before its composite.
var _clip_scratch: SaTexture = null
## Where a masked chunk goes. Its own texture rather than `_clip_scratch`,
## because a layer that is masked and clipped is a chain: the mask writes this
## one, the clip reads it and writes the other.
var _mask_scratch: SaTexture = null
## Where a clip base's alpha goes after the base's own mask, so a layer clipped
## to a masked base shows only where the base shows. A third texture, because
## the clip reads it and the masked source at once.
var _clip_alpha_scratch: SaTexture = null
## Where a generated clip base is evaluated, which stores no chunk to read its
## alpha from. Its own texture rather than the compositor's
## generated scratch, because a generated layer clipped to it is still in that
## scratch when its clip reads this.
var _base_generated: SaTexture = null
## A finer chunk at the document's resolution, for the flat one alone: the
## source shown, a clip base, and a mask's coverage.
var _texels := SaDocumentTexels.new()
var _base_texels := SaDocumentTexels.new()
var _mask_texels := SaDocumentTexels.new()


func _init(fine: bool, filter_chain: SaFilterChain, compute: Callable) -> void:
    _fine = fine
    _filter_chain = filter_chain
    _compute = compute


## What *layer* shows of *source* at *grid_pos*: *node*'s filters over it, at a
## finer layer's own density, then the layer's mask. *node* is
## the layer, or the group a cache stands for, and *neighbours* is what
## `SaFilterChain.filtered` takes. Null where nothing shows: no source, and no
## paint beside it for a filter's halo to carry in.
func shown(
    node: SaLayer, layer: SaLayer, source: SaTexture, grid_pos: Vector2i, region: Rect2i, neighbours: SaLayer = null
) -> SaTexture:
    var answer := _filter_chain.filtered(node, source, grid_pos, region, neighbours)
    if not _fine:
        answer = _texels.of(answer, region)
    return masked(layer, answer, grid_pos, region) if answer != null else null


## *source*, *layer*'s chunk at *grid_pos* or what the chain made of it, hidden
## by the layer's mask when it has coverage there, and as it is when it has none.
func masked(layer: SaLayer, source: SaTexture, grid_pos: Vector2i, region: Rect2i) -> SaTexture:
    var coverage := SaCompositor.coverage_at(layer, grid_pos)
    if coverage == null:
        return source
    return mask_chunk(source, coverage, region)


## *source* with its alpha multiplied by *mask*'s coverage over *region*.
func mask_chunk(source: SaTexture, mask: SaTexture, region: Rect2i) -> SaTexture:
    var coverage := mask if _fine else _mask_texels.of(mask, region)
    _mask_scratch = _into(_mask_scratch, MASK_SHADER, "mask_chunk", source, coverage, region)
    return _mask_scratch


## *source* with its alpha multiplied by *mask*'s, over *region*. What a layer
## clipped to the one below reads as.
func clip_chunk(source: SaTexture, mask: SaTexture, region: Rect2i) -> SaTexture:
    _clip_scratch = _into(_clip_scratch, CLIP_SHADER, "clip_chunk", source, mask, region)
    return _clip_scratch


## What a layer clipped to *base* reads its alpha from at *grid_pos*: *drawn*,
## the base's chunk there as the caller draws it, with the base's own mask
## applied, so the clip follows what the base shows rather than what it
## stores. A generated base stores no chunk and gives what its kernel makes of
## the chunk, over *region* alone. Null where a base that stores holds no
## chunk, which is nothing to show.
func clip_alpha(base: SaLayer, drawn: SaTexture, grid_pos: Vector2i, region: Rect2i) -> SaTexture:
    var alpha := _generated(base, grid_pos, region) if base.is_generated() else drawn
    if not _fine:
        alpha = _base_texels.of(alpha, region)
    if alpha == null:
        return null
    var coverage := SaCompositor.coverage_at(base, grid_pos)
    if coverage == null:
        return alpha
    var mask := coverage if _fine else _mask_texels.of(coverage, region)
    _clip_alpha_scratch = _into(_clip_alpha_scratch, MASK_SHADER, "mask_chunk", alpha, mask, region)
    return _clip_alpha_scratch


## *base*'s kernel over *region* of the chunk at *grid_pos*, in the base's own
## albedo format, which is the depth every chunk of the document shares. At the
## document's resolution, so the fine one's clip reads it the way it reads a
## base at 1.0.
func _generated(base: SaLayer, grid_pos: Vector2i, region: Rect2i) -> SaTexture:
    var side := Vector2i(SaLayer.CHUNK_SIZE, SaLayer.CHUNK_SIZE)
    var format: int = base.schema[0].format
    if _base_generated == null or _base_generated.format != format:
        _base_generated = SaTexture.new(side, format)
    var covered := region if region.size.x > 0 else Rect2i(Vector2i.ZERO, side)
    var compute: SaCompute = _compute.call(base.generator)
    compute.use_storage_format(format)
    compute.set_texture(0, _base_generated.rid)
    SaGeneratedLayer.bind_params(compute, base, Vector2(grid_pos * SaLayer.CHUNK_SIZE), covered)
    compute.dispatch_kernel("generate", SaCompute.groups_for(covered.size.x), SaCompute.groups_for(covered.size.y), 1)
    return _base_generated


## Dispatches *kernel* of *shader* from *source* and *mask* into *scratch*
## over *region*, in document pixels, allocating it first when it is missing or
## at another format or size, and answers it. The scratch is as fine as the
## finer of the two, which in the flat one is always *source*, so *region*
## there is in its texels already and the dispatch is a plain one.
func _into(scratch: SaTexture, shader: String, kernel: String, source: SaTexture, mask: SaTexture, region: Rect2i) -> SaTexture:
    var side := source.size if source.size.x >= mask.size.x else mask.size
    if scratch == null or scratch.format != source.format or scratch.size != side:
        scratch = SaTexture.new(side, source.format)
    var density := SaDocumentTexels.density_of(scratch)
    var covered := Rect2i(Vector2i.ZERO, side)
    if region.size.x > 0:
        covered = Rect2i(Vector2i(Vector2(region.position) * density), Vector2i(Vector2(region.size) * density))
    var compute: SaCompute = _compute.call(shader)
    compute.use_storage_format(source.format)
    compute.set_texture(0, scratch.rid)
    compute.set_texture(1, source.rid)
    compute.set_texture(2, mask.rid)
    compute.set_push_constant_float_array(
        PackedFloat32Array([covered.position.x, covered.position.y, covered.size.x, covered.size.y])
    )
    compute.dispatch_kernel(kernel, SaCompute.groups_for(covered.size.x), SaCompute.groups_for(covered.size.y), 1)
    return scratch


func _notification(what: int) -> void:
    if what == NOTIFICATION_PREDELETE:
        # The textures go while the device is still there.
        _clip_scratch = null
        _mask_scratch = null
        _clip_alpha_scratch = null
        _base_generated = null
        _texels = null
        _base_texels = null
        _mask_texels = null
