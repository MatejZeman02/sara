## A chunk stored finer than the document, brought down to the document's
## resolution for the passes that read a chunk texel for texel against another.
##
## The composite kernel reads a finer chunk at its density itself, so a plain
## layer at twice the resolution goes straight into the canvas or a batch. A
## mask, a clip and a layer filter do not: each reads its source at the same
## chunk-local pixel as a coverage or a base at the document's resolution. So
## what goes through them is this scratch, each pixel the mean of the texels
## under it, which is what the kernel draws anyway, and the order it is drawn in
## changes nothing because a mask and a clip only scale a pixel's alpha.
##
## One scratch, reused, so its answer is read before the next call, the way
## `SaCompositor.clip_chunk` is. The compositor holds one for the sources it
## shows, one for the clip bases read beside them, and one for the coverage of
## a mask, which a layer at 2.0 stores at 2.0 too and in a format of its own.
## Each has its own kernel for that reason, so a format is chosen once rather
## than reloaded a chunk at a time, and none is compiled until a finer chunk
## first comes through.
class_name SaDocumentTexels
extends RefCounted

var _scratch: SaTexture = null
var _compute: SaCompute = null


## How many texels of *source* lie along one document pixel: its width over a
## chunk's at 1.0, and 1 for anything no wider. `SaChunk.pixel_size()` is that
## width times the scale, so this is the scale read back from the texture.
static func density_of(source: SaTexture) -> float:
    if source == null or source.size.x <= SaChunk.SIZE:
        return 1.0
    return float(source.size.x) / float(SaChunk.SIZE)


## *source* over *region*, in document pixels, at the document's resolution:
## *source* itself when it is no finer, and this scratch holding its mean when
## it is.
func of(source: SaTexture, region: Rect2i) -> SaTexture:
    var density := density_of(source)
    if density <= 1.0:
        return source
    var side := Vector2i(SaChunk.SIZE, SaChunk.SIZE)
    if _scratch == null or _scratch.format != source.format:
        _scratch = SaTexture.new(side, source.format)
    var covered := region if region.size.x > 0 else Rect2i(Vector2i.ZERO, side)
    if _compute == null:
        _compute = SaCompute.new("composite")
    _compute.use_storage_format(source.format)
    _compute.set_texture(0, _scratch.rid)
    _compute.set_texture(1, source.rid)
    _compute.set_push_constant_float_array(SaCompute.pack_composite_params(Vector2.ZERO, 1.0, null, density, 1.0, covered))
    _compute.dispatch_kernel("resample", SaCompute.groups_for(covered.size.x), SaCompute.groups_for(covered.size.y), 1)
    return _scratch


func _notification(what: int) -> void:
    if what == NOTIFICATION_PREDELETE:
        _scratch = null
        _compute = null
