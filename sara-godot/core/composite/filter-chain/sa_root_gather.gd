## The canvas gathered for a root record that reads the whole node, kept from
## one composite to the next.
##
## The root stores no chunk, so what a whole-node pass on it reads is the
## composite under it, which the canvas holds only between the compositor
## drawing it and the root's filters rewriting it. The gather is taken there.
##
## **Over every position the composite under the root may show something**,
## and not over the dirty set. Every chunk a layer, the live stroke or the fold
## caches hold, the whole grid when a generated layer draws everywhere, and
## whatever the composite under the root changed this time. The dirty set is
## where the pass writes, as small as the chunks a change lands on, and a pass
## that folds or wraps reads far from where it writes. A gather over a dirty
## set widened to every chunk the root holds would rewrite all of them at every
## composite of a stroke.
##
## Kept, a composite copies again only the positions whose composite under the
## root changed, which [method changed] marks, and composites nothing under the
## root anywhere else, since the pass writes every texel from the gather. Anew,
## after a composite of everything, another document, another format or a set
## of positions that grew, every position is composited and every one written,
## which [method composited] and [method written] answer alike.
##
## Its own file because it is one thing the chain keeps: a texture, what it
## still owes, and the one decision of when it starts anew. The copies are the
## chain's, handed over at construction, so it dispatches nothing of its own.
class_name SaRootGather
extends RefCounted

## The gather, reused across composites.
var whole := SaNeighbourhoodPass.Whole.new()

var _ledger := SaGatherLedger.new()
## Where the composite under the root may have changed this composite, as a set.
var _beneath: Dictionary[Vector2i, bool] = {}
## The positions this composite gathers, grid position -> the canvas, which
## is what [SaGatherLedger] reads a copy from.
var _cells: Dictionary[Vector2i, SaTexture] = {}
## Whether this composite gathers anew, so every position of [member _cells]
## is composited under the root and written by its filters.
var _anew: bool = true
## The chain's copy of a rectangle between two textures and its clear of one.
var _copy: Callable
var _clear: Callable


func _init(copy: Callable, clear: Callable) -> void:
    _copy = copy
    _clear = clear


## Notes where the composite under the root may have changed this composite:
## *beneath*, what the document says, and every position *grown* holds that
## *given*, the document's dirty set, did not, a new record's halo or a
## landing, which a composite of its own redraws.
func changed(
    beneath: Dictionary[Vector2i, bool], given: Dictionary[Vector2i, Rect2i], grown: Dictionary[Vector2i, Rect2i]
) -> void:
    _beneath = beneath.duplicate()
    for grid_pos: Vector2i in grown:
        if not given.has(grid_pos):
            _beneath[grid_pos] = true
    _ledger.mark(_beneath)


## What the compositor composites under a root that reads the whole node, out
## of *dirty*, and whether this composite gathers anew, decided here once.
##
## Anew, *dirty* with every position of the gather added whole, since the
## gather copies whole chunks off the canvas. Kept, *dirty* itself, or when
## *narrow* says the first pass reads the whole node and nothing reads the
## canvas beside it, the positions of *dirty* whose composite changed. Every
## other position of *dirty* still gets its filtered texels, which the pass
## writes from the kept gather and never from what the canvas holds there, so
## compositing the layers under it again would be three dispatches a chunk a
## frame for nothing.
func composited(
    document: SaDocument, canvas: SaTexture, dirty: Dictionary[Vector2i, Rect2i], narrow: bool
) -> Dictionary[Vector2i, Rect2i]:
    _cells = _cells_of(canvas, _under(document))
    _anew = whole.texture == null or whole.texture.format != canvas.format or not _ledger.covers(_cells)
    var out := written(dirty)
    if _anew or not narrow:
        return out
    for grid_pos: Vector2i in out.keys():
        if not _beneath.has(grid_pos):
            out.erase(grid_pos)
    return out


## Where the root's filters write, out of *dirty*: every position of the
## gather added whole when this composite gathers anew, since each of them was
## composited unfiltered, and otherwise *dirty* with every position the gather
## copies again made whole. The gather copies a chunk and not the part a paint
## dirtied, so the composite under it has to cover the chunk, and the canvas
## there is unfiltered until the pass writes all of it. A layer's landing
## makes the root's regions whole anyway, and a wrap's landing, which misses
## the painted chunk, is the one this is for.
func written(dirty: Dictionary[Vector2i, Rect2i]) -> Dictionary[Vector2i, Rect2i]:
    var out := dirty.duplicate()
    for grid_pos: Vector2i in dirty:
        if _beneath.has(grid_pos) and _cells.has(grid_pos):
            out[grid_pos] = SaDocument.WHOLE_CHUNK
    if _anew:
        for grid_pos: Vector2i in _cells:
            out[grid_pos] = SaDocument.WHOLE_CHUNK
    return out


## The canvas over the positions [method composited] chose, into
## [member whole], copying only what the ledger says it owes. Cleared first
## when it owes every position. A texel between two positions reads
## transparent, as the composite holds nothing there.
func gathered(canvas: SaTexture) -> SaNeighbourhoodPass.Whole:
    if _cells.is_empty():
        whole.texture = null
        return whole
    var first: Vector2i = _cells.keys()[0]
    var last: Vector2i = first
    for grid_pos: Vector2i in _cells:
        first = first.min(grid_pos)
        last = last.max(grid_pos)
    var side := Vector2i(SaChunk.SIZE, SaChunk.SIZE)
    var size := (last - first + Vector2i.ONE) * side
    var anew := whole.origin != first * side
    whole.origin = first * side
    if whole.texture == null or whole.texture.format != canvas.format or whole.texture.size != size:
        whole.texture = SaTexture.new(size, canvas.format)
        anew = true
    var owed := _ledger.owed(_cells, anew)
    if owed.size() == _cells.size():
        _clear.call(whole.texture, Rect2i(Vector2i.ZERO, size))
    var chunk := Rect2i(Vector2i.ZERO, side)
    for grid_pos: Vector2i in owed:
        var origin := grid_pos * SaChunk.SIZE
        # The canvas is document-sized and its last row of chunks may end inside
        # the document, so only what it holds of this chunk is copied.
        var held := Rect2i(-origin, canvas.size).intersection(chunk)
        _copy.call(canvas, origin + held.position, whole.texture, Rect2i(origin + held.position - whole.origin, held.size))
    return whole


## Lets the texture go, for a root that no longer carries a record that reads
## the whole node, so it does not sit in VRAM for the rest of the document's
## life.
func let_go() -> void:
    whole.texture = null
    _cells = {}


## Every position the composite under *document*'s root may show something
## at, as a set: what a composite of everything draws, and what changed this
## composite.
func _under(document: SaDocument) -> Dictionary[Vector2i, bool]:
    var found := _beneath.duplicate()
    for layer in SaLayerStack.layers(document):
        for grid_pos: Vector2i in layer.chunks:
            found[grid_pos] = true
    for grid_pos in SaGeneratedLayer.covered_positions(document):
        found[grid_pos] = true
    return found


## The positions of *positions* whose chunk meets *canvas*, each answering the
## canvas, which is what a gather of the root copies from.
static func _cells_of(canvas: SaTexture, positions: Dictionary[Vector2i, bool]) -> Dictionary[Vector2i, SaTexture]:
    var cells: Dictionary[Vector2i, SaTexture] = {}
    var chunk := Rect2i(Vector2i.ZERO, Vector2i(SaChunk.SIZE, SaChunk.SIZE))
    for grid_pos: Vector2i in positions:
        var held := Rect2i(-grid_pos * SaChunk.SIZE, canvas.size).intersection(chunk)
        if held.size.x > 0 and held.size.y > 0:
            cells[grid_pos] = canvas
    return cells
