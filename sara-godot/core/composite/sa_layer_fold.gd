## The fold: what the compositor walks, and the caches it folds layers into.
##
## `SaLayerStack` answers questions about the layer tree and owns nothing. This
## is the rebuild, with the state it works on: the two stacks either side of
## the active layer, the scopes of the isolated groups around it, and every
## cache a run of layers was folded into. A class of its own rather than fields
## of `SaDocument` worked on by statics, so the document holds one fold, and
## `release()` is the one place a cache is freed.
##
## A cache is made at the document's schema the first time the fold needs it,
## and follows the document's depth at every rebuild, so a document loaded at
## another depth needs nothing of the loader but a `release()`.
##
## The caches are `SaLayer` nodes that are nobody's children, because they are
## never serialised, so an orphan left here is a leaked set of chunk textures.
## `release()` frees every one, and the document calls it from the one function
## that drops its contents.
class_name SaLayerFold
extends RefCounted

## The key of the mark a hidden layer leaves among the steps where, shown, it
## would part a run of plain Normal layers. The run is parted there all the
## same, so hiding a Multiply layer folds the layers either side of it into the
## caches they were folded into while it showed. Over is not associative once
## a cache rounds to the document's depth, so one cache for the run where two
## stood moved pixels the layer held no paint at by a rounding. A mark is no step, and the folds drop it.
const PARTS := "parts"

## Everything visible below the active layer, folded, whatever the modes.
var bottom_cache: SaLayer = null
## The first run of plain Normal layers above the active one. Later runs get
## caches of their own in `top_run_caches`.
var top_cache: SaLayer = null
var top_run_caches: Array[SaLayer] = []

## What the compositor walks, below and above the active layer, in order. Each
## entry is a Dictionary of `SaLayerStack.LAYER`, `MODE` and `OPACITY`, and the
## layer is a cache or a real layer: the compositor does not know which.
var bottom_stack: Array[Dictionary] = []
var top_stack: Array[Dictionary] = []

## The isolated groups the active layer sits inside, outermost first, each
## with its own bottom and top stacks around the next one in. Empty when the
## active layer is at the top level or inside pass-through groups only. The
## clip group the active layer or a group around it is the base of or is
## clipped in is a scope too, right inside the isolated group that holds it,
## as `SaLayerStack.BASE` says.
var active_scopes: Array[Dictionary] = []
## Caches for isolated groups and for runs inside them, by key, freed when a
## rebuild no longer asks for them.
var extra_caches: Dictionary[String, SaLayer] = {}
## Every mask and effect layer the last rebuild baked into a cache, and the
## nodes each cache baked.
var ledger: SaFoldLedger = SaFoldLedger.new()
## What the fold owes the document since an activation or a change of the
## stack put the fold off, and when it is paid.
var debt: SaFoldDebt = SaFoldDebt.new()
## The steps of every isolated group folded into a cache that holds a layer at
## 2.0 at any depth, by the group's instance id. The cache averaged the layer,
## so a display chunk's walk composites the group afresh from these, and the
## steps stay out of the run caches for the same reason.
var fine_groups: Dictionary[int, Array] = {}

# Held for the length of one `rebuild()` and dropped at its end, so the fold
# keeps no reference to the document between rebuilds.
var _document: SaDocument = null
var _compositor: SaCompositor = null
var _visible_rect: Rect2 = Rect2()
var _schema: Array[SaFieldSpec] = []
var _used: Dictionary[String, bool] = {}
## Every fold the last rebuild made, in the order it made them, which puts a
## group's cache before the cache that folds the group in. What `refold` reads
## the last steps of each cache from.
var _folded: Array[Folded] = []
## What the last build read the walk from: the active layer, and each layer's
## place, visibility, blend mode, opacity and clip. A refold that reads them
## the same keeps the walk as it stands.
var _built_from: Array = []
# Held for the length of one `refold()`: the folds of the build before it by
# the cache's instance id, the instance ids of what moved, the moved layers and
# every cache folded again since, and the grid positions where what a cache
# shows may differ from the last build.
var _refolding := false
var _before: Dictionary[int, Folded] = {}
var _moved: Dictionary[int, bool] = {}
var _changed: Dictionary[Vector2i, bool] = {}
# The clip scope the last `_atoms` call met around its split, or empty.
var _clip_scope: Dictionary = {}
# What each layer composites, its descriptor's answer read once a build.
var _kinds := SaLayerTypeRegistry.Reading.new()
# The folds a build over frames put off, in the order it made them, and
# whether the build running now puts them off.
var _unpaid: Array[Unpaid] = []
var _putting_off := false


## One fold of a rebuild: the cache and the steps composited into it, in order.
class Folded:
    extends RefCounted

    var cache: SaLayer = null
    var steps: Array[Dictionary] = []

    func _init(into: SaLayer, folded: Array[Dictionary]) -> void:
        cache = into
        steps = folded


## A fold a build over frames put off: the fold, the chunks it folds into once
## begun, and how many of its steps are folded.
class Unpaid:
    extends RefCounted

    var fold: Folded = null
    var spots: Array[Vector2i] = []
    var done := 0

    func _init(put_off: Folded) -> void:
        fold = put_off


## Rebuilds the stacks and scopes of *document* for *visible_rect*, with
## *compositor* doing the folding. The caches are reused, and their chunks
## outside what the visible layers hold are dropped: a cache is allocated where
## paint is, never over the canvas.
func rebuild(document: SaDocument, compositor: SaCompositor, visible_rect: Rect2) -> void:
    _visible_rect = visible_rect
    _build(document, compositor)


## Builds the walk as [method rebuild] does and folds none of its caches,
## which [method pay] folds after it, a few at a time. Until the last is paid
## the walk names caches that do not hold what it says, so whatever draws pays
## the rest first, as `SaFoldDebt` does.
func rebuild_unpaid(document: SaDocument, compositor: SaCompositor, visible_rect: Rect2) -> void:
    _visible_rect = visible_rect
    _putting_off = true
    _build(document, compositor)
    _putting_off = false


## Whether a build over frames left a fold unpaid.
func is_unpaid() -> bool:
    return not _unpaid.is_empty()


## Folds what [method rebuild_unpaid] put off, in the order it put it off,
## which folds a group's cache before the cache that folds the group in. Folds
## about *steps* of its steps, a layer or a group each, or all that is left
## when it is nought. A cache is begun once, its chunks dropped and cleared as
## a fold does, and takes its steps over as many calls as they need. A cache
## with a step that reads around its chunk is folded whole in one call, since
## that step folds over the ring the others leave.
func pay(document: SaDocument, compositor: SaCompositor, steps: int = 0) -> void:
    _document = document
    _compositor = compositor
    var left := steps
    while not _unpaid.is_empty() and (steps <= 0 or left > 0):
        var each: Unpaid = _unpaid[0]
        var cache := each.fold.cache
        var folded := each.fold.steps
        if not is_instance_valid(cache):
            _unpaid.pop_front()
            continue
        if each.done == 0:
            for atom in folded:
                SaLayerStack.layer_of(atom).resolve_pending()
            if folded.any(_reads_around):
                _fold_over(cache, folded, {})
                _unpaid.pop_front()
                left -= folded.size()
                continue
            each.spots = _cleared(cache, _begun(cache, folded))
        var to := folded.size() if steps <= 0 else mini(folded.size(), each.done + left)
        _fold_steps(cache, folded, each.spots, each.done, to)
        left -= to - each.done
        each.done = to
        if each.done == folded.size():
            _unpaid.pop_front()
    _document = null
    _compositor = null


## Where *cache* needs a chunk to hold *folded*, its other chunks dropped, as
## a whole fold begins.
func _begun(cache: SaLayer, folded: Array[Dictionary]) -> Array[Vector2i]:
    var needed := _needed(folded)
    for grid_pos: Vector2i in cache.chunks.keys():
        if not needed.has(grid_pos):
            cache.set_chunk(grid_pos, null)
    var spots: Array[Vector2i] = []
    spots.assign(needed.keys())
    return spots


## The rebuild at the last one's visible rectangle, which `refold` narrows by
## the folds it skips.
func _build(document: SaDocument, compositor: SaCompositor) -> void:
    _document = document
    _compositor = compositor
    _kinds = SaLayerTypeRegistry.Reading.new()
    _built_from = walk_of(document)
    debt.paid()
    _unpaid = []
    _schema = SaFieldSpec.schema_for_space(document.color_space)
    _used = {}
    ledger.forget()
    _folded = []
    fine_groups = {}
    if bottom_cache == null:
        bottom_cache = _new_cache("BottomCache")
    if top_cache == null:
        top_cache = _new_cache("TopCache")
    _follow_depth(bottom_cache)
    _follow_depth(top_cache)

    # The isolated groups around the active layer, outermost first. Each one is
    # a scope, and the top level splits at the outermost of them.
    # A lifted active layer is drawn after the top level's last layer whatever
    # holds it, so no group around it is a scope.
    var path: Array[SaLayer] = []
    var active := document.active_layer
    var group: SaLayer = null if SaBackdropLayer.lifts(active) else SaLayerStack.parent_of(active)
    var guard := 0
    while group != null and guard < 64:
        if SaLayerStack.isolates(group) or _clips_inside(active, group):
            path.push_front(group)
        group = SaLayerStack.parent_of(group)
        guard += 1

    var root_split: SaLayer = path[0] if not path.is_empty() else document.active_layer
    _clip_scope = {}
    var root_atoms := _atoms(null, 1.0, root_split)
    root_atoms.append_array(_lifted_atoms(root_split))
    var halves := _split(root_atoms)
    var scopes: Array[Dictionary] = []
    if not _clip_scope.is_empty():
        scopes.append(_clip_scope)
    var root_below: Array[Dictionary] = halves[0]
    var root_above: Array[Dictionary] = halves[1]
    bottom_stack = _fold_below(root_below, bottom_cache, "below")
    var root_runs := _fold_above(root_above, _run_cache)
    top_stack = root_runs[0]
    for i in range(root_runs[1], 1 + top_run_caches.size()):
        _run_cache(i).release_chunks()

    for i in path.size():
        var scope_group := path[i]
        var next_split: SaLayer = path[i + 1] if i + 1 < path.size() else document.active_layer
        _clip_scope = {}
        var inner := _split(_atoms(scope_group, 1.0, next_split))
        var clip_scope := _clip_scope
        var inner_below: Array[Dictionary] = inner[0]
        var inner_above: Array[Dictionary] = inner[1]
        var below_cache := _extra_cache("scope%d/bottom" % i)
        var runs := _fold_above(inner_above, func(index: int) -> SaLayer: return _extra_cache("scope%d/run%d" % [i, index]))
        (
            scopes
            . append(
                {
                    SaLayerStack.GROUP: scope_group,
                    SaLayerStack.BOTTOM: _fold_below(inner_below, below_cache, "scope%d/below" % i),
                    SaLayerStack.TOP: runs[0],
                }
            )
        )
        if not clip_scope.is_empty():
            scopes.append(clip_scope)
    active_scopes = scopes
    _clip_scope = {}

    # A cache no group and no scope asked for this time holds chunks nothing
    # reads, and a group that is gone must not keep a chunk set alive.
    for key: String in extra_caches.keys():
        if not _used.has(key):
            var stale: SaLayer = extra_caches[key]
            extra_caches.erase(key)
            stale.free()

    _document = null
    _compositor = null
    _used = {}


## Frees every cache and empties the walk. The fold is usable again after it,
## and makes its caches afresh at the next rebuild.
func release() -> void:
    for cache in caches():
        if is_instance_valid(cache):
            cache.free()
    bottom_cache = null
    top_cache = null
    top_run_caches = []
    extra_caches = {}
    ledger.forget()
    _folded = []
    _unpaid = []
    _built_from = []
    fine_groups = {}
    bottom_stack = []
    top_stack = []
    active_scopes = []
    debt.paid()


## Every cache the fold holds, made or not.
func caches() -> Array[SaLayer]:
    var held: Array[SaLayer] = [bottom_cache, top_cache]
    held.append_array(top_run_caches)
    held.append_array(extra_caches.values())
    return held


## Whether *document*'s walk reads as the last build read it, the active layer
## left out when *any_active*, which is a walk that draws the same picture.
func reads_as_built(document: SaDocument, any_active: bool = false) -> bool:
    var walk := walk_of(document)
    return walk.slice(1) == _built_from.slice(1) if any_active else walk == _built_from


## Folds again, over *positions*, every cache *node* moved in, and answers the
## grid positions past *positions* where what a cache shows may have changed,
## as keys, since the caller marked *positions* dirty with their halo already
## and marking them again would grow the halo twice. *node* moved over
## *positions*, a grid position in it as a key: its paint, an undo's or a
## fill's, its mask, its attached filters' parameters, its blend mode, its
## opacity or its visibility. What a group holds and what is clipped to *node*
## moved with it, as `SaLayerStack.drawn_by` says.
##
## When the walk reads as the last build read it, which a write of paint, a
## mask or a filter's parameters leaves it, the walk stands, and each cache the
## ledger says baked what moved folds again over the positions. Otherwise the
## walk is built again, and a cache is folded again over the positions where
## its other steps are those of the last build and it holds a moved one,
## whole where its other steps changed, because a step left or joined its run,
## and not at all where nothing in it moved.
##
## A cache with an adjustment layer among its steps that reads around its
## chunk is folded again whole, because that step reads the backdrop in the
## ring around each chunk, and the ring past *positions* holds the cache's
## finished picture rather than the backdrop. A cache folded again counts as
## moved for the caches folded after it, which puts the cache of a group into
## the cache that baked the group.
func refold(
    document: SaDocument, compositor: SaCompositor, node: SaLayer, positions: Dictionary[Vector2i, bool]
) -> Dictionary[Vector2i, bool]:
    var changed: Dictionary[Vector2i, bool] = {}
    if node == null:
        return changed
    # A refold reads every cache as folded, so what a build over frames put
    # off is paid first.
    pay(document, compositor)
    _moved = {node.get_instance_id(): true}
    for child in document.get_children():
        var layer := child as SaLayer
        if layer != null and (SaLayerStack.is_inside(layer, node) or SaLayerStack.clip_base(document, layer) == node):
            _moved[layer.get_instance_id()] = true
    _changed = positions.duplicate()
    if walk_of(document) == _built_from:
        _document = document
        _compositor = compositor
        for each in _folded:
            if is_instance_valid(each.cache) and not _changed.is_empty() and ledger.bakes(each.cache, _moved):
                _refold_one(each.cache, each.steps, _changed)
        _document = null
        _compositor = null
    else:
        _before = {}
        for each in _folded:
            if is_instance_valid(each.cache):
                _before[each.cache.get_instance_id()] = each
        _refolding = true
        _build(document, compositor)
        _refolding = false
    for grid_pos: Vector2i in _changed:
        if not positions.has(grid_pos):
            changed[grid_pos] = true
    _before = {}
    _moved = {}
    _changed = {}
    return changed


## Builds the walk again after a delete, an add or a drop that moved *moved*
## alone, layers by instance id with both split layers among them, and folds
## each cache over *positions* as [method refold] does once the walk moved.
## `SaFoldDebt` reads what moved, so the fold is of the layer's chunks.
func restack(
    document: SaDocument, compositor: SaCompositor, moved: Dictionary[int, bool], positions: Dictionary[Vector2i, bool]
) -> void:
    # Every cache is read as folded, so what a build over frames put off is
    # paid first, as in a refold.
    pay(document, compositor)
    _moved = moved.duplicate()
    _changed = positions.duplicate()
    _before = {}
    for each in _folded:
        if is_instance_valid(each.cache):
            _before[each.cache.get_instance_id()] = each
    # Through [method rebuild], since what counts the fold's builds counts it
    # there.
    _refolding = true
    rebuild(document, compositor, _visible_rect)
    _refolding = false
    _before = {}
    _moved = {}
    _changed = {}


## Folds *steps* into *cache* again over *within*, or whole when it is empty,
## and counts the cache as moved and what it wrote as changed.
func _refold_one(cache: SaLayer, steps: Array[Dictionary], within: Dictionary[Vector2i, bool]) -> void:
    # The rebuild resolves every layer before it folds, for the reason
    # `SaDocument.update_caches` gives.
    for atom in steps:
        SaLayerStack.layer_of(atom).resolve_pending()
    _changed.merge(_fold_over(cache, steps, within))
    _moved[cache.get_instance_id()] = true


## What a build reads the walk from in *document*, which `_built_from` keeps,
## each layer by its instance id so that a layer freed since compares as gone:
## the active layer's, then for each layer its own, its group's, and whether it
## shows, its blend mode, its opacity, its clip and Affect all.
static func walk_of(document: SaDocument) -> Array:
    var read: Array = [_id_of(document.active_layer)]
    for child in document.get_children():
        var layer := child as SaLayer
        if layer != null:
            var place := [_id_of(layer), _id_of(SaLayerStack.parent_of(layer)), layer.visible]
            read.append(place + [layer.get_blend_mode_name(), layer.opacity, layer.clip_to_below, layer.affects_all])
    return read


static func _id_of(layer: SaLayer) -> int:
    return layer.get_instance_id() if layer != null else 0


## The steps of *steps* that are not of what moved, which a refold folds the
## same as the last build did. A step whose layer is gone stands as one that
## no build makes, so a cache that held it is folded whole.
func _kept(steps: Array[Dictionary]) -> Array[Dictionary]:
    var kept: Array[Dictionary] = []
    for atom in steps:
        var gone := false
        var moved := false
        for part in SaLayerStack.parts_of(atom):
            var layer: Variant = part[SaLayerStack.LAYER]
            var node: Variant = part.get(SaLayerStack.NODE, layer)
            if not is_instance_valid(layer) or not is_instance_valid(node):
                gone = true
            elif _moved.has(_id_of(SaLayerStack.layer_of(part))) or _moved.has(_id_of(SaLayerStack.node_of(part))):
                moved = true
        if gone:
            kept.append({})
        elif not moved:
            kept.append(atom)
    return kept


## Whether *steps* hold a step of what moved.
func _holds_moved(steps: Array[Dictionary]) -> bool:
    return _kept(steps).size() != steps.size()


## The ordered steps for the members of *scope_group* (null for the top level),
## groups expanded: a pass-through group's members in place with its opacity
## multiplied in, an isolated group folded into its cache as one step, and a
## clipping base with the layers clipped to it as one step. The layer
## *split_at*, or the pass-through group holding it, leaves a marker where it
## sits instead of a step.
func _atoms(scope_group: SaLayer, opacity_mult: float, split_at: SaLayer) -> Array[Dictionary]:
    var atoms: Array[Dictionary] = []
    var siblings := SaLayerStack.members(_document, scope_group)
    for layer in siblings:
        # A lifted layer is drawn after the top level's last layer instead.
        if SaBackdropLayer.lifts(layer):
            continue
        # A clipped layer is a step of its base's, and one clipped to a layer with
        # no pixels of its own shows nothing, both read off one list.
        var base := SaLayerStack.base_among(siblings, siblings.find(layer))
        if base != null and not _kinds.reads_below(base):
            continue
        var run := SaLayerStack.run_among(siblings, siblings.find(layer))
        if not run.is_empty():
            _clip_run(atoms, layer, run, opacity_mult, split_at)
            continue
        if _splits(layer, split_at):
            atoms.append(_marker(layer))
            continue
        if not SaLayerStack.shows(_document, layer):
            if base == null and _would_part(layer):
                var parting := _step(layer, opacity_mult)
                parting[PARTS] = true
                atoms.append(parting)
            continue
        if _kinds.nests(layer) and not SaLayerStack.isolates(layer):
            atoms.append_array(_atoms(layer, layer.opacity * opacity_mult, split_at))
        else:
            atoms.append(_step(layer, opacity_mult))
    return atoms


## The steps of every lifted adjustment layer, `SaBackdropLayer`'s, the lowest
## first, each at its opacity times every group's around it, and a marker for
## *split_at* when it is one of them. A layer that does not show, or sits in a
## group that does not, is no step.
func _lifted_atoms(split_at: SaLayer) -> Array[Dictionary]:
    var atoms: Array[Dictionary] = []
    for layer in SaBackdropLayer.lifted(_document):
        if layer == split_at:
            atoms.append(_marker(layer))
        elif SaLayerStack.shows(_document, layer):
            atoms.append(_step(layer, SaBackdropLayer.carried(layer)))
    return atoms


## Whether *layer* is the split *split_at* names. A group that is active is
## expanded like any other: nothing paints on it, so there is no live tier to
## split around, and a marker here would leave its members on neither side. An
## isolated group around the active layer is the next scope in, and it splits:
## folded here as well, it would be composited twice, once from its cache and
## once as the scope.
func _splits(layer: SaLayer, split_at: SaLayer) -> bool:
    return layer == split_at and not (_kinds.nests(layer) and layer == _document.active_layer)


## Whether *layer*, a layer of paint and not a group, would part a run of plain
## Normal layers were it shown. A layer at 2.0 never folds, so it is left out.
func _would_part(layer: SaLayer) -> bool:
    return not _kinds.nests(layer) and layer.resolution_scale <= 1.0 and not _folds_over_transparent(_step(layer, 1.0))


## *atoms* less the hidden layers' marks, for a fold that composites its steps
## in order onto one cache, where no run is parted.
static func _drawn(atoms: Array[Dictionary]) -> Array[Dictionary]:
    return atoms.filter(func(atom: Dictionary) -> bool: return not atom.has(PARTS))


static func _marker(layer: SaLayer) -> Dictionary[String, Variant]:
    return {SaLayerStack.LAYER: layer, SaLayerStack.SPLIT: true}


## The step of *layer*, a layer or an isolated group, at its opacity times
## *opacity_mult*. A group's step composites its cache and stands for the
## group, so the group's filters run over the group's composite.
func _step(layer: SaLayer, opacity_mult: float) -> Dictionary[String, Variant]:
    var mode := layer.get_blend_mode_name()
    if not SaLayerStack.isolates(layer):
        return SaLayerStack.entry(SaLiveTransform.paint_of(layer), mode, layer.opacity * opacity_mult, layer)
    var cache := _extra_cache("group/%d" % layer.get_instance_id())
    # The cache stands for the group's composite, so it hides what the group's
    # mask hides, and every site that masks a layer's chunk masks this one
    # without knowing it is a group's.
    cache.mask = layer.mask
    var steps := _drawn(_atoms(layer, 1.0, null))
    if steps.any(_is_fine):
        fine_groups[layer.get_instance_id()] = steps
    _fold(cache, steps)
    return SaLayerStack.entry(cache, mode, layer.opacity * opacity_mult, layer)


## Appends to *atoms* the step of *base* and *run*, the layers clipped to it,
## as one group: the base's mode, its opacity times *opacity_mult*, and each
## clipped layer at its own, since the group carries the pass-through groups'.
## Where *split_at* is the base or one of the run, the group is a scope around
## it instead, kept in `_clip_scope` for the rebuild, and a marker stands in
## its place. A hidden base hides the run, and a hidden active layer in it
## leaves the rest as one step, since a scope draws only around a layer that
## shows.
func _clip_run(atoms: Array[Dictionary], base: SaLayer, run: Array[SaLayer], opacity_mult: float, split_at: SaLayer) -> void:
    var at_base := _splits(base, split_at)
    if not SaLayerStack.shows(_document, base):
        if at_base or run.any(func(layer: SaLayer) -> bool: return _holds_split(layer, split_at)):
            atoms.append(_marker(split_at))
        return
    var base_entry := _step(base, opacity_mult)
    var steps := _clipped_steps(run, split_at)
    var splits := at_base or steps.any(func(step: Dictionary) -> bool: return step.has(SaLayerStack.SPLIT))
    var halves := _split(steps)
    var below: Array[Dictionary] = []
    var above: Array[Dictionary] = steps
    if not at_base:
        below = halves[0]
        above = halves[1]
    var clipped: Array[Dictionary] = []
    clipped.append_array(below)
    clipped.append_array(above)
    var scoped := splits and SaLayerStack.shows(_document, split_at)
    if scoped and not (at_base and clipped.is_empty()):
        _clip_scope = {
            SaLayerStack.GROUP: base,
            SaLayerStack.BASE: {} if at_base else SaLayerStack.base_step(base_entry),
            SaLayerStack.BOTTOM: below,
            SaLayerStack.TOP: above,
        }
        atoms.append(_marker(split_at))
        return
    if at_base:
        atoms.append(_marker(split_at))
        return
    var mode := SaLayerStack.mode_of(base_entry)
    var opacity := SaLayerStack.opacity_of(base_entry)
    atoms.append(base_entry if clipped.is_empty() else SaLayerStack.clip_group(base_entry, mode, opacity, clipped))
    if splits:
        atoms.append(_marker(split_at))


## The steps of *run*, the layers clipped to one base, each at its own opacity
## and a marker where *split_at* sits. A pass-through group in the run has no
## composite of its own, so its members lie on the base's plate one by one with
## its opacity multiplied in, each by its own mode, as they would lie on what
## is under the group were it not clipped.
func _clipped_steps(run: Array[SaLayer], split_at: SaLayer) -> Array[Dictionary]:
    var steps: Array[Dictionary] = []
    for layer in run:
        if _splits(layer, split_at):
            steps.append(_marker(layer))
        elif not SaLayerStack.shows(_document, layer):
            if _holds_split(layer, split_at):
                steps.append(_marker(split_at))
        elif _kinds.nests(layer) and not SaLayerStack.isolates(layer):
            steps.append_array(_drawn(_atoms(layer, layer.opacity, split_at)))
        else:
            steps.append(_step(layer, 1.0))
    return steps


## Whether *group*, a clipped pass-through group around *active*, holds a
## clip of its own on the way down to *active*: *active* or a group between
## them clipped to a layer or a clipping base. Only one clip scope stands at a
## level, so such a group is a scope of its own while the painter works inside
## it, and its members composite over transparent there and not on the plate
## until another layer is active.
func _clips_inside(active: SaLayer, group: SaLayer) -> bool:
    if not group.clip_to_below or SaLayerStack.isolates(group):
        return false
    var at := active
    var guard := 0
    while at != null and at != group and guard < 64:
        if SaLayerStack.clip_base(_document, at) != null or not SaLayerStack.clipped_run(_document, at).is_empty():
            return true
        at = SaLayerStack.parent_of(at)
        guard += 1
    return false


## Whether *layer* is *split_at* or holds it, so a hidden clipping base leaves
## the marker its run would have.
func _holds_split(layer: SaLayer, split_at: SaLayer) -> bool:
    return _splits(layer, split_at) or (split_at != null and _kinds.nests(layer) and SaLayerStack.is_inside(split_at, layer))


## The steps below the marker and the steps above it. Without a marker
## everything is below, which is a document with nothing active.
static func _split(atoms: Array[Dictionary]) -> Array:
    var below: Array[Dictionary] = []
    var above: Array[Dictionary] = []
    var passed := false
    for atom in atoms:
        if atom.has(SaLayerStack.SPLIT):
            passed = true
            continue
        if passed:
            above.append(atom)
        else:
            below.append(atom)
    return [below, above]


## Everything below the active layer into *cache*, whatever the modes, up to
## the first layer that stores nothing. That layer never folds, because a
## cache holds chunks only where its layers do and a background covers the
## document: it stays a step of its own, and past it a run of plain Normal
## layers folds and any other step stays its own, as above the active layer.
## Each run of two or more folds into a cache of its own, the first into
## *cache* and the rest into extra caches. An effect layer is a step of its
## own too, because its chunks move whenever its input does and a cache would
## hold last refresh's.
func _fold_below(below: Array[Dictionary], cache: SaLayer, prefix: String) -> Array[Dictionary]:
    # A layer at 2.0 never folds either, so the detail view reads it and not a
    # cache that averaged it, and what is above it folds as
    # above the active layer does, over what is drawn by then.
    var fine := below.find_custom(_is_fine)
    if fine >= 0:
        var split := _fold_below(below.slice(0, fine), cache, prefix)
        split.append(below[fine])
        var cache_for := func(index: int) -> SaLayer: return _extra_cache("%s/fine%d" % [prefix, index])
        var folded: Array[Dictionary] = _fold_above(below.slice(fine + 1), cache_for)[0]
        split.append_array(folded)
        return split
    # An adjustment layer folds with its run only when the run starts at the
    # bottom of the scope, so the cache chunk under it is its backdrop. Past a
    # layer that stores nothing it is a step of its own, over what is drawn
    # by then, and what is above it folds as it does above the active layer.
    var adjusting := SaBackdropLayer.first_past_a_step(below)
    if adjusting >= 0:
        var parted := _fold_below(below.slice(0, adjusting), cache, prefix)
        parted.append(below[adjusting])
        var later := func(index: int) -> SaLayer: return _extra_cache("%s/adjusted%d" % [prefix, index])
        var above: Array[Dictionary] = _fold_above(below.slice(adjusting + 1), later)[0]
        parted.append_array(above)
        return parted
    # Only the first run starts at the bottom of the scope, over nothing, which
    # is the transparent a cache starts from. A run past a layer that stores
    # nothing has that layer under it, and a cache folded over transparent and
    # laid Normal holds it only for plain Normal layers. A Multiply layer folded
    # there multiplied nothing and covered the paper, so past that layer a step
    # that blends with its backdrop stays a step of its own, as above the
    # active layer, and the composite is the same whichever layer is active.
    var stack: Array[Dictionary] = []
    var run: Array[Dictionary] = []
    var caches_used := 0
    var stepped := false
    for atom in below:
        if atom.has(PARTS):
            if stepped:
                caches_used = _flush_below(stack, run, caches_used, cache, prefix)
                run = []
            continue
        var stores_nothing := _kinds.stores_nothing(SaLayerStack.layer_of(atom))
        if stores_nothing or (stepped and not _folds_over_transparent(atom)):
            caches_used = _flush_below(stack, run, caches_used, cache, prefix)
            run = []
            stack.append(atom)
            stepped = true
            continue
        run.append(atom)
    caches_used = _flush_below(stack, run, caches_used, cache, prefix)
    if caches_used == 0:
        cache.release_chunks()
    return stack


## Appends what *run* becomes below the active layer, and answers how many
## caches are in use: *cache* for the first run of two or more, an extra
## cache under *prefix* for each later one.
func _flush_below(stack: Array[Dictionary], run: Array[Dictionary], caches_used: int, cache: SaLayer, prefix: String) -> int:
    if run.is_empty():
        return caches_used
    if run.size() == 1:
        stack.append(run[0])
        return caches_used
    var target := cache
    if caches_used > 0:
        target = _extra_cache("%s/run%d" % [prefix, caches_used])
    _fold(target, run)
    stack.append(SaLayerStack.entry(target, SaLayer.BLEND_MODE.NORMAL, 1.0))
    return caches_used + 1


## The steps above, with runs of plain Normal folded through *cache_for*, and
## how many run caches were used. What is clipped to the active layer is a
## clip scope of its own and never reaches here.
func _fold_above(above: Array[Dictionary], cache_for: Callable) -> Array:
    var stack: Array[Dictionary] = []
    var run: Array[Dictionary] = []
    var runs_used := 0
    for atom in above:
        if atom.has(PARTS):
            runs_used = _flush_run(stack, run, runs_used, cache_for)
            run = []
            continue
        if _folds_over_transparent(atom):
            run.append(atom)
            continue
        runs_used = _flush_run(stack, run, runs_used, cache_for)
        run = []
        stack.append(atom)
    runs_used = _flush_run(stack, run, runs_used, cache_for)
    return [stack, runs_used]


## Whether the step *atom* composites the same folded into a cache over
## transparent and the cache laid Normal over its backdrop as laid over that
## backdrop itself: a plain Normal layer, which reads nothing of what is under
## it, or a clipping base and its run laid Normal as one group.
func _folds_over_transparent(atom: Dictionary) -> bool:
    var normal: bool = atom[SaLayerStack.MODE] == SaLayer.BLEND_MODE.NORMAL
    return normal and _kinds.reads_own(SaLayerStack.layer_of(atom)) and not _is_fine(atom)


## Whether the step is a layer stored at more than the document's resolution,
## or the cache of a group that holds one, or a clipping base's with such a
## step among its parts.
func _is_fine(atom: Dictionary) -> bool:
    for part in SaLayerStack.parts_of(atom):
        var layer := SaLayerStack.layer_of(part)
        var node := SaLayerStack.node_of(part, layer)
        if layer.resolution_scale > 1.0 or fine_groups.has(node.get_instance_id()):
            return true
    return false


## Appends what *run* becomes, and answers how many run caches are in use.
func _flush_run(stack: Array[Dictionary], run: Array[Dictionary], runs_used: int, cache_for: Callable) -> int:
    if run.is_empty():
        return runs_used
    if run.size() == 1:
        stack.append(run[0])
        return runs_used
    var cache: SaLayer = cache_for.call(runs_used)
    _fold(cache, run)
    stack.append(SaLayerStack.entry(cache, SaLayer.BLEND_MODE.NORMAL, 1.0))
    return runs_used + 1


## The cache for the *index*th run of Normal layers above the active one at
## the top level. The first is `top_cache`, later ones are made on demand.
func _run_cache(index: int) -> SaLayer:
    if index == 0:
        return top_cache
    while top_run_caches.size() < index:
        top_run_caches.append(_new_cache("TopRunCache%d" % top_run_caches.size()))
    var cache := top_run_caches[index - 1]
    _follow_depth(cache)
    return cache


## A cache for an isolated group, a scope, or a run inside one, by key. Made
## on demand, kept between rebuilds, and recorded as used so the rebuild can
## free the ones it did not ask for.
func _extra_cache(key: String) -> SaLayer:
    _used[key] = true
    var cache: SaLayer = extra_caches.get(key, null)
    if cache == null or not is_instance_valid(cache):
        cache = _new_cache("Cache_" + key.replace("/", "_"))
        extra_caches[key] = cache
    _follow_depth(cache)
    return cache


func _new_cache(cache_name: String) -> SaLayer:
    var cache := SaLayer.new()
    cache.name = cache_name
    cache.schema = _schema
    return cache


## A cache left over from a document at another depth would be the one
## mismatched binding in the composite, so its chunks go with the old schema.
func _follow_depth(cache: SaLayer) -> void:
    if cache.schema.is_empty() or cache.schema[0].format != _schema[0].format:
        cache.release_chunks()
        cache.schema = _schema


## Composites *folded* in order into *cache*, over transparent, where any of
## them holds a chunk inside the visible rectangle. Cache chunks nowhere in
## that set are dropped, so the cache is exactly as sparse as the layers it
## stands for.
##
## In a refold the cache is folded whole only when its other steps changed, over
## what moved when it holds a step of that, and otherwise not at all.
func _fold(cache: SaLayer, folded: Array[Dictionary]) -> void:
    _folded.append(Folded.new(cache, folded))
    for atom in folded:
        ledger.note(atom, cache)
    if not _refolding:
        if _putting_off:
            _unpaid.append(Unpaid.new(_folded[_folded.size() - 1]))
        else:
            _fold_over(cache, folded, {})
        return
    var before: Folded = _before.get(cache.get_instance_id(), null)
    if before != null and _tops_up(cache, before.steps, folded):
        return
    if before == null or _kept(before.steps) != _kept(folded):
        _refold_one(cache, folded, {})
    elif not _changed.is_empty() and (_holds_moved(before.steps) or _holds_moved(folded)):
        # A step of what moved that joined or left the cache shows wherever it holds paint.
        var crossed: Array[Dictionary] = []
        crossed.assign((before.steps + folded).filter(func(a: Dictionary) -> bool: return (a in before.steps) != (a in folded)))
        _refold_one(cache, folded, _changed.merged(_needed(crossed)))


## Folds into *cache* only the steps *folded* has past *built*, its last
## steps, when those stand unchanged under them, which folds what a whole fold
## would byte for byte. A chunk the cache lacks starts transparent, since no
## step under holds paint there. Answers whether it folded.
func _tops_up(cache: SaLayer, built: Array[Dictionary], folded: Array[Dictionary]) -> bool:
    if built.is_empty() or folded.size() <= built.size() or folded.slice(0, built.size()) != built:
        return false
    if folded.any(_reads_around):
        return false
    var added: Array[Dictionary] = folded.slice(built.size())
    for atom in added:
        SaLayerStack.layer_of(atom).resolve_pending()
    var spots: Array[Vector2i] = []
    for grid_pos: Vector2i in _needed(added):
        if not cache.chunks.has(grid_pos):
            cache.get_or_create_chunk(grid_pos).clear(Color(0, 0, 0, 0))
        spots.append(grid_pos)
        _changed[grid_pos] = true
    _fold_steps(cache, folded, spots, built.size(), folded.size())
    _moved[cache.get_instance_id()] = true
    return true


## Composites *folded* into *cache* where *within* holds a grid position as a
## key, or everywhere when *within* is empty, and drops a cache chunk there
## that no step needs any more. Answers the grid positions it wrote or
## dropped, as keys.
func _fold_over(cache: SaLayer, folded: Array[Dictionary], within: Dictionary[Vector2i, bool]) -> Dictionary[Vector2i, bool]:
    var whole := within.is_empty() or folded.any(_reads_around)
    var touched: Dictionary[Vector2i, bool] = within.duplicate()
    if whole:
        for grid_pos: Vector2i in cache.chunks:
            touched[grid_pos] = true
    var needed := _needed(folded)
    for grid_pos: Vector2i in cache.chunks.keys():
        if not needed.has(grid_pos) and (whole or within.has(grid_pos)):
            cache.set_chunk(grid_pos, null)

    var drawer := SaFoldStep.new(_compositor, _document)
    if not _compositor.adjustment.fold_around(_compositor, cache, folded, needed, _visible_rect, drawer.chunk_step):
        var spots: Array[Vector2i] = []
        for grid_pos: Vector2i in needed:
            if whole or within.has(grid_pos):
                spots.append(grid_pos)
        _fold_steps(cache, folded, _cleared(cache, spots), 0, folded.size())
    # The fold around the chunks grows *needed* by the ring it wrote.
    if whole:
        touched.merge(needed)
    return touched


## Where any step of *folded* holds a chunk inside the visible rectangle, as
## keys, which is where its cache needs one.
func _needed(folded: Array[Dictionary]) -> Dictionary[Vector2i, bool]:
    var needed: Dictionary[Vector2i, bool] = {}
    for atom in folded:
        var base := SaLayerStack.layer_of(atom)
        var parts := SaLayerStack.parts_of(atom)
        for index in parts.size():
            var part := parts[index]
            var layer := SaLayerStack.layer_of(part)
            # A step whose filters gather a halo shows in the ring around its
            # chunks too, so the cache holds a chunk there.
            var positions := _compositor.filter_chain.walked(SaLayerStack.node_of(part, layer), SaTyped.positions(layer.chunks))
            for grid_pos: Vector2i in positions:
                # A clipped chunk over no base chunk shows nothing, so it needs
                # no cache chunk either.
                if index > 0 and not SaLayerStack.clip_reaches(base, grid_pos):
                    continue
                if _chunk_rect(grid_pos).intersects(_visible_rect):
                    needed[grid_pos] = true
    return needed


## The chunks of *cache* at *spots*, made where missing and cleared to
## transparent, which a fold starts from.
static func _cleared(cache: SaLayer, spots: Array[Vector2i]) -> Array[Vector2i]:
    for grid_pos in spots:
        cache.get_or_create_chunk(grid_pos).clear(Color(0, 0, 0, 0))
    return spots


## Composites the steps of *folded* from *from* up to *to* into *cache* at
## *spots*, over what its chunks hold, `SaFoldStep`'s.
func _fold_steps(cache: SaLayer, folded: Array[Dictionary], spots: Array[Vector2i], from: int, to: int) -> void:
    SaFoldStep.new(_compositor, _document).steps(cache, folded, spots, from, to)


## Whether the step *atom* is an adjustment layer that reads around its chunk,
## which `SaBackdropLayer.fold_around` folds over the ring as well.
func _reads_around(atom: Dictionary) -> bool:
    return SaBackdropLayer.reads_around(_compositor.filter_chain, SaLayerStack.layer_of(atom))


## Whether the last rebuild baked *effect* into a cache, so that only a
## rebuild shows a refresh of it.
func folds_effect(effect: SaLayer) -> bool:
    return ledger.folds_effect(effect)


## Whether the last rebuild baked *mask* into a cache, so that only a rebuild
## shows a change to it.
func folds(mask: SaMask) -> bool:
    return ledger.folds(mask)


static func _chunk_rect(grid_pos: Vector2i) -> Rect2:
    var size := float(SaLayer.CHUNK_SIZE)
    return Rect2(float(grid_pos.x) * size, float(grid_pos.y) * size, size, size)
