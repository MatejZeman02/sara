## Image > Image Size: scaling every layer's texels into a rebuilt chunk grid,
## as one undoable step.
##
## The transform tool's scale gesture resamples through `resample` in
## `shaders/compute/transform.gmacs`, and this pass is that kernel driven by a
## dialog instead of by eight handles. No kernel is new here.
##
## **A pass beside the crop rather than a mode inside it.** `core/image/sa_crop.gd`
## re-tiles: every destination texel is some source texel moved, so it copies
## overlaps with `shift`. A resample has no such texel, every destination is read
## between four sources, and the two walks share only the shape of the loop.
##
## **The source is one stitched texture per field, not the chunks.** A bilinear
## read needs the four texels around a position, and at a chunk border two of
## them live in a neighbour that is not bound, so reading the chunks directly
## puts a seam every 256 pixels. `SaTransform` answers the same question the same
## way and its header says why. The cost is one texture the size of the layer's
## painted bounds, held for the length of the pass and released with it, which is
## the old canvas at worst and usually less.
##
## **The dispatch walks the destination and allocates nothing it does not
## write.** A destination chunk whose source rectangle misses the layer's painted
## bounds is never created, so an off-canvas region and the empty half of a grow
## both stay unallocated, which is hard rule 3 rather than a special case. Each
## chunk is dispatched over its own texels and nothing wider, which is rule 2.
##
## Undo restores the size and the chunks together, the way `SaCrop` does and for
## the same reason: either alone is a document that disagrees with itself.
##
## **The walk takes a map, and a scale is one map.** Image > Flip and Rotate are
## `SaOrient`, which hands `resample_by` and `mapped_chunks` a flip or a quarter turn
## with the filter on nearest, so every destination texel reads one source texel
## at its centre and the copy is exact. One walk serves the three, because the
## two ways a map like that differs from a scale, a read that runs backwards and
## a canvas whose sides swap, are both answered by the bounding box of two
## mapped corners rather than by dividing by the scale.
class_name SaResample
extends RefCounted

## What the undo menu calls this. Not "Canvas Size", which is the canvas grow and
## takes nothing away from the picture, and not "Crop": a painter looking at the
## undo stack is trying to find the thing they just did by its name.
const ACTION_NAME := "Image Size"

## The same ceiling File > New and Canvas Size use.
const MAX_DIMENSION := 16384

var _document: SaDocument
## `SaResampleKernel.Filter`, so the tool and the dialog cannot drift into two
## spellings of bilinear.
var filter: int = SaResampleKernel.Filter.BILINEAR

var _resample_compute: SaCompute = null
var _shift_compute: SaCompute = null
var _blank_compute: SaCompute = null
## How many chunks this object's steps have worked out for layers, as
## `SaCrop.chunks_made` counts them. Read by a suite.
var chunks_made := 0


func _init(document: SaDocument) -> void:
    _document = document


## The height that keeps *from*'s aspect ratio at width *width*.
##
## Rounded rather than truncated, and floored at one, because a 1920 by 1080
## document taken to width 3 is two thirds of a row of pixels and a document of
## height zero has no inverse for the map below.
static func locked_height(from: Vector2i, width: int) -> int:
    if from.x <= 0:
        return maxi(1, from.y)
    return clampi(roundi(float(width) * float(from.y) / float(from.x)), 1, MAX_DIMENSION)


## The width that keeps *from*'s aspect ratio at height *height*.
static func locked_width(from: Vector2i, height: int) -> int:
    if from.y <= 0:
        return maxi(1, from.x)
    return clampi(roundi(float(height) * float(from.x) / float(from.y)), 1, MAX_DIMENSION)


## Scales the whole document to *size*. True when it happened.
##
## False for a size that is not a canvas, and false for the size the document
## already is: recording a step there would put an undo on the stack that changes
## nothing when it fires, which is the rule `SaCrop._reshape_to` states.
func resample_to(size: Vector2i) -> bool:
    if _document == null:
        return false
    if size == _document.canvas_size:
        return false
    var scale := Vector2(float(size.x) / float(_document.canvas_size.x), float(size.y) / float(_document.canvas_size.y))
    return resample_by(size, Transform2D(Vector2(scale.x, 0.0), Vector2(0.0, scale.y), Vector2.ZERO), ACTION_NAME)


## The whole document through *map* into a canvas of *size*, as one history step
## called *action*. True when it happened.
##
## *map* sends a document pixel of the canvas as it stands to the one it lands
## on, and keeps to the axes: a scale, a flip or a quarter turn. Any other turn
## would need four mapped corners where `_source_rect` and `_reached` read two,
## and nothing asks for one. *source* goes to the view as `SaCrop._apply`'s does,
## the part of the old document the new one is made of: a flip passes the whole
## canvas so the view stays where it was, and the empty default has the view fit
## the document afresh, which is what a new size wants.
##
## No check that the size changed, because a flip keeps it and is still a step.
## `resample_to` refuses the size the document already is on its own line.
func resample_by(size: Vector2i, map: Transform2D, action: String, source: Rect2i = Rect2i()) -> bool:
    if _document == null:
        return false
    if size.x <= 0 or size.y <= 0 or size.x > MAX_DIMENSION or size.y > MAX_DIMENSION:
        return false
    if _resample() == null:
        return false

    # Keyed by Variant, because a typed key refuses a layer that was freed.
    var before: Dictionary[Variant, Dictionary] = {}
    var layers := _paint_layers()
    for layer: SaLayer in layers:
        before[layer] = layer.chunks.duplicate()

    # Asked before the walk, for the reason `SaDrawnLayer.Remap` gives.
    var geometry := SaDrawnLayer.Remap.new(layers, map, action)

    var after: Dictionary[Variant, Dictionary] = {}
    for layer: SaLayer in before:
        if not geometry.moves_chunks(layer):
            after[layer] = {}
            continue
        var twin := SaCrop.done_user(layer, after)
        if twin != null:
            after[layer] = after[twin]
            continue
        after[layer] = mapped_chunks(layer.chunks, layer.schema, layer.resolution_scale, map, size)
        chunks_made += after[layer].size()

    # A group's mask and an attached filter's hold chunks of their own, which
    # the layer walk never reaches. They go with the picture on the same map,
    # opening every chunk at the mask's rest so what the mapped coverage does
    # not reach reads what it read before.
    var masks_before: Dictionary[Variant, Dictionary] = {}
    for mask: SaMask in SaCrop.own_masks(_document):
        masks_before[mask] = mask.chunks.duplicate()
    var masks_after: Dictionary[Variant, Dictionary] = {}
    for mask: SaMask in masks_before:
        masks_after[mask] = mapped_chunks(mask.chunks, SaMask.schema(), 1.0, map, size, SaCrop.at_rest(mask))

    # The source stays as it is at every swap, because a flip's undo is a flip
    # of the same canvas and a new size's undo is a new size again.
    var exchange := SaCanvasExchange.new(_document, _document.canvas_size, before, masks_before, _put_back.bind(geometry), source)
    _apply(size, after, masks_after, source, geometry)
    exchange.commit(action)
    return true


## The chunk dictionary a store of *chunks* should hold once its picture has
## gone through *map*, in document pixels, into a canvas of *size*. The store
## is a layer's, with its *schema* and its *density*, or an own mask's, and
## *blanks* is what its fields read where no chunk is, which for a mask is its
## rest and overrides what a source chunk says. `SaOrient` calls this for the
## layers a Layer menu flip moves.
##
## **Neither walk here is an [SaChunkWalk], and the reasons differ.** The stitch
## below writes every chunk into one texture the size of the painted bounds, so
## its destination is not a chunk and there is no per-chunk rectangle to
## narrow. This one does walk the destination grid a chunk at a time, but each
## stop dispatches through `SaResampleKernel`, the one writer of that kernel's
## push constant, which owns the extent as well as the push constant. Handing
## that to the walk would mean two files deciding how wide a resample
## dispatches, which is the thing the walk exists to stop.
##
## **Everything below is in the layer's own texels.** A double resolution layer
## holds `resolution_scale` texels to a document pixel, so its
## stitch, its bounds and every destination chunk's origin are that many times
## the document's, and the map's linear part is the same in either unit. The layer
## is read at its own density and written back at it, never through the
## document's resolution.
func mapped_chunks(
    chunks: Dictionary[Vector2i, SaChunk],
    schema: Array[SaFieldSpec],
    density: float,
    map: Transform2D,
    size: Vector2i,
    blanks: Dictionary[StringName, Color] = {}
) -> Dictionary[Vector2i, SaChunk]:
    var pixels := _painted_bounds(chunks)
    if pixels.size.x <= 0 or pixels.size.y <= 0:
        return {}
    var low := SaCrop.texels(pixels.position, density)
    var bounds := Rect2i(low, SaCrop.texels(pixels.end, density) - low)
    var stitched := _stitch(chunks, bounds, blanks)
    if stitched.is_empty():
        return {}

    # The map in the layer's own texels: the linear part is the same in either
    # unit and the shift is `density` texels to the pixel, which is what puts a
    # double resolution layer's flip about its own 2W rather than about W.
    var forward := Transform2D(map.x, map.y, map.origin * density)
    var back := _axis_inverse(forward)
    var edge := SaCrop.texels(Vector2i(SaLayer.CHUNK_SIZE, SaLayer.CHUNK_SIZE), density).x
    # Each chunk the layer holds, rather than the box round all of them: two
    # strokes in opposite corners have the whole canvas between them, and a
    # chunk of the new grid that reads only that gap would be made to hold
    # nothing.
    var tiles: Array[Rect2i] = []
    for grid_pos: Vector2i in chunks:
        if chunks[grid_pos] != null:
            tiles.append(Rect2i(grid_pos * edge, Vector2i(edge, edge)))
    var fresh: Dictionary[Vector2i, SaChunk] = {}
    for grid_pos: Vector2i in SaLayer.grid_positions(size):
        var destination := Rect2i(grid_pos * edge, Vector2i(edge, edge))
        var reads := _source_rect(destination, back)
        if not tiles.any(func(tile: Rect2i) -> bool: return reads.intersects(tile)):
            continue
        var chunk := SaChunk.create(schema, density)
        for field_id: StringName in blanks:
            chunk.blanks[field_id] = blanks[field_id]
        # A lazy field, height, comes along where the layer holds any of it,
        # since the stitch is what reads it and the kernel below scales it.
        for field_id: StringName in stitched:
            var spec := SaFieldSpec.find(schema, field_id)
            if spec != null and spec.lazy and not chunk.has_field(field_id):
                chunk.add_sparse_field(spec)
        # Through the kernel rather than `texture_clear`, for the reason
        # `SaTransform` records: a clear is a transfer and the resample is
        # compute, and the two are not ordered against each other, so a chunk
        # cleared that way kept whatever last owned the memory.
        _blank_chunk(chunk)
        _resample_into(chunk, stitched, destination.position, bounds, forward, back)
        fresh[grid_pos] = chunk
    return fresh


## The inverse of *map*, which keeps to the axes, worked a component at a time.
##
## Not `Transform2D.affine_inverse`, which divides by the determinant, so a scale
## of 1.5 came back as 1.5 over 2.25 rather than one over 1.5. The two differ in
## the last bit, and `_source_rect` floors and ceils what this gives: at a
## destination edge that lands on a whole source texel, the last bit decides
## whether the read reaches the next chunk and allocates one. A flip or a turn
## is exact either way, and Image Size keeps the arithmetic it had.
static func _axis_inverse(map: Transform2D) -> Transform2D:
    var x := map.x
    var y := map.y
    var linear := Transform2D(Vector2(1.0 / x.x, 0.0), Vector2(0.0, 1.0 / y.y), Vector2.ZERO)
    if x.x == 0.0 and y.y == 0.0:
        # A quarter turn: x lands on y and y on x, so each comes back from the
        # other, and a turn with a pull is still answered.
        linear = Transform2D(Vector2(0.0, 1.0 / y.x), Vector2(1.0 / x.y, 0.0), Vector2.ZERO)
    return Transform2D(linear.x, linear.y, -linear.basis_xform(map.origin))


## The source rectangle *destination* reads, in the layer's old texels, through
## *back*, the inverse of the map.
##
## **No skirt for the filter, deliberately.** A bilinear read at the far edge of
## the picture does reach one texel past this rectangle, but growing it by that
## texel would allocate a ring of chunks all the way round: a doubled 256 tile
## covers four chunks of the new grid and would make nine, the five extra ones
## holding nothing a source texel maps into. The blend at the picture's edge
## happens inside the last chunk that owns paint, and the chunk after it is
## empty either way, so the skirt belongs to the kernel's reads and not to the
## question of what exists.
##
## Two corners rather than four, because a map that keeps to the axes sends a
## rectangle's opposite corners to the opposite corners of another one. The
## lesser and the greater of each pair, because a flip sends the first corner
## to the far side.
static func _source_rect(destination: Rect2i, back: Transform2D) -> Rect2i:
    var one := back * Vector2(destination.position)
    var two := back * Vector2(destination.end)
    var first := one.min(two)
    var last := one.max(two)
    var from := Vector2i(floori(first.x), floori(first.y))
    var to := Vector2i(ceili(last.x), ceili(last.y))
    return Rect2i(from, to - from)


## The document rectangle *layer*'s chunks cover, which is the picture this pass
## has to read and nothing wider.
##
## The chunk grid rather than the painted texels, for the reason the crop tool's
## box gives: finding the first non-transparent texel is a readback of every
## chunk, which is what hard rule 1 exists to prevent.
static func _painted_bounds(chunks: Dictionary[Vector2i, SaChunk]) -> Rect2i:
    var edge := SaLayer.CHUNK_SIZE
    var found := Rect2i()
    var first := true
    for grid_pos: Vector2i in chunks:
        if chunks[grid_pos] == null:
            continue
        var tile := Rect2i(grid_pos * edge, Vector2i(edge, edge))
        found = tile if first else found.merge(tile)
        first = false
    return found


## Every field of *layer* over *bounds*, in the layer's texels, as one texture
## each, so the resample reads across chunk borders without a seam.
func _stitch(
    chunks: Dictionary[Vector2i, SaChunk], bounds: Rect2i, blanks: Dictionary[StringName, Color] = {}
) -> Dictionary[StringName, SaTexture]:
    var stitched: Dictionary[StringName, SaTexture] = {}
    for grid_pos: Vector2i in chunks:
        var source: SaChunk = chunks[grid_pos]
        if source == null:
            continue
        var edge := source.pixel_size()
        var origin := grid_pos * edge
        for field_id: StringName in source.fields:
            var from: SaTexture = source.fields[field_id]
            if from == null or not from.rid.is_valid():
                continue
            var into: SaTexture = stitched.get(field_id, null)
            if into == null:
                into = SaTexture.new(bounds.size, from.format)
                # A hole in the grid reads as the field's blank, which is what
                # the layer answers there: no paint, and a mask fully shown.
                var hole: Color = blanks.get(field_id, source.blanks.get(field_id, SaFieldSpec.NO_PAINT))
                _blank_texture(into, Rect2i(Vector2i.ZERO, bounds.size), hole)
                stitched[field_id] = into
            _shift_texture(from, into, Vector2i.ZERO, origin - bounds.position, Vector2i(edge, edge))
    return stitched


## One chunk's worth of resample: every field read out of *stitched* through
## *back*, the inverse of *forward*, which is the same push constant the
## transform tool fills.
## **Every field goes through, not only the colour ones.** The transform tool
## skips a non-colour field because it lifts a selected region and a height field
## has no lift, but here the whole document moves and a field left at the old
## size would disagree with the albedo beside it. The mask is the second field
## Sara ships, and what changed for it is where the kernel may write, below.
##
## *at* is the chunk's origin and *bounds* the stitch's, both in the layer's texels.
func _resample_into(
    into: SaChunk,
    stitched: Dictionary[StringName, SaTexture],
    at: Vector2i,
    bounds: Rect2i,
    forward: Transform2D,
    back: Transform2D
) -> void:
    var compute := _resample()
    if compute == null:
        return
    var edge := into.pixel_size()
    # The map is handed over already inverted, so the kernel does no matrix work
    # per texel. A row of the kernel is a row of the inverse, which is the two
    # columns' same component, and the translation is the inverse's own less
    # where the stitched texture's (0, 0) sits. Every map here is affine, so the
    # kernel's third row is (0, 0, 1) and the divide is by one.
    var rows: Array = [
        Vector2(back.x.x, back.y.x),
        Vector2(back.x.y, back.y.y),
        back.origin - Vector2(bounds.position),
        Vector3(0.0, 0.0, 1.0),
    ]
    var world := Vector2(at)
    var nearest := filter == SaResampleKernel.Filter.NEAREST
    var whole := Rect2i(0, 0, edge, edge)
    var reached := _reached(whole, world, bounds, forward, nearest)
    for field_id: StringName in into.fields:
        # The kernel writes zero wherever its read misses the source, which is
        # no paint and so right for colour. A field with a blank of its own is
        # written only where the read lands, and keeps its blank elsewhere.
        var local := reached if into.blanks.has(field_id) else whole
        var source: SaTexture = stitched.get(field_id, null)
        var curve := SaResampleKernel.curve_for(_document.color_space if _document != null else null, field_id)
        SaResampleKernel.dispatch(compute, into.fields[field_id], source, rows, world, local, nearest, curve)


## The part of *whole*, a destination chunk at *world*, whose read lands on the
## stitched source, which is the texels the kernel gives a value other than its
## own zero.
##
## A bilinear read lands when any of its four texels is inside, so it reaches
## half a source texel past *bounds*, and the read renormalises by the weight
## that was inside, so what it gives there is the edge's value. A nearest read
## lands only inside. Drawn a hundredth of a texel tight, because this runs in
## doubles and the kernel in floats, and a texel the two disagree about is
## better left at the blank than written as zero. The bounds go through
## *forward* by two corners, for the reason `_source_rect` gives.
static func _reached(whole: Rect2i, world: Vector2, bounds: Rect2i, forward: Transform2D, nearest: bool) -> Rect2i:
    var skirt := 0.0 if nearest else 0.5
    var tight := 0.01
    var one := forward * (Vector2(bounds.position) - Vector2(skirt, skirt))
    var two := forward * (Vector2(bounds.end) + Vector2(skirt, skirt))
    var low := one.min(two) - Vector2(0.5, 0.5) - world
    var high := one.max(two) - Vector2(0.5, 0.5) - world
    var from := Vector2i(floori(low.x + tight) + 1, floori(low.y + tight) + 1)
    var to := Vector2i(ceili(high.x - tight), ceili(high.y - tight))
    return Rect2i(from, to - from).intersection(whole)


## Moves *size* texels from *from*'s *at* to *into*'s *to*, through the crop
## kernel's own `shift`.
func _shift_texture(from: SaTexture, into: SaTexture, at: Vector2i, to: Vector2i, size: Vector2i) -> void:
    var compute := _shift()
    if compute == null or size.x <= 0 or size.y <= 0:
        return
    compute.use_storage_format(into.format)
    compute.set_texture(0, from.rid)
    compute.set_texture(1, into.rid)
    compute.set_push_constant_float_array(PackedFloat32Array([to.x, to.y, at.x, at.y, size.x, size.y, 0.0, 0.0]))
    compute.dispatch_kernel("shift", SaCompute.groups_for(size.x), SaCompute.groups_for(size.y), 1)


## Every field of a fresh chunk set to its own blank, which `SaChunk.blanks`
## names and this file does not: zero is no paint for a colour field and fully
## hidden for a mask.
func _blank_chunk(chunk: SaChunk) -> void:
    var edge := chunk.pixel_size()
    for field_id: StringName in chunk.fields:
        var blank: Color = chunk.blanks.get(field_id, SaFieldSpec.NO_PAINT)
        _blank_texture(chunk.fields[field_id], Rect2i(0, 0, edge, edge), blank)


func _blank_texture(target: SaTexture, local: Rect2i, value: Color) -> void:
    var compute := _blank()
    if compute == null or target == null or not target.rid.is_valid():
        return
    if local.size.x <= 0 or local.size.y <= 0:
        return
    compute.use_storage_format(target.format)
    compute.set_texture(0, target.rid)
    compute.set_push_constant_float_array(
        PackedFloat32Array([value.r, value.g, value.b, value.a, local.position.x, local.position.y, local.size.x, local.size.y])
    )
    compute.dispatch_kernel("blank_region", SaCompute.groups_for(local.size.x), SaCompute.groups_for(local.size.y), 1)


## Every layer that stores texels, as `SaCrop` counts them: a generated layer
## evaluates a kernel over whatever the canvas is now, so the new size is all it
## needs.
func _paint_layers() -> Array[SaLayer]:
    var found: Array[SaLayer] = []
    _collect_layers(_document, found)
    return found


func _collect_layers(from: Node, into: Array[SaLayer]) -> void:
    for child: Node in from.get_children():
        var layer := child as SaLayer
        if layer == null:
            continue
        if layer != _document.stroke_layer and not layer.is_generated():
            into.append(layer)
        _collect_layers(layer, into)


## Puts *size* and *chunks* on the document and tells everything that draws it.
##
## The selection is dropped rather than scaled, which is `SaCrop`'s answer and
## the same reasoning: its chunks are in the old coordinates and a selection that
## survived a halving while pointing at twice the area is worse than none.
## *source* rides on `SaDocument.resize_source` for the length of the emit, as
## `SaCrop._apply` sets it, so no later resize can read a stale one.
func _apply(
    size: Vector2i,
    chunks: Dictionary[Variant, Dictionary],
    masks: Dictionary[Variant, Dictionary],
    source: Rect2i,
    geometry: SaDrawnLayer.Remap = null
) -> void:
    # The brush's side scales with the picture, so the brush keeps its size against
    # what is painted, a side a crop kept stays in proportion and a turn keeps it.
    var side := _document.brush_side * minf(size.x, size.y) / minf(_document.canvas_size.x, _document.canvas_size.y)
    _document.canvas_size = size
    _document.brush_side = side
    for layer: SaLayer in chunks:
        # Emptied and refilled by key rather than assigned, because
        # `SaLayer.chunks` is a typed dictionary and refuses a plain one, which
        # is the silent no-op `SaCrop`'s own comment records.
        var wanted := SaTyped.chunks(chunks[layer])
        layer.chunks.clear()
        for grid_pos: Vector2i in wanted:
            layer.chunks[grid_pos] = wanted[grid_pos]
        layer.mark_all_unresolved()
    if geometry != null:
        geometry.swap()
    SaCrop.put_masks(_document, masks)
    _document.selection.deselect_and_forget()
    _document.modified = true
    _document.update_caches()
    _document.invalidate_all_allocated_chunks()
    _document.resize_source = source
    EventBus.document_resized.emit(_document, size)
    _document.resize_source = Rect2i()
    _document.document_changed.emit()


## What `SaCanvasExchange` puts back at an undo or a redo.
func _put_back(
    size: Vector2i,
    chunks: Dictionary[Variant, Dictionary],
    masks: Dictionary[Variant, Dictionary],
    source: Rect2i,
    _projection: SaProjection,
    geometry: SaDrawnLayer.Remap
) -> void:
    _apply(size, chunks, masks, source, geometry)


func _resample() -> SaCompute:
    if _resample_compute == null and GlobalShaderCompiler.get_rd() != null:
        _resample_compute = SaCompute.new("transform")
    return _resample_compute


func _shift() -> SaCompute:
    if _shift_compute == null and GlobalShaderCompiler.get_rd() != null:
        _shift_compute = SaCompute.new("crop")
    return _shift_compute


func _blank() -> SaCompute:
    if _blank_compute == null and GlobalShaderCompiler.get_rd() != null:
        _blank_compute = SaCompute.new("blank")
    return _blank_compute
