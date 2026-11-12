## How much of the graphics card Sara keeps the open documents to, and what
## each of them holds against it.
##
## The budget is read from the card's reported memory, a fraction of it, with
## a Preferences row to lower it, so a painter sharing the card with Blender
## can. It is `SaSettings.card_memory_share` of `SaCardMemory.total()`, six
## tenths in a fresh profile, for the reason `card_memory_share` gives. It
## stands below the card's limit, the card less `SaCardMemory.margin`, so that
## eviction can move layers out of the card before a document is refused: on a
## card small enough that six tenths would reach past three quarters of that
## limit, three quarters of it is the budget. A card that reads as 0 has no
## budget, as `SaCardMemory` sets no limit there.
##
## **The accounting** is per document, in two parts. The resident bytes are
## every chunk of every layer of the document's tree, its masks and its
## stroke buffer, each chunk the sum of its own fields, `SaChunk.byte_size`.
## The history bytes are what the history holds on the card now, every
## snapshot and kept chunk `SaResidency.history_entries` finds outside the
## tree, so a snapshot in RAM counts as 0 and a kept layer back in the tree is
## counted once, with the tree. The history's own limits keep reading what each
## step was charged, `SaHistory.total_bytes`. Both are sums over what the
## document already keeps on the CPU, so a reading costs a walk of
## dictionaries and never touches the canvas, which is what lets eviction read
## it before every eviction.
class_name SaMemoryBudget
extends RefCounted

## When a small card's share is cut, the share of the card's limit it is cut
## to.
const LIMIT_SHARE := 0.75


## The budget in bytes for a card of *card* bytes, `SaCardMemory.total()` when
## left at -1, or 0 when the card's memory is not known.
static func budget(card: int = -1) -> int:
    if card < 0:
        card = SaCardMemory.total()
    if card <= 0:
        return 0
    var share := roundi(float(card) * SaSettings.card_memory_share)
    var limit := card - SaCardMemory.margin(card)
    if limit > 0:
        share = mini(share, roundi(float(limit) * LIMIT_SHARE))
    return share


## What the chunks of *document*'s layers hold in VRAM now.
static func resident_bytes(document: SaDocument) -> int:
    if document == null:
        return 0
    var total := _tree_bytes(document)
    if document.stroke_layer != null and document.stroke_layer.get_parent() == null:
        total += layer_bytes(document.stroke_layer)
    return total


## What *document*'s undo history holds in VRAM now, a snapshot in RAM
## counted as 0.
static func history_bytes(document: SaDocument) -> int:
    var total := 0
    for entry: Variant in SaResidency.history_entries(document):
        if entry is SaChunk:
            var chunk: SaChunk = entry
            total += chunk.byte_size()
        elif entry is SaChunkDelta:
            var delta: SaChunkDelta = entry
            total += delta.byte_size()
    return total


## What *document* holds against the budget, its layers and its history.
static func document_bytes(document: SaDocument) -> int:
    return resident_bytes(document) + history_bytes(document)


## What every document *documents* holds open holds against the budget.
static func used(documents: SaDocuments) -> int:
    var total := 0
    if documents == null:
        return total
    for surface in documents.surfaces:
        total += document_bytes(SaSurface.document_of(surface))
    return total


## What one layer's chunks and its mask's chunks hold.
static func layer_bytes(layer: SaLayer) -> int:
    var total := _chunks_bytes(layer.chunks)
    if layer.mask != null:
        total += _chunks_bytes(layer.mask.chunks)
    return total


static func _tree_bytes(node: Node) -> int:
    var total := 0
    for child in node.get_children():
        var layer := child as SaLayer
        if layer != null:
            total += layer_bytes(layer)
        total += _tree_bytes(child)
    return total


static func _chunks_bytes(chunks: Dictionary[Vector2i, SaChunk]) -> int:
    var total := 0
    for chunk: SaChunk in chunks.values():
        if chunk != null:
            total += chunk.byte_size()
    return total
