## The live stroke over a plain active layer, composited one stage at a time
## over a run of chunks.
##
## A chunk under the live stroke is a chain: the layer into a scratch, the
## stroke over it, the scratch onto the canvas, and each step reads what the
## last one wrote. Taken a chunk at a time that is three compute lists and
## three barriers a chunk, and a gradient lays its preview over every chunk of
## the canvas, so ten moves cost 1725 lists. Every chunk of a
## run has a scratch of its own, so no dispatch of a stage touches another
## chunk's texture, and a stage is one list over the whole run with the
## barrier between the stages rather than between the dispatches.
##
## Only for a pass with no isolated group around the active layer, no clip, no
## point preview, no mask and no enabled filter on it, which is `simple` in
## `SaCompositeWalk.walk`. Every other chain still goes a chunk at a time
## through `_render_scope`, because its mask, clip and filter steps each go
## through a scratch the compositor holds one of.
##
## The run is handed the compositor's three list operations rather than the
## compositor, the way `SaFilterHalo.fill` is handed `composite_chunk`, so the
## blend modes stay resolved in one place and the run holds the chunks alone.
class_name SaStrokeRun
extends RefCounted


## One chunk of the run: its *scratch*, the layer's chunk or null, the stroke's
## chunk, *held*, what the scratch is cleared and built over, the region grown
## by what the layer's filters read, in the scratch's own texels, the *offset*
## onto the canvas, and *region*, what reaches the canvas, in document pixels.
class Entry:
    extends RefCounted

    var scratch: SaTexture
    var layer_chunk: SaTexture
    var stroke_chunk: SaTexture
    var held: Rect2i
    var offset: Vector2
    var region: Rect2i

    func _init(own: SaTexture, below: SaTexture, stroke: SaTexture, built: Rect2i, placed: Vector2, reached: Rect2i) -> void:
        scratch = own
        layer_chunk = below
        stroke_chunk = stroke
        held = built
        offset = placed
        region = reached


## `SaCompositor.clear_scratch_batch`, `composite_chunk_pairs` and
## `composite_chunk_batch`, one a stage.
var _clear: Callable
var _pairs: Callable
var _batch: Callable
## Where the scratches come from, a slot per chunk of the run.
var _pools: SaScratchPools
## What the pass [method begin] started composites onto, and from.
var _canvas: SaTexture = null
var _document: SaDocument = null
## The active layer, or null when it does not show and the stroke goes onto
## the canvas alone.
var _layer: SaLayer = null
var _layer_mode: StringName = SaLayer.BLEND_MODE.NORMAL
var _layer_opacity: float = 1.0
## The run so far, one [Entry] a chunk and its slot its position here.
var _entries: Array[Entry] = []


func _init(clear: Callable, pairs: Callable, batch: Callable, pools: SaScratchPools) -> void:
    _clear = clear
    _pairs = pairs
    _batch = batch
    _pools = pools


## Starts a pass onto *canvas* of *document*, whose active layer is *layer*
## when it shows and null when it does not, blended with *layer_mode* at
## *layer_opacity*. What the last pass left unflushed is dropped, which is
## nothing, since every pass flushes before it ends.
func begin(canvas: SaTexture, document: SaDocument, layer: SaLayer, layer_mode: StringName, layer_opacity: float) -> void:
    _canvas = canvas
    _document = document
    _layer = layer
    _layer_mode = layer_mode
    _layer_opacity = layer_opacity
    _entries.clear()


## Takes the chunk at *grid_pos*, whose stroke chunk is *stroke_chunk*, into the
## run, and composites the run once it holds `SaCompositor.SCRATCH_RUN` of them,
## so their slots are free for the next.
func add(grid_pos: Vector2i, offset: Vector2, region: Rect2i, stroke_chunk: SaTexture) -> void:
    # The scratch is as fine as the stroke, so a stroke on a layer at 2.0 meets
    # the layer texel for texel and reaches the canvas at its own detail, the
    # detail the commit bakes. The output's composite takes its mean, and a
    # display chunk reads it whole.
    var density := SaDocumentTexels.density_of(stroke_chunk)
    var scratch := _pools.stroke_slot(_entries.size(), _canvas.format, density)
    var layer_chunk: SaTexture = _layer.get_field(grid_pos) if _layer != null else null
    var side := Vector2i(SaChunk.SIZE, SaChunk.SIZE)
    _entries.append(Entry.new(scratch, layer_chunk, stroke_chunk, finer(held(_layer, region, side), density), offset, region))
    if _entries.size() == SaCompositor.SCRATCH_RUN:
        flush()


## What a stroke scratch of *side* holds for a chunk whose dirty part is
## *region*: the region, or what *layer*'s filters read of it when they will
## run. *layer* is the active layer, or null when it does not show. The
## scratch's clear, the layer and the stroke all cover it, and it is the
## compositor's question as much as the run's, since its chains clear the same.
static func held(layer: SaLayer, region: Rect2i, side: Vector2i) -> Rect2i:
    return SaFilterChain.read_region(layer.filters, region, side) if layer != null else region


## *region*, in document pixels, in the texels of a scratch *density* of them
## to a pixel.
static func finer(region: Rect2i, density: float) -> Rect2i:
    if density <= 1.0:
        return region
    return Rect2i(Vector2i(Vector2(region.position) * density), Vector2i(Vector2(region.size) * density))


## How many texels of stroke *scratch* a region in document pixels spans: the
## scratch's density, or one when *placed*, in a display chunk's walk, which
## places a region itself through `SaDetailView.Target`.
static func across(scratch: SaTexture, placed: bool) -> float:
    return 1.0 if placed else SaDocumentTexels.density_of(scratch)


## Composites what the run holds: every scratch cleared in one list, the layer
## into them in a second, the stroke over them in a third, and the scratches
## onto the canvas in a fourth. The next run takes the same slots again, which
## is safe because its clears are a list of their own, ordered after the one
## that read them.
func flush() -> void:
    if _entries.is_empty():
        return
    var clears: Array = []
    var below: Array = []
    var strokes: Array = []
    var onto: Array = []
    for entry: Entry in _entries:
        clears.append([entry.scratch, entry.held])
        if entry.layer_chunk != null:
            below.append([entry.scratch, entry.layer_chunk, entry.held])
        strokes.append([entry.scratch, entry.stroke_chunk, entry.held])
        onto.append([entry.scratch, entry.offset, entry.region])
    _entries.clear()
    var space := _document.color_space
    var white := _document.blend_reference_white
    _clear.call(clears)
    _pairs.call(below, SaLayer.BLEND_MODE.NORMAL, 1.0, space, white)
    _pairs.call(strokes, _document.stroke_layer.get_blend_mode_name(), _document.stroke_opacity, space, white)
    _batch.call(_canvas, onto, _layer_mode, _layer_opacity, space, white)
