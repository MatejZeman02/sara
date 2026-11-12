## Where each effect layer's cache is known to hold its input as the input
## stands, so a refresh owed to a reveal skips the chunks nothing has moved. A
## view change marks every chunk dirty at no layer to show what the window now
## reaches, and so does a reorder or a show of a layer the fold owes for: on
## a large painting each of them drew all 219 effect layers over every chunk
## again, 260 to 626 ms of one frame, for caches that already held what they
## would draw.
##
## **Only a reveal is skipped.** A mark at no layer counts as a change below
## every layer, and a module that paints a chunk it already held in place and
## marks it at no layer moves no identity this can read. So the callers that
## mark and move nothing call `SaDocument.reveal_all_allocated_chunks`, the
## document keeps where only they marked as `SaDocument.still`, and the
## stamps are asked over those positions alone. Every other mark at no layer
## is drawn again.
##
## **A stamp** is kept for an effect at a chunk when a refresh wrote the whole
## chunk there, or dropped it because the input shows nothing: the input's
## signature at that moment and the cache chunk the effect then held. A refresh
## that reaches the chunk at no layer skips it while both still match, and one
## that wrote part of the chunk forgets the stamp, since the rest of the chunk
## was drawn from an input that may have stood otherwise.
##
## **The signature** of a node is everything its composite is drawn from: its
## mode, opacity, visibility, clip and lock of alpha, the revision, switch and
## mask of each record, its own mask, its chunks by identity, and for a group
## each member's signature in the stack's order. Paint written in place moves
## no identity, so each layer carries a count of the times it moved: the
## layers the document names as moved at, and every pixel step, which says so
## through `paint_recorded` and is marked at no layer by a filter's apply. An
## effect layer's own chunks are left out, because every write a refresh makes
## to one is handed on to the effects that read it in the same refresh, see
## `SaEffectLayer._spread`, so a reader's cache never waits on another's.
##
## **What is never skipped.** A node drawn through a live transform, a
## simulation, a scene or a generator is drawn from more than this can see, so
## an input holding one is always refreshed, and so is every effect while a
## dialog previews a pass on the active layer. A history step that moved no
## signature anywhere in the stack wrote something in place that nothing named,
## so every stamp of that document is forgotten, and so is every stamp when
## the history crossed a step that holds pixels no layer said it moved for, a
## merge's, which only a reveal follows.
class_name SaEffectStamps
extends RefCounted

## Effect instance id -> grid position -> [the input's signature, the instance
## id of the cache chunk, 0 for none].
var _stamps: Dictionary[int, Dictionary] = {}
## Layer instance id -> how many times its paint moved in place.
var _moves: Dictionary[int, int] = {}
## The layer instance ids whose `paint_recorded` this counts.
var _heard: Dictionary[int, bool] = {}
## How many moves in place at a layer of a document were heard since the last
## [method begin], each the most pixel steps it can account for.
var _announced := 0
## Document instance id -> [history position, the whole stack's signature, the
## document's own key], as the last refresh found them.
var _seen: Dictionary[int, Array] = {}
## For the refresh under way: each group's members in the stack's order, the
## signatures found so far, and whether a stamp may be trusted at all.
var _members: Dictionary[SaLayer, Array] = {}
var _known: Dictionary[SaLayer, int] = {}
var _trusted := false
var _registry: SaFilterRegistry = null


## Readies one refresh of *document* by *compositor*, and forgets every stamp
## of the document when its history moved and no signature in it did.
func begin(document: SaDocument, compositor: SaCompositor) -> void:
    _members = {}
    _known = {}
    _registry = compositor.filter_chain.registry
    for child in document.get_children():
        var layer := child as SaLayer
        var group := SaLayerStack.parent_of(layer) if layer != null else null
        if group != null:
            var members: Array = _members.get_or_add(group, [])
            members.append(layer)
    _trusted = compositor.point_preview.for_document(document) == null
    var position := document.history.position() if document.history != null else 0
    var key := hash(
        [
            document.color_space.get_instance_id(),
            document.color_space.texel_format(),
            document.canvas_size,
            document.projection.wrapping,
        ]
    )
    var id := document.get_instance_id()
    var seen: Array = _seen.get(id, [])
    var announced := _announced
    _announced = 0
    if not seen.is_empty() and seen[0] == position and seen[2] == key:
        return
    var whole := _whole(document)
    var heard_up_to: int = seen[0] if not seen.is_empty() else position
    if seen.is_empty() or seen[2] != key or seen[1] == whole or _unheard(document.history, heard_up_to, position, announced):
        _forget(document)
    _seen[id] = [position, whole, key]


## Counts a move in place at each layer *ids* names, instance ids as
## `SaDocument.moved_at` keys them. A layer still in a document announces a
## step's pixels, and one taken out, a merge's upper layer, does not.
func moved(ids: Array) -> void:
    for id: int in ids:
        _moves[id] = _moves.get(id, 0) + 1
        var layer := instance_from_id(id) as SaLayer
        if layer != null and layer.get_parent() is SaDocument:
            _announced += 1


## The part of *regions*, grid position to Rect2i, that *effect* still owes:
## every region but those in *still*, the positions only a reveal marked, over
## a chunk whose stamp matches its input as it stands.
func owed(
    effect: SaLayer, regions: Dictionary[Vector2i, Rect2i], still: Dictionary[Vector2i, bool]
) -> Dictionary[Vector2i, Rect2i]:
    var mine: Dictionary = _stamps.get(effect.get_instance_id(), {})
    if not _trusted or mine.is_empty() or still.is_empty():
        return regions.duplicate()
    var now := _input(effect)
    var left: Dictionary[Vector2i, Rect2i] = {}
    for grid_pos: Vector2i in regions:
        var held: Array = mine.get(grid_pos, [])
        if not still.has(grid_pos) or now == 0 or held.is_empty() or held[0] != now or held[1] != _chunk_id(effect, grid_pos):
            left[grid_pos] = regions[grid_pos]
    return left


## Keeps what a refresh wrote into *effect* at *grid_pos*: a stamp when *whole*,
## the cache there drawn whole from the input as it stands, and none otherwise.
func stamp(effect: SaLayer, grid_pos: Vector2i, whole: bool) -> void:
    var id := effect.get_instance_id()
    var now := _input(effect) if whole and _trusted else 0
    if now == 0:
        if _stamps.has(id):
            _stamps[id].erase(grid_pos)
        return
    var mine: Dictionary = _stamps.get_or_add(id, {})
    mine[grid_pos] = [now, _chunk_id(effect, grid_pos)]


## The signature of what *effect* draws its cache from, 0 when it cannot be
## trusted.
func _input(effect: SaLayer) -> int:
    var source := SaEffectLayer.input_of(effect)
    var alone := SaEffectLayer.reads_paint_alone(effect, _registry)
    if source == null:
        return hash([0, alone])
    var of := signature(source)
    return 0 if of == 0 else hash([source.get_instance_id(), alone, of])


## The signature of *node*, 0 when something it draws from is beyond it.
func signature(node: SaLayer) -> int:
    if _known.has(node):
        return _known[node]
    var parts: Array = []
    var trusted := _parts(node, parts)
    if node.is_group and trusted:
        for member: SaLayer in _members.get(node, []):
            var of := signature(member)
            if of == 0:
                trusted = false
                break
            parts.append(of)
    var found := hash(parts) if trusted else 0
    if found == 0 and trusted:
        found = 1
    _known[node] = found
    return found


## Appends what *node* is drawn from, its members aside, to *parts*, and
## answers false for a node drawn from more than this sees.
func _parts(node: SaLayer, parts: Array) -> bool:
    var id := node.get_instance_id()
    if not _heard.has(id):
        node.paint_recorded.connect(_painted.bind(id))
        _heard[id] = true
    (
        parts
        . append_array(
            [
                id,
                node.visible,
                node.opacity,
                node.blend_mode,
                node.clip_to_below,
                node.alpha_locked,
                node.isolated,
                node.affects_all,
                node.resolution_scale,
                node.layer_type,
                node.input,
                node.source.get_instance_id() if node.source != null else 0,
                _moves.get(id, 0),
                _mask(node.mask),
            ]
        )
    )
    for record in node.filters:
        if record != null:
            parts.append_array([record.key, record.revision, record.enabled, _mask(record.mask)])
    if not node.is_effect():
        parts.append(_chunks(node.chunks))
    return node.live_transform == null and node.simulation == null and node.scene == "" and not node.is_generated()


func _painted(_grid_positions: Array, id: int) -> void:
    _moves[id] = _moves.get(id, 0) + 1
    _announced += 1


static func _mask(mask: SaMask) -> int:
    if mask == null:
        return 0
    return hash([mask.enabled, mask.rest, _chunks(mask.chunks)])


## The positions and identities of *chunks*, in the order they are held.
static func _chunks(chunks: Dictionary) -> int:
    var ids := PackedInt64Array()
    for grid_pos: Vector2i in chunks:
        var chunk: Object = chunks[grid_pos]
        ids.append(grid_pos.x)
        ids.append(grid_pos.y)
        ids.append(chunk.get_instance_id() if chunk != null else 0)
    return hash(ids)


static func _chunk_id(effect: SaLayer, grid_pos: Vector2i) -> int:
    var chunk: SaChunk = effect.chunks.get(grid_pos)
    return chunk.get_instance_id() if chunk != null else 0


## What every node of *document* is drawn from, a node beyond the signatures
## among them, each with the group it stands in, in the stack's order.
func _whole(document: SaDocument) -> int:
    var parts: Array = []
    for child in document.get_children():
        var layer := child as SaLayer
        if layer != null:
            var group := SaLayerStack.parent_of(layer)
            parts.append(group.get_instance_id() if group != null else 0)
            _parts(layer, parts)
    return hash(parts)


## Whether *history* crossed more steps that hold pixels between the serials
## *from* and *to*, either way, than *announced* moves in place account for,
## or cannot say. A merge or a flatten writes its lower layer in place and
## marks only through the fold's debt, a reveal, so the step's snapshot is
## what says the paint moved. A stroke, a filter's apply and the undo of
## either name their layer, which moves its signature.
static func _unheard(history: SaHistory, from: int, to: int, announced: int) -> bool:
    if history == null or from == to:
        return false
    var low := mini(from, to)
    var high := maxi(from, to)
    var ends := 0
    for end: int in [low, high]:
        if end == history.base_serial or history.step_serials.has(end):
            ends += 1
    if ends < 2:
        return true
    var crossed := 0
    for i in history.step_serials.size():
        var serial: int = history.step_serials[i]
        if serial > low and serial <= high and history._step_bytes[i] > 0:
            crossed += 1
    return crossed > announced


## Drops the stamps of every effect of *document*, and of effects gone.
func _forget(document: SaDocument) -> void:
    for effect in SaEffectLayer.effects_of(document):
        _stamps.erase(effect.get_instance_id())
    for id: int in _stamps.keys():
        if not is_instance_id_valid(id):
            _stamps.erase(id)
