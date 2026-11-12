## A composite before a node's filters, kept at the grid positions a pass reads
## it from and nowhere else, and the same shape the compositor keeps the active
## layer's live stroke in. A layer that is nobody's child, the way the fold's
## caches are, so [method SaFilterChain.filtered] reads it as it reads any
## neighbours, and a position it holds no chunk at reads as transparent.
##
## A class of its own because two owners hold one, and it takes no reference
## back: the compositor builds one for the live stroke, the chain one for the
## root and one per scope, and none of the three asks the other anything.
class_name SaFilterHalo
extends RefCounted

## The meta [method fill] leaves on [member layer]: the instance id of the
## layer the halo lies over, which reads as itself wherever the halo holds no
## chunk.
const OVER := &"sa_halo_over"

var layer: SaLayer = null
## Where a clear goes, made once and reused: a dispatch and not
## `texture_clear`, for the reason [SaNeighbourhoodPass.Runner] gives.
var _clearer: SaCompute = null
## Where a gather's copies go, made on their first use and for the reason
## [member _clearer] gives.
var _copier: SaCompute = null
## The layer gathered into one texture for a whole-node pass to read, the
## rectangle it spans, the positions already copied into it, and whether
## the texture still holds the last composite's chunks.
var _whole := SaNeighbourhoodPass.Whole.new()
var _span := Rect2i()
var _gathered: Dictionary[Vector2i, bool] = {}
var _blank: bool = true
## The document the last [method fill] composited and its consume count then,
## so a position swept over an empty region keeps its chunk only when the fill
## before this one saw every paint since.
var _filled_document: int = 0
var _filled_consumed: int = -1


## The chunk at *grid_pos*, at *format* and *scale* texels along a document
## pixel, made when missing. What it held before is only ever read where the
## caller has just copied.
func take(grid_pos: Vector2i, format: int, scale: float = 1.0) -> SaTexture:
    if layer != null and (layer.schema[0].format != format or layer.resolution_scale != scale):
        layer.free()
        layer = null
    if layer == null:
        layer = SaLayer.new()
        layer.name = "Halo"
        layer.schema = SaFieldSpec.default_schema(format)
        layer.resolution_scale = scale
    return layer.get_or_create_chunk(grid_pos).albedo()


## Opens a sweep: the rectangle the upcoming gather spans, taken from the
## positions the sweep fills, and an empty gather under it. Called before
## the sweep renders, so the texture is already the right size when the
## first chunk lands in it and never has to be made again.
func begin(held: Dictionary[Vector2i, bool]) -> void:
    _span = _span_of(held)
    _gathered.clear()
    _blank = true


## The layer gathered at *format*, extended with whichever of its chunks no
## earlier call copied, or null where the halo holds none.
##
## A whole-node pass on a scope reads a texel the sweep has not filled yet,
## so the gather grows with the halo rather than being made again: a position
## is copied by the first dispatch after it was written. That keeps a sweep
## over N positions at N copies instead of N gathers of N chunks, and what a
## dispatch in the middle of the sweep reads is the positions filled so far,
## which is the sweep's own answer and is read by nobody: the sweep renders
## into a slot the pass proper clears before it writes.
func gathered(format: int) -> SaNeighbourhoodPass.Whole:
    if layer == null or _span.size.x <= 0:
        return null
    var side := Vector2i(SaLayer.CHUNK_SIZE, SaLayer.CHUNK_SIZE)
    if _whole.texture == null or _whole.texture.format != format or _whole.texture.size != _span.size:
        _whole.texture = SaTexture.new(_span.size, format)
        _whole.origin = _span.position
        _gathered.clear()
        _blank = true
    if _blank:
        # A chunk the halo was not given reads as nothing rather than as the
        # chunk the last composite left there.
        _clear_unheld(side)
        _blank = false
    for grid_pos: Vector2i in layer.chunks:
        if _gathered.has(grid_pos):
            continue
        var texture := layer.get_field(grid_pos)
        if texture == null or texture.size != side:
            continue
        _gathered[grid_pos] = true
        var at := grid_pos * SaLayer.CHUNK_SIZE - _span.position
        _copy_onto(_whole.texture, texture, at, side)
    return _whole


## Drops every chunk outside *reached*, so a position the pass does not
## copy into reads as transparent and never as an earlier pass left it.
func only(reached: Dictionary[Vector2i, bool]) -> void:
    if layer == null:
        return
    for grid_pos: Vector2i in layer.chunks.keys():
        if not reached.has(grid_pos):
            layer.set_chunk(grid_pos, null)


## Fills this halo with *painted*'s own chunks and the live stroke over them,
## over *swept*, grid position -> the region to composite there, so a
## neighbourhood pass of *painted*'s own reads the two together rather than
## the layer alone. A position outside *swept* holds no chunk, and the layer is
## marked as lying over *painted*, see [method lies_over], so a whole-node
## gather reads *painted*'s own chunk there.
##
## *composite* is the compositor's own `composite_chunk`: the pair a halo
## chunk holds is then the pair the stroke's scratch is built from and the
## two cannot drift. Each chunk is cleared first, because a texel the layer
## and the stroke both leave transparent would otherwise read as whatever
## the halo held there before, and the whole layer is let go when *swept* is
## empty, which is a layer at rest paying nothing.
##
## A position swept over an empty region keeps the chunk the halo holds there,
## which is how a whole-node pass's sweep says nothing changed under it. It is
## composited whole instead when the halo holds none there, or when the fill
## before this one was of another document or missed a consume of this one,
## since then a paint in between was never swept.
func fill(swept: Dictionary[Vector2i, Rect2i], painted: SaLayer, document: SaDocument, composite: Callable) -> void:
    only(SaTyped.positions(swept))
    var continued := document.get_instance_id() == _filled_document and document.consumed == _filled_consumed + 1
    _filled_document = document.get_instance_id()
    _filled_consumed = document.consumed
    if swept.is_empty() or painted == null or document.stroke_layer == null:
        drop()
        return
    var stroke := document.stroke_layer
    var mode := stroke.get_blend_mode_name()
    var opacity := document.stroke_opacity
    var space := document.color_space
    var white := document.blend_reference_white
    # At the layer's own density, so a neighbourhood pass over a layer at 2.0
    # and its stroke runs at 2.0, as it does once the stroke is committed,
    # rather than bringing the two down to this halo first.
    var scale := SaFilterDensity.scale_of(painted)
    var chunks: Dictionary[Vector2i, Array] = {}
    for grid_pos: Vector2i in swept:
        var chunk := painted.get_field(grid_pos)
        if chunk == null:
            chunk = stroke.get_field(grid_pos)
        if chunk == null:
            continue
        var asked: Rect2i = swept[grid_pos]
        if asked.size.x <= 0 and continued and layer != null and layer.get_field(grid_pos) != null:
            continue
        var kept := take(grid_pos, chunk.format, scale)
        var region := SaFilterChain.read_region(painted.filters, asked, SaDocument.WHOLE_CHUNK.size)
        _clear(kept, _finer(region, scale))
        chunks[grid_pos] = [kept, region]
    for grid_pos: Vector2i in chunks:
        var kept: SaTexture = chunks[grid_pos][0]
        var region: Rect2i = chunks[grid_pos][1]
        var fine := _finer(region, scale)
        var under := painted.get_field(grid_pos)
        var over := stroke.get_field(grid_pos)
        composite.call(kept, under, SaLayer.BLEND_MODE.NORMAL, 1.0, Vector2.ZERO, space, white, fine, _read(under, scale))
        composite.call(kept, over, mode, opacity, Vector2.ZERO, space, white, fine, _read(over, scale))
    if layer != null:
        layer.set_meta(OVER, painted.get_instance_id())


## Whether *neighbours* is the layer of a halo [method fill] filled over
## *node*, so a position it holds no chunk at reads as *node*'s own chunk.
static func lies_over(neighbours: SaLayer, node: SaLayer) -> bool:
    return neighbours != null and neighbours != node and neighbours.get_meta(OVER, 0) == node.get_instance_id()


## *region*, in document pixels, in the texels of a halo chunk at *scale*.
static func _finer(region: Rect2i, scale: float) -> Rect2i:
    return Rect2i(Vector2i(Vector2(region.position) * scale), Vector2i(Vector2(region.size) * scale))


## The density a composite into a halo chunk at *scale* reads *source* at,
## zero for the source's own when the halo is at the document's resolution.
static func _read(source: SaTexture, scale: float) -> float:
    return SaDocumentTexels.density_of(source) / scale if scale > 1.0 else 0.0


## Lets the layer go, chunks and all: a halo nothing is swept into holds no
## VRAM and reads as nothing anywhere.
func drop() -> void:
    if layer != null:
        layer.free()
        layer = null


## The rectangle spanning *held*'s grid positions, in document pixels, empty
## for none.
static func _span_of(held: Dictionary[Vector2i, bool]) -> Rect2i:
    if held.is_empty():
        return Rect2i()
    var first: Vector2i = held.keys()[0]
    var last: Vector2i = held.keys()[0]
    for grid_pos: Vector2i in held:
        first = first.min(grid_pos)
        last = last.max(grid_pos)
    return Rect2i(first * SaLayer.CHUNK_SIZE, (last - first + Vector2i.ONE) * SaLayer.CHUNK_SIZE)


## Copies all of *source* onto *target* at *at*, through `copy_region.gmacs`
## for the reason that kernel gives.
func _copy_onto(target: SaTexture, source: SaTexture, at: Vector2i, size: Vector2i) -> void:
    if _copier == null:
        _copier = SaCompute.new("copy_region")
    _copier.use_storage_format(source.format)
    _copier.set_texture(0, target.rid)
    _copier.set_texture(1, source.rid)
    _copier.set_push_constant_float_array(PackedFloat32Array([0.0, 0.0, at.x, at.y, size.x, size.y, 0.0, 0.0]))
    _copier.dispatch_kernel("copy_region", SaCompute.groups_for(size.x), SaCompute.groups_for(size.y), 1)


## Clears every chunk-sized cell of [member _span] the halo holds no chunk at,
## one dispatch each, in the pixels of [member _whole] whose first texel stands
## for the span's start. The positions it does hold are wholly overwritten by
## their own copies, so a clear over them would write the same texels twice and
## pay a dispatch over a rectangle nobody painted.
func _clear_unheld(side: Vector2i) -> void:
    var first := Vector2i((Vector2(_span.position) / Vector2(side)).floor())
    var last := Vector2i((Vector2(_span.end - Vector2i.ONE) / Vector2(side)).floor())
    for y in range(first.y, last.y + 1):
        for x in range(first.x, last.x + 1):
            var grid_pos := Vector2i(x, y)
            var texture := layer.get_field(grid_pos)
            if texture != null and texture.size == side:
                continue
            _clear(_whole.texture, Rect2i(grid_pos * side - _span.position, side))


## Clears *area* of *target*. A dispatch and not `texture_clear`, for the
## reason [SaNeighbourhoodPass.Runner] gives: the composites that follow are
## compute, and a transfer is not ordered against them.
func _clear(target: SaTexture, area: Rect2i) -> void:
    if _clearer == null:
        _clearer = SaCompute.new("clear")
    _clearer.use_storage_format(target.format)
    _clearer.set_texture(0, target.rid)
    _clearer.set_push_constant_float_array(
        PackedFloat32Array([0.0, 0.0, area.position.x, area.position.y, area.size.x, area.size.y, 0.0, 0.0])
    )
    _clearer.dispatch_kernel("clear_chunk", SaCompute.groups_for(area.size.x), SaCompute.groups_for(area.size.y), 1)


func positions() -> Array:
    return layer.chunks.keys() if layer != null else []


func _notification(what: int) -> void:
    if what == NOTIFICATION_PREDELETE:
        _clearer = null
        _copier = null
        _whole.texture = null
        if layer != null:
            layer.free()
