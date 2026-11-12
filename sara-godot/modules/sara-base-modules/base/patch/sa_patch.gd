## The patch tool's fill: what the selection covers, drawn again out of the
## picture around it, by one of two methods.
##
## **Texture**, the default, is PatchMatch (Barnes, Shechtman, Finkelstein and
## Goldman, SIGGRAPH 2009) inside the coarse-to-fine completion of Wexler,
## Shechtman and Irani (IEEE PAMI 2007), the family Krita's Smart Patch tool
## belongs to. It copies patches of the picture from around the selection, so a
## blemish across an edge or in a texture comes back as that edge or texture.
## `sa_patch_match.gd` beside this file holds it and says where it departs from
## Krita's.
##
## **Smooth** is the method the tool began with, a normalised convolution that
## carries colour and alpha inwards from the ring and smooths them. It loses a
## blemish in a soft gradient better than any copy can, because a gradient has
## no patch elsewhere that matches it, and it blurs one that lies across an edge.
##
## The shape of one patch:
##
## 1. The work rectangle is the selection's bounds grown by [constant RING] for
##    Smooth, or by its own size for Texture, which needs patches to copy, and
##    clipped to the canvas either way (see [method work_for]).
## 2. `patch_gather` reads the layer's chunks under that rectangle into a flat
##    pair of textures, the colour premultiplied and a confidence that is one
##    outside the selection and below one inside it.
## 3. Smooth runs `patch_sweep` [method passes_for] times, ping-ponging between
##    two such pairs, each pass advancing the front one texel. Texture hands the
##    pair to `sa_patch_match.gd`, which redraws the hole in place.
## 4. `patch_scatter` writes the result back into the layer's chunks in
##    proportion to the mask, and the whole thing is one history step.
##
## **The scratch pair is flat rather than chunks, and that is the one real
## decision here.** Every other pass in the tree writes a chunk from that same
## chunk, so [SaChunkWalk] can decide its rectangle and be done. A normalised
## convolution reads its eight neighbours and a patch reads eighty, and a texel
## on a chunk seam reads across it: a chunked ping-pong would need neighbour
## bindings at every stop of every pass. One pair of textures over the rectangle
## the tool was going to dispatch over anyway is the cheaper door. It is
## scratch, not storage: the canvas stays sparse chunks, the pair is allocated
## for the operation and released with it, and nothing is read back.
##
## The gather is a loop of its own because its destination is not the chunk it
## reads, which is the one thing the walk cannot express. The scatter is a walk,
## because it is a pass that writes a chunk through the selection.
##
## In the base module beside the tool it serves, the way `sa_wand.gd` and
## `sa_gradient.gd` are, so nothing in the skeleton knows this exists.
class_name SaPatch
extends RefCounted

## The exemplar fill, reached by path the way the tool reaches this file.
const SaPatchMatchScript = preload("res://modules/sara-base-modules/base/patch/sa_patch_match.gd")

## The two ways of drawing the hole again, in the order the tool's Method row
## offers them.
enum Method { TEXTURE, SMOOTH }

## What the undo menu calls a patch.
const ACTION_NAME := "Patch"

## How far outside the selection the fill is drawn from. Two texels rather than
## one, because the 3 by 3 sweep reads one and a second gives the tent
## something to lean on where the selection runs along a chunk seam.
const RING: int = 2

## How many sweeps a patch runs, and the floor and ceiling on that count.
##
## The front advances one texel a pass and a hole closes from both sides, so
## half the rectangle's longer edge closes it, and the rest settle what was
## laid down. Two dozen is the floor because a blemish smaller than that still
## wants the passes that settle what was laid. The
## ceiling is what stops a painter who selected half the canvas from waiting on
## a thousand dispatches for a fill that would be a smear anyway.
const MIN_PASSES: int = 24
const MAX_PASSES: int = 192

## How fast confidence saturates behind the front. At one, a texel that found a
## full neighbourhood is fully confident, and a texel on the front is confident
## in proportion to the sliver it found, which leaves the front so faint that
## the next pass barely reads it. Two is the front advancing at a texel a pass
## with the arithmetic still normalised, which is what makes [constant
## MIN_PASSES] mean what it says.
const GAIN: float = 2.0

## How far round the selection Texture looks for patches, on each side, as a
## share of the selection's own width and height. Krita's Smart Patch takes
## `1 + accuracy / 25` of it, one at its lowest setting and three at its
## default. One here, because the pyramid over the surround is GPU memory, and
## the random search reaches every texel of the surround on every pass however
## wide it is.
const SURROUND: float = 1.0

## The least surround Texture takes on each side, four patches wide, so a
## blemish a few pixels across still has patches round it to copy.
const MIN_SURROUND: int = 4 * (2 * SaPatchMatchScript.RADIUS + 1)

## The bindings `patch.gmacs` declares, in its own order. The mask is at
## `SaSelection.BINDING` because every kernel that honours the selection binds
## it there.
const BINDING_IN: int = 2
const BINDING_OUT: int = 3
const BINDING_WEIGHT_IN: int = 4
const BINDING_WEIGHT_OUT: int = 5

var _compute: SaCompute = null

var _match: SaPatchMatchScript = null

## A 1 by 1 texel at each colour format met, bound as the canvas while the
## sweeps run: a uniform set has to cover every binding the compiled kernel
## kept, and the sweep reads no chunk.
var _blank: Dictionary = {}


## Fills what the selection covers of *layer* out of its surround, as one
## history step. Answers the number of chunks it wrote, and zero when there is
## no selection, when the layer is locked, or when the selection's bounds are
## empty.
##
## *region* is a mask of the caller's own to fill instead of the document's
## selection, which is what the patch tool hands over when a painter drew a
## region with the tool's own circle rather than making a selection. Nothing
## below this line learns where the mask came from: it is an [SaSelection] like
## the document's, bound at [constant SaSelection.BINDING] like the document's,
## and the three passes read it through the same two calls. Null is the
## document's own, which is every other caller.
##
## *method* is a [enum Method], Texture unless the caller asks for Smooth.
func patch(document: SaDocument, layer: SaLayer, region: SaSelection = null, method: int = Method.TEXTURE) -> int:
    if document == null or layer == null or SaContext.refuse_paint(layer, TranslationServer.translate("patch")):
        return 0
    var selection := region if region != null else document.selection
    if selection == null or not selection.active:
        return 0
    # Clipped to the canvas, because a region the tool painted at the edge
    # claims the whole of its last chunk and the document's own selection never
    # reaches past the picture. Without it the hole loop below creates a layer
    # chunk outside the canvas and the scatter writes paint nothing composites.
    var bounds := selection.bounds.intersection(Rect2i(Vector2i.ZERO, document.canvas_size))
    if bounds.size.x <= 0 or bounds.size.y <= 0:
        return 0
    if method == Method.TEXTURE and bounds == Rect2i(Vector2i.ZERO, document.canvas_size):
        # Texture copies from the surround, and a selection whose rectangle is
        # the whole canvas leaves none it can count on: under Select All every
        # texel is hole, and a fill with nothing known would lay the empty top
        # of its pyramid over the paint. Smooth with nothing known leaves the
        # paint where it is, and with a known corner fills from it.
        method = Method.SMOOTH
    var work := work_for(bounds, document.canvas_size, method)
    if work.size.x <= 0 or work.size.y <= 0:
        return 0
    var format := _albedo_format(layer)
    if format < 0:
        return 0
    if _compute == null:
        _compute = SaCompute.new("patch")
    _compute.use_storage_format(format)

    # Before anything is allocated, so a chunk this patch creates is recorded as
    # "there was nothing here", which is what `swap_pixels` reads a null as
    # and what an undo of a patch over empty canvas has to put back.
    var holes: Dictionary = {}
    var undo_data: Dictionary = {}
    for grid_pos: Vector2i in SaChunkWalk.positions_in(bounds):
        if selection.texture_for(grid_pos) == null:
            continue
        holes[grid_pos] = true
        undo_data[grid_pos] = layer.duplicate_chunk(grid_pos) if layer.chunks.has(grid_pos) else null
    if holes.is_empty():
        return 0

    var colour: Array[SaTexture] = [SaTexture.new(work.size, format)]
    var weight: Array[SaTexture] = [SaTexture.new(work.size, SaSelection.FORMAT)]
    _clear(work, colour[0], weight[0])
    _gather(selection, layer, work, holes, colour[0], weight[0])

    var written := 0
    if method == Method.SMOOTH:
        colour.append(SaTexture.new(work.size, format))
        weight.append(SaTexture.new(work.size, SaSelection.FORMAT))
        var read := _sweep(work.size, colour, weight)
        written = _scatter(selection, layer, bounds, work, colour[read], weight[read], false)
    else:
        if _match == null:
            _match = SaPatchMatchScript.new()
        var hole := Rect2i(bounds.position - work.position, bounds.size)
        var drawn := _match.fill(colour[0], weight[0], hole, _sweep)
        written = _scatter(selection, layer, bounds, work, drawn[0], drawn[1], true)

    document.record_pixel_step(ACTION_NAME, layer, undo_data)
    document.invalidate_chunks(undo_data.keys())
    document.modified = true
    document.document_changed.emit()
    return written


## The rectangle a patch of *bounds* by *method* gathers and works over: the
## selection and the ring Smooth draws from, or the selection and the surround
## Texture copies patches out of, clipped to a canvas of *canvas* either way.
static func work_for(bounds: Rect2i, canvas: Vector2i, method: int) -> Rect2i:
    var whole := Rect2i(Vector2i.ZERO, canvas)
    if method == Method.SMOOTH:
        return bounds.grow(RING).intersection(whole)
    var across := maxi(ceili(bounds.size.x * SURROUND), MIN_SURROUND)
    var down := maxi(ceili(bounds.size.y * SURROUND), MIN_SURROUND)
    return bounds.grow_individual(across, down, across, down).intersection(whole)


## How many sweeps a rectangle of *size* is worth, between the two bounds
## [constant MIN_PASSES] and [constant MAX_PASSES] set.
static func passes_for(size: Vector2i) -> int:
    return clampi(floori(maxi(size.x, size.y) * 0.5) + 8, MIN_PASSES, MAX_PASSES)


## The format of *layer*'s albedo, which every schema has to carry, or -1 when
## the schema names none.
##
## **The albedo alone is patched, and a second colour field is left to the layer
## type that introduced it.** The clipboard says the same thing about a height
## or a concentration in its own copy loop: what a partial rewrite of such a
## field means is that type's question, and averaging one the way a colour is
## averaged would be this unit guessing at it.
static func _albedo_format(layer: SaLayer) -> int:
    var spec := SaFieldSpec.find(layer.schema, SaFieldSpec.ALBEDO)
    return spec.format if spec != null else -1


## Puts *colour* and *weight* into the state a texel the layer has no chunk at
## has to be read in: transparent, and fully known, so empty canvas beside the
## selection is paint the fill can draw from rather than a second hole.
##
## **A kernel rather than `SaTexture.clear`.** A clear is a transfer and every
## other write here is compute, and the two are not ordered against each other
## on this driver. `core/transform/sa_transform.gd`'s header records what that cost the
## transform preview: a tile cleared that way kept the texels of whatever had
## last owned the memory, and the drag drew fragments of the painting in three
## places at once.
func _clear(work: Rect2i, colour: SaTexture, weight: SaTexture) -> void:
    _bind(_blank_at(colour.format), _blank_mask(), colour, weight)
    _compute.set_push_constant_float_array(_flat_push(work))
    _compute.dispatch_kernel("patch_clear", SaCompute.groups_for(work.size.x), SaCompute.groups_for(work.size.y), 1)


## Reads the layer's chunks under *work* into *colour* and *weight*.
##
## Every chunk the layer already holds, so the ring is read wherever it is, and
## a chunk allocated at each position of *holes*, because that is where the
## patch will be written and a hole with no chunk under it would otherwise read
## as known empty canvas rather than as something to fill.
func _gather(
    selection: SaSelection, layer: SaLayer, work: Rect2i, holes: Dictionary, colour: SaTexture, weight: SaTexture
) -> void:
    for grid_pos: Vector2i in SaChunkWalk.positions_in(work):
        var mask := selection.texture_for(grid_pos)
        var chunk: SaChunk = layer.chunks.get(grid_pos, null)
        if chunk == null:
            if not holes.has(grid_pos):
                continue
            chunk = layer.get_or_create_chunk(grid_pos)
        if chunk == null:
            continue
        var texture: SaTexture = chunk.field(SaFieldSpec.ALBEDO)
        if texture == null or not texture.rid.is_valid():
            continue
        var local := SaChunkWalk.local_rect(grid_pos, work, chunk.pixel_size())
        if local.size.x <= 0 or local.size.y <= 0:
            continue
        _bind(texture, mask if mask != null else selection.nothing(), colour, weight)
        _compute.set_push_constant_float_array(_push(local.position, local.end, grid_pos, work, chunk, false, false))
        _compute.dispatch_kernel("patch_gather", SaCompute.groups_for(local.size.x), SaCompute.groups_for(local.size.y), 1)


## Runs the sweeps over a rectangle of *size* and answers which of the two
## pairs holds the result. Texture calls it too, for its coarsest level.
##
## **Not a batched list.** Every dispatch here reads what the one before it
## wrote, and `SaCompute` closes a list per `dispatch_kernel`, which is where
## the full barrier between two passes comes from. Batching them under one list
## would be a race rather than a saving.
func _sweep(size: Vector2i, colour: Array[SaTexture], weight: Array[SaTexture]) -> int:
    var blank := _blank_at(colour[0].format)
    var groups_x := SaCompute.groups_for(size.x)
    var groups_y := SaCompute.groups_for(size.y)
    var params := _flat_push(Rect2i(Vector2i.ZERO, size))
    var read := 0
    for _pass in passes_for(size):
        var write := 1 - read
        _compute.set_texture(0, blank.rid)
        _compute.set_texture(SaSelection.BINDING, _blank_mask().rid)
        _compute.set_texture(BINDING_IN, colour[read].rid)
        _compute.set_texture(BINDING_OUT, colour[write].rid)
        _compute.set_texture(BINDING_WEIGHT_IN, weight[read].rid)
        _compute.set_texture(BINDING_WEIGHT_OUT, weight[write].rid)
        _compute.set_push_constant_float_array(params)
        _compute.dispatch_kernel("patch_sweep", groups_x, groups_y, 1)
        read = write
    return read


## Writes *colour* back into the layer through the selection, and answers how
## many chunks it wrote. *whole* says every texel of the hole was drawn, which
## Texture's always is, so the scatter does not ask *weight* whether the front
## reached it.
func _scatter(
    selection: SaSelection, layer: SaLayer, bounds: Rect2i, work: Rect2i, colour: SaTexture, weight: SaTexture, whole: bool
) -> int:
    var lock := layer.alpha_locked
    var chunk_at := func(grid_pos: Vector2i) -> SaChunk:
        var chunk: SaChunk = layer.chunks.get(grid_pos, null)
        if chunk != null:
            layer.mark_unresolved(grid_pos)
        return chunk
    var push := func(grid_pos: Vector2i, local: Rect2i, start: Vector2i) -> PackedFloat32Array:
        var chunk: SaChunk = layer.chunks[grid_pos]
        return _push(start, local.end, grid_pos, work, chunk, lock, whole)
    # No layer on the walk, so it dispatches over the albedo alone rather than
    # over every colour field the schema carries, for the reason
    # `_albedo_format` gives. The chunks it writes are marked unresolved above
    # instead.
    var walk := SaChunkWalk.new(_compute, selection, null, SaFieldSpec.ALBEDO)
    var bindings := {BINDING_IN: colour, BINDING_OUT: colour, BINDING_WEIGHT_IN: weight, BINDING_WEIGHT_OUT: weight}
    return walk.run("patch_scatter", bounds, chunk_at, push, bindings).size()


## The twelve floats `patch.gmacs` declares, for one chunk's dispatch.
func _push(
    start: Vector2i, end: Vector2i, grid_pos: Vector2i, work: Rect2i, chunk: SaChunk, lock: bool, whole: bool
) -> PackedFloat32Array:
    var place := grid_pos * SaChunk.SIZE - work.position
    # Colour texels per mask texel, asked of the chunk rather than assumed
    # (hard rule 3). A chunk restored from a `.sad` at a reduced resolution
    # holds fewer texels than the document pixels it covers, and the mask is
    # always at the document's own scale.
    var scale := float(chunk.pixel_size()) / float(SaChunk.SIZE)
    return PackedFloat32Array(
        [
            float(start.x),
            float(start.y),
            float(end.x),
            float(end.y),
            float(place.x),
            float(place.y),
            float(work.size.x),
            float(work.size.y),
            scale,
            1.0 if lock else 0.0,
            GAIN,
            1.0 if whole else 0.0,
        ]
    )


## The six bindings `patch.gmacs` declares, with the flat pair on both
## sides of the ping-pong for a kernel that reads and writes the same one.
func _bind(canvas: SaTexture, mask: SaTexture, colour: SaTexture, weight: SaTexture) -> void:
    _compute.set_texture(0, canvas.rid)
    _compute.set_texture(SaSelection.BINDING, mask.rid)
    _compute.set_texture(BINDING_IN, colour.rid)
    _compute.set_texture(BINDING_OUT, colour.rid)
    _compute.set_texture(BINDING_WEIGHT_IN, weight.rid)
    _compute.set_texture(BINDING_WEIGHT_OUT, weight.rid)


## The push constant for a kernel that runs over the whole of *work* from its
## own corner rather than over one chunk's share of it, which is the clear and
## the sweep. The chunk half of the block reads zero and neither kernel looks
## at it.
static func _flat_push(work: Rect2i) -> PackedFloat32Array:
    return PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0, float(work.size.x), float(work.size.y), 1.0, 0.0, GAIN, 0.0])


## A 1 by 1 texel at *format*, kept per format met, bound as the canvas while
## the sweeps run.
func _blank_at(format: int) -> SaTexture:
    var blank: SaTexture = _blank.get(format, null)
    if blank == null:
        blank = SaTexture.new(Vector2i(1, 1), format)
        blank.clear(Color(0.0, 0.0, 0.0, 0.0))
        _blank[format] = blank
    return blank


## The 1 by 1 mask bound while the sweeps run, for the same reason the blank
## canvas is: the sweep reads no selection and the set still has to cover the
## binding.
func _blank_mask() -> SaTexture:
    return _blank_at(SaSelection.FORMAT)
