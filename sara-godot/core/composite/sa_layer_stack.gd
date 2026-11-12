## The questions the walk asks of the layer tree. What the compositor walks is
## the layers below the active one folded into one cache, and the layers above
## it as an ordered list in which only runs of plain Normal are folded.
##
## Every layer has a real destination, the canvas as it is when the walk
## reaches it, rather than a cache cleared to transparent and drawn with
## Normal: Porter-Duff over an empty destination returns the source, so a
## Multiply layer above a painting would multiply against nothing and do
## nothing.
##
## Two caches remain, because a dab must not rebuild the stack. Everything
## below the active layer folds into one, whatever its modes, since that cache's
## destination never changes between dabs. Above the active layer only plain
## Normal folds, because Porter-Duff over is associative and no other mode is:
## (A over B) over C is A over (B over C), so a run of Normal layers is one
## texture and one dispatch, and a Multiply between two runs is applied from
## its own chunks against the canvas that already holds everything under it.
##
## Groups are the same walk one level down. A pass-through group's members take
## their places in the parent's order with the group's opacity multiplied in.
## An isolated group folds its members into a cache of its own, whatever their
## modes, and joins the parent's order as one step with the group's mode and
## opacity, which is the intermediate target its modes need. An
## isolated group with the active layer inside it cannot fold, so it becomes a
## scope: its own bottom and top stacks around the active layer, or around the
## next isolated group in, and the compositor renders the chain through one
## scratch chunk per level.
##
## This file answers questions about the layer tree and holds no state. The
## rebuild, and the caches and stacks it fills, are `SaLayerFold`'s, which the
## document holds one of.
class_name SaLayerStack
extends RefCounted

## The keys of a stack entry. A Dictionary rather than a class, because the
## compositor reads four fields and nothing else does.
const LAYER := "layer"
const MODE := "mode"
const OPACITY := "opacity"
## A clipping base's step: the steps clipped to it, laid one by one onto the
## base's own pixels made opaque, each by its own mode and opacity, before the
## base's alpha is put back and the whole is laid by the entry's mode and
## opacity, which are the base's. Absent on every other step. `SaClipGroup`
## draws it. A base and its run are one group, the way Photoshop's clipping
## masks are, so a clipped layer covering the base hides it with no rim.
const CLIPPED := "clipped"
## The tree node the entry stands for, whose attached filters run over its
## chunk. A plain layer is its own node. An isolated group's entry composites
## a cache, and its node is the group, which is what makes a group's filters
## run over the group's composite with no second code path. Absent on a run
## cache, which stands for no node.
const NODE := "node"
## Marks the place in an order where the active layer, or the isolated group
## holding it, sits. Never reaches the compositor.
const SPLIT := "split"

## The keys of a scope in `SaLayerFold.active_scopes`. A scope that holds
## `BASE` is a clip group around the active layer rather than an isolated
## group: its group is the base, `BASE` is the base's own step, empty when the
## base is the active layer, and its bottom and top are the steps clipped to
## the base below and above the active layer.
const GROUP := "group"
const BOTTOM := "bottom"
const TOP := "top"
const BASE := "base"


## One step of the walk: composite *layer* with *mode* at *opacity*, standing
## for *node* when there is one.
static func entry(layer: SaLayer, mode: StringName, opacity: float, node: SaLayer = null) -> Dictionary[String, Variant]:
    var step: Dictionary[String, Variant] = {LAYER: layer, MODE: mode, OPACITY: opacity}
    if node != null:
        step[NODE] = node
    return step


## The step of a clipping base and *clipped*, the steps clipped to it: the base
## as *drawn* draws it, and the group laid by *mode* at *opacity*.
static func clip_group(
    drawn: Dictionary, mode: StringName, opacity: float, clipped: Array[Dictionary]
) -> Dictionary[String, Variant]:
    var step := entry(layer_of(drawn), mode, opacity, node_of(drawn))
    step[CLIPPED] = clipped
    return step


## The layer *step* composites, as `entry` wrote it. These readers are where an
## entry's values are typed, since the Dictionary holds a layer, a name and a
## number side by side and hands each back as a Variant.
static func layer_of(step: Dictionary) -> SaLayer:
    var layer: SaLayer = step[LAYER]
    return layer


## The blend mode *step* composites with.
static func mode_of(step: Dictionary) -> StringName:
    var mode: StringName = step[MODE]
    return mode


## The opacity *step* composites at.
static func opacity_of(step: Dictionary) -> float:
    var opacity: float = step[OPACITY]
    return opacity


## The steps clipped to *step*'s layer, laid on its plate, empty for a step
## that is no clipping base.
static func clipped_of(step: Dictionary) -> Array[Dictionary]:
    var held: Array = step.get(CLIPPED, [])
    var clipped: Array[Dictionary] = []
    clipped.assign(held)
    return clipped


## A clipping base's own step inside its group: its layer as it shows, laid
## Normal and whole into the group's first scratch.
static func base_step(step: Dictionary) -> Dictionary[String, Variant]:
    return entry(layer_of(step), SaLayer.BLEND_MODE.NORMAL, 1.0, node_of(step))


## *step* and every step clipped to it, the steps whose layers a fold reads.
static func parts_of(step: Dictionary) -> Array[Dictionary]:
    var parts: Array[Dictionary] = [step]
    parts.append_array(clipped_of(step))
    return parts


## The node *step* stands for, or *fallback* when it names none.
static func node_of(step: Dictionary, fallback: SaLayer = null) -> SaLayer:
    var node: SaLayer = step.get(NODE, fallback)
    return node


## The isolated group a scope of `SaLayerFold.active_scopes` renders, or the
## base of a clip scope.
static func group_of(scope: Dictionary) -> SaLayer:
    var group: SaLayer = scope[GROUP]
    return group


## Whether *scope* is a clip group around the active layer rather than an
## isolated group.
static func is_clip_scope(scope: Dictionary) -> bool:
    return scope.has(BASE)


## Every layer the compositor reads, in walk order: the bottom stack, each
## scope's bottom, the active layer, the stroke buffer, each scope's top from
## the inside out, the top stack. Caches and real layers alike, nothing null.
static func layers(document: SaDocument) -> Array[SaLayer]:
    # A walk the stack changed under may name a layer freed since.
    if document.fold.debt.owes_whole():
        return SaFoldDebt.drawn_from(document)
    var found: Array[SaLayer] = []
    _gather(found, document.fold.bottom_stack)
    for scope: Dictionary in document.fold.active_scopes:
        _gather(found, _below_in(scope))
    if document.active_layer != null:
        found.append(document.active_layer)
    if document.stroke_layer != null:
        found.append(document.stroke_layer)
    for i in range(document.fold.active_scopes.size() - 1, -1, -1):
        var scope: Dictionary = document.fold.active_scopes[i]
        var above: Array = scope[TOP]
        _gather(found, above)
    _gather(found, document.fold.top_stack)
    return found


## Appends to *found* the layer of every step of *steps* and of every step
## clipped to one.
static func _gather(found: Array[SaLayer], steps: Array) -> void:
    for stack_entry: Dictionary in steps:
        for part in parts_of(stack_entry):
            found.append(layer_of(part))


## The steps a scope draws below the active layer: its bottom, after its
## base's own step when it is a clip group whose base is not the active layer.
static func _below_in(scope: Dictionary) -> Array:
    var base: Dictionary = scope.get(BASE, {})
    return ([base] if not base.is_empty() else []) + scope[BOTTOM]


## The layers the active tier reads per chunk: the active layer, the stroke
## buffer, and everything inside the scopes around them.
static func active_tier_layers(document: SaDocument) -> Array[SaLayer]:
    var found: Array[SaLayer] = []
    if document.active_layer != null:
        found.append(document.active_layer)
    if document.stroke_layer != null:
        found.append(document.stroke_layer)
    for scope: Dictionary in document.fold.active_scopes:
        var above: Array = scope[TOP]
        _gather(found, _below_in(scope) + above)
    return found


## Marks dirty every chunk *layer* draws on, and every chunk the layers inside
## it draw on when it is a group.
##
## `SaDocument.invalidate_all_allocated_chunks()` cannot answer this question.
## It walks `layers()` below, which is what the compositor reads, so a layer
## that a rebuild has just taken out of the walk is not in it and the region it
## drew would keep the composite it had. Hiding a layer rebuilds first, so
## without this a hidden layer's paint stays on the canvas, and on the minimap,
## until something else marks those chunks.
##
## Here because the question is about the walk rather than about the
## document.
static func invalidate_layer_chunks(document: SaDocument, layer: SaLayer) -> void:
    var covered := drawn_by(document, layer)
    if not covered.is_empty():
        document.invalidate_chunks(covered.keys())


## Every grid position *layer* draws on, and the layers inside it when it is a
## group and the layers clipped to it, as a set: what
## `invalidate_layer_chunks` marks, and what a write of its attached filters'
## parameters redraws.
static func drawn_by(document: SaDocument, layer: SaLayer) -> Dictionary[Vector2i, bool]:
    var covered: Dictionary[Vector2i, bool] = {}
    if document == null or layer == null:
        return covered
    for affected in _layers_drawn_by(document, layer):
        # A layer that stores nothing has drawn over the whole document.
        # `SaGeneratedLayer.covered_positions()` is no use here for the reason
        # the walk is no use: it asks whether one is in the walk, and the layer
        # that has just been hidden has already left it.
        if affected.is_generated():
            for grid_pos in SaLayer.grid_positions(document.canvas_size):
                covered[grid_pos] = true
        for grid_pos in affected.chunks:
            covered[grid_pos] = true
        # An adjustment layer holds no chunk and has drawn wherever the
        # layers below it do, the whole grid when one of those is generated.
        if affected.is_adjustment():
            for grid_pos in SaBackdropLayer.drawn_over(document, affected):
                covered[grid_pos] = true
    return covered


## *layer* and every layer whose drawing follows it: what a group holds at any
## depth, and what is clipped to it. Both stop drawing when it does, so both
## leave a region behind that nothing else would mark.
static func _layers_drawn_by(document: SaDocument, layer: SaLayer) -> Array[SaLayer]:
    var found: Array[SaLayer] = [layer]
    for child in document.get_children():
        var other := child as SaLayer
        if other == null or other == layer:
            continue
        if is_inside(other, layer) or clip_base(document, other) == layer:
            found.append(other)
    return found


## Sets the flag the way a document setter would: marks the document
## modified, queues the rebuild and announces the change. Here rather than on
## `SaDocument` because what the flag changes is the walk: which base a layer
## clips to is this class's answer, and so are the chunks a layer that leaves
## the walk leaves behind.
static func set_clip_to_below(document: SaDocument, layer: SaLayer, value: bool) -> void:
    if document == null or layer == null or layer.clip_to_below == value:
        return
    layer.clip_to_below = value
    document.modified = true
    # The rebuild marks the walk, and a layer that has just been clipped to a
    # hidden base is no longer in it, so its own chunks are marked here.
    invalidate_layer_chunks(document, layer)
    document.request_cache_update()
    document.document_changed.emit()


# ---------------------------------------------------------------------------
# Groups
# ---------------------------------------------------------------------------


## The group *layer* belongs to, or null: at the top level, or when the
## reference points at something that is no longer a group in this document.
static func parent_of(layer: SaLayer) -> SaLayer:
    if layer == null:
        return null
    var group := layer.group
    if group == null or not is_instance_valid(group) or not group.is_group or group == layer:
        return null
    if group.get_parent() != layer.get_parent():
        return null
    return group


## How many groups *layer* sits inside.
static func depth(layer: SaLayer) -> int:
    var count := 0
    var group := parent_of(layer)
    while group != null and count < 64:
        count += 1
        group = parent_of(group)
    return count


## The layers whose group is *group*, in the document's order. Null is the
## top level.
static func members(document: SaDocument, group: SaLayer) -> Array[SaLayer]:
    var found: Array[SaLayer] = []
    for child in document.get_children():
        var layer := child as SaLayer
        if layer != null and parent_of(layer) == group:
            found.append(layer)
    return found


## Whether *layer* is *group* or sits inside it, at any depth.
static func is_inside(layer: SaLayer, group: SaLayer) -> bool:
    var at := layer
    var guard := 0
    while at != null and guard < 64:
        if at == group:
            return true
        at = parent_of(at)
        guard += 1
    return false


## The layers of *picked* in *document* and not inside another picked group,
## each once. Delete and Duplicate act on these, so a group picked with its
## child goes or is copied once with the child inside it.
static func roots(document: SaDocument, picked: Array[SaLayer]) -> Array[SaLayer]:
    var present: Array[SaLayer] = []
    for layer in picked:
        if layer != null and is_instance_valid(layer) and layer.get_parent() == document and not present.has(layer):
            present.append(layer)
    var found: Array[SaLayer] = []
    for layer in present:
        var covered := false
        for other in present:
            if other != layer and other.is_group and is_inside(layer, other):
                covered = true
                break
        if not covered:
            found.append(layer)
    return found


## The layer *layer* is clipped to: the nearest sibling below it that is not
## clipped, so a stack of clipped layers all clip to one base and a clip never
## reaches out of its group. Null for a layer that is not clipped or has no
## base, which is then walked as if the flag were off, and null too when that
## sibling is a group, which has no pixels of its own to be a base. A group is
## not skipped to the layer under it, because a layer clipped above it would
## then join a base the group lies between, which a base and its run
## composited as one group cannot draw in its place.
static func clip_base(document: SaDocument, layer: SaLayer) -> SaLayer:
    if layer == null or not layer.clip_to_below:
        return null
    var siblings := members(document, parent_of(layer))
    return base_among(siblings, siblings.find(layer))


## [method clip_base] of the layer at *at* in *siblings*, its group's members
## bottom first, for a walk that read them once rather than once a layer.
static func base_among(siblings: Array[SaLayer], at: int) -> SaLayer:
    if at < 0 or not siblings[at].clip_to_below:
        return null
    var index := at - 1
    while index >= 0 and siblings[index].clip_to_below:
        index -= 1
    if index < 0 or siblings[index].is_group:
        return null
    return siblings[index]


## The layers clipped to *layer*, the run of clipped siblings right above it,
## bottom first, which composite with it as one group. Empty for a layer that
## is no base: one clipped itself or a group, and an adjustment layer, which
## has no pixels of its own, so what is clipped to it shows nothing.
static func clipped_run(document: SaDocument, layer: SaLayer) -> Array[SaLayer]:
    if layer == null:
        return [] as Array[SaLayer]
    var siblings := members(document, parent_of(layer))
    return run_among(siblings, siblings.find(layer))


## [method clipped_run] of the layer at *at* in *siblings*, as
## [method base_among] is [method clip_base].
static func run_among(siblings: Array[SaLayer], at: int) -> Array[SaLayer]:
    var run: Array[SaLayer] = []
    if at < 0:
        return run
    var layer := siblings[at]
    if layer.is_group or layer.is_adjustment() or base_among(siblings, at) != null:
        return run
    for index in range(at + 1, siblings.size()):
        if not siblings[index].clip_to_below:
            break
        run.append(siblings[index])
    return run


## Whether a layer clipped to *base* can show anything at *grid_pos*: where the
## base holds a chunk, and everywhere for a generated base, which stores none
## and whose kernel `clip_alpha` evaluates at the chunk.
static func clip_reaches(base: SaLayer, grid_pos: Vector2i) -> bool:
    return base.is_generated() or base.chunks.has(grid_pos)


## Whether *layer* contributes anything: hidden layers, layers inside a hidden
## group, clipped layers under a hidden base, and clipped layers on an
## adjustment layer, which has no pixels of its own to show them on, do not.
static func contributes(document: SaDocument, layer: SaLayer) -> bool:
    return layer.visible and could_show(document, layer)


## Whether *layer* would contribute when it is visible itself: no group it is
## in is hidden and its clip base, when it has one, shows it. A layer for which
## this is false moves nothing in the picture when it is shown or hidden.
static func could_show(document: SaDocument, layer: SaLayer) -> bool:
    var group := parent_of(layer)
    var guard := 0
    while group != null and guard < 64:
        if not group.visible:
            return false
        group = parent_of(group)
        guard += 1
    var base := clip_base(document, layer)
    return base == null or (base.visible and not base.is_adjustment())


## Whether the canvas draws *layer*: it contributes, and Isolate Active Layer,
## [SaLocalView], does not leave it out. The compositor's walk and fold ask
## this, and a command on the document asks [method contributes], because a
## merge or a bake while isolated takes every visible layer as the file holds it.
static func shows(document: SaDocument, layer: SaLayer) -> bool:
    return contributes(document, layer) and not SaLocalView.leaves_out(document, layer)


## Whether *layer* composites its members into an intermediate of its own
## before it blends into what lies below, and the one place that says so. A
## group does when the painter isolated it, while it carries a mask or an
## enabled attached filter, because a mask hides a composite and a filter runs
## over one. A pass-through group has none of these: its members blend
## straight into the layers below, and a pass-through group clipped to the
## layer below lays them one by one on the base's plate, each by its own mode.
## The clip is no reason to isolate: a painter groups a Multiply and a Hard
## Light layer and clips the group to lay two blend effects on one base, and
## an isolated group would lay them over transparent instead. The flag is never written for either's sake, so dropping
## the mask, or detaching the last filter, gives the group its pass-through
## back with no second step. **The rejected alternative** is writing `isolated`
## on attach: a detach then cannot tell an isolation the painter asked for from
## one a filter caused.
static func isolates(layer: SaLayer) -> bool:
    return layer != null and layer.is_group and (layer.isolated or held_isolated(layer))


## Whether something the group carries isolates it whatever its flag says: a
## mask, or an attached filter that is on. The layers docker dims its Blend
## Group on Its Own row on this, because unticking the flag would change
## nothing, and marks the group's row.
##
## The two are not alike when switched off, on purpose. A mask switched off
## still isolates, so toggling it changes what is hidden and never how the
## members' blend modes read. A filter switched off composites as if it were
## not there, which is what `enabled` promises, and a group with nothing to run
## has no composite to run it over.
static func held_isolated(layer: SaLayer) -> bool:
    return layer != null and layer.is_group and (layer.mask != null or SaFilterChain.has_enabled(layer.filters))


## The pass-through groups between *layer* and the nearest isolated group
## around it, or the top level, multiply their opacities into its own.
static func passthrough_multiplier(layer: SaLayer) -> float:
    var factor := 1.0
    var group := parent_of(layer)
    var guard := 0
    while group != null and not isolates(group) and guard < 64:
        factor *= group.opacity
        group = parent_of(group)
        guard += 1
    return factor
