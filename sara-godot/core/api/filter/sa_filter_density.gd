## Where a chunk's texels sit in a picture of a rectangle, and a selection's
## coverage at a chunk's density, for the filter door on a layer at twice the
## document's resolution.
##
## The door hands a filter a layer at the layer's own density: a picture of a
## rectangle of document pixels holds *scale* texels per pixel on a side, and a
## chunk at 2.0 holds 512 texels over its 256 pixels. The context, Apply, the
## browser's pass picture and the preview all stitch chunks into such a picture
## or out of it, so where a chunk's share lands is answered here once. The
## share is [method SaChunkWalk.local_rect], the rule for every walk, so a
## filter and a fill agree on which texels a rectangle holds.
##
## A kernel reads its selection at its own texel, `min(at, image_size(mask) -
## 1)`, which is right while a chunk and its mask are the same size. [Masks]
## enlarges the mask to the chunk's size, so a module that knows nothing of
## scale masks the texels it writes by the pixel they lie in.
class_name SaFilterDensity
extends RefCounted


## The texels per document pixel on a side of *layer*, 1.0 with no layer.
static func scale_of(layer: SaLayer) -> float:
    if layer == null or layer.resolution_scale <= 0.0:
        return 1.0
    return layer.resolution_scale


## The side of a chunk of *layer* in texels, which is what
## `SaChunk.pixel_size()` answers for the chunks it makes. Asked of the layer
## because a position the layer holds no chunk at still has a side a filter
## writes at.
static func side_of(layer: SaLayer) -> int:
    return maxi(1, roundi(float(SaChunk.SIZE) * scale_of(layer)))


## The size in texels of a picture of *rect*, in document pixels, at *side*
## texels a chunk.
static func texels(rect: Rect2i, side: int) -> Vector2i:
    return in_texels(rect.size, side)


## *pixels*, a place or a size in document pixels, in the texels of a chunk
## *side* texels across. Exact at the scales a layer takes, 1.0 and 2.0.
static func in_texels(pixels: Vector2i, side: int) -> Vector2i:
    return Vector2i(length(pixels.x, side), length(pixels.y, side))


## A length of *pixels* document pixels in the texels of a chunk *side*
## texels across.
static func length(pixels: int, side: int) -> int:
    @warning_ignore("integer_division")
    return pixels * side / SaChunk.SIZE


## Where the chunk at *grid_pos*, *side* texels across, meets a picture of
## *rect*: `[local, at]`, its share in the chunk's own texels and where that
## share's first texel sits in the picture. An empty *local* when the two do
## not meet.
static func place(grid_pos: Vector2i, rect: Rect2i, side: int) -> Array[Rect2i]:
    var local := SaChunkWalk.local_rect(grid_pos, rect, side)
    var corner := grid_pos * side - in_texels(rect.position, side)
    return [local, Rect2i(corner + local.position, local.size)]


## A GPU to GPU copy of the chunk texture *chunk* at *grid_pos* into
## *picture*, which covers *rect*, or the other way round with *outwards*
## false, over the chunk's share. Answers the share, empty when there is none.
static func copy_share(
    rd: RenderingDevice, chunk: SaTexture, grid_pos: Vector2i, rect: Rect2i, picture: SaTexture, outwards: bool = true
) -> Rect2i:
    var placed := place(grid_pos, rect, chunk.size.x)
    var local: Rect2i = placed[0]
    if local.size.x <= 0 or local.size.y <= 0:
        return Rect2i()
    var at: Rect2i = placed[1]
    var from := Vector3(local.position.x, local.position.y, 0)
    var to := Vector3(at.position.x, at.position.y, 0)
    var extent := Vector3(local.size.x, local.size.y, 1)
    if outwards:
        rd.texture_copy(chunk.rid, picture.rid, from, to, extent, 0, 0, 0, 0)
    else:
        rd.texture_copy(picture.rid, chunk.rid, to, from, extent, 0, 0, 0, 0)
    return local


## A selection's coverage enlarged to a chunk's density, made on the GPU and
## kept while the holder lives, so one Apply enlarges each mask once. Held per
## run: a mask held longer would answer a selection the painter has since
## changed.
class Masks:
    extends RefCounted

    var _compute: SaCompute = null
    # The mask's instance id and the side -> the enlarged mask.
    var _made: Dictionary[Vector2i, SaTexture] = {}

    ## *mask* at *side* texels across. Itself when it is already that size or
    ## is a 1 by 1 stand-in, which reads the same at any density through a
    ## clamped read, and null for null, a selection that leaves the chunk out.
    func at(mask: SaTexture, side: int) -> SaTexture:
        if mask == null or mask.size.x <= 1 or mask.size.x == side:
            return mask
        var key := Vector2i(mask.get_instance_id(), side)
        if _made.has(key):
            return _made[key]
        var enlarged := SaTexture.new(Vector2i(side, side), mask.format)
        if _compute == null:
            _compute = SaCompute.new("mask_at_density")
        _compute.use_storage_format(mask.format)
        _compute.set_texture(0, enlarged.rid)
        _compute.set_texture(1, mask.rid)
        _compute.set_push_constant_float_array(PackedFloat32Array([0.0, 0.0]))
        _compute.dispatch_kernel("mask_at_density", SaCompute.groups_for(side), SaCompute.groups_for(side), 1)
        _made[key] = enlarged
        return enlarged

    func _notification(what: int) -> void:
        if what == NOTIFICATION_PREDELETE:
            _made.clear()
            _compute = null
