## A node's attached filters, run in order over one chunk of what the node
## composites to.
##
## The compositor asks on the way from a chunk to `composite_chunk`, before the
## node's mask and its clip, because a filter decides what the node shows and
## those two decide where it shows. A node with no enabled record gets its
## source back untouched and nothing is dispatched, so a document with no
## attached filter pays nothing for the feature.
##
## It names no layer type. A plain layer hands over its chunk, an isolated
## group the chunk of the cache or the scratch its members were composited
## into, and the document's root the canvas, so one code path serves all three.
##
## One scratch, reused, so a filtered chunk is a chain like a clipped one and
## goes through `composite_chunk` one at a time. A point kernel rewrites binding
## 0 in place (the contract on [SaPointPass]), so every record reads what the
## record before it wrote with nothing to swap. A pass that reads its neighbours
## cannot, and its second texture is the padded one [SaNeighbourhoodPass.Runner]
## gathers the chunk and its eight neighbours into.
##
## A node carrying a neighbourhood pass is run over its dirty region grown by
## every such pass's halo and clipped to the chunk, and not over the region
## alone, because a texel of the region reads its neighbours' filtered values.
## What the growth reaches past the region is computed and never composited. A
## neighbour past the chunk's edge is read as its node stores it, or after a
## whole-node record as the records before left it, [SaChainedNeighbours].
##
## Two nodes store nothing to read a neighbour from, and each keeps a [SaFilterHalo] of
## its composite before its filters instead: the root, whose canvas beside a dirty
## chunk holds last frame's filtered composite, and a scope, a group holding the active
## layer, composited one chunk at a time into a scratch. Neither is kept whole. The
## root's is copied off the canvas over the dirty regions grown by twice the chain's
## reach, which the compositor composites for it, and a scope's over the positions the
## compositor sweeps before the pass proper, so both cost VRAM for the dirty set and
## its ring and nothing for the rest of the document.
##
## A third reads a neighbour that is in no chunk of its own at all: a layer under a
## live stroke, whose stroke is a buffer of its own until it commits.
## [method stroke_sweep] answers where the compositor has to composite the two
## together, it keeps them in a [SaFilterHalo] of its own, and that is handed back as
## the neighbours.
##
## A pass that reads the whole node reads the node's allocated chunks gathered
## into one [SaNeighbourhoodPass.Whole], built the first time a chunk of the
## node is filtered in an evaluation and read by every chunk after it. An
## evaluation is one composite, which [method spilled] opens, or one frame for
## a caller that filters without compositing, a flatten. Its halo is zero, so
## the work is the region alone.
##
## The two nodes that store no chunk gather from what stands for their composite
## instead. The root's [SaRootGather] gathers the canvas over every position the
## composite under it shows something at, taken before any root filter rewrites it
## and kept between composites, which is what lets its dirty set be where a change
## lands and nothing more. A scope and a layer under a live stroke gather
## from the [SaFilterHalo] the sweep fills for them, its sweep widened to every
## position the node holds, because a whole-node pass reads a texel the dirty region
## never reached. Only a node that holds nothing at all is left with nothing to
## gather, and that one is reported once.
class_name SaFilterChain
extends RefCounted

## Where a record's key is answered. Injected by the host the way the
## compositor's blend mode registry is, and null in a host that has no filters,
## where every record is skipped.
var registry: SaFilterRegistry = null

var _scratch: SaTexture = null
## Every scratch [method _scratch_for] made, by format and side. A thumbnail
## drawn at a sixteenth of a chunk asks for one sixteen texels across between
## two of a chunk's, and one scratch made again at each freed a texture each
## time, which drops every uniform set `SaCompute` has cached.
var _scratches: Dictionary[String, SaTexture] = {}
## The previewed neighbourhood pass's own scratch, apart from [member _scratch]
## because the preview's answer is what the node's own filters read next.
var _preview: SaTexture = null
var _runner := SaNeighbourhoodPass.Runner.new()
## A runner for each halo a pass of a node's chain gathers at, by its reach in
## texels. One runner keeps one padded texture and makes a new one when the
## reach changes, and freeing a texture drops every uniform set `SaCompute`
## has cached, so two filters of unlike reach in one walk, the wobble and the
## motion blur of a large painting's group, freed and made a texture at
## every chunk and built most sets of the walk again.
var _reaches: Dictionary[int, SaNeighbourhoodPass.Runner] = {}
## The document [method _passes_of] last named, by instance id, whose canvas a
## runner made after it clamps to.
var _canvas_of := 0
## The chunks a neighbourhood pass reads beside its own after a whole-node pass.
var _around := SaChainedNeighbours.new(_copy, _clear)
## A finer source brought down to neighbours stored at the document's resolution.
var _texels := SaDocumentTexels.new()
## Shader key -> the SaCompute the chain dispatches that shader's passes on.
var _computes: Dictionary[String, SaCompute] = {}
## Record instance id -> the revision it failed to build a pass at, so a record
## no registry answers is reported once and not run again on every chunk of
## every frame. A record that is touched gets one more try.
var _failed: Dictionary[int, int] = {}
## The widest halo of the neighbourhood passes built since [method spilled] last
## read it: what no dirty region has been grown by yet.
var _unspilled: int = 0
## Document instance id -> the widest halo its last composite drew with, kept
## per document because thumbnails and the scratchpad share a compositor.
var _drawn: Dictionary[int, int] = {}
## The root's composite before its filters, over the regions the pass grew.
var _root_halo := SaFilterHalo.new()
## The canvas gathered for a root record that reads the whole node, kept
## across composites and let go when the root carries no such record.
var _root_gather := SaRootGather.new(_copy, _clear)
## The filtered composite the growth is about to clear outside the dirty
## regions, which nothing asked to change and which goes back after.
var _root_saved := SaFilterHalo.new()
## Layer instance ids whose passes an open builds over its frames, which
## [method spilled] does not build meanwhile. Building a large painting's 217
## in the first walk held one frame for 100 ms.
var _held_back: Dictionary[int, bool] = {}
## Group instance id -> the [SaFilterHalo] of a scope whose filters read neighbours.
var _scope_halos: Dictionary[int, SaFilterHalo] = {}
## The gathers a whole-node pass reads, kept from one composite to the next.
var _wholes := SaWholeGathers.new()
## Record instance ids a whole-node pass was reported skipped for, once each.
var _whole_skipped: Dictionary[int, bool] = {}
## A record's mask enlarged to a finer chunk's side, and the frame it was made in.
var _masks := SaFilterDensity.Masks.new()
var _masks_frame: int = -1


## Whether any of *records* would change what its node shows.
static func has_enabled(records: Array[SaAttachedFilter]) -> bool:
    for record in records:
        if record != null and record.enabled:
            return true
    return false


## The pass *record* evaluates to over *node*, built and cached the way the
## composite builds it, or null when no installed module can build one. What
## a flatten walks, so the texels it writes are the ones the canvas showed.
func pass_for(document: SaDocument, node: SaLayer, record: SaAttachedFilter) -> SaPointPass:
    if document == null or record == null:
        return null
    return _pass_of(document, node, record)


## *source*, *node*'s chunk at *grid_pos* or what stands for it, with every
## enabled filter of the node run over *region* in order, in the scratch. The
## source itself when the node carries none. The document is asked of the node,
## which is a child of it, so a stack entry needs to carry the node and nothing
## else.
##
## *neighbours* is the layer a neighbourhood pass reads the chunks around this
## one from, the node itself when null: an isolated group's cache, which is
## where its composite is, rather than the group, which stores nothing, or the
## halo of the active layer's live stroke, which is the layer and the stroke
## together.
##
## *source* at the node's own density, 512 texels on a layer at 2.0, is
## filtered at that density with *region* still in document pixels, and so is
## what comes back. The caller brings it down to the document.
func filtered(
    node: SaLayer,
    source: SaTexture,
    grid_pos: Vector2i,
    region: Rect2i,
    neighbours: SaLayer = null,
    whole: SaNeighbourhoodPass.Whole = null
) -> SaTexture:
    if node == null or not has_enabled(node.filters):
        return source
    var document := node.get_parent() as SaDocument
    if document == null:
        return source
    var passes := _passes_of(document, node, node.filters)
    if passes.is_empty():
        return source
    var stored := neighbours if neighbours != null else node
    if source != null and SaDocumentTexels.density_of(source) != SaFilterDensity.scale_of(stored):
        # A finer chunk beside coarser neighbours comes down to them first. A
        # group filtered at 2.0 reads the halo `SaFineGroup` keeps at 2.0.
        source = _texels.of(source, region)
    var reach := _reach(passes)
    # A position the node never allocated still shows what a neighbourhood pass
    # carries into it from the chunks beside it. One of those says the format
    # and the size, and a cleared scratch stands for the chunk.
    var like := source if source != null else _beside(stored, grid_pos, reach)
    if like == null:
        # A position a whole-node pass carries paint onto from anywhere.
        like = _any_held(stored, passes)
    if like == null:
        return null
    # A chunk finer than the document, 512 texels on a layer at 2.0, is read at
    # its own side: the region, the scratch and the halo in its texels, so a
    # filter runs at the layer's density as Apply does.
    var side := like.size.x
    var work := _grown(_in_texels(region, side), _reach(passes, side), like.size)
    _scratch_for(like.format, like.size)
    if source != null:
        _copy(source, work.position, _scratch, work)
    else:
        _clear(_scratch, work)
    if whole == null and SaFilterHalo.lies_over(stored, node) and _reads_whole(passes):
        # The node's kept gather with the halo's chunks laid in, see stroke_sweep.
        whole = _wholes.of(stored, like.format, _runner, node)
    _dispatch(passes, grid_pos, work, document.selection.everything(), stored.get_field, stored, whole)
    return _scratch


## What [method filtered] reads of a source of *side* texels when asked for
## *region* under *records*: the region grown by the reach of the passes they
## were last evaluated to, kept to the chunk. A source composited for the
## occasion has to hold its paint over all of this, and a scratch that holds it
## over the region alone hands the pass whatever chunk used the scratch last.
## Static and read off the records, which [method spilled] has built by the
## time a composite asks, so the compositor asks it of no chain.
static func read_region(records: Array[SaAttachedFilter], region: Rect2i, side: Vector2i) -> Rect2i:
    var reach := read_reach(records)
    return _grown(region, reach, side) if reach > 0 else region


## How far *records* read past a texel: the halos of the neighbourhood passes
## they were last evaluated to, added, and zero before the first composite built
## one. The sum and not the widest, because two neighbourhood passes in one
## chain each read and a growth short of the sum leaves a texel of the work
## uncomputed. Static and read off the cached passes, the way
## [method read_region] is, so a caller with no chain asks it of no chain.
static func read_reach(records: Array[SaAttachedFilter]) -> int:
    var reach := 0
    for record in records:
        if record != null and record.enabled and record.cached_pass is SaNeighbourhoodPass:
            reach += (record.cached_pass as SaNeighbourhoodPass).halo()
    return reach


## *region*, in document pixels, in the texels of a chunk *side* texels across,
## and an empty one, which is the whole chunk, as it is.
static func _in_texels(region: Rect2i, side: int) -> Rect2i:
    if region.size.x <= 0 or side == SaChunk.SIZE:
        return region
    return Rect2i(SaFilterDensity.in_texels(region.position, side), SaFilterDensity.in_texels(region.size, side))


static func _grown(region: Rect2i, reach: int, side: Vector2i) -> Rect2i:
    var covered := region if region.size.x > 0 else Rect2i(Vector2i.ZERO, side)
    return covered.grow(reach).intersection(Rect2i(Vector2i.ZERO, side))


## Leaves the passes of *layers* to [method build], one call each, in place
## of any held back before, so an empty array lets every one go. Their halos
## grow no region meanwhile, and the open that asks marks the whole canvas
## once they are built.
func hold_back(layers: Array[SaLayer]) -> void:
    _held_back.clear()
    for layer in layers:
        _held_back[layer.get_instance_id()] = true


## Builds the passes of *layer* that [method hold_back] left, as
## [method reach_of] does.
func build(layer: SaLayer) -> void:
    _held_back.erase(layer.get_instance_id())
    reach_of(layer)


## How far *node*'s enabled records gather past a chunk's edge, the sum of their
## halos, zero for a node with point passes alone. Builds the passes it has to
## ask, so the answer is right before the node's first composite, which
## `SaNeighbourhoodPass.halo_of` is not.
func reach_of(node: SaLayer) -> int:
    if node == null or not has_enabled(node.filters):
        return 0
    var document := node.get_parent() as SaDocument
    return _reach(_passes_of(document, node, node.filters)) if document != null else 0


## *regions*, grid position -> Rect2i in chunk-local pixels, grown by the halo
## the document's own growth could not know of, and kept to the canvas.
##
## `SaDocument.invalidate_chunk_regions` grows by the passes already built, and
## a record just attached or just touched has none until the chain is asked, so
## the redraw that follows an attach reached no position beside the paint. Every
## pass of the tree is built here, and the regions grow by the widest halo among
## the ones built since the last call. A record that went away is the same trap
## from the other side, the walk cannot redraw what left it: when the widest
## halo of the document is not what its last composite drew with, the regions
## grow by the wider of the two, so the spill a detached blur left is cleared.
## With *whole* it is the widest halo of all, for a caller whose regions were
## gathered from the chunks and never went through the document, and every
## position a whole-node pass declares its paint lands on is added whole, since
## a chunk gathered that way is where the node is and not where it draws.
func spilled(document: SaDocument, regions: Dictionary[Vector2i, Rect2i], whole: bool = false) -> Dictionary[Vector2i, Rect2i]:
    var given := regions
    # The root's as well, whose filters draw into every position they reach.
    var widest := _reach(_root_passes(document))
    var landed: Dictionary[Vector2i, bool] = {}
    # The layers that carry a filter, kept for the stroke being painted, and
    # not every layer of the stack at every frame of it.
    for layer: SaLayer in SaStaleSpread.bearers(document):
        if _held_back.has(layer.get_instance_id()):
            continue
        widest = maxi(widest, reach_of(layer))
        if whole and has_enabled(layer.filters):
            landed.merge(SaNeighbourhoodPass.landing(layer.filters, SaTyped.positions(layer.chunks), document.canvas_size))
    if not landed.is_empty():
        regions = regions.duplicate()
        for grid_pos: Vector2i in landed:
            if not regions.has(grid_pos):
                regions[grid_pos] = SaDocument.WHOLE_CHUNK
    var id := document.get_instance_id()
    var drawn: int = _drawn.get(id, 0)
    var reach := _unspilled if widest == drawn else maxi(_unspilled, maxi(widest, drawn))
    reach = maxi(reach, widest) if whole else reach
    _unspilled = 0
    if _wholes.keep(document, whole):
        _root_gather = SaRootGather.new(_copy, _clear)
    if widest > 0:
        _drawn[id] = widest
    else:
        _drawn.erase(id)
    if reach <= 0:
        _root_gather.changed(document.beneath_root, given, regions)
        return regions
    var grown := SaNeighbourhoodPass.grown(regions, reach)
    var side := float(SaLayer.CHUNK_SIZE)
    var limit := Rect2i(0, 0, ceili(document.canvas_size.x / side), ceili(document.canvas_size.y / side))
    for grid_pos: Vector2i in grown.keys():
        if not limit.has_point(grid_pos):
            grown.erase(grid_pos)
    _root_gather.changed(document.beneath_root, given, grown)
    return grown


## Where *node* can show something when it holds *chunks*, a dictionary keyed
## by grid position: the chunks themselves, and for a node whose records gather
## a halo the eight positions around each as well, as a set. A record whose
## pass reads the whole node and writes past it adds where it declares its
## paint lands, so a wrap draws on ground its node never allocated.
func walked(node: SaLayer, chunks: Dictionary[Vector2i, bool]) -> Dictionary[Vector2i, bool]:
    var out := chunks
    if reach_of(node) > 0:
        out = {}
        for grid_pos: Vector2i in chunks:
            for dy: int in [-1, 0, 1]:
                for dx: int in [-1, 0, 1]:
                    out[grid_pos + Vector2i(dx, dy)] = true
    var document := node.get_parent() as SaDocument if node != null else null
    if document == null or not has_enabled(node.filters):
        return out
    # reach_of has built the passes, so every record's cached pass is current.
    return SaNeighbourhoodPass.landing(node.filters, out, document.canvas_size)


## *source*, the active layer's chunk at *grid_pos*, run through the previewed
## neighbourhood pass *recorded* over *region* on *compute*, masked by the
## selection's *mask*, in a scratch of its own. The one-shot dialog's preview on
## the canvas, which goes through the gather the attached form goes through, so
## what the preview shows is what Apply writes. *halvings* draws a whole-node
## pass coarser while a control drags, [method SaNeighbourhoodPass.Runner.run_whole].
func previewed(
    recorded: SaNeighbourhoodPass,
    compute: SaCompute,
    layer: SaLayer,
    source: SaTexture,
    grid_pos: Vector2i,
    region: Rect2i,
    mask: SaTexture,
    halvings: int = 0
) -> SaTexture:
    if _preview == null or _preview.format != source.format or _preview.size != source.size:
        _preview = SaTexture.new(source.size, source.format)
    # A finer chunk is previewed at its own side, as Apply writes it, the
    # selection read by the pixel. A whole-node pass is not,
    # since Apply refuses one there, and the chunk shows as it is.
    var side := source.size.x
    if recorded.whole() and side != SaChunk.SIZE:
        return source
    mask = _at_side(mask, side)
    var covered := _in_texels(region, side) if region.size.x > 0 else Rect2i(Vector2i.ZERO, source.size)
    var work := covered.grow(recorded.halo_at(side)).intersection(Rect2i(Vector2i.ZERO, source.size))
    if recorded.whole():
        var gathered := _wholes.of(layer, source.format, _runner)
        _runner.run_whole(recorded, compute, _preview, gathered, grid_pos, work, mask, false, halvings)
    else:
        _runner.reads_canvas_of(layer)
        _runner.run(recorded, compute, _preview, source, layer.get_field, grid_pos, work, mask)
    return _preview


## *scratch*, the composite of the scope *group* at *grid_pos*, filtered as
## [method filtered] filters, with its neighbours read from the group's
## composite the sweep kept beside it rather than from the group, which stores
## nothing.
##
## The scratch is copied into the group's [SaFilterHalo] and the chain reads the halo's
## chunk and not the scratch, because the scratch holds the composite over *region*
## alone and a neighbourhood pass reads its own chunk past the region too. The sweep
## composited the halo's chunk wider, and a scratch past its region holds whatever
## chunk last used the slot, which shows as a yellow smear under the canvas's bottom
## edge.
func filtered_scope(group: SaLayer, scratch: SaTexture, grid_pos: Vector2i, region: Rect2i) -> SaTexture:
    var halo: SaFilterHalo = _scope_halos.get(group.get_instance_id(), null)
    if halo == null:
        return filtered(group, scratch, grid_pos, region)
    var covered := region if region.size.x > 0 else Rect2i(Vector2i.ZERO, scratch.size)
    var kept := halo.take(grid_pos, scratch.format)
    _copy(scratch, covered.position, kept, covered)
    return filtered(group, kept, grid_pos, region, halo.layer, halo.gathered(scratch.format))


## Where the active layer and its live stroke have to be composited before the
## pass proper, grid position -> Rect2i in chunk-local pixels: the positions a
## neighbourhood pass of that layer's own reads a neighbour from, so a stroke
## under a blur is not read there as the layer without it.
##
## The compositor keeps the two composited over these positions in a [SaFilterHalo] and
## hands it to [method filtered] as the neighbours. The set is the dirty regions
## grown by twice the chain's reach, which is what a pass reads of the chunk
## beside it, kept to the positions that hold paint and to nothing else, so a
## neighbour that holds none reads transparent as it does without a stroke.
##
## A record that reads the whole node reads a texel the dirty regions never
## reached, so the sweep takes in the stroke's positions and not the layer's:
## where the stroke holds nothing, the gather [method filtered] reads takes the
## layer's own chunk, and a stroke's first frame copies its chunks alone. A
## position painted since the last composite is swept over its whole chunk, as
## the halo chunk is the gathered source and a texel outside the region would
## read what it held before. Every other one is swept over an empty region,
## which [method SaFilterHalo.fill] reads as keeping what the halo holds.
##
## Static and read off the records' cached passes, the way [method read_region]
## is, so the compositor asks this of no chain: `spilled` has built every pass
## before a composite asks. Empty when the layer carries no neighbourhood pass
## and none that reads the whole node, or the stroke buffer holds no chunk,
## which is a blurred layer at rest.
static func stroke_sweep(document: SaDocument, dirty: Dictionary[Vector2i, Rect2i]) -> Dictionary[Vector2i, Rect2i]:
    if document == null:
        return {}
    var layer := document.active_layer
    var stroke := document.stroke_layer
    if layer == null or stroke == null or not stroke.visible or stroke.chunks.is_empty():
        return {}
    var reach := read_reach(layer.filters)
    var whole := SaNeighbourhoodPass.reads_whole(layer.filters)
    if reach <= 0 and not whole:
        return {}
    var swept: Dictionary[Vector2i, Rect2i] = {}
    var wide := SaNeighbourhoodPass.grown(dirty, 2 * reach)
    for grid_pos: Vector2i in wide:
        if layer.get_field(grid_pos) != null or stroke.get_field(grid_pos) != null:
            swept[grid_pos] = wide[grid_pos]
    # Last, since a whole-node pass reads the chunk past the region the ring
    # grew by and a position painted since the last composite is the wider of
    # the two. One that was not keeps what the halo holds there, an empty
    # region, since neither the layer nor the stroke changed under it, and
    # never its region alone, since the gather reads all of the halo's chunk.
    if whole:
        for grid_pos: Vector2i in swept:
            swept[grid_pos] = SaDocument.WHOLE_CHUNK if document.painted.has(grid_pos) else Rect2i()
        for grid_pos: Vector2i in stroke.chunks:
            swept[grid_pos] = SaDocument.WHOLE_CHUNK if document.painted.has(grid_pos) else swept.get(grid_pos, Rect2i())
    return swept


## The region sets the compositor composites the active scopes over before the
## pass proper, widest first, and none when no scope carries a neighbourhood
## pass. A chunk of a scope is filtered as soon as it is composited, so
## without a sweep a neighbour later in the pass would be read as the frame
## before left it. One sweep per such scope, each wider by twice the widest
## reach, so a nested one reads a neighbour its own sweep reached. Only
## positions in *contents*, where the active tier holds a chunk, are swept,
## and every other position reads as transparent.
##
## A scope whose records read the whole node holds its composite over every
## position the tier holds and not over the dirty ring alone, each over its
## whole chunk, since the halo chunk is the gathered source. One more sweep
## and not a wider first one: a neighbourhood scope beside it pays for the
## dirty set and nothing else.
func scope_sweeps(
    document: SaDocument, contents: Dictionary[Vector2i, bool], dirty: Dictionary[Vector2i, Rect2i]
) -> Array[Dictionary]:
    var reach := 0
    var read_whole := false
    var kept: Dictionary[int, SaFilterHalo] = {}
    for scope: Dictionary in document.fold.active_scopes:
        var group: SaLayer = scope[SaLayerStack.GROUP]
        # A clip scope's base runs its filters over its own paint, as a step.
        if SaLayerStack.is_clip_scope(scope) or not has_enabled(group.filters):
            continue
        var passes := _passes_of(document, group, group.filters)
        var grows := _reach(passes)
        var whole := _reads_whole(passes)
        if grows > 0 or whole:
            reach = maxi(reach, grows)
            read_whole = read_whole or whole
            var halo: SaFilterHalo = _scope_halos.get(group.get_instance_id(), SaFilterHalo.new())
            # Before the sweep renders, so the gather a whole-node pass extends
            # spans every position this one will fill.
            halo.begin(contents)
            kept[group.get_instance_id()] = halo
    _scope_halos = kept
    var sweeps: Array[Dictionary] = []
    var reached: Dictionary[Vector2i, bool] = {}
    var wide := dirty
    for _level in kept.size():
        wide = SaNeighbourhoodPass.grown(wide, 2 * reach)
        var swept: Dictionary[Vector2i, Rect2i] = {}
        for grid_pos: Vector2i in wide:
            if contents.has(grid_pos):
                swept[grid_pos] = wide[grid_pos]
                reached[grid_pos] = true
        sweeps.push_front(swept)
    if read_whole:
        var every: Dictionary[Vector2i, Rect2i] = {}
        for grid_pos: Vector2i in contents:
            every[grid_pos] = SaDocument.WHOLE_CHUNK
            reached[grid_pos] = true
        sweeps.append(every)
    for halo: SaFilterHalo in kept.values():
        halo.only(reached)
    return sweeps


## The regions the composite under the root's filters covers: *dirty* itself,
## or, when the root carries a neighbourhood pass, every region grown by twice
## the chain's reach and cut to the canvas, so the canvas holds an unfiltered
## composite as far as a dirty texel's halo reads. What the growth reaches
## outside *dirty* holds a filtered composite nothing asked to change, and it
## is kept here to go back after the root's filters. Called before the canvas
## is cleared.
##
## A root that reads the whole node has its [SaRootGather] say first what the
## composite under it covers, every position it gathers when it gathers anew
## and, when nothing but the gather is read, only the positions that changed
## beneath it.
func root_regions(document: SaDocument, canvas: SaTexture, dirty: Dictionary[Vector2i, Rect2i]) -> Dictionary[Vector2i, Rect2i]:
    var passes := _root_passes(document)
    var reach := _reach(passes)
    if canvas != null and _reads_whole(passes):
        dirty = _root_gather.composited(document, canvas, dirty, reach == 0 and _first_whole(passes))
    if reach == 0 or canvas == null:
        _root_halo.only({})
        _root_saved.only({})
        return dirty
    var wide: Dictionary[Vector2i, Rect2i] = {}
    var saved: Dictionary[Vector2i, Rect2i] = {}
    var grown := SaNeighbourhoodPass.grown(dirty, 2 * reach)
    for grid_pos: Vector2i in grown:
        var origin := grid_pos * SaLayer.CHUNK_SIZE
        var region := (grown[grid_pos] as Rect2i).intersection(Rect2i(-origin, canvas.size))
        if region.size.x <= 0 or region.size.y <= 0:
            continue
        wide[grid_pos] = region
        if dirty.get(grid_pos, Rect2i()) != region:
            saved[grid_pos] = region
    _root_saved.only(SaTyped.positions(saved))
    for grid_pos: Vector2i in saved:
        var region: Rect2i = saved[grid_pos]
        _copy(canvas, grid_pos * SaLayer.CHUNK_SIZE + region.position, _root_saved.take(grid_pos, canvas.format), region)
    return wide


## The document's root filters run in order over *dirty* of the canvas, which
## is rewritten there. *wide* is what [method root_regions] answered and what
## the canvas now holds unfiltered. Nothing when the root carries no filter.
##
## Through the scratch and back rather than in place on the canvas, for two
## reasons. A dirty region is not aligned to the workgroup and a point kernel
## stops at the texture's edge and nowhere else, so in place the threads past
## the region would filter texels that already hold a filtered composite. And a
## record's mask is a chunk, read in chunk-local pixels, which a canvas position
## is not.
##
## A neighbourhood pass reads the root's [SaFilterHalo], the canvas copied before any
## chunk is filtered, and the ring the growth composited gets the filtered composite
## it held back. Reading transparent there shows as a darker band along the chunk
## grid. A pass that reads the whole node reads the canvas the [SaRootGather] took
## before any of them ran, since the root stores no chunk of its own, and writes
## every position it gathered when it gathered anew.
func filter_root(
    document: SaDocument, canvas: SaTexture, dirty: Dictionary[Vector2i, Rect2i], wide: Dictionary[Vector2i, Rect2i]
) -> void:
    if document == null or canvas == null:
        return
    var passes := _root_passes(document)
    var whole: SaNeighbourhoodPass.Whole = null
    if _reads_whole(passes):
        whole = _root_gather.gathered(canvas)
        dirty = _root_gather.written(dirty)
    else:
        _root_gather.let_go()
    if passes.is_empty():
        return
    var reach := _reach(passes)
    if reach > 0:
        _root_halo.only(SaTyped.positions(wide))
        var side := Rect2i(0, 0, SaLayer.CHUNK_SIZE, SaLayer.CHUNK_SIZE)
        for grid_pos: Vector2i in wide:
            var region: Rect2i = wide[grid_pos]
            var at := grid_pos * SaLayer.CHUNK_SIZE + region.position
            var halo := _root_halo.take(grid_pos, canvas.format)
            # A chunk the canvas ends inside is read past the canvas's edge by
            # the chunk beside it, and a halo chunk holds nothing it was not
            # given, so that part is cleared to read as transparent. It shows
            # as a yellow smear under the bottom edge.
            if not Rect2i(-grid_pos * SaLayer.CHUNK_SIZE, canvas.size).encloses(side):
                _clear(halo, region.grow(2 * reach).intersection(side))
            _copy(canvas, at, halo, region)
        for grid_pos: Vector2i in _root_saved.positions():
            var region: Rect2i = wide[grid_pos]
            var at := grid_pos * SaLayer.CHUNK_SIZE + region.position
            _copy(_root_saved.layer.get_field(grid_pos), region.position, canvas, Rect2i(at, region.size))
    var everything := document.selection.everything()
    var straight := _straight(passes, whole)
    for grid_pos: Vector2i in dirty:
        var origin := grid_pos * SaLayer.CHUNK_SIZE
        var on_canvas := Rect2i(-origin, canvas.size)
        # The canvas ends inside its last chunk unless its size is a multiple
        # of the chunk's, and a copy may not reach past it.
        var covered := (dirty[grid_pos] as Rect2i).intersection(on_canvas)
        if covered.size.x <= 0 or covered.size.y <= 0:
            continue
        var at := Rect2i(origin + covered.position, covered.size)
        if straight != null and _fills_groups(at, canvas.size):
            _runner.run_whole(straight, _compute(straight.shader), canvas, whole, Vector2i.ZERO, at, everything, true)
            continue
        if straight != null:
            # Another list may not open while this one is.
            _compute(straight.shader).list_end()
        var side := Vector2i(SaLayer.CHUNK_SIZE, SaLayer.CHUNK_SIZE)
        var scratch := _scratch_for(canvas.format, side)
        if reach == 0:
            # A first pass that reads the whole node writes every texel of the
            # work from the gather and reads none of the scratch, and the
            # canvas there may hold last frame's filtered composite.
            if not _first_whole(passes):
                _copy(canvas, origin + covered.position, scratch, covered)
            _dispatch(passes, grid_pos, covered, everything, _nothing, null, whole)
        else:
            # Grown as [method filtered] grows a node's work, for a chain whose
            # later passes read what the earlier ones wrote around the region.
            var work := covered.grow(reach).intersection(Rect2i(Vector2i.ZERO, side)).intersection(on_canvas)
            _copy(_root_halo.layer.get_field(grid_pos), work.position, scratch, work)
            _dispatch(passes, grid_pos, work, everything, _root_halo.layer.get_field, null, whole)
        _copy(_scratch, covered.position, canvas, at)
    if straight != null:
        _compute(straight.shader).list_end()


## The root's enabled records that have a pass, none when it carries none.
func _root_passes(document: SaDocument) -> Array:
    if document == null or not has_enabled(document.root_filters):
        return []
    return _passes_of(document, null, document.root_filters)


## Whether the first of *passes* reads the whole node, so what the scratch holds
## before it is never read: a whole-node kernel reads the gather alone and
## writes every texel of its work.
static func _first_whole(passes: Array) -> bool:
    if passes.is_empty():
        return false
    var head: Array = passes[0]
    var first := _gather_of(head)
    return first != null and first.whole()


## The one pass of *passes* when it reads the whole node through no mask of its
## own and *whole* holds a gather, which [method filter_root] runs straight into
## the canvas, every chunk under one compute list, and null otherwise. Its kernel
## reads the gather alone and no chunk writes where another reads, so the chunks
## need no barrier between them. Through the scratch it was a kernel and a copy a
## chunk, two lists each, 80 for the 40 chunks a kaleidoscope makes stale.
static func _straight(passes: Array, whole: SaNeighbourhoodPass.Whole) -> SaNeighbourhoodPass:
    if passes.size() != 1 or not _first_whole(passes) or whole == null or whole.texture == null:
        return null
    var record: SaAttachedFilter = passes[0][1]
    var mask := record.mask
    var head: Array = passes[0]
    return null if mask != null and mask.enabled else _gather_of(head)


## Whether a dispatch over *area* of a canvas of *size* writes *area* alone. A
## kernel stops at its target's edge and nowhere else, so the groups past an
## area whose side is no multiple of theirs would write the canvas beside it.
static func _fills_groups(area: Rect2i, size: Vector2i) -> bool:
    var end := area.end
    var x := area.size.x % SaCompute.WORKGROUP_SIZE == 0 or end.x >= size.x
    return x and (area.size.y % SaCompute.WORKGROUP_SIZE == 0 or end.y >= size.y)


## Whether any of *passes* reads the whole node, which is what makes the node
## it hangs on gather every position it holds.
static func _reads_whole(passes: Array) -> bool:
    for pair: Array in passes:
        var gather := _gather_of(pair)
        if gather != null and gather.whole():
            return true
    return false


## How far *passes* read past a texel of a chunk *side* texels across, the
## halos of their neighbourhood passes added, which is what [method filtered]
## grows a node's work by. In document pixels at the default side.
static func _reach(passes: Array, side: int = SaChunk.SIZE) -> int:
    var reach := 0
    for pair: Array in passes:
        var gather := _gather_of(pair)
        if gather != null:
            reach += gather.halo_at(side)
    return reach


## The pass of *pair*, one of the `[SaPointPass, SaAttachedFilter]` pairs
## `_passes_of` builds, when it is a neighbourhood pass, and null when it reads a
## texel alone.
static func _gather_of(pair: Array) -> SaNeighbourhoodPass:
    var held: Variant = pair[0]
    return held if held is SaNeighbourhoodPass else null


## The enabled records of *records* that have a pass, each with the mask it
## reads, in order: an Array of `[SaPointPass, SaAttachedFilter]`.
##
## In order except for a record whose filter [method SaFilter.finishes], which
## runs after every other record of the node wherever it sits in the array, so
## a dither quantises the picture the other records made. Two finishing records
## keep their order between them. The array itself is not touched: the docker
## shows what the painter put there, and the order is the chain's reading of it.
func _passes_of(document: SaDocument, node: SaLayer, records: Array[SaAttachedFilter]) -> Array:
    var passes: Array = []
    var finishing: Array = []
    _runner.reads_canvas_of(document)
    for kept: SaNeighbourhoodPass.Runner in _reaches.values():
        kept.reads_canvas_of(document)
    _canvas_of = document.get_instance_id() if document != null else 0
    for record in records:
        if record == null or not record.enabled:
            continue
        var recorded := _pass_of(document, node, record)
        if recorded == null:
            continue
        if finishes(record):
            finishing.append([recorded, record])
        else:
            passes.append([recorded, record])
    passes.append_array(finishing)
    return passes


## Whether *record*'s filter runs after every other record of its node, false
## for a record no installed module answers.
func finishes(record: SaAttachedFilter) -> bool:
    var filter := registry.get_filter(record.key) if registry != null and record != null else null
    return filter != null and filter.finishes()


## Whether a filter of *document* already forms the picture the screen shows.
##
## [SaFilterPicture] owns the walk over the two lists a record can stand in, and
## this passes it the registry and nothing else, so the chain is the one place a
## key becomes a filter and the view is the one place the answer is used.
func covers_the_picture(document: SaDocument) -> bool:
    return SaFilterPicture.covers(registry, document)


## The pass *record* evaluates to, built once per revision: `touch()` drops the
## cached one, and nothing else makes this run the filter again. **The rejected
## alternative** is running `run` per chunk, which rebuilds a buffer and so a
## uniform set per chunk per frame, the cost the whole point pass exists to
## stop.
func _pass_of(document: SaDocument, node: SaLayer, record: SaAttachedFilter) -> SaPointPass:
    var cached := record.cached_pass as SaPointPass
    if cached != null:
        return cached
    var id := record.get_instance_id()
    if _failed.get(id, -1) == record.revision:
        return null
    var filter := registry.get_filter(record.key) if registry != null else null
    if filter == null:
        _failed[id] = record.revision
        SaProblems.report("SaFilterChain", "no installed module registers the filter %s, so it is skipped." % record.key)
        return null
    # The registry's one instance may be a dialog's, so the values it held go
    # back once the record has run.
    var shown := filter.parameters()
    filter.set_parameters(record.parameters)
    # A preview context, so a filter that writes pixels from its `run` writes
    # nothing here: the chain reads a recorded pass and never a layer.
    var ctx := SaFilterContext.new(document, node, registry.owner_of(record.key), filter.title(), true)
    var ran := SaFilterApply.call_run(filter, ctx)
    filter.set_parameters(shown)
    if not ran or ctx.point == null:
        _failed[id] = record.revision
        SaProblems.report("SaFilterChain", "the filter %s recorded no point pass, so it is skipped while attached." % record.key)
        return null
    _failed.erase(id)
    record.cached_pass = ctx.point
    if ctx.point is SaNeighbourhoodPass:
        _unspilled = maxi(_unspilled, (ctx.point as SaNeighbourhoodPass).halo())
    return ctx.point


## The scratch at *format* and *side*, kept for the next call that asks for
## them.
func _scratch_for(format: int, side: Vector2i) -> SaTexture:
    if _scratch == null or _scratch.format != format or _scratch.size != side:
        var key := "%d %d %d" % [format, side.x, side.y]
        if not _scratches.has(key):
            _scratches[key] = SaTexture.new(side, format)
        _scratch = _scratches[key]
    return _scratch


## Copies the rectangle that starts at *from* in *source* onto *covered* of
## *target*. The copy and every dispatch between the two cover the region alone
## (hard rule 2). A kernel and not `texture_copy`, for the reason
## `copy_region.gmacs` gives.
func _copy(source: SaTexture, from: Vector2i, target: SaTexture, covered: Rect2i) -> void:
    var compute := _compute("copy_region")
    compute.use_storage_format(source.format)
    compute.set_texture(0, target.rid)
    compute.set_texture(1, source.rid)
    compute.set_push_constant_float_array(
        PackedFloat32Array([from.x, from.y, covered.position.x, covered.position.y, covered.size.x, covered.size.y, 0.0, 0.0])
    )
    compute.dispatch_kernel("copy_region", SaCompute.groups_for(covered.size.x), SaCompute.groups_for(covered.size.y), 1)


## Clears *area* of *target* to transparent. A dispatch and not
## `texture_clear`, for the reason [SaNeighbourhoodPass.Runner] gives.
func _clear(target: SaTexture, area: Rect2i) -> void:
    var compute := _compute("clear")
    compute.use_storage_format(target.format)
    compute.set_texture(0, target.rid)
    compute.set_push_constant_float_array(
        PackedFloat32Array([0.0, 0.0, area.position.x, area.position.y, area.size.x, area.size.y, 0.0, 0.0])
    )
    compute.dispatch_kernel("clear_chunk", SaCompute.groups_for(area.size.x), SaCompute.groups_for(area.size.y), 1)


## Every pass in order over *covered* of the scratch, each in place on what the
## one before it wrote. *everything* is the document's 1 by 1 mask that reads as
## one, bound where a record has no coverage of its own: the document's selection
## is not read here, because an attach under a selection copies it into the
## record's mask, which outlives it. *neighbour* answers the chunk beside this
## one a neighbourhood pass gathers, by grid position, and *stored* is the layer
## a whole-node pass gathers, null where there is none to gather. *whole* is
## what the root's gather answered, where the node a whole-node pass reads is
## not a layer. *into* is written in place of the scratch, a neighbour's strip.
func _dispatch(
    passes: Array,
    grid_pos: Vector2i,
    covered: Rect2i,
    everything: SaTexture,
    neighbour: Callable,
    stored: SaLayer,
    whole: SaNeighbourhoodPass.Whole = null,
    into: SaTexture = null
) -> void:
    into = into if into != null else _scratch
    for index in passes.size():
        var pair: Array = passes[index]
        var recorded: SaPointPass = pair[0]
        var record: SaAttachedFilter = pair[1]
        var coverage: SaTexture = null
        if record.mask != null and record.mask.enabled:
            coverage = _at_side(record.mask.coverage(grid_pos), into.size.x)
        var compute := _compute(recorded.shader)
        var mask := coverage if coverage != null else everything
        if recorded is SaNeighbourhoodPass and (recorded as SaNeighbourhoodPass).whole():
            var gathered: SaNeighbourhoodPass.Whole = whole if whole != null else _wholes.of(stored, into.format, _runner)
            if gathered == null or gathered.texture == null or into.size.x != SaChunk.SIZE:
                _skip_whole(record, into.size.x != SaChunk.SIZE)
                continue
            _runner.run_whole(recorded as SaNeighbourhoodPass, compute, into, gathered, grid_pos, covered, mask)
            continue
        if recorded is SaNeighbourhoodPass:
            # The neighbours as the records before left them, see
            # [SaChainedNeighbours], and the padded copy is taken before the
            # kernel writes, so *into* is both what is read and what is written.
            var run := func(before: Array, at: Vector2i, strip: Rect2i, texture: SaTexture) -> void:
                _dispatch(before, at, strip, everything, neighbour, stored, whole, texture)
            var around := _around.around(passes, index, grid_pos, covered, into.size.x, into.format, neighbour, run)
            var runner := _runner_at((recorded as SaNeighbourhoodPass).halo_at(into.size.x))
            runner.run(recorded as SaNeighbourhoodPass, compute, into, into, around, grid_pos, covered, mask)
            continue
        compute.use_storage_format(into.format)
        compute.set_texture(0, into.rid)
        compute.set_texture(SaSelection.BINDING, mask.rid)
        recorded.bind(compute)
        compute.set_push_constant_float_array(recorded.push_for(covered.position, grid_pos * SaChunk.SIZE))
        compute.dispatch_kernel(recorded.kernel, SaCompute.groups_for(covered.size.x), SaCompute.groups_for(covered.size.y), 1)


## The runner of a pass gathering *reach* texels around its chunk, made the
## first time and kept, reading the canvas [method _passes_of] last named.
func _runner_at(reach: int) -> SaNeighbourhoodPass.Runner:
    if not _reaches.has(reach):
        var made := SaNeighbourhoodPass.Runner.new()
        var document := instance_from_id(_canvas_of) as SaDocument if _canvas_of != 0 else null
        if document != null:
            made.reads_canvas_of(document)
        _reaches[reach] = made
    return _reaches[reach]


## Says once per record that its whole-node pass had nothing to gather: the
## document's root, or a group being painted in, whose composite is built a
## chunk at a time and never held whole.
## A node at twice the document's resolution, *finer*, is the other case: the
## gather takes chunks at the document's side alone, so `attach` refuses such a
## record there and one that got on another way is skipped.
func _skip_whole(record: SaAttachedFilter, finer: bool = false) -> void:
    var id := record.get_instance_id()
    if _whole_skipped.has(id):
        return
    _whole_skipped[id] = true
    var why := TranslationServer.translate("%s needs the whole layer and is skipped here.")
    if finer:
        why = TranslationServer.translate(
            "%s needs the whole layer, which a layer at twice the resolution cannot give yet, so it is skipped."
        )
    SaProblems.report("SaFilterChain", why % record.key)


## *mask*, a coverage at the document's resolution, enlarged to *side*, the
## side of the chunk it masks, so a kernel reading it at its own texel
## reads the pixel that texel lies in. Enlarged once a frame, which is one
## evaluation, and made anew after, since a painted mask changes in place.
func _at_side(mask: SaTexture, side: int) -> SaTexture:
    if mask == null or side == SaChunk.SIZE:
        return mask
    var frame := Engine.get_process_frames()
    if frame != _masks_frame:
        _masks = SaFilterDensity.Masks.new()
        _masks_frame = frame
    return _masks.at(mask, side)


## The first chunk *stored* holds beside *grid_pos*, null when it holds none or
## *reach* is zero, which is a position nothing can spill into.
static func _beside(stored: SaLayer, grid_pos: Vector2i, reach: int) -> SaTexture:
    if reach <= 0:
        return null
    for dy: int in [-1, 0, 1]:
        for dx: int in [-1, 0, 1]:
            var texture := stored.get_field(grid_pos + Vector2i(dx, dy))
            if texture != null:
                return texture
    return null


## A chunk *stored* holds, when one of *passes* reads the whole node and writes
## past it, so a position it lands on has a format and a size to stand a
## cleared chunk in with. Null otherwise, which is a position nothing reaches.
static func _any_held(stored: SaLayer, passes: Array) -> SaTexture:
    if stored.chunks.is_empty():
        return null
    for pair: Array in passes:
        var recorded := _gather_of(pair)
        if recorded != null and recorded.whole() and recorded.writes != SaNeighbourhoodPass.WRITES_NODE:
            for grid_pos: Vector2i in stored.chunks:
                var texture := stored.get_field(grid_pos)
                if texture != null:
                    return texture
    return null


## The neighbour of a node that stores no chunk to read one from.
func _nothing(_grid_pos: Vector2i) -> SaTexture:
    return null


func _compute(shader: String) -> SaCompute:
    if not _computes.has(shader):
        _computes[shader] = SaCompute.new(shader)
    return _computes[shader]


func _notification(what: int) -> void:
    if what == NOTIFICATION_PREDELETE:
        # The textures first, while the device is still there, then the
        # computes, whose own PREDELETE frees their pipelines.
        _scratch = null
        _scratches.clear()
        _preview = null
        _root_halo = null
        _root_saved = null
        _root_gather.let_go()
        _scope_halos.clear()
        _wholes.let_go()
        _around = null
        _runner = null
        _reaches.clear()
        _computes.clear()

## A composite before a node's filters, kept at the grid positions a pass reads
## it from and nowhere else, and the same shape the compositor keeps the active
## layer's live stroke in. A layer that is nobody's child, the way the fold's
## caches are, so [method SaFilterChain.filtered] reads it as it reads any
## neighbours, and a position it holds no chunk at reads as transparent.
