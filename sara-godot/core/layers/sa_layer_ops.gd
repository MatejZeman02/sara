## Every operation on the layer stack and on its groups, each one a history step.
##
## Built by whoever runs one and dropped at once, the way `SaCrop` is: an
## object with a job, not a piece of the document. A step binds a method of the
## instance that made it, so UndoRedo dropping the step drops both.
##
## Two shapes of step. A property change, opacity, blend mode, visibility, a
## lock, a name, a move, is a pair of values and goes through `SaHistory.commit_pair`,
## with opacity folded so a slider drag is one step. A structural change, add,
## duplicate, delete, merge down, flatten, a wrap into a group, takes a layer
## out of the document or puts one in, and the layer stays alive inside the step
## in a `LayerKeeper`. Undo and redo toggle its presence, so one Callable serves
## both directions the way `SaDocument.swap_pixels` does for chunks.
##
## The group operations and the moves of a layer's block among its siblings
## are `SaLayerGroups` in `groups/`, which this class forwards to, so a caller still asks
## one door. The keeper, `take_out`, `put_back` and `refresh` are public for
## it, the mechanics every structural step shares.
class_name SaLayerOps
extends RefCounted


## A layer that is out of the document, kept alive by the history step that
## took it out or put it in, together with the stack position it goes back to.
##
## A Node is not RefCounted, so dropping the last reference to one leaks it and
## every chunk it holds. The keeper is RefCounted and bound into the step's
## Callable, so when UndoRedo evicts the step the keeper goes with it, and it
## frees the layer then, but only if the layer is still out of a document: an
## add that was undone and then dropped from the redo stack keeps the layer
## that never came back, a delete that was undone leaves the layer where the
## painter put it.
class LayerKeeper:
    extends RefCounted

    ## Metadata key on the layer: how many keepers hold it. An add and a later
    ## delete of the same layer are two steps with two keepers, and the older
    ## one being evicted while the layer is out of the document must not free
    ## what the newer one still promises to bring back.
    const COUNT_KEY := &"sa_layer_keepers"

    var layer: SaLayer
    var index: int
    ## The layer the brush goes back to when this one leaves, by its id, since
    ## a step outlives a layer a later delete frees. Nought is the one under it.
    var back_to: int

    func _init(kept: SaLayer, at: int, back: SaLayer = null) -> void:
        layer = kept
        index = at
        back_to = back.get_instance_id() if back != null else 0
        layer.set_meta(COUNT_KEY, SaTyped.whole(layer.get_meta(COUNT_KEY, 0)) + 1)

    ## VRAM the layer holds, which is what the step is charged with while the
    ## layer is out of the document.
    func bytes() -> int:
        var total := 0
        if layer == null or not is_instance_valid(layer):
            return total
        for grid_pos: Vector2i in layer.chunks:
            var chunk: SaChunk = layer.chunks[grid_pos]
            if chunk != null:
                total += chunk.byte_size()
        return total

    func _notification(what: int) -> void:
        if what != NOTIFICATION_PREDELETE or layer == null or not is_instance_valid(layer):
            return
        var remaining := SaTyped.whole(layer.get_meta(COUNT_KEY, 1)) - 1
        layer.set_meta(COUNT_KEY, remaining)
        if remaining <= 0 and layer.get_parent() == null:
            layer.free()


## Several picked rows read as one merge, which is what Merge Down does to a
## pick of more than one row: its layers in the stack's order, and what stops
## them going into the lowest. The Layers docker reads it too, for the hover of
## its dimmed Merge Down row.
class MergePick:
    extends RefCounted

    ## What the corner says over picked rows with a gap between them, or rows
    ## of two different groups, which a Shift range of rows never is.
    const NOT_SIDE_BY_SIDE := "Merge needs layers that sit next to each other."

    ## The picked layers in the stack's order, bottom first, each once, and only
    ## the ones in the document.
    var layers: Array[SaLayer] = []
    ## What stops them merging into the lowest, as a template for `tr` and the
    ## names that go in it, the way `SaLayerRefusals.merge` answers, or nothing.
    var stop: Array = []

    func _init(document: SaDocument, picked: Array) -> void:
        # A picked group's members go with it, so they are not uppers of their own.
        for child in document.get_children():
            if child is SaLayer and picked.has(child) and not _in_picked_group(child as SaLayer, picked):
                layers.append(child as SaLayer)
        if layers.size() > 1:
            stop = _stop(document)

    ## Whether a group *layer* sits inside is in *picked* too.
    static func _in_picked_group(layer: SaLayer, picked: Array) -> bool:
        var group := SaLayerStack.parent_of(layer)
        var guard := 0
        while group != null and guard < 64:
            if picked.has(group):
                return true
            group = SaLayerStack.parent_of(group)
            guard += 1
        return false

    ## Why the layers will not merge, in the words the corner says, or empty
    ## when they will.
    func refusal() -> String:
        return tr(str(stop[0])) % stop.slice(1) if not stop.is_empty() else ""

    ## Not siblings standing next to each other, or the first upper the lowest
    ## cannot take, for a reason `SaLayerRefusals.merge` gives.
    func _stop(document: SaDocument) -> Array:
        var siblings := SaLayerStack.members(document, SaLayerStack.parent_of(layers[0]))
        var start := siblings.find(layers[0])
        for i in layers.size():
            if start + i >= siblings.size() or siblings[start + i] != layers[i]:
                return [NOT_SIDE_BY_SIDE]
        var refusals := SaLayerRefusals.new(document)
        for upper: SaLayer in layers.slice(1):
            var found := refusals.merge(upper, layers[0])
            if not found.is_empty():
                return found
        return []


## The corner line a delete that would leave no layer is refused with.
const KEEPS_A_LAYER := "A document needs at least one layer, so these layers were not deleted."

var _document: SaDocument
var _fold: SaMergeFold
var _refusals: SaLayerRefusals


func _init(document: SaDocument) -> void:
    _document = document
    _fold = SaMergeFold.new(document)
    _refusals = SaLayerRefusals.new(document)


## The stack, bottom first. Every child of the document is a layer: the stroke
## buffer and the caches are deliberately not children.
func layers() -> Array[SaLayer]:
    var stack: Array[SaLayer] = []
    for child in _document.get_children():
        if child is SaLayer:
            stack.append(child as SaLayer)
    return stack


# ---------------------------------------------------------------------------
# Structure
# ---------------------------------------------------------------------------


## Adds a layer above the active one, of *type_id* when *types* knows that type.
##
## The default is the plain colour layer, which is what every caller wanted
## before layer types existed and is what an empty id still means. A type the
## registry does not know falls back to the plain schema and says so, rather
## than refusing to add a layer at all: this is reached from a UI button, and a
## button that does nothing is worse than a layer of the wrong kind plus an
## error. `SaContext.create_layer` is the module-facing door, and it refuses.
##
## The registry is a parameter, not the document's: a document is made per
## easel, and whoever knows about layer types already has the registry. *scale*
## is the layer's `resolution_scale`, 2.0 for New Layer at Double Resolution,
## and 0.0, the default, leaves it to the document's Double Resolution switch,
## `SaDoubleResolution.scale_for`, which makes a paint layer at 2.0 while the
## switch is on. A caller that uploads a picture at the document's density
## names 1.0.
##
## A ground goes where `SaGeneratedLayer.lay` says, under the painting, rather
## than over the active layer, where its opaque paper covered every stroke. An
## undo gives the brush back to the layer it was on. A kind whose descriptor
## says `under_paint` goes in at the same place and leaves the brush where it
## was, because its picture is to paint over. *step* names the history's
## row, "Paste" or "Place Picture" for a picture that lands as a new layer.
func add(type_id: StringName = &"", types: SaLayerTypeRegistry = null, scale: float = 0.0, step := "Add Layer") -> SaLayer:
    var layer := SaLayer.new()
    layer.name = SaLayerNames.next_for(_document)
    layer.schema = SaFieldSpec.schema_for_space(_document.color_space)
    if not String(type_id).is_empty():
        if types == null or not types.apply_to(layer, type_id, _document.color_space):
            push_error("SaLayerOps.add: unknown layer type '%s', adding a plain layer." % type_id)
    # After the type, which says whether the layer holds paint of its own.
    layer.resolution_scale = scale if scale > 0.0 else _document.double_resolution.scale_for(layer)
    var was_active := _document.active_layer
    var index := was_active.get_index() + 1 if was_active != null else layers().size()
    # Into the group the active layer is in, so a layer added above a member
    # is a member too.
    layer.group = SaLayerStack.parent_of(was_active)
    var under := types != null and types.has(type_id) and types.get_descriptor(type_id).under_paint
    if layer.is_generated():
        index = SaGeneratedLayer.lay(_document, layer, types.get_descriptor(type_id))
    elif under:
        layer.group = null
        index = SaGeneratedLayer.ground_index(_document)
    _document.add_child(layer)
    _document.move_child(layer, index)
    layer.source = SaEffectLayer.first_input(_document, layer) if layer.is_effect() else null
    # No grid. The layer allocates where the brush lands, transparent when made.
    _document.modified = true
    if not under or was_active == null:
        _document.set_active_layer(layer)
    commit_presence(step, [LayerKeeper.new(layer, index, was_active)])
    return layer


## Records *block*, nodes a caller already put into the document bottom first,
## as one step that takes them all out and brings them all back, which is what
## an import of many layers is. The keepers go top first, so each one takes
## the index it stands at when it leaves and the lowest-first return lands it
## there again.
func commit_added(action_name: String, block: Array[SaLayer]) -> void:
    var keepers: Array = []
    for i in range(block.size() - 1, -1, -1):
        keepers.append(LayerKeeper.new(block[i], block[i].get_index()))
    _document.modified = true
    refresh()
    commit_presence(action_name, keepers)


## Copies a layer above itself as a layer of its own kind, a group with
## copies of its members, through `SaLayerDuplicate`. The copies leave and
## come back together, which is the one step a duplicate is, and the copy on
## top is the active layer.
func duplicate(source: SaLayer) -> SaLayer:
    var block := SaLayerDuplicate.new(_document).place(source)
    if block.is_empty():
        return null
    _document.set_active_layer(block[-1])
    commit_added("Duplicate Layer", block)
    return block[-1]


## Takes a layer out of the document. Undoable, and the layer lives on inside
## the step, charged to the history's layer pool rather than its paint pool so
## that a delete never costs a stroke.
##
## The only layer is cleared rather than refused. A document always has a layer,
## so there is nothing sensible to take out, and a delete button that answers
## nothing at all reads as broken.
##
## A group goes with everything inside it, as `remove_group` takes it, because
## taking the group alone would leave its members loose at the top of the stack and
## the picture the painter meant to remove still in the saved file.
func remove(layer: SaLayer) -> bool:
    if not can_remove(layer):
        return false
    if layer.is_group:
        return remove_group(layer)
    if layers().size() <= 1:
        return _clear_only(layer)
    var keeper := LayerKeeper.new(layer, layer.get_index())
    take_out(keeper)
    _document.modified = true
    refresh()
    commit_presence("Delete Layer", [keeper], keeper.bytes())
    return true


## Whether `remove`, or `remove_group` for a group, would do anything to
## *layer*, which is what dims Delete Layer. Everything in the document can go,
## and the only layer is emptied instead, which a lock refuses, so the only
## layer locked is the one case where the press does nothing. A group goes with
## its members, so not when they are the whole document.
func can_remove(layer: SaLayer) -> bool:
    var stack := layers()
    if layer == null or not stack.has(layer):
        return false
    if layer.is_group:
        return _groups().can_remove_group(layer)
    return stack.size() > 1 or not layer.is_locked


## Deletes every layer of *picked* as one step, which is what the minus does to
## a pick of several rows, so one Ctrl+Z brings them all back.
##
## A layer inside a picked group goes with the group and is not counted again.
## A pick that comes down to one layer or one group is `remove` or
## `remove_group`, so the only layer is still cleared and a lone group's step
## keeps its name. A pick that would take every layer out, a group that is the
## whole document or several rows that are, is refused whole with one corner
## line, `KEEPS_A_LAYER`, rather than leaving the document with no layer.
func remove_many(picked: Array[SaLayer]) -> bool:
    var roots := SaLayerStack.roots(_document, picked)
    if roots.is_empty():
        return false
    if roots.size() == 1 and not roots[0].is_group:
        return remove(roots[0])
    var block: Array[SaLayer] = []
    for root in roots:
        block.append_array(subtree(root))
    if block.size() >= layers().size():
        SaProblems.refuse("Delete Layer", tr(KEEPS_A_LAYER))
        return false
    if roots.size() == 1:
        return remove_group(roots[0])
    block.sort_custom(func(a: SaLayer, b: SaLayer) -> bool: return a.get_index() < b.get_index())
    var keepers: Array = []
    var layer_bytes := 0
    # Top of the stack first, as `SaLayerGroups.remove_group` does, so two
    # keepers never claim one slot.
    for i in range(block.size() - 1, -1, -1):
        var keeper := LayerKeeper.new(block[i], block[i].get_index())
        take_out(keeper)
        layer_bytes += keeper.bytes()
        keepers.append(keeper)
    _document.modified = true
    refresh()
    commit_presence("Delete Layers", keepers, layer_bytes)
    return true


## Layer > Resample to Document Resolution, whose pass is `SaLayerBake`, and
## whether it has anything to bake.
func bake(layer: SaLayer) -> bool:
    return SaLayerBake.new(_document).bake(layer)


func can_bake(layer: SaLayer) -> bool:
    return SaLayerBake.can_bake(layer)


## Whether `merge_down` would merge *layer*, which is what dims Merge Down:
## there is a layer below it, a group's sibling under it for a group, neither
## of the two is a generated layer, the lower one is no group, and it can take
## a merge. Over *picked*, several rows of
## the Layers docker, it is whether they merge into the lowest of them. Quiet,
## because a menu asks it on every open.
func can_merge_down(layer: SaLayer, picked: Array = []) -> bool:
    var pick := MergePick.new(_document, picked)
    if pick.layers.size() > 1:
        return pick.stop.is_empty()
    var lower := SaGroupMerge.lower_of(_document, layer)
    return lower != null and _refusals.can_take(layer, lower)


## Composites a layer into the one below it, with its own blend mode and
## opacity, and takes it out of the document.
##
## One dispatch of the blend kernel per chunk into the lower layer's chunk, so
## a Multiply layer merges as the product, on the GPU throughout. A hidden
## layer contributes nothing and is still taken out, as in Krita. The lower
## layer's chunks are snapshotted first, so the whole thing is one step.
## A group goes down into the paint layer under it drawn as the canvas draws
## it, and leaves with everything inside it, `SaGroupMerge`.
##
## What is merged is what was on screen: the upper layer goes through its
## attached filters and its mask on the way in, and the lower layer's own
## filters and its mask are written into it first and taken off it, because a
## filter left on the lower layer would run over the upper layer's paint from
## then on, and a mask left on it would hide that paint wherever it is zero,
## which is what Krita does with a transparency mask on a merge. A mask that
## is switched off hides nothing now and stays. The records and the mask live
## on in the step, so undo puts them back.
##
## **Several picked rows**, *picked*, merge into the lowest of them as one
## step instead, which is what Merge Down does to a pick in Krita and
## Photoshop, or the corner says why not. The uppers go in bottom to top, each
## with its own mode, opacity, filters and mask, the order the canvas draws
## them in. Merged down from the top, each upper took the mode and opacity of
## the one under it, which is not what the rows showed. A pick of one row is
## *layer*, so a single Merge Down is the one it always was.
func merge_down(layer: SaLayer, picked: Array = []) -> bool:
    var pick := MergePick.new(_document, picked)
    if pick.layers.size() > 1:
        if not pick.stop.is_empty():
            SaProblems.refuse("Merge Down", pick.refusal())
            return false
        _merge_into(pick.layers[0], pick.layers.slice(1))
        return true
    var lower := SaGroupMerge.lower_of(_document, layer)
    if lower == null:
        return false
    if _refusals.refuses_merge("Merge Down", layer, lower):
        return false
    var uppers: Array[SaLayer] = [layer]
    _merge_into(lower, uppers)
    return true


## The step both merges are: a live transform on *lower* baked into its chunks
## and taken off it, so it holds its paint where the canvas showed it, then
## *lower*'s own filters and mask written into it and taken off it, its
## opacity written into its paint and set to 1, `SaOpacityBake`, each of
## *uppers*, bottom first, composited into it with one snapshot of its chunks,
## a transformed one as the canvas draws it, and the uppers taken out, top
## first, so each keeper holds the index its layer stood at. All on the GPU,
## nothing read back, and one undo puts every layer back, a transform with it.
func _merge_into(lower: SaLayer, uppers: Array[SaLayer]) -> void:
    var state: Dictionary[Vector2i, Variant] = {}
    var live := SaLiveTransform.bake_into(_document, lower, state)
    SaTreeRender.new(_document).bake(lower, lower, state)
    var baked := _fold.take_filters(lower)
    var shape := _fold.take_mask(lower)
    var height := SaHeightOps.new(_document)
    SaOpacityBake.new(_document).bake(lower, state, height, shape)
    var taken := SaGroupMerge.taken(_document, uppers)
    height.give_schema(lower, taken, shape)
    for upper in uppers:
        if upper.is_group:
            SaGroupMerge.new(_document).composite_into(lower, upper, state, height)
        else:
            _fold.composite_into(lower, upper, state, height)
    var keepers: Array = []
    var layer_bytes := 0
    for i in range(taken.size() - 1, -1, -1):
        var keeper := LayerKeeper.new(taken[i], taken[i].get_index())
        take_out(keeper)
        layer_bytes += keeper.bytes()
        keepers.append(keeper)
    _document.set_active_layer(lower)
    _document.modified = true
    refresh()
    var swap := _toggle_merge.bind(lower, state, keepers, baked, shape)
    _document.history.commit(
        "Merge Down", SaLiveTransform.toggled(_document, lower, live, swap), state, layer_bytes, kept_layers(keepers)
    )


## The whole tree drawn into the bottom layer, and every other layer and
## group taken out, as one step. What the bottom layer holds afterwards is
## what the canvas showed, group by group: a group's members composite into
## it the way the compositor draws them, an isolated one into an intermediate
## and then through its filters, mask, mode and opacity, so a flatten never
## reads a group's members as if they stood at the top level. The
## bottom layer is drawn as a node of the tree like the rest and then shows
## its paint plainly: Normal, whole, unclipped, at the top level, with its
## enabled filters and its mask taken off, all of which undo puts back. The
## document's root filters stay where they are, because the root is still
## there. A layer with a live transform is drawn through it, and a bottom
## layer with one has it baked into its chunks first and taken off, which
## undo puts back too.
##
## **A bottom layer that stores nothing**, a ground, a filter layer or an
## empty group, was refused, which left Flatten unusable on a document laid on
## a paper. The flatten draws into a new paint layer of its
## name instead, takes it out with the rest, and the new layer is one more
## keeper of the step, so one undo takes it out and puts every layer back.
func flatten() -> bool:
    var stack := layers()
    if stack.size() < 2:
        return false
    var fresh := _paint_under(stack[0])
    var bottom := fresh if fresh != null else stack[0]
    if _refusals.refuses_merge("Flatten", null, bottom):
        if fresh != null:
            fresh.free()
        return false
    var state: Dictionary[Vector2i, Variant] = {}
    var live := SaLiveTransform.bake_into(_document, bottom, state)
    _flatten_into(bottom, stack, state)
    var baked := _fold.take_filters(bottom)
    var shape := _fold.take_mask(bottom)
    SaHeightOps.new(_document).give_schema(bottom, stack, shape)
    var plain := {
        &"opacity": 1.0, &"blend_mode": SaLayer.BLEND_MODE.NORMAL, &"clip_to_below": false, &"group": null, &"visible": true
    }
    for key: StringName in plain:
        shape[key] = bottom.get(key)
        bottom.set(key, plain[key])
    var keepers: Array = []
    var layer_bytes := 0
    for i in range(stack.size() - 1, -1 if fresh != null else 0, -1):
        var keeper := LayerKeeper.new(stack[i], stack[i].get_index())
        take_out(keeper)
        layer_bytes += keeper.bytes()
        keepers.append(keeper)
    if fresh != null:
        # Last, once the old bottom is out, so the name it takes is free.
        var kept := LayerKeeper.new(fresh, 0)
        put_back(kept)
        keepers.append(kept)
    _document.set_active_layer(bottom)
    _document.modified = true
    refresh()
    var swap := _toggle_merge.bind(bottom, state, keepers, baked, shape)
    _document.history.commit(
        "Flatten", SaLiveTransform.toggled(_document, bottom, live, swap), state, layer_bytes, kept_layers(keepers)
    )
    return true


## The plain paint layer a flatten draws into when *bottom* stores nothing, of
## its name and the document's schema, not yet in the document, or null when
## *bottom* stores paint and takes the flatten itself.
func _paint_under(bottom: SaLayer) -> SaLayer:
    if _refusals.stores_paint(bottom):
        return null
    var layer := SaLayer.new()
    layer.take_name(bottom.shown_name())
    layer.schema = SaFieldSpec.schema_for_space(_document.color_space)
    return layer


## Every grid position the tree draws on rendered into a new chunk, the chunks
## put into *bottom* and each one they replace put into *state*, its pixel
## state, unless the bake of its transform put one there first. Rendered
## before anything moves, because the tree is read as it stands.
func _flatten_into(bottom: SaLayer, stack: Array[SaLayer], state: Dictionary[Vector2i, Variant]) -> void:
    var render := SaTreeRender.new(_document)
    var reach: Dictionary[Vector2i, bool] = {}
    for grid_pos: Vector2i in bottom.chunks:
        reach[grid_pos] = true
    for layer in stack:
        layer.resolve_pending()
        if layer.is_group or not SaLayerStack.contributes(_document, layer):
            continue
        var covered: Dictionary[Vector2i, bool] = {}
        for grid_pos: Vector2i in _covered_by(layer):
            covered[grid_pos] = true
        reach.merge(render.reach(layer, covered))
    # A group's halo reaches past its members' chunks, and a group inside it
    # past that, so the ring is taken once per group over everything so far.
    for layer in stack:
        if layer.is_group and SaLayerStack.contributes(_document, layer):
            reach.merge(render.reach(layer, reach.duplicate()))
    var schema: Array[SaFieldSpec] = []
    for spec in bottom.schema:
        if spec != null and spec.id != SaFieldSpec.MASK:
            schema.append(spec)
    var flat: Dictionary[Vector2i, SaChunk] = {}
    for grid_pos: Vector2i in reach:
        flat[grid_pos] = render.flattened(schema, grid_pos)
    SaHeightOps.new(_document).flatten(SaHeightOps.spec_among(stack), stack, flat)
    for grid_pos: Vector2i in reach:
        if not state.has(grid_pos):
            state[grid_pos] = bottom.chunks.get(grid_pos, null)
        bottom.set_chunk(grid_pos, flat[grid_pos])


# ---------------------------------------------------------------------------
# Groups and the tree's order, which `SaLayerGroups` does
# ---------------------------------------------------------------------------


## Whether `move` would shift *layer* by *delta*, which is what dims Move Up
## and Move Down.
func can_move(layer: SaLayer, delta: int) -> bool:
    return _groups().can_move(layer, delta)


## Moves a layer *delta* sibling steps up the stack, or down for a negative
## delta, as one Move Layer step, a group's block moving whole.
func move(layer: SaLayer, delta: int) -> bool:
    return _groups().move(layer, delta)


## Wraps the active layer in a new pass-through group. Answers the group.
func group_active() -> SaLayer:
    return _groups().group_active()


## Wraps several layers in one new pass-through group, as one step.
func group_layers(members: Array) -> SaLayer:
    return _groups().group_layers(members)


## Dissolves a group into its parent, what it did to its members written into them.
func ungroup(group: SaLayer) -> bool:
    return _groups().ungroup(group)


## Takes a group out with everything inside it, as one step.
func remove_group(group: SaLayer) -> bool:
    return _groups().remove_group(group)


## Isolated or pass-through, as a step.
func set_isolated(group: SaLayer, value: bool) -> void:
    _groups().set_isolated(group, value)


## Puts *layer* and its subtree into *group* at *index*, as one step.
func place(layer: SaLayer, group: SaLayer, index: int) -> bool:
    return _groups().place(layer, group, index)


## *layer* followed by everything inside it, in the document's order.
func subtree(layer: SaLayer) -> Array[SaLayer]:
    return _groups().subtree(layer)


func _groups() -> SaLayerGroups:
    return SaLayerGroups.new(_document)


# ---------------------------------------------------------------------------
# Properties
# ---------------------------------------------------------------------------


## The eye is a place on the trail, and a history step only when Preferences'
## `visibility_in_history` asks for one: what it owes the fold is paid over the
## frames after it, and a stall in that work would be named by whatever stood
## before, a load or a save of minutes past. Off the history, `_apply_visible`
## marks the document changed and that is the whole record.
func set_visible(layer: SaLayer, value: bool) -> void:
    if layer == null or layer.visible == value:
        return
    var previous := layer.visible
    SaTrail.note("the eye of %s, %s" % [layer.name, "shown" if value else "hidden"])
    var traced := SaFrameTrace.now()
    _apply_visible(layer, value)
    SaFrameTrace.spent("eye", traced)
    if not SaSettings.visibility_in_history:
        return
    _document.history.commit_pair("Layer Visibility", _apply_visible.bind(layer, value), _apply_visible.bind(layer, previous))


## Folded: a slider announces every pixel it travels, and a drag is one change.
## *merge* is the fold, which a MIDI turn opens with MERGE_DISABLE so a turn
## after a rest starts a step of its own rather than folding into the last.
func set_opacity(layer: SaLayer, value: float, merge: UndoRedo.MergeMode = UndoRedo.MERGE_ENDS) -> void:
    if layer == null:
        return
    var previous := layer.opacity
    var clamped := clampf(value, 0.0, 1.0)
    if is_equal_approx(previous, clamped):
        return
    _apply_opacity(layer, clamped)
    _document.history.commit_pair(
        "Layer Opacity", _apply_opacity.bind(layer, clamped), _apply_opacity.bind(layer, previous), 0, 0, merge
    )


## *merge* folds a run of Ctrl wheel steps on a blend button into one step.
func set_blend_mode(layer: SaLayer, mode_id: StringName, merge: UndoRedo.MergeMode = UndoRedo.MERGE_DISABLE) -> void:
    if layer == null or layer.blend_mode == mode_id:
        return
    var previous: StringName = layer.blend_mode
    _apply_blend_mode(layer, mode_id)
    _document.history.commit_pair(
        "Layer Blend Mode", _apply_blend_mode.bind(layer, mode_id), _apply_blend_mode.bind(layer, previous), 0, 0, merge
    )


func set_locked(layer: SaLayer, value: bool) -> void:
    if layer == null or layer.is_locked == value:
        return
    _apply_locked(layer, value)
    _document.history.commit_pair("Layer Lock", _apply_locked.bind(layer, value), _apply_locked.bind(layer, not value))


func set_alpha_locked(layer: SaLayer, value: bool) -> void:
    if layer == null or layer.alpha_locked == value:
        return
    _apply_alpha_locked(layer, value)
    _document.history.commit_pair(
        "Layer Alpha Lock", _apply_alpha_locked.bind(layer, value), _apply_alpha_locked.bind(layer, not value)
    )


## Names *layer* *wanted*, and gives it *note* in the same step when a note is
## passed, as one "Rename Layer" step. True when the step was recorded.
##
## Godot makes a node's name unique among its siblings, so a name another layer
## already holds lands with a digit on it. The name is applied once and read
## back, and both sides of the step write the names read rather than the typed
## text, so a redo gives the layer the name its row showed. The name is the one
## the painter sees, full stops and colons kept, through `SaLayer.take_name`. Nothing that changes
## neither the name nor the note is a step, and an empty name is not a name.
func rename(layer: SaLayer, wanted: String, note: Variant = null) -> bool:
    if layer == null or wanted.is_empty():
        return false
    var old_name := layer.shown_name()
    var old_note := layer.comment
    var new_note: String = note if note is String else old_note
    if wanted == old_name and new_note == old_note:
        return false
    _apply_name(layer, wanted, new_note)
    var landed := layer.shown_name()
    # A name a sibling holds can come back as the one the layer had.
    if landed == old_name and new_note == old_note:
        return false
    _document.history.commit_pair(
        "Rename Layer", _apply_name.bind(layer, landed, new_note), _apply_name.bind(layer, old_name, old_note)
    )
    return true


# ---------------------------------------------------------------------------
# The do and undo sides
# ---------------------------------------------------------------------------


## Shows or hides *layer*, its fold owed to `SaFoldDebt` and paid over the
## frames after it, as the Layers docker's eye does.
##
## A layer inside a hidden group, or clipped to a hidden base, shows nothing
## either way, so its eye owes no fold and redraws nothing, and only the docker
## hears of it.
func _apply_visible(layer: SaLayer, value: bool) -> void:
    layer.visible = value
    _document.layer_changed.emit(layer)
    _document.modified = true
    if not SaLayerStack.could_show(_document, layer):
        _document.document_changed.emit()
        return
    _document.fold.debt.owe_shown(_document, layer)


## Opacity and blend mode refold at the end of the frame, a slider writes per tick.
func _apply_opacity(layer: SaLayer, value: float) -> void:
    layer.opacity = value
    _document.layer_changed.emit(layer)
    _mark_moved(layer)


func _apply_blend_mode(layer: SaLayer, mode_id: StringName) -> void:
    layer.blend_mode = mode_id
    _document.layer_changed.emit(layer)
    _mark_moved(layer)


## Marks what *layer*'s new opacity or mode moves. A layer the picture leaves
## out, hidden or inside a hidden group, moves nothing in it, so nothing is
## marked or refolded and only the docker hears of it: a painter's
## night lights were set inside hidden groups, and each such step redrew the
## group's 27 chunks through 540 layers.
func _mark_moved(layer: SaLayer) -> void:
    _document.modified = true
    if not SaLayerStack.contributes(_document, layer):
        _document.document_changed.emit()
        return
    _document.invalidate_chunks(SaLayerStack.drawn_by(_document, layer).keys(), layer)
    _document.request_cache_update(layer)


func _apply_locked(layer: SaLayer, value: bool) -> void:
    layer.is_locked = value
    _document.layer_changed.emit(layer)
    _document.modified = true
    _document.document_changed.emit()


func _apply_alpha_locked(layer: SaLayer, value: bool) -> void:
    layer.alpha_locked = value
    _document.layer_changed.emit(layer)
    _document.modified = true
    _document.document_changed.emit()


## Nothing in the engine announces a rename, so the signal is what puts the
## name back on its row after an undo.
func _apply_name(layer: SaLayer, value: String, note: String) -> void:
    layer.take_name(value)
    layer.comment = note
    _document.layer_changed.emit(layer)
    _document.modified = true
    _document.document_changed.emit()


## Registers a structural step: undo takes the keepers' layers out or puts them
## back, whichever is the opposite of where they are now.
func commit_presence(action_name: String, keepers: Array, layer_bytes: int = 0) -> void:
    _document.history.commit(action_name, _toggle_presence.bind(keepers), {}, layer_bytes, kept_layers(keepers))


## The layers *keepers* hold, which the step hands the history so that
## `SaResidency` can move their chunks to RAM while they are out of the tree.
static func kept_layers(keepers: Array) -> Array:
    var found: Array = []
    for keeper: LayerKeeper in keepers:
        found.append(keeper.layer)
    return found


func _toggle_presence(keepers: Array) -> void:
    var attaching: Array = []
    for keeper: LayerKeeper in keepers:
        if keeper.layer.get_parent() == _document:
            take_out(keeper)
        else:
            attaching.append(keeper)
    # Lowest first, so each one lands at the index it was taken from.
    attaching.sort_custom(func(a: LayerKeeper, b: LayerKeeper) -> bool: return a.index < b.index)
    for keeper: LayerKeeper in attaching:
        put_back(keeper)
    _document.modified = true
    refresh()


## The presence toggle already points the document at what came back, or at
## the neighbour below what left, which is the lower layer.
##
## *baked* is the records the merge took off *lower*, each with the place it
## held: there, they leave, and gone, they come back where they were, before
## the refresh the presence toggle ends on. *shape* is the members of *lower*
## the step changed, its schema when the mask went, each holding the other
## side's value and swapped with the live one, so one call serves both ways.
func _toggle_merge(
    lower: SaLayer,
    state: Dictionary[Vector2i, Variant],
    keepers: Array,
    baked: Array = [],
    shape: Dictionary[StringName, Variant] = {}
) -> void:
    _document.swap_pixels(lower, state)
    for slot: Array in baked:
        var record: SaAttachedFilter = slot[0]
        if lower.filters.has(record):
            lower.filters.erase(record)
        else:
            lower.filters.insert(mini(SaTyped.whole(slot[1]), lower.filters.size()), record)
    for key: StringName in shape:
        var live: Variant = lower.get(key)
        lower.set(key, shape[key])
        shape[key] = live
    _toggle_presence(keepers)


## Takes a layer out of the document, and marks what it was drawing dirty
## before it goes.
##
## The dirty set every refresh builds walks the layers that are *there*, so a
## grid position this layer covered and nobody else does is invisible to every
## refresh after the child is removed, and the canvas keeps the composite the
## layer was still part of, a stale painting under an empty stack. The mark
## lives here rather than in `remove`
## because every door that takes a layer out comes through this one: the delete,
## the redo of a delete and the undo of an add in `_toggle_presence`, a merge or
## a flatten whose upper layer stores nothing to composite, and
## `SaLayerGroups.remove_group`.
func take_out(keeper: LayerKeeper) -> void:
    var layer := keeper.layer
    if layer.get_parent() != _document:
        return
    keeper.index = layer.get_index()
    var stack := layers()
    var neighbour_index := stack.find(layer)
    _document.invalidate_chunks(_covered_by(layer))
    _document.remove_child(layer)
    stack = layers()
    # The last layer out leaves it alone: a flatten into a new layer empties
    # the stack until that layer's `put_back`, which makes it active.
    # Back to the layer an add was made from, since a ground lands far from it.
    if _document.active_layer == layer and not stack.is_empty():
        var back := instance_from_id(keeper.back_to) as SaLayer if keeper.back_to != 0 else null
        var below := stack[clampi(neighbour_index - 1, 0, stack.size() - 1)]
        _document.set_active_layer(back if back != null and back.get_parent() == _document else below)


## Puts a kept layer back at the index it was taken from and makes it active.
func put_back(keeper: LayerKeeper) -> void:
    var layer := keeper.layer
    if layer.get_parent() == _document:
        return
    _document.add_child(layer)
    _document.move_child(layer, clampi(keeper.index, 0, _document.get_child_count() - 1))
    layer.mark_all_unresolved()
    _document.set_active_layer(layer)


## Every grid position *layer* draws on: the chunks it holds, the chunks its
## live transform's cache holds when it carries one, or the whole document
## when it stores nothing and has therefore drawn everywhere.
func _covered_by(layer: SaLayer) -> Array:
    if layer.is_generated():
        return SaGeneratedLayer.covered_positions(_document)
    return SaLiveTransform.paint_of(layer).chunks.keys()


## Emptying the only layer, which is what deleting it means.
##
## Through the document's own clear, so the colour space conversion, the
## selection and the generated layers all behave the way they do for the Clear
## action beside the delete one, and this unit adds no second way to empty a
## layer. The step it registers is that clear, so the undo menu never offers to
## undo a delete that did not happen.
func _clear_only(layer: SaLayer) -> bool:
    if layer.is_locked:
        return false
    _document.clear_layer(layer)
    refresh()
    return true


## The chunks of the layers the change moved marked dirty, all when `SaFoldDebt`
## cannot read it as theirs, and the caches owed a fold the next draw pays once.
func refresh() -> void:
    _document.fold.debt.owe(_document, true)
    _document.document_changed.emit()


func _name_taken(candidate: String) -> bool:
    for child in _document.get_children():
        if str(child.name) == candidate:
            return true
    return false


## *pattern* with the first number from *from* that no layer is named.
func free_name(pattern: String, from: int) -> String:
    var number := from
    while _name_taken(pattern % number):
        number += 1
    return pattern % number
