## Every operation on a node's attached filters, each one a history step.
##
## Built by whoever runs one and dropped at once,
## `SaFilterOps.new(document).attach(layer, key, values)`, the way `SaLayerOps`
## is. A step binds a method of the instance that made it, which keeps that
## instance alive exactly as long as the step.
##
## A node is an `SaLayer`, a group being one, or null for the document's root,
## which is the document's global filter and one more list rather than a second
## mechanism. A record taken out of its list stays alive inside the step that
## took it out, mask and all, because it is `RefCounted` and bound into the
## step's Callable. That is what a layer needs a keeper for and a record does
## not.
class_name SaFilterOps
extends RefCounted

var _document: SaDocument = null


## The layers a bake on a group or on the whole picture reaches, read once:
## those it writes, every paint layer under the node the brush may write, and
## for each other layer under it the sentence that says why it was passed over,
## translated. A group is neither, since its members are read in its place.
class Reach:
    extends RefCounted

    var written: Array[SaLayer] = []
    var passed: Array[String] = []

    ## Reads *document* under *node*, a group, or every layer for null.
    func _init(document: SaDocument, node: SaLayer) -> void:
        var refusals := SaLayerRefusals.new(document)
        for layer in SaLayerOps.new(document).layers():
            if layer.is_group or not (node == null or SaLayerStack.is_inside(layer, node)):
                continue
            var why := refusals.sentence(SaLayerRefusals.Act.STORE, layer)
            if why.is_empty() and layer.refuses_paint():
                why = "'%s' is locked." if layer.is_locked else "'%s' takes no paint."
            if why.is_empty():
                written.append(layer)
            else:
                passed.append(TranslationServer.translate(why) % layer.name)


func _init(document: SaDocument) -> void:
    _document = document


## The list *node* keeps its records in, the document's own for null. The array
## itself and not a copy, so a step edits what the compositor reads.
func filters_of(node: SaLayer) -> Array[SaAttachedFilter]:
    return _document.root_filters if node == null else node.filters


## Attaches the filter registered under *key* to *node* with *values*, on top of
## the node's other filters or at *index*, masked by the selection when one is
## active, and answers the record. The key is not looked up: a record of a filter
## no installed module registers is legal, as a loaded document may hold.
func attach(node: SaLayer, key: StringName, values: Dictionary = {}, index: int = -1) -> SaAttachedFilter:
    if key == &"" or not _holds(node):
        return null
    var record := SaAttachedFilter.new(key, values)
    if _refused_finer("Attach Filter", node, record) or _refused_adjusting("Attach Filter", node, record):
        return null
    var at := filters_of(node).size() if index < 0 else mini(index, filters_of(node).size())
    SaMaskOps.new(_document).mask_from_selection(record)
    _insert(node, record, at)
    _commit("Attach Filter", _insert.bind(node, record, at), _remove.bind(node, record), 0, record.byte_size())
    return record


## Takes *record* off *node*. The step keeps it, so undo brings back the same
## record with the same mask, and is charged with what that mask holds.
func detach(node: SaLayer, record: SaAttachedFilter) -> bool:
    var at := filters_of(node).find(record) if _holds(node) else -1
    if at < 0:
        return false
    _remove(node, record)
    _commit("Detach Filter", _remove.bind(node, record), _insert.bind(node, record, at), 0, record.byte_size())
    return true


## Switches *record* on or off, as a step.
func set_enabled(record: SaAttachedFilter, value: bool) -> void:
    if record == null or record.enabled == value:
        return
    _apply_enabled(record, value)
    _commit("Toggle Filter", _apply_enabled.bind(record, value), _apply_enabled.bind(record, not value))


## Gives *record* the parameters *values*, as a step named Edit Filter whose
## undo puts back *was*, or what the record held before when *was* is null.
## Answers whether it made one.
##
## The one door both of a record's editors write through. The Tool Options
## panel passes its live values with *merge* `UndoRedo.MERGE_ENDS` after its
## first write, so a drag folds into one step, and Godot folds only a step that
## follows its namesake within 800 ms, so a drag held still longer than that is
## two. The edit window has already written its values live as the preview,
## so it hands the values it opened with as *was* and the step only adds the
## undo side.
func set_parameters(
    record: SaAttachedFilter, values: Dictionary, merge: UndoRedo.MergeMode = UndoRedo.MERGE_DISABLE, was: Variant = null
) -> bool:
    if record == null:
        return false
    var before: Dictionary = record.parameters
    if was is Dictionary:
        before = was
    before = before.duplicate(true)
    var after := values.duplicate(true)
    if before == after:
        return false
    if record.parameters != after:
        write(record, after)
    _commit("Edit Filter", write.bind(record, after), write.bind(record, before), 0, 0, merge)
    return true


## Moves *record* to *index* among *node*'s filters, counted with the record
## taken out, the way `Node.move_child` counts.
func reorder(node: SaLayer, record: SaAttachedFilter, index: int) -> bool:
    var from := filters_of(node).find(record) if _holds(node) else -1
    if from < 0:
        return false
    var to := clampi(index, 0, filters_of(node).size() - 1)
    if to == from:
        return false
    _move(node, record, to)
    _commit("Reorder Filter", _move.bind(node, record, to), _move.bind(node, record, from))
    return true


## Carries *record* from *from* to *to*, on top of that node's other filters or
## at *index*: one detach and one attach in one step, which is what a drag from
## one node's row to another's is. The same record, so its mask and its
## parameters go with it.
func move_to(from: SaLayer, record: SaAttachedFilter, to: SaLayer, index: int = -1) -> bool:
    if from == to or not _holds(from) or not _holds(to):
        return false
    var was := filters_of(from).find(record)
    if was < 0 or _refused_finer("Move Filter", to, record) or _refused_adjusting("Move Filter", to, record):
        return false
    var list := filters_of(to)
    var at := list.size() if index < 0 else mini(index, list.size())
    _carry(from, record, to, at)
    _commit("Move Filter", _carry.bind(from, record, to, at), _carry.bind(to, record, from, was))
    return true


## A copy of *record* directly above it on the same node, with a mask of its
## own, and answers the copy.
func duplicate(node: SaLayer, record: SaAttachedFilter) -> SaAttachedFilter:
    var from := filters_of(node).find(record) if _holds(node) else -1
    if from < 0:
        return null
    var copy := record.duplicate_record()
    _insert(node, copy, from + 1)
    _commit("Duplicate Filter", _insert.bind(node, copy, from + 1), _remove.bind(node, copy))
    return copy


## Writes *record* into the pixels of what it hangs on and takes it off, as one
## history step whose undo brings back both. Answers whether it wrote.
##
## Through the compositor's chain and never a second evaluation, the way
## `SaLayerOps` bakes a merged layer's filters: every chunk of each target is
## run through the node's records into a copy, and the copies go in at the end,
## the originals becoming the step's snapshot. So the texels written are the
## texels the canvas showed, masks and neighbourhoods included, which is the
## board's rule that the attach and the one-shot are two callers of one filter.
## Into copies and not in place because a neighbourhood pass reads the chunks
## around the one it writes.
##
## **Every record the chain runs before it goes too**, in the chain's order,
## because one written into the pixels while those stay attached would run them
## after it and move the picture. A finishing record runs after the plain ones.
## One switched off stays, and flattening one that is off is refused.
##
## A layer is its own target. A group holds no pixels, so its records are
## written into its members one by one, and the root's into every layer, which
## is the page's rule. A layer that stores no paint is passed over, and a
## locked one refuses the whole flatten rather than a part. A record on an
## adjustment or an effect layer is refused, there being no paint under it,
## and Merge Down is what bakes one. `SaLayerRefusals` says which kinds.
## `flatten_sentence` is what the caller shows before either of those. The
## chain runs no node for the root, so the root's point passes are walked
## over each layer in place, and a neighbourhood pass on the root is refused:
## the pixels around a texel of the root are the whole composite, which no
## one layer holds.
func flatten(node: SaLayer, record: SaAttachedFilter) -> bool:
    if not _holds(node):
        return false
    var list := filters_of(node)
    var at := list.find(record)
    if at < 0:
        return false
    if SaLayerRefusals.new(_document).refuses("Flatten Filter", SaLayerRefusals.Act.WRITE_FILTER, node):
        return false
    if not record.enabled:
        SaProblems.refuse("Flatten Filter", tr("The filter is switched off, so there is nothing to flatten."))
        return false
    var targets := targets_of(node)
    for layer in targets:
        if layer.is_locked:
            SaProblems.refuse("Flatten Filter", tr("'%s' is locked, so nothing was flattened.") % layer.name)
            return false
    var chain := _chain()
    var taken := _taken(chain, list, record)
    var passes: Array[SaPointPass] = []
    for below in taken:
        var recorded: SaPointPass = chain.call("pass_for", _document, node, below) if chain != null else null
        if recorded == null:
            SaProblems.refuse("Flatten Filter", tr("'%s' cannot be evaluated here, so nothing was flattened.") % below.key)
            return false
        passes.append(recorded)
    var baked: Array[SaAttachedFilter] = []
    var places: Array[int] = []
    for index in list.size():
        if taken.has(list[index]):
            baked.append(list[index])
            places.append(index)
    # Keyed by Variant, because a typed key refuses a layer that was freed.
    var states: Dictionary[Variant, Dictionary] = {}
    if node == null:
        for recorded in passes:
            if recorded is SaNeighbourhoodPass:
                SaProblems.refuse("Flatten Filter", tr("A document-wide filter that reads its neighbours cannot be flattened."))
                return false
        for layer in targets:
            var state: Dictionary[Vector2i, Variant] = {}
            for i in passes.size():
                _bake(layer, passes[i], _coverage_of(taken[i]), state)
            states[layer] = state
    else:
        # The records the chain runs after the flattened one stay attached and
        # out of the chain while it runs, and the array goes back as it was.
        var kept := list.duplicate()
        for each: SaAttachedFilter in kept:
            if not taken.has(each):
                list.erase(each)
        for layer in targets:
            states[layer] = _through_chain(chain, node, layer)
        list.assign(kept)
    var paint_bytes := 0
    for layer: SaLayer in states.keys():
        if (states[layer] as Dictionary).is_empty():
            states.erase(layer)
        else:
            paint_bytes += _bytes_of(states[layer])
    var layer_bytes := 0
    for gone in baked:
        filters_of(node).erase(gone)
        layer_bytes += gone.byte_size()
    _written()
    var toggle := _toggle_flatten.bind(node, baked, places, states)
    _commit("Flatten Filter", toggle, toggle, paint_bytes, layer_bytes, UndoRedo.MERGE_DISABLE, states.values())
    return true


## One sentence saying what `flatten` would do with *record*, for the caller to
## show before it does it: which records and which layers.
func flatten_sentence(node: SaLayer, record: SaAttachedFilter) -> String:
    if not _holds(node):
        return ""
    var list := filters_of(node)
    if not list.has(record):
        return ""
    var count := _taken(_chain(), list, record).size()
    var into := targets_of(node).size()
    var owner := tr("the whole document") if node == null else tr("'%s'") % node.name
    if count > 1:
        var many := tr_n(
            "Flatten applies %d filters of %s to %d layer and removes them.",
            "Flatten applies %d filters of %s to %d layers and removes them.",
            into
        )
        return many % [count, owner, into]
    var one := tr_n(
        "Flatten applies this filter of %s to %d layer and removes it.",
        "Flatten applies this filter of %s to %d layers and removes it.",
        into
    )
    return one % [owner, into]


## The layers a flatten on *node* writes into: the layer itself, a group's
## members at every depth, or every layer for the root. A layer that stores
## no paint by `SaLayerRefusals` is left out.
func targets_of(node: SaLayer) -> Array[SaLayer]:
    var found: Array[SaLayer] = []
    var refusals := SaLayerRefusals.new(_document)
    for layer in SaLayerOps.new(_document).layers():
        if not refusals.stores_paint(layer):
            continue
        if node == null or layer == node or (node.is_group and SaLayerStack.is_inside(layer, node)):
            found.append(layer)
    return found


## The filter of *key* run once over *layer* with *values* and written into
## it, as one history step called *title*, through the same pass an attached
## record of it would evaluate to. What a filter dialog's Apply is when the
## filter records a point pass. Answers whether it wrote.
##
## The attach and the flatten of the page, with the list left out of it: a
## record put on the layer and taken off again inside one step is a step that
## changes nothing but the pixels, so the record is built, evaluated and
## dropped without ever being listed. The coverage is the document's
## selection rather than a mask, because a one-shot honours the selection it
## was run under, and it is bound where the record's mask would be.
func apply_once(layer: SaLayer, key: StringName, values: Dictionary, title: String) -> bool:
    if layer == null or not _holds(layer) or SaFilterApply.refuses_bake(title, layer):
        return false
    var states: Dictionary[Variant, Dictionary] = {layer: _once(layer, key, values)}
    return _commit_states(title, states)


## Apply's Bake on the group *node*, or on the whole picture for null, the
## dialog's Affect all: the filter of *ctx* run over every paint layer under
## it that the brush may write and written into each, as one history step
## named after the filter, whose undo puts every layer back. Answers whether
## it wrote. Every other layer under it, one that stores no paint or one that
## is locked, is named in the corner with why.
##
## Run again in a context of each layer's own, because a run reads one layer's
## pixels at that layer's density, and the dialog's context was made for the
## group, which holds none. A point filter is then written as `apply_once`
## writes it, through the pass an attached record would evaluate to, and the
## other two kinds by `SaFilterApply.apply`, which hands back its undo state
## rather than recording it.
func bake_under(node: SaLayer, ctx: SaFilterContext, filter: SaFilter) -> bool:
    if ctx == null or filter == null or not _holds(node):
        return false
    var title := filter.title()
    var reach := Reach.new(_document, node)
    if not reach.passed.is_empty():
        SaProblems.refuse(title, tr("Passed over: %s") % " ".join(PackedStringArray(reach.passed)))
    elif reach.written.is_empty():
        # The picture's line is whole, so a language with cases declines it. A
        # layer's name is the painter's, quoted, and stands as it was typed.
        if node == null:
            SaProblems.refuse(title, tr("There is no layer in the picture to bake into."))
        else:
            SaProblems.refuse(title, tr("There is no layer in %s to bake into.") % ("'%s'" % node.name))
    var key := SaFilterRegistry.key_for(ctx.module_id, filter)
    var states: Dictionary[Variant, Dictionary] = {}
    for layer in reach.written:
        var own := SaFilterContext.new(_document, layer, ctx.module_id, title, true)
        if not SaFilterApply.call_run(filter, own):
            continue
        if own.point != null and not own.point is SaNeighbourhoodPass:
            states[layer] = _once(layer, key, filter.parameters())
        else:
            SaFilterApply.apply(own, title, states)
    return _commit_states(title, states)


## Why a bake on the group *node*, or on the whole picture for null, would
## write nothing, translated, or an empty string when some layer under it
## takes the filter. What `SaFilterApply.way_refusal` dims Bake with there.
func bake_refusal(node: SaLayer) -> String:
    if not Reach.new(_document, node).written.is_empty():
        return ""
    if node == null:
        return tr("No layer of the picture takes paint, so there is nothing to bake.")
    return tr("'%s' holds no layer the filter can write, so there is nothing to bake.") % node.name


## Apply in a filter's dialog over the context *ctx* its last run was made in,
## the one-shot. A filter that recorded a point pass goes through `apply_once`,
## so its texels are the ones it would show attached. One that only showed a
## texture cannot be attached at all, and one that recorded a neighbourhood pass
## is written by `apply_neighbourhood`, which gathers a chunk's neighbours
## through the same runner the chain does, so both keep the write they had.
## A group, and with *every*, Affect all, the whole picture, is `bake_under`'s.
##
## **The rejected alternative** was leaving the point filters on the old write
## as well: two paths to the same texels are two answers the first bug report
## cannot tell apart.
static func one_shot(ctx: SaFilterContext, filter: SaFilter, every: bool = false) -> bool:
    if ctx == null or filter == null:
        return false
    if every or (ctx.layer != null and ctx.layer.is_group):
        return SaFilterOps.new(ctx.document).bake_under(null if every else ctx.layer, ctx, filter)
    if ctx.point == null or ctx.point is SaNeighbourhoodPass:
        return SaFilterApply.apply(ctx, filter.title())
    var key := SaFilterRegistry.key_for(ctx.module_id, filter)
    return SaFilterOps.new(ctx.document).apply_once(ctx.layer, key, filter.parameters(), filter.title())


## Where *record* hangs: the layer whose list holds it, or null for the root's
## and for a record the document does not hold. Null is also the root, so a
## caller that must tell the two apart asks `filters_of(null).has(record)`.
func node_of(record: SaAttachedFilter) -> SaLayer:
    for layer in SaLayerOps.new(_document).layers():
        if layer.filters.has(record):
            return layer
    return null


## Every chunk of *layer* run through *node*'s enabled records by *chain* into
## a copy, the copies put in at the end and the chunks they replace answered
## as a pixel state. *layer* is where the chain reads a chunk's neighbours,
## which for a group's record is the member being written.
func _through_chain(chain: Object, node: SaLayer, layer: SaLayer) -> Dictionary[Vector2i, Variant]:
    var state: Dictionary[Vector2i, Variant] = {}
    var rd := GlobalShaderCompiler.get_rd()
    if chain == null or rd == null:
        return state
    var written: Dictionary[Vector2i, SaChunk] = {}
    for grid_pos: Vector2i in layer.chunks:
        var chunk: SaChunk = layer.chunks[grid_pos]
        if chunk == null:
            continue
        var albedo := chunk.albedo()
        var filtered: SaTexture = chain.call("filtered", node, albedo, grid_pos, Rect2i(), layer)
        if filtered == albedo:
            continue
        var copy := chunk.duplicate_chunk()
        var extent := Vector3(albedo.size.x, albedo.size.y, 1)
        rd.texture_copy(filtered.rid, copy.albedo().rid, Vector3.ZERO, Vector3.ZERO, extent, 0, 0, 0, 0)
        written[grid_pos] = copy
    for grid_pos: Vector2i in written:
        state[grid_pos] = layer.chunks[grid_pos]
        layer.set_chunk(grid_pos, written[grid_pos])
    return state


## The filter of *key* with *values* walked once over *layer* through the pass
## an attached record of it would evaluate to, the pixel state of what it
## wrote answered, empty where the chain builds no point pass for it.
func _once(layer: SaLayer, key: StringName, values: Dictionary) -> Dictionary[Vector2i, Variant]:
    var state: Dictionary[Vector2i, Variant] = {}
    var chain := _chain()
    var record := SaAttachedFilter.new(key, values)
    var recorded: SaPointPass = chain.call("pass_for", _document, layer, record) if chain != null else null
    if recorded != null and not recorded is SaNeighbourhoodPass:
        _bake(layer, recorded, _coverage_of(null), state)
    return state


## One step named *title* over *states*, a pixel state a layer, whose undo
## and redo swap each layer's chunks, the empty ones left out. Answers whether
## any layer was written.
func _commit_states(title: String, states: Dictionary[Variant, Dictionary]) -> bool:
    var bytes := 0
    for layer: Variant in states.keys():
        if (states[layer] as Dictionary).is_empty():
            states.erase(layer)
        else:
            bytes += SaHistory.bytes_of(states[layer])
    if states.is_empty():
        return false
    _written()
    var toggle := _toggle_flatten.bind(null, [] as Array[SaAttachedFilter], [] as Array[int], states)
    _commit(title, toggle, toggle, bytes, 0, UndoRedo.MERGE_DISABLE, states.values())
    return true


## Walks *recorded* once over every chunk of *layer*, each chunk bound with
## what *coverage* answers for it, or passed over when it answers null.
## *state* takes each chunk as it stood before the first pass that wrote it,
## so a second pass over the same chunk keeps the first snapshot.
func _bake(layer: SaLayer, recorded: SaPointPass, coverage: Callable, state: Dictionary[Vector2i, Variant]) -> void:
    var snapshot := func(grid_pos: Vector2i) -> SaChunk:
        var chunk: SaChunk = layer.chunks.get(grid_pos, null)
        if chunk == null or coverage.call(grid_pos) == null:
            return null
        if not state.has(grid_pos):
            state[grid_pos] = layer.duplicate_chunk(grid_pos)
        return chunk
    # The coverage at the chunk's density, so a layer at 2.0 is masked by the
    # pixel.
    var masks := SaFilterDensity.Masks.new()
    var bindings := func(grid_pos: Vector2i) -> Dictionary[int, Variant]:
        var bound: Dictionary[int, Variant] = {}
        bound.assign(recorded.buffers)
        var covered: SaTexture = coverage.call(grid_pos)
        bound[SaSelection.BINDING] = masks.at(covered, layer.chunks[grid_pos].pixel_size())
        return bound
    # The walk covers whole chunks, so every stop starts at the chunk's own
    # origin, which is what `SaFilterApply.apply_point` hands the pass as well.
    var push := func(grid_pos: Vector2i, _local: Rect2i, start: Vector2i) -> PackedFloat32Array:
        return recorded.push_for(start, grid_pos * SaChunk.SIZE)
    var walk := SaChunkWalk.new(SaCompute.new(recorded.shader), null, layer)
    walk.run(recorded.kernel, SaChunkWalk.reach_of(layer.chunks.keys()), snapshot, push, bindings)


## What a record's pass reads as its coverage at a chunk, the way the chain
## binds it: the record's own mask where it holds a chunk, and the texture that
## reads as one everywhere else. Null for no record is the one-shot's, which
## reads the document's selection and passes over a chunk it leaves out.
func _coverage_of(record: SaAttachedFilter) -> Callable:
    var selection := _document.selection
    if record == null:
        return func(grid_pos: Vector2i) -> SaTexture: return selection.texture_for(grid_pos)
    var everything := selection.everything()
    return func(grid_pos: Vector2i) -> SaTexture:
        if record.mask != null and record.mask.enabled:
            var coverage := record.mask.coverage(grid_pos)
            if coverage != null:
                return coverage
        return everything


## Whether *record* reads the whole node on *node* at twice the document's
## resolution, which the chain's gather does not offer: asked of the pass the
## chain builds, which it keeps on the record for the composite that follows.
## Refuses *record* on *node* under *title* when it reads the whole of a
## node finer than the document, and answers whether it did. The chain reads a
## layer at 2.0 at its own density, but a whole-node gather
## takes chunks at the document's side alone, so that one filter is refused
## there, as the Filter menu's one-shot is. Attach and move both ask, since a
## move lands the record on its new node as an attach would.
func _refused_finer(title: String, node: SaLayer, record: SaAttachedFilter) -> bool:
    if not _reads_whole_finer(node, record):
        return false
    SaProblems.refuse(
        title,
        tr("'%s' is at twice the resolution, and this filter reads the whole layer, which it does not offer yet.") % node.name
    )
    return true


## Refuses *record* on *node* under *title* when the node is an adjustment
## layer and the record's pass reads the whole node, and answers whether it
## did. The adjustment reads the backdrop around each chunk it writes, which a
## pass reading its neighbours needs, but not gathered whole, which waits for
## the named input's board.
func _refused_adjusting(title: String, node: SaLayer, record: SaAttachedFilter) -> bool:
    var refusals := SaLayerRefusals.new(_document)
    if refusals.sentence(SaLayerRefusals.Act.READ_WHOLE, node).is_empty():
        return false
    var chain := _chain()
    var built: Variant = chain.call("pass_for", _document, node, record) if chain != null else null
    var gather: SaNeighbourhoodPass = built if built is SaNeighbourhoodPass else null
    return gather != null and gather.whole() and refusals.refuses(title, SaLayerRefusals.Act.READ_WHOLE, node)


func _reads_whole_finer(node: SaLayer, record: SaAttachedFilter) -> bool:
    if node == null or node.resolution_scale == 1.0:
        return false
    var chain := _chain()
    var built: Variant = chain.call("pass_for", _document, node, record) if chain != null else null
    var gather: SaNeighbourhoodPass = built if built is SaNeighbourhoodPass else null
    return gather != null and gather.whole()


## The enabled records of *list* a flatten of *record* takes, in the order
## *chain* runs them, which of them finish being asked of its `finishes`: the
## plain ones, then the finishing ones, up to and including *record*.
static func _taken(chain: Object, list: Array[SaAttachedFilter], record: SaAttachedFilter) -> Array[SaAttachedFilter]:
    var at := list.find(record)
    var last: bool = chain != null and chain.call("finishes", record) == true
    var plain: Array[SaAttachedFilter] = []
    var after: Array[SaAttachedFilter] = []
    for index in list.size():
        var finishing: bool = chain != null and chain.call("finishes", list[index]) == true
        if not list[index].enabled or not (last and index <= at or not finishing and (last or index <= at)):
            continue
        if finishing:
            after.append(list[index])
        else:
            plain.append(list[index])
    plain.append_array(after)
    return plain


## The compositor's filter chain, or null in a host with no compositor. Held
## as an Object and asked through `call`, because the chain is private to its
## package and this file asks it for two things.
func _chain() -> Object:
    var compositor := _document.compositor
    return compositor.filter_chain if compositor != null else null


## VRAM a pixel state holds, which is what a step is charged with. Every entry
## a bake writes is a whole chunk.
static func _bytes_of(state: Dictionary[Vector2i, Variant]) -> int:
    var total := 0
    for kept: Variant in state.values():
        if kept is SaChunk:
            var chunk: SaChunk = kept
            total += chunk.byte_size()
    return total


## Both sides of a flatten's step. The pixels are a swap, which inverts itself,
## and the records go out when they are listed and back at their places when
## they are not, so one Callable is the undo and the redo.
func _toggle_flatten(
    node: SaLayer, records: Array[SaAttachedFilter], places: Array[int], states: Dictionary[Variant, Dictionary]
) -> void:
    if node != null and not is_instance_valid(node):
        return
    # Untyped, because a typed loop variable refuses a key that was freed.
    for key: Variant in states:
        if is_instance_valid(key):
            var layer: SaLayer = key
            _document.swap_pixels(layer, states[key])
    var list := filters_of(node)
    if not records.is_empty() and list.has(records[0]):
        for record in records:
            list.erase(record)
    else:
        for i in records.size():
            list.insert(mini(places[i], list.size()), records[i])
    _changed()


## One step on the document's history, *layer_bytes* being what a record the
## step keeps alive holds, charged the way a deleted layer is, and *merge* how
## it folds into the step before. *states* are the pixel states the step swaps,
## which the history hands `SaResidency` to move to RAM first past the budget.
func _commit(
    title: String,
    redo: Callable,
    undo: Callable,
    paint_bytes: int = 0,
    layer_bytes: int = 0,
    merge := UndoRedo.MERGE_DISABLE,
    states: Array = []
) -> void:
    _document.history.commit_pair(title, redo, undo, paint_bytes, layer_bytes, merge, states)


## Whether *node* is somewhere a record can hang: the root, or a layer of this
## document that is still alive.
func _holds(node: SaLayer) -> bool:
    return node == null or (is_instance_valid(node) and node.get_parent() == _document)


func _insert(node: SaLayer, record: SaAttachedFilter, at: int) -> void:
    if node != null and not is_instance_valid(node):
        return
    var list := filters_of(node)
    if list.has(record):
        return
    _changed_at(node, func() -> void: list.insert(mini(at, list.size()), record))


func _remove(node: SaLayer, record: SaAttachedFilter) -> void:
    if node != null and not is_instance_valid(node):
        return
    _changed_at(node, func() -> void: filters_of(node).erase(record))


func _carry(from: SaLayer, record: SaAttachedFilter, to: SaLayer, at: int) -> void:
    if (from != null and not is_instance_valid(from)) or (to != null and not is_instance_valid(to)):
        return
    if not filters_of(from).has(record):
        return
    filters_of(from).erase(record)
    var list := filters_of(to)
    list.insert(mini(at, list.size()), record)
    _changed()


func _move(node: SaLayer, record: SaAttachedFilter, to: int) -> void:
    if node != null and not is_instance_valid(node):
        return
    var list := filters_of(node)
    if not list.has(record):
        return
    list.erase(record)
    list.insert(mini(to, list.size()), record)
    _changed()


## Puts *values* on *record* with no step and redraws its node alone, for both
## sides of an Edit Filter step and for the edit window's preview.
func write(record: SaAttachedFilter, values: Dictionary) -> void:
    _redrawn(node_of(record), record.replace_parameters.bind(values))


func _apply_enabled(record: SaAttachedFilter, value: bool) -> void:
    record.enabled = value
    record.touch()
    _changed()


## What a flatten and a one-shot end on: `_changed`, whose cache update makes
## the announcement a pixel write needs, `document_changed`, which a layer's
## thumbnail redraws from. It emitted the signal a second time after it, which
## ran every listener twice in the frame Apply was pressed in.
## The undo and the redo announce it themselves, through the swap.
func _written() -> void:
    _changed()


## Makes *edit*, a record put on or taken off *node*, and redraws what the
## node draws, as an edit of its parameters does. Marking every chunk at no
## layer instead drew each of the nights file's 219 effect layers again over
## the three seconds after a mirror was attached to an empty layer. The
## root's records read the whole canvas and redraw it whole.
func _changed_at(node: SaLayer, edit: Callable) -> void:
    if node == null:
        edit.call()
        _changed()
        return
    _redrawn(node, edit)


## Makes *edit* on *node*'s records and redraws what the node draws alone, the
## root's whole canvas for a null *node*.
##
## The first enabled record on a pass-through group isolates it, and taking the
## last one off releases it, which changes the fold's walk and not only the
## chunks. `SaLayerFold.walk_of` reads neither the records nor the isolation,
## so the refold in `filter_moved` keeps the walk it had, the group expanded
## and the record in no step, until something else builds it. Such a write
## builds the walk at once in `_changed`, as `SaMaskOps._refresh` does for a
## group's mask.
func _redrawn(node: SaLayer, edit: Callable) -> void:
    var isolated := SaLayerStack.isolates(node)
    _document.filter_moved(node, edit)
    if node != null and is_instance_valid(node) and SaLayerStack.isolates(node) != isolated:
        _changed()


## What every other operation ends on. The whole document redraws, because a filter
## on a node changes every chunk that node composites to.
func _changed() -> void:
    _document.modified = true
    _document.invalidate_all_allocated_chunks()
    _document.update_caches()
