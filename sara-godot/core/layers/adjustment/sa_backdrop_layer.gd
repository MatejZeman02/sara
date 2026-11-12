## The adjustment layer: a layer that stores nothing and whose pixels are the
## backdrop below it run through its own attached filters, and the step the
## compositor takes at its place in the walk.
##
## The kind is the effect layer with an input of *below*, beside the attached
## filter, so any filter can also be a layer. Attaching stays the default, and
## this is the form a painter picks.
##
## **Its result replaces the backdrop, it does not lie over it.** A layer's
## composite is Porter-Duff source over, and the source here is the backdrop
## filtered, so over would count the backdrop's coverage twice wherever it is
## not opaque. The step mixes the backdrop towards the filtered copy in the
## layer's blend mode, by its opacity and its mask, and keeps the backdrop's
## alpha, the way Photoshop's and Krita's adjustment layers do. Clipped to a
## base, its backdrop is the base's plate in the compositor's `clip_group`, so
## it adjusts the base and what is clipped under it alone. Over one chunk's
## region it
##
## 1. copies the backdrop out of whatever the walk is writing, the canvas, a
##    scope's scratch or a cache chunk,
## 2. runs the layer's enabled records over the copy through
##    `SaFilterChain.filtered`, as a node's records run over its chunk,
## 3. makes the result opaque, so the mask and the opacity alone say how far
##    the mix goes, and masks it,
## 4. composites that in the layer's blend mode over an opaque copy of the
##    backdrop, which is the mix in the mode, whichever mode it is,
## 5. writes the mix's colour back under the backdrop's own alpha.
##
## The layer holds no chunk, so nothing of it is saved but the recipe. Below
## the active layer it is baked into the fold's cache it sits in. Above it, over
## the canvas, [SaAdjustmentCache] keeps what the step showed per chunk where
## paint is below it, and the step runs where its input moved, grown by its
## reach, and copies the rest out of what it kept (hard rules 2 and 3).
##
## A record whose pass reads its neighbours, a blur, reads the backdrop at the
## layer's height around the chunk, which is the root's problem one height
## lower, and each place the step runs answers it the way the root does. Over
## the canvas, [SaBackdropLayer.Sweep] grows the set the walk draws, keeps the
## backdrop copied off it before the records run and gives the ring past the
## set back what it held. In a fold's cache or a merge's layer the steps below
## are drawn over every chunk first, and [method adjust_around] reads those as
## the neighbours, into copies put in at the end. A flatten draws the backdrop
## over the ring itself. A record that reads the whole node is still refused by
## `SaFilterOps`, since what it would read is the backdrop gathered whole,
## which waits for the named input's board.
class_name SaBackdropLayer
extends RefCounted

## The type id, persisted in `.sad`.
const TYPE_ID: StringName = &"adjustment"

## The name of the history step that toggles Affect all.
const AFFECT_ALL_STEP := "Affect All"

## The backdrop copied out of the target, at the target's own texels.
var _backdrop: SaTexture = null
## The filtered copy made opaque, then masked by the compositor.
var _adjusted: SaTexture = null
## The opaque backdrop the adjusted copy is composited over in the mode.
var _solid: SaTexture = null
## The backdrop kept around the walk's dirty set over the canvas, for a blur,
## and what each layer showed there, [SaAdjustmentCache].
var sweep: Sweep = null


## *caching* says whether the walk over the canvas keeps what each adjustment
## layer showed, false for a suite's reference walk.
func _init(caching: bool = true) -> void:
    sweep = Sweep.new(SaAdjustmentCache.new(caching))


## The kind as it registers through the door, from `skeleton_module.gd`. The
## plain schema, because `SaLayerTypeDescriptor.is_valid` refuses an empty one,
## and a chunk is never allocated on it.
static func descriptor() -> SaLayerTypeDescriptor:
    var made := SaLayerTypeDescriptor.create(TYPE_ID, SaFieldSpec.default_schema())
    made.display_name = "Adjustment Layer"
    made.icon_name = "wrench"
    made.hint = "Runs a filter over every layer below it and leaves their paint as it is. You choose the filter next."
    made.input = SaLayerTypeDescriptor.INPUT_BELOW
    return made


## The record that is *layer*'s own, the one its row stands for: the first it
## holds, which runs first over the backdrop. Null for a layer that is not an
## adjustment layer, and for one with no record left. When the first is taken
## off, the next is the layer's own by this rule, with nothing stored to move.
static func own_filter(layer: SaLayer) -> SaAttachedFilter:
    return layer.filters[0] if layer != null and layer.is_adjustment() and not layer.filters.is_empty() else null


## Whether the step would change anything: a record to run, or a mode that is
## not Normal, since a Multiply adjustment with nothing to run still multiplies
## the backdrop by itself.
static func changes(layer: SaLayer, mode_id: StringName) -> bool:
    return SaFilterChain.has_enabled(layer.filters) or mode_id != SaLayer.BLEND_MODE.NORMAL


## Adjusts *region* of the chunk at *grid_pos* in *target*, which holds the
## backdrop at *offset*, by *layer* in *mode_id* at *opacity*. Clipped to a
## base, it is handed the base's plate as *target*, so it adjusts the base
## alone. *compositor* is the walk's, and places the composite in a display
## chunk's walk. The colour space and the
## blend reference white are the layer's document's, the one the walk reads.
##
## *around*, when given, holds the backdrop at this chunk and the chunks beside
## it, at the document's resolution, and a record that reads its neighbours
## reads them there. Without it the walk over the canvas answers from
## [member sweep], and anywhere else the backdrop is this chunk alone and a
## neighbour reads as transparent.
func adjust(
    compositor: SaCompositor,
    target: SaTexture,
    layer: SaLayer,
    mode_id: StringName,
    opacity: float,
    grid_pos: Vector2i,
    offset: Vector2,
    region: Rect2i,
    around: SaLayer = null
) -> void:
    var document := layer.get_parent() as SaDocument if layer != null else null
    if target == null or document == null or not changes(layer, mode_id):
        return
    if around == null:
        around = sweep.around(compositor, target, layer)
    var step := sweep.step(compositor, target, layer)
    if step == null:
        _adjust(compositor, target, layer, mode_id, opacity, grid_pos, offset, region, around)
        return
    # Over the canvas a step the cache plans runs the layer where what is below
    # it moved, keeps that, and shows the rest of what it is asked from the
    # chunk it kept, which is the layer's output over the same backdrop.
    var origin := grid_pos * SaLayer.CHUNK_SIZE
    var runs: Rect2i = step.runs[grid_pos].intersection(region) if step.runs.has(grid_pos) else Rect2i()
    var shows: Rect2i = step.shows[grid_pos].intersection(region) if step.shows.has(grid_pos) else Rect2i()
    var kept := step.chunk(grid_pos, target.format)
    if runs.has_area():
        _adjust(compositor, target, layer, mode_id, opacity, grid_pos, offset, runs, around)
        if kept != null:
            _copy(compositor, target, origin + runs.position, kept, runs)
    if kept != null and shows.has_area() and not runs.encloses(shows):
        _copy(compositor, kept, shows.position, target, Rect2i(origin + shows.position, shows.size))


## [method adjust] over *region*, the step itself.
func _adjust(
    compositor: SaCompositor,
    target: SaTexture,
    layer: SaLayer,
    mode_id: StringName,
    opacity: float,
    grid_pos: Vector2i,
    offset: Vector2,
    region: Rect2i,
    around: SaLayer
) -> void:
    var document := layer.get_parent() as SaDocument
    var space := document.color_space
    var blend_white := document.blend_reference_white
    var covered := region if region.size.x > 0 else SaDocument.WHOLE_CHUNK
    var at := compositor.detail.placed(target, offset, covered, 1.0)
    var side := Vector2i(Vector2(SaDocument.WHOLE_CHUNK.size) / at.density)
    _backdrop = _made(_backdrop, side, target.format)
    _solid = _made(_solid, side, target.format)
    if compositor.detail.active():
        compositor.detail.adopt(_solid)
    var from := Vector2i(at.offset) + at.region.position
    _copy(compositor, target, from, _backdrop, at.region)
    var held := around.get_field(grid_pos) if around != null else null
    var filtered: SaTexture = null
    if held != null:
        # The kept chunk holds the backdrop past the region as far as the
        # records read, and the copy above holds it over the region alone.
        filtered = compositor.filter_chain.filtered(layer, held, grid_pos, covered, around)
    else:
        filtered = compositor.filter_chain.filtered(layer, _backdrop, grid_pos, covered)
    if filtered == null:
        return
    _adjusted = _made(_adjusted, filtered.size, target.format)
    # The filtered copy is at the target's texels or brought down to the
    # document's, and each copy below reads it at its own.
    var own := at.region if filtered.size == side else covered
    _run(compositor, "opaque", _adjusted, filtered, Vector2.ZERO, own, space, blend_white)
    _run(compositor, "opaque", _solid, _backdrop, Vector2.ZERO, at.region, space, blend_white)
    var source := compositor.masked(layer, _adjusted, grid_pos, covered)
    compositor.composite_chunk(_solid, source, mode_id, opacity, Vector2.ZERO, space, blend_white, covered)
    _run(compositor, "keep_alpha", target, _solid, Vector2(at.offset), at.region, space, blend_white)


## Whether *layer* is an adjustment layer whose records read the pixels around
## the one they write, as *chain* evaluates them.
static func reads_around(chain: SaFilterChain, layer: SaLayer) -> bool:
    return layer != null and layer.is_adjustment() and chain.reach_of(layer) > 0


## *grid_pos* and the eight positions around it, where a blur carries what
## is at *grid_pos*.
static func ring(grid_pos: Vector2i) -> Array[Vector2i]:
    var out: Array[Vector2i] = []
    for dy: int in [-1, 0, 1]:
        for dx: int in [-1, 0, 1]:
            out.append(grid_pos + Vector2i(dx, dy))
    return out


## *layer* adjusting every chunk of *held* at *positions*, where *held* holds
## the backdrop, a fold's cache or the layer a merge writes into. Each chunk is
## adjusted in a copy reading *held*'s chunks as its neighbours, and the copies
## go in at the end, because a chunk written a moment ago is not the backdrop
## the chunk beside it reads.
func adjust_around(
    compositor: SaCompositor, held: SaLayer, layer: SaLayer, mode_id: StringName, opacity: float, positions: Array
) -> void:
    var written: Dictionary[Vector2i, SaTexture] = {}
    for grid_pos: Vector2i in positions:
        var chunk := held.get_field(grid_pos)
        if chunk == null:
            continue
        var whole := Rect2i(Vector2i.ZERO, chunk.size)
        var copy := SaTexture.new(chunk.size, chunk.format)
        _copy(compositor, chunk, Vector2i.ZERO, copy, whole)
        adjust(compositor, copy, layer, mode_id, opacity, grid_pos, Vector2.ZERO, SaDocument.WHOLE_CHUNK, held)
        written[grid_pos] = copy
    for grid_pos: Vector2i in written:
        var copy := written[grid_pos]
        _copy(compositor, copy, Vector2i.ZERO, held.get_field(grid_pos), Rect2i(Vector2i.ZERO, copy.size))


## Folds *folded* into *cache* over *needed* when a step of it reads the chunks
## around its own, and answers whether it did. A blur carries the backdrop into
## the ring around what is below it, as a blurred group would, so *needed*
## grows by the ring inside the grid and *visible*. The steps are drawn one at a
## time over every needed chunk, each other step by *draw*, called with the
## chunk, the step and its position, so a blur reads its neighbours at its own
## height.
func fold_around(
    compositor: SaCompositor,
    cache: SaLayer,
    folded: Array[Dictionary],
    needed: Dictionary[Vector2i, bool],
    visible: Rect2,
    draw: Callable
) -> bool:
    var reading := folded.filter(func(atom: Dictionary) -> bool: return _reads(compositor, atom))
    if reading.is_empty():
        return false
    var first: Dictionary = reading[0]
    var document := SaLayerStack.layer_of(first).get_parent() as SaDocument
    var side := float(SaLayer.CHUNK_SIZE)
    var grid := Rect2i(0, 0, ceili(document.canvas_size.x / side), ceili(document.canvas_size.y / side))
    for held: Vector2i in needed.keys():
        for grid_pos: Vector2i in ring(held):
            if grid.has_point(grid_pos) and Rect2(Vector2(grid_pos) * side, Vector2(side, side)).intersects(visible):
                needed[grid_pos] = true
    for grid_pos: Vector2i in needed:
        cache.get_or_create_chunk(grid_pos).clear(Color(0, 0, 0, 0))
    for atom in folded:
        if not _reads(compositor, atom):
            for grid_pos: Vector2i in needed:
                draw.call(cache.chunks[grid_pos], atom, grid_pos)
            continue
        var layer := SaLayerStack.layer_of(atom)
        adjust_around(compositor, cache, layer, SaLayerStack.mode_of(atom), SaLayerStack.opacity_of(atom), needed.keys())
    return true


## Adjusts every chunk *lower* holds by *upper*, a merge down, when *upper*
## reads the paint around each chunk, and answers whether it did. *state* keeps
## each chunk as it was for the merge's undo, and each one written waits to be
## resolved again.
func merge_around(compositor: SaCompositor, lower: SaLayer, upper: SaLayer, state: Dictionary[Vector2i, Variant]) -> bool:
    if not reads_around(compositor.filter_chain, upper):
        return false
    var held: Array = []
    for grid_pos: Vector2i in lower.chunks.keys():
        if lower.chunks[grid_pos] != null:
            held.append(grid_pos)
            if not state.has(grid_pos):
                state[grid_pos] = lower.duplicate_chunk(grid_pos)
    adjust_around(compositor, lower, upper, upper.get_blend_mode_name(), upper.opacity, held)
    for grid_pos: Vector2i in held:
        lower.mark_unresolved(grid_pos)
    return true


## The backdrop of *node* at *grid_pos* and the eight positions around it in a
## flatten, when its records read their neighbours, and null otherwise.
## *target* holds it at *grid_pos* by now. Around it is everything drawn before
## *node* into the same composite, the members of the isolated group or the
## document holding it, and of each pass-through group between, up to *node*,
## which *draw* renders when called with the chunk, its position, the layers and
## the opacity their pass-through groups multiply them by.
func halo(compositor: SaCompositor, node: SaLayer, target: SaTexture, grid_pos: Vector2i, draw: Callable) -> SaFilterHalo:
    var document := node.get_parent() as SaDocument
    if document == null or not reads_around(compositor.filter_chain, node):
        return null
    var made := SaFilterHalo.new()
    var held := made.take(grid_pos, target.format)
    _copy(compositor, target, Vector2i.ZERO, held, Rect2i(Vector2i.ZERO, held.size))
    var path: Array[SaLayer] = [node]
    var holder := SaLayerStack.parent_of(node)
    while holder != null and not SaLayerStack.isolates(holder):
        path.push_front(holder)
        holder = SaLayerStack.parent_of(holder)
    var grid := Rect2i(Vector2i.ZERO, Vector2i((Vector2(document.canvas_size) / float(SaLayer.CHUNK_SIZE)).ceil()))
    for beside: Vector2i in ring(grid_pos):
        if beside == grid_pos or not grid.has_point(beside):
            continue
        var chunk := made.take(beside, target.format)
        compositor.clear_scratch_batch([[chunk, Rect2i(Vector2i.ZERO, chunk.size)]])
        var nodes := SaLayerStack.members(document, holder)
        # A lifted layer reads the whole tree around the chunk, the lifted
        # layers below it left out, which only a blur beside its chunk misses.
        if lifts(node):
            draw.call(chunk, beside, SaLayerStack.members(document, null), 1.0)
            continue
        var factor := 1.0
        for step in path:
            draw.call(chunk, beside, nodes.slice(0, nodes.find(step)), factor)
            factor *= step.opacity
            nodes = SaLayerStack.members(document, step)
    return made


## *node* adjusting all of *target* at *grid_pos* in a flatten by *opacity*,
## reading the neighbours [method halo] has *draw* render when its records read
## them.
func flattened(
    compositor: SaCompositor, target: SaTexture, node: SaLayer, opacity: float, grid_pos: Vector2i, draw: Callable
) -> void:
    var made := halo(compositor, node, target, grid_pos, draw)
    var around := made.layer if made != null else null
    var whole := Rect2i(Vector2i.ZERO, target.size)
    adjust(compositor, target, node, node.get_blend_mode_name(), opacity, grid_pos, Vector2.ZERO, whole, around)


## Whether the fold's step *atom* is an adjustment layer reading its neighbours.
static func _reads(compositor: SaCompositor, atom: Dictionary) -> bool:
    return reads_around(compositor.filter_chain, SaLayerStack.layer_of(atom))


## Where *layer* has drawn, which is wherever a layer below it in the document
## holds a chunk, whatever its group, since a pass-through group's adjustment
## reads them all, and wherever any layer does for one `SaBackdropLayer` lifts.
## The whole grid when one below is generated.
static func drawn_over(document: SaDocument, layer: SaLayer) -> Array[Vector2i]:
    var found: Dictionary[Vector2i, bool] = {}
    # A lifted layer draws after every other one, wherever it sits.
    var raised := lifts(layer)
    for child in document.get_children():
        var below := child as SaLayer
        if below == layer and not raised:
            break
        if below != null:
            for grid_pos: Vector2i in (
                SaLayer.grid_positions(document.canvas_size) if below.is_generated() else below.chunks.keys()
            ):
                found[grid_pos] = true
    var out: Array[Vector2i] = []
    out.assign(found.keys())
    return out


## The index of the first adjustment layer among the fold's atoms *below* with
## a layer that stores nothing or an effect layer before it, a step of its own
## which a cache from transparent would not hold, or -1.
static func first_past_a_step(below: Array[Dictionary]) -> int:
    var stepped := false
    for i in below.size():
        var layer := SaLayerStack.layer_of(below[i])
        if layer.is_adjustment() and stepped:
            return i
        stepped = stepped or layer.is_generated() or layer.is_effect()
    return -1


static func _made(scratch: SaTexture, side: Vector2i, format: int) -> SaTexture:
    if scratch == null or scratch.format != format or scratch.size != side:
        return SaTexture.new(side, format)
    return scratch


## Copies the rectangle at *from* in *source* onto *covered* of *target*, a
## dispatch and not a transfer for the reason `copy_region.gmacs` gives.
static func _copy(compositor: SaCompositor, source: SaTexture, from: Vector2i, target: SaTexture, covered: Rect2i) -> void:
    var compute := compositor.get_compute("copy_region")
    compute.use_storage_format(source.format)
    compute.set_texture(0, target.rid)
    compute.set_texture(1, source.rid)
    compute.set_push_constant_float_array(
        PackedFloat32Array([from.x, from.y, covered.position.x, covered.position.y, covered.size.x, covered.size.y, 0.0, 0.0])
    )
    compute.dispatch_kernel("copy_region", SaCompute.groups_for(covered.size.x), SaCompute.groups_for(covered.size.y), 1)


## One of the two kernels `composite.gmacs` ends on for this step, *source*
## into *destination* at *offset* over *region*, in the destination's texels,
## which are the source's in every call this step makes.
static func _run(
    compositor: SaCompositor,
    kernel: String,
    destination: SaTexture,
    source: SaTexture,
    offset: Vector2,
    region: Rect2i,
    space: SaColorSpace,
    blend_white: float
) -> void:
    var compute := compositor.get_compute("composite")
    compute.use_storage_format(destination.format)
    compute.set_texture(0, destination.rid)
    compute.set_texture(1, source.rid)
    compute.set_push_constant_float_array(SaCompute.pack_composite_params(offset, 1.0, space, 1.0, blend_white, region))
    compute.dispatch_kernel(kernel, SaCompute.groups_for(region.size.x), SaCompute.groups_for(region.size.y), 1)


func _notification(what: int) -> void:
    if what == NOTIFICATION_PREDELETE:
        _backdrop = null
        _adjusted = null
        _solid = null
        sweep = null


## **Affect all** is the adjustment layer's own property:
## what `SaLayer.affects_all` means to the fold, the walk and a flatten, and
## the one step that toggles it, below.
##
## A property rather than a place, the top of the stack in no group, so a
## global effect can sit inside a group and turn off when the group is hidden,
## which a place could not do, since an adjustment layer reads the scope it
## sits in.
##
## **A layer with it on is lifted out of its place.** Every walk that draws the
## tree, the fold the compositor walks and `SaTreeRender` for a flatten, a merge
## of the visible layers and an export, leaves it out where it sits and draws it
## after the top level's last layer, the lowest such layer first. So an
## isolated group holding it confines nothing, and what lies above its group
## is under it too. It draws only while it and every group around it are
## visible, so hiding its group turns it off, and the opacities of those
## groups multiply into its own as a pass-through group's do. Its mask and
## blend mode apply as any layer's do.
##
## **The rejected alternative** was a scope of its own: running the step at
## the layer's place with the whole picture copied in as the backdrop. What
## lies above the group would then be drawn twice, once into that backdrop and
## once over the result.


## Whether *layer* is an adjustment layer with Affect all on, which the walks
## lift out of its place.
static func lifts(layer: SaLayer) -> bool:
    return layer != null and layer.affects_all and layer.is_adjustment()


## Every lifted layer of *document*, the lowest first, which is the order their
## steps run in after the top level's last layer.
static func lifted(document: SaDocument) -> Array[SaLayer]:
    var found: Array[SaLayer] = []
    if document == null:
        return found
    for child in document.get_children():
        var layer := child as SaLayer
        if lifts(layer):
            found.append(layer)
    return found


## The opacities of every group around *layer* multiplied together, which a
## lifted layer's own opacity is drawn times, as a pass-through group's
## members are.
static func carried(layer: SaLayer) -> float:
    var factor := 1.0
    var group := SaLayerStack.parent_of(layer)
    var guard := 0
    while group != null and guard < 64:
        factor *= group.opacity
        group = SaLayerStack.parent_of(group)
        guard += 1
    return factor


## Whether *layer* and every group around it are visible, the flag alone, which
## is what a flatten reads. The canvas reads `SaLayerStack.shows`, which asks
## the same and an isolated view besides.
static func visible_through(layer: SaLayer) -> bool:
    var node := layer
    var guard := 0
    while node != null and guard < 64:
        if not node.visible:
            return false
        node = SaLayerStack.parent_of(node)
        guard += 1
    return layer != null


## Turns Affect all on *layer* of *document* to *on* as one history step,
## nothing on a layer that is not an adjustment layer or already reads so.
## Answers whether it changed anything.
static func affect_all(document: SaDocument, layer: SaLayer, on: bool) -> bool:
    if document == null or layer == null or not layer.is_adjustment() or layer.affects_all == on:
        return false
    _affect_all_apply(document, layer, on)
    var undo := _affect_all_apply.bind(document, layer, not on)
    document.history.commit_pair(AFFECT_ALL_STEP, _affect_all_apply.bind(document, layer, on), undo)
    return true


## Writes *on* and owes the fold a rebuild, since the layer changes its place in
## the walk, and marks every chunk dirty, since it changes what it reaches.
static func _affect_all_apply(document: SaDocument, layer: SaLayer, on: bool) -> void:
    layer.affects_all = on
    document.modified = true
    SaLayerOps.new(document).refresh()


## The backdrop a blur on an adjustment layer reads over the canvas, the
## answer `SaFilterChain.root_regions` and `SaFilterChain.filter_root` give the
## root, one height lower. The canvas beside a dirty chunk holds last frame's
## finished picture and not the backdrop at the layer's height, so
##
## 1. [method regions] grows the set the walk draws by twice the summed reach of
##    every adjustment layer the walk draws over the canvas, and keeps what the
##    ring past the set held before the canvas is cleared,
## 2. [method around] copies the canvas over the grown set into the layer's
##    [SaFilterHalo] the first time the walk adjusts the canvas by the layer,
##    before any of its records run, and answers it as the neighbours,
## 3. [method give_back] puts the ring back once the walk is done, since what
##    the walk drew there read a backdrop cut short.
##
## Nothing is kept and nothing is swept when no such layer is drawn, which is a
## point adjustment paying nothing. A display chunk's walk reads the halo the
## output's walk filled in the same frame, at the document's resolution.
##
## When [member cache] keeps a layer's output, the set the walk draws is the
## cache's plan rather than the growth by twice the summed reach, and each
## layer's halo is filled over what that layer reads in it.
class Sweep:
    extends RefCounted

    ## Layer instance id -> the backdrop at that layer's height over the grown set.
    var _halos: Dictionary[int, SaFilterHalo] = {}
    ## The canvas over the grown set, as it was before the walk cleared it.
    var _saved := SaFilterHalo.new()
    ## Grid position -> the rectangles of the ring past the set there, each an
    ## Array of Rect2i in chunk-local pixels.
    var _ring: Dictionary[Vector2i, Array] = {}
    ## How far every halo was grown past the set, twice the summed reach.
    var _grown_by: int = 0
    ## The canvas and the grown set of the walk in hand, until it gives back.
    var _canvas: SaTexture = null
    var _walked: Dictionary[Vector2i, Rect2i] = {}
    ## Layer instance id -> whether its halo holds the walk in hand's backdrop.
    var _filled: Dictionary[int, bool] = {}
    ## What each layer showed over the canvas, and the plan of the walk in hand.
    var cache: SaAdjustmentCache = null

    func _init(kept: SaAdjustmentCache) -> void:
        cache = kept

    ## Walks *document* over *canvas* through *compositor* in *inner* and the
    ## ring [method regions] grows it by, and gives the ring back. *named* is
    ## [method SaAdjustmentCache.plan]'s.
    func walk(
        compositor: SaCompositor,
        document: SaDocument,
        canvas: SaTexture,
        inner: Dictionary[Vector2i, Rect2i],
        visible: Rect2,
        named: bool = false
    ) -> void:
        var walked := regions(compositor, document, canvas, inner, visible, named)
        compositor.clear_canvas_chunks(canvas, walked)
        compositor.walk(canvas, document, walked, visible)
        give_back(compositor, canvas)

    ## *inner*, the regions the walk has to answer for, grown by twice the
    ## summed reach of the adjustment layers *compositor* draws over the canvas
    ## of *document*, cut to *canvas*, or by what [member cache] plans for
    ## *visible* when it keeps any. What the growth reaches past *inner* is
    ## saved to go back after the walk. *inner* itself when there is none.
    ## *named* is [method SaAdjustmentCache.plan]'s.
    func regions(
        compositor: SaCompositor,
        document: SaDocument,
        canvas: SaTexture,
        inner: Dictionary[Vector2i, Rect2i],
        visible: Rect2 = Rect2(),
        named: bool = false
    ) -> Dictionary[Vector2i, Rect2i]:
        var planned := cache.plan(compositor, document, canvas, inner, visible, named)
        var reach := 0
        var kept: Dictionary[int, SaFilterHalo] = {}
        for layer in _drawn_over_canvas(document):
            var grows := compositor.filter_chain.reach_of(layer)
            if grows > 0:
                reach += grows
                kept[layer.get_instance_id()] = _halos.get(layer.get_instance_id(), SaFilterHalo.new())
        _halos = kept
        _ring.clear()
        _filled.clear()
        _canvas = canvas
        _grown_by = 2 * reach
        if reach == 0 or canvas == null:
            _saved.drop()
            return inner
        var wide: Dictionary[Vector2i, Rect2i] = {}
        var grown := cache.walked if planned else SaNeighbourhoodPass.grown(inner, _grown_by)
        for grid_pos: Vector2i in grown:
            var origin := grid_pos * SaLayer.CHUNK_SIZE
            var region := (grown[grid_pos] as Rect2i).intersection(Rect2i(-origin, canvas.size))
            if region.size.x <= 0 or region.size.y <= 0:
                continue
            wide[grid_pos] = region
            var held: Rect2i = inner.get(grid_pos, Rect2i())
            var bands := _outside(region, held)
            if not bands.is_empty():
                _ring[grid_pos] = bands
        _saved.only(SaTyped.positions(_ring))
        for grid_pos: Vector2i in _ring:
            var region: Rect2i = wide[grid_pos]
            var kept_chunk := _saved.take(grid_pos, canvas.format)
            SaBackdropLayer._copy(compositor, canvas, grid_pos * SaLayer.CHUNK_SIZE + region.position, kept_chunk, region)
        # A region the growth passed over, an empty one, stays as it was asked.
        for grid_pos: Vector2i in inner:
            if not wide.has(grid_pos):
                wide[grid_pos] = inner[grid_pos]
        _walked = wide
        return wide

    ## The layer holding *layer*'s backdrop around the dirty set, or null when
    ## its records read no neighbour. The first call adjusting the canvas
    ## itself copies the canvas over the grown set into the halo, which is the
    ## backdrop at the layer's height, since the walk draws layer by layer. A
    ## display chunk's walk reads what the output's walk left.
    func around(compositor: SaCompositor, target: SaTexture, layer: SaLayer) -> SaLayer:
        var halo: SaFilterHalo = _halos.get(layer.get_instance_id(), null)
        if halo == null:
            return null
        if target == _canvas and not _filled.has(layer.get_instance_id()) and not compositor.detail.active():
            _filled[layer.get_instance_id()] = true
            var planned := step(compositor, target, layer)
            _fill(compositor, _canvas, halo, planned.reads if planned != null else _walked)
        return halo.layer

    ## The step [member cache] planned for *layer* in the walk in hand, when
    ## *target* is its canvas and the walk is the output's, or null.
    func step(compositor: SaCompositor, target: SaTexture, layer: SaLayer) -> SaAdjustmentCache.Step:
        if target != _canvas or target == null or compositor.detail.active():
            return null
        return cache.steps.get(layer.get_instance_id(), null)

    ## Copies *canvas* over *walked* into *halo*.
    func _fill(compositor: SaCompositor, canvas: SaTexture, halo: SaFilterHalo, walked: Dictionary[Vector2i, Rect2i]) -> void:
        halo.only(SaTyped.positions(walked))
        var side := Rect2i(0, 0, SaLayer.CHUNK_SIZE, SaLayer.CHUNK_SIZE)
        for grid_pos: Vector2i in walked:
            var region: Rect2i = walked[grid_pos]
            if region.size.x <= 0 or region.size.y <= 0:
                continue
            var origin := grid_pos * SaLayer.CHUNK_SIZE
            var kept := halo.take(grid_pos, canvas.format)
            # A chunk the canvas ends inside is read past the canvas's edge by
            # the chunk beside it, and a halo chunk holds nothing it was not
            # given, so that part reads as transparent, as the root's does.
            if not Rect2i(-origin, canvas.size).encloses(side):
                compositor.clear_scratch_batch([[kept, region.grow(_grown_by).intersection(side)]])
            SaBackdropLayer._copy(compositor, canvas, origin + region.position, kept, region)

    ## Puts the ring past the set back into *canvas* as [method regions] found it.
    func give_back(compositor: SaCompositor, canvas: SaTexture) -> void:
        for grid_pos: Vector2i in _ring:
            var kept := _saved.layer.get_field(grid_pos) if _saved.layer != null else null
            if kept == null:
                continue
            var origin := grid_pos * SaLayer.CHUNK_SIZE
            for band: Rect2i in _ring[grid_pos]:
                SaBackdropLayer._copy(compositor, kept, band.position, canvas, Rect2i(origin + band.position, band.size))
        _ring.clear()
        _canvas = null
        _walked = {}

    ## The adjustment layers the walk draws over the canvas itself: a step of
    ## either stack, and the active layer outside any isolated group.
    static func _drawn_over_canvas(document: SaDocument) -> Array[SaLayer]:
        var found: Array[SaLayer] = []
        if document == null or document.fold == null:
            return found
        for entry: Dictionary in document.fold.bottom_stack + document.fold.top_stack:
            var layer := SaLayerStack.layer_of(entry)
            if layer.is_adjustment() and layer.visible:
                found.append(layer)
        var active := document.active_layer
        if active != null and active.is_adjustment() and document.fold.active_scopes.is_empty():
            if SaLayerStack.shows(document, active) and not found.has(active):
                found.append(active)
        return found

    ## *region* without *inner*, as up to four rectangles, all of it when
    ## *inner* is empty.
    static func _outside(region: Rect2i, inner: Rect2i) -> Array[Rect2i]:
        var bands: Array[Rect2i] = []
        var cut := region.intersection(inner)
        if cut.size.x <= 0 or cut.size.y <= 0:
            bands.append(region)
            return bands
        var top := Rect2i(region.position, Vector2i(region.size.x, cut.position.y - region.position.y))
        var bottom := Rect2i(Vector2i(region.position.x, cut.end.y), Vector2i(region.size.x, region.end.y - cut.end.y))
        var left := Rect2i(Vector2i(region.position.x, cut.position.y), Vector2i(cut.position.x - region.position.x, cut.size.y))
        var right := Rect2i(Vector2i(cut.end.x, cut.position.y), Vector2i(region.end.x - cut.end.x, cut.size.y))
        for band: Rect2i in [top, bottom, left, right]:
            if band.size.x > 0 and band.size.y > 0:
                bands.append(band)
        return bands

    func _notification(what: int) -> void:
        if what == NOTIFICATION_PREDELETE:
            _halos.clear()
            _saved = null
            _canvas = null
            cache = null
