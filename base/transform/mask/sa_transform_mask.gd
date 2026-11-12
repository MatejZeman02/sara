## The layer's mask carried with the paint a transform lifts.
##
## A layer's mask is the `SaFieldSpec.MASK` field of its own chunks, so it
## belongs to the paint it hides, and Photoshop and Krita alike move a linked
## mask with whatever the transform tool does to the layer. A sibling of
## [SaTransform] rather than more of it, because what is here is the mask's
## half alone: the lift's chunks, the history step and the map stay there,
## and this owns the carry, the textures it lands through and what it wrote
## into the layer while the hand was still moving.
##
## **The lift.** `take` reads the mask where the selection covers it into one
## carry the size of the lifted box, its colour the mask and its alpha the
## coverage, and leaves the mask in the hole at its rest. It runs after the
## pass captured the chunk, so the cut is in the gesture's one undo step.
##
## **The drag shows the moved mask.** The compositor masks the stroke layer's
## preview with the active layer's mask, so a preview over the mask left where
## it was would show what the moved mask hides. Each frame `draw` puts back
## what the last frame wrote and lays the moved carry over the landing, and a
## landing with no chunk of the layer under it gains one that `restore` takes
## away again. The first write to a chunk keeps a copy of its mask, and
## `restore` writes every copy back, so the layer reads as the lift left it
## before the commit captures its landing or the cancel puts the lift back.
##
## **The commit.** `land` lays the moved carry over one landing chunk after
## the pass captured it, where the mask goes towards the carried mask by the
## carried coverage and keeps what it held outside the moved selection.
##
## The kernels are this object's own, at the carry's `rgba32f` and the mask's
## `r32f`, for the reason `SaTransformSelection.Kernels` gives: one object
## switched between the document's depth and these would rebuild its
## pipelines on every switch.
class_name SaTransformMask
extends RefCounted

## The workgroup a dispatch's start is aligned down to.
const WORKGROUP := SaCompute.WORKGROUP_SIZE
## The carry's format: the mask in the colour, the coverage in the alpha.
const CARRY_FORMAT: int = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT

var _document: SaDocument
var _layer: SaLayer
## What the mask reads where the layer holds no chunk, which the hole takes.
var _rest: float
## Texels a document pixel, the layer's resolution scale.
var _scale: float
## The lifted box in document pixels, where the carry's (0, 0) stands.
var _bounds: Rect2i
## The whole lifted box of mask and coverage, made by the first `take`.
var _carry: SaTexture = null
## One chunk's texels of the carry moved through the map, written and read
## once per landing chunk.
var _moved: SaTexture = null
## Grid position -> the copy of that chunk's mask as the lift left it, kept
## the first time a frame wrote there.
var _kept: Dictionary[Vector2i, SaTexture] = {}
## Grid position -> the rectangle the last frame wrote, in the chunk's texels.
var _written: Dictionary[Vector2i, Rect2i] = {}
## The chunks a frame made where the layer held none, taken away by `restore`.
var _made: Dictionary[Vector2i, bool] = {}
var _carry_compute: SaCompute = null
var _resample_compute: SaCompute = null
var _warp_compute: SaCompute = null
var _blank_compute: SaCompute = null
var _copy_compute: SaCompute = null


func _init(document: SaDocument, layer: SaLayer, bounds: Rect2i) -> void:
    _document = document
    _layer = layer
    _bounds = bounds
    _rest = layer.mask.rest
    _scale = layer.resolution_scale


## A carry for *layer*'s mask over *bounds*, or null when the layer has no mask
## of its own chunks or there is no device to carry it on. A group's mask holds
## chunks of its own and moves with the group's transform, not here.
static func of(document: SaDocument, layer: SaLayer, bounds: Rect2i) -> SaTransformMask:
    if document == null or layer == null or layer.mask == null or layer.mask.is_own():
        return null
    if SaFieldSpec.find(layer.schema, SaFieldSpec.MASK) == null or GlobalShaderCompiler.get_rd() == null:
        return null
    return SaTransformMask.new(document, layer, bounds)


## Takes the mask of the chunk at *grid_pos* over *local*, its texels inside
## the lifted box, into the carry where *selection* covers it, and leaves the
## mask in the hole at its rest.
func take(grid_pos: Vector2i, local: Rect2i, selection: SaTexture) -> void:
    var field := _layer.get_field(grid_pos, SaFieldSpec.MASK)
    if field == null or selection == null or local.size.x <= 0 or local.size.y <= 0:
        return
    if _carry == null:
        var whole := _texels(Rect2i(Vector2i.ZERO, _bounds.size)).size
        _carry = SaTexture.new(whole, CARRY_FORMAT)
        _blank(_carry, Rect2i(Vector2i.ZERO, whole))
    var start := _aligned(local)
    var origin := _texel_of(grid_pos * SaLayer.CHUNK_SIZE - _bounds.position)
    var compute := _carry_kernels()
    compute.set_texture(0, field.rid)
    compute.set_texture(SaSelection.BINDING, selection.rid)
    compute.set_texture(2, _carry.rid)
    compute.set_push_constant_float_array(
        PackedFloat32Array([start.x, start.y, local.end.x, local.end.y, origin.x, origin.y, _rest])
    )
    var covered := local.end - start
    compute.dispatch_kernel("mask_take", SaCompute.groups_for(covered.x), SaCompute.groups_for(covered.y), 1)


## Whether the lift took any mask, and so whether a frame or a commit has a
## carry to lay down.
func is_carrying() -> bool:
    return _carry != null


## Lays the carry through the map over *wanted*, grid position to the
## rectangle a frame lands on in that chunk's texels, after putting back what
## the frame before wrote. *resample* draws a source through the pass's map
## into a target over a rectangle of a chunk, `SaTransform._resample_with`.
## Answers the grid positions whose mask changed, which want drawing again.
func draw(wanted: Dictionary, resample: Callable) -> Array[Vector2i]:
    var touched: Array[Vector2i] = []
    if _carry == null:
        return touched
    for grid_pos: Vector2i in _written:
        if not wanted.has(grid_pos):
            _put_back(grid_pos, _written[grid_pos])
            touched.append(grid_pos)
    var written: Dictionary[Vector2i, Rect2i] = {}
    for grid_pos: Vector2i in wanted:
        var local: Rect2i = wanted[grid_pos]
        if _written.has(grid_pos):
            _put_back(grid_pos, _written[grid_pos])
        elif not _layer.chunks.has(grid_pos):
            _layer.get_or_create_chunk(grid_pos, _scale)
            _made[grid_pos] = true
        var field := _layer.get_field(grid_pos, SaFieldSpec.MASK)
        if field == null:
            continue
        if not _kept.has(grid_pos):
            var copy := SaTexture.new(field.size, field.format)
            _shift(field, copy, Rect2i(Vector2i.ZERO, field.size))
            _kept[grid_pos] = copy
        _land(field, grid_pos, local, resample)
        written[grid_pos] = local
        touched.append(grid_pos)
    _written = written
    return touched


## Writes back every chunk's mask a frame wrote, and takes away the chunks a
## frame made, so the layer reads as the lift left it. Answers the positions
## that changed.
func restore() -> Array[Vector2i]:
    var touched: Array[Vector2i] = []
    for grid_pos: Vector2i in _written:
        _put_back(grid_pos, _written[grid_pos])
        touched.append(grid_pos)
    for grid_pos: Vector2i in _made:
        _layer.set_chunk(grid_pos, null)
        if not touched.has(grid_pos):
            touched.append(grid_pos)
    _written.clear()
    _made.clear()
    _kept.clear()
    return touched


## Lays the carry through the map over *local* of *chunk*'s mask, the chunk
## at *grid_pos* the commit lands in, after the pass captured it.
func land(chunk: SaChunk, grid_pos: Vector2i, local: Rect2i, resample: Callable) -> void:
    if _carry == null or chunk == null:
        return
    var field := chunk.field(SaFieldSpec.MASK)
    if field != null:
        _land(field, grid_pos, local, resample)


func _land(field: SaTexture, grid_pos: Vector2i, local: Rect2i, resample: Callable) -> void:
    if local.size.x <= 0 or local.size.y <= 0:
        return
    if _moved == null or _moved.size != field.size:
        _moved = SaTexture.new(field.size, CARRY_FORMAT)
    _kernels_ready()
    resample.call(_resample_compute, _warp_compute, _moved, _carry, grid_pos, local)
    var start := _aligned(local)
    var compute := _carry_kernels()
    compute.set_texture(0, field.rid)
    compute.set_texture(2, _moved.rid)
    compute.set_push_constant_float_array(PackedFloat32Array([start.x, start.y, local.end.x, local.end.y, 0.0, 0.0, _rest]))
    var covered := local.end - start
    compute.dispatch_kernel("mask_land", SaCompute.groups_for(covered.x), SaCompute.groups_for(covered.y), 1)


## Writes *local* of the kept copy back into the chunk at *grid_pos*.
func _put_back(grid_pos: Vector2i, local: Rect2i) -> void:
    var copy: SaTexture = _kept.get(grid_pos, null)
    var field := _layer.get_field(grid_pos, SaFieldSpec.MASK)
    if copy != null and field != null:
        _shift(copy, field, local)


## A copy of *rect* of *from* into the same texels of *into*, on the compute
## queue, so it is ordered against the kernels round it.
func _shift(from: SaTexture, into: SaTexture, rect: Rect2i) -> void:
    if _copy_compute == null:
        _copy_compute = SaCompute.new("crop")
        _copy_compute.use_storage_format(SaSelection.FORMAT)
    _copy_compute.set_texture(0, from.rid)
    _copy_compute.set_texture(1, into.rid)
    var at := rect.position
    _copy_compute.set_push_constant_float_array(PackedFloat32Array([at.x, at.y, at.x, at.y, rect.size.x, rect.size.y, 0.0, 0.0]))
    _copy_compute.dispatch_kernel("shift", SaCompute.groups_for(rect.size.x), SaCompute.groups_for(rect.size.y), 1)


## Writes transparency over *rect* of *texture*, on the compute queue.
func _blank(texture: SaTexture, rect: Rect2i) -> void:
    if _blank_compute == null:
        _blank_compute = SaCompute.new("clear")
        _blank_compute.use_storage_format(CARRY_FORMAT)
    _blank_compute.set_texture(0, texture.rid)
    _blank_compute.set_push_constant_float_array(
        PackedFloat32Array([0.0, 0.0, rect.position.x, rect.position.y, rect.size.x, rect.size.y, 0.0, 0.0])
    )
    _blank_compute.dispatch_kernel("clear_chunk", SaCompute.groups_for(rect.size.x), SaCompute.groups_for(rect.size.y), 1)


func _carry_kernels() -> SaCompute:
    if _carry_compute == null:
        _carry_compute = SaCompute.new("mask_carry")
        _carry_compute.use_storage_format(SaSelection.FORMAT)
    return _carry_compute


func _kernels_ready() -> void:
    if _resample_compute == null:
        _resample_compute = SaCompute.new("transform")
        _resample_compute.use_storage_format(CARRY_FORMAT)
        _warp_compute = SaCompute.new("warp")
        _warp_compute.use_storage_format(CARRY_FORMAT)


## *local*'s start aligned down to the workgroup grid.
static func _aligned(local: Rect2i) -> Vector2i:
    return Vector2i(
        floori(float(local.position.x) / WORKGROUP) * WORKGROUP, floori(float(local.position.y) / WORKGROUP) * WORKGROUP
    )


## The texel a document offset *at* falls on at the layer's scale.
func _texel_of(at: Vector2i) -> Vector2i:
    return Vector2i((Vector2(at) * _scale).floor())


## *rect*, in document pixels, in the layer's texels.
func _texels(rect: Rect2i) -> Rect2i:
    var start := Vector2i((Vector2(rect.position) * _scale).floor())
    return Rect2i(start, Vector2i((Vector2(rect.end) * _scale).ceil()) - start)
