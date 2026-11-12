## What an adjustment layer drawn over the canvas showed, kept per chunk, so a
## change below a stack of blurs runs each blur again over what moved under it
## and the blur's reach, and the walk takes the rest from here.
##
## Without it a stack of blur layers would run every blur again over the
## walk's set grown by twice their summed reach. Each step of [member steps] is one adjustment
## layer the walk draws over the canvas whose records read their neighbours.
## Its chunks hold the canvas as the walk left it after the layer, the layer's
## output over everything below it, and they are allocated where a layer below
## holds paint and the window reaches every chunk the layer's output there is
## read from, nowhere else (hard rule 3). Nothing leaves VRAM (hard rule 1).
##
## [method plan] reads the walk in hand before the canvas is cleared:
##
## 1. forward, what moved below each step: the dirty set grown by the summed
##    reach of the step and every step under it, since a blur spreads a change
##    by its reach and the one above it spreads that again,
## 2. drops a chunk the window no longer reaches, or where nothing below holds
##    paint any more,
## 3. backward from the dirty set, what each step has to show: a held chunk
##    runs the layer again over what moved below it and copies the rest out of
##    the cache, a chunk not held yet runs whole and is kept, and a chunk that
##    cannot be kept runs over what is asked of it, as without the cache. What
##    a step runs, grown by its reach, is what the step under it has to show.
##
## The walk draws the union of those sets, so a stroke below the stack costs
## each layer the stroke's region grown by the reach up to it (hard rule 2).
##
## A region the document marked dirty names the layer it moved at,
## [member SaDocument.moved_at], and counts only for the steps above that
## layer, the layer itself and those inside it, grown by their reach alone, so
## the steps under a change keep their chunks. A region that names no layer,
## one the walk took from elsewhere and a full composite's, counts as below
## every step, the conservative answer `SaEffectLayer.refresh` gives as well. A
## change that rebuilds the fold, another layer made active or an undo of the
## layers' order, comes with the whole canvas dirty and no name, and so runs
## every step again wherever it keeps a chunk.
class_name SaAdjustmentCache
extends RefCounted

## Layer instance id -> the step the walk in hand takes for that layer, every
## layer of the plan, empty when nothing is cached.
var steps: Dictionary[int, Step] = {}
## The set the walk draws, grid position -> Rect2i in chunk-local pixels, cut
## to the canvas, when [method plan] answered true.
var walked: Dictionary[Vector2i, Rect2i] = {}
## Whether the cache is used at all, false for a suite's reference walk.
var _on: bool = true
## Layer instance id -> the layer's output over the canvas, a chunk at each
## position it is kept at.
var _held: Dictionary[int, SaFilterHalo] = {}
## The document and the canvas the chunks were kept for. Another document or
## another canvas drops them all.
var _document: int = 0
var _canvas: SaTexture = null


func _init(on: bool = true) -> void:
    _on = on


## Plans the walk of *document* over *canvas* through *compositor*, for
## *inner*, the regions the walk answers for, and *visible*, the window it
## draws. Answers whether any step is cached, and then [member walked] is the
## set the walk draws and [member steps] what each layer does in it. Nothing
## is kept and every chunk is dropped when it answers false. *named* says
## *inner* went through the document, so [member SaDocument.moved_at] names
## the layer each of its regions moved at.
func plan(
    compositor: SaCompositor,
    document: SaDocument,
    canvas: SaTexture,
    inner: Dictionary[Vector2i, Rect2i],
    visible: Rect2,
    named: bool = false
) -> bool:
    var before := steps
    steps = {}
    walked = {}
    var order: Array[Step] = []
    if _on and canvas != null:
        order = _order(compositor, document)
    if order.is_empty():
        _drop()
        return false
    if document.get_instance_id() != _document or canvas != _canvas:
        _drop()
    _document = document.get_instance_id()
    _canvas = canvas
    var size := canvas.size
    var kept: Dictionary[int, SaFilterHalo] = {}
    var dirty := cut(inner, size)
    var records := _records(document, dirty, named)
    # Each record's reach so far, summed over the steps it counted for.
    var summed: Array[int] = []
    summed.resize(records.size())
    var below: Array[Dictionary] = []
    var spread := 0
    for step: Step in order:
        var id := step.layer.get_instance_id()
        spread += step.reach
        kept[id] = _held.get(id, SaFilterHalo.new())
        step.open(kept[id], spread, visible, size, before[id] if before.has(id) else null)
        # Grown from each record by its whole reach at once, not from the
        # step below by this reach: each growth merges a chunk's pieces into
        # the rectangle around them, and growing that again would spread a
        # stroke's set wider at every layer of the stack.
        var moved: Dictionary[Vector2i, Rect2i] = {}
        for r in records.size():
            var record: Array = records[r]
            var at: SaLayer = record[0]
            if _counts(step.layer, at):
                summed[r] += step.reach
                var regions: Dictionary[Vector2i, Rect2i] = record[1]
                moved = merged(moved, grown(regions, summed[r], size))
        below.append(moved)
    _held = kept
    var needed := cut(inner, size)
    walked = merged(inner, needed)
    for i in range(order.size() - 1, -1, -1):
        var step: Step = order[i]
        needed = step.settle(needed, below[i], size)
        walked = merged(walked, needed)
        steps[step.layer.get_instance_id()] = step
    return true


## The regions of *dirty* by the layer they moved at, each record a pair of the
## layer and its regions, the layer null for what names none. Every region
## names none unless *named*, and a position counts as named only where the
## regions [member SaDocument.moved_at] names there at layers of *document*
## enclose its dirty region, since one the walk took from elsewhere, a halo's,
## a backlog's or a live transform's, names nothing.
static func _records(document: SaDocument, dirty: Dictionary[Vector2i, Rect2i], named: bool) -> Array:
    var records: Array = []
    if not named:
        records.append([null, dirty])
        return records
    var layers: Dictionary[int, SaLayer] = {}
    var enclosing: Dictionary[Vector2i, Rect2i] = {}
    for id: int in document.moved_at:
        var layer := instance_from_id(id) as SaLayer
        if layer != null and layer.get_parent() == document:
            layers[id] = layer
            enclosing = merged(enclosing, SaTyped.regions(document.moved_at[id]))
    var unnamed: Dictionary[Vector2i, Rect2i] = {}
    for grid_pos: Vector2i in dirty:
        if not enclosing.has(grid_pos) or not enclosing[grid_pos].encloses(dirty[grid_pos]):
            unnamed[grid_pos] = dirty[grid_pos]
    for id: int in layers:
        var regions: Dictionary[Vector2i, Rect2i] = {}
        var moved := SaTyped.regions(document.moved_at[id])
        for grid_pos: Vector2i in moved:
            if dirty.has(grid_pos) and not unnamed.has(grid_pos):
                var region := moved[grid_pos].intersection(dirty[grid_pos])
                if region.has_area():
                    regions[grid_pos] = region
        records.append([layers[id], regions])
    records.append([null, unnamed])
    return records


## Whether a change at *at* moves what the step of *layer* shows: *at* names
## no layer, or is under *layer*, *layer* itself or a group that holds it, or
## *layer* is one `SaBackdropLayer` lifts over the whole picture.
static func _counts(layer: SaLayer, at: SaLayer) -> bool:
    # A lifted layer runs over the whole picture, so every change is under it.
    if at == null or layer.get_parent() != at.get_parent() or SaBackdropLayer.lifts(layer):
        return true
    return layer.get_index() > at.get_index() or SaLayerStack.is_inside(layer, at)


## Bytes the kept chunks hold in VRAM, for the Done paragraph's figure.
func held_bytes() -> int:
    var total := 0
    for store: SaFilterHalo in _held.values():
        for grid_pos: Vector2i in store.positions():
            var chunk := store.layer.get_field(grid_pos)
            total += chunk.bytes if chunk != null else 0
    return total


## *regions* grown by *reach*, kept to a canvas of *size*. A reach past a chunk
## grows a chunk at a time, since [method SaNeighbourhoodPass.grown] spills
## into the ring around a chunk and no further.
static func grown(regions: Dictionary[Vector2i, Rect2i], reach: int, size: Vector2i) -> Dictionary[Vector2i, Rect2i]:
    var out := regions
    var left := reach
    while left > 0:
        out = SaNeighbourhoodPass.grown(out, mini(left, SaLayer.CHUNK_SIZE))
        left -= SaLayer.CHUNK_SIZE
    return cut(out, size)


## *regions* inside a canvas of *size*, an empty region left out.
static func cut(regions: Dictionary[Vector2i, Rect2i], size: Vector2i) -> Dictionary[Vector2i, Rect2i]:
    var out: Dictionary[Vector2i, Rect2i] = {}
    for grid_pos: Vector2i in regions:
        var region := (regions[grid_pos] as Rect2i).intersection(Rect2i(-grid_pos * SaLayer.CHUNK_SIZE, size))
        if region.has_area():
            out[grid_pos] = region
    return out


## *into* with *more* added, each position's two rectangles merged into the
## one around both. Neither is changed.
static func merged(into: Dictionary[Vector2i, Rect2i], more: Dictionary[Vector2i, Rect2i]) -> Dictionary[Vector2i, Rect2i]:
    var out: Dictionary[Vector2i, Rect2i] = into.duplicate()
    for grid_pos: Vector2i in more:
        out[grid_pos] = out[grid_pos].merge(more[grid_pos]) if out.has(grid_pos) else more[grid_pos]
    return out


## The steps the walk takes over the canvas of *document* in its order, the
## stack below the active layer, the active layer, the stack above, for every
## adjustment layer it draws there whose records read their neighbours. The
## active layer counts only where `SaCompositeWalk` draws it as a tier of its
## own, and a step the walk does not take is never planned, since its chunks
## would answer for a canvas nobody drew.
static func _order(compositor: SaCompositor, document: SaDocument) -> Array[Step]:
    var found: Array[Step] = []
    if document == null or document.fold == null:
        return found
    var layers: Array[SaLayer] = []
    for entry: Dictionary in document.fold.bottom_stack:
        layers.append(SaLayerStack.layer_of(entry))
    var active := document.active_layer
    if active != null and active.is_adjustment() and document.fold.active_scopes.is_empty():
        if SaLayerStack.shows(document, active):
            layers.append(active)
    for entry: Dictionary in document.fold.top_stack:
        layers.append(SaLayerStack.layer_of(entry))
    for layer in layers:
        if layer.is_adjustment() and layer.visible:
            var reach := compositor.filter_chain.reach_of(layer)
            if reach > 0:
                found.append(Step.new(layer, reach, SaBackdropLayer.drawn_over(document, layer)))
    return found


func _drop() -> void:
    for store: SaFilterHalo in _held.values():
        store.drop()
    _held = {}


func _notification(what: int) -> void:
    if what == NOTIFICATION_PREDELETE:
        # Each kept layer is freed by its own halo going.
        _held.clear()
        _canvas = null


## One adjustment layer's step in the walk in hand: what it runs, what it
## shows, and the chunks it keeps.
class Step:
    extends RefCounted

    var layer: SaLayer = null
    ## How far the layer's records read past a texel, in document pixels.
    var reach: int = 0
    ## The summed reach of this step and every step under it, how far the
    ## layer's output at a texel reads the canvas below the whole stack.
    var spread: int = 0
    ## Grid positions, read as a set, where a layer below holds paint.
    var paint: Dictionary[Vector2i, bool] = {}
    ## Where the step runs the layer, each region kept after it where the step
    ## keeps a chunk.
    var runs: Dictionary[Vector2i, Rect2i] = {}
    ## Where the canvas after the step has to hold the layer's output.
    var shows: Dictionary[Vector2i, Rect2i] = {}
    ## Where the canvas before the step has to hold its backdrop, [member runs]
    ## grown by the reach, which the layer's halo is filled over.
    var reads: Dictionary[Vector2i, Rect2i] = {}
    ## The layer's kept chunks.
    var store: SaFilterHalo = null
    ## Grid positions, read as a set, where the step makes a chunk it keeps.
    var fresh: Dictionary[Vector2i, bool] = {}
    var _visible := Rect2()
    var _grid := Rect2i()

    func _init(adjusting: SaLayer, layer_reach: int, drawn: Array[Vector2i]) -> void:
        layer = adjusting
        reach = layer_reach
        for grid_pos in drawn:
            paint[grid_pos] = true

    ## Takes *kept* as the layer's chunks, *summed* as [member spread], and
    ## drops every chunk it holds that [method keeps] no longer answers for in
    ## *visible* over a canvas of *size*. Nothing is asked when *before*, the
    ## layer's step in the last plan, kept the same chunks under the same
    ## window, spread, canvas and paint, since every chunk held then passed
    ## [method keeps] or was made where it did: a stroke under a still view
    ## then pays nothing here, where asking every chunk of a deep stack would
    ## cost a share of every composite.
    func open(kept: SaFilterHalo, summed: int, visible: Rect2, size: Vector2i, before: Step = null) -> void:
        store = kept
        spread = summed
        _visible = visible
        _grid = Rect2i(Vector2i.ZERO, Vector2i((Vector2(size) / float(SaLayer.CHUNK_SIZE)).ceil()))
        if before != null and before.store == kept and before.spread == spread:
            if before._visible == _visible and before._grid == _grid and before.paint == paint:
                return
        var held: Dictionary[Vector2i, bool] = {}
        for grid_pos: Vector2i in store.positions():
            if keeps(grid_pos):
                held[grid_pos] = true
        store.only(held)

    ## Plans the step for *needed*, where the canvas after it has to hold the
    ## layer's output, and *moved*, where what is below it may have changed, on
    ## a canvas of *size*, and answers where the canvas before it has to hold
    ## the backdrop.
    func settle(
        needed: Dictionary[Vector2i, Rect2i], moved: Dictionary[Vector2i, Rect2i], size: Vector2i
    ) -> Dictionary[Vector2i, Rect2i]:
        shows = needed
        runs = {}
        fresh = {}
        for grid_pos: Vector2i in store.positions():
            if moved.has(grid_pos):
                runs[grid_pos] = moved[grid_pos]
        for grid_pos: Vector2i in needed:
            if store.layer != null and store.layer.get_field(grid_pos) != null:
                continue
            if keeps(grid_pos):
                runs[grid_pos] = SaDocument.WHOLE_CHUNK.intersection(Rect2i(-grid_pos * SaLayer.CHUNK_SIZE, size))
                fresh[grid_pos] = true
            else:
                runs[grid_pos] = needed[grid_pos]
        reads = SaAdjustmentCache.grown(runs, reach, size)
        return reads

    ## Whether the step keeps a chunk at *grid_pos*: a layer below holds paint
    ## there, and the window reaches every chunk of the canvas within
    ## [member spread] of it, so every texel its output there reads is drawn.
    func keeps(grid_pos: Vector2i) -> bool:
        if not paint.has(grid_pos) or not _grid.has_point(grid_pos):
            return false
        var side := SaLayer.CHUNK_SIZE
        var area := Rect2i(grid_pos * side, Vector2i(side, side)).grow(spread)
        var first := Vector2i(floori(area.position.x / float(side)), floori(area.position.y / float(side)))
        var last := Vector2i(floori((area.end.x - 1) / float(side)), floori((area.end.y - 1) / float(side)))
        for y in range(maxi(first.y, _grid.position.y), mini(last.y, _grid.end.y - 1) + 1):
            for x in range(maxi(first.x, _grid.position.x), mini(last.x, _grid.end.x - 1) + 1):
                if not _visible.intersects(Rect2(Vector2(x, y) * side, Vector2(side, side))):
                    return false
        return true

    ## The chunk the step keeps at *grid_pos* at *format*, made when the step
    ## keeps one there from this walk on, or null where it keeps none.
    func chunk(grid_pos: Vector2i, format: int) -> SaTexture:
        var held := store.layer.get_field(grid_pos) if store.layer != null else null
        if held != null or not fresh.has(grid_pos):
            return held
        return store.take(grid_pos, format)
