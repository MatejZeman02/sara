## The layer tree drawn into one chunk the way the compositor draws it, and a
## node's filters and mask written into a layer's paint, for the operations
## that turn what is on screen into pixels: a flatten, a merge and an
## ungroup.
##
## The compositor draws from its fold, caches and scopes built around the
## active layer, and it draws into the easel's output, so none of it can be
## asked for one chunk of the whole tree in a texture of the caller's. This
## walks the tree itself, one chunk at a time, through the compositor's own
## calls in the compositor's order: a node's filters, then its mask, then the
## blend, and a clipping base with the layers clipped to it as one group
## through the compositor's `clip_group`. A pass-through group's members take
## their places in the parent's order with its opacity multiplied in, an
## adjustment layer mixes the target it reaches towards its records' result,
## and an isolated group, by the painter's flag or because it carries a mask or
## a filter, is drawn into a scratch of its own first and then through its
## filters, mask, mode and opacity, which is `SaCompositeWalk._render_scope`'s
## shape one level at a time.
##
## It owns one scratch per depth of isolated group it has reached, because an
## isolated group inside another composites into its own while the outer one is
## still being filled. The compositor's scratches, the chain's, the mask's and
## the clip's, are each read by the composite that follows the call that wrote
## them, so the recursion never holds one across another call, and the clip
## group keeps its own per depth of nesting.
class_name SaTreeRender
extends RefCounted

var _document: SaDocument
## Depth to the chunk an isolated group at that depth composites into.
var _scratches: Array[SaTexture] = []
## The node a render up to a node stops at, null for the whole tree.
var _stop: SaLayer = null
## Whether the walk has reached `_stop`, so every level above it ends too.
var _reached: bool = false
## Whether the active layer is drawn with the pass a dialog previews on it.
var _previewed: bool = false
## The members of every group, read once a walk, or null between walks, and
## read once for every walk of a render made with `kept`.
var _siblings: Siblings = null
## The adjustment step of a render the compositor's `detail` places at
## another density, an adjustment layer's thumbnail, with scratches of its
## own. The compositor's step keeps scratches a chunk across for the walk, and
## a thumbnail drawn through them made them again at its own size and the walk
## made them again at a chunk's, every frame, each time freeing a texture,
## which drops every uniform set `SaCompute` has cached.
var _sized_step: SaBackdropLayer = null


## *previewed* draws the active layer with the pass a dialog previews on it, for
## an effect layer reading a group. A flatten or a merge does not. *kept* reads
## every group's members once, here, for every render this makes, which is a
## caller that renders many nodes while the stack holds still: the effect
## layers' refresh, which read the members of a stack of 593 layers again for
## each of 219 effects a chunk on a large night painting.
## Without it each render reads them at its start.
func _init(document: SaDocument, previewed: bool = false, kept: bool = false) -> void:
    _document = document
    _previewed = previewed
    if kept:
        _siblings = Siblings.new(document)


## The group whose composite *node* blends into: its nearest isolated group,
## or null for the top level, where a pass-through group between them has no
## composite of its own. What an adjustment layer reads as its backdrop.
static func scope_of(node: SaLayer) -> SaLayer:
    # A lifted layer reads the whole picture, `SaBackdropLayer`'s rule.
    if SaBackdropLayer.lifts(node):
        return null
    var group := SaLayerStack.parent_of(node)
    var guard := 0
    while group != null and not SaLayerStack.isolates(group) and guard < 64:
        group = SaLayerStack.parent_of(group)
        guard += 1
    return group


## The backdrop *node* reads at *grid_pos*, into *target*, a chunk the caller
## has cleared: what the walk has drawn into its scope when it reaches *node*,
## the members of its isolated group below it, or every layer below it at the
## top level. It is the histogram a Levels record on an adjustment layer
## equalizes from, which the canvas draws over before the frame ends.
func render_below(target: SaTexture, grid_pos: Vector2i, node: SaLayer) -> void:
    if node == null:
        return
    _stop = node
    _reached = false
    render_members(target, scope_of(node), grid_pos)
    _stop = null
    _reached = false


## Every node of the tree composited into *target*, a chunk at *grid_pos* the
## caller has cleared: what the canvas shows there before the document's root
## filters run over it. The stroke buffer is not part of the document and is
## left out, and so is a previewed pass unless this render was made to draw it.
func render(target: SaTexture, grid_pos: Vector2i) -> void:
    render_members(target, null, grid_pos)


## *node* alone composited into *target* at *grid_pos*, over what *target*
## holds already, as the canvas draws it at its place: a pass-through group's
## members one by one with its opacity multiplied in, anything else through
## its filters, mask, mode and opacity. A group merged down lays itself on the
## paint of the layer under it through this, `SaGroupMerge`, and a clip to
## that layer is the caller's, so it is not asked here.
func render_node(target: SaTexture, node: SaLayer, grid_pos: Vector2i) -> void:
    if _document.compositor == null or target == null or not node.visible:
        return
    var held := _siblings
    if held == null:
        _siblings = Siblings.new(_document)
    if node.is_group and not SaLayerStack.isolates(node):
        _render_nodes(target, _siblings.of(node), grid_pos, node.opacity, 0)
    else:
        _render_node(target, node, grid_pos, node.get_blend_mode_name(), node.opacity, 0)
    _siblings = held


## The members of *group* composited into *target*, a cleared chunk at
## *grid_pos*, before the group's own records: what an effect layer reads.
func render_members(target: SaTexture, group: SaLayer, grid_pos: Vector2i) -> void:
    if _document.compositor == null or target == null:
        return
    var outermost := _siblings == null
    if outermost:
        _siblings = Siblings.new(_document)
    _render_nodes(target, _siblings.of(group), grid_pos, 1.0, 0)
    if group == null and not _reached:
        _render_lifted(target, grid_pos)
    if outermost:
        _siblings = null


## Every layer `SaBackdropLayer` lifts out of its place, into *target* at
## *grid_pos* after the top level's last layer, the lowest first, each while
## it and every group around it are visible and at its opacity times theirs.
func _render_lifted(target: SaTexture, grid_pos: Vector2i) -> void:
    for node in SaBackdropLayer.lifted(_document):
        if node == _stop:
            _reached = true
            return
        if SaBackdropLayer.visible_through(node):
            var opacity := node.opacity * SaBackdropLayer.carried(node)
            _render_node(target, node, grid_pos, node.get_blend_mode_name(), opacity, 0)


## A new chunk of *schema* holding the whole tree at *grid_pos*. Every field but
## the albedo takes its blank, and the albedo is cleared by the compositor's
## kernel rather than by `texture_clear`, because the composites that follow
## are compute and a transfer is not ordered against them inside a frame.
func flattened(schema: Array[SaFieldSpec], grid_pos: Vector2i) -> SaChunk:
    var chunk := SaChunk.create(schema)
    for field_id: StringName in chunk.field_ids():
        if field_id != SaFieldSpec.ALBEDO:
            var blank: Color = chunk.blanks.get(field_id, SaFieldSpec.NO_PAINT)
            chunk.field(field_id).clear(blank)
    var albedo := chunk.albedo()
    var compositor := _document.compositor
    if compositor != null:
        compositor.clear_scratch_batch([[albedo, Rect2i(Vector2i.ZERO, albedo.size)]])
    render(albedo, grid_pos)
    return chunk


## Writes what *node* does to what it draws, its enabled filters in order and
## then its mask, into *layer*'s chunks, and puts each chunk it replaced into
## *state* the first time, so one swap undoes it. *node* is the layer itself
## for a merge, and the group around it for an ungroup, where a neighbourhood
## filter reads the chunks around this one from the member, as the flatten of
## a group's record does.
##
## Every chunk goes into a copy and the copies go in at the end, because a
## neighbourhood pass reads the chunks around the one it writes and a chunk
## written a moment ago is not what the layer was drawn from. A position beside
## the layer's chunks that a halo carries paint into gets a chunk of its own,
## which is what the canvas showed there. Each is at the layer's density, as
## `SaLayerGroups.BakeShown` answers it. The copy out of a scratch is GPU to GPU (hard rule 1).
func bake(node: SaLayer, layer: SaLayer, state: Dictionary[Vector2i, Variant]) -> void:
    var compositor := _document.compositor
    var rd := GlobalShaderCompiler.get_rd()
    if compositor == null or rd == null:
        return
    var written: Dictionary[Vector2i, SaChunk] = {}
    var shows := SaLayerGroups.BakeShown.new(compositor)
    for grid_pos: Vector2i in _inside(compositor.filter_chain.walked(node, SaTyped.positions(layer.chunks))):
        var albedo := layer.get_field(grid_pos)
        var shown := shows.of(node, layer, albedo, grid_pos)
        if shown == null or shown == albedo:
            continue
        var copy: SaChunk = layer.duplicate_chunk(grid_pos) if albedo != null else _blank(layer)
        var extent := Vector3(shown.size.x, shown.size.y, 1)
        rd.texture_copy(shown.rid, copy.albedo().rid, Vector3.ZERO, Vector3.ZERO, extent, 0, 0, 0, 0)
        written[grid_pos] = copy
    for grid_pos: Vector2i in written:
        if not state.has(grid_pos):
            state[grid_pos] = layer.chunks.get(grid_pos, null)
        layer.set_chunk(grid_pos, written[grid_pos])


## Where a node that holds *positions* can show something, its halo's ring
## included, as a set cut to the document's grid.
func reach(node: SaLayer, positions: Dictionary[Vector2i, bool]) -> Dictionary[Vector2i, bool]:
    var compositor := _document.compositor
    return _inside(compositor.filter_chain.walked(node, positions) if compositor != null else positions)


## *positions* without the ones off the document's grid, where a ring around an
## edge chunk reaches and nothing is drawn.
func _inside(positions: Dictionary[Vector2i, bool]) -> Dictionary[Vector2i, bool]:
    var side := float(SaLayer.CHUNK_SIZE)
    var canvas := _document.canvas_size
    var limit := Rect2i(0, 0, ceili(canvas.x / side), ceili(canvas.y / side))
    var kept: Dictionary[Vector2i, bool] = {}
    for grid_pos: Vector2i in positions:
        if limit.has_point(grid_pos):
            kept[grid_pos] = true
    return kept


## A chunk of *layer* with every field at its blank, for a position a halo
## writes into where the layer held nothing.
static func _blank(layer: SaLayer) -> SaChunk:
    var chunk := SaChunk.create(layer.schema, SaFilterDensity.scale_of(layer))
    chunk.clear(SaFieldSpec.NO_PAINT)
    return chunk


## *nodes*, siblings bottom first, into *target* at *grid_pos*, each at its
## opacity times *factor*, the pass-through groups above them having no
## composite of their own to multiply into.
func _render_nodes(target: SaTexture, nodes: Array[SaLayer], grid_pos: Vector2i, factor: float, depth: int) -> void:
    for node in nodes:
        # A lifted layer is drawn after the top level's last layer instead.
        if SaBackdropLayer.lifts(node):
            continue
        if _stops_at(node):
            _reached = true
            return
        # A clipped layer is drawn with its base, and one clipped to a layer
        # with no pixels of its own shows nothing.
        if not node.visible or _siblings.clip_base(node) != null:
            continue
        var opacity := node.opacity * factor
        if node.is_group and not SaLayerStack.isolates(node):
            _render_nodes(target, _siblings.of(node), grid_pos, opacity, depth)
        else:
            var run := _siblings.clipped_run(node)
            _render_node(target, node, grid_pos, node.get_blend_mode_name(), opacity, depth, run)
        if _reached:
            return


## Whether the render up to a node stops at *node*: the stop itself, or a
## hidden pass-through group around it, skipped whole, so the stop is reached
## at the group.
func _stops_at(node: SaLayer) -> bool:
    if _stop == null or node == _stop:
        return _stop != null
    # A lifted stop is reached after the whole tree, wherever it sits.
    return not node.visible and SaLayerStack.is_inside(_stop, node) and not SaBackdropLayer.lifts(_stop)


## *node*, a layer or an isolated group, into *target* at *grid_pos* by *mode*
## at *opacity*: its filters, then its mask, then the blend. With *clipped*,
## the layers clipped to it, the two go in as one group by *mode* and
## *opacity*, each clipped layer at its own, since the group carries what the
## pass-through groups around it multiply in.
func _render_node(
    target: SaTexture,
    node: SaLayer,
    grid_pos: Vector2i,
    mode: StringName,
    opacity: float,
    depth: int,
    clipped: Array[SaLayer] = []
) -> void:
    var compositor := _document.compositor
    var space := _document.color_space
    var white := _document.blend_reference_white
    var whole := Rect2i(Vector2i.ZERO, target.size)
    if not clipped.is_empty():
        var lay_base := func(into: SaTexture) -> void: _render_node(into, node, grid_pos, SaLayer.BLEND_MODE.NORMAL, 1.0, depth)
        var lay_clipped := func(plate: SaTexture) -> void:
            for layer in clipped:
                if _stops_at(layer):
                    _reached = true
                    return
                # A pass-through group lays its members on the plate one by
                # one, each by its own mode, as the fold's clip run does.
                if layer.visible and layer.is_group and not SaLayerStack.isolates(layer):
                    _render_nodes(plate, _siblings.of(layer), grid_pos, layer.opacity, depth)
                elif layer.visible:
                    _render_node(plate, layer, grid_pos, layer.get_blend_mode_name(), layer.opacity, depth)
                if _reached:
                    return
        compositor.clip_group.composite(
            compositor, target, Vector2.ZERO, whole, mode, opacity, space, white, lay_base, lay_clipped
        )
        return
    if node.is_generated():
        compositor.composite_generated_chunk(target, node, mode, opacity, grid_pos, Vector2.ZERO, whole, space, white)
        return
    if node.is_adjustment():
        # The target holds the backdrop by now, which is all a point step
        # reads, and a blur reads it around the chunk as well.
        var draw := func(chunk: SaTexture, at: Vector2i, below: Array[SaLayer], by: float) -> void:
            _render_nodes(chunk, below, at, by, depth)
        _step(compositor).flattened(compositor, target, node, opacity, grid_pos, draw)
        return
    var drawn: SaTexture = null
    var neighbours: SaLayer = null
    # A layer with a live transform is drawn from its cache, as the fold
    # draws it, and the cache holds the layer's mask already.
    var paint := SaLiveTransform.paint_of(node)
    if node.is_group:
        drawn = _scratch(depth, target.format)
        compositor.clear_scratch_batch([[drawn, whole]])
        _render_nodes(drawn, _siblings.of(node), grid_pos, 1.0, depth + 1)
    else:
        # No chunk here is still something to draw when the node's filters
        # carry the paint beside it in, and `shown` answers null when they
        # do not.
        drawn = paint.get_field(grid_pos)
        neighbours = paint
        if _previewed:
            drawn = compositor.point_preview.drawn(compositor, _document, node, drawn, grid_pos, whole)
    var source := compositor.shown(node, paint, drawn, grid_pos, whole, neighbours)
    if source == null:
        return
    compositor.composite_chunk(target, source, mode, opacity, Vector2.ZERO, space, white, whole)


## The adjustment step a render through *compositor* takes: the compositor's,
## and one of this render's own while its `detail` places it at another density.
func _step(compositor: SaCompositor) -> SaBackdropLayer:
    if not compositor.detail.active():
        return compositor.adjustment
    if _sized_step == null:
        _sized_step = SaBackdropLayer.new(false)
    return _sized_step


## The scratch an isolated group at *depth* composites into, at *format*.
func _scratch(depth: int, format: int) -> SaTexture:
    while _scratches.size() <= depth:
        _scratches.append(null)
    var scratch := _scratches[depth]
    if scratch == null or scratch.format != format:
        scratch = SaTexture.new(Vector2i(SaLayer.CHUNK_SIZE, SaLayer.CHUNK_SIZE), format)
        _scratches[depth] = scratch
    return scratch


## Every group's members, bottom first, read from the document once for a
## walk. `SaLayerStack.members` reads every layer of the document each time it
## is asked, and the walk asks it of each node it reaches, for its clip base
## and its clipped run, so a walk of a few hundred layers in groups spent half
## a second of the main thread a chunk on it. A walk changes no layer's place,
## so what this read at its start holds until it ends.
class Siblings:
    extends RefCounted

    ## A group's instance id, nought for the top level, to its members.
    var _members: Dictionary[int, Array] = {}
    ## A layer's instance id to its place among its group's members.
    var _at: Dictionary[int, int] = {}

    func _init(document: SaDocument) -> void:
        for child in document.get_children():
            var layer := child as SaLayer
            if layer == null:
                continue
            var group := SaLayerStack.parent_of(layer)
            var key := group.get_instance_id() if group != null else 0
            if not _members.has(key):
                _members[key] = [] as Array[SaLayer]
            var found: Array[SaLayer] = _members[key]
            _at[layer.get_instance_id()] = found.size()
            found.append(layer)

    ## The members of *group*, or of the top level for null.
    func of(group: SaLayer) -> Array[SaLayer]:
        var key := group.get_instance_id() if group != null else 0
        if not _members.has(key):
            return [] as Array[SaLayer]
        return _members[key]

    ## `SaLayerStack.clip_base` of *layer*.
    func clip_base(layer: SaLayer) -> SaLayer:
        if not layer.clip_to_below:
            return null
        var at: int = _at.get(layer.get_instance_id(), -1)
        return SaLayerStack.base_among(of(SaLayerStack.parent_of(layer)), at)

    ## `SaLayerStack.clipped_run` of *layer*.
    func clipped_run(layer: SaLayer) -> Array[SaLayer]:
        var at: int = _at.get(layer.get_instance_id(), -1)
        return SaLayerStack.run_among(of(SaLayerStack.parent_of(layer)), at)
