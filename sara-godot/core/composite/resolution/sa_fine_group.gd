## An isolated group holding a layer at 2.0, inside a display chunk's walk: its
## composite made afresh from its members at twice the density, where its cache
## averaged the layer's detail away, and the halo its own filters read there.
##
## A group whose own records run reads its neighbours through
## [method SaFilterChain.filtered], which brings a source finer than its
## neighbours down to them. Beside the cache or the chain's scope halo, both at
## the document's resolution, the group's composite would come down before its
## filters and the detail would be gone. Here the neighbours are at 2.0 as well: a [Halo] of
## the group's composite at twice the density, over the chunk the walk draws and
## the strips of the eight around it a pass reads, so the chain runs at 2.0 and
## scales a pass's reach into its texels the way it does for a record on a
## layer at 2.0 itself.
##
## Two roads fill a halo. A group the walk sets aside for its cache is
## composited here from its members, the chunk and the strips. A scope, a group
## holding the active layer, is composited by the compositor's sweep and pass
## proper into a scratch twice a chunk across, and [method filtered_scope]
## copies it into the halo as the chain's own copies a scope at 1.0.
##
## A group whose records read the whole node keeps the document's resolution,
## because the gather such a pass reads is built of chunks at 1.0.
##
## A display chunk's walk draws one grid position, so a halo is kept around it
## and [method begin] moves it with the walk: its chunks are kept by their
## offset from the position walked and handed to the next position at the same
## offset, so a frame of display chunks makes no texture past the first.
class_name SaFineGroup
extends RefCounted

## The display chunk's pools' `group_slot`, a group's own scratch at each depth.
var _group_slot: Callable
var _chain: SaFilterChain = null
var _detail: SaDetailView.Target = null
## The compositor's `clear_scratch_batch`, and its `_composite_entry_chunk`
## for one member into a target twice a chunk across.
var _clear: Callable
var _step: Callable
## Group instance id -> its [Halo], for the groups the walks so far filtered.
var _halos: Dictionary[int, Halo] = {}
## The grid position the walk in hand draws.
var _centre := Vector2i.ZERO
## Where a scope's scratch is copied into its halo, made on its first use.
var _copier: SaCompute = null


## A group's composite at twice the density before its filters, over the
## position a display chunk's walk draws and the strips of the eight around it
## its filters read. A layer nobody is a child of, which the chain reads as it
## reads any neighbours, and a position it holds no chunk at reads as nothing.
class Halo:
    extends RefCounted

    var layer: SaLayer = null
    ## Offset from the walked position -> the chunk kept there, so the next
    ## walk hands it to its own position rather than making a texture.
    var _kept: Dictionary[Vector2i, SaChunk] = {}

    ## Lets every chunk go from where it stood and keeps it by its offset from
    ## *centre*, so the walk about to begin holds nothing it does not fill.
    func move(centre: Vector2i) -> void:
        if layer == null:
            return
        for grid_pos: Vector2i in layer.chunks.keys():
            _kept[grid_pos - centre] = layer.chunks[grid_pos]
            layer.set_chunk(grid_pos, null)

    ## The chunk at *grid_pos*, *offset* from the walked position, at *format*
    ## and twice the density, made only when none is kept at that offset.
    func take(grid_pos: Vector2i, offset: Vector2i, format: int) -> SaTexture:
        if layer != null and layer.schema[0].format != format:
            layer.free()
            layer = null
            _kept.clear()
        if layer == null:
            layer = SaLayer.new()
            layer.name = "Fine halo"
            layer.schema = SaFieldSpec.default_schema(format)
            layer.resolution_scale = SaDetailView.DENSITY
        if layer.chunks.has(grid_pos):
            return layer.get_field(grid_pos)
        var chunk: SaChunk = _kept.get(offset, null)
        if chunk == null:
            return layer.get_or_create_chunk(grid_pos).albedo()
        _kept.erase(offset)
        layer.set_chunk(grid_pos, chunk)
        return chunk.albedo()

    func _notification(what: int) -> void:
        if what == NOTIFICATION_PREDELETE and layer != null:
            layer.free()


func _init(group_slot: Callable, chain: SaFilterChain, detail: SaDetailView.Target, clear: Callable, step: Callable) -> void:
    _group_slot = group_slot
    _chain = chain
    _detail = detail
    _clear = clear
    _step = step


## Whether *group*'s own records run at a dense member's density: some record
## is on, and none reads the whole node, for the reason the header gives.
static func dense(group: SaLayer) -> bool:
    return SaFilterChain.has_enabled(group.filters) and not SaNeighbourhoodPass.reads_whole(group.filters)


## Opens a display chunk's walk over *regions*, one grid position: every halo
## moves to it and holds nothing yet.
func begin(regions: Dictionary[Vector2i, Rect2i]) -> void:
    if regions.is_empty():
        return
    _centre = regions.keys()[0]
    for halo: Halo in _halos.values():
        halo.move(_centre)


## *layer*'s chunk at *grid_pos*, or in a display chunk's walk, where *layer*
## is the cache of an isolated group *node* holding a layer at 2.0, the group
## composited afresh from its members over *region*, at *format* and twice a
## chunk across, *depth* groups in. A group whose filters run at 2.0 is
## composited into its [Halo], the strips around it too. One whose filters read
## the whole node is composited over the whole chunk into a scratch, because
## they read past the region, and the chain brings it down.
func field(layer: SaLayer, node: SaLayer, grid_pos: Vector2i, region: Rect2i, format: int, depth: int) -> SaTexture:
    var document := node.get_parent() as SaDocument if node != null and _detail.active() else null
    var steps: Array = document.fold.fine_groups.get(node.get_instance_id(), []) if document != null else []
    if steps.is_empty():
        return layer.get_field(grid_pos)
    if dense(node):
        return _halo_of(layer, node, steps, grid_pos, format, depth)
    var covered := SaDocument.WHOLE_CHUNK if SaFilterChain.has_enabled(node.filters) else region
    var scratch: SaTexture = _group_slot.call(depth, format)
    _detail.adopt(scratch)
    _composite(steps, document, scratch, grid_pos, covered, depth)
    return scratch


## What the chain reads *node*'s neighbours from when *answered* is what
## [method field] answered at *grid_pos*: its [Halo] when that is where the
## field is, and *stored* otherwise.
func neighbours(node: SaLayer, stored: SaLayer, answered: SaTexture, grid_pos: Vector2i) -> SaLayer:
    var halo: Halo = _halos.get(node.get_instance_id(), null) if node != null and answered != null else null
    if halo == null or halo.layer == null or halo.layer.get_field(grid_pos) != answered:
        return stored
    return halo.layer


## Whether a scope *group* is composited twice a chunk across in the walk in
## hand, which is a display chunk's and the group's filters run at 2.0 or none.
func fine_scope(group: SaLayer) -> bool:
    return _detail.active() and (dense(group) or not SaFilterChain.has_enabled(group.filters))


## *scratch*, the scope *group*'s composite at *grid_pos* twice a chunk across,
## filtered at that density with its neighbours read from its [Halo], which the
## sweep filled over the positions around. The scratch is copied into the halo
## and the chain reads the halo's chunk, for the reason
## [method SaFilterChain.filtered_scope] gives. At 1.0 it is the chain's own.
func filtered_scope(group: SaLayer, scratch: SaTexture, grid_pos: Vector2i, region: Rect2i) -> SaTexture:
    if SaDocumentTexels.density_of(scratch) <= 1.0 or not dense(group):
        return _chain.filtered_scope(group, scratch, grid_pos, region)
    var halo := _halo(group)
    var kept := halo.take(grid_pos, grid_pos - _centre, scratch.format)
    var covered := region if region.size.x > 0 else SaDocument.WHOLE_CHUNK
    var density := SaDetailView.DENSITY
    var fine := Rect2i(Vector2i(Vector2(covered.position) * density), Vector2i(Vector2(covered.size) * density))
    _copy(scratch, kept, fine)
    return _chain.filtered(group, kept, grid_pos, region, halo.layer)


## The group's composite at *grid_pos* in its [Halo], over the whole chunk, and
## over the strip of each position around that a pass of the group's reads,
## where the cache says the group shows something. A position around that holds
## nothing is left out, so the chain reads it as transparent.
func _halo_of(cache: SaLayer, node: SaLayer, steps: Array, grid_pos: Vector2i, format: int, depth: int) -> SaTexture:
    var halo := _halo(node)
    var side := SaLayer.CHUNK_SIZE
    var around: Dictionary[Vector2i, Rect2i] = {grid_pos: SaDocument.WHOLE_CHUNK}
    var reach := _chain.reach_of(node)
    if reach > 0:
        # Twice the reach, what a chain of two passes reads, as the chain's own
        # sweeps grow by.
        var read := SaDocument.WHOLE_CHUNK.grow(2 * reach)
        for dy: int in [-1, 0, 1]:
            for dx: int in [-1, 0, 1]:
                var step := Vector2i(dx, dy)
                if step == Vector2i.ZERO or cache.get_field(grid_pos + step) == null:
                    continue
                var strip := Rect2i(read.position - step * side, read.size).intersection(SaDocument.WHOLE_CHUNK)
                if strip.has_area():
                    around[grid_pos + step] = strip
    var document := node.get_parent() as SaDocument
    for at: Vector2i in around:
        var chunk := halo.take(at, at - _centre, format)
        _detail.adopt(chunk)
        _composite(steps, document, chunk, at, around[at], depth)
    return halo.layer.get_field(grid_pos)


## Clears *target* over *region* and composites every member step of *steps*
## into it at *grid_pos*.
func _composite(steps: Array, document: SaDocument, target: SaTexture, grid_pos: Vector2i, region: Rect2i, depth: int) -> void:
    _clear.call([[target, region]])
    for step: Dictionary in steps:
        _step.call(target, Vector2.ZERO, step, grid_pos, region, document.color_space, document.blend_reference_white, depth + 1)


func _halo(group: SaLayer) -> Halo:
    var id := group.get_instance_id()
    if not _halos.has(id):
        _halos[id] = Halo.new()
    return _halos[id]


## Copies *area* of *source* onto *target* at the same texels, through
## `copy_region.gmacs` for the reason [SaFilterHalo] gives.
func _copy(source: SaTexture, target: SaTexture, area: Rect2i) -> void:
    if _copier == null:
        _copier = SaCompute.new("copy_region")
    _copier.use_storage_format(source.format)
    _copier.set_texture(0, target.rid)
    _copier.set_texture(1, source.rid)
    _copier.set_push_constant_float_array(
        PackedFloat32Array(
            [area.position.x, area.position.y, area.position.x, area.position.y, area.size.x, area.size.y, 0.0, 0.0]
        )
    )
    _copier.dispatch_kernel("copy_region", SaCompute.groups_for(area.size.x), SaCompute.groups_for(area.size.y), 1)


func _notification(what: int) -> void:
    if what == NOTIFICATION_PREDELETE:
        _copier = null
        _halos.clear()
