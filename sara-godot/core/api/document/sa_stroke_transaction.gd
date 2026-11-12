## Tracks the reversible state of one stroke without exposing undo internals to tools.
class_name SaStrokeTransaction
extends RefCounted

## Grid position -> SaChunkDelta (part of a chunk) or null (there was no chunk).
var before_chunks: Dictionary[Vector2i, Variant] = {}

## Grid position -> the union of every region painted there during this stroke.
##
## Accumulated on the CPU as dabs land, and spent once when the snapshot is taken.
## A stroke crossing a chunk touches a band of it, not all of it, so history
## keeps the band rather than the whole 256x256 tile.
var painted_regions: Dictionary[Vector2i, Rect2i] = {}

var direct_paint: bool = false

## The brush is erasing, and what names the step Erase Stroke rather than Brush
## Stroke. Painting straight in, [member direct_paint], is the route of a
## build-up eraser and of a stroke on an alpha-locked layer alike, so it is
## not what tells the two steps apart.
##
## `SaDocument.begin_stroke` sets it when either mode it is handed is ERASE.
## That misses the Erase toggle and a pen's flipped end, which leave the
## brush's own mode as it was, so `SaStrokeNote.commit` sets it again from the
## engine's own answer before the commit reads it.
var erasing: bool = false

## The mask this stroke paints, or null for a stroke on a layer's colour. Set by
## the first dab that lands on it, and what tells the commit whose step the
## snapshot is.
var mask: SaMask = null

## The selection as it stood when the stroke was pressed, which every dab of
## the stroke is clipped by, or null outside a stroke. A walk the frame's
## budget carries goes on painting after the press by up to hundreds of
## frames, and a selection changed or dropped meanwhile would clip only the
## dabs laid before the change, so a long zigzag wash whose later passes run
## on after a door's `select: none` would paint whole rows past the edge.
## Holding it costs two dictionaries and no texture, because a
## change to the selection starts from fresh chunks or copies the chunk it
## writes ([method SaSelection.change]), so the held chunks are never written.
var selection: SaSelectionHeld = null

## The seed the commit's rounding draws from when it stores into a half layer,
## the stroke's own. [method open] draws one off the clock, so
## every stroke has a seed of its own, and a tool that was handed a seed writes
## its stroke's over it once the stroke is open, so a replay commits the same
## bits.
var stroke_seed: int = 0

## How many strokes [method open] has opened, which names the one being
## painted, so what is kept for a stroke (`SaStaleSpread.bearers`) is known
## for another stroke's even when two strokes share a seed.
var opened: int = 0


## Widens the region this stroke has touched in one chunk. Cheap: no GPU work, and
## it is called once per dab.
func note_region(grid_pos: Vector2i, region: Rect2i) -> void:
    if region.size.x <= 0 or region.size.y <= 0:
        return
    if painted_regions.has(grid_pos):
        painted_regions[grid_pos] = (painted_regions[grid_pos] as Rect2i).merge(region)
    else:
        painted_regions[grid_pos] = region


## What the commit shows anew at each of *positions* of *layer*, as grid
## position -> Rect2i in chunk-local pixels: the region the stroke painted there.
##
## The live stroke already drew the band it touched, so the bake changes that
## band and nothing else in the tile. Marking the whole tile instead made a
## stroke on a deep stack redraw several whole chunks under every filter and
## effect after its last dab. A chunk with no region noted, or one kept
## at another pixel size than the grid's, is answered whole, which is the
## honest answer when nobody said where the paint went.
func shown(positions: Array, layer: SaLayer) -> Dictionary[Vector2i, Rect2i]:
    var whole := Rect2i(0, 0, SaChunk.SIZE, SaChunk.SIZE)
    var regions: Dictionary[Vector2i, Rect2i] = {}
    for grid_pos: Vector2i in positions:
        var chunk: SaChunk = layer.chunks.get(grid_pos, null)
        var region: Rect2i = painted_regions.get(grid_pos, whole)
        if chunk != null and chunk.pixel_size() != SaChunk.SIZE:
            region = whole
        regions[grid_pos] = region.intersection(whole) if region.intersects(whole) else whole
    return regions


## Snapshots what the stroke will overwrite in one chunk, over the region noted so
## far.
##
## Called once per chunk for a buffered stroke, at commit, when the layer is still
## untouched. Called per dab when painting straight into the layer, where the
## region grows under it, which is what `grown_to` is for: only the bands that are
## still pristine are read, and the rest comes from what was already saved.
func capture_before(layer: SaLayer, grid_pos: Vector2i) -> void:
    _capture_in(layer.chunks, grid_pos)


## The same snapshot for a stroke on *painted*, taken from whichever store the
## mask keeps: the layer's own chunks for the field form, the mask's for the
## own form. The layer's chunk is captured with every field it holds, over the
## region the stroke painted, the way a direct stroke on its colour is.
func capture_mask_before(painted: SaMask, grid_pos: Vector2i) -> void:
    mask = painted
    direct_paint = true
    if painted.is_own():
        _capture_in(painted.chunks, grid_pos)
    elif is_instance_valid(painted.layer):
        _capture_in(painted.layer.chunks, grid_pos)


func _capture_in(chunks: Dictionary[Vector2i, SaChunk], grid_pos: Vector2i) -> void:
    var chunk: SaChunk = chunks.get(grid_pos, null)
    # No region noted means nobody said where the paint went, and the honest answer
    # is then the whole tile. A caller that skipped note_region gets a whole
    # tile rather than a snapshot with holes.
    var whole := (
        Rect2i(0, 0, SaChunk.SIZE, SaChunk.SIZE)
        if chunk == null
        else Rect2i(Vector2i.ZERO, Vector2i(chunk.pixel_size(), chunk.pixel_size()))
    )
    var region: Rect2i = painted_regions.get(grid_pos, whole)
    if region.size.x <= 0 or region.size.y <= 0:
        region = whole

    if chunk == null:
        # No chunk to save. Recorded so a later dab does not try again, and so undo
        # knows to remove the one the stroke is about to create.
        if not before_chunks.has(grid_pos):
            before_chunks[grid_pos] = null
        return

    var existing: Variant = before_chunks.get(grid_pos, null)
    if existing == null:
        if before_chunks.has(grid_pos):
            return
        before_chunks[grid_pos] = SaChunkDelta.capture(chunk, region)
        return
    var saved: SaChunkDelta = existing
    before_chunks[grid_pos] = saved.grown_to(chunk, region)


## Moves everything this stroke keeps by grid position *by* whole chunks, for a
## grow of the infinite canvas on the left or at the top under the stroke,
## `SaInfiniteCanvas`: the snapshots, the regions painted and the selection
## the stroke was pressed under, whose bounds move by the same pixels.
func moved(by: Vector2i) -> void:
    _move(before_chunks, by)
    _move(painted_regions, by)
    if selection == null:
        return
    _move(selection.chunks, by)
    _move(selection.boxes, by)
    selection.bounds = Rect2i(selection.bounds.position + by * SaChunk.SIZE, selection.bounds.size)


static func _move(keyed: Dictionary, by: Vector2i) -> void:
    var held := keyed.duplicate()
    keyed.clear()
    for grid_pos: Vector2i in held:
        keyed[grid_pos + by] = held[grid_pos]


func mark_direct_paint() -> void:
    direct_paint = true


## Opens a stroke pressed under *pressed_under*, the document's selection,
## which the stroke keeps as [member selection] until its commit.
func open(pressed_under: SaSelection) -> void:
    reset()
    opened += 1
    selection = pressed_under.hold() if pressed_under != null else null
    stroke_seed = SaPenClock.now_usec()


## Takes *handed*, a tool's `ToolState.stroke_seed`, over the clock's seed
## [method open] drew when it is not nought, and gives the stroke's seed folded
## to the 24 bits a kernel's rounding of a store into a half reads. A brush
## whose own random streams start from another seed, as the noise brush's field
## does at Randomness nought for every stroke, rounds from this one
## all the same, so no two strokes repeat one draw.
func take_seed(handed: int) -> int:
    if handed != 0:
        stroke_seed = handed
    return SaStrokeInfo.folded_seed(stroke_seed)


## Lets the pressed selection go as the commit begins, since every dab is laid
## by then, and answers [member mask] for the commit to read. A commit that
## finds nothing to commit never reaches [method reset], and a held selection
## left behind would clip the next context built outside a stroke.
func closing() -> SaMask:
    selection = null
    return mask


func reset() -> void:
    before_chunks.clear()
    painted_regions.clear()
    direct_paint = false
    erasing = false
    mask = null
    selection = null
