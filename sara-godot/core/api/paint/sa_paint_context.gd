## Turns a document-space region into the chunks a tool must dispatch over.
##
## Here in core rather than in each tool, so every tool that paints shares one
## tiling: the chunk grid coordinates, the 8-aligned dispatch box, the choice
## between painting straight in and through the buffer, chunk creation and the
## invalidation.
##
## It takes a *region*, not a dab. A stamp engine passes the square around one
## dab. A stroke-based engine (bristles baked from 3D hair simulation) passes the
## swept path's bounds. There is deliberately no brush-engine interface - engines
## share what they need from the document, not a lifecycle.
##
## Performance: this is per-dab code, so it holds no Callables, emits no signals
## and allocates one Target per touched chunk (typically 1-4). A walk's plain
## dabs go further and share one context, which [method aim] points at each
## dab in turn and which keeps what it looked up about each chunk it reached,
## because building a context is a large share of what a small dab costs.
class_name SaPaintContext
extends RefCounted

## Compute shaders use 8x8 workgroups. Dispatch regions are aligned to that.
const WORKGROUP: int = 8
## Where the sine of a dab's turn sits in its push constant,
## `SaDabGeometry.pack`'s order, and the mirror bit that flips its frame's y.
const TURN_SINE: int = 11
const FLIP_Y: int = 2

## A target's centre is in chunk-local document pixels, and its offset and
## workgroups are in the chunk's own texels, which are twice as many along each
## side on a double resolution layer. A kernel turns its texel into document
## pixels by `target.resolution_scale` before it measures against the centre.
## At 1.0 the two are the same numbers, so a kernel that ignores the scale
## paints an ordinary layer right. The dirty rectangles the compositor is told
## stay in
## document pixels, and the regions the stroke's snapshot is told are in
## texels, the unit it copies.
##
## **A layer drawn through a live transform**, an affine one, is painted in its
## own pixels where the map shows them under the pointer. Each
## region is taken back through the map before its targets are made, so the
## centres, the offsets and the snapshot are the layer's, [method dab] takes a
## dab's size, turn and mirror back the same way, and the dirty rectangles the
## compositor is told are taken forward again, `SaLiveTransform.painted`.
##
## **A region past a pole**, on a context that folds, lands also across the pole
## at the longitude half a turn away, read downward, by the kind's own map,
## `SaProjection.pole_folds`. The map turns the plane over, so
## [method dab] draws such a target's dab turned the other way and mirrored in
## its own y. Only the part that comes back onto the canvas is built, as with
## the wrap, so nothing past the canvas is allocated.


## One chunk to dispatch over.
class Target:
    extends RefCounted

    ## Chunk grid coordinate.
    var grid_pos: Vector2i

    ## The tile itself, for a tool that writes more than colour: an impasto brush
    ## reaches `chunk.field(&"height")` through here.
    var chunk: SaChunk

    ## The albedo field of `chunk`, which is what a colour brush paints into and
    ## the only field the compositor reads.
    var texture: SaTexture

    ## The selection mask a kernel binds for this chunk at SaSelection.BINDING:
    ## the chunk's own mask, or the 1 by 1 everything stand-in when no selection
    ## is active. Never null on a target, because a chunk the selection leaves
    ## out never becomes one. dispatch_batch binds it, and an engine dispatching
    ## on its own binds it the same way.
    var mask: SaTexture

    ## The layer this chunk belongs to: the active layer when painting directly
    ## (erase, alpha lock), otherwise the stroke buffer.
    var layer: SaLayer

    ## Dab centre in chunk-local pixels.
    var local_center: Vector2

    ## 8-aligned offset of the dispatch region within the chunk, in its texels.
    var render_offset: Vector2

    ## Workgroup counts, already clamped to at least 1.
    ##
    ## `int(width / 8.0)` truncating to zero for a sub-8px region is what produced
    ## "Dispatch amount of X compute groups (0) is zero". Clamping here fixes it
    ## once for every present and future tool instead of per tool.
    var groups_x: int = 1
    var groups_y: int = 1

    ## Copied from the chunk: texels along one document pixel, 2.0 on a double
    ## resolution layer. The offset and the workgroups are already scaled by it.
    var resolution_scale: float = 1.0
    ## Which pass of the batch this target dispatches in. A mirrored dab that
    ## lands in a chunk an earlier image already touched would race it inside
    ## one list, so it waits for the barrier a new pass brings.
    var pass_index: int = 0
    ## How far the document's wrap moved the image this target paints, in
    ## document pixels: nought for the region asked for and its symmetry's
    ## images, and a canvas width either way for the copy a wrapping kind
    ## folds back across the seam. `local_center` is already the moved one,
    ## so a stamp needs nothing of this. An engine that maps a texel back into
    ## its own stroke's frame subtracts it first, because the stroke itself
    ## never crossed the seam. It is [member landing]'s origin, and the whole
    ## move only on a context that does not fold across a pole.
    var wrap_offset: Vector2 = Vector2.ZERO
    ## The map from the region asked for to the image this target paints, in
    ## document pixels: [member wrap_offset] as a move, or on a context that
    ## folds, the kind's map over a pole and then the wrap. [method local_point]
    ## and [method dab] take a stamp through it.
    var landing: Transform2D = Transform2D.IDENTITY


var document: SaDocument
var chunk_size: int = 256

## Painting straight into the active layer instead of the stroke buffer, which is
## what erase and alpha lock require.
var draw_direct: bool = false

## The stroke changes only paint that is there, an eraser or an alpha-locked
## stroke, so a chunk the layer lacks is no target. The stamp
## brush says so for its direct route. Painting straight in is not enough to
## know it, because a suite or a module may paint colour straight in.
var keeps_to_paint: bool = false

## True when the targets are coverage rather than colour: the quick mask's
## selection, or a mask the document names as its `mask_target`. An engine
## reads this one flag to paint the chosen colour's lightness as coverage,
## `SaColorSpace.lightness` of it in the document's space, black hiding and
## white showing, so it paints either mask without asking the document which
## one it is.
var paints_coverage: bool = false

## Chunks this region touches, 1-4 for a typical dab.
var targets: Array[Target] = []
## Grid position -> the chunk-local rectangle this dab actually touched.
##
## Computed here to size the dispatch, and kept for the invalidation, so the
## compositor redraws the part of a chunk that changed rather than all 65,536
## pixels of it.
var _invalidated: Dictionary[Vector2i, Rect2i] = {}
var _layer: SaLayer = null
## The mask this context paints into, or null. Not the quick mask, which is the
## selection and is told apart by `paints_coverage` with no mask here.
var _mask: SaMask = null
## Grid position -> a target this context built there, whose chunk, texture,
## selection mask and scale [method aim] takes again rather than looking them up.
## Filled only once the context is aimed, so a context built for one dab pays
## nothing for it, and only on a layer's own chunks.
var _reached: Dictionary[Vector2i, Target] = {}
## Whether [method aim] has pointed this context, which is when it keeps
## [member _reached].
var _reaching: bool = false
## The live transform of the active layer this context paints through, or null
## for a layer drawn where it was painted.
var _live: SaLiveTransform = null
## Whether a region past a pole lands also folded across it, which a dab drawn
## on the sphere asks for and a flat one never does.
var _folds: bool = false


## The layer arrives here rather than being written on the context afterwards,
## because a private member is written by its own class only. Defaulted to
## null, which is what
## the quick mask and a context with no document both want. *mask* is the mask
## target, and its layer, for the field form, is *layer*. *live* is the map a
## stroke on the active layer is painted through. *folds* is whether a region
## past a pole lands also folded across it.
func _init(layer: SaLayer = null, mask: SaMask = null, live: SaLiveTransform = null, folds: bool = false) -> void:
    _layer = layer
    _mask = mask
    _live = live
    _folds = folds


## `region` is in document pixels. `padding` widens it so interpolated dabs cover
## chunk edges. The document's symmetry turns the one region into every region
## it stands for, so a tool that paints through here gets symmetry without
## knowing, provided it stamps at each target's own `local_center`, and
## [method for_regions] folds each of them across the seam of a document whose
## kind wraps, so the tool gets that too. *keeps* is [member keeps_to_paint],
## and binds only a direct context. *folds* lands a region past a pole also
## across it, for a dab drawn round on the sphere, `SaDabParams.stretch`.
static func for_region(
    doc: SaDocument, region: Rect2, direct: bool, padding: float = 2.0, keeps: bool = false, folds: bool = false
) -> SaPaintContext:
    var regions: Array[Rect2] = [region]
    if doc != null and doc.symmetry.is_active():
        regions = SaInfiniteCanvas.mirrored(doc, region)
    return for_regions(doc, regions, direct, padding, keeps, folds)


## Several regions in one context, each with its own targets and its own dirty
## rectangles, dispatched as one batch: mirrored dabs join one list, and only a
## chunk two of them share costs
## a barrier between them.
##
## **The wrap.** On a document whose projection
## wraps in x, a region that crosses the left or right edge lands also a
## canvas width the other way, so a dab on the seam lands whole on both
## sides, each copy with its own targets and dirty rectangles. Nothing past
## the canvas is allocated for it: the part of a
## region outside the canvas stays there, where no chunk is made, and its copy
## is the part that lands inside. It is the shape the symmetry gives, one
## region to several, and the two compose, every image of the symmetry folded
## on its own. A flat document has one landing, the region.
static func for_regions(
    doc: SaDocument, regions: Array[Rect2], direct: bool, padding: float = 2.0, keeps: bool = false, folds: bool = false
) -> SaPaintContext:
    # The quick mask: the brush paints coverage into the selection itself,
    # straight in, with no stroke buffer and no history step, because a
    # selection is a working state and not part of the picture.
    var editing := doc != null and doc.selection.editing
    # A layer's, a group's or a filter's mask, after the quick mask and before
    # the layer: the same engine paints it as coverage, and straight in, the
    # way the quick mask paints the selection.
    var mask: SaMask = doc.mask_target if doc != null and not editing else null
    if mask != null:
        return _for_mask(doc, mask, regions, padding, folds)
    # Chosen before the context exists, because the layer is a constructor
    # argument rather than something the factory writes afterwards, a private
    # member being written by its own class only. Null with no document, and
    # for the quick mask, which paints into no layer at all.
    var target_layer: SaLayer = null
    if doc != null and not editing:
        target_layer = doc.active_layer if direct else doc.stroke_layer
    var live: SaLiveTransform = SaLocalView.map_of(doc.active_layer) if target_layer != null else null

    var context := SaPaintContext.new(target_layer, null, live, folds)
    context.document = doc
    context.draw_direct = direct
    context.keeps_to_paint = keeps and direct
    if doc == null:
        return context

    if editing:
        context.draw_direct = true
        context.paints_coverage = true
        context.chunk_size = SaChunk.SIZE
        for region in regions:
            context._build_landings(region.grow(padding), null)
        return context

    if target_layer == null:
        return context
    # The page grows under paint before the targets are made, so none of them
    # falls past an edge of an infinite canvas.
    SaInfiniteCanvas.reach(doc, regions)
    context.chunk_size = target_layer.CHUNK_SIZE
    # A stroke buffered through a live transform is in the layer's pixels,
    # where the walk would draw it unmoved, so the walk is kept off it and the
    # cache draws it, until `SaLiveTransform` lets it go after the commit. Any
    # other stroke shows it, so a buffer once hidden is never left hidden.
    if not direct:
        target_layer.visible = live == null

    for region in regions:
        context._build_landings(region.grow(padding), target_layer, padding)
    return context


## The context for a stroke on *mask*. It paints straight in, with no stroke
## buffer, into the coverage `SaMask.get_or_create` answers. Two things set it
## apart from the quick mask, both deliberate: the selection is honoured, since
## a layer mask is part of the picture and the quick mask is the selection
## itself, and every chunk is snapshotted before its first dab, since a stroke
## on the picture is a history step.
static func _for_mask(doc: SaDocument, mask: SaMask, regions: Array[Rect2], padding: float, folds: bool) -> SaPaintContext:
    var owner: SaLayer = null if mask.is_own() else mask.layer
    # A layer's mask is in its paint's pixels, so a stroke on it goes through
    # the live map the paint is drawn through, as a stroke on the paint does.
    var live: SaLiveTransform = SaLocalView.map_of(owner) if is_instance_valid(owner) else null
    if live != null and not live.takes_paint(owner):
        live = null
    var context := SaPaintContext.new(owner, mask, live, folds)
    context.document = doc
    context.draw_direct = true
    context.paints_coverage = true
    if not mask.is_own() and not is_instance_valid(owner):
        return context
    context.chunk_size = SaChunk.SIZE if owner == null else owner.CHUNK_SIZE
    SaInfiniteCanvas.reach(doc, regions)
    for region in regions:
        context._build_landings(region.grow(padding), owner)
    return context


## Points this context at *region* for the next dab, the way [method for_region]
## would build one for it, keeping the dirty rectangles every dab before it
## left, which is what [method absorb] would have folded in.
##
## For a walk's plain dabs, which share one context: nothing between two dabs
## of one input event can change the document, the layer, the selection or the
## mode the context was built for, and its targets are read before the next dab
## aims it. A dab whose targets are kept past it, the smudge's queue, needs a
## context of its own. A target this context already built at a chunk is aimed
## again rather than built, so the chunk, its selection mask and its scale are
## looked up once a walk. The transaction is still told of every dab, and a
## stroke painting straight in still snapshots under each.
##
## Each region goes through [method _build_landings], as the factory's do, so
## an aimed dab lands across the seam and through a live transform as the
## walk's first dab does, rather than straight onto the chunks, where it would
## paint the layer's own pixels under the pointer and the map would show them a
## second time beside the stroke.
func aim(region: Rect2, padding: float = 2.0) -> void:
    targets.clear()
    _reaching = true
    if document == null or (_layer == null and _mask == null and not paints_coverage):
        return
    if _mask != null and not _mask.is_own() and not is_instance_valid(_layer):
        return
    var regions: Array[Rect2] = [region]
    if document.symmetry.is_active():
        regions = SaInfiniteCanvas.mirrored(document, region)
    _moved_under(SaInfiniteCanvas.reach(document, regions))
    for each in regions:
        _build_landings(each.grow(padding), _layer, padding)


## Follows a grow of the infinite canvas on the left or at the top, *by* whole
## chunks: the dirty rectangles kept from the dabs before it go to the chunks'
## new grid keys, and no target built before it is aimed again.
func _moved_under(by: Vector2i) -> void:
    if by == Vector2i.ZERO:
        return
    var held := _invalidated.duplicate()
    _invalidated.clear()
    for grid_pos: Vector2i in held:
        _invalidated[grid_pos + by] = held[grid_pos]
    _reached.clear()


## How many compute lists a batch opens: one, plus one for every image that
## revisits a chunk an earlier image already wrote.
func passes() -> int:
    var last := -1
    for target in targets:
        last = maxi(last, target.pass_index)
    return last + 1


## Builds *region*'s targets and, on a document whose kind wraps, those of each
## copy of it the wrap brings onto the canvas, every copy's targets told how
## it got there. A copy that touches a chunk an earlier landing did goes in a
## later pass, the way a mirrored image does. The wrap is the canvas's, so
## each landing is found in document pixels and only then taken through a
## live transform into the layer's own, grown by *padding* again there.
func _build_landings(region: Rect2, target_layer: SaLayer, padding: float = 0.0) -> void:
    for map in _landings(document, region, _folds):
        var first := targets.size()
        # A move is added rather than mapped, so the wrap's copies keep the
        # region's size to the bit, which a product through the map need not.
        var landing := Rect2(region.position + map.origin, region.size) if map.determinant() > 0.0 else map * region
        _build_targets(landing if _live == null else _live.layer_area(landing).grow(padding), target_layer)
        for index in range(first, targets.size()):
            targets[index].landing = map
            targets[index].wrap_offset = map.origin


## The map of each landing of *region* on *doc*, in document pixels: the
## region where it is first and always, then a whole canvas width either way
## for each copy the wrap of a kind that wraps brings onto the canvas, and when
## *folds*, the same for its image over each pole it reaches past.
static func _landings(doc: SaDocument, region: Rect2, folds: bool = false) -> Array[Transform2D]:
    var size := Vector2(doc.canvas_size)
    var wrapping := doc.projection.wrapping
    # The stroke's frame onto the page, which a grow of an infinite canvas on the
    # left or at the top moved under it. Nought on any other document.
    var shift := Vector2(doc.infinite_canvas.shift) if doc.infinite_canvas != null else Vector2.ZERO
    var images: Array[Transform2D] = [Transform2D(0.0, shift)]
    if folds:
        images.append_array(doc.projection.pole_folds(region, size))
    var out: Array[Transform2D] = []
    for image in images:
        var seen := image * region
        var across := _turns(seen.position.x, seen.end.x, size.x) if wrapping != SaProjection.Wrap.NONE else PackedInt32Array([0])
        var down := _turns(seen.position.y, seen.end.y, size.y) if wrapping == SaProjection.Wrap.XY else PackedInt32Array([0])
        for turn_y in down:
            for turn_x in across:
                out.append(image.translated(Vector2(turn_x * size.x, turn_y * size.y)))
    return out


## The whole turns of a wrap *span* long that bring the stretch from *from* to
## *to* onto the canvas, nought first and always, so the region itself is built
## whether it reaches the canvas or not, as a flat document builds it.
static func _turns(from: float, to: float, span: float) -> PackedInt32Array:
    var out := PackedInt32Array([0])
    if span <= 0.0:
        return out
    for turn in range(floori(-to / span), ceili((span - from) / span) + 1):
        if turn != 0 and from + turn * span < span and to + turn * span > 0.0:
            out.append(turn)
    return out


func _build_targets(region: Rect2, target_layer: SaLayer) -> void:
    var size_f := float(chunk_size)
    # The pass this region's targets go in: after every pass that already
    # touched one of its chunks, so two images never write one texture in one
    # list. Disjoint images share the list they started in.
    var start_x := floori(region.position.x / size_f)
    var start_y := floori(region.position.y / size_f)
    var end_x := floori(region.end.x / size_f)
    var end_y := floori(region.end.y / size_f)
    var pass_index := 0
    if not targets.is_empty():
        var touched: Dictionary[Vector2i, bool] = {}
        for existing in targets:
            touched[existing.grid_pos] = true
            pass_index = maxi(pass_index, existing.pass_index)
        var first_pass := 0
        for cy in range(start_y, end_y + 1):
            for cx in range(start_x, end_x + 1):
                if touched.has(Vector2i(cx, cy)):
                    first_pass = pass_index + 1
        pass_index = first_pass

    var active_layer := document.active_layer
    var selection: SaSelection = document.selection
    var transaction := document.stroke_transaction
    # The selection the stroke was pressed under, which clips it to its last
    # dab whatever the selection has become since, and null outside a stroke.
    var pressed: SaSelectionHeld = transaction.selection if transaction != null else null
    # A null layer and no mask is the selection itself, while the quick mask
    # is on. A mask target keeps its own branch below, because it is part of
    # the picture and the selection is not.
    var into_mask := target_layer == null and _mask == null
    # Paint is kept only where a chunk reaches the canvas. One the edge crosses
    # stays a target and holds its overhang, as a crop leaves it, while one
    # wholly past the edge is never allocated, because nothing composites it
    # and a chunk where nothing shows is one that need not be stored.
    # Through a live transform it is where the map shows the chunk that counts.
    var canvas := Rect2(Vector2.ZERO, Vector2(document.canvas_size))
    var centre := region.get_center()

    for cy in range(start_y, end_y + 1):
        for cx in range(start_x, end_x + 1):
            var grid_pos := Vector2i(cx, cy)
            var origin := Vector2(cx * chunk_size, cy * chunk_size)
            var square := Rect2(origin, Vector2(size_f, size_f))
            var overlap := region.intersection(square)
            if overlap.size.x <= 0.0 or overlap.size.y <= 0.0:
                continue
            # A target an aimed context built here before, on the layer's own
            # chunk, which a dab of this aim has not taken already: a symmetric
            # image back on its chunk is a target of its own. A grow of an
            # infinite canvas under the walk lets every one go, `_moved_under`.
            var reached: Target = null
            if _reaching and target_layer != null and _mask == null:
                reached = _reached.get(grid_pos)
                if reached != null and (reached.chunk != target_layer.chunks.get(grid_pos) or targets.has(reached)):
                    reached = null
            var lands: bool = canvas.intersects(square) if _live == null else _live.lands(document, grid_pos)
            if reached == null and not lands:
                continue
            # A chunk the selection leaves out is not a target at all: nothing
            # is dispatched, snapshotted or invalidated for it, and no chunk is
            # allocated where paint could not land. Painting the mask itself is
            # never masked by it.
            var mask: SaTexture = reached.mask if reached != null else null
            if reached == null:
                mask = selection.everything() if into_mask else _mask_at(selection, pressed, grid_pos)
            if mask == null:
                continue

            # Align outwards to whole workgroups so no touched pixel is missed.
            var render_start_x: float = floor(overlap.position.x / WORKGROUP) * WORKGROUP
            var render_start_y: float = floor(overlap.position.y / WORKGROUP) * WORKGROUP
            var render_end_x: float = ceil(overlap.end.x / WORKGROUP) * WORKGROUP
            var render_end_y: float = ceil(overlap.end.y / WORKGROUP) * WORKGROUP

            var width: float = render_end_x - render_start_x
            var height: float = render_end_y - render_start_y
            if width <= 0.0 or height <= 0.0:
                continue

            var dab_region := Rect2i(
                Vector2i(int(render_start_x - origin.x), int(render_start_y - origin.y)), Vector2i(int(width), int(height))
            )
            var scale := 1.0
            if reached != null:
                scale = reached.resolution_scale
            elif not into_mask:
                scale = _scale_at(target_layer, grid_pos)
            var texel_region := Rect2i(Vector2i(Vector2(dab_region.position) * scale), Vector2i(Vector2(dab_region.size) * scale))
            # The transaction is told where every dab lands, whichever layer it
            # lands on, so the snapshot can cover the union rather than the tile.
            # In texels, because that is what the snapshot copies. A dab into
            # the mask is nobody's history.
            if transaction != null and not into_mask:
                transaction.note_region(grid_pos, texel_region)
            # An eraser straight in makes no empty chunk where the layer has
            # none, so the next eraser over it still meets nothing and
            # `SaStrokeNote` can say so. The region is noted all the same, for
            # that note.
            if keeps_to_paint and _mask == null and not into_mask and not target_layer.chunks.has(grid_pos):
                continue
            # A mask target is snapshotted like a direct stroke, from its own
            # store, and before the chunk it may be about to allocate.
            if _mask != null and transaction != null:
                transaction.capture_mask_before(_mask, grid_pos)
            # Painting straight into the layer means the snapshot has to be taken
            # now, before this dab, and widened under itself as the stroke moves.
            # A buffered stroke leaves the layer alone until commit and is captured
            # there, in one piece.
            if draw_direct and active_layer != null and not into_mask and _mask == null:
                document.capture_direct_stroke_chunk(active_layer, grid_pos)

            var target := reached
            if target == null:
                target = Target.new()
                target.grid_pos = grid_pos
                target.layer = target_layer
                if into_mask:
                    target.chunk = selection.get_or_create_chunk(grid_pos)
                    target.texture = target.chunk.field(SaSelection.FIELD)
                elif _mask != null:
                    target.texture = _mask.get_or_create(grid_pos)
                    target.chunk = _mask.chunks.get(grid_pos) if _mask.is_own() else target_layer.chunks.get(grid_pos)
                else:
                    target.chunk = target_layer.get_or_create_chunk(grid_pos)
                    target.texture = target.chunk.field(SaPaintedField.of(target_layer))
                target.mask = mask
                target.resolution_scale = scale
                if _reaching and target_layer != null and _mask == null:
                    _reached[grid_pos] = target
            target.render_offset = Vector2(texel_region.position)
            target.local_center = Vector2(centre.x - origin.x, centre.y - origin.y)
            target.pass_index = pass_index
            # Exact at 1.0 and 2.0: render_start is floored and render_end
            # ceiled to WORKGROUP above, so both spans are whole multiples of
            # it, and so are twice them. A scale below one rounds up.
            target.groups_x = maxi(1, ceili(float(texel_region.size.x) / WORKGROUP))
            target.groups_y = maxi(1, ceili(float(texel_region.size.y) / WORKGROUP))
            targets.append(target)
            # Exactly the box the dispatch covers, so the compositor redraws what
            # was painted rather than the chunk around it.
            # Two images in one chunk redraw the union of their two boxes.
            if _invalidated.has(grid_pos):
                _invalidated[grid_pos] = (_invalidated[grid_pos] as Rect2i).merge(dab_region)
            else:
                _invalidated[grid_pos] = dab_region


## The selection's mask for the chunk at *grid_pos*, read off *pressed*, the
## selection a stroke was pressed under, while one is open, and off the live
## *selection* otherwise, by the rule of `SaSelection.texture_for`: the
## everything stand-in when none was active, the chunk's own mask, or null for
## a chunk it leaves out.
static func _mask_at(selection: SaSelection, pressed: SaSelectionHeld, grid_pos: Vector2i) -> SaTexture:
    if pressed == null:
        return selection.texture_for(grid_pos)
    if not pressed.active:
        return selection.everything()
    var chunk: SaChunk = pressed.chunks.get(grid_pos, null)
    return chunk.field(SaSelection.FIELD) if chunk != null else null


## Texels along one document pixel of the chunk at *grid_pos*: the chunk's own
## scale when it exists, and the scale a new one is made at when it does not,
## the layer's, since `SaLayer.get_or_create_chunk` makes it at that. An own
## mask keeps its chunks at the document's resolution.
func _scale_at(target_layer: SaLayer, grid_pos: Vector2i) -> float:
    var own := _mask != null and _mask.is_own()
    var chunk: SaChunk = null
    if own:
        chunk = _mask.chunks.get(grid_pos, null)
    elif target_layer != null:
        chunk = target_layer.chunks.get(grid_pos, null)
    # Floored at 1.0 as the dab kernel floors it, so a half resolution chunk
    # is addressed in the document pixels a full resolution one is.
    if chunk != null:
        return maxf(chunk.resolution_scale, 1.0)
    return 1.0 if own or target_layer == null else maxf(target_layer.resolution_scale, 1.0)


func is_empty() -> bool:
    return targets.is_empty()


## Dab centre in chunk-local pixels for `target`, given a document-space point,
## taken through the target's `landing` first, so a copy across the seam or
## over a pole stamps where the copy lands, and then taken back through the
## live transform when the context paints through one. The centre stored on a
## Target is the region's centre. A stamp usually wants its own position
## instead.
func local_point(target: Target, document_point: Vector2) -> Vector2:
    var point := target.landing * document_point
    point = point if _live == null else _live.unmap_point(point)
    return point - Vector2(target.grid_pos * chunk_size)


## *data*, a dab's push constant packed in the document's frame, in the frame
## of the pixels this context paints: as it is, or with its size, turn and
## mirror taken back through the live transform, `SaLiveTransform.dab`. An
## engine hands every target's block through here once it is whole, with the
## *target* it is for, so a copy folded over a pole is drawn as the mirror of
## the dab: the turn the other way and the frame's y flipped, which is the
## kernel's frame read through a map that turns the plane over.
func dab(data: PackedFloat32Array, target: Target = null) -> PackedFloat32Array:
    var drawn := data
    if target != null and target.landing.determinant() < 0.0:
        drawn = data.duplicate()
        drawn[TURN_SINE] = -drawn[TURN_SINE]
        drawn[SaDabGeometry.MIRROR_INDEX] = float(int(drawn[SaDabGeometry.MIRROR_INDEX]) ^ FLIP_Y)
    return drawn if _live == null else _live.dab(drawn)


## Marks every touched chunk dirty so the compositor redraws exactly those, and
## marks the layer's derived fields stale for the same chunks.
## Call once after dispatching, not per chunk. Through a live transform the
## chunks are the layer's, so the map is told what changed and the regions it
## shows them at are marked in their place.
func commit_invalidation() -> void:
    if _invalidated.is_empty():
        return
    if _layer != null and _layer.has_derived:
        for grid_pos in _invalidated:
            _layer.mark_unresolved(grid_pos)
    if document != null and _layer == null and _mask == null:
        # The mask moved, not the picture: the overlay redraws and nothing
        # composites.
        document.selection.changed.emit()
        return
    if document != null:
        # The rectangles name the layer the paint moved at: the mask's holder,
        # or the active layer that the stroke layer paints for.
        var at := _layer if _layer != document.stroke_layer else document.active_layer
        var shown: Dictionary[Vector2i, Rect2i] = _invalidated
        if _live != null:
            shown = _live.painted(document, _invalidated, not draw_direct)
        document.invalidate_chunk_regions(shown, _mask.holder_in(document) if _mask != null else at)


## Takes *later*'s dirty rectangles into this context's, so the dabs of one
## input event commit once rather than once each, and answers whether it could.
##
## Only a context over the same document, layer, mask and live transform can
## take another's, because [method commit_invalidation] reads those four to
## decide what the rectangles dirty. The caller commits what it held and keeps *later* when
## this answers false. A dab's commit walks the neighbourhood halo and the
## whole-layer spread and emits two signals when a chunk is new, and a 2 px
## tip paints thirty dabs an event where a 128 px one paints two.
func absorb(later: SaPaintContext) -> bool:
    if later.document != document or later._layer != _layer or later._mask != _mask or later._live != _live:
        return false
    for grid_pos: Vector2i in later._invalidated:
        var region: Rect2i = later._invalidated[grid_pos]
        _invalidated[grid_pos] = (_invalidated[grid_pos] as Rect2i).merge(region) if _invalidated.has(grid_pos) else region
    return true


## Runs `dispatcher` for each target inside one compute list.
##
## A dab straddles one to four chunks, each its own texture, so the dispatches
## carry no hazard between them. `compute_list_end()` inserts a full barrier, so
## one list pays one, where a list per chunk would pay one per chunk for work
## that needs one at the end.
##
## *dispatcher* binds one target and nothing else. The group counts, the format
## and the selection mask are read here, so a tool cannot get a batch half right.
func dispatch_batch(compute: SaCompute, kernel_name: String, dispatcher: Callable) -> void:
    if targets.is_empty():
        return

    # Settled before the list opens. Switching storage format reloads the kernels,
    # and the list is about to be bound to one of them. The targets of one dab are
    # chunks of one layer, so they share a depth by construction, and a kernel
    # dispatched at a format it was not built for is undefined across the whole
    # image rather than merely wrong.
    var format: int = targets[0].texture.format
    compute.use_storage_format(format)

    var kernel := compute.index_of_kernel(kernel_name)
    var current_pass := 0
    compute.list_begin(kernel)
    for target in targets:
        if target.texture.format != format:
            push_warning(
                (
                    "SaPaintContext: a target chunk is format %d inside a batch at %d, so it was skipped."
                    % [target.texture.format, format]
                )
            )
            continue
        if target.pass_index != current_pass:
            # A barrier, because this image writes a chunk an earlier one did.
            compute.list_end()
            compute.list_begin(kernel)
            current_pass = target.pass_index
        compute.set_texture(SaSelection.BINDING, target.mask.rid)
        dispatcher.call(target)
        compute.list_dispatch(target.groups_x, target.groups_y, 1)
    compute.list_end()
    dab_dispatched(targets.size())


## Tells the stroke ledger a dab's compute list has closed over *target_count*
## chunks, for a tool that dispatched the dab itself rather than through
## [method dispatch_batch], the way a walk sends the dabs it held.
static func dab_dispatched(target_count: int) -> void:
    SaStrokeLedger.dab_dispatched(target_count)
