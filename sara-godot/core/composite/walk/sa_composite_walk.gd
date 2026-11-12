## The compositor's walk: the stack below the active layer, the active tier,
## and the stack above it, drawn into a canvas a chunk at a time, each layer's
## chunk through its filters and its mask before its blend, and a clipping
## base with what is clipped to it as one group through the compositor's
## `clip_group`.
##
## A class of its own beside `SaCompositor`, with the state only the walk reads: the scratches
## the active tier chains through, the stroke run that batches the plain one,
## the halo the active layer's filters read the live stroke from, and the
## groups a display chunk's walk composites afresh at 2.0. The compositor keeps
## what a single chunk takes, the blend modes, the dispatches and the clears, a
## layer's filters and mask, and the entry point that grows the dirty
## regions before the walk. It is handed to every call here rather than held,
## the way `SaBackdropLayer`'s sweep is, so the two never hold each other. The
## three list operations and the one step a group composited afresh takes per
## member arrive as the compositor's callables, which hold no reference to it.
class_name SaCompositeWalk
extends RefCounted

## The active tier's scratches, a slot per touched chunk of a run.
var _pools := SaScratchPools.new()
## The scratches of a display chunk's walk, twice a chunk across, kept apart
## from the output's so neither walk reallocates the other's every frame.
var _fine_pools := SaScratchPools.new(SaDetailView.DENSITY)
## The active layer and its live stroke composited together, over the ring of
## the dirty set a neighbourhood pass of that layer's own reads a neighbour
## from, which is what `_render_active_layer` hands the chain as the neighbours.
## A layer holds no stroke until it commits, so the chunk beside the one being
## painted holds the layer alone, and the halo is filled through
## `composite_chunk` itself so the pair it holds cannot drift from the pair the
## stroke's own scratch is built from.
var _stroke_halo := SaFilterHalo.new()
## The live stroke over a plain active layer, a list a stage over each run of
## chunks under it, through the walk's pools and the compositor's three batches.
var _stroke_run: SaStrokeRun = null
## An isolated group holding a layer at 2.0 in a display chunk's walk, composited
## afresh at 2.0 and filtered there over a halo at 2.0.
var _dense: SaFineGroup = null
## The compositor's filter chain and the target its walk writes, the output or
## a display chunk.
var _chain: SaFilterChain = null
var _detail: SaDetailView.Target = null


## *chain* and *detail* are the compositor's own. *clear*, *pairs* and *batch*
## are its `clear_scratch_batch`, `composite_chunk_pairs` and
## `composite_chunk_batch`, and *step* the call that composites one stack
## entry's chunk through [method composite_entry_chunk].
func _init(
    chain: SaFilterChain, detail: SaDetailView.Target, clear: Callable, pairs: Callable, batch: Callable, step: Callable
) -> void:
    _chain = chain
    _detail = detail
    _stroke_run = SaStrokeRun.new(clear, pairs, batch, _pools)
    _dense = SaFineGroup.new(_fine_pools.group_slot, chain, detail, clear, step)


## Steps 1 to 3 of [method SaCompositor.composite_chunks] into *canvas*,
## cleared over *dirty_chunks* already: below the active layer, the active
## tier, above it, each step through *compositor*'s own calls.
func walk(
    compositor: SaCompositor,
    canvas: SaTexture,
    document: SaDocument,
    dirty_chunks: Dictionary[Vector2i, Rect2i],
    visible_rect: Rect2
) -> void:
    var chunk_size := float(SaLayer.CHUNK_SIZE)
    var space := document.color_space
    var blend_white := document.blend_reference_white
    if _detail.active():
        _dense.begin(dirty_chunks)
    # 1. Everything below the active layer, in order, folded or one by one.
    for stack_entry: Dictionary in document.fold.bottom_stack:
        _render_entry(compositor, canvas, document, stack_entry, visible_rect, dirty_chunks)

    # 2. The active tier: the active layer and the live stroke, inside whatever
    # isolated groups hold them. A chunk with no stroke, no clip and no scope
    # joins one batch. Everything else is a chain through a scratch, a stage at
    # a time over a run when the tier is plain and a chunk at a time otherwise.
    var act_layer := document.active_layer
    var act_visible: bool = act_layer != null and SaLayerStack.shows(document, act_layer)
    var stroke_has_chunks := (
        document.stroke_layer != null and document.stroke_layer.visible and not document.stroke_layer.chunks.is_empty()
    )
    if act_visible or stroke_has_chunks:
        var all_chunks: Dictionary[Vector2i, bool] = {}
        for layer in SaLayerStack.active_tier_layers(document):
            if layer == act_layer and not act_visible:
                continue
            if layer == document.stroke_layer and not stroke_has_chunks:
                continue
            # A layer drawn through a live transform shows where its cache holds paint.
            for grid_pos in SaLiveTransform.paint_of(layer).chunks:
                all_chunks[grid_pos] = true
        # A blur on the active layer carries its paint into the positions
        # beside the ones it holds, so they are walked too, and so does a
        # wrap previewed on it into where its paint lands.
        if act_visible:
            all_chunks = _chain.walked(act_layer, all_chunks)
            if compositor.point_preview.for_document(document) != null:
                all_chunks.merge(compositor.point_preview.reached(document))
        # So does a blur on a group the active layer is a member of.
        all_chunks = SaScopeReach.walked(_chain, document, all_chunks)
        # A clip group whose base stores nothing, a paper, is drawn wherever
        # the paper is, which is every dirty region.
        for scope: Dictionary in document.fold.active_scopes:
            if SaLayerStack.is_clip_scope(scope) and SaLayerStack.group_of(scope).is_generated():
                for grid_pos: Vector2i in dirty_chunks:
                    all_chunks[grid_pos] = true

        # And the live stroke is in none of the chunks a filter of the active
        # layer reads beside the one it draws from until it commits, so the two
        # are composited over the ring of the dirty set first and the pass reads
        # them from there. Nothing is swept and nothing is held when no stroke
        # is up, which is a blurred layer at rest paying nothing.
        _stroke_halo.fill(SaFilterChain.stroke_sweep(document, dirty_chunks), act_layer, document, compositor.composite_chunk)

        var laid := _active_laid(document)
        var act_mode: StringName = laid[0]
        var act_opacity: float = laid[1]
        var active_clip: SaLayer = SaLayerStack.clip_base(document, act_layer)
        if active_clip != null and not active_clip.visible:
            # A hidden base hides the layer clipped to it, stroke and all.
            all_chunks.clear()
        # A previewed chunk goes through one scratch, so it is a chain and
        # cannot join the batch.
        var previewed := compositor.point_preview.for_document(document)
        # A masked layer is a chain through the mask scratch as well.
        var act_masked := act_layer != null and act_layer.mask != null and act_layer.mask.enabled
        # And a filtered one through the chain's.
        var act_chained := act_masked or (act_layer != null and SaFilterChain.has_enabled(act_layer.filters))
        var simple := document.fold.active_scopes.is_empty() and active_clip == null and previewed == null and not act_chained
        # What the stroke's scratch is built over, nothing when the layer hides.
        var shown_layer: SaLayer = act_layer if act_visible else null

        # A picked layer that stores nothing, the paper or the background, has no
        # chunks for `all_chunks` to gather and answers no field below, so the
        # walk that follows drew it nowhere and picking it took it out of the
        # document. It is drawn over every dirty region first, the way
        # `_render_tier` draws one that is not picked, and the stroke and
        # everything above then land on it as they would on any layer.
        # A picked adjustment layer holds none either, and adjusts every dirty
        # region the same way.
        var stores_nothing := act_visible and (act_layer.is_generated() or act_layer.is_adjustment())
        # One clipped to a layer that has no pixels of its own shows nothing.
        if stores_nothing and document.fold.active_scopes.is_empty() and active_clip == null:
            _render_tier(compositor, canvas, document, act_layer, act_opacity, act_mode, visible_rect, dirty_chunks)

        # Every touched chunk that needs the scratch chain gets its own pool
        # slot, gathered here rather than cleared one at a time inside
        # `_render_scope`, so their clears share one compute list. The scope
        # depth this pass actually reaches is the same for every chunk, since
        # `SaLayerStack.shows` reads layer and group state rather than
        # a chunk, so it is read once rather than once per touched chunk.
        var scope_count := document.fold.active_scopes.size()
        var active_depth := 0
        while (
            active_depth < scope_count
            and SaLayerStack.shows(document, SaLayerStack.group_of(document.fold.active_scopes[active_depth]))
        ):
            active_depth += 1

        # A scope whose filters read their neighbours is composited around the
        # dirty chunks first, so the chain holds the group's composite beside
        # every chunk it filters. Into the pool's second slot, which the sweep
        # leaves unread and the pass proper clears first.
        for sweep: Dictionary[Vector2i, Rect2i] in _chain.scope_sweeps(document, all_chunks, dirty_chunks):
            for grid_pos: Vector2i in sweep:
                var swept := _stroke_slot(document, 0, canvas.format)
                var swept_held := SaStrokeRun.held(shown_layer, sweep[grid_pos], SaDocument.WHOLE_CHUNK.size)
                var clears: Array = [[swept, SaStrokeRun.finer(swept_held, SaStrokeRun.across(swept, _detail.active()))]]
                _scope_clears(clears, document, active_depth, 0, sweep[grid_pos], canvas.format)
                compositor.clear_scratch_batch(clears)
                var sink := _stroke_slot(document, 1, canvas.format)
                _render_scope(compositor, sink, Vector2.ZERO, 0, document, grid_pos, sweep[grid_pos], space, blend_white, 0)

        _stroke_run.begin(canvas, document, shown_layer, act_mode, act_opacity)
        var plain_entries: Array = []
        var scoped_positions: Array = []
        var clear_entries: Array = []
        for grid_pos: Vector2i in all_chunks:
            if not dirty_chunks.has(grid_pos):
                continue
            var offset_x: float = float(grid_pos.x) * chunk_size
            var offset_y: float = float(grid_pos.y) * chunk_size
            var chunk_rect := Rect2(offset_x, offset_y, chunk_size, chunk_size)
            if not visible_rect.intersects(chunk_rect):
                continue
            var region: Rect2i = dirty_chunks[grid_pos]
            var stroke_chunk: SaTexture = document.stroke_layer.get_field(grid_pos) if stroke_has_chunks else null
            if simple and stroke_chunk == null:
                var chunk_to_draw: SaTexture = SaLiveTransform.paint_of(act_layer).get_field(grid_pos) if act_visible else null
                if chunk_to_draw != null:
                    plain_entries.append([chunk_to_draw, Vector2(offset_x, offset_y), region])
                continue
            if simple:
                _stroke_run.add(grid_pos, Vector2(offset_x, offset_y), region, stroke_chunk)
                continue
            var slot := scoped_positions.size()
            _scope_clears(clear_entries, document, active_depth, slot, region, canvas.format)
            # Mirrors `_render_active_layer`'s own gate for reaching the
            # stroke branch: past every scope, a stroke chunk here, and not
            # clipped to a layer that has no pixels of its own.
            if active_depth == scope_count and stroke_chunk != null and not _clipped_away(active_clip):
                var stroke_scratch := _stroke_slot(document, slot, canvas.format)
                var stroke_held := SaStrokeRun.held(shown_layer, region, SaDocument.WHOLE_CHUNK.size)
                var stroke_across := SaStrokeRun.across(stroke_scratch, _detail.active())
                clear_entries.append([stroke_scratch, SaStrokeRun.finer(stroke_held, stroke_across)])
            scoped_positions.append([grid_pos, Vector2(offset_x, offset_y), region])
            if scoped_positions.size() == SaCompositor.SCRATCH_RUN:
                _render_scratch_run(compositor, canvas, document, scoped_positions, clear_entries, space, blend_white)
                scoped_positions.clear()
                clear_entries.clear()

        _render_scratch_run(compositor, canvas, document, scoped_positions, clear_entries, space, blend_white)
        _stroke_run.flush()
        _pools.keep_levels(active_depth)
        _fine_pools.keep_levels(active_depth)

        compositor.composite_chunk_batch(canvas, plain_entries, act_mode, act_opacity, space, blend_white)

    # 3. Everything above the active layer, in order, each against the canvas
    # that already holds everything under it, so a Multiply above a painting
    # multiplies the painting.
    for stack_entry: Dictionary in document.fold.top_stack:
        _render_entry(compositor, canvas, document, stack_entry, visible_rect, dirty_chunks)


## One stack entry's chunk into *target* at *offset*, masked when the entry
## says so. What a scope does per step, where the top level batches, and what
## a group composited afresh does per member, *depth* groups in.
func composite_entry_chunk(
    compositor: SaCompositor,
    target: SaTexture,
    offset: Vector2,
    stack_entry: Dictionary,
    grid_pos: Vector2i,
    region: Rect2i,
    space: SaColorSpace,
    blend_white: float,
    depth: int = 0
) -> void:
    var layer := SaLayerStack.layer_of(stack_entry)
    var mode := SaLayerStack.mode_of(stack_entry)
    var opacity := SaLayerStack.opacity_of(stack_entry)
    var clipped := SaLayerStack.clipped_of(stack_entry)
    if not clipped.is_empty():
        var lay_base := func(into: SaTexture) -> void:
            composite_entry_chunk(
                compositor, into, Vector2.ZERO, SaLayerStack.base_step(stack_entry), grid_pos, region, space, blend_white, depth
            )
        var lay_clipped := func(plate: SaTexture) -> void:
            for step: Dictionary in clipped:
                composite_entry_chunk(compositor, plate, Vector2.ZERO, step, grid_pos, region, space, blend_white, depth)
        compositor.clip_group.composite(
            compositor, target, offset, region, mode, opacity, space, blend_white, lay_base, lay_clipped
        )
        return
    if layer.is_generated():
        compositor.composite_generated_chunk(target, layer, mode, opacity, grid_pos, offset, region, space, blend_white)
        return
    if layer.is_adjustment():
        compositor.adjustment.adjust(compositor, target, layer, mode, opacity, grid_pos, offset, region)
        return
    # No chunk here is still something to draw when the node's filters carry
    # the paint beside it in, and the chain answers null when they do not.
    var node := SaLayerStack.node_of(stack_entry, layer)
    var field := _dense.field(layer, node, grid_pos, region, target.format, depth)
    var source := compositor.shown(node, layer, field, grid_pos, region, _dense.neighbours(node, layer, field, grid_pos))
    if source == null:
        return
    compositor.composite_chunk(target, source, mode, opacity, offset, space, blend_white, region)


## One run of scratch-chain chunks: every scratch the run will use is cleared
## in one list, then each chunk is rendered through its own slot. The next
## run takes the same slots again, which is safe because its clears are a
## compute list of their own, ordered after the composites that read them.
func _render_scratch_run(
    compositor: SaCompositor,
    canvas: SaTexture,
    document: SaDocument,
    scoped_positions: Array,
    clear_entries: Array,
    space: SaColorSpace,
    blend_white: float
) -> void:
    compositor.clear_scratch_batch(clear_entries)
    for slot in scoped_positions.size():
        var scoped_entry: Array = scoped_positions[slot]
        var offset: Vector2 = scoped_entry[1]
        var grid_pos: Vector2i = scoped_entry[0]
        var region: Rect2i = scoped_entry[2]
        _render_scope(compositor, canvas, offset, 0, document, grid_pos, region, space, blend_white, slot)


func _render_entry(
    compositor: SaCompositor,
    canvas: SaTexture,
    document: SaDocument,
    stack_entry: Dictionary,
    visible_rect: Rect2,
    dirty_chunks: Dictionary[Vector2i, Rect2i]
) -> void:
    if not SaLayerStack.clipped_of(stack_entry).is_empty():
        _render_clip_group(compositor, canvas, document, stack_entry, visible_rect, dirty_chunks)
        return
    _render_tier(
        compositor,
        canvas,
        document,
        SaLayerStack.layer_of(stack_entry),
        SaLayerStack.opacity_of(stack_entry),
        SaLayerStack.mode_of(stack_entry),
        visible_rect,
        dirty_chunks,
        SaLayerStack.node_of(stack_entry)
    )


## A clipping base's step with what is clipped to it, over every dirty chunk
## the base shows on, into *canvas*: where it holds paint, the ring a filter
## of its carries that paint into, or everywhere for a base that stores
## nothing. Beyond the base a clipped layer shows nothing.
func _render_clip_group(
    compositor: SaCompositor,
    canvas: SaTexture,
    document: SaDocument,
    stack_entry: Dictionary,
    visible_rect: Rect2,
    dirty_chunks: Dictionary[Vector2i, Rect2i]
) -> void:
    var base := SaLayerStack.layer_of(stack_entry)
    var positions: Array = dirty_chunks.keys()
    if not base.is_generated():
        positions = _chain.walked(SaLayerStack.node_of(stack_entry, base), SaTyped.positions(base.chunks)).keys()
    var side := float(SaLayer.CHUNK_SIZE)
    for grid_pos: Vector2i in positions:
        var offset := Vector2(grid_pos) * side
        if dirty_chunks.has(grid_pos) and visible_rect.intersects(Rect2(offset, Vector2(side, side))):
            var region: Rect2i = dirty_chunks[grid_pos]
            composite_entry_chunk(
                compositor, canvas, offset, stack_entry, grid_pos, region, document.color_space, document.blend_reference_white
            )


## Renders the active tier for one chunk into *target* at *offset*: scope
## *level* of `document.fold.active_scopes`, or the active layer and the live
## stroke past the last one. A scope composites into a scratch of its own,
## its bottom, the level in, its top, and then the scratch onto its parent
## with the group's mode and opacity, which is the intermediate target an
## isolated group is.
##
## *slot* is this chunk's own position among the pass's touched chunks: the
## caller has already cleared every scratch this chunk will use, across every
## level, in one batched list before calling here, so the scratch this fetches
## at each level is already the transparency `clear.gmacs` left it at rather
## than something this function clears itself. A shared, reused scratch cannot
## be pre-cleared this way, because the next chunk's clear would land on top of
## this one's own paint before it is read, which is why every chunk keeps its
## own slot in the pool instead.
func _render_scope(
    compositor: SaCompositor,
    target: SaTexture,
    offset: Vector2,
    level: int,
    document: SaDocument,
    grid_pos: Vector2i,
    region: Rect2i,
    space: SaColorSpace,
    blend_white: float,
    slot: int
) -> void:
    var scopes := document.fold.active_scopes
    if level >= scopes.size():
        _render_active_layer(compositor, target, offset, document, grid_pos, region, space, blend_white, slot)
        return
    var scope: Dictionary = scopes[level]
    var group: SaLayer = scope[SaLayerStack.GROUP]
    if not SaLayerStack.shows(document, group):
        return
    if SaLayerStack.is_clip_scope(scope):
        _render_clip_scope(compositor, target, offset, level, document, grid_pos, region, space, blend_white, slot)
        return
    var scratch := _scope_slot(document, level, slot, target.format)
    for stack_entry: Dictionary in scope[SaLayerStack.BOTTOM]:
        composite_entry_chunk(compositor, scratch, Vector2.ZERO, stack_entry, grid_pos, region, space, blend_white)
    _render_scope(compositor, scratch, Vector2.ZERO, level + 1, document, grid_pos, region, space, blend_white, slot)
    for stack_entry: Dictionary in scope[SaLayerStack.TOP]:
        composite_entry_chunk(compositor, scratch, Vector2.ZERO, stack_entry, grid_pos, region, space, blend_white)

    # The group's filters over its composite, then its mask. A clipped group
    # is laid on its base's plate by the clip scope around this one.
    var source: SaTexture = compositor.masked(group, _dense.filtered_scope(group, scratch, grid_pos, region), grid_pos, region)
    var opacity := group.opacity * SaLayerStack.passthrough_multiplier(group)
    compositor.composite_chunk(target, source, group.get_blend_mode_name(), opacity, offset, space, blend_white, region)


## Scope *level* when it is a clip group around the active layer, for one
## chunk into *target* at *offset*: the base as it shows, the active layer and
## its live stroke when it is the base, then the plate it makes, with the
## steps clipped to it below the active layer laid on, the next level in, and
## the steps above, and the whole laid by the base's mode and opacity.
func _render_clip_scope(
    compositor: SaCompositor,
    target: SaTexture,
    offset: Vector2,
    level: int,
    document: SaDocument,
    grid_pos: Vector2i,
    region: Rect2i,
    space: SaColorSpace,
    blend_white: float,
    slot: int
) -> void:
    var scope: Dictionary = document.fold.active_scopes[level]
    var base_step: Dictionary = scope[SaLayerStack.BASE]
    var lay_base := func(into: SaTexture) -> void:
        if base_step.is_empty():
            _render_scope(compositor, into, Vector2.ZERO, level + 1, document, grid_pos, region, space, blend_white, slot)
        else:
            composite_entry_chunk(compositor, into, Vector2.ZERO, base_step, grid_pos, region, space, blend_white)
    var lay_clipped := func(plate: SaTexture) -> void:
        for stack_entry: Dictionary in scope[SaLayerStack.BOTTOM]:
            composite_entry_chunk(compositor, plate, Vector2.ZERO, stack_entry, grid_pos, region, space, blend_white)
        if not base_step.is_empty():
            _render_scope(compositor, plate, Vector2.ZERO, level + 1, document, grid_pos, region, space, blend_white, slot)
        for stack_entry: Dictionary in scope[SaLayerStack.TOP]:
            composite_entry_chunk(compositor, plate, Vector2.ZERO, stack_entry, grid_pos, region, space, blend_white)
    var base := SaLayerStack.group_of(scope)
    var opacity := base.opacity * SaLayerStack.passthrough_multiplier(base)
    compositor.clip_group.composite(
        compositor, target, offset, region, base.get_blend_mode_name(), opacity, space, blend_white, lay_base, lay_clipped
    )


## The active layer and the live stroke for one chunk, into *target* at
## *offset*. A chunk with a stroke over it is a real chain: the scratch is
## written, written again, then read. Masked, it goes through the mask scratch
## on the way out. Clipped, it is laid on its base's plate by the clip scope
## around it, and as the base, it is laid Normal and whole into the scope's
## first scratch.
##
## *slot* is this chunk's own position among the pass's touched chunks,
## which the caller's gather loop mirrors this function's own gate for
## reaching the stroke branch to decide whether it cleared a scratch at this
## slot at all: see [method walk].
func _render_active_layer(
    compositor: SaCompositor,
    target: SaTexture,
    offset: Vector2,
    document: SaDocument,
    grid_pos: Vector2i,
    region: Rect2i,
    space: SaColorSpace,
    blend_white: float,
    slot: int
) -> void:
    var act_layer := document.active_layer
    var act_visible: bool = act_layer != null and SaLayerStack.shows(document, act_layer)
    # The cache of a live transform is what shows, its mask already in it.
    var act_paint := SaLiveTransform.paint_of(act_layer)
    var chunk_to_draw: SaTexture = act_paint.get_field(grid_pos) if act_visible else null
    var stroke_chunk: SaTexture = null
    if document.stroke_layer != null and document.stroke_layer.visible:
        stroke_chunk = document.stroke_layer.get_field(grid_pos)
    if chunk_to_draw == null and stroke_chunk == null and not act_visible:
        return
    # Clipped to a layer that has no pixels of its own, it shows nothing.
    if _clipped_away(SaLayerStack.clip_base(document, act_layer)):
        return
    var laid := _active_laid(document)
    var act_mode: StringName = laid[0]
    var act_opacity: float = laid[1]
    # A picked adjustment layer inside a scope adjusts its composite so far, and
    # a picked layer that stores nothing is drawn there over the region.
    if act_visible and act_layer.is_adjustment():
        compositor.adjustment.adjust(compositor, target, act_layer, act_mode, act_opacity, grid_pos, offset, region)
        return
    if act_visible and act_layer.is_generated():
        compositor.composite_generated_chunk(
            target, act_layer, act_mode, act_opacity, grid_pos, offset, region, space, blend_white
        )
        return

    # The previewed pass, before the live stroke joins the layer's pixels. A
    # chunk the selection leaves out shows as it is, the way the pass would
    # leave it.
    chunk_to_draw = compositor.point_preview.drawn(compositor, document, act_layer, chunk_to_draw, grid_pos, region)

    if stroke_chunk != null:
        # At the stroke chunk's own depth and density, so a layer at 2.0 and
        # its filters meet the stroke texel for texel. Already cleared by
        # [method walk]'s batch through `clear.gmacs`, a dispatch rather
        # than `texture_clear` because a transfer is not ordered against compute.
        var scratch := _stroke_slot(document, slot, stroke_chunk.format)
        # The clear and both composites use one rectangle, the one the caller
        # cleared: the dirty region, grown by what the layer's filters read past
        # it. The scratch and the canvas chunk share an origin, so the rectangle
        # addresses both and nothing outside it is ever read.
        var held := SaStrokeRun.held(act_layer if act_visible else null, region, SaDocument.WHOLE_CHUNK.size)
        var stroke_mode := document.stroke_layer.get_blend_mode_name()
        var across := SaStrokeRun.across(scratch, _detail.active())
        var fine := SaStrokeRun.finer(held, across)
        if chunk_to_draw != null:
            var under := SaDocumentTexels.density_of(chunk_to_draw) / across if across > 1.0 else 0.0
            compositor.composite_chunk(
                scratch, chunk_to_draw, SaLayer.BLEND_MODE.NORMAL, 1.0, Vector2.ZERO, space, blend_white, fine, under
            )
        var over := SaDocumentTexels.density_of(stroke_chunk) / across if across > 1.0 else 0.0
        compositor.composite_chunk(
            scratch, stroke_chunk, stroke_mode, document.stroke_opacity, Vector2.ZERO, space, blend_white, fine, over
        )
        chunk_to_draw = scratch

    # The mask hides the layer and the live stroke on it alike, as the stroke
    # will be hidden once it is committed into the layer's chunk, and the
    # layer's filters run over the two for the same reason. Filters, then the
    # mask, then the blend. The neighbours a neighbourhood pass reads are the
    # halo [member _stroke_halo] holds of the same two.
    if act_visible:
        var halo: SaLayer = _stroke_halo.layer if _stroke_halo.layer != null or act_paint == act_layer else act_paint
        chunk_to_draw = compositor.shown(act_layer, act_paint, chunk_to_draw, grid_pos, region, halo)
    # Nothing held here and nothing a filter's halo carried in.
    if chunk_to_draw == null:
        return
    compositor.composite_chunk(target, chunk_to_draw, act_mode, act_opacity, offset, space, blend_white, region)


## The mode and the opacity the active layer is laid by in *document*, as
## `[mode, opacity]`: Normal and whole as the base of the clip group around
## it, its own mode and opacity as a layer clipped to the base, since the
## group carries the base's and the pass-through groups', and its own mode at
## its opacity times the pass-through groups' anywhere else, or every group's
## for a layer `SaBackdropLayer` lifts.
static func _active_laid(document: SaDocument) -> Array:
    var layer := document.active_layer
    if layer == null:
        return [SaLayer.BLEND_MODE.NORMAL, 1.0]
    var scopes := document.fold.active_scopes
    var inner: Dictionary = {} if scopes.is_empty() else scopes.back()
    if SaLayerStack.is_clip_scope(inner):
        var below: Dictionary = inner[SaLayerStack.BASE]
        var is_base := below.is_empty()
        if is_base:
            return [SaLayer.BLEND_MODE.NORMAL, 1.0]
        return [layer.get_blend_mode_name(), layer.opacity * _carried_to(layer, SaLayerStack.group_of(inner))]
    # A lifted layer is drawn at the top level, every group around it carried.
    if SaBackdropLayer.lifts(layer):
        return [layer.get_blend_mode_name(), layer.opacity * SaBackdropLayer.carried(layer)]
    return [layer.get_blend_mode_name(), layer.opacity * SaLayerStack.passthrough_multiplier(layer)]


## The opacities of the pass-through groups between *layer* and the level of
## *base*, its clipping base, which a clipped pass-through group lays on the
## base's plate with its members. One at the base's level.
static func _carried_to(layer: SaLayer, base: SaLayer) -> float:
    var factor := 1.0
    var level := SaLayerStack.parent_of(base)
    var group := SaLayerStack.parent_of(layer)
    var guard := 0
    while group != null and group != level and guard < 64:
        factor *= group.opacity
        group = SaLayerStack.parent_of(group)
        guard += 1
    return factor


## Whether the active layer is clipped to *base* and *base* is a layer with no
## pixels of its own, an adjustment layer, so nothing of it shows.
static func _clipped_away(base: SaLayer) -> bool:
    return base != null and base.is_adjustment()


## One entry of a stack, or a picked layer that stores nothing, over every
## dirty chunk it holds into *canvas*, in *document*'s space. The chunks that
## need no scratch share one batch, and a filtered or masked one is composited
## on its own.
func _render_tier(
    compositor: SaCompositor,
    canvas: SaTexture,
    document: SaDocument,
    current_layer: SaLayer,
    current_opacity: float,
    mode_name: StringName,
    visible_rect: Rect2,
    dirty_chunks: Dictionary[Vector2i, Rect2i],
    node: SaLayer = null
) -> void:
    if current_layer == null or not current_layer.visible:
        return
    var space := document.color_space
    var blend_white := document.blend_reference_white
    # The tree node the tier stands for, whose filters run over it: the layer
    # itself, or the group when the tier is a group's cache.
    var chained := node != null and SaFilterChain.has_enabled(node.filters)
    var chunk_size := float(SaLayer.CHUNK_SIZE)

    # A layer that stores nothing has no chunks to walk: it contributes over
    # every dirty region instead, each through the generated scratch, or an
    # adjustment layer adjusts every one.
    if current_layer.is_generated() or current_layer.is_adjustment():
        for grid_pos: Vector2i in dirty_chunks:
            var offset := Vector2(grid_pos) * chunk_size
            var region: Rect2i = dirty_chunks[grid_pos]
            if not visible_rect.intersects(Rect2(offset, Vector2(chunk_size, chunk_size))):
                continue
            if current_layer.is_adjustment():
                compositor.adjustment.adjust(
                    compositor, canvas, current_layer, mode_name, current_opacity, grid_pos, offset, region
                )
                continue
            compositor.composite_generated_chunk(
                canvas, current_layer, mode_name, current_opacity, grid_pos, offset, region, space, blend_white
            )
        return

    # Collected rather than dispatched one at a time: every chunk of a tier shares
    # the kernel and the destination and writes its own region, so the whole tier
    # is one list and one barrier. A node that gathers a halo is walked over the
    # ring around its chunks as well, where the chain stands a cleared chunk in
    # for the missing one.
    var positions: Array = current_layer.chunks.keys()
    if chained:
        positions = _chain.walked(node, SaTyped.positions(current_layer.chunks)).keys()
    var entries: Array = []
    for grid_pos: Vector2i in positions:
        if not dirty_chunks.has(grid_pos):
            continue
        var offset_x: float = float(grid_pos.x) * chunk_size
        var offset_y: float = float(grid_pos.y) * chunk_size
        var chunk_rect := Rect2(offset_x, offset_y, chunk_size, chunk_size)
        if not visible_rect.intersects(chunk_rect):
            continue

        var region: Rect2i = dirty_chunks[grid_pos]
        var albedo := _dense.field(current_layer, node, grid_pos, region, canvas.format, 0)
        var coverage := SaCompositor.coverage_at(current_layer, grid_pos)
        if coverage != null or chained or albedo != current_layer.get_field(grid_pos):
            # Filtered and masked through scratches, so each such chunk is
            # composited before the next one overwrites them. A ring position
            # out of reach is nothing to draw.
            var neighbours := _dense.neighbours(node, current_layer, albedo, grid_pos)
            var source := compositor.shown(node, current_layer, albedo, grid_pos, region, neighbours)
            if source == null:
                continue
            compositor.composite_chunk(
                canvas, source, mode_name, current_opacity, Vector2(offset_x, offset_y), space, blend_white, region
            )
            continue
        entries.append([albedo, Vector2(offset_x, offset_y), region])

    compositor.composite_chunk_batch(canvas, entries, mode_name, current_opacity, space, blend_white)


## Appends to *clears* the scratch of every scope level under *depth* at *slot*
## over *region*, at *format*. A clip scope clears its own as it draws.
func _scope_clears(clears: Array, document: SaDocument, depth: int, slot: int, region: Rect2i, format: int) -> void:
    for level in range(depth):
        if not SaLayerStack.is_clip_scope(document.fold.active_scopes[level]):
            clears.append([_scope_slot(document, level, slot, format), region])


## The stroke scratch of a chain at *slot*: the output's, as fine as
## *document*'s live stroke for the reason `SaStrokeRun.add` gives, or in a
## display chunk's walk one twice a chunk across that the walk places.
func _stroke_slot(document: SaDocument, slot: int, format: int) -> SaTexture:
    if not _detail.active():
        return _pools.stroke_slot(slot, format, SaFilterDensity.scale_of(document.stroke_layer))
    var scratch := _fine_pools.stroke_slot(slot, format)
    _detail.adopt(scratch)
    return scratch


## The scratch of scope *level* at *slot*, fine in a display chunk's walk as
## [method _stroke_slot] is, but for a group whose filters read the whole node,
## whose gather is at the document's resolution, so its scope is too.
func _scope_slot(document: SaDocument, level: int, slot: int, format: int) -> SaTexture:
    var group: SaLayer = document.fold.active_scopes[level][SaLayerStack.GROUP]
    if not _dense.fine_scope(group):
        return _pools.scope_slot(level, slot, format)
    var scratch := _fine_pools.scope_slot(level, slot, format)
    _detail.adopt(scratch)
    return scratch
