## Past the budget, the chunks of the layers nobody is painting on move to RAM,
## and come back before anything reads them.
##
## Eviction reads back as a kind of its own under hard rule 1, never during a
## stroke, and an evicted chunk goes to RAM compressed with the
## Zstd the save uses. This file is the one that reads a chunk back for it, and
## the one `READBACK_ALLOWED` names for it.
## A drawn layer's chunk is read back by nobody: `SaDrawnLayer.let_go` gives
## its textures up, and its recipe draws it again when a reader meets it.
##
## **When.** `SaDocument.begin_stroke` calls [method press] and the end of its
## `commit_stroke` [method release], and the release settles the document: while
## `SaCardMemory.held()`, every texture Sara holds on the card, is over
## `SaMemoryBudget.budget()`, the history's snapshots go to RAM first, the
## oldest step's first, with the chunks a step keeps beyond its snapshots
## (`history_entries`), and only once none is left on the card the chunks of
## the document's layers, the least recently drawn layer's first, by
## `SaLayer.drawn_at`. The layer the document paints on and its mask stay whole. While any document holds a
## stroke from press to release, nothing is evicted and nothing is read back.
##
## **Coming back** is the chunk's own business, the getter of `SaChunk.fields`,
## so every reader of a chunk's pixels finds its textures there again, and a
## snapshot's alike, the getter of `SaChunkDelta.fields` or of the whole chunk
## the snapshot is, which an undo or a redo reads before it puts it back.
##
## The history's snapshots go first because they are the chunks a painter is least likely to need soon,
## so a long history costs RAM rather than VRAM. Which steps the history keeps
## is its own business, so RAM holds only what it already kept.
##
## Measured by the card's whole figure rather than the documents' accounting
## alone, because the budget is a share of the card and the fold's caches and
## the history hold memory there too that no eviction of layers can give back.
## Which layer goes first is read from the layers themselves.
class_name SaResidency
extends RefCounted

## How many textures this file has read back since Sara started.
static var readbacks: int = 0

## Instance id of every document between a press and its release.
static var _held: Dictionary[int, bool] = {}

## Instance id of every document [method spare] was told of.
static var _spared: Dictionary[int, bool] = {}


## Leaves *document*'s chunks on the card whatever the budget. For a document
## made to draw one picture and be let go of, a preset's thumbnail, whose
## every composite reads its layers whole: an eviction there is read back at
## the release only to be uploaded again by the composite after it.
static func spare(document: SaDocument) -> void:
    if document != null:
        _spared[document.get_instance_id()] = true


## Opens a stroke on *document*, which holds every eviction back until its
## release and records the layer it paints on as drawn now.
static func press(document: SaDocument) -> void:
    if document == null:
        return
    _held[document.get_instance_id()] = true
    if document.active_layer != null:
        document.active_layer.note_drawn()


## Closes *document*'s stroke and settles it against the budget.
static func release(document: SaDocument) -> void:
    if document == null:
        return
    _held.erase(document.get_instance_id())
    for id: int in _spared.keys():
        if not is_instance_id_valid(id):
            _spared.erase(id)
    if not _spared.has(document.get_instance_id()):
        settle(document)


## Whether some document holds a stroke between its press and its release.
## A document freed with its stroke open, which a reset or a close can do,
## holds nothing back.
static func stroke_held() -> bool:
    for id: int in _held.keys():
        if not is_instance_id_valid(id):
            _held.erase(id)
    return not _held.is_empty()


## Moves chunks of *document*'s layers to RAM while the card holds more than
## *budget* bytes, `SaMemoryBudget.budget()` when left at -1, and answers how
## many it moved. Nothing moves during a stroke, under a budget of 0 or while
## the card holds less.
static func settle(document: SaDocument, budget: int = -1) -> int:
    if budget < 0:
        budget = SaMemoryBudget.budget()
    if document == null or budget <= 0 or stroke_held():
        return 0
    if SaCardMemory.held() <= budget:
        return 0
    var moved := 0
    var held_before := SaCardMemory.held()
    for entry: Variant in history_entries(document):
        if SaCardMemory.held() <= budget:
            break
        if evict_snapshot(entry):
            moved += 1
    for layer: SaLayer in candidates(document):
        for chunks: Dictionary in _chunk_sets(layer):
            for grid_pos: Vector2i in chunks:
                if SaCardMemory.held() <= budget:
                    break
                # A drawn layer's chunk is let go unread, its recipe drawing it again.
                var chunk: SaChunk = chunks[grid_pos]
                if SaDrawnLayer.let_go(layer, grid_pos, chunk) or evict(chunk):
                    moved += 1
    if moved > 0:
        print(line(moved, held_before - SaCardMemory.held(), budget))
    return moved


## The log's line for an eviction of *moved* chunks that gave back *freed*
## bytes of the card under a budget of *budget* bytes.
static func line(moved: int, freed: int, budget: int) -> String:
    return (
        (
            "SaResidency: %d chunks to RAM, %.1f MiB off the card, %d chunks in RAM in %.1f MiB,"
            + " %d snapshot pieces in RAM in %.1f MiB, the card holds %.1f MiB of a budget of %.1f MiB"
        )
        % [
            moved,
            _mib(freed),
            SaChunk.stored_count,
            _mib(SaChunk.stored_bytes),
            SaChunkDelta.stored_count,
            _mib(SaChunkDelta.stored_bytes),
            _mib(SaCardMemory.held()),
            _mib(budget)
        ]
    )


static func _mib(bytes: int) -> float:
    return float(bytes) / float(1 << 20)


## Every snapshot and every kept chunk *document*'s history holds outside its
## tree, each once, the oldest step's first: the snapshots of a pixel step, the
## chunks of a layer a step took out while it is still out, and the chunks a
## whole grid's swap keeps that no layer of the tree holds now. A kept layer
## back in the tree, which an undone delete puts there, is the tree's and is
## never here, because it may be the layer being painted.
static func history_entries(document: SaDocument) -> Array:
    var found: Array = []
    if document == null or document.history == null:
        return found
    var in_tree := _tree_chunk_ids(document)
    var seen: Dictionary[int, bool] = {}
    for held: Array in document.history.holdings():
        _collect(held, document, in_tree, seen, found)
    return found


## Gathers into *found* the snapshots *value* holds, walking the dictionaries
## and lists a step keeps and the layers it took out.
static func _collect(
    value: Variant, document: SaDocument, in_tree: Dictionary[int, bool], seen: Dictionary[int, bool], found: Array
) -> void:
    if value is Dictionary:
        var values: Dictionary = value
        for inner: Variant in values.values():
            _collect(inner, document, in_tree, seen, found)
    elif value is Array:
        var items: Array = value
        for inner: Variant in items:
            _collect(inner, document, in_tree, seen, found)
    elif value is Object and not is_instance_valid(value):
        return
    elif value is SaChunkDelta or value is SaChunk:
        var object: Object = value
        var id := object.get_instance_id()
        if not in_tree.has(id) and not seen.has(id):
            seen[id] = true
            found.append(value)
    elif value is SaLayer:
        var layer: SaLayer = value
        if layer == document.active_layer or layer == document.stroke_layer or document.is_ancestor_of(layer):
            return
        for chunks: Dictionary in _chunk_sets(layer):
            _collect(chunks, document, in_tree, seen, found)
        for child in layer.get_children():
            _collect(child, document, in_tree, seen, found)


## The instance id of every chunk the document's tree holds now, its layers',
## their masks', the own masks' and the stroke buffer's.
static func _tree_chunk_ids(document: SaDocument) -> Dictionary[int, bool]:
    var ids: Dictionary[int, bool] = {}
    var layers: Array[SaLayer] = []
    _gather(document, null, layers)
    if document.stroke_layer != null:
        layers.append(document.stroke_layer)
    var sets: Array[Dictionary] = []
    for layer: SaLayer in layers:
        sets.append_array(_chunk_sets(layer))
    for mask: SaMask in SaCrop.own_masks(document):
        sets.append(mask.chunks)
    for chunks: Dictionary in sets:
        for chunk: Variant in chunks.values():
            var object: Object = chunk
            if object != null:
                ids[object.get_instance_id()] = true
    return ids


## The layers of *document* that may give their chunks up, the least recently
## drawn first: every layer of its tree but the one it paints on.
static func candidates(document: SaDocument) -> Array[SaLayer]:
    var found: Array[SaLayer] = []
    _gather(document, document.active_layer, found)
    found.sort_custom(func(a: SaLayer, b: SaLayer) -> bool: return a.drawn_at < b.drawn_at)
    return found


## Reads *chunk*'s fields back, keeps them compressed in RAM and lets its
## textures go. Answers false for a chunk already in RAM, one with no fields,
## or any chunk while a stroke is held.
static func evict(chunk: SaChunk) -> bool:
    if chunk == null or chunk.is_stored() or stroke_held():
        return false
    if chunk.byte_size() == 0:
        return false
    var kept := _read_back(chunk.fields)
    if kept == null:
        return false
    chunk.store(kept)
    return true


## Reads one history snapshot back to RAM, a whole `SaChunk` or an
## `SaChunkDelta`, and lets its textures go. Answers false for null, for a
## snapshot already in RAM or holding nothing, and while a stroke is held.
static func evict_snapshot(entry: Variant) -> bool:
    if entry is SaChunk:
        var chunk: SaChunk = entry
        return evict(chunk)
    if not entry is SaChunkDelta:
        return false
    var delta: SaChunkDelta = entry
    if delta == null or delta.is_stored() or delta.byte_size() == 0 or stroke_held():
        return false
    var kept := _read_back(delta.fields)
    if kept == null:
        return false
    delta.store(kept)
    return true


## The textures of *fields* read back and compressed, or null when none holds
## a texture on the card.
static func _read_back(fields: Dictionary[StringName, SaTexture]) -> SaChunk.Stored:
    var rd := GlobalShaderCompiler.get_rd()
    if rd == null:
        return null
    var kept: SaChunk.Stored = null
    for field_id: StringName in fields:
        var texture: SaTexture = fields[field_id]
        if texture == null or not texture.rid.is_valid():
            continue
        if kept == null:
            kept = SaChunk.Stored.new(texture.size, SaSadFile.SAD_BLOB_COMPRESS)
        readbacks += 1
        kept.keep(field_id, rd.texture_get_data(texture.rid, 0), texture.format)
    return kept


static func _gather(node: Node, painted: SaLayer, found: Array[SaLayer]) -> void:
    for child in node.get_children():
        var layer := child as SaLayer
        if layer != null and layer != painted:
            found.append(layer)
        _gather(child, painted, found)


static func _chunk_sets(layer: SaLayer) -> Array[Dictionary]:
    var sets: Array[Dictionary] = [layer.chunks]
    if layer.mask != null:
        sets.append(layer.mask.chunks)
    return sets
