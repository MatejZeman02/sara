## Zoomed in past 100%, a double resolution layer's own detail.
##
## The output is the document at the document's resolution, and a layer at 2.0
## is averaged into it. Past 100% that average is what the view magnifies,
## so the painter zoomed in on the boat would see none of the detail they paint.
## This is a sparse set of display chunks, each a texture twice a chunk across
## over one grid position's document pixels, composited by the compositor's
## own walk at twice the density: a chunk at 2.0 read texel for texel and
## everything at 1.0, the fold's caches included, repeated over two by two
## blocks, the way the view's nearest filter magnifies the output. The canvas
## draws each one over its own texture.
##
## A chunk at 2.0 keeps its density through every path of the walk: its filters
## run at it and nothing brings the result down, its mask and its clip are
## applied at it, a scope or a live stroke's chain around it is a scratch twice a
## chunk across, and an isolated group holding one is composited afresh from its
## members rather than read off its cache. A group whose own filters run, and
## the scope it opens, filter that composite at 2.0 over a halo at 2.0, which
## [SaFineGroup] keeps, so nothing brings it down before the display. A record
## that reads the whole node runs at the document's resolution on every node,
## a layer at 2.0 as well, because the gather it reads is built of chunks at 1.0.
##
## A display chunk exists only where the easel's window reaches a chunk of a
## visible layer at 2.0, and only while the view is zoomed in past 100%, so it
## is never a texture over the canvas or the window (hard rules 2 and 3). The
## easel asks for it each frame with the regions its own composite walked, so
## a stroke reaches both in one frame.
##
## A document whose root carries a filter shows no detail: the root's filters
## run over the whole output, and a display chunk would show the picture
## before them.
class_name SaDetailView
extends RefCounted

## How many display texels lie along one document pixel.
const DENSITY: float = 2.0

## How far past one pixel per texel the view has to be before the detail is
## drawn, the same tenth of a per mille the canvas's sampler allows for the
## float round trip of a 100% zoom.
const EPSILON: float = 1.0e-4

## Grid position to its display chunk, a `SaTexture` of `side()` texels.
var chunks: Dictionary[Vector2i, SaTexture] = {}

## Bumped whenever a display chunk is made, released or composited, so the
## view draws again only when something it shows changed.
var revision: int = 0


## Where the compositor's walk writes. The output takes a composite at the
## offset and over the region it is given, and a display chunk takes it at
## `DENSITY` times both, measured from its own corner, and reads each source
## at its own density over `DENSITY`. So does a scratch the walk adopted, an
## isolated group's or a live stroke's twice a chunk across, measured from its
## own corner, which is offset zero. Held by the compositor for
## the length of one walk, and at rest it moves nothing.
class Target:
    extends RefCounted

    var _destination: SaTexture = null
    var _origin: Vector2 = Vector2.ZERO
    var _density: float = 1.0
    ## The adopted scratches of the walk in hand, by RID.
    var _adopted: Dictionary[RID, bool] = {}

    func begin(destination: SaTexture, origin: Vector2, density: float) -> void:
        _destination = destination
        _origin = origin
        _density = density

    func end() -> void:
        _destination = null
        _adopted.clear()

    ## Whether a walk into a display chunk is in hand.
    func active() -> bool:
        return _destination != null

    ## Places what the walk in hand composites into *scratch* as it places
    ## the display chunk's own, from the scratch's corner.
    func adopt(scratch: SaTexture) -> void:
        _adopted[scratch.rid] = true

    ## The offset, the region and the source's density a composite into
    ## *destination* is dispatched with.
    func placed(destination: SaTexture, offset: Vector2, region: Rect2i, density: float) -> Placed:
        if destination == null or _destination == null:
            return Placed.new(offset, region, density)
        var origin := _origin
        if destination != _destination:
            if not _adopted.has(destination.rid):
                return Placed.new(offset, region, density)
            origin = offset
        var scaled := Rect2i(Vector2i(Vector2(region.position) * _density), Vector2i(Vector2(region.size) * _density))
        return Placed.new((offset - origin) * _density, scaled, density / _density)


## Where [method Target.placed] puts one composite: the offset and the region
## in the destination's own texels, and the density the source is read at.
class Placed:
    extends RefCounted

    var offset: Vector2
    var region: Rect2i
    var density: float

    func _init(at: Vector2, area: Rect2i, read_at: float) -> void:
        offset = at
        region = area
        density = read_at


## A display chunk's width and height in texels.
static func side() -> Vector2i:
    var across := int(SaChunk.SIZE * DENSITY)
    return Vector2i(across, across)


## Whether a view at *pixels_per_texel* is zoomed in past 100%.
static func zoomed_in(pixels_per_texel: float) -> bool:
    return pixels_per_texel > 1.0 + EPSILON


## Makes, releases and composites the display chunks for one frame. *window*
## is what the view shows grown by a chunk, in document pixels, *zoomed* says
## whether the view is past 100%, and *regions* is what the easel's composite
## walked this frame, grid position to a chunk-local rectangle, every chunk
## whole when *full*. A new display chunk is composited whole.
func follow(
    document: SaDocument, compositor: SaCompositor, window: Rect2, zoomed: bool, regions: Dictionary[Vector2i, Rect2i], full: bool
) -> void:
    if chunks.is_empty() and not zoomed:
        return
    var wanted: Dictionary[Vector2i, bool] = {}
    if zoomed:
        wanted = held_under(document, window)
    for grid_pos: Vector2i in chunks.keys():
        if not wanted.has(grid_pos):
            chunks.erase(grid_pos)
            revision += 1
    var format := document.color_space.texel_format() if document != null else 0
    for grid_pos: Vector2i in wanted:
        var chunk: SaTexture = chunks.get(grid_pos, null)
        var region := SaDocument.WHOLE_CHUNK
        if chunk == null or chunk.format != format:
            chunk = SaTexture.new(side(), format)
            chunks[grid_pos] = chunk
        elif not full:
            if not regions.has(grid_pos):
                continue
            region = (regions[grid_pos] as Rect2i).intersection(SaDocument.WHOLE_CHUNK)
            if not region.has_area():
                continue
        _composite(document, compositor, grid_pos, chunk, region)
        revision += 1


## The grid positions a visible layer at 2.0 holds a chunk at inside
## *window*, the layers the compositor walks, the members of an isolated
## group whose cache the walk sets aside, and the live stroke over an active
## layer at 2.0.
## None when the root's filters run, for the reason the header gives.
static func held_under(document: SaDocument, window: Rect2) -> Dictionary[Vector2i, bool]:
    var found: Dictionary[Vector2i, bool] = {}
    if document == null or document.fold == null or SaFilterChain.has_enabled(document.root_filters):
        return found
    for layer in SaLayerStack.layers(document):
        if layer.resolution_scale <= 1.0 or not SaLayerStack.shows(document, layer):
            continue
        _gather(found, layer, window)
    # And one inside an isolated group a cache stands for, which the walk
    # composites afresh from the group's members.
    for steps: Array in document.fold.fine_groups.values():
        for step: Dictionary in steps:
            for part in SaLayerStack.parts_of(step):
                var member := SaLayerStack.layer_of(part)
                if member.resolution_scale > 1.0 and SaLayerStack.shows(document, member):
                    _gather(found, member, window)
    # A live stroke or a lifted picture on a layer at 2.0 is at 2.0 too, and
    # reaches past the chunks the layer holds, so its own chunks are shown at
    # their detail before the commit makes them the layer's.
    var stroke := document.stroke_layer
    var active := document.active_layer
    if stroke != null and stroke.visible and stroke.resolution_scale > 1.0:
        if active == null or SaLayerStack.shows(document, active):
            _gather(found, stroke, window)
    return found


## Adds to *found* every grid position *layer* holds a chunk at inside
## *window*.
static func _gather(found: Dictionary[Vector2i, bool], layer: SaLayer, window: Rect2) -> void:
    var across := float(SaLayer.CHUNK_SIZE)
    for grid_pos: Vector2i in layer.chunks:
        if window.intersects(Rect2(Vector2(grid_pos) * across, Vector2(across, across))):
            found[grid_pos] = true


## Lets go of every display chunk: the view zoomed out, the document was
## swapped or resized, or the easel is going.
func release() -> void:
    if chunks.is_empty():
        return
    chunks.clear()
    revision += 1


## The walk over *region* of the chunk at *grid_pos*, into *chunk* at twice
## the density: the clear, then every tier, exactly the passes the output's
## walk ran over the same region.
func _composite(document: SaDocument, compositor: SaCompositor, grid_pos: Vector2i, chunk: SaTexture, region: Rect2i) -> void:
    var origin := Vector2(grid_pos * SaLayer.CHUNK_SIZE)
    var regions: Dictionary[Vector2i, Rect2i] = {grid_pos: region}
    compositor.detail.begin(chunk, origin, DENSITY)
    compositor.clear_canvas_chunks(chunk, regions)
    compositor.walk(chunk, document, regions, Rect2(origin, Vector2(SaLayer.CHUNK_SIZE, SaLayer.CHUNK_SIZE)))
    compositor.detail.end()
