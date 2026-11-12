## The effect layer with a named input: a layer that is never painted and whose
## pixels are another node of the tree, a layer or a group, run through its own
## attached filters, saved as its recipe. It is the case the adjustment layer
## leaves open, an effect whose output belongs somewhere other than its input.
##
## **Its chunks are a cache of the input's composite**, the input's paint with
## its own records and mask, and nothing else. A mirror layer is the one
## exception, because a mirror reads paint only: an effect layer whose first record's filter answers `reads_paint_alone()`
## true, the base module's Mirror, caches its input's paint alone, a layer's own
## chunks and a group's members drawn without the group's records and mask, see
## [method reads_paint_alone]. The layer's own records, mask,
## clip, mode and opacity then run over those chunks exactly as they run over a
## paint layer's, so the walk, the fold, a flatten and a merge down draw it as
## one and none of them learns what it is: the same `SaAttachedFilter`s, run
## by the same chain.
##
## **Refreshed where its input moved.** `SaDocument.invalidate_chunk_regions`
## says a region does not say which layer moved it, so every effect layer is
## refreshed over the dirty regions the compositor is handed, before it walks
## them, and only there: a chunk of the cache is written over the region that is
## dirty in it, and allocated or dropped where the input shows something or
## nothing (hard rules 2 and 3). The regions are grown by every halo in the tree
## already, the input's filters included, so a blur on the input reaches the
## chunks beside its paint.
##
## **Not during a live stroke.** The stroke is in the stroke buffer until it
## commits, and the input's chunks do not move until then, so a refresh mid
## stroke would copy the same pixels every frame. The regions wait, and the
## commit's own invalidation lands them, over the frames [SaEffectPace] spreads
## the landing across. An effect that follows the stroke as it
## is drawn, the mirror's stroke sweep, is left out, since it would need
## `core/composite` re-cut first.
##
## **Nor while a file opens.** An open fills its chunks in over frames, and on
## a large painting a refresh of its 217 effect layers in the landing's whole
## composite held a frame of 0.45 s and the end's of 1.07 s. The regions wait
## as a stroke's do, each effect showing the picture under it with nothing in
## its cache, and land once the last chunk is in, paced the same way and from
## the view's middle outwards.
##
## **A whole-node record carries a fresh chunk.** The document spreads a change
## through a node whose records read the whole node only where that node held a
## chunk when the change was invalidated. A chunk this refresh makes for an
## effect layer did not exist then, so a mirror over a stroke on new ground
## would never redraw the reflection. The refresh adds to the walk's regions
## where such a record carries the fresh chunk's region, and nowhere else.
##
## **It never folds into a run's cache.** Like a generated layer it is a step of
## its own in the fold, so a refresh is drawn by the next walk with no rebuild.
## Inside an isolated group that does not hold the active layer the group's
## cache folds it, so a refresh there asks for one rebuild, and the refresh that
## rebuild causes does not ask again.
##
## Nothing of the cache is saved: `.sad` stores the input's name, the records and
## the mask, as it stores a generated layer's parameters.
class_name SaEffectLayer
extends RefCounted

## The type id, persisted in `.sad`.
const TYPE_ID: StringName = &"effect"
## The header key the input's name is saved under.
const INPUT_KEY := "input"
## What an effect layer asks its first record's filter to learn whether it reads
## its input's paint alone. A method a filter declares rather than a key the
## skeleton knows, because the skeleton never names a module, and asked of the
## filter rather than saved beside the input's name, so a record carries it
## through a save, a duplicate and an undo with nothing written for it.
const PAINT_ALONE := &"reads_paint_alone"

## Regions dirtied while a stroke was live, refreshed once it has landed.
var _pending: Dictionary[Vector2i, Rect2i] = {}
## The chunk an input group's members are composited into.
var _drawn: SaTexture = null
## Whether the last refresh of a folded effect asked for the rebuild the next
## refresh follows.
var _asked := false
## Where each dirty region moved, kept until a refresh takes it.
var _moved := Moved.new()
## Where each effect's cache is known to hold its input as it stands.
var _stamps := SaEffectStamps.new()
## How much of a stroke's landing one frame refreshes, and the rest of it.
var _pace := SaEffectPace.new()


## The kind as it registers through the door, from `skeleton_module.gd`. The
## plain schema, which is what the cache's chunks are made at.
static func descriptor() -> SaLayerTypeDescriptor:
    var made := SaLayerTypeDescriptor.create(TYPE_ID, SaFieldSpec.default_schema())
    made.display_name = "Effect Layer"
    made.icon_name = "duplicate"
    made.hint = "Shows the active layer through a filter, and leaves its paint as it is. You choose the filter next."
    made.input = SaLayerTypeDescriptor.INPUT_NAMED
    return made


## The node *effect* reads while it is in the document, or null.
static func input_of(effect: SaLayer) -> SaLayer:
    if effect == null or not effect.is_effect():
        return null
    var source := effect.source
    if source == null or not is_instance_valid(source) or source.get_parent() != effect.get_parent():
        return null
    return source


## Why *effect* cannot read *source*, as a sentence, or empty when it can. No
## source at all is allowed, and reads nothing.
static func refusal(effect: SaLayer, source: SaLayer) -> String:
    var why := _refusal(effect, source)
    return "" if why.is_empty() else TranslationServer.translate(str(why[0])) % why.slice(1)


## The refusal as its untranslated sentence and the names it takes, the way
## `SaLayerRefusals` keeps its own, so each caller says it through a lookup.
static func _refusal(effect: SaLayer, source: SaLayer) -> Array:
    if effect == null or not effect.is_effect():
        return ["Only an effect layer reads an input."]
    if source == null:
        return []
    if source.get_parent() != effect.get_parent():
        return ["'%s' is not in this document.", source.name]
    if source.is_generated() or source.is_adjustment():
        return ["'%s' holds no paint of its own to read.", source.name]
    if source.resolution_scale != 1.0:
        return ["'%s' is at another resolution than the document. Resample it to the document's resolution first.", source.name]
    if reads(source, effect, 0):
        return ["'%s' shows this layer, so reading it would read itself.", source.name]
    return []


## Whether drawing *node* draws *target*: the node itself, a group holding
## it, or an effect layer reading either.
static func reads(node: SaLayer, target: SaLayer, depth: int) -> bool:
    if node == null or depth > 64:
        return false
    if node == target or SaLayerStack.is_inside(target, node):
        return true
    var document := node.get_parent() as SaDocument
    if node.is_group and document != null:
        for member in SaLayerStack.members(document, node):
            if reads(member, target, depth + 1):
                return true
    return node.is_effect() and reads(input_of(node), target, depth + 1)


## What a new effect layer reads: the active layer it was made above, when it
## can read that. Null leaves it reading nothing until the painter picks.
static func first_input(document: SaDocument, effect: SaLayer) -> SaLayer:
    var active := document.active_layer if document != null else null
    if active == null or active == effect or not refusal(effect, active).is_empty():
        return null
    return active


## Points *effect* at *source* as one history step, and answers whether it
## did. A refusal is said in the corner.
static func read(document: SaDocument, effect: SaLayer, source: SaLayer) -> bool:
    if document == null or effect == null or effect.source == source:
        return false
    var why := _refusal(effect, source)
    if not why.is_empty():
        SaProblems.refuse("Effect Input", TranslationServer.translate(str(why[0])) % why.slice(1))
        return false
    var before := effect.source
    _apply(document, effect, source)
    document.history.commit_pair("Effect Input", _apply.bind(document, effect, source), _apply.bind(document, effect, before))
    return true


static func _apply(document: SaDocument, effect: SaLayer, source: SaLayer) -> void:
    effect.source = source
    document.modified = true
    document.invalidate_all_allocated_chunks()
    document.update_caches()


## The document's effect layers, each after every effect layer it reads, so
## one refresh brings a chain up to date in order. With *among* given, those of
## them alone, in the same order, so a refresh that reaches a few effects of a
## stack of hundreds orders the few.
##
## The effects inside each input are found by one climb from each effect up
## its groups, so the order costs the effects times the depth. Asking every
## effect whether it sits inside every other's input cost 97 ms at each
## composite on a large winter painting, 217 effects over 563 layers.
static func ordered(document: SaDocument, among: Array[SaLayer] = []) -> Array[SaLayer]:
    var effects := among if not among.is_empty() else effects_of(document)
    var inside: Dictionary[SaLayer, Array] = {}
    for effect in effects:
        var source := input_of(effect)
        if source != null:
            inside[source] = []
    for other in effects:
        var at := other
        var guard := 0
        while at != null and guard < 64:
            if inside.has(at):
                inside[at].append(other)
            at = SaLayerStack.parent_of(at)
            guard += 1
    var found: Array[SaLayer] = []
    var seen: Dictionary[SaLayer, bool] = {}
    for layer in effects:
        _visit(inside, layer, found, seen, 0)
    return found


## Every effect layer of *document*, in the stack's order.
static func effects_of(document: SaDocument) -> Array[SaLayer]:
    var found: Array[SaLayer] = []
    for child in document.get_children():
        var layer := child as SaLayer
        if layer != null and layer.is_effect():
            found.append(layer)
    return found


# Puts *effect* in *found*, and *seen*, after the effects inside its input,
# which *inside* holds by input in the stack's order.
static func _visit(
    inside: Dictionary[SaLayer, Array], effect: SaLayer, found: Array[SaLayer], seen: Dictionary[SaLayer, bool], depth: int
) -> void:
    if seen.has(effect) or depth > 64:
        return
    var source := input_of(effect)
    if source != null:
        for other: SaLayer in inside.get(source, []):
            if other != effect:
                _visit(inside, other, found, seen, depth + 1)
    if not seen.has(effect):
        seen[effect] = true
        found.append(effect)


## Notes where the regions *dirty* moved, before the compositor holds back
## what the view does not reach: at the layers [member SaDocument.moved_at]
## names when *named*, the regions having come through the document's dirty
## set, and at no layer it can name otherwise. A position keeps what was noted
## until a refresh takes it, so a region the backlog hands back frames later is
## refreshed for the change that dirtied it.
func note(document: SaDocument, dirty: Dictionary[Vector2i, Rect2i], named: bool) -> void:
    _moved.note(document, dirty, named)
    _stamps.moved(document.moved_at.keys())


## Brings the effect layers of *document* up to date over *dirty*, grid
## position to chunk-local region, before *compositor* walks it, and adds to
## *dirty* where a whole-node record carries a chunk the refresh made.
## Each effect refreshed hands where its cache moved on to the effects reading
## it, through the records between them, see [method _spread].
##
## **Only the effects the change reaches.** A region [method note] named at a
## layer refreshes an effect whose input is that layer or holds it, and the
## effects that read those, and no other, since an effect's cache is its
## input's composite and nothing above or beside the input moves it. A
## region named at no layer refreshes every effect. On the mirrors
## file of a large painting, 211 mirrors over 540 layers, refreshing all of
## them for one layer's opacity cost a quarter of a second a chunk.
##
## **A landing is paced.** The regions a live stroke left waiting are refreshed
## for as long as [SaEffectPace] pays for a frame, given *held*, the backlog of
## a frame that may leave work to the next, and the rest of the same refresh
## goes on in the frames after it. An open's fill lands the same way, and so
## does any change in a frame given *held*, a group shown among them, since
## showing a large painting's top-summer group refreshed its mirrors for
## 153 ms in one frame. *room* is the chunks the composite budget pays for in
## this frame, below nought when it pays for any. A change in a frame given no
## backlog, a reader's flush, is refreshed whole at once.
func refresh(
    compositor: SaCompositor,
    document: SaDocument,
    dirty: Dictionary[Vector2i, Rect2i],
    held: SaCompositeBacklog = null,
    room := -1,
) -> void:
    if compositor == null or document == null:
        return
    var running := _pace.running(document, dirty)
    var fresh := false
    for grid_pos: Vector2i in dirty:
        var marked := document.beneath_root.has(grid_pos)
        if running and not marked and _pace.kept(grid_pos):
            continue
        fresh = fresh or marked
        var region: Rect2i = dirty[grid_pos]
        _pending[grid_pos] = (_pending[grid_pos] as Rect2i).merge(region) if _pending.has(grid_pos) else region
    # An open's landing frees the stack a refresh still going on was started
    # over, so that refresh is dropped and its regions wait with the open's.
    # The wait ends with the last chunk in, whose composite an open finished
    # in one call, for a save or an export, draws at once and never again.
    var opening := SaSadFile.chunks_to_come(document)
    if running and opening:
        _merged_into(_pending, _pace.abort(dirty))
        running = false
    var live := opening or _stroke_live(document)
    # An open's regions come in its last frames, so its landing is noted
    # whatever waits now, where a stroke's is noted once regions wait.
    if opening or (live and not _pending.is_empty()):
        _pace.waited()
    if running and fresh and not live:
        _merged_into(_pending, _pace.abort(dirty))
        running = false
    if running:
        _finished(document, _pace.run(self, compositor, null, dirty, held, room))
        return
    if _pending.is_empty() or live:
        return
    var regions := _pending
    _pending = {}
    _finished(document, _pace.run(self, compositor, start(document, regions), dirty, held, room))


## The refresh of *regions*, grid position to chunk-local region, ready for
## [method SaEffectPace.Job.step], which calls [method fill] first.
func start(document: SaDocument, regions: Dictionary[Vector2i, Rect2i]) -> SaEffectPace.Job:
    return SaEffectPace.Job.new(document, regions)


## Finds what *job*'s regions reach and the order it refreshes them in, or
## marks it done where they reach no effect.
func fill(job: SaEffectPace.Job, compositor: SaCompositor) -> void:
    var document := job.document
    var owed := _moved.take(document, job.regions)
    _stamps.begin(document, compositor)
    var reached := _reached(document, owed, _stamps)
    if reached.is_empty():
        job.done = true
        return
    var among: Array[SaLayer] = []
    if not owed.anyone_owed():
        among.assign(reached.keys())
    job.reached = reached
    job.shares = _shares(ordered(document, among), compositor.filter_chain.registry)
    job.renderer = SaTreeRender.new(document, true, true)
    job.reaches = Reaches.new(compositor, document)
    job.readers = _readers(document)


## After a frame of [SaEffectPace] handed back *finished*, the job it ended:
## asks for the fold's rebuild where a folded effect moved, and once nothing
## waits, ends the landing.
func _finished(document: SaDocument, finished: SaEffectPace.Job) -> void:
    if finished == null:
        return
    if _pending.is_empty():
        _pace.landed()
    if not finished.folded:
        return
    if _asked:
        _asked = false
    else:
        _asked = true
        document.request_cache_update()


## What *job*'s next run of effects, *share*, is refreshed over: each effect
## the change reached or a refresh before it spread to, with the regions of
## both.
func share_over(job: SaEffectPace.Job, share: Array) -> Dictionary[SaLayer, Dictionary]:
    var over: Dictionary[SaLayer, Dictionary] = {}
    for effect: SaLayer in share:
        if not job.reached.has(effect) and not job.spread.has(effect):
            continue
        var reached_here: Dictionary = job.reached.get(effect, {})
        var spread_here: Dictionary = job.spread.get(effect, {})
        var here := SaTyped.regions(reached_here.duplicate())
        _merged_into(here, spread_here)
        over[effect] = here
    return over


## Hands on what *job*'s run of effects wrote, once its last chunk is written:
## the chunks a whole-node record carries and the regions the effects reading
## them owe, each added to *dirty*, or to what a paced job owes the walk.
func share_close(job: SaEffectPace.Job, dirty: Dictionary[Vector2i, Rect2i]) -> void:
    var document := job.document
    var walked := job.walk if job.paced else dirty
    for effect: SaLayer in job.over:
        _carry(effect, job.made[effect], document.canvas_size, walked)
        _spread(document, effect, job.wrote[effect], job.readers, job.spread, walked)
        job.folded = job.folded or (document.fold != null and document.fold.folds_effect(effect))


## Each effect layer of *document* that *owed* reaches, with the regions it is
## refreshed over: every region named at no layer but those a reveal alone
## marked where *stamps* says the cache stands, and those named at its input,
## at a layer inside it, or at an effect inside it that is refreshed itself.
## Each layer that moved hands its regions up its chain of groups once, and an
## effect whose input is on that chain takes them and moves in turn, so the
## search costs the depth of what moved and not the stack's size.
static func _reached(document: SaDocument, owed: Owed, stamps: SaEffectStamps) -> Dictionary[SaLayer, Dictionary]:
    var reached: Dictionary[SaLayer, Dictionary] = {}
    var effects := effects_of(document)
    var reading: Dictionary[SaLayer, Array] = {}
    for effect in effects:
        if owed.anyone_owed():
            var left := stamps.owed(effect, owed.anyone, owed.still)
            if not left.is_empty():
                reached[effect] = left
        var source := input_of(effect)
        if source != null:
            if not reading.has(source):
                reading[source] = []
            reading[source].append(effect)
    var moving: Array = []
    for layer: SaLayer in owed.at:
        moving.append([layer, owed.at[layer]])
    while not moving.is_empty():
        var next: Array = moving.pop_back()
        var layer: SaLayer = next[0]
        var regions: Dictionary = next[1]
        var at := layer
        var guard := 0
        while at != null and guard < 64:
            for effect: SaLayer in reading.get(at, []):
                if effect == layer:
                    continue
                var mine: Dictionary = reached.get_or_add(effect, {})
                if _merged_into(mine, regions):
                    moving.append([effect, mine.duplicate()])
            at = SaLayerStack.parent_of(at)
            guard += 1
    return reached


## Merges the regions of *more* into *into*, grid position to Rect2i, and
## answers whether *into* took anything it lacked.
static func _merged_into(into: Dictionary, more: Dictionary) -> bool:
    var took := false
    for grid_pos: Vector2i in more:
        var region: Rect2i = more[grid_pos]
        if not into.has(grid_pos):
            into[grid_pos] = region
            took = true
            continue
        var held: Rect2i = into[grid_pos]
        if not held.encloses(region):
            into[grid_pos] = held.merge(region)
            took = true
    return took


static func _stroke_live(document: SaDocument) -> bool:
    var buffer := document.stroke_layer
    if buffer != null and not buffer.chunks.is_empty():
        return true
    return document.stroke_transaction != null and not document.stroke_transaction.before_chunks.is_empty()


## The effects of *order* in runs that read one input the same way, each run
## where its first effect stands in *order*. Every effect of a run waits on the same effects, those inside the input, so a
## later one moved up to the first is still drawn after all of them, and
## nothing drawn between the two can move the input, since an effect inside it
## that read one of the run would read itself, which [method refusal] forbids.
static func _shares(order: Array[SaLayer], registry: SaFilterRegistry) -> Array[Array]:
    var shares: Array[Array] = []
    var at: Dictionary[String, int] = {}
    for effect in order:
        var source := input_of(effect)
        var key := "%d %s" % [source.get_instance_id() if source != null else 0, reads_paint_alone(effect, registry)]
        if at.has(key):
            shares[at[key]].append(effect)
            continue
        at[key] = shares.size()
        shares.append([effect])
    return shares


## Opens *job*'s run of effects [member SaEffectPace.Job.over] for its
## chunks, which [method share_cell] writes one at a time. The caches of the
## effects it holds, which read one input the same way,
## each over its regions there: the input drawn once a chunk where it shows
## something and copied to every effect owed that chunk, written over the
## dirty region of a chunk an effect had and over the whole of one it makes,
## and no chunk where the input shows nothing. The job gathers by effect the
## chunks made, each with the region that was dirty in it, and every chunk its
## cache moved at, which [method _spread] hands on to the effects reading it.
##
## **Drawn once for the run.** The nights file of a large painting holds
## 219 effect layers over 96 inputs, most of them groups, and a load owes
## every effect every chunk. Drawing the input once an effect cost 1.6 s of
## one frame when a door step paid the load's last 16 chunks at once.
##
## **No input shows nothing.** An effect whose input was deleted, or never
## picked, reaches nowhere, so every chunk it holds in its regions is dropped.
## The delete invalidates every allocated chunk, the effect's own among them,
## so that is all of them. The empty reach is typed where it is declared,
## because a bare `{}` on the far side of a conditional is an untyped
## dictionary, and assigning it to this variable raises a script error that
## ends the refresh before it clears a chunk.
func share_open(job: SaEffectPace.Job, compositor: SaCompositor) -> void:
    var over := job.over
    var first: SaLayer = over.keys()[0]
    job.source = input_of(first)
    job.alone = reads_paint_alone(first, compositor.filter_chain.registry)
    job.reach = {}
    if job.source != null:
        job.reach = job.reaches.of(job.source, not job.alone)
    job.made = {}
    job.wrote = {}
    var owed: Dictionary[Vector2i, bool] = {}
    for effect: SaLayer in over:
        var mine: Dictionary[Vector2i, Rect2i] = {}
        job.made[effect] = mine
        var written: Dictionary[Vector2i, Rect2i] = {}
        job.wrote[effect] = written
        for grid_pos: Vector2i in over[effect]:
            owed[grid_pos] = true
    job.cells.assign(owed.keys())
    if job.paced:
        job.outwards(job.cells)
    job.cell = 0


## Writes *job*'s open run of effects at *grid_pos*: the input drawn once and
## copied to every effect owed the chunk. A paced job owes the walk the
## region, since the frame that took the change did not walk it.
func share_cell(job: SaEffectPace.Job, compositor: SaCompositor, grid_pos: Vector2i) -> void:
    var drawn: SaTexture = null
    if job.reach.has(grid_pos):
        drawn = _drawn_input(compositor, job.document, job.source, grid_pos, job.renderer, job.alone)
    for effect: SaLayer in job.over:
        var regions: Dictionary = job.over[effect]
        if regions.has(grid_pos):
            var region: Rect2i = regions[grid_pos]
            var whole := _write(compositor, effect, drawn, grid_pos, region, job.made[effect], job.wrote[effect])
            _stamps.stamp(effect, grid_pos, whole)
            if job.paced:
                SaCompositeBacklog.merge(job.walk, grid_pos, region)


## Writes *drawn*, the input at *grid_pos*, into *effect*'s cache over *dirty*,
## or over the whole chunk when the effect had none there, noting a chunk it
## made in *made* and every chunk it moved in *wrote*. A null *drawn* drops
## the chunk. Answers whether the cache there now holds the input whole.
static func _write(
    compositor: SaCompositor,
    effect: SaLayer,
    drawn: SaTexture,
    grid_pos: Vector2i,
    dirty: Rect2i,
    made: Dictionary,
    wrote: Dictionary
) -> bool:
    if drawn == null:
        if effect.chunks.has(grid_pos):
            effect.set_chunk(grid_pos, null)
            wrote[grid_pos] = dirty
        return true
    if drawn.size != SaDocument.WHOLE_CHUNK.size:
        return false
    wrote[grid_pos] = dirty
    var fresh := not effect.chunks.has(grid_pos)
    var albedo := effect.get_or_create_chunk(grid_pos).albedo()
    if fresh:
        made[grid_pos] = dirty
    _copy(compositor, drawn, albedo, SaDocument.WHOLE_CHUNK if fresh else dirty)
    return fresh or dirty.encloses(SaDocument.WHOLE_CHUNK)


## Whether *effect* reads its input's paint alone: its first record's filter, as
## *registry* answers it, declares [constant PAINT_ALONE] and answers true. The
## base module's Mirror is the filter that does, because a mirror reads paint
## only. False for every other effect layer, which reads its input's composite.
static func reads_paint_alone(effect: SaLayer, registry: SaFilterRegistry) -> bool:
    if effect == null or not effect.is_effect() or effect.filters.is_empty() or registry == null:
        return false
    var first := effect.filters[0]
    var filter := registry.get_filter(first.key) if first != null else null
    return filter != null and filter.has_method(PAINT_ALONE) and filter.call(PAINT_ALONE) == true


## Adds to *dirty* where *effect*'s records carry the chunks this refresh *made*,
## for an effect whose records read the whole node, which the document could not
## spread through a chunk that did not exist yet. Each position added is redrawn
## whole, as the document's own spread redraws it.
static func _carry(
    effect: SaLayer, made: Dictionary[Vector2i, Rect2i], canvas: Vector2i, dirty: Dictionary[Vector2i, Rect2i]
) -> void:
    if made.is_empty() or not SaNeighbourhoodPass.reads_whole(effect.filters):
        return
    var held := SaTyped.positions(effect.chunks)
    for grid_pos: Vector2i in SaNeighbourhoodPass.stale_under(effect.filters, held, made, canvas):
        dirty[grid_pos] = SaDocument.WHOLE_CHUNK


## Each node of *document* an effect layer reads, with the effects that read
## it, in the stack's order.
static func _readers(document: SaDocument) -> Dictionary[SaLayer, Array]:
    var found: Dictionary[SaLayer, Array] = {}
    for effect in effects_of(document):
        var source := input_of(effect)
        if source != null:
            var reading: Array = found.get_or_add(source, [])
            reading.append(effect)
    return found


## Hands where *effect*'s cache was *written* on to every effect that reads it,
## grown by the records between the two, and adds it to *dirty* where the
## canvas draws *effect*.
##
## **Why.** A record that reads past its chunk, a Mirror reading the land for
## the lake or a ripple's wobble, makes the composite at one chunk hang on the
## cache at another. The document grows a change by those records before a
## composite, so one refresh over the whole of it is right. The budget and the
## view cut that set into the batches of several frames, though, and a reader
## refreshed in one batch would read the caches of a later batch as they stood,
## empty after a load. Nothing marks it again, so a reflection would depend on
## how a load's frames were cut, and two loads of one file would export
## different reflections. [method ordered] puts every reader
## after *effect*, so what this hands on is drawn in the same refresh.
static func _spread(
    document: SaDocument,
    effect: SaLayer,
    written: Dictionary[Vector2i, Rect2i],
    readers: Dictionary[SaLayer, Array],
    spread: Dictionary[SaLayer, Dictionary],
    dirty: Dictionary[Vector2i, Rect2i]
) -> void:
    if written.is_empty():
        return
    var canvas := document.canvas_size
    var out := _through(effect, written, canvas)
    if SaLayerStack.shows(document, effect):
        _merged_into(dirty, out)
    var at := effect
    var guard := 0
    while at != null and guard < 64:
        for reader: SaLayer in readers.get(at, []):
            if reader != effect:
                var owed: Dictionary = spread.get_or_add(reader, {})
                _merged_into(owed, out)
        at = SaLayerStack.parent_of(at)
        if at != null:
            out = _through(at, out, canvas)
        guard += 1


## Where *node*'s composite moves when its pixels move over *regions*: the
## regions grown by the halo of its records, or for a record that reads the
## node whole, the regions and every position it carries the change to, which
## a whole pass's halo says nothing of.
static func _through(node: SaLayer, regions: Dictionary[Vector2i, Rect2i], canvas: Vector2i) -> Dictionary[Vector2i, Rect2i]:
    if node.filters.is_empty():
        return regions
    if not SaNeighbourhoodPass.reads_whole(node.filters):
        return SaNeighbourhoodPass.grown(regions.duplicate(), SaNeighbourhoodPass.halo_of(node.filters))
    var out := regions.duplicate()
    var held := SaTyped.positions(node.chunks)
    for grid_pos: Vector2i in SaNeighbourhoodPass.stale_under(node.filters, held, regions, canvas):
        out[grid_pos] = SaDocument.WHOLE_CHUNK
    return out


## The input's composite at *grid_pos*, what it shows before its own mode and
## opacity: a layer through its records and mask, a group's members drawn as an
## isolated group draws them and then through its records and mask. With
## *alone*, the input's paint and nothing of its own records or mask: a layer's
## chunk as it is, a group's members drawn and no more. Null where it shows
## nothing. A scratch read by the copy that follows, or the layer's own chunk.
##
## **Drawn through its live transform.** A layer with one is read from the
## cache of its map, where its paint shows after a move, a turn, a scale or the
## Crop tool's crop, the way `SaTreeRender` draws it, and its records run over
## that cache with the cache as their neighbours, or the effect would show the
## input where it was painted. The cache holds the layer's mask already, so the layer's own
## mask is not run again. With *alone* the cache is read as it is, so a mirror
## over a transformed input whose mask is on reflects what the mask leaves,
## though a mirror reads paint only: the one resample of the
## paint without its mask is the bake's, private to `SaLiveTransform`.
##
## The paint is read as the canvas draws it while a filter dialog previews a
## pass on the active layer, so the effect follows the preview before Apply.
func _drawn_input(
    compositor: SaCompositor, document: SaDocument, source: SaLayer, grid_pos: Vector2i, renderer: SaTreeRender, alone: bool
) -> SaTexture:
    var side := Vector2i(SaLayer.CHUNK_SIZE, SaLayer.CHUNK_SIZE)
    var whole := Rect2i(Vector2i.ZERO, side)
    if not source.is_group:
        var paint := SaLiveTransform.paint_of(source)
        var drawn := compositor.point_preview.drawn(compositor, document, source, paint.get_field(grid_pos), grid_pos, whole)
        if alone:
            return drawn
        return compositor.shown(source, paint, drawn, grid_pos, whole, paint)
    var format := document.color_space.texel_format()
    if _drawn == null or _drawn.format != format:
        _drawn = SaTexture.new(side, format)
    compositor.clear_scratch_batch([[_drawn, whole]])
    renderer.render_members(_drawn, source, grid_pos)
    return _drawn if alone else compositor.shown(source, source, _drawn, grid_pos, whole)


## Copies *region* of *source* onto the same place in *target*, a dispatch and
## not a transfer for the reason `copy_region.gmacs` gives.
static func _copy(compositor: SaCompositor, source: SaTexture, target: SaTexture, region: Rect2i) -> void:
    var compute := compositor.get_compute("copy_region")
    compute.use_storage_format(source.format)
    compute.set_texture(0, target.rid)
    compute.set_texture(1, source.rid)
    var at := region.position
    compute.set_push_constant_float_array(PackedFloat32Array([at.x, at.y, at.x, at.y, region.size.x, region.size.y, 0.0, 0.0]))
    compute.dispatch_kernel("copy_region", SaCompute.groups_for(region.size.x), SaCompute.groups_for(region.size.y), 1)


## The chunks `.sad` writes for *layer*: none of an effect layer's or a drawn
## one's, which are a cache, and every chunk of any other. A drawn layer with
## a mask keeps its chunks, because the mask is a field of them that no
## recipe draws again.
static func stored_chunks(layer: SaLayer) -> Dictionary[Vector2i, SaChunk]:
    if layer.is_effect() or (layer.is_drawn() and layer.mask == null):
        var none: Dictionary[Vector2i, SaChunk] = {}
        return none
    return layer.chunks


## Writes *layer*'s input into its header entry *layer_dict*, by name, which
## is unique in a document.
static func write_input(layer: SaLayer, layer_dict: Dictionary[String, Variant]) -> void:
    var source := input_of(layer)
    if source != null:
        layer_dict[INPUT_KEY] = str(source.name)


## Keeps the input's name from *layer_data* on *layer* until every layer
## exists, for [method join_inputs].
static func read_input(layer: SaLayer, layer_data: Dictionary[String, Variant]) -> void:
    if layer_data.has(INPUT_KEY):
        layer.set_meta(&"input_name", str(layer_data[INPUT_KEY]))


## Points every effect layer of a loaded *document* at the node its header
## named. A second pass, because the input may be written after the layer.
static func join_inputs(document: SaDocument) -> void:
    var by_name: Dictionary[String, SaLayer] = {}
    for child in document.get_children():
        if child is SaLayer:
            by_name[str(child.name)] = child
    for child in document.get_children():
        var layer := child as SaLayer
        if layer == null or not layer.has_meta(&"input_name"):
            continue
        var named: SaLayer = by_name.get(str(layer.get_meta(&"input_name")), null)
        layer.remove_meta(&"input_name")
        layer.source = named if named != layer else null


## Where *effect* shows something once its own records have run, as a set cut to
## the document's grid: the chunks of its cache, and the ring or the landing its
## records carry paint onto. What its row's picture is drawn over, with
## [method result_at].
static func result_positions(document: SaDocument, effect: SaLayer) -> Dictionary[Vector2i, bool]:
    return SaTreeRender.new(document).reach(effect, SaTyped.positions(effect.chunks))


## What *effect* shows at *grid_pos* before its mask, mode and opacity: its
## cache run through its own records, as the walk runs them. The cache alone is
## the input, so a row's picture drawn from it would show the photograph
## rather than its kaleidoscope. The cache as it is
## where there is no compositor to run the records, and null where nothing
## shows. A scratch of the filter chain's, read before the next call.
static func result_at(document: SaDocument, effect: SaLayer, grid_pos: Vector2i) -> SaTexture:
    var cached := effect.get_field(grid_pos)
    var compositor := document.compositor if document != null else null
    if compositor == null:
        return cached
    return compositor.filter_chain.filtered(effect, cached, grid_pos, SaDocument.WHOLE_CHUNK, effect)


func _notification(what: int) -> void:
    if what == NOTIFICATION_PREDELETE:
        _drawn = null


## Where the nodes of one document can show something, for one refresh: a
## node's chunks and the ring its records carry paint into, a group's the
## union of its members'. Every position when a member is generated. Without
## *own*, the node's own records are left out, which is where its paint alone
## shows, a group's members still through theirs. A layer drawn through a live
## transform shows where its cache holds paint, as the walk reads it, and not
## where it was painted.
##
## Each group's members are read in one pass over the stack and each node's
## reach is found once a refresh, since hundreds of effects read the same
## groups: finding them afresh for each effect cost 65 ms at each composite on
## a large winter painting. An effect's own reach is asked only after
## the refresh has brought it up to date, because [method ordered] puts every
## effect after those inside its input.
class Reaches:
    extends RefCounted

    ## The compositor's chain, held rather than the compositor, so a refresh
    ## [SaEffectPace] carries to the next frame holds no cycle back to it.
    var _chain: SaFilterChain
    var _canvas: Vector2i
    ## Each group's members, in the stack's order.
    var _members: Dictionary[SaLayer, Array] = {}
    ## The reaches found so far, with and without the node's own records.
    var _own: Dictionary[SaLayer, Dictionary] = {}
    var _alone: Dictionary[SaLayer, Dictionary] = {}

    func _init(compositor: SaCompositor, document: SaDocument) -> void:
        _chain = compositor.filter_chain
        _canvas = document.canvas_size
        for child in document.get_children():
            var layer := child as SaLayer
            var group := SaLayerStack.parent_of(layer) if layer != null else null
            if group != null:
                var members: Array = _members.get_or_add(group, [])
                members.append(layer)

    ## Where *node* can show something, through its own records when *own*.
    func of(node: SaLayer, own: bool = true) -> Dictionary[Vector2i, bool]:
        var known := _own if own else _alone
        if known.has(node):
            return known[node]
        var found: Dictionary[Vector2i, bool] = {}
        if node.is_group:
            for member: SaLayer in _members.get(node, []):
                if member.is_generated():
                    for grid_pos in SaLayer.grid_positions(_canvas):
                        found[grid_pos] = true
                elif not member.is_adjustment():
                    found.merge(of(member))
        else:
            found = SaTyped.positions(SaLiveTransform.paint_of(node).chunks)
        var reach := _chain.walked(node, found) if own else found
        known[node] = reach
        return reach


## The regions one refresh owes, split by what moved them: [member anyone]
## refreshes every effect layer, and [member at] the effects whose input holds
## the layer it is keyed by.
class Owed:
    extends RefCounted

    ## Grid position -> Rect2i, regions moved at no layer a refresh can name.
    var anyone: Dictionary[Vector2i, Rect2i] = {}
    ## The positions of [member anyone], read as a set, that only a reveal
    ## marked, [member SaDocument.still].
    var still: Dictionary[Vector2i, bool] = {}
    ## Layer -> grid position -> Rect2i, regions moved at that layer.
    var at: Dictionary[SaLayer, Dictionary] = {}

    func _init(
        found_anyone: Dictionary[Vector2i, Rect2i],
        found_at: Dictionary[SaLayer, Dictionary],
        found_still: Dictionary[Vector2i, bool],
    ) -> void:
        anyone = found_anyone
        at = found_at
        still = found_still

    ## Whether a region is owed to every effect layer.
    func anyone_owed() -> bool:
        return not anyone.is_empty()


## The layers each dirty position moved at, noted where the compositor takes
## the regions and kept until a refresh walks the position.
class Moved:
    extends RefCounted

    ## Grid position -> layer instance id -> true, the layers a change there
    ## moved at.
    var _at: Dictionary[Vector2i, Dictionary] = {}
    ## Grid position -> whether only a reveal marked it, where a change moved at
    ## no layer that can be named.
    var _anyone: Dictionary[Vector2i, bool] = {}
    ## Grid position -> layer instance id -> true, what the last [method take]
    ## answered there at named layers. A refresh takes what a stroke left
    ## pending while the backlog still holds some of its positions, and a
    ## position it hands back after that is read at these rather than at no
    ## layer, which drew each of the nights file's 219 effect layers again over
    ## two chunks after a wash stroke.
    var _taken: Dictionary[Vector2i, Dictionary] = {}

    ## Notes *dirty* at the layers [member SaDocument.moved_at] names, where
    ## *named* and the named regions there enclose the dirty one, and at no
    ## layer elsewhere, a halo's or a live transform's growth among them. A
    ## position the document did not mark since the last consume, one the
    ## backlog hands back, keeps what was noted when it was marked, or what the
    ## last take answered there, and is noted at no layer only when neither
    ## names one.
    func note(document: SaDocument, dirty: Dictionary[Vector2i, Rect2i], named: bool) -> void:
        if not named:
            for grid_pos: Vector2i in dirty:
                _anyone[grid_pos] = false
            return
        var enclosing: Dictionary[Vector2i, Rect2i] = {}
        var ids: Dictionary[Vector2i, Dictionary] = {}
        for id: int in document.moved_at:
            var regions := SaTyped.regions(document.moved_at[id])
            for grid_pos: Vector2i in regions:
                var region: Rect2i = regions[grid_pos]
                enclosing[grid_pos] = enclosing[grid_pos].merge(region) if enclosing.has(grid_pos) else region
                var here: Dictionary = ids.get_or_add(grid_pos, {})
                here[id] = true
        for grid_pos: Vector2i in dirty:
            var fresh := document.beneath_root.has(grid_pos)
            if fresh and enclosing.has(grid_pos) and enclosing[grid_pos].encloses(dirty[grid_pos]):
                var noted: Dictionary = _at.get_or_add(grid_pos, {})
                noted.merge(ids[grid_pos])
            elif not fresh and not _at.has(grid_pos) and _taken.has(grid_pos):
                _at[grid_pos] = _taken[grid_pos].duplicate()
            elif fresh:
                var revealed := document.still.has(grid_pos) and not ids.has(grid_pos)
                _anyone[grid_pos] = revealed and _anyone.get(grid_pos, true)
            elif not _at.has(grid_pos) and not _anyone.has(grid_pos):
                _anyone[grid_pos] = false

    ## *regions* split by what was noted there, and the notes of those
    ## positions forgotten. A position noted at nothing, or at a layer no
    ## longer in *document*, is owed to every effect, and is still where only a
    ## reveal marked it.
    func take(document: SaDocument, regions: Dictionary[Vector2i, Rect2i]) -> Owed:
        var anyone: Dictionary[Vector2i, Rect2i] = {}
        var still: Dictionary[Vector2i, bool] = {}
        var at: Dictionary[SaLayer, Dictionary] = {}
        for grid_pos: Vector2i in regions:
            var region: Rect2i = regions[grid_pos]
            var ids: Dictionary = _at.get(grid_pos, {})
            var layers: Array[SaLayer] = []
            for id: int in ids:
                var layer := instance_from_id(id) as SaLayer
                if layer == null or layer.get_parent() != document:
                    layers.clear()
                    break
                layers.append(layer)
            if _anyone.has(grid_pos) or layers.is_empty():
                anyone[grid_pos] = region
                if _anyone.get(grid_pos, false) and ids.is_empty():
                    still[grid_pos] = true
                _taken.erase(grid_pos)
            else:
                _taken[grid_pos] = ids
                for layer in layers:
                    var owed: Dictionary = at.get_or_add(layer, {})
                    owed[grid_pos] = region
            _at.erase(grid_pos)
            _anyone.erase(grid_pos)
        return Owed.new(anyone, at, still)
