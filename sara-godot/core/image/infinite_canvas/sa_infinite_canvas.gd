## The infinite canvas: with its switch on, a document's page grows by whole
## chunks as a stroke nears an edge, so paint never falls past the page and
## every reader of the document, export, the eyedropper, filters and Fit to
## View, keeps working unchanged and covers everything painted.
##
## **Before the dab lands.** The paint context asks [method reach] with the
## regions of a dab before it builds a target, and when they come within one
## chunk of an edge the page grows on that side first. A grow on the right or
## at the bottom adds chunks to the size and moves nothing. A grow on the left
## or at the top moves every layer's, own mask's and the selection's chunks to
## new grid keys by whole chunks, the chunk objects themselves and no copy of a
## texel, and the view keeps the picture where it was on screen, through
## `SaDocument.resize_source` as a crop does.
##
## **The stroke keeps the frame it was pressed in.** A brush holds where its last
## dab was, its stabiliser's queue and the walk's next dab, all in the document
## pixels of the press. Rather than tell every engine that the origin moved,
## [member shift] says how far it moved under the stroke in hand: the tool reads
## the pointer back into the press's frame through [method stroke_point], and
## the paint context lands each region that far over, so an engine never learns
## the page grew.
##
## **One undo.** The grow is not its own step. What each grow did waits in this
## object until the stroke commits, and [method settle] registers the waiting
## grows and the stroke as one step through `SaHistory.as_one`, so one undo
## takes back the stroke and then the growth, and a redo puts the growth back
## before the stroke's pixels. A grow is undone by moving the chunks back by
## grid key and taking away the ground it laid, never by putting a held
## dictionary back, because the stroke's own undo may have put a copy of a chunk
## in the place of the one the grow moved.
##
## **Hard rules 1 and 2.** Nothing is read back. The only dispatches a grow makes
## of its own are the clears of the ground under the chunks it adds, and only
## where a background stores its pixels: a generated ground fills whatever the
## canvas is. The easel's output is made at the new size, as after any Canvas
## Size, and the composite redraws what is allocated.
##
## Only a flat document grows, only under paint, and never through a live
## transform: a stroke on a layer drawn through one would see its map left
## where it was while its chunks moved. Hover, a selection and a filter build
## no stroke, so they never reach the grow.
class_name SaInfiniteCanvas
extends RefCounted

## The `.sad` header's key, written only when the switch is on, so a file from
## before this switch, which has none, opens with it off.
const HEADER_KEY := "infinite_canvas"

## What one grow is called when it is a step alone, which is only when the
## stroke that grew the page left no step of its own, an eraser over nothing.
const ACTION_NAME := "Grow Canvas"

## Whether the page grows under paint. Off in a new document.
var on: bool = false

## How far the document's origin moved under the stroke in hand, in document
## pixels, nought between strokes.
var shift: Vector2i = Vector2i.ZERO

## How many grows this document made, read by the suites and the dump.
var grows: int = 0

## Each grow the stroke in hand made, waiting for its commit.
var _waiting: Array[Dictionary] = []


## The point *point*, in the document's pixels as they are now, in the frame
## the stroke in hand was pressed in, which is what a tool walks in.
static func stroke_point(document: SaDocument, point: Vector2) -> Vector2:
    if document == null or document.infinite_canvas == null:
        return point
    return point - Vector2(document.infinite_canvas.shift)


## The images symmetry makes of *region*, a region in the stroke's frame, in
## that frame. The axes stand in the document's pixels and move with a grow, so
## the region is taken there and back.
static func mirrored(document: SaDocument, region: Rect2) -> Array[Rect2]:
    var moved := Vector2(document.infinite_canvas.shift) if document.infinite_canvas != null else Vector2.ZERO
    var out: Array[Rect2] = []
    for image: Rect2 in document.symmetry.regions(Rect2(region.position + moved, region.size)):
        out.append(Rect2(image.position - moved, image.size))
    return out


## Grows *document*'s page so every one of *regions*, in the stroke's frame, is
## more than one chunk inside each edge, when the switch is on and a stroke is
## being painted. Answers how many whole chunks the origin moved, right and
## down, which is nought unless the page grew on the left or at the top.
static func reach(document: SaDocument, regions: Array[Rect2]) -> Vector2i:
    if document == null or document.infinite_canvas == null or regions.is_empty():
        return Vector2i.ZERO
    return document.infinite_canvas._reach(document, regions)


## Commits the stroke in hand through *bake*, `SaDocument`'s own commit, as one
## step with every grow it made. A stroke that grew nothing commits as any stroke does.
static func settle(document: SaDocument, bake: Callable) -> void:
    if document.infinite_canvas == null:
        bake.call()
        return
    document.infinite_canvas._settle(document, bake)


func _settle(document: SaDocument, bake: Callable) -> void:
    var waiting := _waiting
    _waiting = []
    shift = Vector2i.ZERO
    if waiting.is_empty() or document.history == null:
        bake.call()
        return
    var history := document.history
    var work := func() -> void:
        for state: Dictionary in waiting:
            history.commit(ACTION_NAME, _exchange.bind(document, state), {}, _ground_bytes(state), [state])
        bake.call()
    history.as_one(_stroke_name(document), work)


## Writes the switch into a `.sad` *header*, and nothing while it is off.
static func write_header(document: SaDocument, header: Dictionary) -> void:
    if document.infinite_canvas != null and document.infinite_canvas.on:
        header[HEADER_KEY] = true


## Reads the switch off a `.sad` *header*. Absent is off, which is what every
## file before the switch means.
static func read_header(document: SaDocument, header: Dictionary) -> void:
    document.infinite_canvas.on = header.get(HEADER_KEY, false) == true


## Turns *document*'s switch to *wanted*, and turning it on stops a flat
## document's wrap, because a wrap needs a fixed page. True when that
## stopped a wrap, for the caller to say so. Marks the document changed when
## the switch moved, since the `.sad` keeps it.
static func turn(document: SaDocument, wanted: bool) -> bool:
    if document == null or document.infinite_canvas == null:
        return false
    var stopped := false
    if wanted and document.projection.kind.id == SaProjection.FLAT and document.projection.wrapping != SaProjection.Wrap.NONE:
        SaProjection.wrap_flat(document, SaProjection.Wrap.NONE)
        stopped = true
    if document.infinite_canvas.on != wanted:
        document.infinite_canvas.on = wanted
        document.modified = true
    return stopped


## The step a stroke leaves, by the names `SaDocument` gives it.
static func _stroke_name(document: SaDocument) -> String:
    if document.stroke_transaction.mask != null:
        return "Mask Stroke"
    return "Erase Stroke" if document.stroke_transaction.erasing else "Brush Stroke"


func _reach(document: SaDocument, regions: Array[Rect2]) -> Vector2i:
    if not on or not _grows_here(document):
        return Vector2i.ZERO
    var edge := SaLayer.CHUNK_SIZE
    var reached := regions[0]
    for region: Rect2 in regions:
        reached = reached.merge(region)
    reached.position += Vector2(shift)
    var size := Vector2(document.canvas_size)
    var before := Vector2i(_cells(edge - reached.position.x, edge), _cells(edge - reached.position.y, edge))
    var after := Vector2i(_cells(reached.end.x - (size.x - edge), edge), _cells(reached.end.y - (size.y - edge), edge))
    if before == Vector2i.ZERO and after == Vector2i.ZERO:
        return Vector2i.ZERO
    _grow(document, before, after)
    return before


## Whether a dab on *document* now may grow it: a stroke is open, it paints the
## picture rather than the quick mask's selection, the document is flat, and
## the active layer is not drawn through a live transform.
static func _grows_here(document: SaDocument) -> bool:
    if document.stroke_transaction == null or document.stroke_transaction.selection == null:
        return false
    if document.selection.editing:
        return false
    if document.projection.kind.id != SaProjection.FLAT or document.projection.wrapping != SaProjection.Wrap.NONE:
        return false
    return document.active_layer != null and SaLocalView.map_of(document.active_layer) == null


## The whole chunks of *edge* pixels that cover *over* pixels, nought for none.
static func _cells(over: float, edge: int) -> int:
    return ceili(over / float(edge)) if over > 0.0 else 0


## Adds *before* chunks on the left and at the top and *after* on the right and
## at the bottom, and keeps what it did for the stroke's step.
func _grow(document: SaDocument, before: Vector2i, after: Vector2i) -> void:
    var edge := SaLayer.CHUNK_SIZE
    var was := document.canvas_size
    var size := was + (before + after) * edge
    # Found on the page as it stands, since it is the layer that covers it.
    var carrier := _ground_carrier(document)
    _move_all(document, before)
    var laid: Array[Vector2i] = []
    if carrier != null:
        var fill := document.background_fill()
        for grid_pos: Vector2i in SaLayer.grid_positions(size):
            if carrier.chunks.get(grid_pos, null) == null:
                carrier.get_or_create_chunk(grid_pos).clear(fill)
                laid.append(grid_pos)
    _show(document, size, Rect2i(-before * edge, size), before * edge)
    shift += before * edge
    grows += 1
    _waiting.append({"size": was, "move": before, "grown": true, "carrier": carrier, "laid": laid, "ground": {}})


## The undo and the redo of one grow, each the other's inverse, run from
## whichever side the document stands on: undone, the ground it laid comes off
## and the chunks move back, redone, the chunks move over and the ground goes
## back where it was laid.
func _exchange(document: SaDocument, state: Dictionary) -> void:
    var edge := SaLayer.CHUNK_SIZE
    var move: Vector2i = state["move"]
    var size: Vector2i = state["size"]
    var carrier: SaLayer = state["carrier"] if is_instance_valid(state["carrier"]) else null
    var ground: Dictionary = state["ground"]
    var was := document.canvas_size
    if state["grown"]:
        if carrier != null:
            for grid_pos: Vector2i in state["laid"]:
                ground[grid_pos] = carrier.chunks.get(grid_pos, null)
                carrier.chunks.erase(grid_pos)
        _move_all(document, -move)
        _show(document, size, Rect2i(move * edge, size), -move * edge)
    else:
        _move_all(document, move)
        if carrier != null:
            for grid_pos: Vector2i in ground:
                if ground[grid_pos] != null:
                    carrier.chunks[grid_pos] = ground[grid_pos]
        _show(document, size, Rect2i(-move * edge, size), move * edge)
    state["size"] = was
    state["grown"] = not state["grown"]


## Moves every chunk *document* keeps by grid key, *by* whole chunks: each
## layer's, the stroke buffer's, each own mask's, the selection's and the open
## stroke's record of them. Users of one shared source hold one dictionary,
## which moves once.
static func _move_all(document: SaDocument, by: Vector2i) -> void:
    if by == Vector2i.ZERO:
        return
    var moved: Array[Dictionary] = []
    for layer: SaLayer in _stores(document):
        if moved.any(func(done: Dictionary) -> bool: return is_same(done, layer.chunks)):
            continue
        _move_keys(layer.chunks, by)
        moved.append(layer.chunks)
    var masks: Dictionary[Variant, Dictionary] = {}
    for mask: SaMask in SaCrop.own_masks(document):
        masks[mask] = _moved(mask.chunks, by)
    SaCrop.put_masks(document, masks)
    var selection := document.selection
    if selection.active:
        var bounds := Rect2i(selection.bounds.position + by * SaLayer.CHUNK_SIZE, selection.bounds.size)
        SaSelection.Swap.new(selection, _moved(selection.chunks, by), bounds).exchange()
    document.stroke_transaction.moved(by)


## Puts *size* on *document*, keeping the side a brush is read against, the
## symmetry axes *moved* pixels over with the picture, and tells every reader
## of the page, the view by *source* as `SaCrop` tells it.
static func _show(document: SaDocument, size: Vector2i, source: Rect2i, moved: Vector2i) -> void:
    var side := document.brush_side
    var centre := document.symmetry.center
    document.canvas_size = size
    document.brush_side = side
    document.symmetry.center = centre + Vector2(moved)
    for layer: SaLayer in _stores(document):
        layer.mark_all_unresolved()
    document.modified = true
    document.update_caches()
    document.invalidate_all_allocated_chunks()
    document.resize_source = source
    EventBus.document_resized.emit(document, size)
    document.resize_source = Rect2i()
    document.document_changed.emit()


## Every layer of *document* that keeps chunks, the stroke buffer with them.
static func _stores(document: SaDocument) -> Array[SaLayer]:
    var found: Array[SaLayer] = []
    _collect(document, found)
    # The buffer is not a child of the document, and it holds every dab the
    # stroke laid before the grow.
    if document.stroke_layer != null:
        found.append(document.stroke_layer)
    return found


static func _collect(from: Node, into: Array[SaLayer]) -> void:
    for child: Node in from.get_children():
        var layer := child as SaLayer
        if layer == null:
            continue
        into.append(layer)
        _collect(layer, into)


## The layer the ground of a grow is laid into, `SaCrop`'s rule: the bottom
## top-level layer when it stores its texels and holds a chunk everywhere the
## page is, which is a background that stores its pixels. Null for a generated
## ground, which fills any page by itself, and for a painting.
static func _ground_carrier(document: SaDocument) -> SaLayer:
    for child: Node in document.get_children():
        var layer := child as SaLayer
        if layer == null or layer == document.stroke_layer:
            continue
        if layer.is_generated():
            return null
        for grid_pos: Vector2i in SaLayer.grid_positions(document.canvas_size):
            if layer.chunks.get(grid_pos, null) == null:
                return null
        return layer
    return null


## Moves every key of *chunks* by *by*, in place, so a typed dictionary and
## every holder of it see the move.
static func _move_keys(chunks: Dictionary, by: Vector2i) -> void:
    var moved := _moved(chunks, by)
    chunks.clear()
    for grid_pos: Vector2i in moved:
        chunks[grid_pos] = moved[grid_pos]


## A copy of *chunks* with every key moved by *by*.
static func _moved(chunks: Dictionary, by: Vector2i) -> Dictionary:
    var out := {}
    for grid_pos: Vector2i in chunks:
        out[grid_pos + by] = chunks[grid_pos]
    return out


## What the ground one grow laid holds, in bytes of VRAM.
static func _ground_bytes(state: Dictionary) -> int:
    var carrier: SaLayer = state["carrier"] if is_instance_valid(state["carrier"]) else null
    if carrier == null:
        return 0
    var total := 0
    for grid_pos: Vector2i in state["laid"]:
        var chunk: SaChunk = carrier.chunks.get(grid_pos, null)
        if chunk != null:
            total += chunk.byte_size()
    return total
