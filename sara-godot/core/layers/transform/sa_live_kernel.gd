## The kernel a live transform resamples a layer's paint through, with the
## textures it binds beside the paint, for the cache and the bake alike.
##
## Owns `live_transform.gmacs` as a compute, the coverage of one bound where
## the layer's mask hides nothing, and the scratch a stroke under way is laid
## over the paint in, each made on first use and kept, and the inverse map and
## the crop every dispatch is pushed, set in the constructor. A change of the
## map or the crop is a new transform and so a new kernel, which takes the
## compute and the textures over from the one before it rather than making
## them again.
##
## **The relief.** A layer's height resamples through the same map and the same
## bilinear read as its colour, with a compute of its own built for the
## height's half float format, so the cache never swaps one pipeline for the
## other between the colour and the height of a chunk. A height is kept as it
## reads, never multiplied by the scale: a relief scaled up is wider and as tall
## as before, as Krita's and Photoshop's height layers are, and a flip leaves its
## sign, since a ridge stays a ridge seen from either side. Nought is its rest,
## so a tap where the layer holds no height adds nothing, and the cache's height
## carries the mask the way its colour does. A stroke writes its height into the
## layer as it goes rather than into the buffer, so the height is read from the
## layer with no stroke laid over it.
##
## Knows nothing of where the map takes a chunk: [method resample] is handed
## the part of the target each source reaches and, for a source a stroke is
## laid over, the part of it the gather reads. [method reached] is the one
## piece of that geometry it keeps, because what it answers is the rectangle a
## gather is dispatched over.
##
## **Linear light, and every texel under a shrink.** The paint's colour is
## resampled through the document's transfer curve, `SaResampleKernel.curve_for`,
## and a map that shrinks the layer averages a box of the texels under each
## destination texel, which reaches further past a source than the bilinear
## read's half texel. [method reach] answers how far, for the geometry that
## decides which sources a region reads and how much of a source a stroke is
## laid over.
##
## Named only by `SaLiveTransform`.
class_name SaLiveKernel
extends RefCounted

## The kernel file beside this one.
const SHADER := "live_transform"
## The least area, in square pixels, a quad shares with a chunk's texel centres
## for the chunk to be reached. Above nought, because a quad that meets the
## centres along an edge alone, as a quarter turn's does, reads nothing there.
const SHARED := 1.0e-4
## The widest box, in source texels along an axis, the kernel averages, which is
## `SA_FOOTPRINT_MOST` of `transform_read.gmacs`.
const FOOTPRINT_MOST := 128.0
## How far past a texel a bilinear read reaches, half a texel.
const BILINEAR_REACH := 0.5

## The map from where a layer's paint shows back to the layer's own pixels.
var _inverse := Basis.IDENTITY
## The rectangle of the layer's own pixels a tap is read inside.
var _kept := Rect2()
var _compute: SaCompute = null
## The same kernels built for the height's format, made on the first height.
var _heights: SaCompute = null
## A 1 by 1 coverage of one, bound where the layer's mask hides nothing.
var _whole: SaTexture = null
## The layer's paint with the stroke over it at one held position, which the
## gather reads in its place, made at the first stroke and kept.
var _scratch: SaTexture = null


## A kernel reading through *inverse* inside *kept*, with the compute and the
## textures of *before* when there is one.
func _init(inverse: Basis = Basis.IDENTITY, kept: Rect2 = Rect2(), before: SaLiveKernel = null) -> void:
    _inverse = inverse
    _kept = kept
    if before != null:
        _compute = before._compute
        _heights = before._heights
        _whole = before._whole
        _scratch = before._scratch


## Resamples *region* of *chunk*'s field *field_id*, the chunk at *grid_pos*,
## from that field of *layer*'s chunks at the positions *parts* holds, each over
## the part of the region it reaches: set to *rest*, each source's share added,
## and for the paint divided through by its alpha. The paint is weighted by the
## layer's mask when *masked*, which is the cache, and by its own alpha alone
## for the bake, which moves the mask as a field of its own, at its rest. A
## source *stroke* holds a stroke at is read with the stroke over it, over the
## part of the source *under* holds for it. The height, lazy, is given to
## *chunk* only where a source holds one, [method _raised].
func resample(
    chunk: SaChunk,
    layer: SaLayer,
    field_id: StringName,
    grid_pos: Vector2i,
    region: Rect2i,
    parts: Dictionary[Vector2i, Rect2i],
    stroke: SaLayer,
    under: Dictionary[Vector2i, Rect2],
    masked: bool,
    rest: float
) -> void:
    var height := field_id == SaFieldSpec.HEIGHT
    if height and not _raised(chunk, layer, parts):
        return
    var target := chunk.field(field_id)
    var compute := _height_compute() if height else _use(target.format)
    var origin := Vector2(grid_pos * SaLayer.CHUNK_SIZE)
    var document := layer.get_parent() as SaDocument
    var curve := SaResampleKernel.curve_for(document.color_space if document != null else null, field_id)
    _run(compute, "live_transform_clear", [target, target, _whole], region, origin, Vector2.ZERO, rest, curve)
    for held: Vector2i in parts:
        var source := layer.get_field(held, field_id)
        var laid := stroke.get_field(held) if stroke != null else null
        if laid != null:
            source = _under_stroke(layer, held, source, laid, under[held])
            _use(target.format)
        if source == null:
            continue
        var cover := SaCompositor.coverage_at(layer, held) if masked else null
        var images: Array[SaTexture] = [target, source, cover if cover != null else _whole]
        var from := Vector2(held * SaLayer.CHUNK_SIZE)
        _run(compute, "live_transform_gather", images, parts[held], origin, from, rest, curve)
    if field_id == SaFieldSpec.ALBEDO:
        _run(compute, "live_transform_settle", [target, target, _whole], region, origin, Vector2.ZERO, 0.0, curve)


## Whether *chunk* holds a height to resample into: one it held already, which
## the region is written back over, or a new one, blank, where a source *parts*
## holds has a height of *layer*'s. A chunk nothing raises stays without one.
func _raised(chunk: SaChunk, layer: SaLayer, parts: Dictionary[Vector2i, Rect2i]) -> bool:
    if chunk.has_field(SaFieldSpec.HEIGHT):
        return true
    for held: Vector2i in parts:
        if layer.get_field(held, SaFieldSpec.HEIGHT) != null:
            chunk.add_sparse_field(SaFieldSpec.height())
            return true
    return false


## The positions inside *grid* where the polygon *quad* holds a texel centre,
## each with the chunk-local rectangle of the quad's bounding box there, which
## the gather is dispatched over. A quad that only touches a chunk's outer half
## texel holds none of its centres, so no chunk is made for it.
static func reached(quad: PackedVector2Array, grid: Rect2i) -> Dictionary[Vector2i, Rect2i]:
    var found: Dictionary[Vector2i, Rect2i] = {}
    if quad.size() != 4:
        return found
    var box := Rect2(quad[0], Vector2.ZERO)
    for corner in quad:
        box = box.expand(corner)
    var side := SaLayer.CHUNK_SIZE
    var pixels := Rect2i(Vector2i(box.position.floor()), Vector2i.ZERO).expand(Vector2i(box.end.ceil()))
    var first := Vector2i((box.position / side).floor()).max(grid.position)
    var last := Vector2i((box.end / side).floor()).min(grid.end - Vector2i.ONE)
    for y in range(first.y, last.y + 1):
        for x in range(first.x, last.x + 1):
            var cell := Rect2i(Vector2i(x, y) * side, Vector2i(side, side))
            var part := cell.intersection(pixels)
            if not part.has_area():
                continue
            # The square through the chunk's outermost texel centres.
            var centres := Rect2(cell).grow(-0.5)
            var square := PackedVector2Array(
                [
                    centres.position,
                    Vector2(centres.end.x, centres.position.y),
                    centres.end,
                    Vector2(centres.position.x, centres.end.y)
                ]
            )
            var shared := 0.0
            for polygon in Geometry2D.intersect_polygons(quad, square):
                shared += absf(_area(polygon))
            if shared <= SHARED:
                continue
            found[Vector2i(x, y)] = Rect2i(part.position - cell.position, part.size)
    return found


## The signed area of *polygon*.
static func _area(polygon: PackedVector2Array) -> float:
    var twice := 0.0
    for i in range(polygon.size()):
        twice += polygon[i].cross(polygon[(i + 1) % polygon.size()])
    return twice * 0.5


## How far past *area*, in the layer's own pixels, a destination texel's read
## reaches: the half texel of a bilinear read, or where the map shrinks the
## layer half the widest box it averages at a corner of *area*, with a texel to
## spare, because a perspective's shrink can grow between the corners.
func reach(area: Rect2) -> float:
    if absf(_inverse.determinant()) <= 0.0:
        return BILINEAR_REACH
    var forward := _inverse.inverse()
    var widest := 1.0
    for corner: Vector2 in [area.position, Vector2(area.end.x, area.position.y), area.end, Vector2(area.position.x, area.end.y)]:
        var h := forward * Vector3(corner.x, corner.y, 1.0)
        if h.z <= 0.0:
            return FOOTPRINT_MOST * 0.5 + 1.0
        var shown := Vector2(h.x, h.y) / h.z
        var at := _back(shown)
        var along_x := _back(shown + Vector2.RIGHT) - at
        var along_y := _back(shown + Vector2.DOWN) - at
        widest = maxf(widest, maxf(Vector2(along_x.x, along_y.x).length(), Vector2(along_x.y, along_y.y).length()))
    if widest <= 1.0:
        return BILINEAR_REACH
    return minf(widest, FOOTPRINT_MOST) * 0.5 + 1.0


## Where the inverse map takes the shown position *shown* in the layer's own
## pixels, with the kernel's guard at the horizon.
func _back(shown: Vector2) -> Vector2:
    var h := _inverse * Vector3(shown.x, shown.y, 1.0)
    return Vector2(h.x, h.y) / maxf(h.z, 1.0e-6)


## The layer's paint at *held*, *field*, null where the layer holds none yet,
## with the stroke *laid* over it in the scratch, as the commit will leave it:
## the buffer's blend mode at the stroke's opacity in the document's space.
## Only over *area* of the chunk, in the layer's own pixels, and as far beyond
## it as a read takes, [method reach], with a margin.
func _under_stroke(layer: SaLayer, held: Vector2i, field: SaTexture, laid: SaTexture, area: Rect2) -> SaTexture:
    var document := layer.get_parent() as SaDocument
    var side := SaLayer.CHUNK_SIZE
    if _scratch == null or _scratch.format != laid.format:
        _scratch = SaTexture.new(Vector2i(side, side), laid.format)
    var from := Vector2(held * side)
    var box := area.grow(reach(area) + 1.5)
    var corner := Vector2i((box.position - from).floor())
    var need := Rect2i(corner, Vector2i.ZERO).expand(Vector2i((box.end - from).ceil()))
    need = need.intersection(Rect2i(0, 0, side, side))
    if not need.has_area():
        return null
    if field != null and field.format == laid.format:
        var at := Vector3(need.position.x, need.position.y, 0)
        var extent := Vector3(need.size.x, need.size.y, 1)
        GlobalShaderCompiler.get_rd().texture_copy(field.rid, _scratch.rid, at, at, extent, 0, 0, 0, 0)
    else:
        _run(_use(laid.format), "live_transform_clear", [_scratch, _scratch, _whole], need, Vector2.ZERO, Vector2.ZERO)
    var compositor := document.compositor
    if compositor != null:
        var mode := document.stroke_layer.blend_mode
        compositor.composite_chunk(_scratch, laid, mode, document.stroke_opacity, Vector2.ZERO, document.color_space, 1.0, need)
    return _scratch


## Makes the compute and the coverage of one on first use, sets the compute to
## write *format*, and answers it.
func _use(format: int) -> SaCompute:
    if _compute == null:
        _compute = SaCompute.new(SHADER)
    _cover_whole()
    _compute.use_storage_format(format)
    return _compute


## The compute built for the height's format, made on first use.
func _height_compute() -> SaCompute:
    if _heights == null:
        _heights = SaCompute.new(SHADER)
        _heights.use_storage_format(SaFieldSpec.HEIGHT_FORMAT)
    _cover_whole()
    return _heights


## Makes the coverage of one on first use.
func _cover_whole() -> void:
    if _whole == null:
        _whole = SaTexture.new(Vector2i.ONE, SaSelection.FORMAT)
        _whole.clear(Color(1.0, 1.0, 1.0, 1.0))


## One dispatch of *kernel* of *compute* over *region* of the target, the first
## of *images*, the source and the mask after it. *origin* is where the target
## chunk starts in the document and *from* where the source chunk does. *rest*
## is what the field reads where the layer holds nothing, nought for the paint.
## *curve* is the field's transfer curve, the identity for the mask and the
## height.
func _run(
    compute: SaCompute,
    kernel: String,
    images: Array[SaTexture],
    region: Rect2i,
    origin: Vector2,
    from: Vector2,
    rest := 0.0,
    curve := SaResampleKernel.IDENTITY
) -> void:
    for binding in range(images.size()):
        compute.set_texture(binding, images[binding].rid)
    var m := _inverse
    var data := PackedFloat32Array([m.x.x, m.y.x, m.z.x, rest, m.x.y, m.y.y, m.z.y, 0.0, m.x.z, m.y.z, m.z.z, 0.0])
    data.append_array([region.position.x, region.position.y, region.size.x, region.size.y, origin.x, origin.y, from.x, from.y])
    data.append_array([_kept.position.x, _kept.position.y, _kept.end.x, _kept.end.y])
    data.append_array([curve.x, curve.y, curve.z, curve.w])
    compute.set_push_constant_float_array(data)
    compute.dispatch_kernel(kernel, SaCompute.groups_for(region.size.x), SaCompute.groups_for(region.size.y), 1)
