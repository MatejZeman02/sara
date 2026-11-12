## The regions of the output the window does not show and nobody has composited
## yet, held until the window reaches them or a reader flushes.
## A region is held after the filter chain grew it, so composited late it needs
## no growing again. Chunk-local pixels by grid position, the shape
## `SaDocument.consume_dirty_chunks` hands over, on the output's grid of
## `SaLayer.CHUNK_SIZE`, since the output is what the window shows.
class_name SaCompositeBacklog
extends RefCounted

## Grid position -> Rect2i in chunk-local pixels, what waits to be composited.
var _regions: Dictionary[Vector2i, Rect2i] = {}


## The document rectangle of the output cell at *grid_pos*.
static func cell(grid_pos: Vector2i) -> Rect2:
    var side := float(SaLayer.CHUNK_SIZE)
    return Rect2(Vector2(grid_pos) * side, Vector2(side, side))


func is_empty() -> bool:
    return _regions.is_empty()


## Moves every region of *regions* whose cell *window* misses in here, the
## test the compositor's walk makes. Nothing is held under an enabled root
## filter, which reads the composite beside what it writes.
func hold_outside(regions: Dictionary[Vector2i, Rect2i], window: Rect2, document: SaDocument) -> void:
    if document != null and SaFilterChain.has_enabled(document.root_filters):
        return
    for grid_pos: Vector2i in regions.keys():
        if not window.intersects(cell(grid_pos)):
            merge(_regions, grid_pos, regions[grid_pos])
            regions.erase(grid_pos)


## Moves the regions of *regions* at *positions* in here, whatever the window
## shows, which is [SaCompositeBudget]'s cut of a set one frame cannot pay
## for. Refused under an enabled root filter, as [method hold_outside] is.
func hold(regions: Dictionary[Vector2i, Rect2i], positions: Array[Vector2i], document: SaDocument) -> void:
    if document != null and SaFilterChain.has_enabled(document.root_filters):
        return
    for grid_pos: Vector2i in positions:
        if regions.has(grid_pos):
            merge(_regions, grid_pos, regions[grid_pos])
            regions.erase(grid_pos)


## Whether *window* reaches any held region's cell.
func reaches(window: Rect2) -> bool:
    return _regions.keys().any(func(grid_pos: Vector2i) -> bool: return window.intersects(cell(grid_pos)))


## Moves every held region whose cell *window* reaches into *regions*.
func take(window: Rect2, regions: Dictionary[Vector2i, Rect2i]) -> void:
    for grid_pos: Vector2i in _regions.keys():
        if window.intersects(cell(grid_pos)):
            merge(regions, grid_pos, _regions[grid_pos])
            _regions.erase(grid_pos)


## Forgets everything, for an output replaced and cleared.
func clear() -> void:
    _regions.clear()


## Merges *region* into what *into* has at *grid_pos*.
static func merge(into: Dictionary[Vector2i, Rect2i], grid_pos: Vector2i, region: Rect2i) -> void:
    into[grid_pos] = (into[grid_pos] as Rect2i).merge(region) if into.has(grid_pos) else region
