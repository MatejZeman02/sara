## A shared source: the paint two or more smart layers are drawn from, each
## through a map of its own, so one edit to it shows in every one of them.
## Sharing is a command of its own, the source acts like a shared pointer, and
## a user can be made independent again.
##
## **What is shared.** The one chunk dictionary every user holds as its own
## `SaLayer.chunks`, so a stroke, a fill and an undo written into any user's
## chunks are written into the source, by the doors a layer always had. A
## user's map, crop, opacity, blend mode, mask and filters stay its own, since
## they are members of the layer and of its `SaLiveTransform`, and only the
## paint is shared.
##
## **Who is told.** Each user's live transform holds this object, set in its
## constructor, and hands it every position its layer says moved, which this
## passes to every other user's transform, so each one resamples its cache at
## that position and nowhere else. A user taken out of the document stays a
## user, so its undo brings it back sharing with nothing owed.
##
## **A shared pointer.** Nothing counts users. The source lives while any
## user's transform holds it and goes with the last, which `RefCounted` does,
## and a user's layer frees its own reference to the dictionary rather than
## clearing it, `SaLayer._notification`, so a deleted user that the history
## lets go never empties the others. Convert to Ordinary Layer and a merge into
## a user take the transform off first, which hands that layer a copy of its
## own, [method relink], so they bake that layer's picture alone.
##
## **The two commands.** Share Source with a Copy, [method link], and
## Make Source Independent, [method make_independent], each one history step.
class_name SaSharedSource
extends RefCounted

## The key each user's `.sad` entry names its source under: the name of the
## user whose entry holds the chunks, the first user in the document's order.
const KEY := "source"
## The name Share Source with a Copy takes in the history and in the corner.
const LINK := "Share Source with a Copy"
## The name Make Source Independent takes in the history and in the corner.
const UNLINK := "Make Source Independent"

## The chunks every user holds as its `chunks`, one dictionary. Set in the
## constructor and never replaced.
var chunks: Dictionary[Vector2i, SaChunk] = {}

## The layers that have held this source, weakly, so a freed one drops out.
var _users: Array[WeakRef] = []
## Whether a change is being passed on, so a user's own change told back to
## this object is heard once.
var _telling := false


func _init(held: Dictionary[Vector2i, SaChunk]) -> void:
    chunks = held


## The shared source *layer* is drawn from, or null for a layer that holds its
## paint alone.
static func of(layer: SaLayer) -> SaSharedSource:
    var live := SaLiveTransform.of(layer)
    return live.source if live != null else null


## Every layer drawn from this source, in or out of a document, bottom first
## for those in one.
func users() -> Array[SaLayer]:
    var found: Array[SaLayer] = []
    for held: WeakRef in _users:
        var object: Object = held.get_ref()
        var layer := object as SaLayer
        if layer != null and of(layer) == self:
            found.append(layer)
    found.sort_custom(func(a: SaLayer, b: SaLayer) -> bool: return a.get_index() < b.get_index())
    return found


## The users *document* holds, bottom first, which is the order a save writes
## them in.
func users_in(document: SaDocument) -> Array[SaLayer]:
    return users().filter(func(layer: SaLayer) -> bool: return layer.get_parent() == document)


## Tells every user that its paint changed at *grid_pos*, which the transform
## of the user it changed through calls from its own `moved`.
func moved(grid_pos: Vector2i) -> void:
    _tell(func(live: SaLiveTransform) -> void: live.moved(grid_pos))


## Tells every user its paint may have changed anywhere.
func moved_all() -> void:
    _tell(func(live: SaLiveTransform) -> void: live.moved_all())


func _tell(say: Callable) -> void:
    if _telling:
        return
    _telling = true
    for layer in users():
        say.call(SaLiveTransform.of(layer))
    _telling = false


## Points *layer*'s chunks at the source *live* draws from, which `SaLiveTransform`
## calls each time it puts *live* on in place of *before*. A layer leaving a
## source gets a copy of its chunks of its own, so what it is written next
## reaches no other user, and one joining a source holds its chunks.
static func relink(layer: SaLayer, before: SaLiveTransform, live: SaLiveTransform) -> void:
    var left: SaSharedSource = before.source if before != null else null
    var joined: SaSharedSource = live.source if live != null else null
    if left == joined:
        return
    if left != null and is_same(layer.chunks, left.chunks):
        var own: Dictionary[Vector2i, SaChunk] = {}
        for grid_pos: Vector2i in left.chunks:
            own[grid_pos] = layer.duplicate_chunk(grid_pos)
        layer.chunks = own
    if joined != null:
        layer.chunks = joined.chunks
        joined._join(layer)


func _join(layer: SaLayer) -> void:
    for held: WeakRef in _users:
        if held.get_ref() == layer:
            return
    _users.append(weakref(layer))


## A transform at *live*'s map and crop, smart, drawn from *source*, or from
## none for null.
static func _drawn_from(live: SaLiveTransform, source: SaSharedSource) -> SaLiveTransform:
    return SaLiveTransform.new(live.matrix, live.crop, true, source)


## Layer > Share Source with a Copy: a copy of smart *layer* above it
## drawn from the same source, at the same map, with its own name, opacity,
## mode, mask and filters, as one history step. The copy is the active layer
## after it and is answered, or null with the reason in the corner for a layer
## that is not smart or whose transform cannot change.
static func link(document: SaDocument, layer: SaLayer) -> SaLayer:
    var live := SaLiveTransform.of(layer)
    if document == null or live == null:
        var named := String(layer.name) if layer != null else ""
        SaProblems.refuse(LINK, TranslationServer.translate("'%s' is not a smart layer. Make it one first.") % named)
        return null
    var why := SaLiveTransform.refusal(document, layer, live.matrix)
    if not why.is_empty():
        SaProblems.refuse(LINK, TranslationServer.translate("The layer cannot be shared. %s") % why)
        return null
    var made: Array[SaLayer] = []
    document.history.as_one(LINK, _place_linked.bind(document, layer, made))
    return made[0] if not made.is_empty() else null


## [method link] as the menu's command runs it, answering whether it made a copy.
static func share(document: SaDocument, layer: SaLayer) -> bool:
    return link(document, layer) != null


## The work of [method link]: the source put on *layer* when it has none, then
## its copy placed above it, holding the source, recorded as an added layer.
static func _place_linked(document: SaDocument, layer: SaLayer, made: Array[SaLayer]) -> void:
    var live := SaLiveTransform.of(layer)
    var source := live.source
    if source == null:
        source = SaSharedSource.new(layer.chunks)
        SaLiveTransform.put_step(document, layer, _drawn_from(live, source), LINK)
    var ops := SaLayerOps.new(document)
    var block := SaLayerDuplicate.new(document).place(layer)
    if block.is_empty():
        return
    var copy := block[-1]
    var before := SaLiveTransform.of(copy)
    copy.live_transform = _drawn_from(live, source)
    relink(copy, before, SaLiveTransform.of(copy))
    document.set_active_layer(copy)
    ops.commit_added(LINK, block)
    made.append(copy)


## Whether *layer* shares its source with another layer, which is what lights
## Layer > Make Source Independent. Quiet, because the menu asks it on every open.
static func can_unlink(layer: SaLayer) -> bool:
    var source := of(layer)
    return source != null and source.users().size() > 1


## Layer > Make Source Independent: gives *layer* a copy of its source of its
## own, as one history step, and answers whether it did. It stays a smart layer
## at its map, an edit to the source no longer reaches it, and the other users
## still share theirs. The undo puts it back on the source. A layer that shares
## nothing, or whose transform cannot change, says why in the corner.
static func make_independent(document: SaDocument, layer: SaLayer) -> bool:
    var live := SaLiveTransform.of(layer)
    if not can_unlink(layer):
        var named := String(layer.name) if layer != null else ""
        SaProblems.refuse(UNLINK, TranslationServer.translate("'%s' shares its source with no other layer.") % named)
        return false
    var why := SaLiveTransform.refusal(document, layer, live.matrix)
    if not why.is_empty():
        SaProblems.refuse(UNLINK, TranslationServer.translate("The source cannot be made independent. %s") % why)
        return false
    SaLiveTransform.put_step(document, layer, _drawn_from(live, null), UNLINK)
    return true


## The names of the layers of *layer*'s document drawn from its source, bottom
## first, *layer* among them, and empty for a layer that shares nothing. What
## the layers report says under `"source"`.
static func names_sharing(layer: SaLayer) -> Array[String]:
    var names: Array[String] = []
    var source := of(layer)
    var document := layer.get_parent() as SaDocument if layer != null else null
    if source == null or document == null:
        return names
    var sharing := source.users_in(document)
    if sharing.size() < 2:
        return names
    for user in sharing:
        names.append(String(user.name))
    return names


## Writes the name of the user whose entry holds the source's chunks into
## *layer*'s entry *layer_dict*, when another layer of its document shares it,
## and nothing otherwise, so a file with no shared source is the file it was.
static func write_header(layer: SaLayer, layer_dict: Dictionary[String, Variant]) -> void:
    var names := names_sharing(layer)
    if not names.is_empty():
        layer_dict[KEY] = names[0]


## Whether *layer*'s entry holds the source's chunks: it holds its paint alone,
## or it is the first user its document holds. The other users' entries hold
## none, so a save stores a shared source once.
static func keeps_chunks(layer: SaLayer) -> bool:
    var names := names_sharing(layer)
    return names.is_empty() or names[0] == String(layer.name)


## Notes the name *layer_data* says *layer*'s source is kept under, for
## [method join] once every layer of the file is in its document.
static func read_header(layer: SaLayer, layer_data: Dictionary[String, Variant]) -> void:
    var keeper := SaTyped.text_at(layer_data, KEY, "")
    if not keeper.is_empty() and SaLiveTransform.of(layer) != null:
        layer.set_meta(KEY, keeper)


## Puts every layer of a loaded *document* whose entry named a source on the
## chunks of the layer it named, one source to each name. A name no smart layer
## of the document has leaves the layer holding what its entry held.
static func join(document: SaDocument) -> void:
    var by_name: Dictionary[String, SaLayer] = {}
    var named: Array[SaLayer] = []
    for child in document.get_children():
        var layer := child as SaLayer
        if layer == null:
            continue
        by_name[String(layer.name)] = layer
        if layer.has_meta(KEY):
            named.append(layer)
    var sources: Dictionary[String, SaSharedSource] = {}
    for layer in named:
        var keeper_name := str(layer.get_meta(KEY))
        layer.remove_meta(KEY)
        var keeper: SaLayer = by_name.get(keeper_name, null)
        if keeper == null or SaLiveTransform.of(keeper) == null:
            continue
        if not sources.has(keeper_name):
            sources[keeper_name] = SaSharedSource.new(keeper.chunks)
        var before := SaLiveTransform.of(layer)
        layer.live_transform = _drawn_from(before, sources[keeper_name])
        relink(layer, before, SaLiveTransform.of(layer))
