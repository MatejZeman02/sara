## What an owner hides: single-channel coverage, one where nothing was painted
## into it, and the one door every reader of a mask goes through.
##
## A mask is not a filter: it is attached to a layer or a filter, so it is
## never a node of the layer tree.
## It belongs to its owner, and the owners keep it in two different stores:
##
## - `of_layer(layer)` is the field form. The coverage is the `SaFieldSpec.MASK`
##   field of the layer's own chunks, so it is saved, duplicated and undone with
##   the paint it hides, and a chunk exists only where the layer has one.
## - `own()` holds chunks of its own, for an owner that stores no paint: a group
##   and an attached filter's record.
##
## Nothing outside this file asks which form it has. Both answer null for a grid
## position they hold nothing at, and that position reads as `rest`, one unless
## an operation said otherwise. A reader asks `coverage`, which answers null
## where the mask reads one, and takes null, a mask that is switched off and no
## mask at all as the same answer: the owner shows whole. That is what keeps
## hard rule 3 over a mask, because a chunk is then allocated only where the
## coverage differs from the rest.
##
## Not persisted by itself. `SaSadFile.write_mask` and `SaSadFile.read_mask` are
## the two doors to disk, for both forms.
class_name SaMask
extends RefCounted

## Whether the mask hides anything just now. Off, the owner shows whole and the
## coverage is kept for when it comes back on.
var enabled: bool = true

## The field form's store: the layer whose chunks carry the field. Null in the
## own form. A `Node`, so holding it is no reference cycle, and a mask that
## outlives its layer answers as an empty one.
var layer: SaLayer = null

## The own form's store, grid position to a chunk of the one field. Empty and
## unused in the field form.
var chunks: Dictionary[Vector2i, SaChunk] = {}

## What a position the mask holds no chunk at reads as, one or zero. A group or
## a record masked from a selection reads zero outside it and holds chunks only
## where the selection does, and an invert flips this and the chunks rather
## than filling the canvas. In the field form a position with no chunk has no
## paint to hide, and the rest is what a chunk the layer allocates there later
## opens its field at, so paint outside the chunks a mask from a selection
## found stays hidden.
var rest: float = 1.0

var _absent: SaTexture = null
var _absent_value: float = 1.0


func _init(of: SaLayer = null) -> void:
    layer = of


## The mask that is a field of *of*'s chunks. The layer's schema has to carry
## the field already, which `SaLayer.add_mask` sees to.
static func of_layer(of: SaLayer) -> SaMask:
    return SaMask.new(of)


## A mask that holds its own chunks, for an owner with no paint of its own.
static func own() -> SaMask:
    return SaMask.new()


## Whether this mask keeps chunks of its own rather than a layer's field.
func is_own() -> bool:
    return layer == null


## The schema of an own chunk: the one field, at the selection's format.
static func schema() -> Array[SaFieldSpec]:
    var fields: Array[SaFieldSpec] = [SaFieldSpec.mask()]
    return fields


## The coverage at *grid_pos*, or null where the mask holds nothing, which reads
## as one. Whether the mask is enabled is the reader's question, not this one's:
## an operation on a mask that is switched off still finds its texels.
func texture_for(grid_pos: Vector2i) -> SaTexture:
    var chunk := _chunk_at(grid_pos)
    return chunk.field(SaFieldSpec.MASK) if chunk != null else null


## What a reader binds at *grid_pos*: the coverage held there, the 1 by 1
## texture of `rest` where nothing is held and the rest is not one, and null
## where the position reads one, which a reader skips. Whether the mask is
## enabled is the reader's question, as it is for `texture_for`.
func coverage(grid_pos: Vector2i) -> SaTexture:
    var held := texture_for(grid_pos)
    if held != null:
        return held
    return absent() if rest < 1.0 else null


## The coverage at *grid_pos*, allocated at the rest when it is new, so a new
## chunk reads what the position read before it. For whoever is about to write
## into it. In the field form this allocates the layer's chunk, every field of
## it, because a chunk is the unit a layer stores.
func get_or_create(grid_pos: Vector2i) -> SaTexture:
    if is_own():
        var chunk: SaChunk = chunks.get(grid_pos, null)
        if chunk == null:
            chunk = SaChunk.create(schema())
            var at_rest := Color(rest, rest, rest, rest)
            chunk.blanks[SaFieldSpec.MASK] = at_rest
            chunk.clear(at_rest)
            chunks[grid_pos] = chunk
        return chunk.field(SaFieldSpec.MASK)
    if not is_instance_valid(layer):
        return null
    return layer.get_or_create_chunk(grid_pos).field(SaFieldSpec.MASK)


## Every grid position the mask holds coverage at.
func grid_positions() -> Array[Vector2i]:
    var positions: Array[Vector2i] = []
    var store: Dictionary[Vector2i, SaChunk] = _store()
    for grid_pos: Vector2i in store:
        var chunk: SaChunk = store[grid_pos]
        if chunk != null and chunk.has_field(SaFieldSpec.MASK):
            positions.append(grid_pos)
    return positions


## The 1 by 1 coverage that reads as `rest` everywhere, what a kernel binds
## through a clamped fetch where `texture_for` answered null. Cleared again when
## the rest moved since it was last asked. Owned here rather than a static, so
## it is freed with the document and not against a device already gone.
func absent() -> SaTexture:
    if _absent == null:
        _absent = SaTexture.new(Vector2i(1, 1), SaSelection.FORMAT)
        _absent_value = -1.0
    if _absent_value != rest:
        _absent.clear(Color(rest, rest, rest, rest))
        _absent_value = rest
    return _absent


## A VRAM copy of the coverage at *grid_pos* and of nothing else, for an undo
## entry. Null where the mask holds nothing, which is an entry that says so.
func duplicate_chunk(grid_pos: Vector2i) -> SaChunk:
    var chunk := _chunk_at(grid_pos)
    if chunk == null or not chunk.has_field(SaFieldSpec.MASK):
        return null
    return chunk.duplicate_chunk(SaFieldSpec.MASK)


## Puts a captured copy back, which is how undo and redo restore a mask. Null
## means the mask held nothing there. In the own form the chunk goes. In the
## field form the layer's chunk stays, because its paint is not the mask's to
## remove, and its coverage goes back to the rest, which reads the same as
## nothing.
func set_chunk(grid_pos: Vector2i, chunk: SaChunk) -> void:
    if is_own():
        if chunk == null:
            chunks.erase(grid_pos)
        else:
            chunks[grid_pos] = chunk
        return
    if not is_instance_valid(layer):
        return
    var captured: SaTexture = chunk.field(SaFieldSpec.MASK) if chunk != null else null
    if captured == null:
        var held: SaChunk = layer.chunks.get(grid_pos, null)
        if held != null and held.has_field(SaFieldSpec.MASK):
            held.field(SaFieldSpec.MASK).clear(Color(rest, rest, rest, rest))
        return
    var target := layer.get_or_create_chunk(grid_pos)
    target.fields[SaFieldSpec.MASK] = captured
    target.blanks[SaFieldSpec.MASK] = SaFieldSpec.SHOWN


## Exchanges what the mask holds with what *state* holds, and *state* keeps what
## came off, so one Dictionary is both directions of a step. An entry is an
## `SaChunkDelta` over the part of a chunk a stroke painted, a whole chunk, or
## null where the mask held nothing. It mirrors `SaDocument.swap_pixels` rather
## than widening it, because that one is on the path of every stroke in Sara and
## a mask is not a layer. *document*, when given, is told which chunks moved, so
## the canvas redraws them.
func swap_chunks(state: Dictionary[Vector2i, Variant], document: SaDocument = null) -> void:
    for grid_pos: Vector2i in state.keys():
        var stored: Variant = state[grid_pos]
        if stored is SaChunkDelta:
            var live: SaChunk = _chunk_at(grid_pos) if get_or_create(grid_pos) != null else null
            if live == null:
                continue
            var delta: SaChunkDelta = stored
            state[grid_pos] = SaChunkDelta.capture(live, delta.rect)
            delta.apply_to(live)
            continue
        var current := duplicate_chunk(grid_pos)
        var whole: SaChunk = stored
        set_chunk(grid_pos, whole)
        state[grid_pos] = current
    if document != null:
        document.mask_moved(self, state.keys())


## Commits *state*, the mask as it stood before, as one history step on
## *document* that `swap_chunks` runs in both directions. A stroke on a mask
## comes here whichever store the mask keeps, and so do an operation on a
## group's mask and on an attached filter's.
func record_step(document: SaDocument, action_name: String, state: Dictionary[Vector2i, Variant]) -> void:
    if document == null or document.history == null:
        return
    document.history.commit(action_name, swap_chunks.bind(state, document), state)


## The layer of *document* this mask hides: the layer whose field it is, or the
## layer or group that holds it or holds the attached filter it masks. Null for
## a mask no layer of the document holds, a root filter's among them. What a
## change of the mask names as the layer it moved at.
func holder_in(document: SaDocument) -> SaLayer:
    if not is_own():
        return layer if is_instance_valid(layer) else null
    for child in document.get_children():
        var holder := child as SaLayer
        if holder == null:
            continue
        if holder.mask == self:
            return holder
        for record: SaAttachedFilter in holder.filters:
            if record.mask == self:
                return holder
    return null


func _store() -> Dictionary[Vector2i, SaChunk]:
    if is_own():
        return chunks
    if is_instance_valid(layer):
        return layer.chunks
    return {}


func _chunk_at(grid_pos: Vector2i) -> SaChunk:
    return _store().get(grid_pos, null)
