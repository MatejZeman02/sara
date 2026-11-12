## A clipping base and the run of layers clipped to it, composited as one
## group, the way Photoshop's clipping masks are.
##
## The base is drawn as it shows into a scratch of its own, its filters, mask
## and alpha and all. Its colour is copied out at full coverage into a second
## scratch, the plate, and each clipped layer is laid onto the plate by its own
## blend mode and opacity, so each blends with the base's colour and nothing
## under the base. The base's alpha then goes back onto the plate, and the
## group is laid over what lies under the base by the base's mode and opacity.
## Nothing of the base's colour shows through a clipped layer that covers it,
## at a soft edge of the base as much as in its middle.
##
## Rather than laying the base over what is under it first and then each
## clipped layer over that with its alpha times the base's. Wherever the base
## is partly there its own colour would show through with a weight of
## a(1 - a), up to a quarter, so every soft edge of a passage under a clipped
## layer would draw a pale or a dark rim.
##
## The canvas's walk, the fold's caches, a flatten and a merge all come here,
## each with its own way of drawing one step, handed in as a callable. A group
## can hold a group, where a clipped layer is an isolated group with a clipping
## base among its members, so the two scratches are kept per depth of nesting
## and each call takes the next depth in, and as fine as a display chunk inside
## one of its walks.
class_name SaClipGroup
extends RefCounted

## The base as it shows, and the plate, by depth, at the document's resolution.
var _bases: Array[SaTexture] = []
var _plates: Array[SaTexture] = []
## The same, twice a chunk across, for a display chunk's walk.
var _fine_bases: Array[SaTexture] = []
var _fine_plates: Array[SaTexture] = []
## How many groups the call in hand sits inside.
var _depth: int = 0


## The group over *region*, chunk-local pixels, onto *target* at *offset* by
## *mode* at *opacity*. *lay_base* draws the base into the cleared texture it is
## called with, Normal and whole, and *lay_clipped* draws every clipped layer
## onto the plate it is called with, each by its own mode and opacity.
func composite(
    compositor: SaCompositor,
    target: SaTexture,
    offset: Vector2,
    region: Rect2i,
    mode: StringName,
    opacity: float,
    space: SaColorSpace,
    blend_white: float,
    lay_base: Callable,
    lay_clipped: Callable
) -> void:
    var shown := plate(compositor, target.format, region, lay_base, lay_clipped)
    compositor.composite_chunk(target, shown, mode, opacity, offset, space, blend_white, region)


## The group over *region* at *format*, before its own mode and opacity: the
## plate under the base's alpha, in the compositor's clip scratch, so it is
## read before the next call that clips. [method composite] lays it, and a
## merge writes it into the base.
func plate(compositor: SaCompositor, format: int, region: Rect2i, lay_base: Callable, lay_clipped: Callable) -> SaTexture:
    var fine := compositor.detail.active()
    var base := _slot(_fine_bases if fine else _bases, format, fine)
    var plated := _slot(_fine_plates if fine else _plates, format, fine)
    if fine:
        compositor.detail.adopt(base)
        compositor.detail.adopt(plated)
    _depth += 1
    compositor.clear_scratch_batch([[base, region]])
    lay_base.call(base)
    compositor.opaque_chunk(plated, base, region)
    lay_clipped.call(plated)
    _depth -= 1
    return compositor.clip_chunk(plated, base, region)


## The scratch of *pool* at the depth in hand, made when it is missing or at
## another format.
func _slot(pool: Array[SaTexture], format: int, fine: bool) -> SaTexture:
    while pool.size() <= _depth:
        pool.append(null)
    var scratch := pool[_depth]
    if scratch == null or scratch.format != format:
        scratch = SaTexture.new(SaDetailView.side() if fine else SaDocument.WHOLE_CHUNK.size, format)
        pool[_depth] = scratch
    return scratch


func _notification(what: int) -> void:
    if what == NOTIFICATION_PREDELETE:
        # The textures go while the device is still there.
        _bases.clear()
        _plates.clear()
        _fine_bases.clear()
        _fine_plates.clear()
