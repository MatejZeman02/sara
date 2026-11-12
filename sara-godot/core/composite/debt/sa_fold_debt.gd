## What the fold owes the document: the caches either side of the active layer
## folded again, put off since an activation or a change of the stack.
##
## The caches below and above the active layer serve a stroke. A click on a
## row, an add, a drop and a delete each make a layer active, and folding the
## whole stack there would cost hundreds of dispatches on a deep stack, so an
## activation owes the fold and folds nothing. The walk still splits at the
## layer it was built on, which draws the same picture, so nothing is drawn
## again either.
##
## **A change of the stack** under the walk, a layer that came, went or moved,
## owes the fold whole and marks the picture to be drawn again. The composite
## that draws it pays first, so the picture on screen is what a fold would
## show at every frame, and a delete that changes the active layer and the
## stack folds once rather than twice. What it marks and folds is what
## [StackChange] reads the change moved: the chunks of the layers that came,
## went or moved, which a delete of a painted layer, an add and a drop are,
## rather than every chunk and every cache, which on a deep stack would cost a
## frame of tens of milliseconds after every delete.
##
## **The rest is paid** at a stroke's press, or on the first idle frame: one
## with no button held, [member quiet_msec] after the last debt. A second
## activation before then only moves the mark. Paying for an activation alone
## draws nothing, as [method settle] says, and an idle frame folds a few of its
## caches and leaves the rest to the frames after it, as [method frame] says.
##
## **A layer or a group shown or hidden** owes the fold whole and draws
## nothing until it is paid, as [method owe_shown] says. The picture changed,
## so no walk drawn before the fold is the true one, and the frames of the fold
## show the picture from before the click rather than a fold half done.
class_name SaFoldDebt
extends RefCounted

## What is owed, as [method owe] says. REST is the caches a fold over frames
## has still to fold, the walk built.
enum Owed { NOTHING, REST, IF_MOVED, WHOLE }

## The milliseconds with no new debt and no button held that make a frame an
## idle one. Half a second lets a painter click down the rows of the Layers
## docker with no fold between the clicks. A suite dials it to nought.
var quiet_msec := 500

## The steps, a layer or a group each, that the idle frame and each frame
## after it fold of a debt of the active layer alone, a few milliseconds a
## step, so a frame of the fold stays short of a stall. It was 8, and a fold
## of a large painting's group, steps of a millisecond, spread over four
## frames before its picture was drawn, so [member frame_usec] is what keeps a
## frame short.
var steps_per_frame := 64

## The microseconds of folding after which a frame leaves the rest to the
## next, whatever [member steps_per_frame] allows. A step of an adjustment
## layer over the 27 chunks of the dawn picture folds in about 25 ms, ten
## times a painted layer's, so eight of them made a frame of 200 ms. One step
## is folded whatever it costs. It was 30 ms, and the frame the fold of the
## large painting's group finished in spent 23 ms of it, beside the 28 ms of
## the composite and the 10 ms of the layers docker that finishing asks for, in
## a frame that has to stay under 0.1 s.
var frame_usec := 15000

## The microseconds the fold paid since the window last drew, which
## [method take_paid] hands the easel's next composite, and the drawn frame
## they were paid after. A payment that finishes the fold draws the picture it
## held in the same frame, and the easel's walk waits for the next when the
## payment took a quarter of a frame: showing a large painting's group paid
## 23 to 28 ms and walked two chunks for 50 ms after it, and the frame came to
## 118 to 160 ms. The window draws only when something on it changed, so two
## process frames may pay before one draw, 15 ms and 7 ms on that file, and
## both are the drawn frame's.
var _paid_usec := 0
var _paid_drawn := -1

# The process frame whose budgeted walk took a quarter of a frame, which
# [method walked] writes after the easel composites, and the fold pays in the
# frame after it rather than beside it. The two come in a frame in the order
# their signals did, and the day group's show walked two chunks for 31 ms and
# then paid 23 ms in one frame of 114 ms.
var _walked_in := -1

var _owed := Owed.NOTHING
# Whether a debt owed whole met a change [StackChange] cannot read, which
# marks every chunk and pays through `SaDocument.update_caches`.
var _wide := false
var _owed_at := 0
# The document the debt is owed to, by instance id, so nothing here keeps it.
var _owed_to := 0
# Whether the debt is of a change of what shows, whose picture is drawn once
# the last of it is paid.
var _draws_when_paid := false
# Whether a show or a hide owes the walk built again. The build waits for the
# end of the frame, or for the first call here that reads the walk, so a door
# request of forty shows and hides builds it once rather than forty times.
var _shown_due := false
# The layers shown or hidden since the picture was last drawn, by instance id,
# or a nought among them when one call named none. The picture they hold back
# is marked at each, so an effect layer whose input none of them is in is not
# drawn again.
var _shown: Array[int] = []


## Owes *document*'s fold, which costs no dispatch. A change of the active
## layer alone, *whole* false, leaves the walk drawing the same picture around
## the layer it was built on, so nothing is drawn again. Anything else the
## walk reads that moved, and *whole* true, which a change of the stack says,
## draws the whole picture again, and the composite that draws it pays first.
func owe(document: SaDocument, whole: bool = false) -> void:
    _build_shown(document)
    var was := _owed
    var moved_only := not whole and document.fold.reads_as_built(document, true)
    _owed = maxi(_owed, Owed.IF_MOVED if moved_only else Owed.WHOLE) as Owed
    _owed_at = Time.get_ticks_msec()
    _owed_to = document.get_instance_id()
    if not moved_only:
        _mark(document, StackChange.new(document))
    if was == Owed.NOTHING:
        frame.call_deferred()


## Owes *document*'s fold after a layer or a group was shown or hidden, the
## walk built at the end of the frame and every cache of it folded over the
## frames after it, as [method frame] pays them. The picture on screen stands
## as it was until the last is paid, and is drawn whole then, so no frame shows
## a fold half done. Every show and hide of one frame shares the one build,
## which a call here that reads the walk before the frame ends makes at once.
## *shown* is the layer shown or hidden, null when the caller cannot say.
func owe_shown(document: SaDocument, shown: SaLayer = null) -> void:
    if document.fold == null or document.compositor == null or document.active_layer == null:
        document.update_caches(Rect2(), true)
        return
    _draws_when_paid = true
    _shown.append(shown.get_instance_id() if shown != null else 0)
    _owed_at = Time.get_ticks_msec()
    _owed_to = document.get_instance_id()
    var due := _shown_due
    _shown_due = true
    _owed = Owed.REST
    if not document.is_inside_tree():
        settle(document)
    elif not due:
        frame.call_deferred()


# Builds the walk a show or a hide owes, once however many asked for it, and
# leaves every cache of it to be folded over the frames after.
func _build_shown(document: SaDocument) -> void:
    if not _shown_due:
        return
    _shown_due = false
    _resolve(document)
    var traced := SaFrameTrace.now()
    document.fold.rebuild_unpaid(document, document.compositor, _canvas_of(document))
    SaFrameTrace.spent("fold rebuild", traced)
    _owed = Owed.REST


## Whether a fold is owed and not yet paid.
func is_owed() -> bool:
    return _owed != Owed.NOTHING


## The microseconds this fold paid since the window last drew, nought when it
## paid nothing, which a composite takes once, so a suite that calls the
## frames of both without drawing finds each payment once.
func take_paid() -> int:
    if _paid_drawn != Engine.get_frames_drawn():
        return 0
    var usec := _paid_usec
    _paid_usec = 0
    return usec


## Notes that the easel's walk took a quarter of this frame, so this fold
## pays in the next.
func walked() -> void:
    _walked_in = Engine.get_process_frames()


## Whether the stack changed under the walk since it was built, which leaves
## the walk naming layers that may be gone.
func owes_whole() -> bool:
    return _owed == Owed.WHOLE


## Every layer of *document*, group members too, its stroke buffer and every
## cache of its fold: what the walk reads once it is folded, which a walk owed
## whole cannot be asked for, since it may name a layer gone since. A document
## with no fold yet has only its walk.
static func drawn_from(document: SaDocument) -> Array[SaLayer]:
    if document.fold == null:
        return SaLayerStack.layers(document)
    var held: Array[SaLayer] = []
    var seen: Array = document.fold.caches() + [document.stroke_layer] + document.get_children()
    while not seen.is_empty():
        var layer: Variant = seen.pop_back()
        if is_instance_valid(layer) and layer is SaLayer:
            var found: SaLayer = layer
            held.append(found)
            seen.append_array(found.get_children())
    return held


## Pays what *document* owes before *dirty*, the chunks a frame is about to
## draw, are drawn, so the frame draws what a fold would show. A change of
## the stack is paid by the composite after it even with nothing to draw, an
## add of an empty layer, so it is never left to a stroke's press.
static func before_drawing(document: SaDocument, dirty: Dictionary) -> void:
    if document.fold != null and (not dirty.is_empty() or document.fold.debt.owes_whole()):
        document.fold.debt.settle(document)


## Pays what *document* owes when the picture it shows is not the one its
## stack draws, before a read of the whole picture for a file or a copy. A
## layer or a group shown or hidden holds the picture back until its fold is
## paid, as [method owe_shown] says, so an export taken while it folds read the
## picture from before the click. It pays the way a stroke's press
## does, in this call and never by waiting for frames. A debt of the active
## layer alone draws the same picture and is left to its idle frame.
static func before_reading(document: SaDocument) -> void:
    if document == null or document.fold == null:
        return
    var debt := document.fold.debt
    if debt._draws_when_paid or debt.owes_whole():
        debt.settle(document)


## Pays all that is owed to *document* now, by folding it whole, unless the
## active layer came back to the one the walk was built on and nothing else
## moved. A press and a frame that draws call it, and both need every cache.
##
## **A debt of the active layer alone** is paid by the fold and nothing else.
## The walk around the old layer drew the same picture the new walk draws, so
## paying draws nothing again and tells nobody the document changed, rather
## than spending a frame on the composite, the relief and the thumbnails of a
## picture that has not moved. A debt owed whole, or a walk that moved
## since the debt, folds and draws through `SaDocument.update_caches`.
func settle(document: SaDocument) -> void:
    _build_shown(document)
    _forgive_a_return(document)
    if _owed == Owed.NOTHING or document.active_layer == null:
        _draw_held(document)
        return
    if _owed == Owed.REST:
        document.fold.pay(document, document.compositor)
        _owed = Owed.NOTHING
    elif _quiet(document):
        _resolve(document)
        document.fold.rebuild(document, document.compositor, _canvas_of(document))
    elif _owed == Owed.WHOLE and not _wide and document.compositor != null:
        _restack(document)
    else:
        document.update_caches(Rect2(), true)
    _draw_held(document)


# Pays a debt owed whole by folding what [StackChange] reads moved, over the
# chunks it holds, or whole through `SaDocument.update_caches` when it reads a
# change it cannot narrow. Marked again with what it reads now, since a change
# since the last debt that owed nothing would otherwise go undrawn.
func _restack(document: SaDocument) -> void:
    var change := StackChange.new(document)
    _mark(document, change)
    if _wide:
        document.update_caches(Rect2(), true)
        return
    _resolve(document)
    document.fold.restack(document, document.compositor, change.moved, change.folded)


# Marks what *change* draws differently, or every chunk the walk reads when it
# is wide, and remembers a wide one until the debt is paid. Marked as a reveal:
# a change of the stack moves the layers' places, eyes and properties, which
# an effect layer's stamps read, and a step that also wrote pixels in place,
# a merge or a flatten, holds them in the history, which the stamps read too.
func _mark(document: SaDocument, change: StackChange) -> void:
    _wide = _wide or not change.narrow
    if _wide:
        document.reveal_all_allocated_chunks()
    elif change.drawn.is_empty():
        document.composite_requested.emit()
    else:
        document.reveal_chunks(change.drawn.keys())


## Pays one idle frame's part of what is owed to *document*. A debt of the
## active layer alone builds the walk and folds [member steps_per_frame] of
## its steps, or what [member frame_usec] pays for, and leaves the rest owed to
## the frames after it, so no frame folds the whole stack under a painter who
## stopped to look. Anything else is paid whole, as [method settle] pays it.
func _pay_a_frame(document: SaDocument) -> void:
    var began := Time.get_ticks_usec()
    _build_shown(document)
    _forgive_a_return(document)
    if _owed == Owed.NOTHING or document.active_layer == null:
        return
    if _quiet(document):
        _resolve(document)
        document.fold.rebuild_unpaid(document, document.compositor, _canvas_of(document))
        _owed = Owed.REST
    elif _owed != Owed.REST:
        settle(document)
        return
    var start := Time.get_ticks_usec()
    var traced := SaFrameTrace.now()
    var steps := 0
    while document.fold.is_unpaid() and steps < steps_per_frame and Time.get_ticks_usec() - start < frame_usec:
        document.fold.pay(document, document.compositor, 1)
        steps += 1
    SaFrameTrace.spent("fold pay", traced)
    var drawn := Engine.get_frames_drawn()
    _paid_usec = (_paid_usec if _paid_drawn == drawn else 0) + Time.get_ticks_usec() - began
    _paid_drawn = drawn
    if not document.fold.is_unpaid():
        _owed = Owed.NOTHING
        _draw_held(document)


# Marks every chunk the walk reads at each layer of *shown*, the ids of the
# layers shown or hidden, since what moved, moved at them. Marked at no layer
# when one is nought or has left *document*, since no layer is left to name,
# and as a reveal, since a show or a hide writes no paint and an effect's
# stamps read every eye.
static func _mark_shown(document: SaDocument, shown: Array[int]) -> void:
    var layers: Array[SaLayer] = []
    for id in shown:
        var layer := instance_from_id(id) as SaLayer if id != 0 else null
        if layer == null or layer.get_parent() != document:
            document.reveal_all_allocated_chunks()
            return
        if not layers.has(layer):
            layers.append(layer)
    if layers.is_empty():
        document.reveal_all_allocated_chunks()
        return
    var drawn := _allocated(document)
    for layer in layers:
        document.invalidate_chunks(drawn, layer)


# Every grid position a layer the walk reads holds a chunk at, and every one a
# layer that stores nothing draws over, as `SaDocument.invalidate_all_allocated_chunks`
# gathers them.
static func _allocated(document: SaDocument) -> Array:
    var found: Dictionary[Vector2i, bool] = {}
    for layer in drawn_from(document):
        for grid_pos in layer.chunks:
            found[grid_pos] = true
    for grid_pos in SaGeneratedLayer.covered_positions(document):
        found[grid_pos] = true
    return found.keys()


# Draws the picture a change of what shows held back, once nothing is owed:
# every chunk the walk reads, as `SaDocument.update_caches` marks them.
func _draw_held(document: SaDocument) -> void:
    if not _draws_when_paid or _owed != Owed.NOTHING:
        return
    _draws_when_paid = false
    var shown := _shown
    _shown = []
    var traced := SaFrameTrace.now()
    _mark_shown(document, shown)
    SaFrameTrace.spent("fold invalidate", traced)
    traced = SaFrameTrace.now()
    document.document_changed.emit()
    SaFrameTrace.spent("document_changed", traced)


# A debt of the active layer alone whose layer came back to the one the walk
# was built on is forgiven, down to what a fold over frames left unpaid.
func _forgive_a_return(document: SaDocument) -> void:
    if _owed == Owed.IF_MOVED and document.fold.reads_as_built(document):
        _owed = Owed.REST if document.fold.is_unpaid() else Owed.NOTHING


# Whether what is owed is the active layer alone, which a fold pays and
# nothing need draw.
func _quiet(document: SaDocument) -> bool:
    return _owed == Owed.IF_MOVED and document.compositor != null and document.fold.reads_as_built(document, true)


# What `SaDocument.update_caches` resolves before it folds, for the reason it
# gives.
static func _resolve(document: SaDocument) -> void:
    for child in document.get_children():
        if child is SaLayer:
            (child as SaLayer).resolve_pending()


static func _canvas_of(document: SaDocument) -> Rect2:
    return Rect2(Vector2.ZERO, Vector2(document.canvas_size))


## Called by the fold's build, which pays whatever was owed. A picture a
## change of what shows held back is drawn at the end of the frame when the
## build paid it, whichever build it was: a refold that found the walk moved, a
## whole `SaDocument.update_caches` or the eye's own. Left held, nothing drew
## it, and the next press, which settles, drew every chunk the walk reads.
## Deferred because the build that calls this has not folded yet.
func paid() -> void:
    _shown_due = false
    _owed = Owed.NOTHING
    _wide = false
    if _draws_when_paid:
        _draw_once_paid.call_deferred()


# What [method paid] defers: the held picture drawn, unless a debt owed since
# holds it again, which draws it once that is paid.
func _draw_once_paid() -> void:
    var document := instance_from_id(_owed_to) as SaDocument
    if document != null and document.fold != null and document.fold.debt == self:
        _draw_held(document)


## Whether this frame is an idle one: no button held, and [member quiet_msec]
## since the last debt.
func idle_now() -> bool:
    return Input.get_mouse_button_mask() == 0 and Time.get_ticks_msec() - _owed_at >= quiet_msec


## One frame of the wait: pays its part when this frame is idle, or when a
## fold over frames is under way or holds a picture back, and waits for the
## next frame while anything is owed. A click on a row while the eye's fold is
## under way owes the fold again, and the frames after it go on paying rather
## than wait for an idle one, so the picture the eye asked for is drawn before
## a press and not by it. A frame whose walk took a quarter of it, by
## [method walked], pays in the next. A document outside the tree has no
## frames and no painter, and is paid at once. A suite calls it for each frame
## it cannot wait for.
func frame() -> void:
    var document := instance_from_id(_owed_to) as SaDocument
    if _owed == Owed.NOTHING or document == null or document.fold == null or document.fold.debt != self:
        return
    var tree := document.get_tree() if document.is_inside_tree() else null
    if tree == null:
        settle(document)
        return
    var walk_took_it := _walked_in == Engine.get_process_frames()
    if not walk_took_it and (_owed == Owed.REST or _draws_when_paid or idle_now()):
        _pay_a_frame(document)
    if _owed != Owed.NOTHING and not tree.process_frame.is_connected(frame):
        tree.process_frame.connect(frame, CONNECT_ONE_SHOT)


## What a change of the stack moved since the walk was built: the walk the
## build recorded, `SaLayerFold.walk_of`, read against the walk the document
## reads now. A layer that came, went, moved past the others or is laid
## otherwise moved, and so did the layer the build split at and the one the
## walk splits at now, which leave a cache and join one.
##
## **Narrow** is a change whose picture differs only where the layers that
## moved hold paint, so the fold and the composite are of their chunks. A
## change of anything that draws past its chunks is not: a group, a layer
## that stores nothing, an adjustment or an effect layer, a clip, a layer
## stored finer than the document, a layer with a filter or in a group with
## one, and any effect, lifted or reaching adjustment layer in the stack,
## which reads what is under it, unless all that moved is a plain layer that
## came holding no chunk.
class StackChange:
    extends RefCounted

    ## The layers that moved, by instance id, the two the walk splits at among
    ## them, which a cache that holds one folds again.
    var moved: Dictionary[int, bool] = {}
    ## Where the picture may differ: the chunks of what came, went or moved.
    var drawn: Dictionary[Vector2i, bool] = {}
    ## Where a cache folds again: those, and the chunks of the two the walk
    ## splits at.
    var folded: Dictionary[Vector2i, bool] = {}
    ## Whether the change is one this reads.
    var narrow := false

    func _init(document: SaDocument) -> void:
        narrow = document.fold != null and document.compositor != null and _read(document)

    func _read(document: SaDocument) -> bool:
        var built: Array = document.fold._built_from
        if built.is_empty():
            return false
        var now := SaLayerFold.walk_of(document)
        var chain := document.compositor.filter_chain
        var reads_under := false
        for child in document.get_children():
            var layer := child as SaLayer
            if layer == null:
                continue
            if layer.is_effect() or SaBackdropLayer.lifts(layer) or SaBackdropLayer.reads_around(chain, layer):
                reads_under = true
                break
        var before := built.slice(1)
        var after := now.slice(1)
        var at_before := _places(before)
        var at_after := _places(after)
        _moved_between(before, after, at_before, at_after)
        if reads_under and not _only_empty_came(at_before, before, after):
            return false
        for id: int in moved.keys():
            var layer := instance_from_id(id) as SaLayer
            var place: Array = at_before.get(id, [])
            if layer == null or _draws_past_its_chunks(layer, place, before, after):
                return false
            drawn.merge(_chunks_of(layer))
        folded = drawn.duplicate()
        for id: int in [built[0], now[0]]:
            var split := instance_from_id(id) as SaLayer if id != 0 else null
            if split != null and split.is_group:
                return false
            if split != null and not moved.has(id):
                moved[id] = true
                folded.merge(_chunks_of(split))
        return true

    # Whether every layer that moved is a plain layer that came holding no
    # chunk, which shows nothing, so what reads under it reads what it read
    # before. Without this, a layer added to a stack of hundreds of effect
    # layers would mark the whole picture at no layer, and each effect layer
    # would be drawn again over the next seconds.
    func _only_empty_came(at_before: Dictionary[int, Array], before: Array, after: Array) -> bool:
        if moved.is_empty():
            return false
        for id: int in moved:
            var layer := instance_from_id(id) as SaLayer
            if layer == null or at_before.has(id) or not _chunks_of(layer).is_empty():
                return false
            if _draws_past_its_chunks(layer, [], before, after):
                return false
        return true

    # Each place of *walk* by its layer's instance id.
    static func _places(walk: Array) -> Dictionary[int, Array]:
        var at: Dictionary[int, Array] = {}
        for place: Array in walk:
            at[place[0]] = place
        return at

    # Fills [member moved]: what is in one walk alone, what is laid otherwise,
    # and the fewest layers whose leaving puts the rest in the same order in
    # both, the ones a drop moved.
    func _moved_between(before: Array, after: Array, at_before: Dictionary[int, Array], at_after: Dictionary[int, Array]) -> void:
        var index_after: Dictionary[int, int] = {}
        for i in after.size():
            index_after[after[i][0]] = i
            if not at_before.has(after[i][0]):
                moved[after[i][0]] = true
        var both: Array[int] = []
        for place: Array in before:
            var id: int = place[0]
            if not at_after.has(id):
                moved[id] = true
            elif place.slice(1) != at_after[id].slice(1):
                moved[id] = true
            else:
                both.append(id)
        var order: Array[int] = []
        for id in both:
            order.append(index_after[id])
        var stays := _longest_rising(order)
        for i in both.size():
            if not stays.has(i):
                moved[both[i]] = true

    # The indices of a longest rising run of *order*, not necessarily
    # neighbours, as keys. A stack is a few dozen layers, so the square cost
    # is nothing.
    static func _longest_rising(order: Array[int]) -> Dictionary[int, bool]:
        var length: Array[int] = []
        var back: Array[int] = []
        var best := -1
        for i in order.size():
            length.append(1)
            back.append(-1)
            for j in i:
                if order[j] < order[i] and length[j] + 1 > length[i]:
                    length[i] = length[j] + 1
                    back[i] = j
            if best < 0 or length[i] > length[best]:
                best = i
        var stays: Dictionary[int, bool] = {}
        while best >= 0:
            stays[best] = true
            best = back[best]
        return stays

    # Whether *layer* draws anywhere but its own chunks, or a layer clipped to
    # it stood or stands above it in either walk, *place* its place in the
    # build's.
    static func _draws_past_its_chunks(layer: SaLayer, place: Array, before: Array, after: Array) -> bool:
        if layer.is_group or layer.is_generated() or layer.is_adjustment() or layer.is_effect():
            return true
        if layer.affects_all or layer.clip_to_below or layer.resolution_scale > 1.0 or not layer.filters.is_empty():
            return true
        var groups: Array[SaLayer] = [SaLayerStack.parent_of(layer)]
        if not place.is_empty():
            var group_id: int = place[1]
            groups.append(instance_from_id(group_id) as SaLayer if group_id != 0 else null)
        for group in groups:
            var guard := 0
            while group != null and guard < 64:
                if not group.filters.is_empty():
                    return true
                group = SaLayerStack.parent_of(group)
                guard += 1
        return _a_base(layer, before) or _a_base(layer, after)

    # Whether the place above *layer*'s in *walk* is clipped to it.
    static func _a_base(layer: SaLayer, walk: Array) -> bool:
        var id := layer.get_instance_id()
        for i in walk.size() - 1:
            if walk[i][0] == id:
                return walk[i + 1][5]
        return false

    static func _chunks_of(layer: SaLayer) -> Dictionary[Vector2i, bool]:
        var held: Dictionary[Vector2i, bool] = {}
        for grid_pos: Vector2i in SaLiveTransform.paint_of(layer).chunks:
            held[grid_pos] = true
        return held
