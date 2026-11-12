## The one undo step of a change that puts every layer's chunks and every own
## mask's back at once: a crop, a flip or quarter turn, a resample and a
## projection conversion.
##
## **Undo and redo are one exchange run twice.** What the document holds now
## goes into the step and what the step held goes on, so the same call undoes
## and redoes. The four commands hand their state to this class rather than
## each carrying a copy of the exchange. Each puts the
## state on the document its own way, through the *put* it passes in, because
## a crop keeps the brush's side, a flip keeps the selection and a conversion
## sets the projection, and the swap is only the exchange.
##
## **The state is a dictionary the step keeps.** `SaResidency` finds the
## snapshots a step holds by walking the dictionaries and lists it was handed,
## so the exchange swaps the values of one dictionary in place and hands that
## dictionary to the history, never itself.
##
## **The source rectangle** rides on `SaDocument.resize_source` while the
## resize is told. A crop's moves the origin, so the exchange turns it into the
## inverse at every swap. A resample's is the whole canvas either way and
## stays. A flip and a conversion pass none.
class_name SaCanvasExchange
extends RefCounted

var _document: SaDocument
var _state: Dictionary[String, Variant]
var _put: Callable
# The command *put* belongs to, held so it lives as long as the step does. A
# command is made for one run and a callable keeps no reference to its object,
# so without this the first undo calls into a freed command.
var _command: Object
var _turns_source: bool


## *size*, *chunks* and *masks* are what the document held before the change,
## keyed by layer and by mask. *put* is called with the size, the chunks, the
## masks, the source rectangle and the projection to put on the document, in
## that order, and takes whichever it needs. *projection* is tracked only
## when one is given.
func _init(
    document: SaDocument,
    size: Vector2i,
    chunks: Dictionary[Variant, Dictionary],
    masks: Dictionary[Variant, Dictionary],
    put: Callable,
    source := Rect2i(),
    turns_source := false,
    projection: SaProjection = null
) -> void:
    _document = document
    _put = put
    _command = put.get_object()
    _turns_source = turns_source
    _state = {"size": size, "chunks": chunks, "masks": masks, "source": source}
    if projection != null:
        _state["projection"] = projection


## Records the step under *action*, weighed by the chunks it keeps. Weighed
## through the history's layer pool and not through the state, because
## `SaHistory.bytes_of` walks one layer's grid and this step holds every
## layer's. The released chunks are exactly what that pool is for: tiles a step
## took out of the document and keeps alive. Nothing is recorded on a document
## without a history.
func commit(action: String) -> void:
    if _document.history == null:
        return
    var chunks: Dictionary[Variant, Dictionary] = _state["chunks"]
    var masks: Dictionary[Variant, Dictionary] = _state["masks"]
    var held := bytes_held(chunks) + bytes_held(masks)
    _document.history.commit(action, swap, {}, held, [_state])


## The undo and the redo: what the document holds now goes into the state and
## what the state held goes on.
func swap() -> void:
    var size: Vector2i = _state["size"]
    var chunks: Dictionary[Variant, Dictionary] = _state["chunks"]
    var masks: Dictionary[Variant, Dictionary] = _state["masks"]
    var source: Rect2i = _state["source"]
    var projection: SaProjection = _state.get("projection")
    var displaced: Dictionary[Variant, Dictionary] = {}
    for layer: SaLayer in chunks:
        displaced[layer] = layer.chunks.duplicate()
    var masks_displaced: Dictionary[Variant, Dictionary] = {}
    for mask: SaMask in masks:
        masks_displaced[mask] = mask.chunks.duplicate()
    var was := _document.canvas_size
    _state["size"] = was
    _state["chunks"] = displaced
    _state["masks"] = masks_displaced
    if _turns_source:
        # The inverse of the move being made, for whichever of undo and redo
        # comes next: the document being put away sits at minus this
        # rectangle's origin, at the size it is now rather than the size being
        # restored.
        _state["source"] = Rect2i(-source.position, was)
    if projection != null:
        _state["projection"] = _document.projection
    _put.call(size, chunks, masks, source, projection)


## What every layer's and own mask's snapshot holds, in bytes of VRAM.
static func bytes_held(chunks: Dictionary[Variant, Dictionary]) -> int:
    var total := 0
    for owner: Variant in chunks:
        for grid_pos: Vector2i in chunks[owner]:
            var chunk: SaChunk = chunks[owner][grid_pos]
            if chunk != null:
                total += chunk.byte_size()
    return total
