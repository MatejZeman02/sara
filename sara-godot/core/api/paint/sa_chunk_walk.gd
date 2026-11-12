## The walk over the chunks a rectangle touches, and the one place a pass that
## rewrites pixels decides which chunks it dispatches over and how narrowly.
##
## Here once rather than in each engine: the grid positions the rectangle
## covers, the selection's mask at each and the positions it leaves out, the
## chunk's own share of the rectangle, the chunk's fields that hold paint, and
## the dispatch. A difference in that walk is a difference in how narrowly Sara
## dispatches.
##
## A walk is built for one pass and kept with it, because the compute, the
## selection and the field policy do not change between runs. What changes per
## run is the kernel, the rectangle, where the chunks come from and what the
## push constant says, and those are [method run]'s arguments.
##
## **What the walk does not do.** It dispatches one kernel over one rectangle
## of one chunk, from the chunk's own origin outwards. A kernel whose invocation
## grid is not the rectangle, the magic wand's row and column sweeps being the
## one in the tree, is not a walk and stays a loop of its own. The reason is
## written where that loop is.
class_name SaChunkWalk
extends RefCounted


## A texture the kernel reads through a sampler rather than as a storage image,
## which is a different `set_` call and cannot be told apart from a plain
## binding by type alone. The gradient's ramp lookup is the one today.
class Sampled:
    extends RefCounted

    var texture: SaTexture

    func _init(sampled: SaTexture) -> void:
        texture = sampled


## One stop of a run: the chunk's field texture the kernel writes at 0, the
## selection's mask or null, the caller's bindings over the stand-ins, the push
## constant and the groups dispatched. Built where the stop is measured and
## read where it is dispatched, which is later for a walk built with
## *one_list*.
class Stop:
    extends RefCounted

    var texture: SaTexture
    var mask: SaTexture
    var bindings: Dictionary[int, Variant]
    var push: PackedFloat32Array
    var groups: Vector2i

    func _init(
        written: SaTexture,
        selected: SaTexture,
        bound: Dictionary[int, Variant],
        constant: PackedFloat32Array,
        dispatched: Vector2i,
    ) -> void:
        texture = written
        mask = selected
        bindings = bound
        push = constant
        groups = dispatched


## The compute the pass dispatches through. Owned by the pass, not by the walk,
## because a pass caches its own for the reason `SaCompute.use_storage_format`
## gives: changing the format reloads the pipelines.
var _compute: SaCompute
## The selection every stop is measured against, or null for a pass that binds
## its own mask through `bindings` or honours none.
var _selection: SaSelection
## The layer whose schema says which fields hold paint, and whose chunks are
## marked unresolved as the walk writes them. Null for a walk over a mask.
var _layer: SaLayer
## The single field a stop dispatches over when the walk is not over a layer.
var _field_id: StringName

## What every stop binds before the caller's own bindings are read: the whole
## of a kernel layout whose uniform set has to cover every binding whichever
## kernel runs, which is what the selection's kernels want. A caller then names
## only what it actually reads, and a null it names falls back to the stand-in
## here rather than unbinding it.
var _defaults: Dictionary[int, Variant]

## True when a run dispatches every stop in one compute list rather than a list
## a stop. Every stop writes its own chunk's texture, so the stops carry no
## hazard between them, but a pass whose bindings read another chunk may read
## one the same run writes, and a list end is the barrier that orders the two.
## So the caller says so, and the gradient, which reads its ramp and the
## selection and writes every chunk of the canvas on every move, is the one
## that does.
var _one_list: bool


func _init(
    compute: SaCompute,
    selection: SaSelection = null,
    layer: SaLayer = null,
    field_id: StringName = &"",
    defaults: Dictionary[int, Variant] = {},
    one_list: bool = false
) -> void:
    _compute = compute
    _selection = selection
    _layer = layer
    _field_id = field_id
    _defaults = defaults
    _one_list = one_list


## Dispatches *kernel* over every chunk *rect* touches, once per chunk, over
## that chunk's own share of *rect*. Returns the grid positions it stopped at,
## in no particular order, which is what a caller records as the reach of what
## it wrote.
##
## *chunk_at* answers the chunk at a grid position or null to skip it, and is
## the caller's whole policy on allocation: a pass that lands edge to edge
## passes `layer.get_or_create_chunk`, one that rewrites what is there reads
## `layer.chunks`. It is called immediately before the chunk is dispatched and
## only for a position the walk has already decided to stop at, so a caller
## that has to snapshot a chunk before the kernel writes over it does that
## here, which is the one moment it is right.
##
## *push* answers the push constant for one stop, given the grid position, the
## chunk-local rectangle and the workgroup-aligned pixel the dispatch starts
## at. A kernel that reads its origin out of the push constant writes *start*
## into the slots it declares for it. A kernel that reads `global_id` as the
## chunk-local pixel gets *start* at zero, because such a caller passes a
## rectangle that reaches the chunk's own origin, and the walk would otherwise
## be dispatching the wrong pixels rather than fewer of them.
##
## *bindings* names what the kernel reads beyond the chunk's own texture, which
## is always bound at 0, and the selection's mask, which is bound at
## `SaSelection.BINDING` when the walk has a selection. A value is an
## [SaTexture], an [SaCompute.Buffer] or a [Sampled].
##
## **Or *bindings* is a `Callable` answering that dictionary for one grid
## position**, which is what a pass that reads across the chunk seams needs:
## the selection's feather and border read the chunk before and the chunk
## after, and the bucket fill's paint takes its mask from the flood's own
## chunks rather than from the document's selection. Three loops share that
## shape, which is what it is for. A pass whose bindings are the same at every
## stop hands over the dictionary and the walk reads it at every stop.
##
## A walk built with *one_list* calls *chunk_at* and *push* for every stop
## first and dispatches afterwards, because allocating a chunk clears a texture
## and the device refuses that while a list is open.
func run(kernel: String, rect: Rect2i, chunk_at: Callable, push: Callable, bindings: Variant = {}) -> Array[Vector2i]:
    var stopped: Array[Vector2i] = []
    if _compute == null or rect.size.x <= 0 or rect.size.y <= 0:
        return stopped
    var queued: Array[Stop] = []
    for grid_pos in positions_in(rect):
        var mask: SaTexture = null
        if _selection != null:
            # Null is a selection that is active and leaves this chunk out, so
            # there is nothing here to write and no chunk worth allocating.
            mask = _selection.texture_for(grid_pos)
            if mask == null:
                continue
        var chunk: SaChunk = chunk_at.call(grid_pos)
        if chunk == null:
            continue
        var local := local_rect(grid_pos, rect, chunk.pixel_size())
        if local.size.x <= 0 or local.size.y <= 0:
            continue
        var start := _aligned_start(local)
        var params: PackedFloat32Array = push.call(grid_pos, local, start)
        var stop := _stop_bindings(bindings, grid_pos)
        for field_id: StringName in _fields_of(chunk):
            var texture: SaTexture = chunk.fields.get(field_id, null)
            if texture == null or not texture.rid.is_valid():
                continue
            var groups := Vector2i(SaCompute.groups_for(local.end.x - start.x), SaCompute.groups_for(local.end.y - start.y))
            var held := Stop.new(texture, mask, stop, params, groups)
            if _one_list:
                queued.append(held)
                continue
            _dispatch_stop(kernel, held)
            _compute.list_end()
        if _layer != null:
            _layer.mark_unresolved(grid_pos)
        stopped.append(grid_pos)
    # What a walk built with *one_list* held back, in one list for each storage
    # format among its chunks, which is one list for every walk in the tree.
    for queued_stop: Stop in queued:
        _dispatch_stop(kernel, queued_stop)
    _compute.list_end()
    return stopped


## Binds what one *stop* reads and writes and dispatches it: the texture at 0,
## the selection's mask when there is one, the caller's bindings and push
## constant, over its groups. Into the list open for the kernel at the
## texture's format, which the caller closes after this stop or after the last
## one.
func _dispatch_stop(kernel: String, stop: Stop) -> void:
    _compute.set_texture(0, stop.texture.rid)
    if stop.mask != null:
        _compute.set_texture(SaSelection.BINDING, stop.mask.rid)
    _bind_extras(stop.bindings)
    _compute.set_push_constant_float_array(stop.push)
    _compute.list_dispatch_kernel(kernel, stop.texture.format, stop.groups.x, stop.groups.y, 1)


## Every grid position *rect* touches, in document pixels. A rectangle that
## starts left of or above the canvas gives negative positions, which is what a
## marquee dragged off the edge is, and a caller's chunk source is what decides
## whether such a position holds anything.
static func positions_in(rect: Rect2i) -> Array[Vector2i]:
    var found: Array[Vector2i] = []
    if rect.size.x <= 0 or rect.size.y <= 0:
        return found
    var side := SaChunk.SIZE
    var first := Vector2i(floori(float(rect.position.x) / side), floori(float(rect.position.y) / side))
    var last := Vector2i(floori(float(rect.end.x - 1) / side), floori(float(rect.end.y - 1) / side))
    for y in range(first.y, last.y + 1):
        for x in range(first.x, last.x + 1):
            found.append(Vector2i(x, y))
    return found


## *rect*'s share of the chunk at *grid_pos*, in that chunk's own texels,
## clipped to a chunk of *pixel_size* texels. The empty rectangle when the two
## do not meet.
##
## *rect* is in document pixels and *pixel_size* comes from the chunk rather
## than from `SaChunk.SIZE`, so the chunk's texels per document
## pixel are *pixel_size* over `SaChunk.SIZE`: a chunk at 2.0 answers twice the
## rectangle, from twice the offset. The share is taken in
## document pixels first and scaled after, so a rectangle never lands on half
## a document pixel.
static func local_rect(grid_pos: Vector2i, rect: Rect2i, pixel_size: int) -> Rect2i:
    var side := SaChunk.SIZE
    var share := Rect2i(rect.position - grid_pos * side, rect.size).intersection(Rect2i(0, 0, side, side))
    if share.size.x <= 0 or share.size.y <= 0:
        return Rect2i()
    if pixel_size == side:
        return share
    var texels := float(pixel_size) / side
    var start := Vector2i((Vector2(share.position) * texels).floor())
    var end := Vector2i((Vector2(share.end) * texels).ceil())
    return Rect2i(start, end - start).intersection(Rect2i(0, 0, pixel_size, pixel_size))


## The rectangle in document pixels that the chunks at *positions* cover. What
## a walk over a layer whose chunks are not a canvas takes as its rectangle: a
## stroke buffer or a cache has chunks wherever paint landed and no canvas size
## to ask.
static func reach_of(positions: Array) -> Rect2i:
    var reach := Rect2i()
    var side := SaChunk.SIZE
    for grid_pos: Vector2i in positions:
        var here := Rect2i(grid_pos * side, Vector2i(side, side))
        reach = here if reach.size == Vector2i.ZERO else reach.merge(here)
    return reach


## The pixel the dispatch starts at: *local*'s origin rounded down to the
## workgroup grid, because a workgroup is dispatched whole and half of one
## cannot be skipped.
static func _aligned_start(local: Rect2i) -> Vector2i:
    var workgroup := SaCompute.WORKGROUP_SIZE
    return Vector2i(
        floori(float(local.position.x) / workgroup) * workgroup, floori(float(local.position.y) / workgroup) * workgroup
    )


## The fields of *chunk* one stop dispatches over: the named one for a walk
## over a mask, and for a walk over a layer every field that holds colour and
## is not derived, because a derived field is computed from the others and a
## pass that wrote it would be overwritten by the next resolve.
func _fields_of(chunk: SaChunk) -> Array:
    if not _field_id.is_empty():
        return [_field_id] if chunk.has_field(_field_id) else []
    var painted: Array = []
    for field_id: StringName in chunk.fields:
        var spec := SaFieldSpec.find(_layer.schema, field_id)
        if spec != null and spec.is_derived():
            continue
        if not _layer.is_color_field(field_id):
            continue
        painted.append(field_id)
    return painted


## One stop's bindings: the stand-ins, with what the caller names over them.
## A null the caller names is the caller saying "there is no neighbour here",
## which the stand-in is for, so it does not unbind anything.
func _stop_bindings(bindings: Variant, grid_pos: Vector2i) -> Dictionary[int, Variant]:
    # A caller's callable or table is its own untyped code, typed here.
    var named: Dictionary[int, Variant] = {}
    var raw: Variant = bindings
    if bindings is Callable:
        var produce: Callable = bindings
        raw = produce.call(grid_pos)
    if raw is Dictionary:
        var plain: Dictionary = raw
        named.assign(plain)
    if _defaults.is_empty():
        return named
    var stop := _defaults.duplicate()
    for binding: int in named:
        if named[binding] != null:
            stop[binding] = named[binding]
    return stop


func _bind_extras(bindings: Dictionary[int, Variant]) -> void:
    for binding: int in bindings:
        var bound: Variant = bindings[binding]
        if bound is Sampled:
            var sampled: Sampled = bound
            _compute.set_sampled_texture(binding, sampled.texture.rid)
        elif bound is SaTexture:
            var texture: SaTexture = bound
            _compute.set_texture(binding, texture.rid)
        elif bound is SaCompute.Buffer:
            var buffer: SaCompute.Buffer = bound
            _compute.set_buffer(binding, buffer.rid)
